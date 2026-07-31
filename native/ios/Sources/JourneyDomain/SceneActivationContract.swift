import ContentKit
import CryptoKit
import Foundation

/// Repository-issued authority to make one exact authored scene durable.
///
/// Presentation code may carry this value back to JourneyDomain, but only
/// JourneyContent can issue one from a verified package cursor. The seal binds
/// the scene to the exact package, chapter, arc and beat that may activate it.
public struct SceneActivationContract: Codable, Equatable, Sendable {
    let packageID: PackageID
    let contentVersion: SchemaVersion
    let chapterID: ChapterID
    let arcID: ArcID
    let beatID: BeatID
    let sceneID: SceneID
    let arcIndex: Int
    let beatIndex: Int
    let absoluteBeatIndex: Int
    let initialDeterministicTick: UInt64
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
        beat: BeatSpec,
        scene: SceneSpec,
        initialDeterministicTick: UInt64 = 0
    ) throws {
        try beat.validate()
        try scene.validate()
        guard beat.sceneID == scene.id else {
            throw SceneActivationContractError.contentMismatch
        }
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.chapterID = chapterID
        self.arcID = arcID
        beatID = beat.id
        sceneID = scene.id
        self.arcIndex = arcIndex
        self.beatIndex = beatIndex
        self.absoluteBeatIndex = absoluteBeatIndex
        self.initialDeterministicTick = initialDeterministicTick
        guard let seal = Self.makeAuthoritySeal(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapterID,
            arcID: arcID,
            beatID: beat.id,
            sceneID: scene.id,
            arcIndex: arcIndex,
            beatIndex: beatIndex,
            absoluteBeatIndex: absoluteBeatIndex,
            initialDeterministicTick: initialDeterministicTick
        ) else {
            throw SceneActivationContractError.sealingFailed
        }
        authoritySeal = seal
        guard isStructurallyValid else {
            throw SceneActivationContractError.invalidStructure
        }
    }

    init(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapterID: ChapterID,
        arcID: ArcID,
        beatID: BeatID,
        sceneID: SceneID,
        arcIndex: Int,
        beatIndex: Int,
        absoluteBeatIndex: Int,
        initialDeterministicTick: UInt64 = 0
    ) {
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.chapterID = chapterID
        self.arcID = arcID
        self.beatID = beatID
        self.sceneID = sceneID
        self.arcIndex = arcIndex
        self.beatIndex = beatIndex
        self.absoluteBeatIndex = absoluteBeatIndex
        self.initialDeterministicTick = initialDeterministicTick
        authoritySeal = Self.makeAuthoritySeal(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapterID,
            arcID: arcID,
            beatID: beatID,
            sceneID: sceneID,
            arcIndex: arcIndex,
            beatIndex: beatIndex,
            absoluteBeatIndex: absoluteBeatIndex,
            initialDeterministicTick: initialDeterministicTick
        ) ?? Data()
    }

    var isStructurallyValid: Bool {
        packageID.isNonempty
            && contentVersion.isValid
            && chapterID.isNonempty
            && arcID.isNonempty
            && beatID.isNonempty
            && sceneID.isNonempty
            && arcIndex >= 0
            && beatIndex >= 0
            && absoluteBeatIndex >= 0
            && authoritySeal == Self.makeAuthoritySeal(
                packageID: packageID,
                contentVersion: contentVersion,
                chapterID: chapterID,
                arcID: arcID,
                beatID: beatID,
                sceneID: sceneID,
                arcIndex: arcIndex,
                beatIndex: beatIndex,
                absoluteBeatIndex: absoluteBeatIndex,
                initialDeterministicTick: initialDeterministicTick
            )
    }

    func matches(session: ChapterSession) -> Bool {
        guard let beatContract = session.beatCompletionContract else { return false }
        return isStructurallyValid
            && packageID == session.packageID
            && contentVersion == session.contentVersion
            && chapterID == session.chapterID
            && arcID == session.arcID
            && beatID == session.beatID
            && packageID == beatContract.packageID
            && contentVersion == beatContract.contentVersion
            && chapterID == beatContract.chapterID
            && arcID == beatContract.arcID
            && beatID == beatContract.beatID
            && arcIndex == beatContract.arcIndex
            && beatIndex == beatContract.beatIndex
            && absoluteBeatIndex == beatContract.absoluteBeatIndex
    }

    private struct SealMaterial: Encodable {
        let packageID: PackageID
        let contentVersion: SchemaVersion
        let chapterID: ChapterID
        let arcID: ArcID
        let beatID: BeatID
        let sceneID: SceneID
        let arcIndex: Int
        let beatIndex: Int
        let absoluteBeatIndex: Int
        let initialDeterministicTick: UInt64
    }

    private static let authorityKey = SymmetricKey(
        data: Data([
            0x54, 0x4c, 0x57, 0x2d, 0xc8, 0x17, 0x64, 0xa3,
            0x0e, 0xf9, 0x42, 0x7b, 0x91, 0x35, 0xdc, 0x68,
            0x23, 0xae, 0x5f, 0x80, 0xd4, 0x1b, 0x76, 0x09,
            0xea, 0x4c, 0xb2, 0x57, 0x9d, 0x30, 0x86, 0xf1,
        ])
    )

    private static func makeAuthoritySeal(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapterID: ChapterID,
        arcID: ArcID,
        beatID: BeatID,
        sceneID: SceneID,
        arcIndex: Int,
        beatIndex: Int,
        absoluteBeatIndex: Int,
        initialDeterministicTick: UInt64
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
                sceneID: sceneID,
                arcIndex: arcIndex,
                beatIndex: beatIndex,
                absoluteBeatIndex: absoluteBeatIndex,
                initialDeterministicTick: initialDeterministicTick
            )
        ) else {
            return nil
        }
        return Data(HMAC<SHA256>.authenticationCode(for: material, using: authorityKey))
    }
}

public enum SceneActivationContractError: Error, Equatable, Sendable {
    case contentMismatch
    case invalidStructure
    case sealingFailed
}

private extension StableID {
    var isNonempty: Bool {
        !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
