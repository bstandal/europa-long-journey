import ContentKit
import CryptoKit
import Foundation

/// The content-authoritative completion contract for one exact beat.
///
/// JourneyContent issues this value from an already validated repository. The
/// public UI can carry the resulting `JourneyAction`, but it has no initializer
/// with which to substitute another beat, content version or world effect set.
/// The complete value is journalled so replay re-establishes the same causal
/// boundary without consulting mutable UI state.
public struct BeatCompletionContract: Codable, Equatable, Sendable {
    enum Mode: Codable, Equatable, Sendable {
        case documentary(effects: [WorldEffect])
        case interaction(id: InteractionID, effects: [WorldEffect])
    }

    let packageID: PackageID
    let contentVersion: SchemaVersion
    let chapterID: ChapterID
    let arcID: ArcID
    let beatID: BeatID
    let arcIndex: Int
    let beatIndex: Int
    let absoluteBeatIndex: Int
    let mode: Mode
    private let authoritySeal: Data

    @_spi(JourneyContent)
    public init(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapterID: ChapterID,
        arcID: ArcID,
        arcIndex: Int,
        beatIndex: Int,
        absoluteBeatIndex: Int,
        beat: BeatSpec
    ) throws {
        try beat.validate()
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.chapterID = chapterID
        self.arcID = arcID
        beatID = beat.id
        self.arcIndex = arcIndex
        self.beatIndex = beatIndex
        self.absoluteBeatIndex = absoluteBeatIndex
        let completionMode: Mode
        if let interaction = beat.interaction {
            completionMode = .interaction(
                id: interaction.id,
                effects: interaction.completionEffects
            )
        } else {
            completionMode = .documentary(effects: beat.completionEffects)
        }
        mode = completionMode
        guard let seal = Self.makeAuthoritySeal(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapterID,
            arcID: arcID,
            beatID: beat.id,
            arcIndex: arcIndex,
            beatIndex: beatIndex,
            absoluteBeatIndex: absoluteBeatIndex,
            mode: completionMode
        ) else {
            throw BeatCompletionContractError.sealingFailed
        }
        authoritySeal = seal
        guard isStructurallyValid else {
            throw BeatCompletionContractError.invalidStructure
        }
    }

    init(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapterID: ChapterID,
        arcID: ArcID,
        beatID: BeatID,
        arcIndex: Int,
        beatIndex: Int,
        absoluteBeatIndex: Int,
        mode: Mode
    ) {
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.chapterID = chapterID
        self.arcID = arcID
        self.beatID = beatID
        self.arcIndex = arcIndex
        self.beatIndex = beatIndex
        self.absoluteBeatIndex = absoluteBeatIndex
        self.mode = mode
        authoritySeal = Self.makeAuthoritySeal(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapterID,
            arcID: arcID,
            beatID: beatID,
            arcIndex: arcIndex,
            beatIndex: beatIndex,
            absoluteBeatIndex: absoluteBeatIndex,
            mode: mode
        ) ?? Data()
    }

    var isStructurallyValid: Bool {
        packageID.isNonempty
            && chapterID.isNonempty
            && arcID.isNonempty
            && beatID.isNonempty
            && contentVersion.isValid
            && arcIndex >= 0
            && beatIndex >= 0
            && absoluteBeatIndex >= 0
            && effectsHaveUniqueNonemptyIDs
            && authoritySeal == Self.makeAuthoritySeal(
                packageID: packageID,
                contentVersion: contentVersion,
                chapterID: chapterID,
                arcID: arcID,
                beatID: beatID,
                arcIndex: arcIndex,
                beatIndex: beatIndex,
                absoluteBeatIndex: absoluteBeatIndex,
                mode: mode
            )
    }

    var effects: [WorldEffect] {
        switch mode {
        case let .documentary(effects), let .interaction(_, effects):
            effects
        }
    }

    var documentaryEffects: [WorldEffect]? {
        guard case let .documentary(effects) = mode else { return nil }
        return effects
    }

    var interactionIdentity: (id: InteractionID, effects: [WorldEffect])? {
        guard case let .interaction(id, effects) = mode else { return nil }
        return (id, effects)
    }

    func matches(session: ChapterSession) -> Bool {
        isStructurallyValid
            && packageID == session.packageID
            && contentVersion == session.contentVersion
            && chapterID == session.chapterID
            && arcID == session.arcID
            && beatID == session.beatID
    }

    private var effectsHaveUniqueNonemptyIDs: Bool {
        let ids = effects.map(\.id)
        return ids.allSatisfy(\.isNonempty) && Set(ids).count == ids.count
    }

    private struct SealMaterial: Encodable {
        let packageID: PackageID
        let contentVersion: SchemaVersion
        let chapterID: ChapterID
        let arcID: ArcID
        let beatID: BeatID
        let arcIndex: Int
        let beatIndex: Int
        let absoluteBeatIndex: Int
        let mode: Mode
    }

    private static let authorityKey = SymmetricKey(
        data: Data([
            0x54, 0x4c, 0x57, 0x2d, 0xa7, 0x83, 0x1e, 0xc4,
            0x39, 0x71, 0xd8, 0x0b, 0x65, 0x92, 0xf1, 0x46,
            0xbc, 0x28, 0x53, 0x9d, 0xe0, 0x14, 0x7a, 0x33,
            0x8f, 0xc6, 0x42, 0xb9, 0x05, 0x6e, 0xd1, 0x7c,
        ])
    )

    private static func makeAuthoritySeal(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapterID: ChapterID,
        arcID: ArcID,
        beatID: BeatID,
        arcIndex: Int,
        beatIndex: Int,
        absoluteBeatIndex: Int,
        mode: Mode
    ) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let material = try? encoder.encode(
            SealMaterial(
                packageID: packageID,
                contentVersion: contentVersion,
                chapterID: chapterID,
                arcID: arcID,
                beatID: beatID,
                arcIndex: arcIndex,
                beatIndex: beatIndex,
                absoluteBeatIndex: absoluteBeatIndex,
                mode: mode
            )
        ) else {
            return nil
        }
        return Data(HMAC<SHA256>.authenticationCode(for: material, using: authorityKey))
    }
}

public enum BeatCompletionContractError: Error, Equatable, Sendable {
    case invalidStructure
    case sealingFailed
}

private extension StableID {
    var isNonempty: Bool {
        !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
