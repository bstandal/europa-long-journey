@testable import ChapterRuntime
import ContentKit
import DramaticAudio
import Dispatch
import Foundation
import JourneyAccessibility
import JourneyContent
import JourneyDomain
import ProgressStore
import SceneRuntime
import XCTest

@MainActor
final class ChapterSceneRuntimeControllerTests: XCTestCase {
    func testInjectedCommitterRestoreBuildsFrameMetalAndSemanticPresentation() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy(startingSequence: 7)
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 7,
            append: { request in try await journal.append(request.event) }
        )

        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )

        XCTAssertEqual(controller.presentation.journeyState, fixture.state)
        XCTAssertEqual(controller.presentation.cursor.chapter.id, RuntimeTestFixture.chapterID)
        XCTAssertEqual(controller.presentation.cursor.arc.id, RuntimeTestFixture.arcID)
        XCTAssertEqual(controller.presentation.cursor.beat.id, RuntimeTestFixture.beatID)
        XCTAssertEqual(
            controller.presentation.framePlan.sceneID,
            controller.presentation.cursor.scene.id
        )
        XCTAssertEqual(
            controller.presentation.metalPreparationPlan.sceneID,
            controller.presentation.framePlan.sceneID
        )
        XCTAssertFalse(controller.presentation.framePlan.drawCommands.isEmpty)
        XCTAssertFalse(controller.presentation.metalPreparationPlan.drawCommands.isEmpty)
        XCTAssertEqual(
            controller.presentation.semanticInteractionModel?.controls.map(\.id),
            ["route-control-accessibility"]
        )
        XCTAssertNil(controller.presentation.directManipulation)
        XCTAssertNil(controller.presentation.interactionFeedback)
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 0)
    }

    func testContinuousTouchPreviewRespondsWithinFiftyMillisecondsWithoutDurableSideEffects() async throws {
        let fixture = try RuntimeTestFixture.pressure()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let log = EventLog()
        let journal = JournalSpy(log: log)
        let controller = try await makeController(
            fixture: fixture,
            journal: journal,
            hapticBridge: HapticSpy(log: log)
        )
        let target = try targetPoint(
            "runtime-defence-target",
            in: controller
        )
        let durablePresentation = controller.presentation
        let durableInteraction = try XCTUnwrap(
            durablePresentation.journeyState.activeChapter?.interaction
        )
        let textureKeys = durablePresentation.metalPreparationPlan
            .textureRequests.map(\.key)
        var maximumLatencyNanoseconds: UInt64 = 0

        for index in 0..<120 {
            let started = DispatchTime.now().uptimeNanoseconds
            let preview = try controller.previewContinuousTouch(
                .adjustTarget(
                    viewportPoint: target,
                    amount: index.isMultiple(of: 2) ? 0.1 : 0.2
                ),
                displayedFramePlan: durablePresentation.framePlan
            )
            maximumLatencyNanoseconds = max(
                maximumLatencyNanoseconds,
                DispatchTime.now().uptimeNanoseconds - started
            )

            XCTAssertEqual(controller.presentation, durablePresentation)
            XCTAssertEqual(
                preview.presentation.journeyState,
                durablePresentation.journeyState
            )
            XCTAssertEqual(
                preview.presentation.framePlan.drawCommands,
                durablePresentation.framePlan.drawCommands
            )
            XCTAssertEqual(
                preview.presentation.metalPreparationPlan.textureRequests
                    .map(\.key),
                textureKeys
            )
            XCTAssertNotNil(
                preview.presentation.framePlan.interactionResponse
            )
            XCTAssertNil(preview.presentation.interactionFeedback)
            XCTAssertNil(preview.presentation.directManipulation)
            XCTAssertNotEqual(
                preview.interactionPreview.candidateState,
                durableInteraction
            )
        }

        XCTAssertLessThanOrEqual(
            maximumLatencyNanoseconds,
            50_000_000,
            "Raw visual feedback must be available inside the 50 ms interaction budget"
        )
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 0)
        XCTAssertTrue(log.events.isEmpty)
    }

    func testContinuousTracePreviewClassifiesAnchorsButDurableInputStillStartsFromCommittedAuthority() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let log = EventLog()
        let journal = JournalSpy(log: log)
        let controller = try await makeController(
            fixture: fixture,
            journal: journal,
            hapticBridge: HapticSpy(log: log)
        )
        let durablePresentation = controller.presentation

        for (index, point) in RuntimeTestFixture.traceTouchPoints.enumerated() {
            let preview = try controller.previewContinuousTouch(
                .trace(viewportPoint: point),
                displayedFramePlan: durablePresentation.framePlan
            )
            XCTAssertEqual(preview.semantic, .traceAnchor(index))
            XCTAssertEqual(controller.presentation, durablePresentation)
            XCTAssertEqual(
                preview.presentation.journeyState,
                durablePresentation.journeyState
            )
            if index == RuntimeTestFixture.traceTouchPoints.count - 1 {
                XCTAssertEqual(
                    preview.interactionPreview.candidateState.phase,
                    .complete
                )
            }
        }

        let repeatedTerminal = try controller.previewContinuousTouch(
            .trace(viewportPoint: RuntimeTestFixture.traceTouchPoints.last!),
            displayedFramePlan: durablePresentation.framePlan
        )
        XCTAssertEqual(repeatedTerminal.semantic, .ordinary)
        XCTAssertEqual(controller.presentation, durablePresentation)
        let previewJournalCount = await journal.count()
        XCTAssertEqual(previewJournalCount, 0)
        XCTAssertTrue(log.events.isEmpty)

        let committed = try await controller.submitTouch(
            .trace(viewportPoint: RuntimeTestFixture.traceTouchPoints[0])
        )
        guard case let .trace(progress)? = committed.presentation.journeyState
            .activeChapter?.interaction?.progress else {
            return XCTFail("Durable Trace must reduce from committed authority")
        }
        XCTAssertEqual(progress.reachedAnchorCount, 1)
        XCTAssertEqual(
            committed.presentation.journeyState.activeChapter?.interaction?.phase,
            .active
        )
        let committedJournalCount = await journal.count()
        XCTAssertEqual(committedJournalCount, 1)
    }

    func testContinuousTouchPreviewClassifiesPressureBoundariesAndTransformStageWithoutCompleting() async throws {
        let pressureFixture = try RuntimeTestFixture.pressure()
        let transformFixture = try RuntimeTestFixture.transform()
        defer {
            try? FileManager.default.removeItem(at: pressureFixture.packageRoot)
            try? FileManager.default.removeItem(at: transformFixture.packageRoot)
        }
        let pressureJournal = JournalSpy()
        let pressure = try await makeController(
            fixture: pressureFixture,
            journal: pressureJournal
        )
        let pressureTarget = try targetPoint(
            "runtime-defence-target",
            in: pressure
        )
        let pressureFrame = pressure.presentation.framePlan

        let entered = try pressure.previewContinuousTouch(
            .adjustTarget(viewportPoint: pressureTarget, amount: 0.4),
            displayedFramePlan: pressureFrame
        )
        XCTAssertEqual(
            entered.semantic,
            .pressureStabilityBoundary(isStable: true)
        )
        let exited = try pressure.previewContinuousTouch(
            .adjustTarget(viewportPoint: pressureTarget, amount: 0),
            displayedFramePlan: pressureFrame
        )
        XCTAssertEqual(
            exited.semantic,
            .pressureStabilityBoundary(isStable: false)
        )
        XCTAssertEqual(
            pressure.presentation.journeyState,
            pressureFixture.state
        )
        let pressureJournalCount = await pressureJournal.count()
        XCTAssertEqual(pressureJournalCount, 0)

        let transformJournal = JournalSpy()
        let transform = try await makeController(
            fixture: transformFixture,
            journal: transformJournal
        )
        let transformTarget = try targetPoint(
            "runtime-clear-target",
            in: transform
        )
        let transformFrame = transform.presentation.framePlan
        let stage = try transform.previewContinuousTouch(
            .adjustTarget(viewportPoint: transformTarget, amount: 1),
            displayedFramePlan: transformFrame
        )
        XCTAssertEqual(stage.semantic, .transformStage(0))
        XCTAssertEqual(stage.interactionPreview.candidateState.phase, .complete)
        XCTAssertEqual(
            stage.presentation.journeyState.activeChapter?.interaction?.phase,
            .ready
        )
        XCTAssertEqual(
            transform.presentation.journeyState,
            transformFixture.state
        )
        let repeatedStage = try transform.previewContinuousTouch(
            .adjustTarget(viewportPoint: transformTarget, amount: 1),
            displayedFramePlan: transformFrame
        )
        XCTAssertEqual(repeatedStage.semantic, .ordinary)
        let transformJournalCount = await transformJournal.count()
        XCTAssertEqual(transformJournalCount, 0)
    }

    func testExplicitResponsiveAudioSynchronizationPublishesBeforeFirstTrace() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        let audioCommit = try await committer.commit(
            .beginResponsiveAudioSession(
                chapterOpenNonce: UUID(),
                generation: 1,
                snapshot: try waitingResponsiveAudioSnapshot(in: fixture)
            )
        )

        XCTAssertNotEqual(
            controller.presentation.journeyState,
            audioCommit.state,
            "The test must begin with the real pre-audio presentation drift"
        )
        let synchronized = try await controller
            .synchronizeResponsiveAudioPresentation()
        XCTAssertEqual(synchronized.journeyState, audioCommit.state)
        XCTAssertTrue(
            synchronized.journeyState.activeChapter?
                .responsiveAudioSessionIsActive == true
        )

        let transition = try await controller.submitTouch(
            .trace(viewportPoint: RuntimeTestFixture.traceTouchPoints[0]),
            alphaSampler: OpaqueMaskSampler()
        )
        guard case let .trace(progress)? = transition.presentation.journeyState
            .activeChapter?.interaction?.progress else {
            return XCTFail("The synchronized controller must process Trace")
        }
        XCTAssertEqual(progress.reachedAnchorCount, 1)
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 2)
    }

    func testFirstTraceReconcilesResponsiveAudioRaceWithoutEagerSynchronization() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        _ = try await committer.commit(
            .beginResponsiveAudioSession(
                chapterOpenNonce: UUID(),
                generation: 1,
                snapshot: try waitingResponsiveAudioSnapshot(in: fixture)
            )
        )

        let transition = try await controller.submitTouch(
            .trace(viewportPoint: RuntimeTestFixture.traceTouchPoints[0]),
            alphaSampler: OpaqueMaskSampler()
        )
        guard case let .trace(progress)? = transition.presentation.journeyState
            .activeChapter?.interaction?.progress else {
            return XCTFail("The input-time audio reconciliation must process Trace")
        }
        XCTAssertEqual(progress.reachedAnchorCount, 1)
        XCTAssertTrue(
            transition.presentation.journeyState.activeChapter?
                .responsiveAudioSessionIsActive == true
        )
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 2)
    }

    func testVoiceOverReconcilesAutomaticResponsiveAudioSnapshotBeforeInput() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        _ = try await committer.commit(
            .beginResponsiveAudioSession(
                chapterOpenNonce: UUID(),
                generation: 1,
                snapshot: try waitingResponsiveAudioSnapshot(in: fixture)
            )
        )
        _ = try await controller.synchronizeResponsiveAudioPresentation()
        let automaticBoundary = try responsiveAudioSnapshot(
            in: fixture,
            cursorSample: 480
        )
        let boundaryCommit = try await committer.commit(
            .setResponsiveAudioSnapshot(automaticBoundary)
        )
        XCTAssertNotEqual(
            controller.presentation.journeyState,
            boundaryCommit.state,
            "The input must close the real automatic-boundary race"
        )

        let authoredAction = try XCTUnwrap(
            fixture.accessibility.elements.first?.actions.first
        )
        let transition = try await controller.submitVoiceOver(
            elementID: "route-control-accessibility",
            authoredAction: authoredAction
        )
        XCTAssertEqual(
            transition.presentation.journeyState.activeChapter?
                .responsiveAudioSnapshot,
            automaticBoundary
        )
        guard case let .trace(progress)? = transition.presentation.journeyState
            .activeChapter?.interaction?.progress else {
            return XCTFail("VoiceOver must continue through the audio boundary")
        }
        XCTAssertEqual(progress.reachedAnchorCount, 1)
        XCTAssertNotNil(transition.durableCommit)
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 3)
    }

    func testTouchReconcilesEndedResponsiveAudioSessionBeforeInput() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        _ = try await committer.commit(
            .beginResponsiveAudioSession(
                chapterOpenNonce: UUID(),
                generation: 1,
                snapshot: try waitingResponsiveAudioSnapshot(in: fixture)
            )
        )
        _ = try await controller.synchronizeResponsiveAudioPresentation()
        let endedSnapshot = try responsiveAudioSnapshot(
            in: fixture,
            cursorSample: 960
        )
        let endedCommit = try await committer.commit(
            .endResponsiveAudioSession(endedSnapshot)
        )
        XCTAssertNotEqual(
            controller.presentation.journeyState,
            endedCommit.state,
            "The input must close the real session-end race"
        )

        let transition = try await controller.submitTouch(
            .trace(viewportPoint: RuntimeTestFixture.traceTouchPoints[0])
        )
        XCTAssertEqual(
            transition.presentation.journeyState.activeChapter?
                .responsiveAudioSnapshot,
            endedSnapshot
        )
        XCTAssertFalse(
            try XCTUnwrap(
                transition.presentation.journeyState.activeChapter?
                    .responsiveAudioSessionIsActive
            )
        )
        guard case let .trace(progress)? = transition.presentation.journeyState
            .activeChapter?.interaction?.progress else {
            return XCTFail("Touch must continue after the audio session ends")
        }
        XCTAssertEqual(progress.reachedAnchorCount, 1)
        XCTAssertNotNil(transition.durableCommit)
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 3)
    }

    func testLifecycleRestoreAdoptsSuspensionBeforeAudioOnlySynchronizationResumes() async throws {
        let fixture = try RuntimeTestFixture.harvestAllocate()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        let source = try XCTUnwrap(
            controller.presentation.framePlan.interactionSourceHitRegion
        )
        let destination = try XCTUnwrap(
            controller.presentation.framePlan.interactionHitRegions.first {
                $0.interactionTargetID == "winter-food-target"
            }
        )
        let interaction = try await controller.submitTouch(
            .allocateDrop(
                sourceViewportPoint: centroid(source.viewportPath),
                destinationViewportPoint: centroid(destination.viewportPath),
                destinationUnits: 2,
                progress: 0.9
            ),
            alphaSampler: OpaqueMaskSampler()
        )
        let feedback = try XCTUnwrap(interaction.presentation.interactionFeedback)
        XCTAssertEqual(feedback, .progress)
        XCTAssertEqual(
            interaction.presentation.directManipulation?.phase,
            .accepted
        )

        let suspended = try await committer.commit(
            .suspendChapter(atEpochMillis: 123_456)
        )
        XCTAssertEqual(
            suspended.state.activeChapter?.lastVisitedAtEpochMillis,
            123_456
        )
        XCTAssertNotEqual(
            controller.presentation.journeyState,
            suspended.state,
            "The controller must still hold the exact pre-suspension presentation"
        )

        do {
            _ = try await controller.synchronizeResponsiveAudioPresentation(
                preserving: feedback,
                directManipulation: nil
            )
            XCTFail("suspendChapter and lastVisited drift cannot enter through the audio-only seam")
        } catch {
            XCTAssertEqual(
                error as? ChapterSceneRuntimeControllerError,
                .presentationDivergedFromCommitter
            )
        }
        XCTAssertEqual(
            controller.presentation.journeyState,
            interaction.presentation.journeyState
        )
        XCTAssertEqual(
            controller.presentation.directManipulation?.phase,
            .accepted,
            "A rejected audio-only refresh must not partially mutate presentation state"
        )

        let restored = try await controller.restorePresentation(
            preserving: feedback,
            directManipulation: nil
        )
        XCTAssertEqual(restored.journeyState, suspended.state)
        XCTAssertEqual(
            restored.journeyState.activeChapter?.lastVisitedAtEpochMillis,
            123_456
        )
        XCTAssertEqual(restored.interactionFeedback, feedback)
        XCTAssertNil(
            restored.directManipulation,
            "Lifecycle restoration must discard the ended direct manipulation"
        )

        let audioCommit = try await committer.commit(
            .beginResponsiveAudioSession(
                chapterOpenNonce: UUID(),
                generation: 1,
                snapshot: try waitingResponsiveAudioSnapshot(in: fixture)
            )
        )
        let synchronized = try await controller
            .synchronizeResponsiveAudioPresentation(
                preserving: restored.interactionFeedback,
                directManipulation: nil
            )
        XCTAssertEqual(synchronized.journeyState, audioCommit.state)
        XCTAssertEqual(synchronized.interactionFeedback, feedback)
        XCTAssertNil(synchronized.directManipulation)
        XCTAssertTrue(
            synchronized.journeyState.activeChapter?
                .responsiveAudioSessionIsActive == true
        )
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 3)
    }

    func testResponsiveAudioSynchronizationRejectsCameraDrift() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        _ = try await committer.commit(.setCameraAnchor(0.75))

        do {
            _ = try await controller.synchronizeResponsiveAudioPresentation()
            XCTFail("A camera change is not a responsive-audio rebase")
        } catch {
            XCTAssertEqual(
                error as? ChapterSceneRuntimeControllerError,
                .presentationDivergedFromCommitter
            )
        }
        XCTAssertEqual(controller.presentation.journeyState, fixture.state)
    }

    func testResponsiveAudioSynchronizationRejectsInteractionDrift() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        _ = try await committer.commit(
            .interact(
                spec: fixture.interaction,
                action: .trace(NormalizedPoint(x: 0.36, y: 0.5))
            )
        )

        do {
            _ = try await controller.synchronizeResponsiveAudioPresentation()
            XCTFail("Interaction progress cannot enter through the audio seam")
        } catch {
            XCTAssertEqual(
                error as? ChapterSceneRuntimeControllerError,
                .presentationDivergedFromCommitter
            )
        }
        XCTAssertEqual(controller.presentation.journeyState, fixture.state)
    }

    func testResponsiveAudioSynchronizationRejectsRouteDrift() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        _ = try await committer.commit(.showWorld)

        do {
            _ = try await controller.synchronizeResponsiveAudioPresentation()
            XCTFail("A route change is not a responsive-audio rebase")
        } catch {
            XCTAssertEqual(
                error as? ChapterSceneRuntimeControllerError,
                .presentationDivergedFromCommitter
            )
        }
        XCTAssertEqual(controller.presentation.journeyState, fixture.state)
    }

    func testResponsiveAudioSynchronizationRejectsBeatDrift() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        var legacyState = fixture.state
        var legacySession = try XCTUnwrap(legacyState.activeChapter)
        legacySession.beatCompletionContract = nil
        legacyState.activeChapter = legacySession
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: legacyState,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        _ = try await committer.commit(
            .enterBeat(
                arcID: RuntimeTestFixture.arcID,
                beatID: "chapter-runtime-drifted-beat"
            )
        )

        do {
            _ = try await controller.synchronizeResponsiveAudioPresentation()
            XCTFail("A beat change is not a responsive-audio rebase")
        } catch {
            XCTAssertEqual(
                error as? ChapterSceneRuntimeControllerError,
                .presentationDivergedFromCommitter
            )
        }
        XCTAssertEqual(controller.presentation.journeyState, legacyState)
    }

    func testResponsiveAudioSynchronizationRejectsWorldEffectDrift() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        guard case let .trace(trace) = fixture.interaction.grammar else {
            return XCTFail("Expected Trace fixture")
        }
        var externalCommit: DurableJourneyCommit?
        for anchor in trace.anchors {
            externalCommit = try await committer.commit(
                .interact(spec: fixture.interaction, action: .trace(anchor))
            )
        }
        let changed = try XCTUnwrap(externalCommit)
        XCTAssertNotEqual(changed.state.world, fixture.state.world)

        do {
            _ = try await controller.synchronizeResponsiveAudioPresentation()
            XCTFail("A world consequence cannot enter through the audio seam")
        } catch {
            XCTAssertEqual(
                error as? ChapterSceneRuntimeControllerError,
                .presentationDivergedFromCommitter
            )
        }
        XCTAssertEqual(controller.presentation.journeyState, fixture.state)
    }

    func testTraceResolverTreatsOnlyImmediateInToleranceEndpointJitterAsSemanticallyEmpty() async throws {
        let fixture = try RuntimeTestFixture.trace(seedReachedAnchors: 1)
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let controller = try await makeController(
            fixture: fixture,
            journal: JournalSpy()
        )
        let runtimeState = try XCTUnwrap(
            fixture.state.activeChapter?.interaction
        )
        let frame = controller.presentation.framePlan
        let scene = controller.presentation.cursor.scene

        let endpointJitter = try SceneTouchActionResolver.resolve(
            .trace(viewportPoint: SceneFramePoint(x: 0.312, y: 0.5)),
            scene: scene,
            interaction: fixture.interaction,
            runtimeState: runtimeState,
            frame: frame
        )
        XCTAssertNil(endpointJitter.action)
        XCTAssertNil(endpointJitter.directManipulation)
        XCTAssertEqual(endpointJitter.targetID, "route-control")

        let departed = try SceneTouchActionResolver.resolve(
            .trace(viewportPoint: SceneFramePoint(x: 0.34, y: 0.5)),
            scene: scene,
            interaction: fixture.interaction,
            runtimeState: runtimeState,
            frame: frame
        )
        let departedAction = try XCTUnwrap(departed.action)

        var departedState = fixture.state
        let effects = JourneyReducer().reduce(
            state: &departedState,
            action: .interact(
                spec: fixture.interaction,
                action: departedAction
            )
        )
        XCTAssertFalse(effects.contains { effect in
            if case .rejected = effect { return true }
            return false
        })
        let afterDeparture = try XCTUnwrap(
            departedState.activeChapter?.interaction
        )

        let returned = try SceneTouchActionResolver.resolve(
            .trace(viewportPoint: SceneFramePoint(x: 0.31, y: 0.5)),
            scene: scene,
            interaction: fixture.interaction,
            runtimeState: afterDeparture,
            frame: frame
        )
        XCTAssertNotNil(
            returned.action,
            "Returning after leaving the authored tolerance field is real Trace input"
        )
    }

    func testTraceEndpointJitterPreservesContactAndRouteMovementStaysEngaged() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let controller = try await makeController(
            fixture: fixture,
            journal: journal
        )

        let first = try await controller.submitTouch(
            .trace(viewportPoint: SceneFramePoint(x: 0.31, y: 0.5))
        )
        XCTAssertEqual(first.presentation.interactionFeedback, .contact)
        XCTAssertNotNil(first.durableCommit)

        let jitter = try await controller.submitTouch(
            .trace(viewportPoint: SceneFramePoint(x: 0.312, y: 0.5))
        )
        XCTAssertNil(jitter.preview)
        XCTAssertNil(jitter.durableCommit)
        XCTAssertNil(jitter.presentation.directManipulation)
        XCTAssertEqual(jitter.presentation.journeyState, first.presentation.journeyState)
        XCTAssertEqual(jitter.presentation.interactionFeedback, .contact)
        XCTAssertEqual(
            SceneResponsiveAudioPhaseResolver.phase(
                interactionPhase: jitter.presentation.journeyState.activeChapter?
                    .interaction?.phase,
                feedback: jitter.presentation.interactionFeedback,
                directManipulation: jitter.presentation.directManipulation
            ),
            .engaged
        )
        let countAfterJitter = await journal.count()
        XCTAssertEqual(countAfterJitter, 1)

        let departed = try await controller.submitTouch(
            .trace(viewportPoint: SceneFramePoint(x: 0.34, y: 0.5))
        )
        XCTAssertEqual(departed.presentation.interactionFeedback, .progress)
        XCTAssertNotNil(departed.durableCommit)

        let returned = try await controller.submitTouch(
            .trace(viewportPoint: SceneFramePoint(x: 0.31, y: 0.5))
        )
        XCTAssertEqual(returned.presentation.interactionFeedback, .progress)
        XCTAssertNotNil(returned.durableCommit)
        let finalCount = await journal.count()
        XCTAssertEqual(finalCount, 3)
    }

    func testTraceHapticsUseContactDragAndSealWithoutResistancePulse() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let log = EventLog()
        let controller = try await makeController(
            fixture: fixture,
            journal: JournalSpy(log: log),
            hapticBridge: HapticSpy(log: log)
        )

        let origin = try await controller.submitTouch(
            .trace(viewportPoint: SceneFramePoint(x: 0.31, y: 0.5))
        )
        XCTAssertEqual(origin.presentation.interactionFeedback, .contact)

        let viableMovement = try await controller.submitTouch(
            .trace(viewportPoint: SceneFramePoint(x: 0.35, y: 0.5))
        )
        XCTAssertEqual(viableMovement.presentation.interactionFeedback, .progress)

        let offCorridor = try await controller.submitTouch(
            .trace(viewportPoint: SceneFramePoint(x: 0.35, y: 0.56))
        )
        XCTAssertEqual(offCorridor.presentation.interactionFeedback, .resistance)

        for point in RuntimeTestFixture.traceTouchPoints.dropFirst() {
            _ = try await controller.submitTouch(.trace(viewportPoint: point))
        }

        XCTAssertEqual(
            log.events,
            [
                "append-interaction", "haptic-contact",
                "append-interaction", "haptic-drag",
                "append-interaction",
                "append-interaction", "haptic-contact",
                "append-interaction", "haptic-contact",
                "append-interaction", "haptic-seal",
            ],
            "Off-corridor resistance must stay visual/audible, and the destination must emit only its durable seal"
        )
    }

    func testTouchAndVoiceOverConvergeOnIdenticalDurableFinalState() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let touchJournal = JournalSpy()
        let semanticJournal = JournalSpy()
        let touchController = try await makeController(
            fixture: fixture,
            journal: touchJournal
        )
        let semanticController = try await makeController(
            fixture: fixture,
            journal: semanticJournal
        )
        let voiceOverAction = try XCTUnwrap(
            fixture.accessibility.elements.first?.actions.first
        )

        XCTAssertEqual(
            RuntimeTestFixture.traceTouchPoints.count,
            RuntimeTestFixture.traceAuthoredViewportPoints.count
        )
        for (touchPoint, authoredPoint) in zip(
            RuntimeTestFixture.traceTouchPoints,
            RuntimeTestFixture.traceAuthoredViewportPoints
        ) {
            XCTAssertNotEqual(
                touchPoint,
                authoredPoint,
                "Physical input must exercise tolerance canonicalization instead of hitting the authored anchor exactly."
            )
        }

        for (index, touchPoint) in RuntimeTestFixture.traceTouchPoints.enumerated() {
            let touch = try await touchController.submitTouch(
                .trace(viewportPoint: touchPoint)
            )
            let voiceOver = try await semanticController.submitVoiceOver(
                elementID: "route-control-accessibility",
                authoredAction: voiceOverAction
            )
            XCTAssertNil(touch.postCommitIssue)
            XCTAssertNil(voiceOver.postCommitIssue)
            XCTAssertEqual(touch.preview?.feedback, voiceOver.preview?.feedback)
            XCTAssertEqual(
                touch.presentation.interactionFeedback,
                voiceOver.presentation.interactionFeedback
            )
            let touchPhase = SceneResponsiveAudioPhaseResolver.phase(
                interactionPhase: touch.presentation.journeyState.activeChapter?
                    .interaction?.phase,
                feedback: touch.presentation.interactionFeedback,
                directManipulation: touch.presentation.directManipulation
            )
            let voiceOverPhase = SceneResponsiveAudioPhaseResolver.phase(
                interactionPhase: voiceOver.presentation.journeyState.activeChapter?
                    .interaction?.phase,
                feedback: voiceOver.presentation.interactionFeedback,
                directManipulation: voiceOver.presentation.directManipulation
            )
            XCTAssertEqual(touchPhase, voiceOverPhase)
            XCTAssertEqual(
                touchPhase,
                index == RuntimeTestFixture.traceTouchPoints.count - 1
                    ? nil : .engaged
            )
        }

        XCTAssertEqual(
            touchController.presentation.journeyState,
            semanticController.presentation.journeyState
        )
        XCTAssertEqual(
            touchController.presentation.framePlan,
            semanticController.presentation.framePlan
        )
        XCTAssertEqual(
            touchController.presentation.semanticInteractionModel,
            semanticController.presentation.semanticInteractionModel
        )
        XCTAssertEqual(
            touchController.presentation.journeyState.activeChapter?.interaction?.phase,
            .complete
        )
        XCTAssertTrue(
            touchController.presentation.journeyState.world.appliedEffects.contains(
                fixture.interaction.completionEffects[0]
            )
        )
        let touchCount = await touchJournal.count()
        let semanticCount = await semanticJournal.count()
        XCTAssertEqual(touchCount, 4)
        XCTAssertEqual(semanticCount, 4)
    }

    func testCompleteAllocateTouchAndVoiceOverConverge() async throws {
        let fixture = try RuntimeTestFixture.harvestAllocate()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let touchJournal = JournalSpy()
        let semanticJournal = JournalSpy()
        let touch = try await makeController(fixture: fixture, journal: touchJournal)
        let semantic = try await makeController(
            fixture: fixture,
            journal: semanticJournal
        )
        let steps = [
            ("winter-food-target", "allocate-winter-food", 4),
            ("protected-reserve-target", "allocate-protected-reserve", 2),
            ("spring-seed-target", "allocate-spring-seed", 6),
        ]

        for (targetID, elementID, units) in steps {
            let source = try XCTUnwrap(
                touch.presentation.framePlan.interactionSourceHitRegion
            )
            let destination = try XCTUnwrap(
                touch.presentation.framePlan.interactionHitRegions.first {
                    $0.interactionTargetID == targetID
                }
            )
            _ = try await touch.submitTouch(
                .allocateDrop(
                    sourceViewportPoint: centroid(source.viewportPath),
                    destinationViewportPoint: centroid(destination.viewportPath),
                    destinationUnits: units,
                    progress: 0.8
                ),
                alphaSampler: OpaqueMaskSampler()
            )
            _ = try await semantic.submitVoiceOver(
                elementID: elementID,
                authoredAction: try authoredAction(in: fixture, elementID: elementID)
            )
            XCTAssertEqual(
                touch.presentation.journeyState,
                semantic.presentation.journeyState,
                targetID
            )
        }

        _ = try await touch.submitTouch(.commitAllocation)
        _ = try await semantic.submitVoiceOver(
            elementID: "commit-harvest-allocation",
            authoredAction: try authoredAction(
                in: fixture,
                elementID: "commit-harvest-allocation"
            )
        )

        assertConverged(touch, semantic)
        let touchCount = await touchJournal.count()
        let semanticCount = await semanticJournal.count()
        XCTAssertEqual(touchCount, 4)
        XCTAssertEqual(semanticCount, 4)
    }

    func testOverAllocatedChoiceCanReturnAuthoredStepsAndStillConverge() async throws {
        let fixture = try RuntimeTestFixture.harvestAllocate()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let touchJournal = JournalSpy()
        let semanticJournal = JournalSpy()
        let touch = try await makeController(fixture: fixture, journal: touchJournal)
        let semantic = try await makeController(
            fixture: fixture,
            journal: semanticJournal
        )
        let source = try XCTUnwrap(
            touch.presentation.framePlan.interactionSourceHitRegion
        )
        let sourcePoint = centroid(source.viewportPath)
        let sampler = OpaqueMaskSampler()

        func targetPoint(_ targetID: String) throws -> SceneFramePoint {
            centroid(
                try XCTUnwrap(
                    touch.presentation.framePlan.interactionHitRegions.first {
                        $0.interactionTargetID == targetID
                    }
                ).viewportPath
            )
        }

        func touchSet(
            targetID: String,
            elementID: String,
            units: Int
        ) async throws {
            _ = try await touch.submitTouch(
                .allocateDrop(
                    sourceViewportPoint: sourcePoint,
                    destinationViewportPoint: try targetPoint(targetID),
                    destinationUnits: units,
                    progress: 0.8
                ),
                alphaSampler: sampler
            )
            _ = try await semantic.submitVoiceOver(
                elementID: elementID,
                authoredAction: try authoredAction(
                    in: fixture,
                    elementID: elementID,
                    kind: .increment
                )
            )
            XCTAssertEqual(
                touch.presentation.journeyState,
                semantic.presentation.journeyState
            )
        }

        // Spend the complete harvest on two obligations, leaving spring seed
        // impossible. This is a valid local state, but not a completable one.
        try await touchSet(
            targetID: "winter-food-target",
            elementID: "allocate-winter-food",
            units: 4
        )
        try await touchSet(
            targetID: "winter-food-target",
            elementID: "allocate-winter-food",
            units: 8
        )
        try await touchSet(
            targetID: "protected-reserve-target",
            elementID: "allocate-protected-reserve",
            units: 2
        )
        try await touchSet(
            targetID: "protected-reserve-target",
            elementID: "allocate-protected-reserve",
            units: 4
        )

        for correction in [
            (
                targetID: "protected-reserve-target",
                elementID: "allocate-protected-reserve",
                destinationID: "reserve",
                expectedUnits: 2
            ),
            (
                targetID: "winter-food-target",
                elementID: "allocate-winter-food",
                destinationID: "food",
                expectedUnits: 4
            ),
        ] {
            let returned = try await touch.submitTouch(
                .allocateReturn(
                    destinationViewportPoint: try targetPoint(correction.targetID),
                    resourceViewportPoint: sourcePoint,
                    progress: 0.9
                ),
                alphaSampler: sampler
            )
            _ = try await semantic.submitVoiceOver(
                elementID: correction.elementID,
                authoredAction: try authoredAction(
                    in: fixture,
                    elementID: correction.elementID,
                    kind: .decrement
                )
            )
            XCTAssertEqual(
                returned.preview?.action,
                .allocate(
                    destinationID: correction.destinationID,
                    units: correction.expectedUnits
                )
            )
            XCTAssertEqual(
                touch.presentation.journeyState,
                semantic.presentation.journeyState
            )
        }

        try await touchSet(
            targetID: "spring-seed-target",
            elementID: "allocate-spring-seed",
            units: 6
        )
        _ = try await touch.submitTouch(.commitAllocation)
        _ = try await semantic.submitVoiceOver(
            elementID: "commit-harvest-allocation",
            authoredAction: try authoredAction(
                in: fixture,
                elementID: "commit-harvest-allocation",
                kind: .activate
            )
        )

        assertConverged(touch, semantic)
        let touchCount = await touchJournal.count()
        let semanticCount = await semanticJournal.count()
        XCTAssertEqual(touchCount, 8)
        XCTAssertEqual(semanticCount, 8)
    }

    func testCompleteAssembleTouchAndVoiceOverConverge() async throws {
        let fixture = try RuntimeTestFixture.assemble()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let touchJournal = JournalSpy()
        let semanticJournal = JournalSpy()
        let touch = try await makeController(fixture: fixture, journal: touchJournal)
        let semantic = try await makeController(
            fixture: fixture,
            journal: semanticJournal
        )
        let elementID = "runtime-charter-target-accessibility"
        let source = try targetPoint("runtime-charter-target", in: touch)
        let slot = try targetPoint("runtime-charter-slot", in: touch)

        _ = try await touch.submitTouch(
            .assembleDrop(
                sourceViewportPoint: source,
                slotViewportPoint: slot,
                progress: 1
            )
        )
        _ = try await semantic.submitVoiceOver(
            elementID: elementID,
            authoredAction: try authoredAction(in: fixture, elementID: elementID)
        )

        // Touch intentionally retains a short accepted-placement response;
        // VoiceOver crosses the same durable `.place` boundary without that
        // gesture ephemera. Rebuild both presentations from durable state
        // before comparing the modalities.
        _ = try await touch.restorePresentation()
        assertConverged(touch, semantic)
        let touchCount = await touchJournal.count()
        let semanticCount = await semanticJournal.count()
        XCTAssertEqual(touchCount, 1)
        XCTAssertEqual(semanticCount, 1)
    }

    func testAssembleWrongSlotPreviewsResistanceWithoutJournalMutation() async throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let controller = try await makeController(fixture: fixture, journal: journal)
        let before = controller.presentation.journeyState
        let foundation = try targetPoint("runtime-foundation-target", in: controller)
        let roofSlot = try targetPoint("runtime-roof-slot", in: controller)

        let transition = try await controller.submitTouch(
            .assembleDrop(
                sourceViewportPoint: foundation,
                slotViewportPoint: roofSlot,
                progress: 1
            )
        )

        XCTAssertEqual(
            transition.preview?.action,
            .place(componentID: "foundation", slotID: "cover")
        )
        XCTAssertEqual(transition.preview?.feedback, .resistance)
        XCTAssertNil(transition.durableCommit)
        XCTAssertNil(transition.responsiveAudioCommit)
        XCTAssertEqual(transition.presentation.journeyState, before)
        XCTAssertEqual(transition.presentation.interactionFeedback, .resistance)
        XCTAssertEqual(transition.presentation.directManipulation?.phase, .snapBack)
        XCTAssertEqual(
            transition.presentation.directManipulation?.subjectID,
            "foundation"
        )
        let eventCount = await journal.count()
        XCTAssertEqual(eventCount, 0)
    }

    func testBlockedVoiceOverPlacementStaysAvailableAndRejectsWithoutDurableEvent() async throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let log = EventLog()
        let journal = JournalSpy(log: log)
        let haptics = HapticSpy(log: log)
        let controller = try await makeController(
            fixture: fixture,
            journal: journal,
            hapticBridge: haptics
        )
        let elementID = "runtime-roof-target-accessibility"
        let action = try authoredAction(in: fixture, elementID: elementID)
        XCTAssertNotNil(
            controller.presentation.semanticInteractionModel?.controls.first {
                $0.id == elementID
            }?.actions.first
        )
        let before = controller.presentation.journeyState

        let rejected = try await controller.submitVoiceOver(
            elementID: elementID,
            authoredAction: action
        )

        XCTAssertEqual(
            rejected.preview?.action,
            .place(componentID: "roof", slotID: "cover")
        )
        XCTAssertEqual(rejected.preview?.feedback, .resistance)
        XCTAssertNil(rejected.durableCommit)
        XCTAssertNil(rejected.responsiveAudioCommit)
        XCTAssertEqual(rejected.presentation.journeyState, before)
        XCTAssertEqual(rejected.presentation.interactionFeedback, .resistance)
        XCTAssertEqual(
            rejected.presentation.ephemeralResponseCleanupToken?.kind,
            .reducerResistance
        )
        XCTAssertEqual(
            SceneResponsiveAudioPhaseResolver.phase(
                interactionPhase: rejected.presentation.journeyState
                    .activeChapter?.interaction?.phase,
                feedback: rejected.presentation.interactionFeedback,
                directManipulation: rejected.presentation.directManipulation
            ),
            .resistance
        )
        let rejectedEventCount = await journal.count()
        XCTAssertEqual(rejectedEventCount, 0)
        XCTAssertEqual(
            log.events,
            ["haptic-contact", "haptic-resistance"],
            "VoiceOver contact and reducer rejection remain immediate, non-durable responses"
        )

        let token = try XCTUnwrap(
            rejected.presentation.ephemeralResponseCleanupToken
        )
        let clearedCandidate = try await controller
            .clearEphemeralInteractionResponse(matching: token)
        let cleared = try XCTUnwrap(
            clearedCandidate
        )
        XCTAssertEqual(cleared.journeyState, before)
        XCTAssertNil(cleared.interactionFeedback)
        XCTAssertNil(cleared.directManipulation)
        XCTAssertNil(cleared.ephemeralResponseCleanupToken)
        XCTAssertEqual(
            SceneResponsiveAudioPhaseResolver.phase(
                interactionPhase: cleared.journeyState.activeChapter?
                    .interaction?.phase,
                feedback: cleared.interactionFeedback,
                directManipulation: cleared.directManipulation
            ),
            .waiting
        )
        let staleCleanup = try await controller
            .clearEphemeralInteractionResponse(matching: token)
        XCTAssertNil(
            staleCleanup,
            "A stale cleanup token must not clear a later presentation"
        )
        let finalRejectedEventCount = await journal.count()
        XCTAssertEqual(finalRejectedEventCount, 0)
    }

    func testVoiceOverAssemblyContactPrecedesAppendAndCompletionSealFollowsIt() async throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let log = EventLog()
        let journal = JournalSpy(log: log)
        let haptics = HapticSpy(log: log)
        let controller = try await makeController(
            fixture: fixture,
            journal: journal,
            hapticBridge: haptics
        )

        let foundationElementID = "runtime-foundation-target-accessibility"
        let foundationAction = try authoredAction(
            in: fixture,
            elementID: foundationElementID
        )
        let foundation = try await controller.submitVoiceOver(
            elementID: foundationElementID,
            authoredAction: foundationAction
        )
        XCTAssertNotNil(foundation.durableCommit)
        XCTAssertEqual(
            log.events,
            ["haptic-contact", "append-interaction"],
            "The durable progress effect must not replay VoiceOver's immediate contact"
        )

        let roofElementID = "runtime-roof-target-accessibility"
        let roofAction = try authoredAction(
            in: fixture,
            elementID: roofElementID
        )
        let completed = try await controller.submitVoiceOver(
            elementID: roofElementID,
            authoredAction: roofAction
        )
        XCTAssertEqual(
            completed.presentation.journeyState.activeChapter?.interaction?.phase,
            .complete
        )
        XCTAssertEqual(
            log.events,
            [
                "haptic-contact",
                "append-interaction",
                "haptic-contact",
                "append-interaction",
                "haptic-seal",
            ]
        )
    }

    func testAssemblyGestureHapticsAreEphemeralDeduplicatedAndCompletionSealsAfterAppend() async throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let log = EventLog()
        let journal = JournalSpy(log: log)
        let haptics = HapticSpy(log: log)
        let controller = try await makeController(
            fixture: fixture,
            journal: journal,
            hapticBridge: haptics
        )
        let foundation = try targetPoint(
            "runtime-foundation-target",
            in: controller
        )
        let foundationSlot = try targetPoint(
            "runtime-foundation-slot",
            in: controller
        )
        let roof = try targetPoint("runtime-roof-target", in: controller)
        let roofSlot = try targetPoint("runtime-roof-slot", in: controller)

        _ = try await controller.submitTouch(
            .assembleContact(viewportPoint: foundation, progress: 0)
        )
        _ = try await controller.submitTouch(
            .assembleContact(viewportPoint: foundation, progress: 0.02)
        )
        let rejected = try await controller.submitTouch(
            .assembleDrop(
                sourceViewportPoint: foundation,
                slotViewportPoint: roofSlot,
                progress: 1
            )
        )
        XCTAssertNil(rejected.durableCommit)
        XCTAssertEqual(log.events, ["haptic-contact", "haptic-resistance"])
        let rejectedEventCount = await journal.count()
        XCTAssertEqual(rejectedEventCount, 0)

        let rejectionToken = try XCTUnwrap(
            rejected.presentation.ephemeralResponseCleanupToken
        )
        _ = try await controller.clearEphemeralInteractionResponse(
            matching: rejectionToken
        )
        _ = try await controller.submitTouch(
            .assembleContact(viewportPoint: foundation, progress: 0)
        )
        let foundationAccepted = try await controller.submitTouch(
            .assembleDrop(
                sourceViewportPoint: foundation,
                slotViewportPoint: foundationSlot,
                progress: 1
            )
        )
        XCTAssertNotNil(foundationAccepted.durableCommit)
        XCTAssertEqual(
            log.events,
            [
                "haptic-contact",
                "haptic-resistance",
                "haptic-contact",
                "append-interaction",
            ],
            "The accepted drop must not replay the gesture's contact haptic"
        )

        let acceptanceToken = try XCTUnwrap(
            foundationAccepted.presentation.ephemeralResponseCleanupToken
        )
        _ = try await controller.clearEphemeralInteractionResponse(
            matching: acceptanceToken
        )
        _ = try await controller.submitTouch(
            .assembleContact(viewportPoint: roof, progress: 0)
        )
        let completed = try await controller.submitTouch(
            .assembleDrop(
                sourceViewportPoint: roof,
                slotViewportPoint: roofSlot,
                progress: 1
            )
        )
        XCTAssertEqual(
            completed.presentation.journeyState.activeChapter?.interaction?
                .phase,
            .complete
        )
        XCTAssertEqual(
            Array(log.events.suffix(3)),
            ["haptic-contact", "append-interaction", "haptic-seal"]
        )
        let completedEventCount = await journal.count()
        XCTAssertEqual(completedEventCount, 2)
    }

    func testAssembleSourceTapCannotCommitOrAppend() async throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let controller = try await makeController(fixture: fixture, journal: journal)
        let before = controller.presentation.journeyState
        let source = try targetPoint("runtime-foundation-target", in: controller)

        do {
            _ = try await controller.submitTouch(
                .assembleDrop(
                    sourceViewportPoint: source,
                    slotViewportPoint: source,
                    progress: 1
                )
            )
            XCTFail("A source target cannot also act as its placement slot")
        } catch {
            XCTAssertEqual(
                error as? SceneTouchActionResolverError,
                .wrongTarget("runtime-foundation-target")
            )
        }

        XCTAssertEqual(controller.presentation.journeyState, before)
        let eventCount = await journal.count()
        XCTAssertEqual(eventCount, 0)
    }

    func testAssemblePhysicalActivateTargetCannotBypassDirectPlacement() async throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let controller = try await makeController(fixture: fixture, journal: journal)
        let source = try targetPoint("runtime-foundation-target", in: controller)

        do {
            _ = try await controller.submitTouch(
                .activateTarget(viewportPoint: source)
            )
            XCTFail("Physical Assemble activation must require a source-to-slot gesture")
        } catch {
            XCTAssertEqual(
                error as? SceneTouchActionResolverError,
                .assemblyDirectPlacementUnavailable
            )
        }

        let eventCount = await journal.count()
        XCTAssertEqual(eventCount, 0)
    }

    func testAssembleCancellationSnapsBackWithoutPreviewOrJournalMutation() async throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let controller = try await makeController(fixture: fixture, journal: journal)
        let before = controller.presentation.journeyState
        let foundation = try targetPoint("runtime-foundation-target", in: controller)
        let outside = SceneFramePoint(x: 0.5, y: 0.22)

        let contact = try await controller.submitTouch(
            .assembleContact(viewportPoint: foundation, progress: 0)
        )
        XCTAssertEqual(contact.presentation.directManipulation?.phase, .contact)
        let lift = try await controller.submitTouch(
            .assembleLift(
                sourceViewportPoint: foundation,
                currentViewportPoint: SceneFramePoint(x: foundation.x, y: foundation.y - 0.03),
                progress: 0.12
            )
        )
        XCTAssertEqual(lift.presentation.directManipulation?.phase, .lift)
        let carry = try await controller.submitTouch(
            .assembleCarry(
                sourceViewportPoint: foundation,
                currentViewportPoint: outside,
                progress: 0.72
            )
        )
        XCTAssertEqual(carry.presentation.directManipulation?.phase, .carrying)
        let carriedLayer = try XCTUnwrap(
            carry.presentation.metalPreparationPlan.drawCommands.first { command in
                if case let .layer(layerID, _) = command.source {
                    return layerID == "runtime-foundation"
                }
                return false
            }
        )
        XCTAssertNotEqual(carriedLayer.interactionOffset, .zero)

        let cancelled = try await controller.submitTouch(
            .assembleCancel(
                sourceViewportPoint: foundation,
                currentViewportPoint: outside,
                progress: 0.72
            )
        )
        XCTAssertNil(cancelled.preview)
        XCTAssertNil(cancelled.durableCommit)
        XCTAssertEqual(cancelled.presentation.journeyState, before)
        XCTAssertEqual(cancelled.presentation.directManipulation?.phase, .snapBack)
        XCTAssertEqual(cancelled.presentation.directManipulation?.outcome, .cancelled)
        XCTAssertNil(cancelled.presentation.interactionFeedback)
        XCTAssertEqual(
            cancelled.presentation.ephemeralResponseCleanupToken?.kind,
            .cancelledSnapBack
        )
        XCTAssertEqual(
            SceneResponsiveAudioPhaseResolver.phase(
                interactionPhase: cancelled.presentation.journeyState
                    .activeChapter?.interaction?.phase,
                feedback: cancelled.presentation.interactionFeedback,
                directManipulation: cancelled.presentation.directManipulation
            ),
            .waiting
        )
        XCTAssertEqual(
            cancelled.presentation.framePlan.interactionResponse?.viewportTransferPath.count,
            2
        )
        let snappedLayer = try XCTUnwrap(
            cancelled.presentation.metalPreparationPlan.drawCommands.first { command in
                if case let .layer(layerID, _) = command.source {
                    return layerID == "runtime-foundation"
                }
                return false
            }
        )
        XCTAssertEqual(snappedLayer.interactionOffset, .zero)
        let eventCount = await journal.count()
        XCTAssertEqual(eventCount, 0)

        let cold = try await ChapterSceneRuntimeController(
            restoration: JourneyRestoration(
                state: cancelled.presentation.journeyState,
                replayedEventCount: 0,
                lastSequence: 0
            ),
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false,
            append: { request in try await journal.append(request.event) }
        )
        XCTAssertNil(cold.presentation.interactionFeedback)
        XCTAssertNil(cold.presentation.directManipulation)
        XCTAssertNil(cold.presentation.ephemeralResponseCleanupToken)
        XCTAssertEqual(
            SceneResponsiveAudioPhaseResolver.phase(
                interactionPhase: cold.presentation.journeyState.activeChapter?
                    .interaction?.phase,
                feedback: cold.presentation.interactionFeedback,
                directManipulation: cold.presentation.directManipulation
            ),
            .waiting
        )
        let coldEventCount = await journal.count()
        XCTAssertEqual(coldEventCount, 0)
    }

    func testAssembleAcceptedDropCommitsOnePlaceThenRestoresWithoutEphemera() async throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let controller = try await makeController(fixture: fixture, journal: journal)
        let foundation = try targetPoint("runtime-foundation-target", in: controller)
        let foundationSlot = try targetPoint("runtime-foundation-slot", in: controller)

        let approach = try await controller.submitTouch(
            .assembleSlotApproach(
                sourceViewportPoint: foundation,
                slotViewportPoint: foundationSlot,
                progress: 0.9
            )
        )
        XCTAssertNil(approach.preview)
        XCTAssertNil(approach.durableCommit)
        XCTAssertEqual(approach.presentation.directManipulation?.phase, .slotApproach)

        let accepted = try await controller.submitTouch(
            .assembleDrop(
                sourceViewportPoint: foundation,
                slotViewportPoint: foundationSlot,
                progress: 1
            )
        )
        XCTAssertEqual(
            accepted.preview?.action,
            .place(componentID: "foundation", slotID: "ground")
        )
        XCTAssertEqual(accepted.preview?.feedback, .progress)
        XCTAssertNotNil(accepted.durableCommit)
        XCTAssertEqual(accepted.presentation.directManipulation?.phase, .accepted)
        let acceptedLayer = try XCTUnwrap(
            accepted.presentation.metalPreparationPlan.drawCommands.first { command in
                if case let .layer(layerID, _) = command.source {
                    return layerID == "runtime-foundation"
                }
                return false
            }
        )
        XCTAssertEqual(acceptedLayer.interactionOffset, .zero)
        guard case let .assemble(progress)? = accepted.presentation.journeyState
            .activeChapter?.interaction?.progress else {
            return XCTFail("Accepted Assemble drop must publish durable placement")
        }
        XCTAssertEqual(
            progress.placements,
            [AssemblyPlacement(componentID: "foundation", slotID: "ground")]
        )
        let eventCount = await journal.count()
        XCTAssertEqual(eventCount, 1)

        let restoredJournal = JournalSpy(startingSequence: 1)
        let restored = try await ChapterSceneRuntimeController(
            restoration: JourneyRestoration(
                state: accepted.presentation.journeyState,
                replayedEventCount: 1,
                lastSequence: 1
            ),
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false,
            append: { request in try await restoredJournal.append(request.event) }
        )
        XCTAssertEqual(
            restored.presentation.journeyState,
            accepted.presentation.journeyState
        )
        XCTAssertNil(restored.presentation.directManipulation)
        XCTAssertNil(restored.presentation.interactionFeedback)
        XCTAssertNil(restored.presentation.framePlan.interactionResponse)
        let restoredEventCount = await restoredJournal.count()
        XCTAssertEqual(restoredEventCount, 0)
    }

    func testAssembleTouchAndVoiceOverDispatchSamePlaceActionsAndConverge() async throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let touchJournal = JournalSpy()
        let semanticJournal = JournalSpy()
        let touch = try await makeController(fixture: fixture, journal: touchJournal)
        let semantic = try await makeController(fixture: fixture, journal: semanticJournal)

        for step in [
            (
                component: "foundation",
                slot: "ground",
                sourceTarget: "runtime-foundation-target",
                slotTarget: "runtime-foundation-slot"
            ),
            (
                component: "roof",
                slot: "cover",
                sourceTarget: "runtime-roof-target",
                slotTarget: "runtime-roof-slot"
            ),
        ] {
            let sourcePoint = try targetPoint(step.sourceTarget, in: touch)
            let slotPoint = try targetPoint(step.slotTarget, in: touch)
            let touched = try await touch.submitTouch(
                .assembleDrop(
                    sourceViewportPoint: sourcePoint,
                    slotViewportPoint: slotPoint,
                    progress: 1
                )
            )
            let elementID = "\(step.sourceTarget)-accessibility"
            let voiced = try await semantic.submitVoiceOver(
                elementID: elementID,
                authoredAction: try authoredAction(
                    in: fixture,
                    elementID: elementID
                )
            )
            let expected = InteractionAction.place(
                componentID: step.component,
                slotID: step.slot
            )
            XCTAssertEqual(touched.preview?.action, expected)
            XCTAssertEqual(voiced.preview?.action, expected)
            guard case let .interact(_, touchAction)? = touched.durableCommit?.event.action,
                  case let .interact(_, semanticAction)? = voiced.durableCommit?.event.action else {
                return XCTFail("Both modalities must append one domain interaction")
            }
            XCTAssertEqual(touchAction, expected)
            XCTAssertEqual(semanticAction, expected)
            _ = try await touch.restorePresentation()
        }

        assertConverged(touch, semantic)
        let touchCount = await touchJournal.count()
        let semanticCount = await semanticJournal.count()
        XCTAssertEqual(touchCount, 2)
        XCTAssertEqual(semanticCount, 2)
    }

    func testAssembleDirectRuntimeHasNoThreeRecordsRepositoryDependency() async throws {
        let fixture = try RuntimeTestFixture.assembleDirectManipulation()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        XCTAssertNil(fixture.repository.beat("beat-first-farmers-three-records"))
        XCTAssertNil(
            fixture.repository.interaction("interaction-first-farmers-at-the-iron-gates")
        )
        let journal = JournalSpy()
        let controller = try await makeController(fixture: fixture, journal: journal)
        let foundation = try targetPoint("runtime-foundation-target", in: controller)
        let foundationSlot = try targetPoint("runtime-foundation-slot", in: controller)
        let transition = try await controller.submitTouch(
            .assembleDrop(
                sourceViewportPoint: foundation,
                slotViewportPoint: foundationSlot,
                progress: 1
            )
        )
        XCTAssertNotNil(transition.durableCommit)
    }

    func testCompletePressureTouchAndVoiceOverConverge() async throws {
        let fixture = try RuntimeTestFixture.pressure()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let touchJournal = JournalSpy()
        let semanticJournal = JournalSpy()
        let touch = try await makeController(fixture: fixture, journal: touchJournal)
        let semantic = try await makeController(
            fixture: fixture,
            journal: semanticJournal
        )
        let defenceElementID = "runtime-defence-target-accessibility"
        let target = try XCTUnwrap(
            touch.presentation.framePlan.interactionHitRegions.first {
                $0.interactionTargetID == "runtime-defence-target"
            }
        )

        _ = try await touch.submitTouch(
            .adjustTarget(
                viewportPoint: centroid(target.viewportPath),
                amount: 0.4
            )
        )
        _ = try await semantic.submitVoiceOver(
            elementID: defenceElementID,
            authoredAction: try authoredAction(
                in: fixture,
                elementID: defenceElementID
            )
        )
        _ = try await touch.submitTouch(.holdPressure(elapsedMillis: 1_000))
        _ = try await semantic.submitVoiceOver(
            elementID: "runtime-pressure-hold",
            authoredAction: try authoredAction(
                in: fixture,
                elementID: "runtime-pressure-hold"
            )
        )

        assertConverged(touch, semantic)
        let touchCount = await touchJournal.count()
        let semanticCount = await semanticJournal.count()
        XCTAssertEqual(touchCount, 2)
        XCTAssertEqual(semanticCount, 2)
    }

    func testTouchAndVoiceOverPublishTheSameResistanceAudioIntent() async throws {
        let fixture = try RuntimeTestFixture.pressure()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let touch = try await makeController(
            fixture: fixture,
            journal: JournalSpy()
        )
        let semantic = try await makeController(
            fixture: fixture,
            journal: JournalSpy()
        )

        let touchTransition = try await touch.submitTouch(
            .holdPressure(elapsedMillis: 1_000)
        )
        let semanticTransition = try await semantic.submitVoiceOver(
            elementID: "runtime-pressure-hold",
            authoredAction: try authoredAction(
                in: fixture,
                elementID: "runtime-pressure-hold"
            )
        )

        XCTAssertEqual(touchTransition.preview?.feedback, .resistance)
        XCTAssertEqual(
            touchTransition.presentation.interactionFeedback,
            semanticTransition.presentation.interactionFeedback
        )
        XCTAssertEqual(
            SceneResponsiveAudioPhaseResolver.phase(
                interactionPhase: touchTransition.presentation.journeyState
                    .activeChapter?.interaction?.phase,
                feedback: touchTransition.presentation.interactionFeedback,
                directManipulation: touchTransition.presentation.directManipulation
            ),
            .resistance
        )
        XCTAssertEqual(
            touchTransition.presentation.journeyState,
            semanticTransition.presentation.journeyState
        )
    }

    func testCompleteTransformTouchAndVoiceOverConverge() async throws {
        let fixture = try RuntimeTestFixture.transform()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let touchJournal = JournalSpy()
        let semanticJournal = JournalSpy()
        let touch = try await makeController(fixture: fixture, journal: touchJournal)
        let semantic = try await makeController(
            fixture: fixture,
            journal: semanticJournal
        )
        let elementID = "runtime-clear-target-accessibility"
        let target = try XCTUnwrap(
            touch.presentation.framePlan.interactionHitRegions.first {
                $0.interactionTargetID == "runtime-clear-target"
            }
        )

        _ = try await touch.submitTouch(
            .adjustTarget(
                viewportPoint: centroid(target.viewportPath),
                amount: 1
            )
        )
        _ = try await semantic.submitVoiceOver(
            elementID: elementID,
            authoredAction: try authoredAction(in: fixture, elementID: elementID)
        )

        assertConverged(touch, semantic)
        let touchCount = await touchJournal.count()
        let semanticCount = await semanticJournal.count()
        XCTAssertEqual(touchCount, 1)
        XCTAssertEqual(semanticCount, 1)
    }

    func testCompletedTouchIsRejectedBeforeResolutionForEveryGrammar() async throws {
        let cases = try RuntimeTestFixture.completedGrammarCases()
        defer {
            for testCase in cases {
                try? FileManager.default.removeItem(at: testCase.fixture.packageRoot)
            }
        }

        for testCase in cases {
            let journal = JournalSpy()
            let controller = try await makeController(
                fixture: testCase.fixture,
                journal: journal
            )
            XCTAssertEqual(
                controller.presentation.journeyState.activeChapter?.interaction?.phase,
                .complete,
                testCase.name
            )

            do {
                _ = try await controller.submitTouch(
                    testCase.touchIntent,
                    alphaSampler: OpaqueMaskSampler()
                )
                XCTFail("Completed \(testCase.name) touch must reject before resolution")
            } catch {
                XCTAssertEqual(
                    error as? ChapterSceneRuntimeControllerError,
                    .interactionAlreadyComplete,
                    testCase.name
                )
            }
            let appendCount = await journal.count()
            XCTAssertEqual(appendCount, 0, testCase.name)
        }
    }

    func testAllocateContactAndCarryAreEphemeralAndNeverJournaled() async throws {
        let fixture = try RuntimeTestFixture.harvestAllocate()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let controller = try await makeController(fixture: fixture, journal: journal)
        let source = try XCTUnwrap(
            controller.presentation.framePlan.interactionSourceHitRegion
        )
        let sourcePoint = centroid(source.viewportPath)
        let sampler = OpaqueMaskSampler()

        let contact = try await controller.submitTouch(
            .allocateContact(viewportPoint: sourcePoint, progress: 0.1),
            alphaSampler: sampler
        )
        XCTAssertNil(contact.durableCommit)
        XCTAssertNil(contact.preview)
        XCTAssertNil(contact.presentation.interactionFeedback)
        XCTAssertEqual(contact.presentation.directManipulation?.phase, .contact)
        XCTAssertEqual(
            SceneResponsiveAudioPhaseResolver.phase(
                interactionPhase: contact.presentation.journeyState.activeChapter?
                    .interaction?.phase,
                feedback: contact.presentation.interactionFeedback,
                directManipulation: contact.presentation.directManipulation
            ),
            .engaged
        )
        XCTAssertEqual(contact.presentation.journeyState, fixture.state)
        let contactJournalCount = await journal.count()
        XCTAssertEqual(contactJournalCount, 0)

        let carry = try await controller.submitTouch(
            .allocateCarry(
                sourceViewportPoint: sourcePoint,
                currentViewportPoint: SceneFramePoint(x: 0.5, y: 0.5),
                progress: 0.55
            ),
            alphaSampler: sampler
        )
        XCTAssertNil(carry.durableCommit)
        XCTAssertNil(carry.preview)
        XCTAssertNil(carry.presentation.interactionFeedback)
        XCTAssertEqual(carry.presentation.directManipulation?.phase, .carrying)
        XCTAssertEqual(carry.presentation.journeyState, fixture.state)
        let carryJournalCount = await journal.count()
        XCTAssertEqual(carryJournalCount, 0)
    }

    func testAcceptedAllocateDropPublishesResponseOnlyAfterDurableAppend() async throws {
        let fixture = try RuntimeTestFixture.harvestAllocate()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let controller = try await makeController(fixture: fixture, journal: journal)
        let source = try XCTUnwrap(
            controller.presentation.framePlan.interactionSourceHitRegion
        )
        let destination = try XCTUnwrap(
            controller.presentation.framePlan.interactionHitRegions.first {
                $0.interactionTargetID == "winter-food-target"
            }
        )

        let transition = try await controller.submitTouch(
            .allocateDrop(
                sourceViewportPoint: centroid(source.viewportPath),
                destinationViewportPoint: centroid(destination.viewportPath),
                destinationUnits: 2,
                progress: 0.9
            ),
            alphaSampler: OpaqueMaskSampler()
        )

        XCTAssertNotNil(transition.durableCommit)
        XCTAssertNil(transition.postCommitIssue)
        XCTAssertEqual(transition.preview?.feedback, .progress)
        XCTAssertEqual(transition.presentation.interactionFeedback, .progress)
        XCTAssertEqual(transition.presentation.directManipulation?.phase, .accepted)
        let reprojected = try await controller.restorePresentation(
            preserving: transition.presentation.interactionFeedback,
            directManipulation: transition.presentation.directManipulation
        )
        XCTAssertEqual(reprojected.interactionFeedback, .progress)
        XCTAssertEqual(reprojected.directManipulation?.phase, .accepted)
        guard case let .allocate(allocation)? = transition.presentation.journeyState
            .activeChapter?.interaction?.progress else {
            return XCTFail("The durable presentation must contain allocation progress")
        }
        XCTAssertEqual(
            allocation.allocations.first { $0.destinationID == "food" }?.units,
            2
        )
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 1)
    }

    func testAllocateDropAtTheCurrentAbsoluteValueNeverAppendsANoop() async throws {
        let fixture = try RuntimeTestFixture.harvestAllocate()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let controller = try await makeController(fixture: fixture, journal: journal)
        let source = try XCTUnwrap(
            controller.presentation.framePlan.interactionSourceHitRegion
        )
        let destination = try XCTUnwrap(
            controller.presentation.framePlan.interactionHitRegions.first {
                $0.interactionTargetID == "winter-food-target"
            }
        )
        let intent = SceneTouchIntent.allocateDrop(
            sourceViewportPoint: centroid(source.viewportPath),
            destinationViewportPoint: centroid(destination.viewportPath),
            destinationUnits: 4,
            progress: 0.9
        )

        _ = try await controller.submitTouch(
            intent,
            alphaSampler: OpaqueMaskSampler()
        )
        do {
            _ = try await controller.submitTouch(
                intent,
                alphaSampler: OpaqueMaskSampler()
            )
            XCTFail("The same absolute allocation must not reach the journal twice")
        } catch {
            XCTAssertEqual(error as? SceneTouchActionResolverError, .invalidAmount)
        }
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 1)
    }

    func testRejectedTouchFailsBeforeAppend() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let controller = try await makeController(fixture: fixture, journal: journal)

        do {
            _ = try await controller.submitTouch(
                .trace(viewportPoint: SceneFramePoint(x: 0.02, y: 0.02))
            )
            XCTFail("An unauthored touch region must fail")
        } catch {
            XCTAssertEqual(
                error as? SceneTouchActionResolverError,
                .targetNotHit
            )
        }
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 0)
        XCTAssertEqual(controller.presentation.journeyState, fixture.state)
        XCTAssertNil(controller.presentation.interactionFeedback)
    }

    func testKillRestoreRebuildsExactPresentationAtEveryQuarter() async throws {
        for completedAnchorCount in 0 ... 4 {
            let fixture = try RuntimeTestFixture.trace()
            defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
            let journal = JournalSpy()
            let controller = try await makeController(fixture: fixture, journal: journal)
            let voiceOverAction = try XCTUnwrap(
                fixture.accessibility.elements.first?.actions.first
            )
            for _ in 0 ..< completedAnchorCount {
                _ = try await controller.submitVoiceOver(
                    elementID: "route-control-accessibility",
                    authoredAction: voiceOverAction
                )
            }
            let beforeKill = controller.presentation
            let encoded = try JSONEncoder().encode(beforeKill.journeyState)
            let restoredState = try JSONDecoder().decode(
                JourneyState.self,
                from: encoded
            )
            let restoredJournal = JournalSpy(
                startingSequence: UInt64(completedAnchorCount)
            )
            let restoredCommitter = DurableJourneyCommitter(
                restoredState: restoredState,
                lastSequence: UInt64(completedAnchorCount),
                append: { request in try await restoredJournal.append(request.event) }
            )
            let restoredController = try await ChapterSceneRuntimeController(
                committer: restoredCommitter,
                coordinator: fixture.coordinator,
                assets: fixture.inventory,
                viewportCropID: "baseline-393x852",
                reduceMotion: false
            )

            XCTAssertEqual(
                restoredController.presentation.journeyState,
                beforeKill.journeyState
            )
            XCTAssertEqual(
                restoredController.presentation.cursor,
                beforeKill.cursor
            )
            XCTAssertEqual(
                restoredController.presentation.framePlan,
                beforeKill.framePlan
            )
            XCTAssertEqual(
                restoredController.presentation.metalPreparationPlan,
                beforeKill.metalPreparationPlan
            )
            XCTAssertEqual(
                restoredController.presentation.semanticInteractionModel,
                beforeKill.semanticInteractionModel
            )
            XCTAssertNil(
                restoredController.presentation.interactionFeedback,
                "Transient reducer feedback must not replay after restoration."
            )
            XCTAssertNil(restoredController.presentation.directManipulation)
            XCTAssertEqual(
                restoredController.presentation.journeyState.activeChapter?
                    .interaction?.progress.traceReachedAnchorCount,
                completedAnchorCount
            )
            let restoredJournalCount = await restoredJournal.count()
            XCTAssertEqual(restoredJournalCount, 0)
        }
    }

    func testKillRestoreRebuildsExactCompletedPresentationForEveryGrammar() async throws {
        let cases = try RuntimeTestFixture.completedGrammarCases()
        defer {
            for testCase in cases {
                try? FileManager.default.removeItem(at: testCase.fixture.packageRoot)
            }
        }

        for testCase in cases {
            let originalJournal = JournalSpy()
            let original = try await makeController(
                fixture: testCase.fixture,
                journal: originalJournal
            )
            let beforeKill = original.presentation
            let encoded = try JSONEncoder().encode(beforeKill.journeyState)
            let restoredState = try JSONDecoder().decode(
                JourneyState.self,
                from: encoded
            )
            let restoredJournal = JournalSpy()
            let restored = try await ChapterSceneRuntimeController(
                committer: DurableJourneyCommitter(
                    restoredState: restoredState,
                    lastSequence: 0,
                    append: { request in try await restoredJournal.append(request.event) }
                ),
                coordinator: testCase.fixture.coordinator,
                assets: testCase.fixture.inventory,
                viewportCropID: "baseline-393x852",
                reduceMotion: false
            )

            XCTAssertEqual(restored.presentation, beforeKill, testCase.name)
            let appendCount = await restoredJournal.count()
            XCTAssertEqual(appendCount, 0, testCase.name)
        }
    }

    func testCandidatePresentationFailurePreventsAppend() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let sequencedRepository = SequencedSceneRepository(
            base: fixture.repository,
            validScene: fixture.repository.sceneValue,
            invalidScene: sceneMissingTracingVariant(fixture.repository.sceneValue),
            firstInvalidCall: 3
        )
        let coordinator = ChapterCoordinator(repository: sequencedRepository)
        let journal = JournalSpy()
        let controller = try await ChapterSceneRuntimeController(
            restoration: JourneyRestoration(
                state: fixture.state,
                replayedEventCount: 0,
                lastSequence: 0
            ),
            coordinator: coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false,
            append: { request in try await journal.append(request.event) }
        )
        let action = try XCTUnwrap(fixture.accessibility.elements.first?.actions.first)

        do {
            _ = try await controller.submitVoiceOver(
                elementID: "route-control-accessibility",
                authoredAction: action
            )
            XCTFail("The invalid candidate frame must fail before append")
        } catch {
            XCTAssertNotNil(error as? ContentValidationError)
        }
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 0)
        XCTAssertEqual(controller.presentation.journeyState, fixture.state)
    }

    func testFIFOCoversAppendPublishHapticAndAudioFollowUp() async throws {
        let fixture = try RuntimeTestFixture.trace(seedReachedAnchors: 3)
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let log = EventLog()
        let journal = JournalSpy(log: log)
        let haptics = HapticSpy(log: log)
        let audio = BlockingAudioBridge(
            log: log,
            programID: fixture.repository.program.id,
            consequenceTimelineID: fixture.repository.program.consequenceTimelineID
        )
        let controller = try await makeController(
            fixture: fixture,
            journal: journal,
            hapticBridge: haptics,
            audioBridge: audio
        )
        let action = try XCTUnwrap(fixture.accessibility.elements.first?.actions.first)

        let first = Task {
            try await controller.submitVoiceOver(
                elementID: "route-control-accessibility",
                authoredAction: action
            )
        }
        await audio.waitUntilEntered()

        XCTAssertEqual(
            controller.presentation.journeyState.activeChapter?.interaction?.phase,
            .complete,
            "The durable completion must be published before audio is released"
        )
        let countAtAudioEntry = await journal.count()
        XCTAssertEqual(countAtAudioEntry, 1)

        let secondFinished = CompletionProbe()
        let second = Task {
            do {
                let transition = try await controller.submitVoiceOver(
                    elementID: "route-control-accessibility",
                    authoredAction: action
                )
                await secondFinished.markFinished()
                return transition
            } catch {
                await secondFinished.markFinished()
                throw error
            }
        }
        for _ in 0 ..< 20 { await Task.yield() }
        let finishedWhileAudioBlocked = await secondFinished.isFinished()
        XCTAssertFalse(finishedWhileAudioBlocked)
        let countWhileAudioBlocked = await journal.count()
        XCTAssertEqual(
            countWhileAudioBlocked,
            1,
            "The second input must not enter append while the first audio consequence is in flight"
        )

        await audio.release()
        let firstTransition = try await first.value
        XCTAssertNil(firstTransition.postCommitIssue)
        XCTAssertNotNil(firstTransition.responsiveAudioCommit)
        do {
            _ = try await second.value
            XCTFail("A completed interaction cannot accept the queued duplicate")
        } catch {
            XCTAssertEqual(
                error as? ChapterSceneRuntimeControllerError,
                .interactionAlreadyComplete
            )
        }
        for _ in 0 ..< 5 {
            if await secondFinished.isFinished() { break }
            await Task.yield()
        }
        let finishedAfterAudio = await secondFinished.isFinished()
        let finalJournalCount = await journal.count()
        XCTAssertTrue(finishedAfterAudio)
        XCTAssertEqual(finalJournalCount, 2)
        XCTAssertEqual(
            log.events,
            [
                "append-interaction",
                "haptic-seal",
                "audio-enter",
                "audio-return",
                "append-audio",
            ]
        )
    }

    func testAudioFailureAfterAppendReturnsAcceptedCommitAndCannotDuplicateAction() async throws {
        let fixture = try RuntimeTestFixture.trace(seedReachedAnchors: 3)
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let log = EventLog()
        let journal = JournalSpy(log: log)
        let haptics = HapticSpy(log: log)
        let audio = ThrowingAudioBridge(log: log)
        let controller = try await makeController(
            fixture: fixture,
            journal: journal,
            hapticBridge: haptics,
            audioBridge: audio
        )
        let action = try XCTUnwrap(fixture.accessibility.elements.first?.actions.first)

        let transition = try await controller.submitVoiceOver(
            elementID: "route-control-accessibility",
            authoredAction: action
        )
        XCTAssertNotNil(transition.durableCommit)
        XCTAssertEqual(transition.postCommitIssue, .audioBridgeFailed)
        XCTAssertEqual(
            transition.presentation.journeyState.activeChapter?.interaction?.phase,
            .complete
        )
        let journalCountAfterFailure = await journal.count()
        XCTAssertEqual(journalCountAfterFailure, 1)
        XCTAssertEqual(log.events, ["append-interaction", "haptic-seal", "audio-throw"])

        do {
            _ = try await controller.submitVoiceOver(
                elementID: "route-control-accessibility",
                authoredAction: action
            )
            XCTFail("A caller cannot retry the already durable action")
        } catch {
            XCTAssertEqual(
                error as? ChapterSceneRuntimeControllerError,
                .interactionAlreadyComplete
            )
        }
        let finalJournalCount = await journal.count()
        XCTAssertEqual(finalJournalCount, 1)
    }

    func testOlderPositiveAudioSequenceIsRejectedWithoutFollowUpAppend() async throws {
        let fixture = try RuntimeTestFixture.trace(seedReachedAnchors: 3)
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy(startingSequence: 41)
        let audio = OlderSequenceAudioBridge(
            programID: fixture.repository.program.id,
            consequenceTimelineID: fixture.repository.program.consequenceTimelineID
        )
        let controller = try await makeController(
            fixture: fixture,
            journal: journal,
            lastSequence: 41,
            audioBridge: audio
        )
        let action = try XCTUnwrap(fixture.accessibility.elements.first?.actions.first)

        let transition = try await controller.submitVoiceOver(
            elementID: "route-control-accessibility",
            authoredAction: action
        )

        XCTAssertEqual(transition.durableCommit?.sequence, 42)
        XCTAssertEqual(transition.postCommitIssue, .audioSnapshotAuthorityMismatch)
        XCTAssertNil(transition.responsiveAudioCommit)
        XCTAssertNil(
            transition.presentation.journeyState.activeChapter?.responsiveAudioSnapshot
        )
        let journalCount = await journal.count()
        XCTAssertEqual(journalCount, 1)
    }

    func testCancelledQueuedInputThrowsCancellationWithoutAppend() async throws {
        let fixture = try RuntimeTestFixture.trace(seedReachedAnchors: 3)
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let journal = JournalSpy()
        let audio = BlockingAudioBridge(
            log: EventLog(),
            programID: fixture.repository.program.id,
            consequenceTimelineID: fixture.repository.program.consequenceTimelineID
        )
        let controller = try await makeController(
            fixture: fixture,
            journal: journal,
            audioBridge: audio
        )
        let action = try XCTUnwrap(fixture.accessibility.elements.first?.actions.first)
        let admitted = Task {
            try await controller.submitVoiceOver(
                elementID: "route-control-accessibility",
                authoredAction: action
            )
        }
        await audio.waitUntilEntered()

        let queued = Task {
            try await controller.submitVoiceOver(
                elementID: "route-control-accessibility",
                authoredAction: action
            )
        }
        for _ in 0 ..< 20 { await Task.yield() }
        queued.cancel()
        do {
            _ = try await queued.value
            XCTFail("A cancelled waiter must never acquire the transition slot")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let countWhileFirstInputIsBlocked = await journal.count()
        XCTAssertEqual(countWhileFirstInputIsBlocked, 1)

        await audio.release()
        _ = try await admitted.value
        let finalCount = await journal.count()
        XCTAssertEqual(finalCount, 2)
    }

    func testCancellationAfterAdmissionStillReturnsTheDurableCommit() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let append = CancellationObservingAppend()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await append.call(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        let action = try XCTUnwrap(fixture.accessibility.elements.first?.actions.first)
        let admitted = Task {
            try await controller.submitVoiceOver(
                elementID: "route-control-accessibility",
                authoredAction: action
            )
        }
        await append.waitUntilEntered()

        admitted.cancel()
        await append.release()
        let transition = try await admitted.value

        XCTAssertNotNil(transition.durableCommit)
        XCTAssertNil(transition.postCommitIssue)
        let count = await append.count()
        XCTAssertEqual(count, 1)
    }

    func testSharedCommitterDriftRejectsSceneActionBeforeItsAppend() async throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let repository = BlockingCandidateSceneRepository(
            base: fixture.repository,
            blockAtSceneCall: 3
        )
        let coordinator = ChapterCoordinator(repository: repository)
        let journal = JournalSpy()
        let committer = DurableJourneyCommitter(
            restoredState: fixture.state,
            lastSequence: 0,
            append: { request in try await journal.append(request.event) }
        )
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false
        )
        let action = try XCTUnwrap(fixture.accessibility.elements.first?.actions.first)
        let drift = Task.detached {
            repository.waitUntilBlocked()
            defer { repository.release() }
            return try await committer.commit(.setCameraAnchor(0.75))
        }

        do {
            _ = try await controller.submitVoiceOver(
                elementID: "route-control-accessibility",
                authoredAction: action
            )
            XCTFail("A scene preflight cannot append after another owner changes revision")
        } catch {
            guard case .staleRevision = error as? DurableJourneyCommitterError else {
                return XCTFail("Expected stale revision, received \(error)")
            }
        }
        _ = try await drift.value
        let events = await journal.recordedEvents()
        XCTAssertEqual(events.count, 1)
        guard case .setCameraAnchor = events.first?.action else {
            return XCTFail("Only the independent owner's event may append")
        }
    }

    private func makeController(
        fixture: RuntimeTestFixture,
        journal: JournalSpy,
        lastSequence: UInt64 = 0,
        hapticBridge: (any ChapterRuntimeHapticBridging)? = nil,
        audioBridge: (any ChapterRuntimeAudioConsequenceBridging)? = nil
    ) async throws -> ChapterSceneRuntimeController {
        try await ChapterSceneRuntimeController(
            restoration: JourneyRestoration(
                state: fixture.state,
                replayedEventCount: 0,
                lastSequence: lastSequence
            ),
            coordinator: fixture.coordinator,
            assets: fixture.inventory,
            viewportCropID: "baseline-393x852",
            reduceMotion: false,
            append: { request in try await journal.append(request.event) },
            hapticBridge: hapticBridge,
            audioConsequenceBridge: audioBridge
        )
    }

    private func authoredAction(
        in fixture: RuntimeTestFixture,
        elementID: String,
        kind: ContentKit.AccessibilityActionKind? = nil
    ) throws -> AccessibilityActionSpec {
        try XCTUnwrap(
            fixture.accessibility.elements.first { $0.id == elementID }?.actions.first {
                kind == nil || $0.kind == kind
            }
        )
    }

    private func waitingResponsiveAudioSnapshot(
        in fixture: RuntimeTestFixture
    ) throws -> ResponsiveAudioProgramSnapshot {
        try responsiveAudioSnapshot(in: fixture, cursorSample: 0)
    }

    private func responsiveAudioSnapshot(
        in fixture: RuntimeTestFixture,
        cursorSample: Int64
    ) throws -> ResponsiveAudioProgramSnapshot {
        let program = fixture.repository.program
        let waiting = try XCTUnwrap(program.interactionBed(for: .waiting))
        return ResponsiveAudioProgramSnapshot(
            programID: program.id,
            stage: .interaction,
            interactionPhase: .waiting,
            timelineID: waiting.timelineID,
            cursorSample: cursorSample,
            loopIteration: 0,
            durableCompletionSequence: nil
        )
    }

    private func assertConverged(
        _ touch: ChapterSceneRuntimeController,
        _ semantic: ChapterSceneRuntimeController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            touch.presentation.journeyState,
            semantic.presentation.journeyState,
            file: file,
            line: line
        )
        XCTAssertEqual(
            touch.presentation.framePlan,
            semantic.presentation.framePlan,
            file: file,
            line: line
        )
        XCTAssertEqual(
            touch.presentation.semanticInteractionModel,
            semantic.presentation.semanticInteractionModel,
            file: file,
            line: line
        )
        XCTAssertEqual(
            touch.presentation.journeyState.activeChapter?.interaction?.phase,
            .complete,
            file: file,
            line: line
        )
    }

    private func centroid(_ points: [SceneFramePoint]) -> SceneFramePoint {
        SceneFramePoint(
            x: points.reduce(0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0) { $0 + $1.y } / Double(points.count)
        )
    }

    private func targetPoint(
        _ targetID: String,
        in controller: ChapterSceneRuntimeController
    ) throws -> SceneFramePoint {
        let region = try XCTUnwrap(
            controller.presentation.framePlan.interactionHitRegions.first {
                $0.interactionTargetID == targetID
            }
        )
        return centroid(region.viewportPath)
    }

    private func sceneMissingTracingVariant(_ scene: SceneSpec) -> SceneSpec {
        let layers = scene.layers.map { layer in
            SceneLayerSpec(
                id: layer.id,
                order: layer.order,
                assetPath: layer.assetPath,
                frame: layer.frame,
                depth: layer.depth,
                opacity: layer.opacity,
                blendMode: layer.blendMode,
                masks: layer.masks,
                motion: layer.motion,
                stateVariants: layer.stateVariants.filter { $0.id != "tracing" }
            )
        }
        return SceneSpec(
            id: scene.id,
            sceneCanvas: scene.sceneCanvas,
            layers: layers,
            cameraRail: scene.cameraRail,
            atmosphere: scene.atmosphere,
            interactionTargets: scene.interactionTargets,
            interactionVisualBinding: scene.interactionVisualBinding,
            reduceMotionComposition: scene.reduceMotionComposition,
            mechanismFocus: scene.mechanismFocus,
            accessibilityID: scene.accessibilityID
        )
    }
}

private struct OpaqueMaskSampler: SceneAlphaMaskSampling {
    func isOpaque(
        in alphaMask: SceneResolvedAsset,
        at unitPoint: NormalizedPoint
    ) throws -> Bool {
        _ = alphaMask
        return unitPoint.isUnitPoint
    }
}

private actor JournalSpy {
    private var sequence: UInt64
    private var events: [JourneyEvent] = []
    private let log: EventLog?

    init(startingSequence: UInt64 = 0, log: EventLog? = nil) {
        sequence = startingSequence
        self.log = log
    }

    func append(_ event: JourneyEvent) async throws -> UInt64 {
        sequence += 1
        events.append(event)
        if let log {
            let label = switch event.action {
            case .interact: "append-interaction"
            case .setResponsiveAudioSnapshot: "append-audio"
            default: "append-other"
            }
            await log.record(label)
        }
        return sequence
    }

    func count() -> Int { events.count }
    func recordedEvents() -> [JourneyEvent] { events }
}

@MainActor
private final class EventLog {
    private(set) var events: [String] = []

    func record(_ event: String) { events.append(event) }
}

@MainActor
private final class HapticSpy: ChapterRuntimeHapticBridging {
    private let log: EventLog

    init(log: EventLog) { self.log = log }

    func play(_ semantic: HapticSemantic) {
        log.record("haptic-\(semantic.rawValue)")
    }
}

private actor BlockingAudioBridge: ChapterRuntimeAudioConsequenceBridging {
    private let log: EventLog
    private let programID: ResponsiveAudioProgramID
    private let consequenceTimelineID: AudioTimelineID
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(
        log: EventLog,
        programID: ResponsiveAudioProgramID,
        consequenceTimelineID: AudioTimelineID
    ) {
        self.log = log
        self.programID = programID
        self.consequenceTimelineID = consequenceTimelineID
    }

    func responsiveAudioSnapshot(
        after commit: DurableJourneyCommit,
        authority: DurableInteractionAudioCompletionReceipt
    ) async throws -> ResponsiveAudioProgramSnapshot? {
        XCTAssertEqual(commit.sequence, authority.sequence)
        await log.record("audio-enter")
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if !released {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        await log.record("audio-return")
        return ResponsiveAudioProgramSnapshot(
            programID: programID,
            stage: .consequence,
            interactionPhase: nil,
            timelineID: consequenceTimelineID,
            cursorSample: 0,
            loopIteration: 0,
            durableCompletionSequence: authority.sequence
        )
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private enum AudioTestError: Error { case failed }

private actor ThrowingAudioBridge: ChapterRuntimeAudioConsequenceBridging {
    private let log: EventLog

    init(log: EventLog) { self.log = log }

    func responsiveAudioSnapshot(
        after commit: DurableJourneyCommit,
        authority: DurableInteractionAudioCompletionReceipt
    ) async throws -> ResponsiveAudioProgramSnapshot? {
        XCTAssertEqual(commit.sequence, authority.sequence)
        await log.record("audio-throw")
        throw AudioTestError.failed
    }
}

private actor OlderSequenceAudioBridge: ChapterRuntimeAudioConsequenceBridging {
    private let programID: ResponsiveAudioProgramID
    private let consequenceTimelineID: AudioTimelineID

    init(
        programID: ResponsiveAudioProgramID,
        consequenceTimelineID: AudioTimelineID
    ) {
        self.programID = programID
        self.consequenceTimelineID = consequenceTimelineID
    }

    func responsiveAudioSnapshot(
        after commit: DurableJourneyCommit,
        authority: DurableInteractionAudioCompletionReceipt
    ) async throws -> ResponsiveAudioProgramSnapshot? {
        XCTAssertEqual(commit.sequence, authority.sequence)
        XCTAssertGreaterThan(authority.sequence, 1)
        return ResponsiveAudioProgramSnapshot(
            programID: programID,
            stage: .consequence,
            interactionPhase: nil,
            timelineID: consequenceTimelineID,
            cursorSample: 0,
            loopIteration: 0,
            durableCompletionSequence: authority.sequence - 1
        )
    }
}

private actor CancellationObservingAppend {
    private var events: [JourneyEvent] = []
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func call(_ event: JourneyEvent) async throws -> UInt64 {
        events.append(event)
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if !released {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        try Task.checkCancellation()
        return UInt64(events.count)
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func count() -> Int { events.count }
}

private actor CompletionProbe {
    private var finished = false

    func markFinished() { finished = true }
    func isFinished() -> Bool { finished }
}

private final class SequencedSceneRepository: @unchecked Sendable, ChapterContentRepository {
    private let base: RuntimeTestRepository
    private let validScene: SceneSpec
    private let invalidScene: SceneSpec
    private let firstInvalidCall: Int
    private let lock = NSLock()
    private var sceneCalls = 0

    init(
        base: RuntimeTestRepository,
        validScene: SceneSpec,
        invalidScene: SceneSpec,
        firstInvalidCall: Int
    ) {
        self.base = base
        self.validScene = validScene
        self.invalidScene = invalidScene
        self.firstInvalidCall = firstInvalidCall
    }

    func chapter(_ id: ChapterID) -> ChapterSpec? { base.chapter(id) }
    func arc(_ id: ArcID) -> ArcSpec? { base.arc(id) }
    func beat(_ id: BeatID) -> BeatSpec? { base.beat(id) }

    func scene(_ id: SceneID) -> SceneSpec? {
        lock.lock()
        sceneCalls += 1
        let call = sceneCalls
        lock.unlock()
        guard id == validScene.id else { return nil }
        return call >= firstInvalidCall ? invalidScene : validScene
    }

    func interaction(_ id: InteractionID) -> InteractionSpec? { base.interaction(id) }
    func accessibility(_ id: AccessibilityID) -> AccessibilitySpec? { base.accessibility(id) }
    func packageID(for chapterID: ChapterID) -> PackageID? { base.packageID(for: chapterID) }
    func contentVersion(for chapterID: ChapterID) -> SchemaVersion? {
        base.contentVersion(for: chapterID)
    }
    func location(of arcID: ArcID) -> ArcContentLocation? { base.location(of: arcID) }
    func location(of beatID: BeatID) -> BeatContentLocation? { base.location(of: beatID) }
    func audioTimelineIDs(for beatID: BeatID) -> [AudioTimelineID]? {
        base.audioTimelineIDs(for: beatID)
    }
    func responsiveAudioProgram(
        for interactionID: InteractionID
    ) -> ResponsiveAudioProgramSpec? {
        base.responsiveAudioProgram(for: interactionID)
    }
    func responsiveAudioTimelines(
        for interactionID: InteractionID
    ) -> [AudioTimeline]? {
        base.responsiveAudioTimelines(for: interactionID)
    }
}

private final class BlockingCandidateSceneRepository: @unchecked Sendable,
    ChapterContentRepository {
    private let base: RuntimeTestRepository
    private let blockAtSceneCall: Int
    private let lock = NSLock()
    private let entered = DispatchSemaphore(value: 0)
    private let releaseGate = DispatchSemaphore(value: 0)
    private var sceneCalls = 0

    init(base: RuntimeTestRepository, blockAtSceneCall: Int) {
        self.base = base
        self.blockAtSceneCall = blockAtSceneCall
    }

    func waitUntilBlocked() { entered.wait() }
    func release() { releaseGate.signal() }

    func chapter(_ id: ChapterID) -> ChapterSpec? { base.chapter(id) }
    func arc(_ id: ArcID) -> ArcSpec? { base.arc(id) }
    func beat(_ id: BeatID) -> BeatSpec? { base.beat(id) }

    func scene(_ id: SceneID) -> SceneSpec? {
        lock.lock()
        sceneCalls += 1
        let shouldBlock = sceneCalls == blockAtSceneCall
        lock.unlock()
        if shouldBlock {
            entered.signal()
            releaseGate.wait()
        }
        return base.scene(id)
    }

    func interaction(_ id: InteractionID) -> InteractionSpec? { base.interaction(id) }
    func accessibility(_ id: AccessibilityID) -> AccessibilitySpec? {
        base.accessibility(id)
    }
    func packageID(for chapterID: ChapterID) -> PackageID? {
        base.packageID(for: chapterID)
    }
    func contentVersion(for chapterID: ChapterID) -> SchemaVersion? {
        base.contentVersion(for: chapterID)
    }
    func location(of arcID: ArcID) -> ArcContentLocation? { base.location(of: arcID) }
    func location(of beatID: BeatID) -> BeatContentLocation? { base.location(of: beatID) }
    func audioTimelineIDs(for beatID: BeatID) -> [AudioTimelineID]? {
        base.audioTimelineIDs(for: beatID)
    }
    func responsiveAudioProgram(
        for interactionID: InteractionID
    ) -> ResponsiveAudioProgramSpec? {
        base.responsiveAudioProgram(for: interactionID)
    }
    func responsiveAudioTimelines(
        for interactionID: InteractionID
    ) -> [AudioTimeline]? {
        base.responsiveAudioTimelines(for: interactionID)
    }
}

private extension InteractionProgress {
    var traceReachedAnchorCount: Int? {
        guard case let .trace(progress) = self else { return nil }
        return progress.reachedAnchorCount
    }
}
