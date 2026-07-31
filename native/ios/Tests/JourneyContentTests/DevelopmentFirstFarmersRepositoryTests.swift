#if DEBUG
import ContentKit
import Foundation
import JourneyDomain
@testable import JourneyContent
import XCTest

final class DevelopmentFirstFarmersRepositoryTests: XCTestCase {
    func testEnvelopeSeedsTheExactFirstBeatWithoutInventingLaunchContent() throws {
        let envelope = try loadEnvelope()
        let coordinator = ChapterCoordinator(repository: envelope.repository)
        let initial = try envelope.initialJourneyState()

        XCTAssertEqual(initial.world.nodes.count, 4)
        XCTAssertTrue(initial.world.nodes.allSatisfy { $0.visibility == .hidden })
        XCTAssertEqual(initial.world.traces.count, 1)
        XCTAssertTrue(initial.world.traces.allSatisfy { $0.state == .dormant })

        let state = applying(
            try coordinator.beginActions(chapterID: "first-farmers", state: initial),
            to: initial
        )
        let cursor = try coordinator.currentCursor(state: state)

        XCTAssertEqual(cursor.packageID, "first-farmers-development-v1")
        XCTAssertEqual(cursor.chapter.id, "first-farmers")
        XCTAssertEqual(cursor.arc.id, "first-farmers-arc-01")
        XCTAssertEqual(cursor.beat.id, "beat-first-farmers-river-world")
        XCTAssertEqual(cursor.scene.id, "scene-first-farmers-iron-gates-dawn")
        XCTAssertEqual(
            cursor.beat.narrative.heading.launchEnglish,
            "The River Already Held a World"
        )
        XCTAssertNil(cursor.beat.interaction)
    }

    func testDocumentaryAdvanceCommitsTheFirstBeatAndEntersItsExactSuccessor() throws {
        let envelope = try loadEnvelope()
        let coordinator = ChapterCoordinator(repository: envelope.repository)
        let initial = try envelope.initialJourneyState()
        var state = applying(
            try coordinator.beginActions(chapterID: "first-farmers", state: initial),
            to: initial
        )

        let plan = try coordinator.advanceActions(state: state)
        XCTAssertEqual(
            plan.destination,
            .beat(
                chapterID: "first-farmers",
                arcID: "first-farmers-arc-01",
                beatID: "beat-first-farmers-household-crosses"
            )
        )
        guard plan.actions.count == 4,
              case .completeDocumentaryBeat = plan.actions[0],
              case .enterAuthoredBeat = plan.actions[1],
              case .activateScene = plan.actions[2],
              case .beginInteraction = plan.actions[3] else {
            return XCTFail("Expected documentary completion followed by the exact interactive beat")
        }

        state = applying(plan.actions, to: state)
        XCTAssertEqual(
            state.activeChapter?.completedBeatIDs,
            ["beat-first-farmers-river-world"]
        )
        let cursor = try coordinator.currentCursor(state: state)
        XCTAssertEqual(cursor.beat.id, "beat-first-farmers-household-crosses")
        XCTAssertEqual(cursor.scene.id, "scene-first-farmers-aegean-crossing")
        XCTAssertEqual(cursor.beat.interaction?.id, "interaction-first-farmers-a-household-crosses")
        XCTAssertEqual(state.activeChapter?.interaction?.phase, .ready)
    }

    func testSaveRoundTripResumesTheSameCausalPointWithoutResettingLocalAnchors() throws {
        let envelope = try loadEnvelope()
        let coordinator = ChapterCoordinator(repository: envelope.repository)
        let initial = try envelope.initialJourneyState()
        var state = applying(
            try coordinator.beginActions(chapterID: "first-farmers", state: initial),
            to: initial
        )
        state = applying(try coordinator.advanceActions(state: state).actions, to: state)
        state = applying(
            [
                .setCameraAnchor(0.67),
                .setReadingAnchor("ff-crossing-02"),
                .setNarration(
                    cueID: "narration-ff-crossing-02",
                    sampleOffset: 48_321,
                    enabled: true,
                    playing: true
                ),
                .showWorld,
            ],
            to: state
        )

        var decoded = try JSONDecoder().decode(
            SaveSnapshot.self,
            from: JSONEncoder().encode(SaveSnapshot(state: state))
        ).state
        decoded.prepareForColdRestore()
        let saved = try XCTUnwrap(decoded.chapterSession("first-farmers"))
        XCTAssertFalse(saved.narration.isPlaying)

        decoded = applying(
            try coordinator.resumeActions(chapterID: "first-farmers", state: decoded),
            to: decoded
        )
        let cursor = try coordinator.currentCursor(state: decoded)
        XCTAssertEqual(cursor.beat.id, "beat-first-farmers-household-crosses")
        XCTAssertEqual(decoded.activeChapter?.cameraAnchor, 0.67)
        XCTAssertEqual(decoded.activeChapter?.readingAnchor, "ff-crossing-02")
        XCTAssertEqual(decoded.activeChapter?.narration.sampleOffset, 48_321)
        XCTAssertTrue(decoded.activeChapter?.narration.isEnabled ?? false)
        XCTAssertFalse(decoded.activeChapter?.narration.isPlaying ?? true)
    }

    func testEnvelopeFailsClosedForMissingAndForgedInputs() throws {
        let files = try payloadFiles()
        let root = URL(fileURLWithPath: "/tmp/non-shipping-first-farmers")

        XCTAssertThrowsError(
            try DevelopmentFirstFarmersEnvelopeLoader.load(
                payloadData: nil,
                receiptData: files.receipt,
                resourceRootURL: root
            )
        ) { error in
            XCTAssertEqual(error as? DevelopmentFirstFarmersEnvelopeError, .missingPayload)
        }
        XCTAssertThrowsError(
            try DevelopmentFirstFarmersEnvelopeLoader.load(
                payloadData: files.payload,
                receiptData: nil,
                resourceRootURL: root
            )
        ) { error in
            XCTAssertEqual(error as? DevelopmentFirstFarmersEnvelopeError, .missingReceipt)
        }

        var forgedPayload = files.payload
        forgedPayload[forgedPayload.startIndex] ^= 0x01
        XCTAssertThrowsError(
            try DevelopmentFirstFarmersEnvelopeLoader.load(
                payloadData: forgedPayload,
                receiptData: files.receipt,
                resourceRootURL: root
            )
        ) { error in
            XCTAssertEqual(error as? DevelopmentFirstFarmersEnvelopeError, .payloadDigestMismatch)
        }

        let forgedReceipt = try mutateJSON(files.receipt) { root in
            root["shippingState"] = "APPROVED"
        }
        XCTAssertThrowsError(
            try DevelopmentFirstFarmersEnvelopeLoader.load(
                payloadData: files.payload,
                receiptData: forgedReceipt,
                resourceRootURL: root
            )
        ) { error in
            XCTAssertEqual(
                error as? DevelopmentFirstFarmersEnvelopeError,
                .nonShippingBoundaryMismatch
            )
        }
    }

    func testDevelopmentPayloadCannotEnterTheProductionRepository() throws {
        let payload = try ContentDocumentDecoder.decodePackage(payloadFiles().payload)
        XCTAssertThrowsError(
            try ContentRepository(packagePayloads: [payload])
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .unknownPackage("first-farmers-development-v1")
            )
        }

        let wrongPackageData = try mutateJSON(payloadFiles().payload) { root in
            root["packageID"] = "forged-first-farmers-development"
        }
        let wrongPackage = try ContentDocumentDecoder.decodePackage(wrongPackageData)
        XCTAssertThrowsError(
            try DevelopmentFirstFarmersRepository(payload: wrongPackage)
        ) { error in
            XCTAssertEqual(
                error as? DevelopmentFirstFarmersRepositoryError,
                .wrongPackage("forged-first-farmers-development")
            )
        }
    }

    private func loadEnvelope() throws -> DevelopmentFirstFarmersEnvelope {
        let files = try payloadFiles()
        return try DevelopmentFirstFarmersEnvelopeLoader.load(
            payloadData: files.payload,
            receiptData: files.receipt,
            resourceRootURL: files.root
        )
    }

    private func payloadFiles() throws -> (payload: Data, receipt: Data, root: URL) {
#if os(iOS)
        let bundle = Bundle(for: DevelopmentFirstFarmersRepositoryTests.self)
        let payloadURL = try XCTUnwrap(
            bundle.url(
                forResource: "first-farmers.content-package",
                withExtension: "json"
            )
        )
        let receiptURL = try XCTUnwrap(
            bundle.url(
                forResource: "first-farmers.payload-receipt",
                withExtension: "json"
            )
        )
        return (
            payload: try Data(contentsOf: payloadURL),
            receipt: try Data(contentsOf: receiptURL),
            root: try XCTUnwrap(bundle.resourceURL)
        )
#else
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let generated = nativeRoot.appending(path: "phase2/generated")
        return (
            payload: try Data(
                contentsOf: generated.appending(path: "first-farmers.content-package.json")
            ),
            receipt: try Data(
                contentsOf: generated.appending(path: "first-farmers.payload-receipt.json")
            ),
            root: nativeRoot
        )
#endif
    }

    private func applying(
        _ actions: [JourneyAction],
        to initial: JourneyState
    ) -> JourneyState {
        var state = initial
        let reducer = JourneyReducer()
        for action in actions {
            let effects = reducer.reduce(state: &state, action: action)
            XCTAssertFalse(effects.contains { effect in
                if case .rejected = effect { return true }
                return false
            })
        }
        return state
    }

    private func mutateJSON(
        _ data: Data,
        mutation: (inout [String: Any]) -> Void
    ) throws -> Data {
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        mutation(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}
#endif
