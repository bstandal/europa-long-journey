import ContentKit
import DramaticAudio
import ExperiencePreferences
import Foundation
import JourneyContent
import JourneyDomain
import ProgressStore
import XCTest

final class ResponsiveAudioProgramRuntimeTests: XCTestCase {
    func testProgramValidationRequiresCompletePhaseMapAndRejectsNarrationInLoop() throws {
        let timelines = Self.timelines()
        let incomplete = ResponsiveAudioProgramSpec(
            id: "harvest-responsive-audio",
            scope: Self.scope,
            approachTimelineID: "approach",
            interactionBeds: Array(Self.beds.prefix(2)),
            consequenceTimelineID: "consequence",
            exitPolicy: .boundedFade(durationSamples: 480)
        )
        XCTAssertThrowsError(try incomplete.validate(timelines: timelines))

        let waiting = try XCTUnwrap(timelines.first { $0.id == "waiting-bed" })
        let narrationEvent = AudioEvent(
            cueID: "illegal-loop-narration",
            role: .narration,
            startSample: 0,
            durationSamples: 48_000,
            assetPath: "audio/illegal-loop-narration.wav",
            gain: 1,
            narrationBinding: Self.narrationBinding
        )
        let unsafeWaiting = AudioTimeline(
            id: waiting.id,
            sampleRate: waiting.sampleRate,
            events: waiting.events + [narrationEvent],
            haptics: waiting.haptics
        )
        XCTAssertThrowsError(
            try Self.program.validate(
                timelines: timelines.filter { $0.id != waiting.id } + [unsafeWaiting]
            )
        )

        let hapticWaiting = AudioTimeline(
            id: waiting.id,
            sampleRate: waiting.sampleRate,
            events: waiting.events,
            haptics: [
                HapticEvent(sample: 10, kind: .contact, intensity: 0.5, sharpness: 0.5),
            ]
        )
        XCTAssertThrowsError(
            try Self.program.validate(
                timelines: timelines.filter { $0.id != waiting.id } + [hapticWaiting]
            )
        )
    }

    func testLoopPhaseStatesMustMatchRolesAndShareExactDuration() throws {
        let timelines = Self.timelines()
        let mismatchedBeds = Self.beds.map { bed in
            guard bed.phase == .waiting else { return bed }
            return ResponsiveInteractionAudioBedSpec(
                phase: bed.phase,
                timelineID: bed.timelineID,
                layerStates: ResponsiveAudioLayerStateSelection(
                    scoreStateID: nil,
                    soundscapeStateID: "field-waiting"
                )
            )
        }
        let mismatchedProgram = ResponsiveAudioProgramSpec(
            id: Self.program.id,
            scope: Self.scope,
            approachTimelineID: Self.program.approachTimelineID,
            interactionBeds: mismatchedBeds,
            consequenceTimelineID: Self.program.consequenceTimelineID,
            exitPolicy: Self.program.exitPolicy
        )
        XCTAssertThrowsError(try mismatchedProgram.validate(timelines: timelines))

        let resistance = try XCTUnwrap(timelines.first { $0.id == "resistance-bed" })
        let shortResistance = AudioTimeline(
            id: resistance.id,
            sampleRate: resistance.sampleRate,
            events: resistance.events.map { event in
                AudioEvent(
                    cueID: event.cueID,
                    role: event.role,
                    startSample: event.startSample,
                    durationSamples: 48_000,
                    assetPath: event.assetPath,
                    gain: event.gain,
                    narrationBinding: event.narrationBinding
                )
            },
            haptics: []
        )
        XCTAssertThrowsError(
            try Self.program.validate(
                timelines: timelines.filter { $0.id != resistance.id } + [shortResistance]
            )
        )
    }

    func testCausalMixSchemaIsExplicitLegacyCompatibleAndFailClosed() throws {
        XCTAssertNoThrow(
            try Self.causalProgram.validate(timelines: Self.causalTimelines())
        )
        let phaseOnlyWire = try XCTUnwrap(
            String(data: JSONEncoder().encode(Self.program), encoding: .utf8)
        )
        XCTAssertFalse(phaseOnlyWire.contains("causalMix"))
        XCTAssertNil(
            try JSONDecoder().decode(
                ResponsiveAudioProgramSpec.self,
                from: JSONEncoder().encode(Self.program)
            ).causalMix
        )

        let waiting = try XCTUnwrap(
            Self.causalTimelines().first { $0.id == "causal-waiting-bed" }
        )
        let conflictingStateZero = AudioTimeline(
            id: waiting.id,
            sampleRate: waiting.sampleRate,
            events: waiting.events.map { event in
                guard event.cueID == "waiting-river" else { return event }
                return AudioEvent(
                    cueID: event.cueID,
                    role: event.role,
                    startSample: event.startSample,
                    durationSamples: event.durationSamples,
                    assetPath: event.assetPath,
                    gain: 0.79
                )
            },
            haptics: []
        )
        XCTAssertThrowsError(
            try Self.causalProgram.validate(
                timelines: Self.causalTimelines().filter {
                    $0.id != waiting.id
                } + [conflictingStateZero]
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("state-zero gain"))
        }

        let incompleteMix = ResponsiveAudioCausalMixSpec(
            rampDurationSamples: Self.causalMix.rampDurationSamples,
            layers: Self.causalMix.layers,
            states: Array(Self.causalMix.states.prefix(2))
        )
        let incompleteProgram = ResponsiveAudioProgramSpec(
            id: Self.causalProgram.id,
            scope: Self.scope,
            approachTimelineID: Self.causalProgram.approachTimelineID,
            interactionBeds: Self.causalBeds,
            consequenceTimelineID: Self.causalProgram.consequenceTimelineID,
            exitPolicy: Self.causalProgram.exitPolicy,
            causalMix: incompleteMix
        )
        XCTAssertThrowsError(
            try incompleteProgram.validateCausalMixBinding(
                to: Self.multistageInteractionSpec
            )
        )
        XCTAssertThrowsError(
            try Self.causalProgram.validateCausalMixBinding(
                to: Self.interactionSpecReplacingGrammarWithAllocate
            )
        )
        XCTAssertNoThrow(
            try Self.causalProgram.validateCausalMixBinding(
                to: Self.multistageInteractionSpec
            )
        )
    }

    func testCausalPlaybackPlanResolvesMissingStageAsZeroAndRestoresExactTarget() throws {
        var runtime = try ResponsiveAudioProgramRuntime(
            program: Self.causalProgram,
            timelines: Self.causalTimelines()
        )
        try runtime.resume()
        try runtime.advance(bySamples: 48_000 + 17_000)
        _ = runtime.pause()

        let zeroPlayback = try XCTUnwrap(
            runtime.makePlaybackPlan(assetMetadata: Self.causalAssetMetadata)
        )
        let stateZero = try XCTUnwrap(zeroPlayback.causalMix)
        XCTAssertNil(runtime.causalStage)
        XCTAssertEqual(stateZero.completedStageCount, 0)
        XCTAssertEqual(stateZero.rampDurationSamples, 4_800)
        XCTAssertEqual(stateZero.layers.map(\.targetGain), [0.8, 0])

        _ = try runtime.selectCausalStage(
            ResponsiveAudioCausalStage(completedStageCount: 1)
        )
        try runtime.selectInteractionPhase(.resistance)
        let onePlayback = try XCTUnwrap(
            runtime.makePlaybackPlan(assetMetadata: Self.causalAssetMetadata)
        )
        let stateOne = try XCTUnwrap(onePlayback.causalMix)
        XCTAssertEqual(stateOne.completedStageCount, 1)
        XCTAssertEqual(stateOne.layers.map(\.cueID), [
            "resistance-river", "resistance-work",
        ])
        XCTAssertEqual(stateOne.layers.map(\.targetGain), [0.8, 0.35])

        let restored = try ResponsiveAudioProgramRuntime(
            program: Self.causalProgram,
            timelines: Self.causalTimelines(),
            restoring: runtime.snapshot()
        )
        let restoredPlayback = try XCTUnwrap(
            restored.makePlaybackPlan(assetMetadata: Self.causalAssetMetadata)
        )
        let restoredPlan = try XCTUnwrap(restoredPlayback.causalMix)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertEqual(restored.cursorSample, 17_000)
        XCTAssertEqual(restoredPlan, stateOne)
    }

    func testApproachEntersIndefiniteWaitingBedWithoutLoopingNarration() throws {
        var runtime = try Self.runtime()
        try runtime.resume()
        try runtime.advance(bySamples: 144_000 + 5 * 96_000 + 12_000)

        XCTAssertEqual(runtime.stage, .interaction)
        XCTAssertEqual(runtime.interactionPhase, .waiting)
        XCTAssertEqual(runtime.timelineID, "waiting-bed")
        XCTAssertEqual(runtime.loopIteration, 5)
        XCTAssertEqual(runtime.cursorSample, 12_000)

        let plan = try XCTUnwrap(
            runtime.makePlaybackPlan(assetMetadata: Self.assetMetadata)
        )
        XCTAssertFalse(plan.timelinePlan.audioSlices.contains { $0.role == .narration })
        XCTAssertEqual(
            plan.repetition,
            .loop(iteration: 5, durationSamples: 96_000)
        )
        XCTAssertEqual(plan.layerStates, Self.beds[0].layerStates)
    }

    func testInteractionPhaseSelectionPreservesSampleAndIteration() throws {
        var runtime = try Self.runtime()
        try runtime.resume()
        try runtime.advance(bySamples: 144_000 + 2 * 96_000 + 36_000)
        let before = runtime.snapshot()

        try runtime.selectInteractionPhase(.resistance)

        XCTAssertEqual(runtime.stage, .interaction)
        XCTAssertEqual(runtime.interactionPhase, .resistance)
        XCTAssertEqual(runtime.timelineID, "resistance-bed")
        XCTAssertEqual(runtime.cursorSample, before.cursorSample)
        XCTAssertEqual(runtime.loopIteration, before.loopIteration)
        let plan = try XCTUnwrap(
            runtime.makePlaybackPlan(assetMetadata: Self.assetMetadata)
        )
        XCTAssertEqual(
            plan.layerStates,
            ResponsiveAudioLayerStateSelection(
                scoreStateID: "grain-tension",
                soundscapeStateID: "field-resistance"
            )
        )
    }

    func testCausalStageIsMonotonicAndPhaseChangesKeepItsExactClock() throws {
        var runtime = try Self.runtime()
        try runtime.resume()
        try runtime.advance(bySamples: 144_000 + 2 * 96_000 + 36_000)
        _ = runtime.pause()

        XCTAssertTrue(
            try runtime.selectCausalStage(
                ResponsiveAudioCausalStage(completedStageCount: 0)
            )
        )
        let beforeThreshold = runtime.snapshot()
        XCTAssertTrue(
            try runtime.selectCausalStage(
                ResponsiveAudioCausalStage(completedStageCount: 1)
            )
        )
        XCTAssertEqual(runtime.cursorSample, beforeThreshold.cursorSample)
        XCTAssertEqual(runtime.loopIteration, beforeThreshold.loopIteration)
        XCTAssertEqual(runtime.interactionPhase, beforeThreshold.interactionPhase)

        try runtime.selectInteractionPhase(.resistance)
        XCTAssertEqual(runtime.causalStage?.completedStageCount, 1)
        XCTAssertEqual(runtime.cursorSample, beforeThreshold.cursorSample)
        XCTAssertEqual(runtime.loopIteration, beforeThreshold.loopIteration)

        XCTAssertThrowsError(
            try runtime.selectCausalStage(
                ResponsiveAudioCausalStage(completedStageCount: 3)
            )
        ) { error in
            XCTAssertEqual(
                error as? ResponsiveAudioRuntimeError,
                .causalStageSkip(current: 1, proposed: 3)
            )
        }
        XCTAssertThrowsError(
            try runtime.selectCausalStage(
                ResponsiveAudioCausalStage(completedStageCount: 0)
            )
        ) { error in
            XCTAssertEqual(
                error as? ResponsiveAudioRuntimeError,
                .causalStageRegression(current: 1, proposed: 0)
            )
        }
    }

    func testColdRestorePreservesExactAuthoredSilenceAndReturnsPaused() throws {
        var runtime = try Self.runtime()
        try runtime.resume()
        try runtime.advance(bySamples: 144_000 + 48_000)
        let snapshot = runtime.pause()

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(
            ResponsiveAudioProgramSnapshot.self,
            from: encoded
        )
        var restored = try ResponsiveAudioProgramRuntime(
            program: Self.program,
            timelines: Self.timelines(),
            restoring: decoded
        )

        XCTAssertFalse(restored.isPlaying)
        XCTAssertEqual(restored.cursorSample, 48_000)
        XCTAssertEqual(restored.loopIteration, 0)
        XCTAssertThrowsError(try restored.advance(bySamples: 1)) { error in
            XCTAssertEqual(error as? ResponsiveAudioRuntimeError, .playbackPaused)
        }
        let plan = try XCTUnwrap(
            restored.makePlaybackPlan(assetMetadata: Self.assetMetadata)
        )
        XCTAssertTrue(plan.isInsideAuthoredSilence)
        XCTAssertEqual(plan.authoredSilenceCueIDs, ["waiting-silence"])
        XCTAssertTrue(plan.timelinePlan.audioSlices.allSatisfy {
            $0.timelineStartOffset > 0
        })

        try restored.resume()
        try restored.advance(bySamples: 1)
        XCTAssertEqual(restored.cursorSample, 48_001)
    }

    func testColdRestorePreservesCausalStagePhaseSampleAndPausedIntent() throws {
        var runtime = try Self.runtime()
        try runtime.resume()
        try runtime.advance(bySamples: 144_000 + 3 * 96_000 + 27_000)
        _ = runtime.pause()
        _ = try runtime.selectCausalStage(
            ResponsiveAudioCausalStage(completedStageCount: 1)
        )
        try runtime.selectInteractionPhase(.engaged)
        let saved = runtime.snapshot()

        let restored = try ResponsiveAudioProgramRuntime(
            program: Self.program,
            timelines: Self.timelines(),
            restoring: try JSONDecoder().decode(
                ResponsiveAudioProgramSnapshot.self,
                from: JSONEncoder().encode(saved)
            )
        )

        XCTAssertFalse(restored.isPlaying)
        XCTAssertEqual(restored.stage, .interaction)
        XCTAssertEqual(restored.interactionPhase, .engaged)
        XCTAssertEqual(restored.causalStage?.completedStageCount, 1)
        XCTAssertEqual(restored.cursorSample, 27_000)
        XCTAssertEqual(restored.loopIteration, 3)
    }

    func testLegacyPhaseOnlySnapshotDecodesWithoutCausalStage() throws {
        let legacyJSON = """
        {
          "formatVersion": 1,
          "programID": "harvest-responsive-audio",
          "stage": "interaction",
          "interactionPhase": "waiting",
          "timelineID": "waiting-bed",
          "cursorSample": 12000,
          "loopIteration": 2,
          "durableCompletionSequence": null
        }
        """
        let decoded = try JSONDecoder().decode(
            ResponsiveAudioProgramSnapshot.self,
            from: Data(legacyJSON.utf8)
        )
        let restored = try ResponsiveAudioProgramRuntime(
            program: Self.program,
            timelines: Self.timelines(),
            restoring: decoded
        )

        XCTAssertNil(decoded.causalStage)
        XCTAssertNil(restored.causalStage)
        XCTAssertEqual(restored.cursorSample, 12_000)
        XCTAssertEqual(restored.loopIteration, 2)
        XCTAssertFalse(restored.isPlaying)
    }

    func testSnapshotRestoreFailsClosedForWrongTimelineOrTerminalBoundary() throws {
        let wrongTimeline = ResponsiveAudioProgramSnapshot(
            programID: Self.program.id,
            stage: .interaction,
            interactionPhase: .waiting,
            timelineID: "engaged-bed",
            cursorSample: 10,
            loopIteration: 0,
            durableCompletionSequence: nil
        )
        XCTAssertThrowsError(
            try ResponsiveAudioProgramRuntime(
                program: Self.program,
                timelines: Self.timelines(),
                restoring: wrongTimeline
            )
        )

        let uncommittedConsequence = ResponsiveAudioProgramSnapshot(
            programID: Self.program.id,
            stage: .consequence,
            interactionPhase: nil,
            timelineID: "consequence",
            cursorSample: 0,
            loopIteration: 0,
            durableCompletionSequence: nil
        )
        XCTAssertThrowsError(
            try ResponsiveAudioProgramRuntime(
                program: Self.program,
                timelines: Self.timelines(),
                restoring: uncommittedConsequence
            )
        )
    }

    func testOnlyActualDurableCompletionReleasesConsequence() async throws {
        let commit = try await Self.makeCompletionCommit(scope: Self.scope)
        let receipt = try DurableInteractionAudioCompletionReceipt.make(from: commit)

        var runtime = try Self.runtimeAtInteraction()
        try runtime.accept(receipt)

        XCTAssertEqual(runtime.stage, .consequence)
        XCTAssertEqual(runtime.timelineID, "consequence")
        XCTAssertEqual(runtime.cursorSample, 0)
        XCTAssertEqual(runtime.durableCompletionSequence, commit.sequence)

        try runtime.resume()
        try runtime.advance(bySamples: 96_000)
        XCTAssertEqual(runtime.stage, .completed)
        XCTAssertEqual(runtime.cursorSample, 96_000)
        XCTAssertFalse(runtime.isPlaying)
        XCTAssertNil(try runtime.makePlaybackPlan(assetMetadata: Self.assetMetadata))

        XCTAssertThrowsError(
            try ResponsiveAudioProgramRuntime(
                program: Self.program,
                timelines: Self.timelines(),
                restoring: runtime.snapshot()
            )
        )
        let coldReceipt = try DurableInteractionAudioCompletionReceipt.makeForRestore(
            sequence: commit.sequence,
            scope: Self.scope,
            interactionSpec: Self.interactionSpec,
            restoration: JourneyRestoration(
                state: commit.state,
                replayedEventCount: 1,
                lastSequence: commit.sequence
            )
        )
        let restored = try ResponsiveAudioProgramRuntime(
            program: Self.program,
            timelines: Self.timelines(),
            restoring: runtime.snapshot(),
            durableCompletionReceipt: coldReceipt
        )
        XCTAssertEqual(restored.stage, .completed)
        XCTAssertFalse(restored.isPlaying)
    }

    func testNonCompletingCommitCannotCreateReceiptAndRepeatedCompletionCannotCommit() async throws {
        let spec = Self.interactionSpec
        let committer = Self.committer(scope: Self.scope, spec: spec)
        let began = try await committer.commit(.interact(spec: spec, action: .begin))
        XCTAssertThrowsError(
            try DurableInteractionAudioCompletionReceipt.make(from: began)
        ) { error in
            XCTAssertEqual(
                error as? DurableInteractionAudioCompletionError,
                .missingDurableConsequence
            )
        }

        let completed = try await committer.commit(
            .interact(
                spec: spec,
                action: .transform(controlID: "press-grain", amount: 1)
            )
        )
        _ = try DurableInteractionAudioCompletionReceipt.make(from: completed)

        let stateBeforeRepeatedAction = await committer.currentCommittedState()
        do {
            _ = try await committer.commit(
                .interact(
                    spec: spec,
                    action: .transform(controlID: "press-grain", amount: 1)
                )
            )
            XCTFail("A completed interaction must reject before a second durable commit")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .rejectedTransition("The interaction is already complete")
            )
        }
        let stateAfterRepeatedAction = await committer.currentCommittedState()
        XCTAssertEqual(stateAfterRepeatedAction, stateBeforeRepeatedAction)
    }

    func testDurableReceiptMustMatchExactChapterArcBeatAndInteractionScope() async throws {
        let otherScope = ResponsiveAudioProgramScope(
            chapterID: "other-chapter",
            arcID: Self.scope.arcID,
            beatID: Self.scope.beatID,
            interactionID: Self.scope.interactionID
        )
        let commit = try await Self.makeCompletionCommit(scope: otherScope)
        let receipt = try DurableInteractionAudioCompletionReceipt.make(from: commit)
        var runtime = try Self.runtimeAtInteraction()

        XCTAssertThrowsError(try runtime.accept(receipt)) { error in
            XCTAssertEqual(
                error as? ResponsiveAudioRuntimeError,
                .invalidDurableCompletion
            )
        }
        XCTAssertEqual(runtime.stage, .interaction)
        XCTAssertNil(runtime.durableCompletionSequence)
    }

    func testLoopOverflowFailsAtomicallyWithoutMovingCursor() throws {
        let snapshot = ResponsiveAudioProgramSnapshot(
            programID: Self.program.id,
            stage: .interaction,
            interactionPhase: .engaged,
            timelineID: "engaged-bed",
            cursorSample: 95_999,
            loopIteration: .max,
            durableCompletionSequence: nil
        )
        var runtime = try ResponsiveAudioProgramRuntime(
            program: Self.program,
            timelines: Self.timelines(),
            restoring: snapshot
        )
        try runtime.resume()
        let before = runtime.snapshot()

        XCTAssertThrowsError(try runtime.advance(bySamples: 1)) { error in
            XCTAssertEqual(
                error as? ResponsiveAudioRuntimeError,
                .loopIterationOverflow
            )
        }
        XCTAssertEqual(runtime.snapshot(), before)
    }

    @MainActor
    func testNativeControllerPersistsSampleCursorAndReleasesConsequenceOnlyAfterCommit() async throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        XCTAssertEqual(transport.preparedTimelineID, Self.program.approachTimelineID)

        try controller.play()
        transport.cursorSample = try XCTUnwrap(
            Self.timelines().first { $0.id == Self.program.approachTimelineID }
        ).authoredDurationSamples
        let enteredInteraction = try controller.pauseAndPersist()
        guard case let .setResponsiveAudioSnapshot(interactionSnapshot) = enteredInteraction else {
            return XCTFail("Expected the exact responsive-audio save action")
        }
        XCTAssertEqual(interactionSnapshot.stage, .interaction)
        XCTAssertEqual(interactionSnapshot.interactionPhase, .waiting)
        XCTAssertEqual(transport.preparedTimelineID, "waiting-bed")

        let phaseAction = try controller.selectInteractionPhase(.resistance)
        guard case let .setResponsiveAudioSnapshot(phaseSnapshot) = phaseAction else {
            return XCTFail("Expected a durable phase cursor")
        }
        XCTAssertEqual(phaseSnapshot.interactionPhase, .resistance)
        XCTAssertEqual(transport.preparedTimelineID, "resistance-bed")
        try controller.play()

        let completion = try await Self.makeCompletionCommit(scope: Self.scope)
        let consequenceAction = try controller.accept(durableCommit: completion)
        guard case let .setResponsiveAudioSnapshot(consequence) = consequenceAction else {
            return XCTFail("Expected a durable consequence cursor")
        }
        XCTAssertEqual(consequence.stage, .consequence)
        XCTAssertEqual(consequence.causalStage?.completedStageCount, 1)
        XCTAssertEqual(consequence.durableCompletionSequence, completion.sequence)
        XCTAssertEqual(transport.preparedTimelineID, Self.program.consequenceTimelineID)
        XCTAssertTrue(transport.isPlaying)
    }

    @MainActor
    func testControllerRollsBackAfterTransportPausesThenThrows() throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        try controller.play()
        let exactFallback = controller.runtime.snapshot()
        transport.cursorSample = 1_024
        transport.pauseFailureAfterStateTouch = .injectedPauseAfterStateTouch

        XCTAssertThrowsError(
            try controller.quiesceForSuspension(.sceneInactive)
        ) { error in
            XCTAssertEqual(
                error as? InMemoryResponsiveTimelineTransport.Failure,
                .injectedPauseAfterStateTouch
            )
        }
        XCTAssertEqual(controller.runtime.snapshot(), exactFallback)
        XCTAssertTrue(controller.runtime.isPlaying)
        XCTAssertEqual(transport.cursorSample, 1_024)
        XCTAssertFalse(transport.isPlaying)
        XCTAssertEqual(transport.pauseCount, 1)

        controller.stopWithoutPersisting()
        let fallbackAction = try controller.quiesceForSuspension(
            .sceneInactive
        )
        guard case let .setResponsiveAudioSnapshot(fallback) = fallbackAction
        else { return XCTFail("Expected the exact pre-failure fallback") }
        XCTAssertEqual(fallback, exactFallback)
        XCTAssertEqual(transport.pauseCount, 1)
    }

    @MainActor
    func testControllerDiscardsBoundaryActionCapturedByFailedPause() throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        try controller.play()
        let exactEntrySnapshot = controller.runtime.snapshot()
        let approachDuration = try XCTUnwrap(
            Self.timelines().first {
                $0.id == Self.program.approachTimelineID
            }
        ).authoredDurationSamples
        transport.cursorSample = approachDuration
        transport.pauseFailureAfterStateTouch =
            .injectedPauseAfterStateTouch

        XCTAssertThrowsError(
            try controller.quiesceForSuspension(.sceneInactive)
        ) { error in
            XCTAssertEqual(
                error as? InMemoryResponsiveTimelineTransport.Failure,
                .injectedPauseAfterStateTouch
            )
        }
        XCTAssertEqual(controller.runtime.snapshot(), exactEntrySnapshot)
        XCTAssertTrue(controller.runtime.isPlaying)
        XCTAssertEqual(transport.preparedTimelineID, "waiting-bed")
        XCTAssertFalse(transport.isPlaying)

        var deliveredAfterRollback: [JourneyAction] = []
        controller.setAutomaticBoundaryActionHandler {
            deliveredAfterRollback.append($0)
        }

        XCTAssertTrue(deliveredAfterRollback.isEmpty)
        XCTAssertEqual(controller.runtime.snapshot(), exactEntrySnapshot)
        XCTAssertNil(controller.automaticBoundaryFailure)
    }

    @MainActor
    func testControllerRollsBackRuntimeWhenLateTimelinePrepareFailsAfterPause()
        throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        try controller.play()
        let exactEntrySnapshot = controller.runtime.snapshot()
        let staleBoundaryHandler = try XCTUnwrap(
            transport.capturedAutomaticBoundaryHandlers.first
        )
        var publishedBoundaryActions: [JourneyAction] = []
        controller.setAutomaticBoundaryActionHandler {
            publishedBoundaryActions.append($0)
        }
        let approachDuration = try XCTUnwrap(
            Self.timelines().first {
                $0.id == Self.program.approachTimelineID
            }
        ).authoredDurationSamples
        transport.automaticBoundaryHandler = nil
        transport.cursorSample = approachDuration
        transport.prepareFailureAfterStateTouch =
            .injectedPrepareAfterStateTouch

        XCTAssertThrowsError(
            try controller.quiesceForSuspension(.sceneInactive)
        ) { error in
            XCTAssertEqual(
                error as? InMemoryResponsiveTimelineTransport.Failure,
                .injectedPrepareAfterStateTouch
            )
        }
        XCTAssertEqual(controller.runtime.snapshot(), exactEntrySnapshot)
        XCTAssertTrue(controller.runtime.isPlaying)
        XCTAssertEqual(transport.preparedTimelineID, "waiting-bed")
        XCTAssertFalse(transport.isPlaying)

        staleBoundaryHandler(.successorStarted(
            NativeTimelineTransportSnapshot(
                timelineID: "waiting-bed",
                cursorSample: 0,
                loopIteration: 0,
                isPlaying: true
            )
        ))
        XCTAssertEqual(controller.runtime.snapshot(), exactEntrySnapshot)
        XCTAssertTrue(controller.runtime.isPlaying)
        XCTAssertTrue(publishedBoundaryActions.isEmpty)
        XCTAssertNil(controller.automaticBoundaryFailure)

        controller.stopWithoutPersisting()
        let fallbackAction = try controller.quiesceForSuspension(
            .sceneInactive
        )
        guard case let .setResponsiveAudioSnapshot(fallback) = fallbackAction
        else { return XCTFail("Expected the exact pre-prepare fallback") }
        XCTAssertEqual(fallback, exactEntrySnapshot)
    }

    @MainActor
    func testControllerSelectsStageOnlyFromCommittedTransformAndRetainsClock() async throws {
        let spec = Self.multistageInteractionSpec
        let committer = Self.committer(scope: Self.scope, spec: spec)
        let firstStageCommit = try await committer.commit(
            .interact(
                spec: spec,
                action: .transform(controlID: "heat-grain", amount: 1)
            )
        )
        let authority = try XCTUnwrap(
            try DurableInteractionAudioCausalStageReceipt.make(from: firstStageCommit)
        )
        XCTAssertEqual(authority.causalStage.completedStageCount, 1)

        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        try controller.play()
        transport.cursorSample = 144_000
        _ = try controller.pauseAndPersist()
        try controller.play()
        transport.cursorSample = 31_337

        let action = try XCTUnwrap(controller.selectCausalStage(authority))
        guard case let .setResponsiveAudioSnapshot(snapshot) = action else {
            return XCTFail("Expected a causal-stage snapshot")
        }
        XCTAssertEqual(snapshot.stage, .interaction)
        XCTAssertEqual(snapshot.interactionPhase, .waiting)
        XCTAssertEqual(snapshot.causalStage?.completedStageCount, 1)
        XCTAssertEqual(snapshot.cursorSample, 31_337)
        XCTAssertEqual(snapshot.loopIteration, 0)
        XCTAssertTrue(transport.isPlaying)
        XCTAssertNil(try controller.selectCausalStage(authority))

        let completion = try await committer.commit(
            .interact(
                spec: spec,
                action: .transform(controlID: "seal-grain", amount: 1)
            )
        )
        let consequence = try controller.accept(durableCommit: completion)
        guard case let .setResponsiveAudioSnapshot(consequenceSnapshot) = consequence else {
            return XCTFail("Expected the consequence snapshot")
        }
        XCTAssertEqual(consequenceSnapshot.stage, .consequence)
        XCTAssertEqual(consequenceSnapshot.causalStage?.completedStageCount, 2)
        XCTAssertEqual(
            consequenceSnapshot.durableCompletionSequence,
            completion.sequence
        )
    }

    @MainActor
    func testCausalControllerTransitionsWithoutPauseOrPrepareAndKeepsCommonClock() async throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.causalProgram,
            timelines: Self.causalTimelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        try controller.play()
        transport.cursorSample = 48_000
        _ = try controller.pauseAndPersist()
        XCTAssertEqual(controller.runtime.stage, .interaction)
        XCTAssertEqual(transport.prepareCount, 1)
        XCTAssertEqual(transport.pauseCount, 1)
        let commonIdentity = try XCTUnwrap(transport.commonPlayerIdentity)
        let commonScheduleCount = transport.commonScheduleCount

        try controller.play()
        transport.loopIteration = 2
        transport.cursorSample = 12_345
        let phaseAction = try controller.selectInteractionPhase(.engaged)
        guard case let .setResponsiveAudioSnapshot(phaseSnapshot) = phaseAction else {
            return XCTFail("Expected phase snapshot")
        }
        XCTAssertEqual(phaseSnapshot.cursorSample, 12_345)
        XCTAssertEqual(phaseSnapshot.loopIteration, 2)
        XCTAssertEqual(transport.pauseCount, 1)
        XCTAssertEqual(transport.prepareCount, 1)
        XCTAssertEqual(transport.transitionCount, 1)
        XCTAssertEqual(transport.commonPlayerIdentity, commonIdentity)
        XCTAssertEqual(transport.commonScheduleCount, commonScheduleCount)
        XCTAssertTrue(transport.isPlaying)

        let committer = Self.committer(
            scope: Self.scope,
            spec: Self.multistageInteractionSpec
        )
        let firstStage = try await committer.commit(
            .interact(
                spec: Self.multistageInteractionSpec,
                action: .transform(controlID: "heat-grain", amount: 1)
            )
        )
        let authority = try XCTUnwrap(
            try DurableInteractionAudioCausalStageReceipt.make(from: firstStage)
        )
        let stageAction = try XCTUnwrap(controller.selectCausalStage(authority))
        guard case let .setResponsiveAudioSnapshot(stageSnapshot) = stageAction else {
            return XCTFail("Expected causal-stage snapshot")
        }
        XCTAssertEqual(stageSnapshot.cursorSample, 12_345)
        XCTAssertEqual(stageSnapshot.loopIteration, 2)
        XCTAssertEqual(stageSnapshot.causalStage?.completedStageCount, 1)
        XCTAssertEqual(transport.targetGains["river"], 0.8)
        XCTAssertEqual(transport.targetGains["work"], 0.35)
        XCTAssertEqual(transport.pauseCount, 1)
        XCTAssertEqual(transport.prepareCount, 1)
        XCTAssertEqual(transport.transitionCount, 2)
        XCTAssertEqual(transport.commonPlayerIdentity, commonIdentity)
        XCTAssertEqual(transport.commonScheduleCount, commonScheduleCount)

        let completion = try await committer.commit(
            .interact(
                spec: Self.multistageInteractionSpec,
                action: .transform(controlID: "seal-grain", amount: 1)
            )
        )
        let consequence = try controller.accept(durableCommit: completion)
        guard case let .setResponsiveAudioSnapshot(snapshot) = consequence else {
            return XCTFail("Expected consequence snapshot")
        }
        XCTAssertEqual(snapshot.stage, .consequence)
        XCTAssertEqual(snapshot.causalStage?.completedStageCount, 2)
        XCTAssertEqual(snapshot.durableCompletionSequence, completion.sequence)
        XCTAssertNil(transport.commonPlayerIdentity)
    }

    @MainActor
    func testControllerDiscardsPhaseAndConsequenceCandidatesWhenTransportFails() async throws {
        let causalTransport = InMemoryResponsiveTimelineTransport()
        let causalController = try ResponsiveAudioProgramController(
            program: Self.causalProgram,
            timelines: Self.causalTimelines(),
            transport: causalTransport,
            resolver: NoopOfflineAudioResolver()
        )
        try causalController.play()
        causalTransport.cursorSample = 48_000
        _ = try causalController.pauseAndPersist()
        let phaseRuntimeBefore = causalController.runtime.snapshot()
        let phaseTransportBefore = causalTransport.snapshot()
        let phaseIdentityBefore = causalTransport.commonPlayerIdentity
        causalTransport.transitionFailure = .injectedTransition

        XCTAssertThrowsError(
            try causalController.selectInteractionPhase(.engaged)
        ) { error in
            XCTAssertEqual(
                error as? InMemoryResponsiveTimelineTransport.Failure,
                .injectedTransition
            )
        }
        XCTAssertEqual(causalController.runtime.snapshot(), phaseRuntimeBefore)
        XCTAssertEqual(causalTransport.snapshot(), phaseTransportBefore)
        XCTAssertEqual(causalTransport.commonPlayerIdentity, phaseIdentityBefore)
        causalTransport.transitionFailure = nil
        _ = try causalController.selectInteractionPhase(.engaged)
        XCTAssertEqual(causalController.runtime.interactionPhase, .engaged)

        try causalController.play()
        let stageCommitter = Self.committer(
            scope: Self.scope,
            spec: Self.multistageInteractionSpec
        )
        let stageCommit = try await stageCommitter.commit(
            .interact(
                spec: Self.multistageInteractionSpec,
                action: .transform(controlID: "heat-grain", amount: 1)
            )
        )
        let stageAuthority = try XCTUnwrap(
            try DurableInteractionAudioCausalStageReceipt.make(from: stageCommit)
        )
        let stageRuntimeBefore = causalController.runtime.snapshot()
        let stageTransportBefore = causalTransport.snapshot()
        let stageTargetsBefore = causalTransport.targetGains
        causalTransport.transitionFailure = .injectedTransition
        XCTAssertThrowsError(
            try causalController.selectCausalStage(stageAuthority)
        )
        XCTAssertEqual(causalController.runtime.snapshot(), stageRuntimeBefore)
        XCTAssertEqual(causalTransport.snapshot(), stageTransportBefore)
        XCTAssertEqual(causalTransport.targetGains, stageTargetsBefore)
        XCTAssertEqual(causalTransport.commonPlayerIdentity, phaseIdentityBefore)
        XCTAssertTrue(causalTransport.isPlaying)
        causalTransport.transitionFailure = nil
        _ = try causalController.selectCausalStage(stageAuthority)
        XCTAssertEqual(
            causalController.runtime.causalStage?.completedStageCount,
            1
        )
        XCTAssertEqual(causalTransport.targetGains["work"], 0.35)

        let phaseOnlyTransport = InMemoryResponsiveTimelineTransport()
        let phaseOnlyController = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: phaseOnlyTransport,
            resolver: NoopOfflineAudioResolver()
        )
        try phaseOnlyController.play()
        phaseOnlyTransport.cursorSample = 144_000
        _ = try phaseOnlyController.pauseAndPersist()
        let completion = try await Self.makeCompletionCommit(scope: Self.scope)
        let consequenceRuntimeBefore = phaseOnlyController.runtime.snapshot()
        let consequenceTransportBefore = phaseOnlyTransport.snapshot()
        phaseOnlyTransport.transitionFailure = .injectedTransition

        XCTAssertThrowsError(
            try phaseOnlyController.accept(durableCommit: completion)
        )
        XCTAssertEqual(
            phaseOnlyController.runtime.snapshot(),
            consequenceRuntimeBefore
        )
        XCTAssertEqual(phaseOnlyTransport.snapshot(), consequenceTransportBefore)
        phaseOnlyTransport.transitionFailure = nil
        _ = try phaseOnlyController.accept(durableCommit: completion)
        XCTAssertEqual(phaseOnlyController.runtime.stage, .consequence)
    }

    @MainActor
    func testControllerValidatesAuthoritativeTransitionSnapshotBeforeTransportCommit() throws {
        for rejectedSnapshot in [
            NativeTimelineTransportSnapshot(
                timelineID: "wrong-phase",
                cursorSample: 0,
                loopIteration: 0,
                isPlaying: false
            ),
            NativeTimelineTransportSnapshot(
                timelineID: "causal-engaged-bed",
                cursorSample: 0,
                loopIteration: .max,
                isPlaying: false
            ),
        ] {
            let transport = InMemoryResponsiveTimelineTransport()
            let controller = try ResponsiveAudioProgramController(
                program: Self.causalProgram,
                timelines: Self.causalTimelines(),
                transport: transport,
                resolver: NoopOfflineAudioResolver()
            )
            try controller.play()
            transport.cursorSample = 48_000
            _ = try controller.pauseAndPersist()
            let runtimeBefore = controller.runtime.snapshot()
            let transportBefore = transport.snapshot()
            let identityBefore = transport.commonPlayerIdentity
            let targetsBefore = transport.targetGains
            transport.transitionSnapshotOverride = rejectedSnapshot

            XCTAssertThrowsError(
                try controller.selectInteractionPhase(.engaged)
            )
            XCTAssertEqual(controller.runtime.snapshot(), runtimeBefore)
            XCTAssertEqual(transport.snapshot(), transportBefore)
            XCTAssertEqual(transport.commonPlayerIdentity, identityBefore)
            XCTAssertEqual(transport.targetGains, targetsBefore)

            transport.transitionSnapshotOverride = nil
            _ = try controller.selectInteractionPhase(.engaged)
            XCTAssertEqual(controller.runtime.interactionPhase, .engaged)
            XCTAssertEqual(transport.preparedTimelineID, "causal-engaged-bed")
        }
    }

    @MainActor
    func testControllerAppliesPreferencesWithoutMovingCursorOrStartingPlayback() throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        let before = controller.runtime.snapshot()
        let preferences = ExperiencePreferences(
            soundEnabled: false,
            narrationEnabled: false,
            hapticsEnabled: false
        )

        controller.applyPreferences(preferences)

        XCTAssertEqual(transport.appliedPreferences, preferences)
        XCTAssertEqual(controller.runtime.snapshot(), before)
        XCTAssertFalse(transport.isPlaying)
    }

    @MainActor
    func testAutomaticApproachBoundaryIsAtomicAcrossCheckpointOrderings() throws {
        let approachDuration = try XCTUnwrap(
            Self.timelines().first { $0.id == Self.program.approachTimelineID }
        ).authoredDurationSamples

        for callbackFirst in [false, true] {
            let transport = InMemoryResponsiveTimelineTransport()
            let controller = try ResponsiveAudioProgramController(
                program: Self.program,
                timelines: Self.timelines(),
                transport: transport,
                resolver: NoopOfflineAudioResolver()
            )
            var delivered: [ResponsiveAudioProgramSnapshot] = []
            controller.setAutomaticBoundaryActionHandler { action in
                guard case let .setResponsiveAudioSnapshot(snapshot) = action else {
                    return
                }
                delivered.append(snapshot)
            }
            XCTAssertEqual(transport.automaticBoundaryConfigureCount, 1)
            XCTAssertEqual(transport.automaticSuccessorPlan?.cursorSample, 0)
            XCTAssertEqual(transport.automaticSuccessorPlan?.loopIteration, 0)

            try controller.play()
            transport.cursorSample = approachDuration
            if callbackFirst {
                transport.triggerAutomaticBoundary()
                let checkpoint = try controller.checkpointForDurability()
                XCTAssertEqual(checkpoint.stage, .interaction)
                XCTAssertEqual(checkpoint.cursorSample, 0)
            } else {
                let checkpoint = try controller.checkpointForDurability()
                XCTAssertEqual(checkpoint.stage, .approach)
                XCTAssertEqual(checkpoint.cursorSample, approachDuration - 1)
                transport.triggerAutomaticBoundary()
            }

            XCTAssertEqual(controller.runtime.stage, .interaction)
            XCTAssertEqual(controller.runtime.interactionPhase, .waiting)
            XCTAssertEqual(controller.runtime.cursorSample, 0)
            XCTAssertEqual(controller.runtime.loopIteration, 0)
            XCTAssertEqual(delivered.count, 1)
            XCTAssertEqual(delivered[0].stage, .interaction)
            XCTAssertEqual(delivered[0].cursorSample, 0)
        }
    }

    @MainActor
    func testApproachCausalStageRestagesSuccessorWithoutRestartAndRejectsStaleBoundary() async throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.causalProgram,
            timelines: Self.causalTimelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        var delivered: [ResponsiveAudioProgramSnapshot] = []
        controller.setAutomaticBoundaryActionHandler { action in
            guard case let .setResponsiveAudioSnapshot(snapshot) = action else {
                return
            }
            delivered.append(snapshot)
        }
        let staleBoundary = try XCTUnwrap(
            transport.capturedAutomaticBoundaryHandlers.first
        )
        let committer = Self.committer(
            scope: Self.scope,
            spec: Self.multistageInteractionSpec
        )
        let firstStageCommit = try await committer.commit(.interact(
            spec: Self.multistageInteractionSpec,
            action: .transform(controlID: "heat-grain", amount: 1)
        ))
        let firstStage = try XCTUnwrap(
            try DurableInteractionAudioCausalStageReceipt.make(
                from: firstStageCommit
            )
        )

        try controller.play()
        transport.cursorSample = 12_345
        let action = try XCTUnwrap(controller.selectCausalStage(firstStage))
        guard case let .setResponsiveAudioSnapshot(approachSnapshot) = action else {
            return XCTFail("Expected the committed causal approach snapshot")
        }
        XCTAssertEqual(approachSnapshot.stage, .approach)
        XCTAssertEqual(approachSnapshot.causalStage?.completedStageCount, 1)
        XCTAssertEqual(approachSnapshot.cursorSample, 12_345)
        XCTAssertEqual(transport.playCount, 1)
        XCTAssertEqual(transport.pauseCount, 0)
        XCTAssertTrue(transport.isPlaying)
        XCTAssertEqual(transport.automaticBoundaryConfigureCount, 2)
        XCTAssertEqual(
            transport.automaticSuccessorPlan?.timeline.id,
            "causal-waiting-bed"
        )
        XCTAssertEqual(transport.automaticSuccessorPlan?.cursorSample, 0)
        XCTAssertEqual(transport.automaticSuccessorPlan?.loopIteration, 0)
        let stagedMix = try XCTUnwrap(transport.automaticSuccessorPlan?.causalMix)
        let stagedGains = Dictionary(uniqueKeysWithValues: stagedMix.layers.map {
            ($0.layerID, $0.targetGain)
        })
        XCTAssertEqual(stagedGains["river"], 0.8)
        XCTAssertEqual(stagedGains["work"], 0.35)

        staleBoundary(.successorStarted(NativeTimelineTransportSnapshot(
            timelineID: try XCTUnwrap(
                transport.automaticSuccessorPlan?.timeline.id
            ),
            cursorSample: 0,
            loopIteration: 0,
            isPlaying: true
        )))
        XCTAssertEqual(controller.runtime.stage, .approach)
        XCTAssertTrue(delivered.isEmpty)

        transport.triggerAutomaticBoundary()
        XCTAssertEqual(controller.runtime.stage, .interaction)
        XCTAssertEqual(controller.runtime.interactionPhase, .waiting)
        XCTAssertEqual(controller.runtime.causalStage?.completedStageCount, 1)
        XCTAssertEqual(controller.runtime.cursorSample, 0)
        XCTAssertEqual(controller.runtime.loopIteration, 0)
        XCTAssertEqual(transport.targetGains["work"], 0.35)
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered[0].causalStage?.completedStageCount, 1)
    }

    @MainActor
    func testApproachCausalStageRestagingUsesLatestMonotoneAuthority() async throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.causalProgram,
            timelines: Self.causalTimelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        let committer = Self.committer(
            scope: Self.scope,
            spec: Self.multistageInteractionSpec
        )
        let firstCommit = try await committer.commit(.interact(
            spec: Self.multistageInteractionSpec,
            action: .transform(controlID: "heat-grain", amount: 1)
        ))
        let secondCommit = try await committer.commit(.interact(
            spec: Self.multistageInteractionSpec,
            action: .transform(controlID: "seal-grain", amount: 1)
        ))
        let firstStage = try XCTUnwrap(
            try DurableInteractionAudioCausalStageReceipt.make(from: firstCommit)
        )
        let secondStage = try XCTUnwrap(
            try DurableInteractionAudioCausalStageReceipt.make(from: secondCommit)
        )

        try controller.play()
        transport.cursorSample = 7_000
        _ = try controller.selectCausalStage(firstStage)
        transport.cursorSample = 9_000
        _ = try controller.selectCausalStage(secondStage)

        XCTAssertEqual(controller.runtime.stage, .approach)
        XCTAssertEqual(controller.runtime.causalStage?.completedStageCount, 2)
        XCTAssertEqual(controller.runtime.cursorSample, 9_000)
        XCTAssertEqual(transport.playCount, 1)
        XCTAssertEqual(transport.pauseCount, 0)
        XCTAssertEqual(transport.automaticBoundaryConfigureCount, 3)
        XCTAssertEqual(
            transport.automaticSuccessorPlan?.timeline.id,
            "causal-waiting-bed"
        )
        XCTAssertEqual(transport.automaticSuccessorPlan?.cursorSample, 0)
        let stagedMix = try XCTUnwrap(transport.automaticSuccessorPlan?.causalMix)
        let stagedGains = Dictionary(uniqueKeysWithValues: stagedMix.layers.map {
            ($0.layerID, $0.targetGain)
        })
        XCTAssertEqual(stagedGains["work"], 0.55)

        transport.triggerAutomaticBoundary()
        XCTAssertEqual(controller.runtime.stage, .interaction)
        XCTAssertEqual(controller.runtime.causalStage?.completedStageCount, 2)
        XCTAssertEqual(controller.runtime.cursorSample, 0)
        XCTAssertEqual(transport.targetGains["work"], 0.55)
    }

    @MainActor
    func testApproachCausalStageRestagingFailureRestoresPreviousSuccessorAtomically() async throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.causalProgram,
            timelines: Self.causalTimelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        let committer = Self.committer(
            scope: Self.scope,
            spec: Self.multistageInteractionSpec
        )
        let firstCommit = try await committer.commit(.interact(
            spec: Self.multistageInteractionSpec,
            action: .transform(controlID: "heat-grain", amount: 1)
        ))
        let firstStage = try XCTUnwrap(
            try DurableInteractionAudioCausalStageReceipt.make(from: firstCommit)
        )

        try controller.play()
        transport.cursorSample = 6_000
        transport.automaticBoundaryFailuresRemaining = 1
        XCTAssertThrowsError(try controller.selectCausalStage(firstStage)) {
            XCTAssertEqual(
                $0 as? InMemoryResponsiveTimelineTransport.Failure,
                .injectedAutomaticBoundary
            )
        }

        XCTAssertEqual(controller.runtime.stage, .approach)
        XCTAssertNil(controller.runtime.causalStage)
        XCTAssertEqual(controller.runtime.cursorSample, 6_000)
        XCTAssertTrue(controller.runtime.isPlaying)
        XCTAssertTrue(transport.isPlaying)
        XCTAssertEqual(transport.playCount, 1)
        XCTAssertEqual(transport.pauseCount, 0)
        XCTAssertEqual(transport.automaticBoundaryConfigureCount, 3)
        let restoredMix = try XCTUnwrap(transport.automaticSuccessorPlan?.causalMix)
        let restoredGains = Dictionary(uniqueKeysWithValues: restoredMix.layers.map {
            ($0.layerID, $0.targetGain)
        })
        XCTAssertEqual(restoredGains["work"], 0)

        let failedCandidateHandler = transport.capturedAutomaticBoundaryHandlers[1]
        failedCandidateHandler(.successorStarted(NativeTimelineTransportSnapshot(
            timelineID: try XCTUnwrap(
                transport.automaticSuccessorPlan?.timeline.id
            ),
            cursorSample: 0,
            loopIteration: 0,
            isPlaying: true
        )))
        XCTAssertEqual(controller.runtime.stage, .approach)
        XCTAssertNil(controller.runtime.causalStage)

        transport.triggerAutomaticBoundary()
        XCTAssertEqual(controller.runtime.stage, .interaction)
        XCTAssertNil(controller.runtime.causalStage)
        XCTAssertEqual(transport.targetGains["work"], 0)
    }

    @MainActor
    func testAutomaticBoundaryRejectsStaleControllerGeneration() throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        let stale = try XCTUnwrap(
            transport.capturedAutomaticBoundaryHandlers.first
        )
        controller.stopWithoutPersisting()

        stale(.successorStarted(NativeTimelineTransportSnapshot(
            timelineID: "waiting-bed",
            cursorSample: 0,
            loopIteration: 0,
            isPlaying: true
        )))

        XCTAssertEqual(controller.runtime.stage, .approach)
        XCTAssertFalse(controller.runtime.isPlaying)
        XCTAssertNil(controller.automaticBoundaryFailure)
    }

    @MainActor
    func testDurabilityCheckpointCannotBorrowUndurableStageAuthority() throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        let durableApproach = controller.runtime.snapshot()
        let approachDuration = try XCTUnwrap(
            Self.timelines().first { $0.id == Self.program.approachTimelineID }
        ).authoredDurationSamples

        try controller.play()
        transport.cursorSample = approachDuration
        transport.triggerAutomaticBoundary()
        XCTAssertEqual(controller.runtime.stage, .interaction)

        let stillApproachResult = try controller.checkpointForDurability(
            constrainedTo: durableApproach
        )
        guard case let .awaitingDurableAuthority(stillApproach) =
                stillApproachResult else {
            return XCTFail("An undurable stage must not refresh cursor freshness")
        }
        XCTAssertEqual(stillApproach.stage, .approach)
        XCTAssertEqual(stillApproach.timelineID, durableApproach.timelineID)
        XCTAssertEqual(stillApproach.cursorSample, approachDuration - 1)
        XCTAssertEqual(stillApproach.loopIteration, 0)

        let durableWaiting = controller.runtime.snapshot()
        transport.cursorSample = 1_337
        transport.loopIteration = 2
        let waitingProgressResult = try controller.checkpointForDurability(
            constrainedTo: durableWaiting
        )
        guard case let .verified(waitingProgress) = waitingProgressResult else {
            return XCTFail("An exact waiting authority must be verified")
        }
        XCTAssertEqual(waitingProgress.stage, .interaction)
        XCTAssertEqual(waitingProgress.interactionPhase, .waiting)
        XCTAssertEqual(waitingProgress.timelineID, durableWaiting.timelineID)
        XCTAssertEqual(waitingProgress.cursorSample, 1_337)
        XCTAssertEqual(waitingProgress.loopIteration, 2)
    }

    @MainActor
    func testDurabilityCheckpointCarriesPositionAcrossUndurablePhaseOnly() throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        try controller.play()
        transport.cursorSample = try XCTUnwrap(
            Self.timelines().first { $0.id == Self.program.approachTimelineID }
        ).authoredDurationSamples
        transport.triggerAutomaticBoundary()
        let durableWaiting = controller.runtime.snapshot()

        transport.cursorSample = 400
        transport.loopIteration = 1
        _ = try controller.selectInteractionPhase(.engaged)
        transport.cursorSample = 900
        transport.loopIteration = 1

        let constrainedResult = try controller.checkpointForDurability(
            constrainedTo: durableWaiting
        )
        guard case let .awaitingDurableAuthority(constrained) =
                constrainedResult else {
            return XCTFail("An undurable phase must not refresh cursor freshness")
        }
        XCTAssertEqual(constrained.stage, .interaction)
        XCTAssertEqual(constrained.interactionPhase, .waiting)
        XCTAssertEqual(constrained.timelineID, durableWaiting.timelineID)
        XCTAssertNil(constrained.causalStage)
        XCTAssertEqual(constrained.cursorSample, 900)
        XCTAssertEqual(constrained.loopIteration, 1)
    }

    @MainActor
    func testQuarterSecondPhaseCommitDelayKeepsDurablePhaseAuthority() throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        try controller.play()
        transport.cursorSample = try XCTUnwrap(
            Self.timelines().first { $0.id == Self.program.approachTimelineID }
        ).authoredDurationSamples
        transport.triggerAutomaticBoundary()
        let durableWaiting = controller.runtime.snapshot()

        _ = try controller.selectInteractionPhase(.engaged)
        transport.cursorSample = 12_000 // 250 ms in the authored 48 kHz domain.
        let delayedResult = try controller.checkpointForDurability(
            constrainedTo: durableWaiting
        )
        guard case let .awaitingDurableAuthority(delayed) = delayedResult else {
            return XCTFail("A pending phase must remain unverified")
        }

        XCTAssertEqual(delayed.interactionPhase, .waiting)
        XCTAssertEqual(delayed.timelineID, durableWaiting.timelineID)
        XCTAssertEqual(delayed.cursorSample, 12_000)
        XCTAssertEqual(delayed.loopIteration, 0)
    }

    @MainActor
    func testQuarterSecondCausalCommitDelayKeepsDurableStageAuthority() async throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.causalProgram,
            timelines: Self.causalTimelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        try controller.play()
        transport.cursorSample = try XCTUnwrap(
            Self.causalTimelines().first {
                $0.id == Self.causalProgram.approachTimelineID
            }
        ).authoredDurationSamples
        transport.triggerAutomaticBoundary()
        let durableStageZero = controller.runtime.snapshot()
        let committer = Self.committer(
            scope: Self.scope,
            spec: Self.multistageInteractionSpec
        )
        let firstStage = try await committer.commit(.interact(
            spec: Self.multistageInteractionSpec,
            action: .transform(controlID: "heat-grain", amount: 1)
        ))
        let authority = try XCTUnwrap(
            try DurableInteractionAudioCausalStageReceipt.make(from: firstStage)
        )

        _ = try controller.selectCausalStage(authority)
        transport.cursorSample = 12_000 // 250 ms before its action is durable.
        let delayedResult = try controller.checkpointForDurability(
            constrainedTo: durableStageZero
        )
        guard case let .awaitingDurableAuthority(delayed) = delayedResult else {
            return XCTFail("A pending causal stage must remain unverified")
        }

        XCTAssertNil(delayed.causalStage)
        XCTAssertEqual(delayed.interactionPhase, .waiting)
        XCTAssertEqual(delayed.timelineID, durableStageZero.timelineID)
        XCTAssertEqual(delayed.cursorSample, 12_000)
        XCTAssertEqual(delayed.loopIteration, 0)
    }

    @MainActor
    func testQuarterSecondApproachBoundaryDelayCannotPublishWaitingAuthority() throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        let durableApproach = controller.runtime.snapshot()
        let approachDuration = try XCTUnwrap(
            Self.timelines().first { $0.id == Self.program.approachTimelineID }
        ).authoredDurationSamples
        try controller.play()
        transport.cursorSample = approachDuration
        transport.triggerAutomaticBoundary()
        transport.cursorSample = 12_000 // Waiting rendered for 250 ms.

        let delayedResult = try controller.checkpointForDurability(
            constrainedTo: durableApproach
        )
        guard case let .awaitingDurableAuthority(delayed) = delayedResult else {
            return XCTFail("A pending finite boundary must remain unverified")
        }
        XCTAssertEqual(delayed.stage, .approach)
        XCTAssertEqual(delayed.timelineID, durableApproach.timelineID)
        XCTAssertEqual(delayed.cursorSample, approachDuration - 1)
        XCTAssertEqual(delayed.loopIteration, 0)
    }

    @MainActor
    func testCompletedCallbackDelayCannotPublishTerminalAuthority() async throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        try controller.play()
        transport.cursorSample = try XCTUnwrap(
            Self.timelines().first { $0.id == Self.program.approachTimelineID }
        ).authoredDurationSamples
        transport.triggerAutomaticBoundary()
        let completion = try await Self.makeCompletionCommit(scope: Self.scope)
        _ = try controller.accept(durableCommit: completion)
        let durableConsequence = controller.runtime.snapshot()
        let consequenceDuration = try XCTUnwrap(
            Self.timelines().first { $0.id == Self.program.consequenceTimelineID }
        ).authoredDurationSamples
        transport.cursorSample = consequenceDuration
        transport.triggerAutomaticBoundary()

        let delayedResult = try controller.checkpointForDurability(
            constrainedTo: durableConsequence
        )
        guard case let .awaitingDurableAuthority(delayed) = delayedResult else {
            return XCTFail("A pending terminal boundary must remain unverified")
        }
        XCTAssertEqual(delayed.stage, .consequence)
        XCTAssertEqual(delayed.timelineID, durableConsequence.timelineID)
        XCTAssertEqual(delayed.cursorSample, consequenceDuration - 1)
        XCTAssertEqual(delayed.durableCompletionSequence, completion.sequence)
    }

    @MainActor
    func testAutomaticConsequenceCompletionEmitsExactTerminalAction() async throws {
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            program: Self.program,
            timelines: Self.timelines(),
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        var delivered: [ResponsiveAudioProgramSnapshot] = []
        controller.setAutomaticBoundaryActionHandler { action in
            guard case let .setResponsiveAudioSnapshot(snapshot) = action else {
                return
            }
            delivered.append(snapshot)
        }
        try controller.play()
        transport.cursorSample = try XCTUnwrap(
            Self.timelines().first { $0.id == Self.program.approachTimelineID }
        ).authoredDurationSamples
        transport.triggerAutomaticBoundary()

        let completion = try await Self.makeCompletionCommit(scope: Self.scope)
        _ = try controller.accept(durableCommit: completion)
        let consequenceDuration = try XCTUnwrap(
            Self.timelines().first { $0.id == Self.program.consequenceTimelineID }
        ).authoredDurationSamples
        transport.cursorSample = consequenceDuration
        transport.triggerAutomaticBoundary()

        XCTAssertEqual(controller.runtime.stage, .completed)
        XCTAssertEqual(controller.runtime.cursorSample, consequenceDuration)
        XCTAssertFalse(controller.runtime.isPlaying)
        XCTAssertFalse(transport.isPlaying)
        XCTAssertEqual(delivered.last?.stage, .completed)
        XCTAssertEqual(delivered.last?.cursorSample, consequenceDuration)
    }

    @MainActor
    func testNativeControllerRejectsDuplicateTimelineIDsWithoutTrapping() throws {
        let duplicate = try XCTUnwrap(Self.timelines().first)
        XCTAssertThrowsError(
            try ResponsiveAudioProgramController(
                program: Self.program,
                timelines: Self.timelines() + [duplicate],
                transport: InMemoryResponsiveTimelineTransport(),
                resolver: NoopOfflineAudioResolver()
            )
        ) { error in
            XCTAssertEqual(
                error as? ResponsiveAudioProgramControllerError,
                .duplicateTimelineID(duplicate.id)
            )
        }
    }

    @MainActor
    func testControllerColdRestoreRequiresJourneyAuthorityAndPromotesCrashGap() async throws {
        let completion = try await Self.makeCompletionCommit(scope: Self.scope)
        let waiting = try XCTUnwrap(Self.program.interactionBed(for: .waiting))
        let stalePreConsequence = ResponsiveAudioProgramSnapshot(
            programID: Self.program.id,
            stage: .interaction,
            interactionPhase: .waiting,
            timelineID: waiting.timelineID,
            cursorSample: 41_337,
            loopIteration: 7,
            durableCompletionSequence: nil
        )
        let plan = ResponsiveAudioRestorationPlan(
            program: Self.program,
            timelines: Self.timelines(),
            snapshot: stalePreConsequence,
            interaction: Self.interactionSpec,
            requiresCompletionAuthority: true
        )
        let restoration = JourneyRestoration(
            state: completion.state,
            replayedEventCount: 1,
            lastSequence: completion.sequence
        )
        let transport = InMemoryResponsiveTimelineTransport()
        let controller = try ResponsiveAudioProgramController(
            restorationPlan: plan,
            restoration: restoration,
            transport: transport,
            resolver: NoopOfflineAudioResolver()
        )
        XCTAssertEqual(controller.runtime.stage, .consequence)
        XCTAssertEqual(controller.runtime.causalStage?.completedStageCount, 1)
        XCTAssertEqual(controller.runtime.cursorSample, 0)
        XCTAssertEqual(controller.runtime.durableCompletionSequence, completion.sequence)
        XCTAssertFalse(controller.runtime.isPlaying)

        XCTAssertThrowsError(
            try ResponsiveAudioProgramController(
                program: Self.program,
                timelines: Self.timelines(),
                transport: InMemoryResponsiveTimelineTransport(),
                resolver: NoopOfflineAudioResolver(),
                restoring: ResponsiveAudioProgramSnapshot(
                    programID: Self.program.id,
                    stage: .consequence,
                    interactionPhase: nil,
                    timelineID: Self.program.consequenceTimelineID,
                    cursorSample: 0,
                    loopIteration: 0,
                    durableCompletionSequence: completion.sequence
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ResponsiveAudioProgramControllerError,
                .completionAuthorityRequired
            )
        }
    }

    private static let scope = ResponsiveAudioProgramScope(
        chapterID: "first-farmers",
        arcID: "fields-that-must-endure",
        beatID: "harvest-allocation",
        interactionID: "harvest-interaction"
    )

    private static let beds = [
        ResponsiveInteractionAudioBedSpec(
            phase: .waiting,
            timelineID: "waiting-bed",
            layerStates: ResponsiveAudioLayerStateSelection(
                scoreStateID: "grain-suspended",
                soundscapeStateID: "field-waiting"
            )
        ),
        ResponsiveInteractionAudioBedSpec(
            phase: .engaged,
            timelineID: "engaged-bed",
            layerStates: ResponsiveAudioLayerStateSelection(
                scoreStateID: "grain-in-motion",
                soundscapeStateID: "field-engaged"
            )
        ),
        ResponsiveInteractionAudioBedSpec(
            phase: .resistance,
            timelineID: "resistance-bed",
            layerStates: ResponsiveAudioLayerStateSelection(
                scoreStateID: "grain-tension",
                soundscapeStateID: "field-resistance"
            )
        ),
    ]

    private static let program = ResponsiveAudioProgramSpec(
        id: "harvest-responsive-audio",
        scope: scope,
        approachTimelineID: "approach",
        interactionBeds: beds,
        consequenceTimelineID: "consequence",
        exitPolicy: .boundedFade(durationSamples: 480)
    )

    private static let causalBeds = ResponsiveInteractionAudioPhase.allCases.map { phase in
        ResponsiveInteractionAudioBedSpec(
            phase: phase,
            timelineID: AudioTimelineID("causal-\(phase.rawValue)-bed"),
            layerStates: ResponsiveAudioLayerStateSelection(
                scoreStateID: "causal-\(phase.rawValue)-score",
                soundscapeStateID: "causal-material-clock"
            )
        )
    }

    private static let causalMix = ResponsiveAudioCausalMixSpec(
        rampDurationSamples: 4_800,
        layers: [
            ResponsiveAudioMaterialLayerSpec(
                id: "river",
                assetPath: "audio/shared-river.wav",
                cueIDs: ResponsiveAudioPhaseCueIDs(
                    waiting: "waiting-river",
                    engaged: "engaged-river",
                    resistance: "resistance-river"
                )
            ),
            ResponsiveAudioMaterialLayerSpec(
                id: "work",
                assetPath: "audio/shared-work.wav",
                cueIDs: ResponsiveAudioPhaseCueIDs(
                    waiting: "waiting-work",
                    engaged: "engaged-work",
                    resistance: "resistance-work"
                )
            ),
        ],
        states: [
            ResponsiveAudioCausalMixStateSpec(
                completedStageCount: 0,
                layerGains: [
                    ResponsiveAudioLayerGainSpec(layerID: "river", gain: 0.8),
                    ResponsiveAudioLayerGainSpec(layerID: "work", gain: 0),
                ]
            ),
            ResponsiveAudioCausalMixStateSpec(
                completedStageCount: 1,
                layerGains: [
                    ResponsiveAudioLayerGainSpec(layerID: "river", gain: 0.8),
                    ResponsiveAudioLayerGainSpec(layerID: "work", gain: 0.35),
                ]
            ),
            ResponsiveAudioCausalMixStateSpec(
                completedStageCount: 2,
                layerGains: [
                    ResponsiveAudioLayerGainSpec(layerID: "river", gain: 0.8),
                    ResponsiveAudioLayerGainSpec(layerID: "work", gain: 0.55),
                ]
            ),
        ]
    )

    private static let causalProgram = ResponsiveAudioProgramSpec(
        id: "causal-harvest-responsive-audio",
        scope: scope,
        approachTimelineID: "causal-approach",
        interactionBeds: causalBeds,
        consequenceTimelineID: "causal-consequence",
        exitPolicy: .boundedFade(durationSamples: 480),
        causalMix: causalMix
    )

    private static let narrationBinding = NarrationCueBinding(
        manuscriptSegmentID: "harvest-segment",
        manuscriptSegmentSHA256: String(repeating: "a", count: 64),
        scope: NarrationCueScope(
            chapterID: scope.chapterID,
            arcID: scope.arcID,
            beatID: scope.beatID
        )
    )

    private static var interactionSpec: InteractionSpec {
        InteractionSpec(
            id: scope.interactionID,
            prompt: LocalizedStringSpec(
                id: "harvest-action",
                launchEnglish: "Press the final measure into the storehouse."
            ),
            grammar: .transform(
                TransformInteractionSpec(
                    stages: [
                        TransformationStage(
                            id: "seal-storehouse",
                            controlID: "press-grain",
                            requiredAmount: 1
                        ),
                    ]
                )
            ),
            completionEffects: [
                WorldEffect(
                    id: "harvest-secured",
                    mutation: .revealNode(
                        WorldNodeBlueprint(
                            id: "winter-storehouse",
                            kind: .object,
                            form: "sealed-granary",
                            position: NormalizedPoint(x: 0.4, y: 0.6)
                        )
                    )
                ),
            ],
            accessibilityID: "harvest-accessibility"
        )
    }

    private static var multistageInteractionSpec: InteractionSpec {
        InteractionSpec(
            id: scope.interactionID,
            prompt: LocalizedStringSpec(
                id: "multistage-harvest-action",
                launchEnglish: "Carry the harvest through each irreversible threshold."
            ),
            grammar: .transform(
                TransformInteractionSpec(
                    stages: [
                        TransformationStage(
                            id: "heat-storehouse",
                            controlID: "heat-grain",
                            requiredAmount: 1
                        ),
                        TransformationStage(
                            id: "seal-storehouse",
                            controlID: "seal-grain",
                            requiredAmount: 1
                        ),
                    ]
                )
            ),
            completionEffects: interactionSpec.completionEffects,
            accessibilityID: "multistage-harvest-accessibility"
        )
    }

    private static var interactionSpecReplacingGrammarWithAllocate: InteractionSpec {
        InteractionSpec(
            id: scope.interactionID,
            prompt: interactionSpec.prompt,
            grammar: .allocate(
                AllocateInteractionSpec(
                    resourceName: LocalizedStringSpec(
                        id: "test-grain-resource",
                        launchEnglish: "Grain"
                    ),
                    totalUnits: 1,
                    destinations: [
                        AllocationDestination(id: "store", minimumUnits: 0),
                    ]
                )
            ),
            completionEffects: interactionSpec.completionEffects,
            accessibilityID: interactionSpec.accessibilityID
        )
    }

    private static func runtime() throws -> ResponsiveAudioProgramRuntime {
        try ResponsiveAudioProgramRuntime(program: program, timelines: timelines())
    }

    private static func runtimeAtInteraction() throws -> ResponsiveAudioProgramRuntime {
        var runtime = try runtime()
        try runtime.resume()
        try runtime.advance(bySamples: 144_000)
        _ = runtime.pause()
        return runtime
    }

    private static func timelines() -> [AudioTimeline] {
        [
            AudioTimeline(
                id: "approach",
                sampleRate: 48_000,
                events: [
                    AudioEvent(
                        cueID: "approach-narration",
                        role: .narration,
                        startSample: 0,
                        durationSamples: 96_000,
                        assetPath: "audio/approach-narration.wav",
                        gain: 1,
                        narrationBinding: narrationBinding
                    ),
                    AudioEvent(
                        cueID: "approach-silence",
                        role: .silence,
                        startSample: 96_000,
                        durationSamples: 48_000,
                        assetPath: nil,
                        gain: 0
                    ),
                ],
                haptics: []
            ),
            AudioTimeline(
                id: "waiting-bed",
                sampleRate: 48_000,
                events: [
                    audibleEvent(
                        cueID: "waiting-score-in",
                        role: .score,
                        startSample: 0,
                        durationSamples: 24_000,
                        assetPath: "audio/waiting-score-in.wav"
                    ),
                    audibleEvent(
                        cueID: "waiting-field-in",
                        role: .soundscape,
                        startSample: 0,
                        durationSamples: 24_000,
                        assetPath: "audio/waiting-field-in.wav"
                    ),
                    AudioEvent(
                        cueID: "waiting-silence",
                        role: .silence,
                        startSample: 24_000,
                        durationSamples: 48_000,
                        assetPath: nil,
                        gain: 0
                    ),
                    audibleEvent(
                        cueID: "waiting-score-out",
                        role: .score,
                        startSample: 72_000,
                        durationSamples: 24_000,
                        assetPath: "audio/waiting-score-out.wav"
                    ),
                    audibleEvent(
                        cueID: "waiting-field-out",
                        role: .soundscape,
                        startSample: 72_000,
                        durationSamples: 24_000,
                        assetPath: "audio/waiting-field-out.wav"
                    ),
                ],
                haptics: []
            ),
            bedTimeline(
                id: "engaged-bed",
                scoreCueID: "engaged-score",
                scorePath: "audio/engaged-score.wav",
                soundscapeCueID: "engaged-field",
                soundscapePath: "audio/engaged-field.wav"
            ),
            bedTimeline(
                id: "resistance-bed",
                scoreCueID: "resistance-score",
                scorePath: "audio/resistance-score.wav",
                soundscapeCueID: "resistance-field",
                soundscapePath: "audio/resistance-field.wav"
            ),
            AudioTimeline(
                id: "consequence",
                sampleRate: 48_000,
                events: [
                    AudioEvent(
                        cueID: "consequence-narration",
                        role: .narration,
                        startSample: 0,
                        durationSamples: 48_000,
                        assetPath: "audio/consequence-narration.wav",
                        gain: 1,
                        narrationBinding: narrationBinding
                    ),
                    audibleEvent(
                        cueID: "consequence-score",
                        role: .score,
                        startSample: 0,
                        durationSamples: 96_000,
                        assetPath: "audio/consequence-score.wav"
                    ),
                ],
                haptics: [
                    HapticEvent(sample: 0, kind: .seal, intensity: 0.8, sharpness: 0.3),
                ]
            ),
        ]
    }

    private static func causalTimelines() -> [AudioTimeline] {
        func conventional(
            id: AudioTimelineID,
            cueID: AudioCueID,
            path: String
        ) -> AudioTimeline {
            AudioTimeline(
                id: id,
                sampleRate: 48_000,
                events: [
                    audibleEvent(
                        cueID: cueID,
                        role: .soundscape,
                        startSample: 0,
                        durationSamples: 48_000,
                        assetPath: path
                    ),
                ],
                haptics: []
            )
        }
        let interaction = ResponsiveInteractionAudioPhase.allCases.map { phase in
            AudioTimeline(
                id: AudioTimelineID("causal-\(phase.rawValue)-bed"),
                sampleRate: 48_000,
                events: [
                    AudioEvent(
                        cueID: AudioCueID("\(phase.rawValue)-score"),
                        role: .score,
                        startSample: 0,
                        durationSamples: 48_000,
                        assetPath: "audio/\(phase.rawValue)-score.wav",
                        gain: 0.5
                    ),
                    AudioEvent(
                        cueID: AudioCueID("\(phase.rawValue)-river"),
                        role: .soundscape,
                        startSample: 0,
                        durationSamples: 48_000,
                        assetPath: "audio/shared-river.wav",
                        gain: 0.8
                    ),
                    AudioEvent(
                        cueID: AudioCueID("\(phase.rawValue)-work"),
                        role: .spatialDetail,
                        startSample: 0,
                        durationSamples: 48_000,
                        assetPath: "audio/shared-work.wav",
                        gain: 0
                    ),
                ],
                haptics: []
            )
        }
        return [
            conventional(
                id: "causal-approach",
                cueID: "causal-approach-world",
                path: "audio/causal-approach.wav"
            ),
        ] + interaction + [
            conventional(
                id: "causal-consequence",
                cueID: "causal-consequence-world",
                path: "audio/causal-consequence.wav"
            ),
        ]
    }

    private static var causalAssetMetadata: [String: AudioAssetMetadata] {
        var result: [String: AudioAssetMetadata] = [:]
        for event in causalTimelines().flatMap(\.events) {
            guard let path = event.assetPath else { continue }
            result[path] = AudioAssetMetadata(
                path: path,
                sampleRate: 48_000,
                frameCount: event.durationSamples,
                channelCount: 2
            )
        }
        return result
    }

    private static func bedTimeline(
        id: AudioTimelineID,
        scoreCueID: AudioCueID,
        scorePath: String,
        soundscapeCueID: AudioCueID,
        soundscapePath: String
    ) -> AudioTimeline {
        AudioTimeline(
            id: id,
            sampleRate: 48_000,
            events: [
                audibleEvent(
                    cueID: scoreCueID,
                    role: .score,
                    startSample: 0,
                    durationSamples: 96_000,
                    assetPath: scorePath
                ),
                audibleEvent(
                    cueID: soundscapeCueID,
                    role: .soundscape,
                    startSample: 0,
                    durationSamples: 96_000,
                    assetPath: soundscapePath
                ),
            ],
            haptics: []
        )
    }

    private static func audibleEvent(
        cueID: AudioCueID,
        role: AudioTrackRole,
        startSample: Int64,
        durationSamples: Int64,
        assetPath: String
    ) -> AudioEvent {
        AudioEvent(
            cueID: cueID,
            role: role,
            startSample: startSample,
            durationSamples: durationSamples,
            assetPath: assetPath,
            gain: 0.6
        )
    }

    private static var assetMetadata: [String: AudioAssetMetadata] {
        var result: [String: AudioAssetMetadata] = [:]
        for timeline in timelines() {
            for event in timeline.events where event.role != .silence {
                let path = event.assetPath!
                let channels: Int = switch event.role {
                case .narration:
                    1
                case .score, .soundscape:
                    2
                case .spatialDetail:
                    1
                case .silence:
                    0
                }
                result[path] = AudioAssetMetadata(
                    path: path,
                    sampleRate: 48_000,
                    frameCount: event.durationSamples,
                    channelCount: channels
                )
            }
        }
        return result
    }

    private static func committer(
        scope: ResponsiveAudioProgramScope,
        spec: InteractionSpec
    ) -> DurableJourneyCommitter {
        let interaction = InteractionRuntimeState(spec: spec)
        let session = ChapterSession(
            chapterID: scope.chapterID,
            packageID: "essential-launch",
            contentVersion: SchemaVersion(major: 1),
            arcID: scope.arcID,
            beatID: scope.beatID,
            interaction: interaction
        )
        let state = JourneyState(
            route: .chapter(scope.chapterID),
            world: WorldGraph(),
            activeChapter: session
        )
        return DurableJourneyCommitter(
            restoredState: state,
            lastSequence: 0,
            append: { request in UInt64(request.event.logicalTimeMillis) }
        )
    }

    private static func makeCompletionCommit(
        scope: ResponsiveAudioProgramScope
    ) async throws -> DurableJourneyCommit {
        let spec = interactionSpec
        let committer = committer(scope: scope, spec: spec)
        return try await committer.commit(
            .interact(
                spec: spec,
                action: .transform(controlID: "press-grain", amount: 1)
            )
        )
    }
}

private struct NoopOfflineAudioResolver: OfflineAudioAssetResolving {
    func url(for packageRelativePath: String) throws -> URL {
        URL(fileURLWithPath: "/nonshipping/\(packageRelativePath)")
    }
}

@MainActor
private final class InMemoryResponsiveTimelineTransport: ResponsiveAudioTimelineTransport {
    enum Failure: Error, Equatable {
        case injectedTransition
        case injectedAutomaticBoundary
        case injectedPauseAfterStateTouch
        case injectedPrepareAfterStateTouch
    }
    var preparedTimelineID: AudioTimelineID?
    var cursorSample: Int64 = 0
    var loopIteration: UInt64 = 0
    var isPlaying = false
    var appliedPreferences: ExperiencePreferences?
    var prepareCount = 0
    var transitionCount = 0
    var pauseCount = 0
    var playCount = 0
    var commonPlayerIdentity: Int?
    var commonScheduleCount = 0
    var targetGains: [ResponsiveAudioMaterialLayerID: Double] = [:]
    var transitionFailure: Failure?
    var pauseFailureAfterStateTouch: Failure?
    var prepareFailureAfterStateTouch: Failure?
    var transitionSnapshotOverride: NativeTimelineTransportSnapshot?
    var automaticBoundaryConfigureCount = 0
    var automaticBoundaryFailuresRemaining = 0
    var automaticSuccessorPlan: ResponsiveAudioTimelineTransportPlan?
    var automaticCurrentDurationSamples: Int64?
    var automaticBoundaryHandler:
        ((ResponsiveAudioAutomaticBoundaryEvent) -> Void)?
    var capturedAutomaticBoundaryHandlers:
        [(ResponsiveAudioAutomaticBoundaryEvent) -> Void] = []
    private var preparedPlan: ResponsiveAudioTimelineTransportPlan?
    private var nextCommonPlayerIdentity = 1

    func prepare(
        timeline: AudioTimeline,
        cursorSample: Int64,
        resolver _: any OfflineAudioAssetResolving
    ) throws {
        prepareCount += 1
        preparedTimelineID = timeline.id
        self.cursorSample = cursorSample
        loopIteration = 0
        isPlaying = false
        preparedPlan = ResponsiveAudioTimelineTransportPlan(
            timeline: timeline,
            cursorSample: cursorSample,
            loopIteration: 0,
            repetition: .once,
            causalMix: nil
        )
    }

    func prepareResponsiveAudio(
        plan: ResponsiveAudioTimelineTransportPlan,
        resolver _: any OfflineAudioAssetResolving
    ) throws {
        prepareCount += 1
        preparedTimelineID = plan.timeline.id
        cursorSample = plan.cursorSample
        loopIteration = plan.loopIteration
        isPlaying = false
        preparedPlan = plan
        if let mix = plan.causalMix {
            commonPlayerIdentity = nextCommonPlayerIdentity
            nextCommonPlayerIdentity += 1
            commonScheduleCount += 1
            targetGains = Dictionary(uniqueKeysWithValues: mix.layers.map {
                ($0.layerID, $0.targetGain)
            })
        } else {
            commonPlayerIdentity = nil
            targetGains = [:]
        }
        if let prepareFailureAfterStateTouch {
            self.prepareFailureAfterStateTouch = nil
            throw prepareFailureAfterStateTouch
        }
    }

    func transitionResponsiveAudio(
        to plan: ResponsiveAudioTimelineTransportPlan,
        resolver _: any OfflineAudioAssetResolving,
        validateBeforeCommit: (
            NativeTimelineTransportSnapshot
        ) throws -> Void
    ) throws -> NativeTimelineTransportSnapshot {
        transitionCount += 1
        automaticBoundaryHandler = nil
        automaticSuccessorPlan = nil
        automaticCurrentDurationSamples = nil
        if let transitionFailure { throw transitionFailure }
        let candidateTargetGains: [ResponsiveAudioMaterialLayerID: Double]
        if let mix = plan.causalMix {
            candidateTargetGains = Dictionary(uniqueKeysWithValues: mix.layers.map {
                ($0.layerID, $0.targetGain)
            })
        } else {
            candidateTargetGains = [:]
        }
        let authoritativeSnapshot = transitionSnapshotOverride
            ?? NativeTimelineTransportSnapshot(
                timelineID: plan.timeline.id,
                cursorSample: plan.cursorSample,
                loopIteration: plan.loopIteration,
                isPlaying: isPlaying
            )
        try validateBeforeCommit(authoritativeSnapshot)
        preparedTimelineID = plan.timeline.id
        cursorSample = plan.cursorSample
        loopIteration = plan.loopIteration
        targetGains = candidateTargetGains
        preparedPlan = plan
        if plan.causalMix == nil {
            commonPlayerIdentity = nil
        }
        return authoritativeSnapshot
    }

    func play() throws {
        playCount += 1
        isPlaying = true
    }

    func pause() throws -> NativeTimelineTransportSnapshot {
        pauseCount += 1
        if let duration = automaticCurrentDurationSamples,
           cursorSample >= duration {
            triggerAutomaticBoundary()
        }
        isPlaying = false
        let pausedSnapshot = snapshot()
        if let pauseFailureAfterStateTouch {
            self.pauseFailureAfterStateTouch = nil
            throw pauseFailureAfterStateTouch
        }
        return pausedSnapshot
    }

    func snapshot() -> NativeTimelineTransportSnapshot {
        let snapshotCursor: Int64
        if isPlaying,
           automaticBoundaryHandler != nil,
           let duration = automaticCurrentDurationSamples {
            snapshotCursor = min(cursorSample, max(0, duration - 1))
        } else {
            snapshotCursor = cursorSample
        }
        return NativeTimelineTransportSnapshot(
            timelineID: preparedTimelineID,
            cursorSample: snapshotCursor,
            loopIteration: loopIteration,
            isPlaying: isPlaying
        )
    }

    func applyPreferences(_ preferences: ExperiencePreferences) {
        appliedPreferences = preferences
    }

    func configureAutomaticBoundary(
        successorPlan: ResponsiveAudioTimelineTransportPlan?,
        resolver _: any OfflineAudioAssetResolving,
        handler: @escaping (ResponsiveAudioAutomaticBoundaryEvent) -> Void
    ) throws {
        automaticBoundaryConfigureCount += 1
        automaticSuccessorPlan = successorPlan
        automaticCurrentDurationSamples = preparedPlan?.timeline
            .authoredDurationSamples
        automaticBoundaryHandler = handler
        capturedAutomaticBoundaryHandlers.append(handler)
        if automaticBoundaryFailuresRemaining > 0 {
            automaticBoundaryFailuresRemaining -= 1
            automaticSuccessorPlan = nil
            automaticCurrentDurationSamples = nil
            automaticBoundaryHandler = nil
            throw Failure.injectedAutomaticBoundary
        }
    }

    func triggerAutomaticBoundary() {
        guard let handler = automaticBoundaryHandler,
              let duration = automaticCurrentDurationSamples else { return }
        automaticBoundaryHandler = nil
        automaticCurrentDurationSamples = nil
        if let successor = automaticSuccessorPlan {
            automaticSuccessorPlan = nil
            preparedPlan = successor
            preparedTimelineID = successor.timeline.id
            cursorSample = 0
            loopIteration = 0
            if let mix = successor.causalMix {
                commonPlayerIdentity = nextCommonPlayerIdentity
                nextCommonPlayerIdentity += 1
                commonScheduleCount += 1
                targetGains = Dictionary(uniqueKeysWithValues: mix.layers.map {
                    ($0.layerID, $0.targetGain)
                })
            } else {
                commonPlayerIdentity = nil
                targetGains = [:]
            }
            handler(.successorStarted(NativeTimelineTransportSnapshot(
                timelineID: successor.timeline.id,
                cursorSample: 0,
                loopIteration: 0,
                isPlaying: true
            )))
        } else {
            cursorSample = duration
            loopIteration = 0
            isPlaying = false
            handler(.completed(NativeTimelineTransportSnapshot(
                timelineID: preparedTimelineID,
                cursorSample: duration,
                loopIteration: 0,
                isPlaying: false
            )))
        }
    }

    func stop() {
        preparedTimelineID = nil
        cursorSample = 0
        loopIteration = 0
        isPlaying = false
        commonPlayerIdentity = nil
        targetGains = [:]
        preparedPlan = nil
        automaticBoundaryHandler = nil
        automaticSuccessorPlan = nil
        automaticCurrentDurationSamples = nil
    }
}
