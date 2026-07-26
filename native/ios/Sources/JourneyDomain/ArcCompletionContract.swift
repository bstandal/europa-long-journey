import ContentKit
import CryptoKit
import Foundation

/// Repository-issued authority to close one exact authored arc.
public struct ArcCompletionContract: Codable, Equatable, Sendable {
    struct BeatInventory: Codable, Equatable, Sendable {
        let sceneID: SceneID
        let completion: BeatCompletionContract
        let interaction: InteractionSpec?
    }

    let packageID: PackageID
    let contentVersion: SchemaVersion
    let chapterID: ChapterID
    let arcID: ArcID
    let arcIndex: Int
    let beats: [BeatInventory]
    let finalBeatID: BeatID
    let finalSceneID: SceneID
    private let authoritySeal: Data

    @_spi(JourneyContent)
    public init(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapter: ChapterSpec,
        arcIndex: Int
    ) throws {
        try chapter.validate()
        guard chapter.arcs.indices.contains(arcIndex) else {
            throw ArcCompletionContractError.invalidStructure
        }
        let arc = chapter.arcs[arcIndex]
        var absoluteBeatIndex = chapter.arcs.prefix(arcIndex)
            .reduce(0) { $0 + $1.beats.count }
        var inventory: [BeatInventory] = []
        for (beatIndex, beat) in arc.beats.enumerated() {
            inventory.append(
                BeatInventory(
                    sceneID: beat.sceneID,
                    completion: try BeatCompletionContract(
                        packageID: packageID,
                        contentVersion: contentVersion,
                        chapterID: chapter.id,
                        arcID: arc.id,
                        arcIndex: arcIndex,
                        beatIndex: beatIndex,
                        absoluteBeatIndex: absoluteBeatIndex,
                        beat: beat
                    ),
                    interaction: beat.interaction
                )
            )
            absoluteBeatIndex += 1
        }
        guard let finalBeat = inventory.last else {
            throw ArcCompletionContractError.invalidStructure
        }
        self.packageID = packageID
        self.contentVersion = contentVersion
        chapterID = chapter.id
        arcID = arc.id
        self.arcIndex = arcIndex
        beats = inventory
        finalBeatID = finalBeat.completion.beatID
        finalSceneID = finalBeat.sceneID
        guard let seal = Self.makeAuthoritySeal(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapter.id,
            arcID: arc.id,
            arcIndex: arcIndex,
            beats: inventory,
            finalBeatID: finalBeat.completion.beatID,
            finalSceneID: finalBeat.sceneID
        ) else {
            throw ArcCompletionContractError.sealingFailed
        }
        authoritySeal = seal
        guard isStructurallyValid else {
            throw ArcCompletionContractError.invalidStructure
        }
    }

    init(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapterID: ChapterID,
        arcID: ArcID,
        arcIndex: Int,
        beats: [BeatInventory],
        finalBeatID: BeatID,
        finalSceneID: SceneID
    ) {
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.chapterID = chapterID
        self.arcID = arcID
        self.arcIndex = arcIndex
        self.beats = beats
        self.finalBeatID = finalBeatID
        self.finalSceneID = finalSceneID
        authoritySeal = Self.makeAuthoritySeal(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapterID,
            arcID: arcID,
            arcIndex: arcIndex,
            beats: beats,
            finalBeatID: finalBeatID,
            finalSceneID: finalSceneID
        ) ?? Data()
    }

    var isStructurallyValid: Bool {
        guard packageID.isNonempty,
              contentVersion.isValid,
              chapterID.isNonempty,
              arcID.isNonempty,
              arcIndex >= 0,
              !beats.isEmpty,
              finalBeatID.isNonempty,
              finalSceneID.isNonempty,
              authoritySeal == Self.makeAuthoritySeal(
                  packageID: packageID,
                  contentVersion: contentVersion,
                  chapterID: chapterID,
                  arcID: arcID,
                  arcIndex: arcIndex,
                  beats: beats,
                  finalBeatID: finalBeatID,
                  finalSceneID: finalSceneID
              ) else {
            return false
        }
        var beatIDs: [BeatID] = []
        var effectIDs: [WorldEffectID] = []
        var expectedAbsoluteBeatIndex = beats[0].completion.absoluteBeatIndex
        for (beatIndex, beat) in beats.enumerated() {
            let completion = beat.completion
            guard beat.sceneID.isNonempty,
                  completion.isStructurallyValid,
                  completion.packageID == packageID,
                  completion.contentVersion == contentVersion,
                  completion.chapterID == chapterID,
                  completion.arcID == arcID,
                  completion.arcIndex == arcIndex,
                  completion.beatIndex == beatIndex,
                  completion.absoluteBeatIndex == expectedAbsoluteBeatIndex,
                  interactionMatchesCompletion(beat) else {
                return false
            }
            beatIDs.append(completion.beatID)
            effectIDs.append(contentsOf: completion.effects.map(\.id))
            expectedAbsoluteBeatIndex += 1
        }
        guard beatIDs.count == Set(beatIDs).count,
              effectIDs.count == Set(effectIDs).count,
              let finalBeat = beats.last else {
            return false
        }
        return finalBeatID == finalBeat.completion.beatID
            && finalSceneID == finalBeat.sceneID
    }

    var orderedBeatIDs: [BeatID] {
        beats.map(\.completion.beatID)
    }

    var finalBeat: BeatInventory? {
        beats.last
    }

    func matches(session: ChapterSession) -> Bool {
        isStructurallyValid
            && packageID == session.packageID
            && contentVersion == session.contentVersion
            && chapterID == session.chapterID
            && arcID == session.arcID
            && finalBeatID == session.beatID
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
        let arcID: ArcID
        let arcIndex: Int
        let beats: [BeatInventory]
        let finalBeatID: BeatID
        let finalSceneID: SceneID
    }

    private static let authorityKey = SymmetricKey(
        data: Data([
            0x54, 0x4c, 0x57, 0x2d, 0xb4, 0x29, 0xe1, 0x75,
            0x08, 0xca, 0x56, 0x9f, 0x32, 0x6d, 0xf8, 0x10,
            0xa7, 0x43, 0x8b, 0xde, 0x61, 0x05, 0xc9, 0x7a,
            0x24, 0xf3, 0x98, 0x4e, 0xd0, 0x17, 0x6c, 0xa2,
        ])
    )

    private static func makeAuthoritySeal(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapterID: ChapterID,
        arcID: ArcID,
        arcIndex: Int,
        beats: [BeatInventory],
        finalBeatID: BeatID,
        finalSceneID: SceneID
    ) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let material = try? encoder.encode(
            SealMaterial(
                packageID: packageID,
                contentVersion: contentVersion,
                chapterID: chapterID,
                arcID: arcID,
                arcIndex: arcIndex,
                beats: beats,
                finalBeatID: finalBeatID,
                finalSceneID: finalSceneID
            )
        ) else {
            return nil
        }
        return Data(HMAC<SHA256>.authenticationCode(for: material, using: authorityKey))
    }
}

public enum ArcCompletionContractError: Error, Equatable, Sendable {
    case invalidStructure
    case sealingFailed
}

private extension StableID {
    var isNonempty: Bool {
        !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
