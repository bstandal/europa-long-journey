#if os(iOS)
import ContentKit
import DramaticAudio
import ExperiencePreferences
import Foundation
import JourneyDomain
import ProgressStore
import XCTest

final class ResponsiveAudioCursorProjectionTests: XCTestCase {
    @MainActor
    func testOffMainCaptureTreatsUnknownGenerationAsAwaitingAndNeverRegresses()
        async throws {
        let (controller, transport) = try Self.makeController()
        try controller.play()
        let authority = controller.runtime.snapshot()
        let binding = try controller.makeActiveAudioCursorBinding(
            constrainedTo: authority
        )
        let generation = try transport.currentGeneration()

        transport.setCapture(
            generation: generation,
            timelineID: authority.timelineID,
            cursorSample: 1_200,
            loopIteration: 0,
            isPlaying: true
        )
        let first = try await Task.detached {
            try binding.feed.capture()
        }.value
        XCTAssertEqual(try Self.verifiedSnapshot(first), authority.replacing(
            cursorSample: 1_200,
            loopIteration: 0
        ))

        transport.setCapture(
            generation: generation,
            timelineID: authority.timelineID,
            cursorSample: 900,
            loopIteration: 0,
            isPlaying: true
        )
        let regressed = try await Task.detached {
            try binding.feed.capture()
        }.value
        XCTAssertEqual(
            try Self.awaitingSnapshot(regressed).cursorSample,
            1_200
        )

        transport.setCapture(
            generation: 9_999,
            timelineID: authority.timelineID,
            cursorSample: 2_400,
            loopIteration: 0,
            isPlaying: true
        )
        let unknown = try await Task.detached {
            try binding.feed.capture()
        }.value
        XCTAssertEqual(
            try Self.awaitingSnapshot(unknown).cursorSample,
            1_200
        )
    }

    @MainActor
    func testPhaseForwardAliasVerifiesNewAuthorityAndKeepsOldAwaitingRaw()
        async throws {
        let (controller, transport) = try Self.makeController()
        try controller.play()
        transport.triggerAutomaticSuccessor()
        XCTAssertEqual(controller.runtime.stage, .interaction)

        let waitingAuthority = controller.runtime.snapshot()
        let oldBinding = try controller.makeActiveAudioCursorBinding(
            constrainedTo: waitingAuthority
        )
        let waitingGeneration = try transport.currentGeneration()
        transport.setCapture(
            generation: waitingGeneration,
            timelineID: waitingAuthority.timelineID,
            cursorSample: 800,
            loopIteration: 2,
            isPlaying: true
        )
        _ = try await Task.detached {
            try oldBinding.feed.capture()
        }.value

        let action = try controller.selectInteractionPhase(.engaged)
        let engagedAuthority = try Self.snapshot(from: action)
        let newBinding = try controller.makeActiveAudioCursorBinding(
            constrainedTo: engagedAuthority
        )

        // The old physical bed is still rendering before the scheduled seam.
        transport.setCapture(
            generation: waitingGeneration,
            timelineID: waitingAuthority.timelineID,
            cursorSample: 1_600,
            loopIteration: 2,
            isPlaying: true
        )
        let newCapture = try await Task.detached {
            try newBinding.feed.capture()
        }.value
        let verified = try Self.verifiedSnapshot(newCapture)
        XCTAssertEqual(verified.interactionPhase, .engaged)
        XCTAssertEqual(verified.timelineID, engagedAuthority.timelineID)
        XCTAssertEqual(verified.cursorSample, 1_600)
        XCTAssertEqual(verified.loopIteration, 2)

        let oldCapture = try await Task.detached {
            try oldBinding.feed.capture()
        }.value
        let awaiting = try Self.awaitingSnapshot(oldCapture)
        XCTAssertEqual(awaiting.interactionPhase, .waiting)
        XCTAssertEqual(awaiting.timelineID, waitingAuthority.timelineID)
        XCTAssertEqual(awaiting.cursorSample, 1_600)
        XCTAssertEqual(awaiting.loopIteration, 2)
    }

    @MainActor
    func testApproachCausalForwardAliasVerifiesNewAndLeavesOldAwaiting()
        async throws {
        let (controller, transport) = try Self.makeController()
        try controller.play()
        let oldAuthority = controller.runtime.snapshot()
        let oldBinding = try controller.makeActiveAudioCursorBinding(
            constrainedTo: oldAuthority
        )
        let generation = try transport.currentGeneration()
        transport.setCapture(
            generation: generation,
            timelineID: oldAuthority.timelineID,
            cursorSample: 1_000,
            loopIteration: 0,
            isPlaying: true
        )
        _ = try await Task.detached {
            try oldBinding.feed.capture()
        }.value

        let commit = try await Self.makeCompletionCommit()
        let receipt = try XCTUnwrap(
            try DurableInteractionAudioCausalStageReceipt.make(from: commit)
        )
        let action = try XCTUnwrap(
            controller.selectCausalStage(receipt)
        )
        let newAuthority = try Self.snapshot(from: action)
        XCTAssertEqual(newAuthority.stage, .approach)
        XCTAssertEqual(newAuthority.causalStage?.completedStageCount, 1)
        let newBinding = try controller.makeActiveAudioCursorBinding(
            constrainedTo: newAuthority
        )

        transport.setCapture(
            generation: generation,
            timelineID: oldAuthority.timelineID,
            cursorSample: 2_000,
            loopIteration: 0,
            isPlaying: true
        )
        let newCapture = try await Task.detached {
            try newBinding.feed.capture()
        }.value
        let verified = try Self.verifiedSnapshot(newCapture)
        XCTAssertEqual(verified.causalStage?.completedStageCount, 1)
        XCTAssertEqual(verified.cursorSample, 2_000)

        let oldCapture = try await Task.detached {
            try oldBinding.feed.capture()
        }.value
        let awaiting = try Self.awaitingSnapshot(oldCapture)
        XCTAssertNil(awaiting.causalStage)
        XCTAssertEqual(awaiting.cursorSample, 1_000)
    }

    @MainActor
    func testConsequenceAliasFreezesZeroAndRegistersCompleteFutureChain()
        async throws {
        let (controller, transport) = try Self.makeController()
        try controller.play()
        transport.triggerAutomaticSuccessor()
        let interactionAuthority = controller.runtime.snapshot()
        let oldBinding = try controller.makeActiveAudioCursorBinding(
            constrainedTo: interactionAuthority
        )
        let interactionGeneration = try transport.currentGeneration()
        transport.setCapture(
            generation: interactionGeneration,
            timelineID: interactionAuthority.timelineID,
            cursorSample: 700,
            loopIteration: 1,
            isPlaying: true
        )
        _ = try await Task.detached {
            try oldBinding.feed.capture()
        }.value

        let commit = try await Self.makeCompletionCommit()
        let consequenceAction = try controller.accept(durableCommit: commit)
        let consequenceAuthority = try Self.snapshot(from: consequenceAction)
        let descriptors = transport.mappingDescriptors()
        XCTAssertEqual(descriptors.count, 3)
        XCTAssertEqual(
            descriptors.map(\.snapshotAtBoundary.timelineID),
            [
                interactionAuthority.timelineID,
                consequenceAuthority.timelineID,
                consequenceAuthority.timelineID,
            ]
        )
        XCTAssertEqual(
            descriptors.map(\.snapshotAtBoundary.isPlaying),
            [true, true, false]
        )

        let consequenceBinding = try controller.makeActiveAudioCursorBinding(
            constrainedTo: consequenceAuthority
        )
        transport.setCapture(
            generation: interactionGeneration,
            timelineID: interactionAuthority.timelineID,
            cursorSample: 1_900,
            loopIteration: 1,
            isPlaying: true
        )
        let beforeSeam = try await Task.detached {
            try consequenceBinding.feed.capture()
        }.value
        let frozen = try Self.verifiedSnapshot(beforeSeam)
        XCTAssertEqual(frozen.stage, .consequence)
        XCTAssertEqual(frozen.cursorSample, 0)
        XCTAssertEqual(frozen.loopIteration, 0)

        let oldAfterCommit = try await Task.detached {
            try oldBinding.feed.capture()
        }.value
        let oldAwaiting = try Self.awaitingSnapshot(oldAfterCommit)
        XCTAssertEqual(oldAwaiting.stage, .interaction)
        XCTAssertEqual(oldAwaiting.cursorSample, 700)
        XCTAssertEqual(oldAwaiting.loopIteration, 1)

        let consequenceDescriptor = descriptors[1]
        transport.setCapture(
            generation: consequenceDescriptor.generation,
            timelineID: consequenceAuthority.timelineID,
            cursorSample: 2_400,
            loopIteration: 0,
            isPlaying: true
        )
        let consequenceProgress = try await Task.detached {
            try consequenceBinding.feed.capture()
        }.value
        XCTAssertEqual(
            try Self.verifiedSnapshot(consequenceProgress).cursorSample,
            2_400
        )

        let completedDescriptor = descriptors[2]
        transport.setCapture(
            generation: completedDescriptor.generation,
            timelineID: consequenceAuthority.timelineID,
            cursorSample: Self.consequenceDuration,
            loopIteration: 0,
            isPlaying: false
        )
        let completedBeforeJournal = try await Task.detached {
            try consequenceBinding.feed.capture()
        }.value
        XCTAssertEqual(
            try Self.awaitingSnapshot(completedBeforeJournal).cursorSample,
            Self.consequenceDuration - 1
        )
    }

    @MainActor
    func testPublicationRaceAwaitsUntilSameBindingSeesRegisteredGeneration()
        async throws {
        let (controller, transport) = try Self.makeController()
        try controller.play()
        let authority = controller.runtime.snapshot()
        let binding = try controller.makeActiveAudioCursorBinding(
            constrainedTo: authority
        )

        let generation = transport.publishUnregisteredCurrentMapping(
            timelineID: authority.timelineID,
            cursorSample: 3_000
        )
        let duringWindow = try await Task.detached {
            try binding.feed.capture()
        }.value
        XCTAssertEqual(
            try Self.awaitingSnapshot(duringWindow),
            authority
        )

        // Creating another binding performs the MainActor registration. The
        // first binding shares the registry and becomes usable immediately.
        _ = try controller.makeActiveAudioCursorBinding(
            constrainedTo: authority
        )
        transport.setCapture(
            generation: generation,
            timelineID: authority.timelineID,
            cursorSample: 3_200,
            loopIteration: 0,
            isPlaying: true
        )
        let afterRegistration = try await Task.detached {
            try binding.feed.capture()
        }.value
        XCTAssertEqual(
            try Self.verifiedSnapshot(afterRegistration).cursorSample,
            3_200
        )
    }

    private static let approachDuration: Int64 = 48_000
    private static let interactionDuration: Int64 = 96_000
    private static let consequenceDuration: Int64 = 48_000
    private static let scope = ResponsiveAudioProgramScope(
        chapterID: "cursor-projection-chapter",
        arcID: "cursor-projection-arc",
        beatID: "cursor-projection-beat",
        interactionID: "cursor-projection-interaction"
    )
    private static let program = ResponsiveAudioProgramSpec(
        id: "cursor-projection-program",
        scope: scope,
        approachTimelineID: "cursor-approach",
        interactionBeds: ResponsiveInteractionAudioPhase.allCases.map { phase in
            ResponsiveInteractionAudioBedSpec(
                phase: phase,
                timelineID: AudioTimelineID("cursor-\(phase.rawValue)"),
                layerStates: ResponsiveAudioLayerStateSelection(
                    scoreStateID: "cursor-\(phase.rawValue)-score",
                    soundscapeStateID: nil
                )
            )
        },
        consequenceTimelineID: "cursor-consequence",
        exitPolicy: .boundedFade(durationSamples: 480)
    )

    @MainActor
    private static func makeController() throws -> (
        ResponsiveAudioProgramController,
        CursorProjectionTimelineTransport
    ) {
        let transport = try CursorProjectionTimelineTransport()
        return (
            try ResponsiveAudioProgramController(
                program: program,
                timelines: timelines,
                transport: transport,
                resolver: CursorProjectionResolver()
            ),
            transport
        )
    }

    private static var timelines: [AudioTimeline] {
        [
            timeline(id: "cursor-approach", duration: approachDuration),
            timeline(id: "cursor-waiting", duration: interactionDuration),
            timeline(id: "cursor-engaged", duration: interactionDuration),
            timeline(id: "cursor-resistance", duration: interactionDuration),
            timeline(id: "cursor-consequence", duration: consequenceDuration),
        ]
    }

    private static func timeline(
        id: AudioTimelineID,
        duration: Int64
    ) -> AudioTimeline {
        AudioTimeline(
            id: id,
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: AudioCueID("\(id.rawValue)-score"),
                    role: .score,
                    startSample: 0,
                    durationSamples: duration,
                    assetPath: "audio/\(id.rawValue).caf",
                    gain: 1
                ),
            ],
            haptics: []
        )
    }

    private static var interactionSpec: InteractionSpec {
        InteractionSpec(
            id: scope.interactionID,
            prompt: LocalizedStringSpec(
                id: "cursor-projection-prompt",
                launchEnglish: "Complete the transfer."
            ),
            grammar: .transform(TransformInteractionSpec(stages: [
                TransformationStage(
                    id: "cursor-projection-stage",
                    controlID: "transfer",
                    requiredAmount: 1
                ),
            ])),
            completionEffects: [
                WorldEffect(
                    id: "cursor-projection-effect",
                    mutation: .revealNode(WorldNodeBlueprint(
                        id: "cursor-projection-node",
                        kind: .object,
                        form: "sealed-store",
                        position: NormalizedPoint(x: 0.5, y: 0.5)
                    ))
                ),
            ],
            accessibilityID: "cursor-projection-accessibility"
        )
    }

    private static func makeCompletionCommit() async throws
        -> DurableJourneyCommit {
        let session = ChapterSession(
            chapterID: scope.chapterID,
            packageID: "cursor-projection-package",
            contentVersion: SchemaVersion(major: 1),
            arcID: scope.arcID,
            beatID: scope.beatID,
            interaction: InteractionRuntimeState(spec: interactionSpec)
        )
        let committer = DurableJourneyCommitter(
            restoredState: JourneyState(
                route: .chapter(scope.chapterID),
                world: WorldGraph(),
                activeChapter: session
            ),
            lastSequence: 0,
            append: { request in UInt64(request.event.logicalTimeMillis) }
        )
        return try await committer.commit(.interact(
            spec: interactionSpec,
            action: .transform(controlID: "transfer", amount: 1)
        ))
    }

    private static func snapshot(
        from action: JourneyAction
    ) throws -> ResponsiveAudioProgramSnapshot {
        guard case let .setResponsiveAudioSnapshot(snapshot) = action else {
            throw CursorProjectionTestError.unexpectedAction
        }
        return snapshot
    }

    private static func verifiedSnapshot(
        _ capture: ActiveAudioCursorFeedCapture
    ) throws -> ResponsiveAudioProgramSnapshot {
        guard case let .verified(snapshot) = capture.result else {
            throw CursorProjectionTestError.expectedVerified
        }
        return snapshot
    }

    private static func awaitingSnapshot(
        _ capture: ActiveAudioCursorFeedCapture
    ) throws -> ResponsiveAudioProgramSnapshot {
        guard case let .awaitingDurableAuthority(snapshot) = capture.result else {
            throw CursorProjectionTestError.expectedAwaiting
        }
        return snapshot
    }
}

private enum CursorProjectionTestError: Error {
    case unexpectedAction
    case expectedVerified
    case expectedAwaiting
    case transportUnavailable
}

private extension ResponsiveAudioProgramSnapshot {
    func replacing(
        cursorSample: Int64,
        loopIteration: UInt64
    ) -> ResponsiveAudioProgramSnapshot {
        ResponsiveAudioProgramSnapshot(
            formatVersion: formatVersion,
            programID: programID,
            stage: stage,
            interactionPhase: interactionPhase,
            timelineID: timelineID,
            cursorSample: cursorSample,
            loopIteration: loopIteration,
            causalStage: causalStage,
            durableCompletionSequence: durableCompletionSequence
        )
    }
}

private struct CursorProjectionResolver: OfflineAudioAssetResolving {
    func url(for packageRelativePath: String) throws -> URL {
        URL(fileURLWithPath: "/nonshipping/\(packageRelativePath)")
    }
}

private final class CursorProjectionFeedState: @unchecked Sendable {
    private let lock = NSLock()
    private var captureValue = NativeAudioCursorFeedCapture(
        snapshot: NativeTimelineTransportSnapshot(
            timelineID: nil,
            cursorSample: 0,
            loopIteration: 0,
            isPlaying: false
        ),
        renderedGraphSample: 0,
        mappingGeneration: 0
    )
    private var descriptorValues: [NativeAudioCursorMappingDescriptor] = []

    func capture() -> NativeAudioCursorFeedCapture {
        lock.lock()
        defer { lock.unlock() }
        return captureValue
    }

    func descriptors() -> [NativeAudioCursorMappingDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        return descriptorValues
    }

    func publish(
        capture: NativeAudioCursorFeedCapture,
        descriptors: [NativeAudioCursorMappingDescriptor]
    ) {
        lock.lock()
        captureValue = capture
        descriptorValues = descriptors
        lock.unlock()
    }

    func setCapture(_ capture: NativeAudioCursorFeedCapture) {
        lock.lock()
        captureValue = capture
        lock.unlock()
    }

    func appendDescriptor(_ descriptor: NativeAudioCursorMappingDescriptor) {
        lock.lock()
        descriptorValues.append(descriptor)
        descriptorValues.sort {
            $0.graphBoundarySample < $1.graphBoundarySample
        }
        lock.unlock()
    }
}

@MainActor
private final class CursorProjectionTimelineTransport:
    ResponsiveAudioTimelineTransport {
    private enum AutomaticTarget {
        case successor(ResponsiveAudioTimelineTransportPlan)
        case completed
    }

    private let feedState = CursorProjectionFeedState()
    private let gate = NativeAudioDurabilityGate()
    private let gateToken: NativeAudioDurabilityGate.EpochToken
    private var nextGeneration: UInt64 = 0
    private var plan: ResponsiveAudioTimelineTransportPlan?
    private var isPlaying = false
    private var automaticTarget: AutomaticTarget?
    private var automaticHandler:
        ((ResponsiveAudioAutomaticBoundaryEvent) -> Void)?

    init() throws {
        gateToken = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 12_000
        )
    }

    func prepare(
        timeline: AudioTimeline,
        cursorSample: Int64,
        resolver _: any OfflineAudioAssetResolving
    ) throws {
        plan = ResponsiveAudioTimelineTransportPlan(
            timeline: timeline,
            cursorSample: cursorSample,
            loopIteration: 0,
            repetition: .once,
            causalMix: nil
        )
        isPlaying = false
    }

    func prepareResponsiveAudio(
        plan: ResponsiveAudioTimelineTransportPlan,
        resolver _: any OfflineAudioAssetResolving
    ) throws {
        self.plan = plan
        isPlaying = false
    }

    func play() throws {
        guard let plan else { throw CursorProjectionTestError.transportUnavailable }
        isPlaying = true
        let current = descriptor(
            timelineID: plan.timeline.id,
            cursorSample: plan.cursorSample,
            loopIteration: plan.loopIteration,
            isPlaying: true,
            graphBoundarySample: 0
        )
        let capture = NativeAudioCursorFeedCapture(
            snapshot: current.snapshotAtBoundary,
            renderedGraphSample: 0,
            mappingGeneration: current.generation
        )
        feedState.publish(capture: capture, descriptors: [current])
        publishAutomaticFutureIfNeeded()
    }

    func pause() throws -> NativeTimelineTransportSnapshot {
        isPlaying = false
        let current = feedState.capture().snapshot
        return NativeTimelineTransportSnapshot(
            timelineID: current.timelineID,
            cursorSample: current.cursorSample,
            loopIteration: current.loopIteration,
            isPlaying: false
        )
    }

    func snapshot() -> NativeTimelineTransportSnapshot {
        feedState.capture().snapshot
    }

    func applyPreferences(_: ExperiencePreferences) {}

    func configureAutomaticBoundary(
        successorPlan: ResponsiveAudioTimelineTransportPlan?,
        resolver _: any OfflineAudioAssetResolving,
        handler: @escaping (ResponsiveAudioAutomaticBoundaryEvent) -> Void
    ) throws {
        automaticTarget = successorPlan.map(AutomaticTarget.successor)
            ?? .completed
        automaticHandler = handler
        if isPlaying {
            publishAutomaticFutureIfNeeded()
        }
    }

    func transitionResponsiveAudio(
        to requestedPlan: ResponsiveAudioTimelineTransportPlan,
        resolver _: any OfflineAudioAssetResolving,
        validateBeforeCommit: (
            NativeTimelineTransportSnapshot
        ) throws -> Void
    ) throws -> NativeTimelineTransportSnapshot {
        let authoritative = NativeTimelineTransportSnapshot(
            timelineID: requestedPlan.timeline.id,
            cursorSample: requestedPlan.cursorSample,
            loopIteration: requestedPlan.loopIteration,
            isPlaying: isPlaying
        )
        try validateBeforeCommit(authoritative)
        let currentCapture = feedState.capture()
        guard let current = feedState.descriptors().first(where: {
            $0.generation == currentCapture.mappingGeneration
        }) else {
            throw CursorProjectionTestError.transportUnavailable
        }
        let scheduled = descriptor(
            timelineID: requestedPlan.timeline.id,
            cursorSample: requestedPlan.cursorSample,
            loopIteration: requestedPlan.loopIteration,
            isPlaying: isPlaying,
            graphBoundarySample: currentCapture.renderedGraphSample + 4_800
        )
        feedState.publish(
            capture: currentCapture,
            descriptors: [current, scheduled]
        )
        plan = requestedPlan
        automaticTarget = nil
        automaticHandler = nil
        return authoritative
    }

    func activeAudioCursorBinding() throws -> NativeAudioCursorBinding {
        guard isPlaying, !feedState.descriptors().isEmpty else {
            throw CursorProjectionTestError.transportUnavailable
        }
        let feedState = feedState
        return NativeAudioCursorBinding(
            feed: NativeAudioCursorFeed {
                feedState.capture()
            },
            gateToken: gateToken,
            renderedGraphSampleRate: 48_000,
            mappingDescriptors: feedState.descriptors()
        )
    }

    func stop() {
        isPlaying = false
    }

    func triggerAutomaticSuccessor() {
        guard case let .successor(successor) = automaticTarget,
              let handler = automaticHandler,
              let scheduled = feedState.descriptors().dropFirst().first
        else { return }
        automaticTarget = nil
        automaticHandler = nil
        plan = successor
        let promoted = NativeAudioCursorFeedCapture(
            snapshot: scheduled.snapshotAtBoundary,
            renderedGraphSample: scheduled.graphBoundarySample,
            mappingGeneration: scheduled.generation
        )
        feedState.publish(capture: promoted, descriptors: [scheduled])
        handler(.successorStarted(scheduled.snapshotAtBoundary))
    }

    func currentGeneration() throws -> UInt64 {
        let generation = feedState.capture().mappingGeneration
        guard generation > 0 else {
            throw CursorProjectionTestError.transportUnavailable
        }
        return generation
    }

    func mappingDescriptors() -> [NativeAudioCursorMappingDescriptor] {
        feedState.descriptors()
    }

    func setCapture(
        generation: UInt64,
        timelineID: AudioTimelineID,
        cursorSample: Int64,
        loopIteration: UInt64,
        isPlaying: Bool
    ) {
        feedState.setCapture(NativeAudioCursorFeedCapture(
            snapshot: NativeTimelineTransportSnapshot(
                timelineID: timelineID,
                cursorSample: cursorSample,
                loopIteration: loopIteration,
                isPlaying: isPlaying
            ),
            renderedGraphSample: max(0, cursorSample),
            mappingGeneration: generation
        ))
    }

    func publishUnregisteredCurrentMapping(
        timelineID: AudioTimelineID,
        cursorSample: Int64
    ) -> UInt64 {
        let mapping = descriptor(
            timelineID: timelineID,
            cursorSample: cursorSample,
            loopIteration: 0,
            isPlaying: true,
            graphBoundarySample: cursorSample
        )
        feedState.appendDescriptor(mapping)
        setCapture(
            generation: mapping.generation,
            timelineID: timelineID,
            cursorSample: cursorSample,
            loopIteration: 0,
            isPlaying: true
        )
        return mapping.generation
    }

    private func publishAutomaticFutureIfNeeded() {
        guard let target = automaticTarget,
              let plan else { return }
        let current = feedState.capture()
        let retained: [NativeAudioCursorMappingDescriptor]
        switch target {
        case .successor:
            retained = feedState.descriptors().filter {
                $0.generation == current.mappingGeneration
            }
        case .completed:
            retained = feedState.descriptors()
        }
        let base = retained.last?.graphBoundarySample
            ?? current.renderedGraphSample
        let boundary = base + max(
            1,
            plan.timeline.authoredDurationSamples - plan.cursorSample
        )
        let future: NativeAudioCursorMappingDescriptor
        switch target {
        case let .successor(successor):
            future = descriptor(
                timelineID: successor.timeline.id,
                cursorSample: 0,
                loopIteration: 0,
                isPlaying: true,
                graphBoundarySample: boundary
            )
        case .completed:
            future = descriptor(
                timelineID: plan.timeline.id,
                cursorSample: plan.timeline.authoredDurationSamples,
                loopIteration: 0,
                isPlaying: false,
                graphBoundarySample: boundary
            )
        }
        feedState.publish(
            capture: current,
            descriptors: retained + [future]
        )
    }

    private func descriptor(
        timelineID: AudioTimelineID,
        cursorSample: Int64,
        loopIteration: UInt64,
        isPlaying: Bool,
        graphBoundarySample: Int64
    ) -> NativeAudioCursorMappingDescriptor {
        nextGeneration += 1
        return NativeAudioCursorMappingDescriptor(
            generation: nextGeneration,
            graphBoundarySample: graphBoundarySample,
            snapshotAtBoundary: NativeTimelineTransportSnapshot(
                timelineID: timelineID,
                cursorSample: cursorSample,
                loopIteration: loopIteration,
                isPlaying: isPlaying
            )
        )
    }
}
#endif
