import Foundation
@testable import ImmersiveRuntime
import JourneyDomain
import XCTest

/// Release-blocking invariants for the complete Chapter 01 interaction path.
/// These tests intentionally exercise the durable authority without relying
/// on RealityKit timing, hit testing or animation completion.
final class Chapter01ExperienceAcceptanceTests: XCTestCase {
    @MainActor
    func testEveryInputRouteProducesTheSameHistoricalEffects() throws {
        for sequence in Chapter01Sequence.allCases {
            let direct = try makeController(sequence: sequence)
            defer { direct.cleanUp() }
            completeInteractionDirectly(direct.controller, sequence: sequence)

            let voiceOver = try makeController(sequence: sequence)
            defer { voiceOver.cleanUp() }
            completeInteractionSemantically(voiceOver.controller, sequence: sequence)

            let hesitant = try makeController(sequence: sequence)
            defer { hesitant.cleanUp() }
            hesitant.controller.cancelManipulation()
            hesitant.controller.cancelManipulation()
            hesitant.controller.cancelManipulation()
            completeInteractionDirectly(hesitant.controller, sequence: sequence)

            let expected = Chapter01InteractionCatalog.spec(for: sequence)
                .completionEffects.map { $0.id.rawValue }.sorted()
            XCTAssertEqual(direct.controller.state.completedEffectIDs, expected)
            XCTAssertEqual(voiceOver.controller.state.completedEffectIDs, expected)
            XCTAssertEqual(hesitant.controller.state.completedEffectIDs, expected)
            XCTAssertFalse(direct.controller.chapterIsComplete)
            XCTAssertFalse(voiceOver.controller.chapterIsComplete)
            XCTAssertFalse(hesitant.controller.chapterIsComplete)
        }
    }

    @MainActor
    func testHardKillRestoresBeforeAndAfterEveryDurableMutation() throws {
        let fixture = try makeController(sequence: .keepTheFutureAlive)
        defer { fixture.cleanUp() }
        var controller = fixture.controller
        var mutationCount = 0

        while !controller.chapterIsComplete, mutationCount < 240 {
            controller = try restoreExactly(controller, at: fixture.storageURL)

            if controller.isTransitioning {
                _ = controller.advanceTransitionByOneStep()
            } else {
                controller.semanticStep()
                controller = try restoreExactly(controller, at: fixture.storageURL)
                controller.advanceDirectedExperience(elapsedMillis: 1_000_000)
            }

            controller = try restoreExactly(controller, at: fixture.storageURL)
            mutationCount += 1
        }

        XCTAssertTrue(controller.chapterIsComplete)
        XCTAssertEqual(
            controller.state.completedEffectIDs.count,
            Chapter01Sequence.allCases.count
        )
        XCTAssertEqual(
            controller.state.authoredCursorMillis,
            Chapter01ExperienceScript.authoredDurationMillis
        )
        XCTAssertLessThan(mutationCount, 240)
    }

    @MainActor
    func testSameInputLogProducesByteIdenticalDomainCameraAudioAndRenderProjection()
        throws {
        let first = try makeController(sequence: .keepTheFutureAlive)
        defer { first.cleanUp() }
        let second = try makeController(sequence: .keepTheFutureAlive)
        defer { second.cleanUp() }

        for controller in [first.controller, second.controller] {
            controller.commitPrimaryManipulation(strength: 0.72)
            controller.cancelManipulation()
            controller.commitPrimaryManipulation(strength: 0.91)
            controller.updateNarrationSampleCursor(
                38_401,
                forBeatID: controller.currentBeat.id
            )
            controller.advanceDirectedExperience(elapsedMillis: 1_750)
        }

        XCTAssertEqual(first.controller.state, second.controller.state)
        XCTAssertEqual(
            try canonicalBytes(first.controller.state),
            try canonicalBytes(second.controller.state)
        )
        XCTAssertEqual(
            first.controller.state.experience.camera,
            second.controller.state.experience.camera
        )
        XCTAssertEqual(
            first.controller.state.experience.materialChannels,
            second.controller.state.experience.materialChannels
        )
        XCTAssertEqual(
            first.controller.state.experience.sampleCursor,
            second.controller.state.experience.sampleCursor
        )
    }

    @MainActor
    private func completeInteractionDirectly(
        _ controller: Chapter01ExperienceController,
        sequence: Chapter01Sequence
    ) {
        var attempts = 0
        while controller.state.interactions[sequence.interactionID]?.phase
            != .complete,
            attempts < 24 {
            switch sequence {
            case .harvestHadToLast:
                let order = ["food", "food", "reserve", "seed", "seed", "reserve"]
                controller.transferGrain(to: order[min(attempts, order.count - 1)])
            default:
                controller.commitPrimaryManipulation(strength: 1)
            }
            attempts += 1
        }
        XCTAssertLessThan(attempts, 24)
    }

    @MainActor
    private func completeInteractionSemantically(
        _ controller: Chapter01ExperienceController,
        sequence: Chapter01Sequence
    ) {
        var attempts = 0
        while controller.state.interactions[sequence.interactionID]?.phase
            != .complete,
            attempts < 24 {
            // This is the exact action invoked by the world's named
            // accessibility action and by the final adaptive tap/step affordance.
            controller.semanticStep()
            attempts += 1
        }
        XCTAssertLessThan(attempts, 24)
    }

    @MainActor
    private func restoreExactly(
        _ controller: Chapter01ExperienceController,
        at storageURL: URL
    ) throws -> Chapter01ExperienceController {
        let expected = controller.state
        controller.stop()
        let restored = Chapter01ExperienceController(storageURL: storageURL)
        XCTAssertEqual(restored.state, expected)
        return restored
    }

    @MainActor
    private func makeController(
        sequence: Chapter01Sequence
    ) throws -> AcceptanceControllerFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let storageURL = directory.appendingPathComponent("state.json")
        let interactions = Dictionary(uniqueKeysWithValues:
            Chapter01Sequence.allCases.map { candidate in
                let spec = Chapter01InteractionCatalog.spec(for: candidate)
                return (spec.id.rawValue, InteractionRuntimeState(spec: spec))
            }
        )
        let state = Chapter01DurableState(
            beatIndex: Chapter01ExperienceScript.firstBeatIndex(for: sequence),
            sequence: sequence,
            interactions: interactions
        )
        try canonicalBytes(state).write(to: storageURL, options: .atomic)
        return AcceptanceControllerFixture(
            controller: Chapter01ExperienceController(storageURL: storageURL),
            storageURL: storageURL,
            directoryURL: directory
        )
    }

    private func canonicalBytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

@MainActor
private struct AcceptanceControllerFixture {
    let controller: Chapter01ExperienceController
    let storageURL: URL
    let directoryURL: URL

    func cleanUp() {
        controller.stop()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
