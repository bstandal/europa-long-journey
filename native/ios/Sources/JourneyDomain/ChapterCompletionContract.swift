import ContentKit
import CryptoKit
import Foundation

/// Repository-issued authority to close one complete authored chapter.
///
/// The contract carries the full ordered arc-and-beat inventory so replay can
/// prove that the final cursor, every durable beat consequence and the chapter
/// consequence still belong to the same verified content version.
public struct ChapterCompletionContract: Codable, Equatable, Sendable {
    struct BeatInventory: Codable, Equatable, Sendable {
        let sceneID: SceneID
        let completion: BeatCompletionContract
        let interaction: InteractionSpec?
    }

    struct ArcInventory: Codable, Equatable, Sendable {
        let arcID: ArcID
        let beats: [BeatInventory]
    }

    let packageID: PackageID
    let contentVersion: SchemaVersion
    let chapterID: ChapterID
    let arcs: [ArcInventory]
    let finalArcID: ArcID
    let finalBeatID: BeatID
    let finalSceneID: SceneID
    let completionEffects: [WorldEffect]
    private let authoritySeal: Data

    @_spi(JourneyContent)
    public init(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapter: ChapterSpec
    ) throws {
        try chapter.validate()
        var absoluteBeatIndex = 0
        var inventory: [ArcInventory] = []
        for (arcIndex, arc) in chapter.arcs.enumerated() {
            var beats: [BeatInventory] = []
            for (beatIndex, beat) in arc.beats.enumerated() {
                let completion = try BeatCompletionContract(
                    packageID: packageID,
                    contentVersion: contentVersion,
                    chapterID: chapter.id,
                    arcID: arc.id,
                    arcIndex: arcIndex,
                    beatIndex: beatIndex,
                    absoluteBeatIndex: absoluteBeatIndex,
                    beat: beat
                )
                beats.append(
                    BeatInventory(
                        sceneID: beat.sceneID,
                        completion: completion,
                        interaction: beat.interaction
                    )
                )
                absoluteBeatIndex += 1
            }
            inventory.append(ArcInventory(arcID: arc.id, beats: beats))
        }
        guard let finalArc = inventory.last,
              let finalBeat = finalArc.beats.last else {
            throw ChapterCompletionContractError.invalidStructure
        }
        self.packageID = packageID
        self.contentVersion = contentVersion
        chapterID = chapter.id
        arcs = inventory
        finalArcID = finalArc.arcID
        finalBeatID = finalBeat.completion.beatID
        finalSceneID = finalBeat.sceneID
        completionEffects = chapter.completionEffects
        guard let seal = Self.makeAuthoritySeal(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapter.id,
            arcs: inventory,
            finalArcID: finalArc.arcID,
            finalBeatID: finalBeat.completion.beatID,
            finalSceneID: finalBeat.sceneID,
            completionEffects: chapter.completionEffects
        ) else {
            throw ChapterCompletionContractError.sealingFailed
        }
        authoritySeal = seal
        guard isStructurallyValid else {
            throw ChapterCompletionContractError.invalidStructure
        }
    }

    init(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapterID: ChapterID,
        arcs: [ArcInventory],
        finalArcID: ArcID,
        finalBeatID: BeatID,
        finalSceneID: SceneID,
        completionEffects: [WorldEffect]
    ) {
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.chapterID = chapterID
        self.arcs = arcs
        self.finalArcID = finalArcID
        self.finalBeatID = finalBeatID
        self.finalSceneID = finalSceneID
        self.completionEffects = completionEffects
        authoritySeal = Self.makeAuthoritySeal(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapterID,
            arcs: arcs,
            finalArcID: finalArcID,
            finalBeatID: finalBeatID,
            finalSceneID: finalSceneID,
            completionEffects: completionEffects
        ) ?? Data()
    }

    var isStructurallyValid: Bool {
        guard packageID.isNonempty,
              contentVersion.isValid,
              chapterID.isNonempty,
              (1 ... 3).contains(arcs.count),
              finalArcID.isNonempty,
              finalBeatID.isNonempty,
              finalSceneID.isNonempty,
              completionEffectsHaveUniqueNonemptyIDs,
              completionEffects.allSatisfy({ (try? $0.validate()) != nil }),
              authoritySeal == Self.makeAuthoritySeal(
                  packageID: packageID,
                  contentVersion: contentVersion,
                  chapterID: chapterID,
                  arcs: arcs,
                  finalArcID: finalArcID,
                  finalBeatID: finalBeatID,
                  finalSceneID: finalSceneID,
                  completionEffects: completionEffects
              ) else {
            return false
        }

        var absoluteBeatIndex = 0
        var arcIDs: [ArcID] = []
        var beatIDs: [BeatID] = []
        var allEffectIDs = completionEffects.map(\.id)
        for (arcIndex, arc) in arcs.enumerated() {
            guard arc.arcID.isNonempty, !arc.beats.isEmpty else { return false }
            arcIDs.append(arc.arcID)
            for (beatIndex, beat) in arc.beats.enumerated() {
                let completion = beat.completion
                guard beat.sceneID.isNonempty,
                      completion.isStructurallyValid,
                      completion.packageID == packageID,
                      completion.contentVersion == contentVersion,
                      completion.chapterID == chapterID,
                      completion.arcID == arc.arcID,
                      completion.arcIndex == arcIndex,
                      completion.beatIndex == beatIndex,
                      completion.absoluteBeatIndex == absoluteBeatIndex,
                      interactionMatchesCompletion(beat) else {
                    return false
                }
                beatIDs.append(completion.beatID)
                allEffectIDs.append(contentsOf: completion.effects.map(\.id))
                absoluteBeatIndex += 1
            }
        }
        guard arcIDs.count == Set(arcIDs).count,
              beatIDs.count == Set(beatIDs).count,
              allEffectIDs.count == Set(allEffectIDs).count,
              let lastArc = arcs.last,
              let lastBeat = lastArc.beats.last else {
            return false
        }
        return finalArcID == lastArc.arcID
            && finalBeatID == lastBeat.completion.beatID
            && finalSceneID == lastBeat.sceneID
    }

    var orderedArcIDs: [ArcID] {
        arcs.map(\.arcID)
    }

    var orderedBeatIDs: [BeatID] {
        arcs.flatMap { $0.beats.map(\.completion.beatID) }
    }

    var beatInventory: [BeatInventory] {
        arcs.flatMap(\.beats)
    }

    var finalBeat: BeatInventory? {
        arcs.last?.beats.last
    }

    func matches(session: ChapterSession) -> Bool {
        isStructurallyValid
            && packageID == session.packageID
            && contentVersion == session.contentVersion
            && chapterID == session.chapterID
            && finalArcID == session.arcID
            && finalBeatID == session.beatID
    }

    private var completionEffectsHaveUniqueNonemptyIDs: Bool {
        let ids = completionEffects.map(\.id)
        return !ids.isEmpty
            && ids.allSatisfy(\.isNonempty)
            && ids.count == Set(ids).count
    }

    private func interactionMatchesCompletion(_ beat: BeatInventory) -> Bool {
        switch (beat.completion.mode, beat.interaction) {
        case (.documentary, nil):
            return true
        case (.documentary, .some), (.interaction, nil):
            return false
        case let (.interaction(id, effects), interaction?):
            return (try? interaction.validate()) != nil
                && interaction.id == id
                && interaction.completionEffects == effects
        }
    }

    private struct SealMaterial: Encodable {
        let packageID: PackageID
        let contentVersion: SchemaVersion
        let chapterID: ChapterID
        let arcs: [ArcInventory]
        let finalArcID: ArcID
        let finalBeatID: BeatID
        let finalSceneID: SceneID
        let completionEffects: [WorldEffect]
    }

    private static let authorityKey = SymmetricKey(
        data: Data([
            0x54, 0x4c, 0x57, 0x2d, 0x6a, 0xd0, 0x31, 0x8c,
            0xe7, 0x45, 0x9b, 0x12, 0x58, 0xaf, 0x73, 0x04,
            0xcd, 0x26, 0x80, 0xf5, 0x49, 0x1e, 0xb7, 0x63,
            0x95, 0x0a, 0xde, 0x38, 0x71, 0xc2, 0x5f, 0xa9,
        ])
    )

    private static func makeAuthoritySeal(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapterID: ChapterID,
        arcs: [ArcInventory],
        finalArcID: ArcID,
        finalBeatID: BeatID,
        finalSceneID: SceneID,
        completionEffects: [WorldEffect]
    ) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let material = try? encoder.encode(
            SealMaterial(
                packageID: packageID,
                contentVersion: contentVersion,
                chapterID: chapterID,
                arcs: arcs,
                finalArcID: finalArcID,
                finalBeatID: finalBeatID,
                finalSceneID: finalSceneID,
                completionEffects: completionEffects
            )
        ) else {
            return nil
        }
        return Data(HMAC<SHA256>.authenticationCode(for: material, using: authorityKey))
    }
}

public enum ChapterCompletionContractError: Error, Equatable, Sendable {
    case invalidStructure
    case sealingFailed
}

private extension StableID {
    var isNonempty: Bool {
        !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
