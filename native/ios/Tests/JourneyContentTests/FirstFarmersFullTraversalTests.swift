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

    private struct TraversalResult {
        let state: JourneyState
        let visitedBeatIDs: [BeatID]
        let interactionIDs: [InteractionID]
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
