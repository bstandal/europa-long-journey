import ContentKit
import Foundation
@testable import ImmersiveRuntime
import JourneyDomain
import XCTest

final class Chapter01ExperienceModelTests: XCTestCase {
    func testApprovedFlowHasFiveCellsSixSequencesAndThirtyFourBeats() {
        XCTAssertEqual(Set(Chapter01ExperienceScript.beats.map(\.cell)).count, 5)
        XCTAssertEqual(Set(Chapter01ExperienceScript.beats.map(\.sequence)).count, 6)
        XCTAssertEqual(Chapter01ExperienceScript.beats.count, 34)
        XCTAssertEqual(
            Set(Chapter01InteractionCatalog.specs.map(\.id.rawValue)),
            Set(Chapter01Sequence.allCases.map(\.interactionID))
        )
    }

    @MainActor
    func testEverySequenceCompletesOnlyThroughItsReducerAndAppliesItsEffect()
        throws {
        for sequence in Chapter01Sequence.allCases {
            let fixture = try makeController(sequence: sequence)
            defer { fixture.cleanUp() }

            var actionCount = 0
            while fixture.controller.state.interactions[sequence.interactionID]?.phase
                != .complete,
                actionCount < 24 {
                fixture.controller.semanticStep()
                actionCount += 1
            }

            let runtime = try XCTUnwrap(
                fixture.controller.state.interactions[sequence.interactionID]
            )
            XCTAssertEqual(
                runtime.phase,
                .complete,
                "Reducer did not complete \(sequence) after \(actionCount) actions"
            )
            let expectedEffects = Chapter01InteractionCatalog.spec(for: sequence)
                .completionEffects.map { $0.id.rawValue }
            XCTAssertEqual(
                fixture.controller.state.completedEffectIDs,
                expectedEffects.sorted()
            )
            XCTAssertLessThan(actionCount, 24)
        }
    }

    @MainActor
    func testSemanticAssistanceNeverCompletesHistoricalWorkByItself() throws {
        let fixture = try makeController(
            sequence: .keepTheFutureAlive,
            assistanceTier: .semanticStep
        )
        defer { fixture.cleanUp() }
        let before = fixture.controller.state.interactions[
            Chapter01Sequence.keepTheFutureAlive.interactionID
        ]

        let directive = AdaptiveAssistancePolicy.directive(
            for: fixture.controller.state.experience.assistance,
            cue: try AdaptiveAssistanceCue("Hold the line")
        )

        XCTAssertTrue(fixture.controller.semanticStepIsAvailable)
        XCTAssertTrue(directive.offersSemanticStep)
        XCTAssertFalse(directive.automaticallyCompletesInteraction)
        XCTAssertEqual(
            fixture.controller.state.interactions[
                Chapter01Sequence.keepTheFutureAlive.interactionID
            ],
            before
        )
        XCTAssertTrue(fixture.controller.state.completedEffectIDs.isEmpty)
        XCTAssertFalse(fixture.controller.chapterIsComplete)
    }

    @MainActor
    func testDurableControllerStateRestoresWithExactDomainState() throws {
        let fixture = try makeController(sequence: .keepTheFutureAlive)
        fixture.controller.commitPrimaryManipulation(strength: 0.8)
        fixture.controller.cancelManipulation()
        fixture.controller.cancelManipulation()
        fixture.controller.cancelManipulation()
        fixture.controller.updateNarrationSampleCursor(176_401)
        let expected = fixture.controller.state
        fixture.controller.stop()

        let restored = Chapter01ExperienceController(
            storageURL: fixture.storageURL
        )
        defer {
            restored.stop()
            fixture.cleanUp()
        }

        XCTAssertEqual(restored.state, expected)
        XCTAssertEqual(restored.state.experience.sampleCursor, 176_401)
        XCTAssertEqual(restored.state.experience.assistance.missCount, 3)
        XCTAssertEqual(
            restored.state.experience.assistance.tier,
            .stabilizedInput
        )
        XCTAssertEqual(
            restored.state.experience.interactionStateReference?.interactionID
                .rawValue,
            Chapter01Sequence.keepTheFutureAlive.interactionID
        )
        XCTAssertTrue(restored.state.experience.isStructurallyValid)
    }

    @MainActor
    func testNarrationCursorResetsAtBeatBoundaryAndRejectsLateCheckpoint() throws {
        let fixture = try makeController(sequence: .keepTheFutureAlive)
        defer { fixture.cleanUp() }
        let priorBeatID = fixture.controller.currentBeat.id
        fixture.controller.updateNarrationSampleCursor(
            176_401,
            forBeatID: priorBeatID
        )

        fixture.controller.semanticStep()
        fixture.controller.advanceDirectedExperience(elapsedMillis: 1_000_000)

        XCTAssertEqual(fixture.controller.currentBeat.id, "load-under-tension")
        XCTAssertEqual(fixture.controller.state.narrationSampleCursor, 0)
        fixture.controller.updateNarrationSampleCursor(
            188_401,
            forBeatID: priorBeatID
        )
        XCTAssertEqual(fixture.controller.state.narrationSampleCursor, 0)
    }

    @MainActor
    func testDirectedRunVisitsAllThirtyFourBeatsBeforeCompletion() throws {
        let fixture = try makeController(sequence: .keepTheFutureAlive)
        defer { fixture.cleanUp() }
        var visited = Set([fixture.controller.currentBeat.id])
        var actionCount = 0

        while !fixture.controller.chapterIsComplete, actionCount < 120 {
            if fixture.controller.isTransitioning {
                for _ in 0 ..< 16 {
                    _ = fixture.controller.advanceTransitionByOneStep()
                }
            } else {
                fixture.controller.semanticStep()
                fixture.controller.advanceDirectedExperience(
                    elapsedMillis: 1_000_000
                )
                actionCount += 1
            }
            visited.insert(fixture.controller.currentBeat.id)
        }

        XCTAssertTrue(fixture.controller.chapterIsComplete)
        XCTAssertEqual(
            visited,
            Set(Chapter01ExperienceScript.beats.map(\.id))
        )
        XCTAssertEqual(
            fixture.controller.state.authoredCursorMillis,
            Chapter01ExperienceScript.authoredDurationMillis
        )
        XCTAssertEqual(
            fixture.controller.state.completedEffectIDs.count,
            Chapter01Sequence.allCases.count
        )
        XCTAssertGreaterThanOrEqual(actionCount, 34)
    }

    @MainActor
    func testDirectContactCannotCreateMoreThanEightPassiveSeconds() throws {
        let fixture = try makeController(sequence: .harvestHadToLast)
        defer { fixture.cleanUp() }
        let start = fixture.controller.state.authoredCursorMillis

        fixture.controller.transferGrain(to: "food")
        fixture.controller.advanceDirectedExperience(elapsedMillis: 60_000)

        XCTAssertEqual(
            fixture.controller.state.authoredCursorMillis - start,
            8_000
        )
        XCTAssertEqual(fixture.controller.state.engagementBudgetMillis, 0)
        XCTAssertFalse(fixture.controller.state.beatActionSatisfied)
        XCTAssertEqual(fixture.controller.currentBeat.id, "three-claims")
    }

    @MainActor
    func testCarrierTransitionRestoresAtExactDeterministicStep() throws {
        let fixture = try makeController(sequence: .keepTheFutureAlive)
        defer { fixture.cleanUp() }

        for _ in 0 ..< 4 {
            fixture.controller.semanticStep()
            fixture.controller.advanceDirectedExperience(
                elapsedMillis: 1_000_000
            )
        }
        XCTAssertTrue(fixture.controller.isTransitioning)
        for _ in 0 ..< 5 {
            XCTAssertFalse(fixture.controller.advanceTransitionByOneStep())
        }
        let expected = fixture.controller.state
        fixture.controller.stop()

        let restored = Chapter01ExperienceController(
            storageURL: fixture.storageURL
        )
        defer { restored.stop() }
        XCTAssertEqual(restored.state, expected)
        XCTAssertEqual(restored.state.experience.transition?.progress, 0.3125)
        XCTAssertEqual(restored.state.pendingBeatID, "first-furrow")
        XCTAssertEqual(restored.currentCell, .aegeanPassage)
    }

    @MainActor
    private func makeController(
        sequence: Chapter01Sequence,
        assistanceTier: Chapter01AssistanceTier = .baseline
    ) throws -> ControllerFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let storageURL = directory.appendingPathComponent("state.json")
        let interactions = Dictionary(uniqueKeysWithValues:
            Chapter01Sequence.allCases.map { sequence in
                let spec = Chapter01InteractionCatalog.spec(for: sequence)
                return (spec.id.rawValue, InteractionRuntimeState(spec: spec))
            }
        )
        let state = Chapter01DurableState(
            beatIndex: Chapter01ExperienceScript.firstBeatIndex(for: sequence),
            sequence: sequence,
            interactions: interactions,
            assistanceTier: assistanceTier
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(state).write(to: storageURL, options: .atomic)
        return ControllerFixture(
            controller: Chapter01ExperienceController(storageURL: storageURL),
            storageURL: storageURL,
            directoryURL: directory
        )
    }
}

@MainActor
private struct ControllerFixture {
    let controller: Chapter01ExperienceController
    let storageURL: URL
    let directoryURL: URL

    func cleanUp() {
        controller.stop()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
