#if DEBUG
import ContentKit
import CryptoKit
import Foundation
import JourneyDomain
@testable import JourneyContent
import XCTest

final class FirstFarmersFullTraversalTests: XCTestCase {
    func testAllSeventeenBeatsAndSixInteractionsReachOneDeterministicFinalState() throws {
        let uninterrupted = try traverse(restoringAfterEveryAction: false)
        let crashRecovered = try traverse(restoringAfterEveryAction: true)

        XCTAssertEqual(uninterrupted.visitedBeatIDs, Self.expectedBeatIDs)
        XCTAssertEqual(crashRecovered.visitedBeatIDs, Self.expectedBeatIDs)
        XCTAssertEqual(uninterrupted.interactionIDs.count, 6)
        XCTAssertEqual(Set(uninterrupted.interactionIDs).count, 6)
        XCTAssertEqual(crashRecovered.interactionIDs, uninterrupted.interactionIDs)
        XCTAssertEqual(crashRecovered.state, uninterrupted.state)
        XCTAssertEqual(try digest(crashRecovered.state), try digest(uninterrupted.state))
        XCTAssertEqual(uninterrupted.state.route, .world)
        XCTAssertEqual(uninterrupted.state.completedChapterIDs, ["first-farmers"])
        let completedSession = try XCTUnwrap(
            uninterrupted.state.chapterSession("first-farmers")
        )
        XCTAssertEqual(Set(completedSession.completedBeatIDs), Set(Self.expectedBeatIDs))
        XCTAssertEqual(completedSession.completedArcIDs.count, 3)
        XCTAssertTrue(
            completedSession.hasSealedReviewArchiveForCompletedBeats
        )
        let reviewCoordinator = ChapterCoordinator(
            repository: try loadEnvelope().repository
        )
        XCTAssertNoThrow(
            try reviewCoordinator.openReviewPlan(
                chapterID: "first-farmers",
                state: uninterrupted.state
            )
        )
    }

    func testEveryInteractionEffectAppearsOnlyAtCompletionAndExactlyOnce() throws {
        let result = try traverse(restoringAfterEveryAction: true)
        let envelope = try loadEnvelope()
        let chapter = try XCTUnwrap(envelope.repository.chapter("first-farmers"))
        let interactionEffects = chapter.arcs
            .flatMap(\.beats)
            .compactMap(\.interaction)
            .flatMap(\.completionEffects)
        let chapterEffects = chapter.completionEffects
        let expectedEffects = interactionEffects + chapterEffects

        XCTAssertEqual(Set(expectedEffects.map(\.id)).count, expectedEffects.count)
        for effect in expectedEffects {
            XCTAssertEqual(
                result.state.world.appliedEffects.filter { $0.id == effect.id },
                [effect]
            )
        }
    }

    func testChapter01ReviewRestoreMatrixCoversEveryBeatBoundaryAndInteractionMidpoint()
        throws {
        let envelope = try loadEnvelope()
        let coordinator = ChapterCoordinator(repository: envelope.repository)
        var state = try envelope.initialJourneyState()
        state = try apply(
            coordinator.beginActions(chapterID: "first-farmers", state: state),
            to: state,
            coordinator: coordinator,
            restoringAfterEveryAction: false
        )

        var checkpoints: [RestoreMatrixCheckpoint] = []
        while case .chapter("first-farmers") = state.route {
            let cursor = try coordinator.currentCursor(state: state)
            let entry = try restoreCheckpoint(
                phase: "entry",
                beatID: cursor.beat.id,
                interactionID: cursor.beat.interaction?.id,
                state: state,
                coordinator: coordinator
            )
            state = entry.state
            checkpoints.append(entry.checkpoint)

            if let interaction = cursor.beat.interaction {
                let actions = try canonicalCompletionActions(for: interaction)
                let midpointAfterActionCount = max(1, actions.count / 2)
                for (index, action) in actions.enumerated() {
                    state = try apply(
                        [.interact(spec: interaction, action: action)],
                        to: state,
                        coordinator: coordinator,
                        restoringAfterEveryAction: false
                    )
                    if index + 1 == midpointAfterActionCount {
                        XCTAssertNotEqual(
                            state.activeChapter?.interaction?.phase,
                            .complete,
                            interaction.id.rawValue
                        )
                        let midpoint = try restoreCheckpoint(
                            phase: "mid-interaction",
                            beatID: cursor.beat.id,
                            interactionID: interaction.id,
                            state: state,
                            coordinator: coordinator
                        )
                        state = midpoint.state
                        checkpoints.append(midpoint.checkpoint)
                    }
                }
                XCTAssertEqual(state.activeChapter?.interaction?.phase, .complete)
            }

            let exit = try restoreCheckpoint(
                phase: "exit",
                beatID: cursor.beat.id,
                interactionID: cursor.beat.interaction?.id,
                state: state,
                coordinator: coordinator
            )
            state = exit.state
            checkpoints.append(exit.checkpoint)
            state = try apply(
                coordinator.advanceActions(state: state).actions,
                to: state,
                coordinator: coordinator,
                restoringAfterEveryAction: false
            )
        }

        let entries = checkpoints.filter { $0.phase == "entry" }
        let exits = checkpoints.filter { $0.phase == "exit" }
        let midpoints = checkpoints.filter { $0.phase == "mid-interaction" }
        XCTAssertEqual(entries.map(\.beatID), Self.expectedBeatIDs.map(\.rawValue))
        XCTAssertEqual(exits.map(\.beatID), Self.expectedBeatIDs.map(\.rawValue))
        XCTAssertEqual(midpoints.count, 6)
        XCTAssertEqual(Set(midpoints.compactMap(\.interactionID)).count, 6)
        XCTAssertTrue(checkpoints.allSatisfy { $0.beforeSHA256 == $0.afterSHA256 })
        XCTAssertEqual(state.route, .world)
        XCTAssertTrue(state.completedChapterIDs.contains("first-farmers"))

        let receipt = RestoreMatrixReceipt(
            formatVersion: 1,
            chapterID: "first-farmers",
            checkpoints: checkpoints,
            finalStateSHA256: try digest(state)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let receiptJSON = String(
            decoding: try encoder.encode(receipt),
            as: UTF8.self
        )
        print("CHAPTER_01_RESTORE_MATRIX=\(receiptJSON)")
    }

    private struct TraversalResult {
        let state: JourneyState
        let visitedBeatIDs: [BeatID]
        let interactionIDs: [InteractionID]
    }

    private struct RestoreMatrixCheckpoint: Codable {
        let phase: String
        let beatID: String
        let interactionID: String?
        let beforeSHA256: String
        let afterSHA256: String
    }

    private struct RestoreMatrixReceipt: Codable {
        let formatVersion: Int
        let chapterID: String
        let checkpoints: [RestoreMatrixCheckpoint]
        let finalStateSHA256: String
    }

    private func traverse(restoringAfterEveryAction: Bool) throws -> TraversalResult {
        let envelope = try loadEnvelope()
        let coordinator = ChapterCoordinator(repository: envelope.repository)
        var state = try envelope.initialJourneyState()
        state = try apply(
            coordinator.beginActions(chapterID: "first-farmers", state: state),
            to: state,
            coordinator: coordinator,
            restoringAfterEveryAction: restoringAfterEveryAction
        )

        var visitedBeatIDs: [BeatID] = []
        var interactionIDs: [InteractionID] = []
        while case .chapter("first-farmers") = state.route {
            let cursor = try coordinator.currentCursor(state: state)
            XCTAssertEqual(
                state.activeChapter?.sceneVisualSnapshot?.sceneID,
                cursor.scene.id
            )
            visitedBeatIDs.append(cursor.beat.id)

            if let interaction = cursor.beat.interaction {
                interactionIDs.append(interaction.id)
                for effect in interaction.completionEffects {
                    XCTAssertFalse(state.world.appliedEffects.contains(where: { $0.id == effect.id }))
                }

                for action in try canonicalCompletionActions(for: interaction) {
                    state = try apply(
                        [.interact(spec: interaction, action: action)],
                        to: state,
                        coordinator: coordinator,
                        restoringAfterEveryAction: restoringAfterEveryAction
                    )
                }

                XCTAssertEqual(state.activeChapter?.interaction?.phase, .complete)
                for effect in interaction.completionEffects {
                    XCTAssertEqual(
                        state.world.appliedEffects.filter { $0.id == effect.id },
                        [effect]
                    )
                }
            }

            let plan = try coordinator.advanceActions(state: state)
            state = try apply(
                plan.actions,
                to: state,
                coordinator: coordinator,
                restoringAfterEveryAction: restoringAfterEveryAction
            )
        }

        return TraversalResult(
            state: state,
            visitedBeatIDs: visitedBeatIDs,
            interactionIDs: interactionIDs
        )
    }

    private func apply(
        _ actions: [JourneyAction],
        to initial: JourneyState,
        coordinator: ChapterCoordinator,
        restoringAfterEveryAction: Bool
    ) throws -> JourneyState {
        var state = initial
        let reducer = JourneyReducer()

        for action in actions {
            if case .activateScene = action,
               state.activeChapter?.sceneVisualSnapshot != nil {
                // Cold restoration may already have repaired the interrupted
                // enter-beat plan by activating this exact authored scene.
                continue
            }
            if case let .beginInteraction(spec) = action,
               state.activeChapter?.interaction?.interactionID == spec.id {
                // Cold restoration repairs an interrupted enter-beat plan by
                // beginning the authored interaction. Do not replay the stale
                // in-memory action after that repair.
                continue
            }

            let effects = reducer.reduce(state: &state, action: action)
            XCTAssertFalse(effects.contains(where: { effect in
                if case .rejected = effect { return true }
                return false
            }))

            guard restoringAfterEveryAction,
                  case .chapter("first-farmers") = state.route else {
                continue
            }
            state = try coldRestore(state, coordinator: coordinator)
        }
        return state
    }

    private func coldRestore(
        _ state: JourneyState,
        coordinator: ChapterCoordinator
    ) throws -> JourneyState {
        let bytes = try JSONEncoder().encode(SaveSnapshot(state: state))
        var restored = try JSONDecoder().decode(SaveSnapshot.self, from: bytes).state
        restored.prepareForColdRestore()

        let repair = try coordinator.resumeActions(
            chapterID: "first-farmers",
            state: restored
        )
        let reducer = JourneyReducer()
        for action in repair {
            let effects = reducer.reduce(state: &restored, action: action)
            XCTAssertFalse(effects.contains(where: { effect in
                if case .rejected = effect { return true }
                return false
            }))
        }
        _ = try coordinator.currentCursor(state: restored)
        return restored
    }

    private func restoreCheckpoint(
        phase: String,
        beatID: BeatID,
        interactionID: InteractionID?,
        state: JourneyState,
        coordinator: ChapterCoordinator
    ) throws -> (state: JourneyState, checkpoint: RestoreMatrixCheckpoint) {
        let beforeSHA256 = try digest(state)
        let restored = try coldRestore(state, coordinator: coordinator)
        let afterSHA256 = try digest(restored)
        XCTAssertEqual(restored, state, "\(phase):\(beatID)")
        XCTAssertEqual(afterSHA256, beforeSHA256, "\(phase):\(beatID)")
        return (
            restored,
            RestoreMatrixCheckpoint(
                phase: phase,
                beatID: beatID.rawValue,
                interactionID: interactionID?.rawValue,
                beforeSHA256: beforeSHA256,
                afterSHA256: afterSHA256
            )
        )
    }

    private func canonicalCompletionActions(
        for interaction: InteractionSpec
    ) throws -> [InteractionAction] {
        switch interaction.grammar {
        case let .trace(configuration):
            return configuration.anchors.map(InteractionAction.trace)

        case let .allocate(configuration):
            guard let first = configuration.destinations.first else {
                throw TraversalError.invalidInteraction(interaction.id)
            }
            let minimumTotal = configuration.destinations.reduce(0) {
                $0 + $1.minimumUnits
            }
            let surplus = configuration.totalUnits - minimumTotal
            let allocations = configuration.destinations.map { destination in
                InteractionAction.allocate(
                    destinationID: destination.id,
                    units: destination.minimumUnits + (destination.id == first.id ? surplus : 0)
                )
            }
            return allocations + [.commitAllocation]

        case let .assemble(configuration):
            var remaining = configuration.components
            var placed: Set<String> = []
            var actions: [InteractionAction] = []
            while !remaining.isEmpty {
                guard let index = remaining.firstIndex(where: {
                    Set($0.prerequisites).isSubset(of: placed)
                }) else {
                    throw TraversalError.invalidInteraction(interaction.id)
                }
                let component = remaining.remove(at: index)
                actions.append(
                    .place(componentID: component.id, slotID: component.targetSlot)
                )
                placed.insert(component.id)
            }
            return actions

        case let .transform(configuration):
            return configuration.stages.map {
                .transform(controlID: $0.controlID, amount: $0.requiredAmount)
            }

        case .pressure:
            // First Farmers deliberately contains no Pressure interaction.
            throw TraversalError.unexpectedPressure(interaction.id)
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
        let bundle = Bundle(for: FirstFarmersFullTraversalTests.self)
        let payloadURL = try XCTUnwrap(
            bundle.url(forResource: "first-farmers.content-package", withExtension: "json")
        )
        let receiptURL = try XCTUnwrap(
            bundle.url(forResource: "first-farmers.payload-receipt", withExtension: "json")
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

    private func digest(_ state: JourneyState) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return SHA256.hash(data: try encoder.encode(state))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private enum TraversalError: Error {
        case invalidInteraction(InteractionID)
        case unexpectedPressure(InteractionID)
    }

    private static let expectedBeatIDs: [BeatID] = [
        "beat-first-farmers-river-world",
        "beat-first-farmers-household-crosses",
        "beat-first-farmers-living-system",
        "beat-first-farmers-european-ground",
        "beat-first-farmers-inhabited-frontier",
        "beat-first-farmers-harvest-allocation",
        "beat-first-farmers-stored-future",
        "beat-first-farmers-gorge-contact",
        "beat-first-farmers-three-records",
        "beat-first-farmers-frontier-consequence",
        "beat-first-farmers-raise-longhouse",
        "beat-first-farmers-plot-remains",
        "beat-first-farmers-paternal-lines",
        "beat-first-farmers-more-mouths",
        "beat-first-farmers-growth-breaks",
        "beat-first-farmers-continent-remade",
        "beat-first-farmers-before-steppe",
    ]
}
#endif
