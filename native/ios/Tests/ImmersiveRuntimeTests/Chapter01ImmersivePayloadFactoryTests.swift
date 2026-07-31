import ContentKit
import XCTest
@testable import ImmersiveRuntime

final class Chapter01ImmersivePayloadFactoryTests: XCTestCase {
    func testFactoryBuildsStrictApprovedPayloadAndCanonicalBytesDeterministically() throws {
        let integrity = makeIntegrity()
        let first = try Chapter01ImmersivePayloadFactory.make(assetIntegrityByPath: integrity)
        let second = try Chapter01ImmersivePayloadFactory.make(assetIntegrityByPath: integrity)

        XCTAssertNoThrow(try first.validate())
        XCTAssertEqual(first, second)
        XCTAssertEqual(
            try ImmersiveContentDocumentV2.encode(first),
            try ImmersiveContentDocumentV2.encode(second)
        )
        XCTAssertEqual(
            try ImmersiveContentDocumentV2.decode(
                ImmersiveContentDocumentV2.encode(first)
            ),
            first
        )
    }

    func testFactoryPreservesFiveCellsSixSequencesAndExactDurableBeatIdentity() throws {
        let payload = try makePayload()

        XCTAssertEqual(payload.worldCells.map(\.id), Chapter01ImmersiveV2Authority.worldCellIDs)
        XCTAssertEqual(payload.sequences.map(\.id), Chapter01ImmersiveV2Authority.sequenceIDs)
        XCTAssertEqual(payload.sequences.count, 6)
        XCTAssertEqual(payload.sequences.flatMap(\.beats).count, 34)
        XCTAssertEqual(
            payload.sequences.flatMap(\.beats).map(\.id.rawValue),
            Chapter01ExperienceScript.beats.map { "beat-first-farmers-\($0.id)" }
        )
        XCTAssertEqual(
            payload.sequences.reduce(0) { $0 + $1.authoredDurationSeconds },
            Chapter01ExperienceScript.authoredDurationSeconds,
            accuracy: 0.001
        )
    }

    func testCurrentAndNextStreamingIsBoundToEveryPhysicalCellBoundary() throws {
        let payload = try makePayload()

        XCTAssertEqual(payload.streamingPolicy.maximumResidentCellCount, 2)
        XCTAssertFalse(payload.streamingPolicy.permitsPlaceholderUI)
        XCTAssertEqual(payload.streamingPolicy.unloadRule, .afterTransitionCommit)
        XCTAssertTrue(
            payload.transitions.allSatisfy {
                $0.prefetchesDestinationCell == ($0.sourceCellID != $0.destinationCellID)
            }
        )
        XCTAssertEqual(payload.transitions.filter(\.prefetchesDestinationCell).count, 4)
    }

    func testFiveCellsShareOneMaterialCarrierAndOneDirectedAnimationLibrary()
        throws
    {
        let payload = try makePayload()
        let materialAssets = payload.assets.filter { $0.kind == .material }
        let animationAssets = payload.assets.filter { $0.kind == .animation }

        XCTAssertEqual(payload.assets.count, 34)
        XCTAssertEqual(materialAssets.count, 1)
        XCTAssertEqual(animationAssets.count, 1)
        XCTAssertEqual(
            materialAssets.first?.path,
            "immersive/first-farmers/materials/chapter01-material-carrier-v1.usdz"
        )
        XCTAssertEqual(
            animationAssets.first?.path,
            "immersive/first-farmers/animations/chapter01-directed-animation-library-v1.usdz"
        )
        XCTAssertEqual(
            Set(
                payload.worldCells
                    .flatMap(\.materialBindings)
                    .flatMap(\.states)
                    .map(\.assetID)
            ),
            Set(materialAssets.map(\.id))
        )
        XCTAssertEqual(
            Set(
                payload.worldCells
                    .flatMap(\.animationBindings)
                    .flatMap(\.states)
                    .map(\.assetID)
            ),
            Set(animationAssets.map(\.id))
        )
    }

    func testInteractionAndExternalWorldEffectAuthorityRemainStable() throws {
        let payload = try makePayload()
        let expectedEffectIDs = [
            "effect-first-farmers-a-household-crosses",
            "effect-first-farmers-the-harvest-had-to-last",
            "effect-first-farmers-at-the-iron-gates",
            "effect-first-farmers-the-house-outlives",
            "effect-first-farmers-more-mouths-more-land",
            "effect-first-farmers-a-continent-remade",
        ]

        XCTAssertEqual(
            payload.sequences.map(\.principalInteraction.interactionID),
            Chapter01InteractionCatalog.specs.map(\.id)
        )
        XCTAssertTrue(
            payload.sequences.allSatisfy {
                $0.principalInteraction.effectAuthority == .externalWorldEffects
            }
        )
        XCTAssertEqual(
            Chapter01InteractionCatalog.specs.flatMap(\.completionEffects).map(\.id.rawValue),
            expectedEffectIDs
        )
        XCTAssertEqual(
            Set(payload.worldCells.flatMap(\.semanticActions).map(\.interactionID)),
            Set(Chapter01InteractionCatalog.specs.map(\.id))
        )
    }

    func testCaptionsAndVisibleFallbackLanguageStayInsideLockedCeilings() throws {
        let payload = try makePayload()
        let captionByID = Dictionary(uniqueKeysWithValues: payload.captions.map { ($0.id, $0) })

        XCTAssertEqual(payload.narrationBindings.count, 10)
        XCTAssertTrue(payload.captions.allSatisfy { (1 ... 2).contains($0.maximumLineCount) })
        for narration in payload.narrationBindings {
            let transcript = narration.captionIDs.compactMap { captionByID[$0]?.text.launchEnglish }
                .joined(separator: " ")
            XCTAssertEqual(normalize(transcript), normalize(narration.text.launchEnglish))
        }

        let visibleCues = payload.worldCells.flatMap(\.semanticActions)
            .compactMap(\.visibleFallbackCue)
        let visibleWordCount = visibleCues.reduce(0) {
            $0 + $1.launchEnglish.split(whereSeparator: \.isWhitespace).count
        }
        XCTAssertLessThanOrEqual(visibleWordCount, payload.pacing.maximumVisibleInterfaceWords)
        XCTAssertTrue(
            visibleCues.allSatisfy {
                (1 ... 4).contains($0.launchEnglish.split(whereSeparator: \.isWhitespace).count)
            }
        )
    }

    func testFactoryRefusesToInventMissingAssetIntegrity() throws {
        var integrity = makeIntegrity()
        let missingPath = try XCTUnwrap(Chapter01ImmersivePayloadFactory.requiredAssetPaths.first)
        integrity[missingPath] = nil

        XCTAssertThrowsError(
            try Chapter01ImmersivePayloadFactory.make(assetIntegrityByPath: integrity)
        ) { error in
            XCTAssertEqual(
                error as? Chapter01ImmersivePayloadFactoryError,
                .missingAssetIntegrity(path: missingPath)
            )
        }
    }
}

private extension Chapter01ImmersivePayloadFactoryTests {
    func makePayload() throws -> ContentPackagePayloadV2 {
        try Chapter01ImmersivePayloadFactory.make(assetIntegrityByPath: makeIntegrity())
    }

    func makeIntegrity() -> [String: Chapter01ImmersiveAssetIntegrity] {
        Dictionary(
            uniqueKeysWithValues: Chapter01ImmersivePayloadFactory.requiredAssetPaths.enumerated().map {
                index, path in
                let hexadecimal = String(format: "%064llx", UInt64(index + 1))
                return (
                    path,
                    Chapter01ImmersiveAssetIntegrity(
                        sha256: hexadecimal,
                        byteCount: Int64(1_024 + index)
                    )
                )
            }
        )
    }

    func normalize(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
