import ContentKit
import ContentKitTestSupport
import Foundation
@testable import JourneyDomain
import XCTest

final class JourneyDomainTests: XCTestCase {
    func testWorldEffectsAreAtomicAndIdempotent() throws {
        let node = WorldEffect(
            id: "reveal-a",
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: "a",
                    kind: .city,
                    form: "city",
                    position: NormalizedPoint(x: 0.5, y: 0.5)
                )
            )
        )
        var graph = WorldGraph()
        try graph.apply(node)
        try graph.apply(node)
        XCTAssertEqual(graph.nodes.count, 1)
        XCTAssertEqual(graph.appliedEffectIDs, [node.id])

        let invalidTrace = WorldEffect(
            id: "bad-trace",
            mutation: .establishTrace(
                WorldTraceBlueprint(
                    id: "a-b",
                    kind: .road,
                    origin: "a",
                    destination: "missing"
                )
            )
        )
        let before = graph
        XCTAssertThrowsError(try graph.applyAtomically([invalidTrace]))
        XCTAssertEqual(graph, before)
    }

    func testRevealMakesAPreloadedHiddenNodeVisible() throws {
        let hidden = WorldNodeState(
            id: "hidden-city",
            kind: .city,
            form: "unlit",
            position: NormalizedPoint(x: 0.4, y: 0.4),
            visibility: .hidden,
            attributes: []
        )
        let effect = WorldEffect(
            id: "reveal-hidden-city",
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: hidden.id,
                    kind: .city,
                    form: "chartered-city",
                    position: hidden.position,
                    attributes: [NamedValue(key: "status", value: .text("revealed"))]
                )
            )
        )
        var graph = WorldGraph(nodes: [hidden])
        try graph.apply(effect)
        XCTAssertEqual(graph.node(hidden.id)?.visibility, .revealed)
        XCTAssertEqual(graph.node(hidden.id)?.form, "chartered-city")
        XCTAssertEqual(graph.appliedEffectIDs, [effect.id])
    }

    func testReusedEffectIDWithDifferentPayloadFailsClosed() throws {
        let first = Fixtures.effect
        let changed = WorldEffect(
            id: first.id,
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: "different-node",
                    kind: .city,
                    form: "different",
                    position: NormalizedPoint(x: 0.2, y: 0.2)
                )
            )
        )
        var graph = WorldGraph()
        try graph.apply(first)
        XCTAssertThrowsError(try graph.apply(changed))
        XCTAssertNil(graph.node("different-node"))
    }

    func testEveryInteractionGrammarCompletesWithItsAuthoredConsequence() throws {
        var trace = InteractionRuntimeState(spec: Fixtures.trace)
        for point in [NormalizedPoint(x: 0, y: 0), NormalizedPoint(x: 1, y: 1)] {
            _ = try InteractionReducer.reduce(state: &trace, spec: Fixtures.trace, action: .trace(point))
        }
        XCTAssertEqual(trace.phase, .complete)

        var allocate = InteractionRuntimeState(spec: Fixtures.allocate)
        _ = try InteractionReducer.reduce(
            state: &allocate,
            spec: Fixtures.allocate,
            action: .allocate(destinationID: "field", units: 3)
        )
        _ = try InteractionReducer.reduce(
            state: &allocate,
            spec: Fixtures.allocate,
            action: .allocate(destinationID: "reserve", units: 1)
        )
        _ = try InteractionReducer.reduce(
            state: &allocate,
            spec: Fixtures.allocate,
            action: .commitAllocation
        )
        XCTAssertEqual(allocate.phase, .complete)

        var assemble = InteractionRuntimeState(spec: Fixtures.assemble)
        _ = try InteractionReducer.reduce(
            state: &assemble,
            spec: Fixtures.assemble,
            action: .place(componentID: "charter", slotID: "law")
        )
        _ = try InteractionReducer.reduce(
            state: &assemble,
            spec: Fixtures.assemble,
            action: .place(componentID: "council", slotID: "office")
        )
        XCTAssertEqual(assemble.phase, .complete)

        var pressure = InteractionRuntimeState(spec: Fixtures.pressure)
        _ = try InteractionReducer.reduce(
            state: &pressure,
            spec: Fixtures.pressure,
            action: .setPressure(forceID: "defence", magnitude: 0.5)
        )
        _ = try InteractionReducer.reduce(
            state: &pressure,
            spec: Fixtures.pressure,
            action: .advancePressure(elapsedMillis: 500)
        )
        XCTAssertEqual(pressure.phase, .complete)

        var transform = InteractionRuntimeState(spec: Fixtures.transform)
        _ = try InteractionReducer.reduce(
            state: &transform,
            spec: Fixtures.transform,
            action: .transform(controlID: "heat", amount: 0.75)
        )
        _ = try InteractionReducer.reduce(
            state: &transform,
            spec: Fixtures.transform,
            action: .transform(controlID: "shape", amount: 1)
        )
        XCTAssertEqual(transform.phase, .complete)
    }

    func testResetCanClearActiveWorkButCannotUndoACompletedInteraction() throws {
        var active = InteractionRuntimeState(spec: Fixtures.allocate)
        _ = try InteractionReducer.reduce(
            state: &active,
            spec: Fixtures.allocate,
            action: .allocate(destinationID: "field", units: 2)
        )
        XCTAssertEqual(active.phase, .active)

        _ = try InteractionReducer.reduce(
            state: &active,
            spec: Fixtures.allocate,
            action: .reset
        )
        XCTAssertEqual(active, InteractionRuntimeState(spec: Fixtures.allocate))

        var journey = interactionState(for: Fixtures.allocate)
        let reducer = JourneyReducer()
        for action in [
            InteractionAction.allocate(destinationID: "field", units: 3),
            .allocate(destinationID: "reserve", units: 1),
            .commitAllocation,
        ] {
            _ = reducer.reduce(
                state: &journey,
                action: .interact(spec: Fixtures.allocate, action: action)
            )
        }
        let completed = journey
        XCTAssertEqual(completed.activeChapter?.interaction?.phase, .complete)
        XCTAssertEqual(completed.world.appliedEffects, Fixtures.allocate.completionEffects)

        let resetEffects = reducer.reduce(
            state: &journey,
            action: .interact(spec: Fixtures.allocate, action: .reset)
        )
        XCTAssertEqual(resetEffects, [.rejected("The interaction is already complete")])
        XCTAssertEqual(journey, completed)
    }

    func testTransformResetCannotUndoACrossedHistoricalStage() throws {
        var transform = InteractionRuntimeState(spec: Fixtures.transform)
        _ = try InteractionReducer.reduce(
            state: &transform,
            spec: Fixtures.transform,
            action: .transform(controlID: "heat", amount: 0.75)
        )
        _ = try InteractionReducer.reduce(
            state: &transform,
            spec: Fixtures.transform,
            action: .transform(controlID: "shape", amount: 0.4)
        )

        _ = try InteractionReducer.reduce(
            state: &transform,
            spec: Fixtures.transform,
            action: .reset
        )

        XCTAssertEqual(transform.phase, .active)
        XCTAssertEqual(
            transform.progress,
            .transform(TransformProgress(completedStageCount: 1, currentAmount: 0))
        )
    }

    func testResponsiveAudioCausalStageCannotSkipRegressOrLeadJourneyState() {
        let reducer = JourneyReducer()
        var state = interactionState(for: Fixtures.transform)
        let baseline = ResponsiveAudioProgramSnapshot(
            programID: "domain-transform-audio",
            stage: .interaction,
            interactionPhase: .waiting,
            timelineID: "domain-transform-waiting",
            cursorSample: 17_000,
            loopIteration: 2,
            causalStage: ResponsiveAudioCausalStage(completedStageCount: 0),
            durableCompletionSequence: nil
        )
        XCTAssertEqual(
            reducer.reduce(
                state: &state,
                action: .setResponsiveAudioSnapshot(baseline)
            ),
            [.checkpoint(.responsiveAudioChanged)]
        )

        _ = reducer.reduce(
            state: &state,
            action: .interact(
                spec: Fixtures.transform,
                action: .transform(controlID: "heat", amount: 0.75)
            )
        )
        var one = baselineWithCausalStage(1, from: baseline)
        XCTAssertEqual(
            reducer.reduce(state: &state, action: .setResponsiveAudioSnapshot(one)),
            [.checkpoint(.responsiveAudioChanged)]
        )

        let regressed = baselineWithCausalStage(0, from: one)
        XCTAssertEqual(
            reducer.reduce(state: &state, action: .setResponsiveAudioSnapshot(regressed)),
            [.rejected("Responsive audio stage did not match durable Transform progress")]
        )

        _ = reducer.reduce(
            state: &state,
            action: .interact(
                spec: Fixtures.transform,
                action: .transform(controlID: "shape", amount: 1)
            )
        )
        // Simulate a missing first follow-up: the Journey has crossed two
        // stages while the durable audio state still records zero.
        state.activeChapter?.responsiveAudioSnapshot = baseline
        let skipped = baselineWithCausalStage(2, from: baseline)
        XCTAssertEqual(
            reducer.reduce(state: &state, action: .setResponsiveAudioSnapshot(skipped)),
            [.rejected("Responsive audio stage cannot skip history")]
        )

        one = baselineWithCausalStage(1, from: baseline)
        state.activeChapter?.responsiveAudioSnapshot = one
        let exactFinal = ResponsiveAudioProgramSnapshot(
            programID: one.programID,
            stage: .consequence,
            interactionPhase: nil,
            timelineID: "domain-transform-consequence",
            cursorSample: 0,
            loopIteration: 0,
            causalStage: ResponsiveAudioCausalStage(completedStageCount: 2),
            durableCompletionSequence: 9
        )
        XCTAssertEqual(
            reducer.reduce(state: &state, action: .setResponsiveAudioSnapshot(exactFinal)),
            [.rejected("Audio consequence requires the durable historical consequence")],
            "The stage contract does not replace the existing completion receipt boundary"
        )
    }

    func testCompletedInteractionRejectsRepeatedActionForEveryGrammarWithoutMutation() {
        let cases: [(
            name: String,
            spec: InteractionSpec,
            completionActions: [InteractionAction],
            repeatedAction: InteractionAction
        )] = [
            (
                name: "trace",
                spec: Fixtures.trace,
                completionActions: [
                    .trace(NormalizedPoint(x: 0, y: 0)),
                    .trace(NormalizedPoint(x: 1, y: 1)),
                ],
                repeatedAction: .trace(NormalizedPoint(x: 1, y: 1))
            ),
            (
                name: "allocate",
                spec: Fixtures.allocate,
                completionActions: [
                    .allocate(destinationID: "field", units: 3),
                    .allocate(destinationID: "reserve", units: 1),
                    .commitAllocation,
                ],
                repeatedAction: .commitAllocation
            ),
            (
                name: "assemble",
                spec: Fixtures.assemble,
                completionActions: [
                    .place(componentID: "charter", slotID: "law"),
                    .place(componentID: "council", slotID: "office"),
                ],
                repeatedAction: .place(componentID: "council", slotID: "office")
            ),
            (
                name: "pressure",
                spec: Fixtures.pressure,
                completionActions: [
                    .setPressure(forceID: "defence", magnitude: 0.5),
                    .advancePressure(elapsedMillis: 500),
                ],
                repeatedAction: .advancePressure(elapsedMillis: 500)
            ),
            (
                name: "transform",
                spec: Fixtures.transform,
                completionActions: [
                    .transform(controlID: "heat", amount: 0.75),
                    .transform(controlID: "shape", amount: 1),
                ],
                repeatedAction: .transform(controlID: "shape", amount: 1)
            ),
        ]

        let reducer = JourneyReducer()
        for testCase in cases {
            var state = interactionState(for: testCase.spec)
            for action in testCase.completionActions {
                _ = reducer.reduce(
                    state: &state,
                    action: .interact(spec: testCase.spec, action: action)
                )
            }

            XCTAssertEqual(
                state.activeChapter?.interaction?.phase,
                .complete,
                testCase.name
            )
            XCTAssertEqual(
                state.world.appliedEffects,
                testCase.spec.completionEffects,
                testCase.name
            )
            let completedState = state
            let completedWorld = state.world

            let effects = reducer.reduce(
                state: &state,
                action: .interact(
                    spec: testCase.spec,
                    action: testCase.repeatedAction
                )
            )

            XCTAssertEqual(
                effects,
                [.rejected("The interaction is already complete")],
                testCase.name
            )
            XCTAssertEqual(state, completedState, testCase.name)
            XCTAssertEqual(state.world, completedWorld, testCase.name)
        }
    }

    func testJourneyHapticsUseTheSingleAuthoredSemanticVocabulary() {
        let reducer = JourneyReducer()

        var prologue = JourneyState.initial
        XCTAssertEqual(
            reducer.reduce(state: &prologue, action: .updatePrologueTrace(0.2)),
            [.haptic(.drag)]
        )
        XCTAssertEqual(
            reducer.reduce(state: &prologue, action: .completePrologue([Fixtures.effect])).first,
            .haptic(.seal)
        )

        XCTAssertEqual(
            interactionEffects(spec: Fixtures.trace, action: .begin),
            [.haptic(.contact), .checkpoint(.interactionChanged)]
        )
        XCTAssertEqual(
            interactionEffects(
                spec: Fixtures.trace,
                action: .trace(NormalizedPoint(x: 0, y: 0))
            ),
            [.haptic(.contact), .checkpoint(.interactionChanged)]
        )
        var trace = interactionState(for: Fixtures.trace)
        _ = reducer.reduce(
            state: &trace,
            action: .interact(
                spec: Fixtures.trace,
                action: .trace(NormalizedPoint(x: 0, y: 0))
            )
        )
        XCTAssertEqual(
            reducer.reduce(
                state: &trace,
                action: .interact(
                    spec: Fixtures.trace,
                    action: .trace(NormalizedPoint(x: 0.5, y: 0))
                )
            ),
            [.checkpoint(.interactionChanged)],
            "Trace resistance may select its audio bed but must not emit a resistance haptic"
        )
        XCTAssertEqual(
            reducer.reduce(
                state: &trace,
                action: .interact(
                    spec: Fixtures.trace,
                    action: .trace(NormalizedPoint(x: 0.5, y: 0.5))
                )
            ),
            [.haptic(.drag), .checkpoint(.interactionChanged)]
        )
        let traceCompletion = reducer.reduce(
            state: &trace,
            action: .interact(
                spec: Fixtures.trace,
                action: .trace(NormalizedPoint(x: 1, y: 1))
            )
        )
        XCTAssertEqual(
            traceCompletion.compactMap { effect -> HapticSemantic? in
                guard case let .haptic(semantic) = effect else { return nil }
                return semantic
            },
            [.seal],
            "The destination must seal only after the durable completion"
        )
        XCTAssertEqual(
            interactionEffects(
                spec: Fixtures.allocate,
                action: .allocate(destinationID: "field", units: 1)
            ),
            [.haptic(.transfer), .checkpoint(.interactionChanged)]
        )
        XCTAssertEqual(
            interactionEffects(
                spec: Fixtures.assemble,
                action: .place(componentID: "charter", slotID: "law")
            ),
            [.haptic(.contact), .checkpoint(.interactionChanged)]
        )
        XCTAssertEqual(
            interactionEffects(
                spec: Fixtures.pressure,
                action: .setPressure(forceID: "defence", magnitude: 0.4)
            ),
            [.haptic(.drag), .checkpoint(.interactionChanged)]
        )
        XCTAssertEqual(
            interactionEffects(
                spec: Fixtures.transform,
                action: .transform(controlID: "heat", amount: 0.4)
            ),
            [.haptic(.drag), .checkpoint(.interactionChanged)]
        )
        XCTAssertEqual(
            interactionEffects(
                spec: Fixtures.allocate,
                action: .allocate(destinationID: "field", units: 5)
            ),
            [.haptic(.resistance), .checkpoint(.interactionChanged)]
        )
        XCTAssertEqual(
            interactionEffects(spec: Fixtures.allocate, action: .reset),
            [.checkpoint(.interactionChanged)]
        )

        var pressure = interactionState(for: Fixtures.pressure)
        _ = reducer.reduce(
            state: &pressure,
            action: .interact(
                spec: Fixtures.pressure,
                action: .setPressure(forceID: "defence", magnitude: 0.5)
            )
        )
        XCTAssertEqual(
            reducer.reduce(
                state: &pressure,
                action: .interact(
                    spec: Fixtures.pressure,
                    action: .advancePressure(elapsedMillis: 250)
                )
            ),
            [.haptic(.break), .checkpoint(.interactionChanged)]
        )

        var allocation = interactionState(for: Fixtures.allocate)
        for action in [
            InteractionAction.allocate(destinationID: "field", units: 3),
            .allocate(destinationID: "reserve", units: 1),
        ] {
            _ = reducer.reduce(
                state: &allocation,
                action: .interact(spec: Fixtures.allocate, action: action)
            )
        }
        XCTAssertEqual(
            reducer.reduce(
                state: &allocation,
                action: .interact(spec: Fixtures.allocate, action: .commitAllocation)
            ).first,
            .haptic(.seal)
        )
    }

    private func interactionEffects(
        spec: InteractionSpec,
        action: InteractionAction
    ) -> [JourneyEffect] {
        var state = interactionState(for: spec)
        return JourneyReducer().reduce(
            state: &state,
            action: .interact(spec: spec, action: action)
        )
    }

    private func baselineWithCausalStage(
        _ completedStageCount: Int,
        from snapshot: ResponsiveAudioProgramSnapshot
    ) -> ResponsiveAudioProgramSnapshot {
        ResponsiveAudioProgramSnapshot(
            programID: snapshot.programID,
            stage: snapshot.stage,
            interactionPhase: snapshot.interactionPhase,
            timelineID: snapshot.timelineID,
            cursorSample: snapshot.cursorSample,
            loopIteration: snapshot.loopIteration,
            causalStage: ResponsiveAudioCausalStage(
                completedStageCount: completedStageCount
            ),
            durableCompletionSequence: snapshot.durableCompletionSequence
        )
    }

    private func interactionState(for spec: InteractionSpec) -> JourneyState {
        var state = JourneyState.initial
        let reducer = JourneyReducer()
        _ = reducer.reduce(
            state: &state,
            action: .selectChapter(
                chapterID: "haptic-test-chapter",
                packageID: "essential-free-v1",
                contentVersion: SchemaVersion(major: 1)
            )
        )
        _ = reducer.reduce(state: &state, action: .beginInteraction(spec))
        return state
    }

    func testReducerReplayIsDeterministicAndColdRestorePausesNarration() {
        let events = [
            JourneyEvent(logicalTimeMillis: 1, action: .updatePrologueTrace(0.4)),
            JourneyEvent(logicalTimeMillis: 2, action: .updatePrologueTrace(0.8)),
            JourneyEvent(logicalTimeMillis: 3, action: .completePrologue([Fixtures.effect])),
            JourneyEvent(
                logicalTimeMillis: 4,
                action: .selectChapter(
                    chapterID: "first-farmers",
                    packageID: "essential",
                    contentVersion: SchemaVersion(major: 1)
                )
            ),
            JourneyEvent(
                logicalTimeMillis: 5,
                action: .setNarration(cueID: "narration", sampleOffset: 48_123, enabled: true, playing: true)
            ),
        ]
        let reducer = JourneyReducer()
        var first = JourneyState.initial
        var second = JourneyState.initial
        for event in events {
            reducer.reduce(state: &first, event: event)
            reducer.reduce(state: &second, event: event)
        }
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.activeChapter?.narration.sampleOffset, 48_123)
        first.prepareForColdRestore()
        XCTAssertFalse(first.activeChapter?.narration.isPlaying ?? true)
        XCTAssertEqual(first.activeChapter?.narration.sampleOffset, 48_123)
    }

    func testSealedSceneActivationAndTickRequireTheExactActiveBeat() {
        let reducer = JourneyReducer()
        let firstBeat = BeatCompletionContract(
            packageID: "essential",
            contentVersion: SchemaVersion(major: 1),
            chapterID: "first-farmers",
            arcID: "first-farmers-arc-02",
            beatID: "harvest-beat",
            arcIndex: 0,
            beatIndex: 0,
            absoluteBeatIndex: 0,
            mode: .documentary(effects: [])
        )
        let firstScene = SceneActivationContract(
            packageID: "essential",
            contentVersion: SchemaVersion(major: 1),
            chapterID: "first-farmers",
            arcID: "first-farmers-arc-02",
            beatID: "harvest-beat",
            sceneID: "harvest-scene",
            arcIndex: 0,
            beatIndex: 0,
            absoluteBeatIndex: 0
        )
        let secondBeat = BeatCompletionContract(
            packageID: "essential",
            contentVersion: SchemaVersion(major: 1),
            chapterID: "first-farmers",
            arcID: "first-farmers-arc-02",
            beatID: "house-beat",
            arcIndex: 0,
            beatIndex: 1,
            absoluteBeatIndex: 1,
            mode: .documentary(effects: [])
        )
        let secondScene = SceneActivationContract(
            packageID: "essential",
            contentVersion: SchemaVersion(major: 1),
            chapterID: "first-farmers",
            arcID: "first-farmers-arc-02",
            beatID: "house-beat",
            sceneID: "house-scene",
            arcIndex: 0,
            beatIndex: 1,
            absoluteBeatIndex: 1
        )
        var state = JourneyState.initial

        XCTAssertEqual(
            reducer.reduce(
                state: &state,
                action: .activateScene(firstScene)
            ),
            [.rejected("Scene activation did not match the active authored beat")]
        )

        state = JourneyState(
            route: .chapter("first-farmers"),
            activeChapter: ChapterSession(
                chapterID: "first-farmers",
                packageID: "essential",
                contentVersion: SchemaVersion(major: 1),
                arcID: "first-farmers-arc-02",
                beatID: "harvest-beat",
                beatCompletionContract: firstBeat
            )
        )
        let firstEffects = reducer.reduce(
            state: &state,
            action: .activateScene(firstScene)
        )
        XCTAssertEqual(firstEffects, [.checkpoint(.sceneVisualChanged)])
        XCTAssertEqual(
            state.activeChapter?.sceneVisualSnapshot,
            SceneVisualSnapshot(sceneID: "harvest-scene", deterministicTick: 0)
        )

        XCTAssertEqual(
            reducer.reduce(
                state: &state,
                action: .updateSceneVisualTick(
                    contract: secondScene,
                    deterministicTick: 14_400
                )
            ),
            [.rejected("Scene tick did not match the active authored scene")]
        )
        let tickEffects = reducer.reduce(
            state: &state,
            action: .updateSceneVisualTick(
                contract: firstScene,
                deterministicTick: 14_321
            )
        )
        XCTAssertEqual(tickEffects, [.checkpoint(.sceneVisualChanged)])
        XCTAssertEqual(
            state.activeChapter?.sceneVisualSnapshot,
            SceneVisualSnapshot(sceneID: "harvest-scene", deterministicTick: 14_321)
        )

        _ = reducer.reduce(
            state: &state,
            action: .completeDocumentaryBeat(firstBeat)
        )
        _ = reducer.reduce(
            state: &state,
            action: .enterAuthoredBeat(secondBeat)
        )
        XCTAssertNil(state.activeChapter?.sceneVisualSnapshot)

        _ = reducer.reduce(
            state: &state,
            action: .activateScene(secondScene)
        )
        XCTAssertEqual(
            state.activeChapter?.sceneVisualSnapshot,
            SceneVisualSnapshot(sceneID: "house-scene", deterministicTick: 0)
        )
    }

    func testSceneVisualSnapshotJSONRoundTripPreservesFrameAndColdRestorePausesNarration() throws {
        let visualSnapshot = SceneVisualSnapshot(
            sceneID: "harvest-scene",
            deterministicTick: 9_876_543
        )
        let state = JourneyState(
            route: .chapter("first-farmers"),
            activeChapter: ChapterSession(
                chapterID: "first-farmers",
                packageID: "essential",
                contentVersion: SchemaVersion(major: 1),
                arcID: "first-farmers-arc-02",
                beatID: "harvest-beat",
                sceneVisualSnapshot: visualSnapshot,
                narration: NarrationCursor(
                    cueID: "harvest-narration",
                    sampleOffset: 48_123,
                    isEnabled: true,
                    isPlaying: true
                )
            )
        )

        let encodedVisual = try JSONEncoder().encode(visualSnapshot)
        let visualObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedVisual) as? [String: Any]
        )
        XCTAssertEqual(
            Set(visualObject.keys),
            Set(["formatVersion", "sceneID", "deterministicTick"])
        )
        XCTAssertEqual(visualSnapshot.formatVersion, SceneVisualSnapshot.currentFormatVersion)

        let encodedSave = try JSONEncoder().encode(SaveSnapshot(state: state))
        let decodedSave = try JSONDecoder().decode(SaveSnapshot.self, from: encodedSave)
        var coldState = decodedSave.state
        coldState.prepareForColdRestore()

        XCTAssertEqual(coldState.activeChapter?.sceneVisualSnapshot, visualSnapshot)
        XCTAssertEqual(coldState.activeChapter?.narration.sampleOffset, 48_123)
        XCTAssertTrue(coldState.activeChapter?.narration.isEnabled ?? false)
        XCTAssertFalse(coldState.activeChapter?.narration.isPlaying ?? true)
    }

    func testIndependentChapterSessionsResumeWithoutOverwritingOneAnother() {
        let reducer = JourneyReducer()
        var state = JourneyState.initial

        reducer.reduce(
            state: &state,
            action: .beginChapter(
                chapterID: "first-farmers",
                packageID: "essential",
                contentVersion: SchemaVersion(major: 1),
                arcID: "farmers-arc",
                beatID: "harvest"
            )
        )
        reducer.reduce(
            state: &state,
            action: .setNarration(
                cueID: "harvest-voice",
                sampleOffset: 48_123,
                enabled: true,
                playing: true
            )
        )
        reducer.reduce(
            state: &state,
            action: .completeBeat(arcID: "farmers-arc", beatID: "harvest")
        )
        reducer.reduce(state: &state, action: .suspendChapter(atEpochMillis: 1_000))
        reducer.reduce(state: &state, action: .showWorld)

        reducer.reduce(
            state: &state,
            action: .beginChapter(
                chapterID: "european-world",
                packageID: "essential",
                contentVersion: SchemaVersion(major: 1),
                arcID: "world-arc",
                beatID: "cable"
            )
        )
        reducer.reduce(state: &state, action: .setCameraAnchor(0.72))
        reducer.reduce(state: &state, action: .showWorld)
        reducer.reduce(
            state: &state,
            action: .selectChapter(
                chapterID: "first-farmers",
                packageID: "essential",
                contentVersion: SchemaVersion(major: 1)
            )
        )

        XCTAssertEqual(state.chapterSessions.count, 2)
        XCTAssertEqual(state.activeChapter?.beatID, "harvest")
        XCTAssertEqual(state.activeChapter?.narration.sampleOffset, 48_123)
        XCTAssertEqual(state.activeChapter?.completedBeatIDs, ["harvest"])
        XCTAssertEqual(state.activeChapter?.lastVisitedAtEpochMillis, 1_000)
        XCTAssertEqual(state.chapterSession("european-world")?.cameraAnchor, 0.72)
        XCTAssertEqual(state.mostRecentlyVisitedChapterID, "first-farmers")
    }

    func testSavedSessionBlocksPackageVersionChangeUntilMigrated() {
        let reducer = JourneyReducer()
        var state = JourneyState(
            chapterSessions: [
                ChapterSession(
                    chapterID: "first-farmers",
                    packageID: "essential",
                    contentVersion: SchemaVersion(major: 1)
                ),
            ]
        )

        let effects = reducer.reduce(
            state: &state,
            action: .installContent(
                packageID: "essential",
                version: SchemaVersion(major: 2)
            )
        )

        XCTAssertEqual(
            effects,
            [.rejected("Active content must be migrated before package activation")]
        )
        XCTAssertTrue(state.installedContent.isEmpty)
    }

    func testLegacySingleSessionStateMigratesIntoVersionedSessionCollection() throws {
        let session = ChapterSession(
            chapterID: "first-farmers",
            packageID: "essential",
            contentVersion: SchemaVersion(major: 1),
            arcID: "farmers-arc",
            beatID: "harvest"
        )
        let current = JourneyState(
            route: .chapter("first-farmers"),
            activeChapter: session
        )
        let currentData = try JSONEncoder().encode(current)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        let sessions = try XCTUnwrap(object.removeValue(forKey: "chapterSessions") as? [Any])
        object["activeChapter"] = try XCTUnwrap(sessions.first)
        object.removeValue(forKey: "stateSchemaVersion")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let migrated = try JSONDecoder().decode(JourneyState.self, from: legacyData)

        XCTAssertEqual(migrated.stateSchemaVersion, JourneyState.currentStateSchemaVersion)
        XCTAssertEqual(migrated.chapterSessions, [session])
        XCTAssertEqual(migrated.activeChapter, session)
        let migratedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as? [String: Any]
        )
        XCTAssertEqual(
            migratedObject["stateSchemaVersion"] as? Int,
            JourneyState.currentStateSchemaVersion
        )
        XCTAssertNil(migratedObject["activeChapter"])
    }

    func testReorientationIsOptionalAndNeverMovesTheCausalCursor() {
        let session = ChapterSession(
            chapterID: "first-farmers",
            packageID: "essential",
            contentVersion: SchemaVersion(major: 1),
            arcID: "farmers-arc",
            beatID: "harvest",
            completedBeatIDs: ["arrival"],
            lastVisitedAtEpochMillis: 1_000
        )
        let policy = ChapterReorientationPolicy(minimumAbsenceMillis: 10_000)

        XCTAssertNil(policy.context(for: session, nowEpochMillis: 10_999))
        let context = policy.context(for: session, nowEpochMillis: 11_000)
        XCTAssertEqual(
            context,
            ChapterReorientationContext(
                chapterID: "first-farmers",
                arcID: "farmers-arc",
                beatID: "harvest",
                absenceMillis: 10_000
            )
        )
        XCTAssertEqual(session.beatID, "harvest")
        XCTAssertEqual(session.completedBeatIDs, ["arrival"])
    }
}

enum Fixtures {
    static let effect = WorldEffect(
        id: "effect",
        mutation: .revealNode(
            WorldNodeBlueprint(
                id: "world-node",
                kind: .institution,
                form: "formed",
                position: NormalizedPoint(x: 0.5, y: 0.5)
            )
        )
    )

    static func interaction(id: InteractionID, grammar: InteractionSpec.Grammar) -> InteractionSpec {
        InteractionSpec(
            id: id,
            prompt: "Act on the mechanism",
            grammar: grammar,
            completionEffects: [effect],
            accessibilityID: AccessibilityID("access-\(id.rawValue)")
        )
    }

    static let trace = interaction(
        id: "trace",
        grammar: .trace(
            TraceInteractionSpec(
                anchors: [NormalizedPoint(x: 0, y: 0), NormalizedPoint(x: 1, y: 1)],
                tolerance: 0.1
            )
        )
    )
    static let allocate = interaction(
        id: "allocate",
        grammar: .allocate(
            AllocateInteractionSpec(
                resourceName: "stores",
                totalUnits: 4,
                destinations: [
                    AllocationDestination(id: "field", minimumUnits: 1),
                    AllocationDestination(id: "reserve", minimumUnits: 1),
                ]
            )
        )
    )
    static let assemble = interaction(
        id: "assemble",
        grammar: .assemble(
            AssembleInteractionSpec(
                components: [
                    AssemblyComponent(id: "charter", targetSlot: "law"),
                    AssemblyComponent(id: "council", targetSlot: "office", prerequisites: ["charter"]),
                ]
            )
        )
    )
    static let pressure = interaction(
        id: "pressure",
        grammar: .pressure(
            PressureInteractionSpec(
                forces: [
                    PressureForce(id: "attack", direction: -1, initialMagnitude: 0.5, userControllable: false),
                    PressureForce(id: "defence", direction: 1, initialMagnitude: 0, userControllable: true),
                ],
                stableRange: -0.05 ... 0.05,
                requiredHoldMillis: 500
            )
        )
    )
    static let transform = interaction(
        id: "transform",
        grammar: .transform(
            TransformInteractionSpec(
                stages: [
                    TransformationStage(id: "fire", controlID: "heat", requiredAmount: 0.7),
                    TransformationStage(id: "form", controlID: "shape", requiredAmount: 0.9),
                ]
            )
        )
    )
}
