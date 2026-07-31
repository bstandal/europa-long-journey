import ContentKit
import Foundation
@testable import JourneyContent
@testable import JourneyDomain
import XCTest

final class DocumentaryBeatCompletionTests: XCTestCase {
    func testDocumentaryCompletionMarksBeatAndAppliesAuthoredWorldEffectInOneEvent() throws {
        let context = try openingContext()
        var state = context.state

        let emitted = JourneyReducer().reduce(
            state: &state,
            event: JourneyEvent(logicalTimeMillis: 1, action: context.action)
        )

        XCTAssertEqual(state.activeChapter?.completedBeatIDs, [context.contract.beatID])
        XCTAssertEqual(state.world.appliedEffects, context.contract.effects)
        XCTAssertEqual(state.world.appliedEffectIDs.count, 1)
        let effect = try XCTUnwrap(context.contract.effects.first)
        guard case let .revealNode(node) = effect.mutation else {
            return XCTFail("Expected the documentary consequence to reveal its authored node")
        }
        XCTAssertEqual(state.world.node(node.id)?.visibility, .revealed)
        XCTAssertEqual(
            emitted,
            [
                .haptic(.seal),
                .worldChanged([effect.id]),
                .checkpoint(.beatChanged),
            ]
        )
    }

    func testSnapshotRestoreAndJournalReplayPreserveTheSameCompletedCausalPoint() throws {
        let context = try openingContext()
        let event = JourneyEvent(logicalTimeMillis: 1, action: context.action)
        var committed = context.state
        let committedEffects = JourneyReducer().reduce(state: &committed, event: event)

        let encodedEvent = try JSONEncoder().encode(event)
        let replayedEvent = try JSONDecoder().decode(JourneyEvent.self, from: encodedEvent)
        var replayed = context.state
        let replayedEffects = JourneyReducer().reduce(
            state: &replayed,
            event: replayedEvent
        )
        XCTAssertEqual(replayed, committed)
        XCTAssertEqual(replayedEffects, committedEffects)

        let snapshotData = try JSONEncoder().encode(SaveSnapshot(state: committed))
        let restored = try JSONDecoder().decode(SaveSnapshot.self, from: snapshotData).state
        XCTAssertEqual(restored, committed)
        XCTAssertNoThrow(try context.coordinator.currentCursor(state: restored))

        let recovery = try context.coordinator.advanceActions(state: restored)
        XCTAssertFalse(recovery.actions.contains(context.action))
        guard case .enterAuthoredBeat = recovery.actions.first else {
            return XCTFail("Restore must continue after the already durable documentary beat")
        }
    }

    func testLegacySnapshotCanBeReboundOnlyToTheRepositoryExactCompletionContract() throws {
        let context = try openingContext()
        var legacy = context.state
        _ = JourneyReducer().reduce(state: &legacy, action: context.action)
        legacy.activeChapter?.beatCompletionContract = nil
        _ = JourneyReducer().reduce(state: &legacy, action: .showWorld)

        let resume = try context.coordinator.resumeActions(
            chapterID: context.contract.chapterID,
            state: legacy
        )
        XCTAssertEqual(resume.count, 2)
        guard case .selectChapter = resume[0], case .restoreAuthoredBeat = resume[1] else {
            return XCTFail("Expected exact repository rebinding after route selection")
        }
        let rebound = JourneyContentFixtures.applying(resume, to: legacy)
        XCTAssertEqual(
            rebound.activeChapter?.beatCompletionContract,
            context.contract
        )
        XCTAssertEqual(rebound.world.appliedEffects, context.contract.effects)
    }

    func testDuplicateDocumentaryCompletionIsRejectedWithoutRepeatingItsConsequence() throws {
        let context = try openingContext()
        var state = context.state
        _ = JourneyReducer().reduce(state: &state, action: context.action)
        let committed = state

        let emitted = JourneyReducer().reduce(state: &state, action: context.action)

        XCTAssertEqual(state, committed)
        XCTAssertEqual(state.world.appliedEffects, context.contract.effects)
        XCTAssertEqual(state.world.appliedEffectIDs.count, 1)
        XCTAssertTrue(emitted.containsRejection)
        XCTAssertFalse(emitted.containsWorldChange)
    }

    func testWrongBeatOrderEffectSetAndVersionAllFailClosed() throws {
        let context = try openingContext()
        let alternateEffect = WorldEffect(
            id: "effect-forged-documentary",
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: "node-forged-documentary",
                    kind: .landscape,
                    form: "forged",
                    position: NormalizedPoint(x: 0.2, y: 0.2)
                )
            )
        )
        let attempts: [(String, BeatCompletionContract)] = [
            (
                "wrong beat",
                replacing(context.contract, beatID: "another-beat")
            ),
            (
                "wrong order",
                replacing(context.contract, absoluteBeatIndex: 1)
            ),
            (
                "wrong effect set",
                replacing(context.contract, effects: [alternateEffect])
            ),
            (
                "wrong version",
                replacing(
                    context.contract,
                    contentVersion: SchemaVersion(major: 2)
                )
            ),
        ]

        for (label, forged) in attempts {
            var state = context.state
            let emitted = JourneyReducer().reduce(
                state: &state,
                action: .completeDocumentaryBeat(forged)
            )
            XCTAssertEqual(state, context.state, label)
            XCTAssertTrue(emitted.containsRejection, label)
            XCTAssertTrue(state.world.appliedEffects.isEmpty, label)
            XCTAssertTrue(state.activeChapter?.completedBeatIDs.isEmpty == true, label)
        }
    }

    func testDecodedPayloadTamperingCannotForgeContentAuthority() throws {
        let context = try openingContext()
        let encoded = try JSONEncoder().encode(context.contract)
        let tamperedText = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(
                of: context.contract.beatID.rawValue,
                with: "forged-documentary-beat"
            )
        XCTAssertNotEqual(tamperedText, String(decoding: encoded, as: UTF8.self))
        let tampered = try JSONDecoder().decode(
            BeatCompletionContract.self,
            from: Data(tamperedText.utf8)
        )
        XCTAssertFalse(tampered.isStructurallyValid)

        var state = context.state
        let emitted = JourneyReducer().reduce(
            state: &state,
            action: .completeDocumentaryBeat(tampered)
        )
        XCTAssertEqual(state, context.state)
        XCTAssertTrue(emitted.containsRejection)
        XCTAssertTrue(state.world.appliedEffects.isEmpty)
    }

    func testDocumentaryCarrierCannotCompleteAnInteractionBeat() throws {
        let context = try openingContext()
        let openingPlan = try context.coordinator.advanceActions(state: context.state)
        let interactionState = JourneyContentFixtures.applying(
            openingPlan.actions,
            to: context.state
        )
        let interactionContract = try XCTUnwrap(
            interactionState.activeChapter?.beatCompletionContract
        )
        let interaction = try XCTUnwrap(interactionContract.interactionIdentity)
        let forgedDocumentary = BeatCompletionContract(
            packageID: interactionContract.packageID,
            contentVersion: interactionContract.contentVersion,
            chapterID: interactionContract.chapterID,
            arcID: interactionContract.arcID,
            beatID: interactionContract.beatID,
            arcIndex: interactionContract.arcIndex,
            beatIndex: interactionContract.beatIndex,
            absoluteBeatIndex: interactionContract.absoluteBeatIndex,
            mode: .documentary(effects: interaction.effects)
        )

        var state = interactionState
        let documentaryAttempt = JourneyReducer().reduce(
            state: &state,
            action: .completeDocumentaryBeat(forgedDocumentary)
        )
        XCTAssertEqual(state, interactionState)
        XCTAssertTrue(documentaryAttempt.containsRejection)
        XCTAssertFalse(interaction.effects.contains { state.world.hasApplied($0.id) })

        let prematureInteractionCompletion = JourneyReducer().reduce(
            state: &state,
            action: .completeBeat(
                arcID: interactionContract.arcID,
                beatID: interactionContract.beatID
            )
        )
        XCTAssertEqual(state, interactionState)
        XCTAssertTrue(prematureInteractionCompletion.containsRejection)
    }

    func testCoordinatorRejectsRestoredCompletionWithoutItsWorldConsequence() throws {
        let context = try openingContext()
        var completed = context.state
        _ = JourneyReducer().reduce(state: &completed, action: context.action)
        let session = try XCTUnwrap(completed.activeChapter)
        let broken = JourneyState(
            route: completed.route,
            world: WorldGraph(),
            chapterSessions: [session]
        )

        XCTAssertThrowsError(try context.coordinator.currentCursor(state: broken)) { error in
            XCTAssertEqual(
                error as? ChapterCoordinatorError,
                .documentaryEffectMismatch(context.contract.beatID)
            )
        }
    }

    private func openingContext() throws -> (
        coordinator: ChapterCoordinator,
        state: JourneyState,
        action: JourneyAction,
        contract: BeatCompletionContract
    ) {
        let coordinator = try ChapterCoordinator(
            repository: ContentRepository(
                packagePayloads: [JourneyContentFixtures.package("essential-free-v1")]
            )
        )
        let state = JourneyContentFixtures.applying(
            try coordinator.beginActions(chapterID: "first-farmers", state: .initial)
        )
        let plan = try coordinator.advanceActions(state: state)
        let action = try XCTUnwrap(plan.actions.first)
        guard case let .completeDocumentaryBeat(contract) = action else {
            throw TestFailure.expectedDocumentaryCompletion
        }
        XCTAssertFalse(contract.effects.isEmpty)
        return (coordinator, state, action, contract)
    }

    private func replacing(
        _ contract: BeatCompletionContract,
        contentVersion: SchemaVersion? = nil,
        beatID: BeatID? = nil,
        absoluteBeatIndex: Int? = nil,
        effects: [WorldEffect]? = nil
    ) -> BeatCompletionContract {
        BeatCompletionContract(
            packageID: contract.packageID,
            contentVersion: contentVersion ?? contract.contentVersion,
            chapterID: contract.chapterID,
            arcID: contract.arcID,
            beatID: beatID ?? contract.beatID,
            arcIndex: contract.arcIndex,
            beatIndex: contract.beatIndex,
            absoluteBeatIndex: absoluteBeatIndex ?? contract.absoluteBeatIndex,
            mode: .documentary(effects: effects ?? contract.effects)
        )
    }
}

private enum TestFailure: Error {
    case expectedDocumentaryCompletion
}

private extension Array where Element == JourneyEffect {
    var containsRejection: Bool {
        contains { effect in
            if case .rejected = effect { return true }
            return false
        }
    }

    var containsWorldChange: Bool {
        contains { effect in
            if case .worldChanged = effect { return true }
            return false
        }
    }
}
