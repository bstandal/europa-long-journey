import ContentKit
import ExperiencePreferences
import Foundation
import JourneyContent
import JourneyDomain
import ProgressStore

public enum ResponsiveAudioProgramControllerError: Error, Equatable, Sendable {
    case missingTimeline(AudioTimelineID)
    case duplicateTimelineID(AudioTimelineID)
    case transportTimelineMismatch(expected: AudioTimelineID, actual: AudioTimelineID?)
    case transportCursorMovedBackwards(expectedMinimum: Int64, actual: Int64)
    case transportLoopMovedBackwards(expectedMinimum: UInt64, actual: UInt64)
    case transportPositionOverflow
    case completionAuthorityRequired
    case causalStageAuthorityMismatch
    case outgoingTailRequiresConsequence
    case outgoingExitPolicyMismatch
    case automaticBoundaryContractViolation(String)
}

/// Distinguishes a cursor captured under the exact durable non-position
/// authority from a monotone projection that still belongs to the preceding
/// authority. A projected snapshot may be persisted for recovery, but it must
/// never refresh the maximum-age watchdog while the new authority is pending.
public enum ResponsiveAudioDurabilityCaptureResult: Equatable, Sendable {
    case verified(ResponsiveAudioProgramSnapshot)
    case awaitingDurableAuthority(
        projectedOldSnapshot: ResponsiveAudioProgramSnapshot
    )
}

private extension ResponsiveAudioProgramSnapshot {
    func matchesNonPosition(
        of other: ResponsiveAudioProgramSnapshot
    ) -> Bool {
        formatVersion == other.formatVersion
            && programID == other.programID
            && stage == other.stage
            && interactionPhase == other.interactionPhase
            && timelineID == other.timelineID
            && causalStage == other.causalStage
            && durableCompletionSequence == other.durableCompletionSequence
    }

    func replacingPositionFrom(
        durableAuthority: ResponsiveAudioProgramSnapshot
    ) -> ResponsiveAudioProgramSnapshot {
        durableAuthority.replacingPosition(
            cursorSample: cursorSample,
            loopIteration: loopIteration
        )
    }

    func replacingPosition(
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

    func isMonotonic(
        after previous: ResponsiveAudioProgramSnapshot?
    ) -> Bool {
        guard let previous else { return true }
        guard matchesNonPosition(of: previous) else { return false }
        if stage == .interaction {
            return loopIteration > previous.loopIteration
                || (loopIteration == previous.loopIteration
                    && cursorSample >= previous.cursorSample)
        }
        return loopIteration == 0
            && previous.loopIteration == 0
            && cursorSample >= previous.cursorSample
    }
}

/// Main-actor bridge between the pure sample-clock runtime and the native
/// AVAudioEngine transport. Every method that changes a durable cursor returns
/// the exact Journey action the app must commit; the controller never writes
/// progress around the write-ahead journal.
@MainActor
public final class ResponsiveAudioProgramController {
    public private(set) var runtime: ResponsiveAudioProgramRuntime

    private let timelinesByID: [AudioTimelineID: AudioTimeline]
    private let transport: any ResponsiveAudioTimelineTransport
    private let resolver: any OfflineAudioAssetResolving
    private var preparedRuntimeCursor: Int64
    private var preparedRuntimeLoopIteration: UInt64
    private var automaticBoundaryGeneration: UInt64 = 0
    private var automaticBoundaryActionHandler: ((JourneyAction) -> Void)?
    private var pendingAutomaticBoundaryActions: [JourneyAction] = []
    private var suppressesAutomaticBoundaryDelivery = false
    private var synchronouslyCapturedAutomaticBoundaryAction: JourneyAction?
    private var constrainedDurabilityAuthority: ResponsiveAudioProgramSnapshot?
    private var lastConstrainedDurabilityCheckpoint:
        ResponsiveAudioProgramSnapshot?
    public private(set) var automaticBoundaryFailure:
        ResponsiveAudioProgramControllerError?

    public init(
        program: ResponsiveAudioProgramSpec,
        timelines: [AudioTimeline],
        transport: any ResponsiveAudioTimelineTransport,
        resolver: any OfflineAudioAssetResolving,
        restoring snapshot: ResponsiveAudioProgramSnapshot? = nil,
        completionReceipt: DurableInteractionAudioCompletionReceipt? = nil,
        restoredCausalStage: ResponsiveAudioCausalStage? = nil
    ) throws {
        var indexedTimelines: [AudioTimelineID: AudioTimeline] = [:]
        for timeline in timelines {
            guard indexedTimelines.updateValue(timeline, forKey: timeline.id) == nil else {
                throw ResponsiveAudioProgramControllerError.duplicateTimelineID(timeline.id)
            }
        }
        timelinesByID = indexedTimelines
        self.transport = transport
        self.resolver = resolver

        if let snapshot {
            if snapshot.stage == .consequence || snapshot.stage == .completed {
                guard completionReceipt != nil else {
                    throw ResponsiveAudioProgramControllerError.completionAuthorityRequired
                }
                runtime = try ResponsiveAudioProgramRuntime(
                    program: program,
                    timelines: timelines,
                    restoring: snapshot,
                    durableCompletionReceipt: completionReceipt,
                    restoredCausalStage: restoredCausalStage
                )
            } else {
                runtime = try ResponsiveAudioProgramRuntime(
                    program: program,
                    timelines: timelines,
                    restoring: snapshot,
                    restoredCausalStage: restoredCausalStage
                )
                if let completionReceipt {
                    try runtime.accept(completionReceipt)
                }
            }
        } else {
            runtime = try ResponsiveAudioProgramRuntime(program: program, timelines: timelines)
            try runtime.reconcileRestoredCausalStage(restoredCausalStage)
            if let completionReceipt {
                try runtime.accept(completionReceipt)
            }
        }
        preparedRuntimeCursor = runtime.cursorSample
        preparedRuntimeLoopIteration = runtime.loopIteration
        try prepareCurrentTimeline()
    }

    /// Rebuilds a paused native session from the integrity-checked Journey
    /// restoration. An audio snapshot cannot authorize its own consequence.
    public convenience init(
        restorationPlan: ResponsiveAudioRestorationPlan,
        restoration: JourneyRestoration,
        transport: any ResponsiveAudioTimelineTransport,
        resolver: any OfflineAudioAssetResolving
    ) throws {
        let receipt: DurableInteractionAudioCompletionReceipt?
        if restorationPlan.requiresCompletionAuthority {
            let sequence = restorationPlan.snapshot?.durableCompletionSequence
                ?? restoration.lastSequence
            receipt = try DurableInteractionAudioCompletionReceipt.makeForRestore(
                sequence: sequence,
                scope: restorationPlan.program.scope,
                interactionSpec: restorationPlan.interaction,
                restoration: restoration
            )
        } else {
            receipt = nil
        }
        let restoredCausalStage = try DurableInteractionAudioCausalStageReceipt
            .restoredCausalStage(
                scope: restorationPlan.program.scope,
                interactionSpec: restorationPlan.interaction,
                restoration: restoration
            )
        try self.init(
            program: restorationPlan.program,
            timelines: restorationPlan.timelines,
            transport: transport,
            resolver: resolver,
            restoring: restorationPlan.snapshot,
            completionReceipt: receipt,
            restoredCausalStage: restoredCausalStage
        )
    }

    public func play() throws {
        try runtime.resume()
        do {
            try transport.play()
        } catch {
            _ = runtime.pause()
            throw error
        }
    }

    /// Applies output routing without touching the deterministic runtime or
    /// asking the transport to play. This is safe while the current timeline
    /// is prepared, paused or already playing.
    public func applyPreferences(_ preferences: ExperiencePreferences) {
        transport.applyPreferences(preferences)
    }

    /// Installs the durability sink for physical finite-stage transitions.
    /// If playback reached a boundary before Journey attached its sink, the
    /// exact action is retained and delivered once rather than being dropped.
    public func setAutomaticBoundaryActionHandler(
        _ handler: @escaping (JourneyAction) -> Void
    ) {
        automaticBoundaryActionHandler = handler
        let pending = pendingAutomaticBoundaryActions
        pendingAutomaticBoundaryActions.removeAll()
        pending.forEach(handler)
    }

    /// Pauses at the transport's current sample, advances the deterministic
    /// program by that exact delta, and returns the state that must be journaled.
    public func pauseAndPersist() throws -> JourneyAction {
        try quiesceForSuspension(.sceneInactive)
    }

    /// Quiesces the native render graph for one lifecycle cause and returns
    /// the exact Journey action owned by that final rendered cursor. Once the
    /// runtime is paused, duplicate inactive/background/notification calls are
    /// idempotent and do not ask the transport to pause again.
    public func quiesceForSuspension(
        _ reason: ResponsiveAudioSuspensionReason
    ) throws -> JourneyAction {
        suppressesAutomaticBoundaryDelivery = true
        synchronouslyCapturedAutomaticBoundaryAction = nil
        do {
            if runtime.isPlaying {
                _ = try synchronizeAndPauseTransport(reason: reason)
            }
            let action = JourneyAction.setResponsiveAudioSnapshot(
                runtime.snapshot()
            )
            synchronouslyCapturedAutomaticBoundaryAction = nil
            suppressesAutomaticBoundaryDelivery = false
            return action
        } catch {
            suppressesAutomaticBoundaryDelivery = false
            // synchronizeAndPauseTransport is transactional. If it throws,
            // the deterministic runtime has returned to its exact entry
            // authority, so a boundary action captured synchronously by the
            // failed physical pause belongs to state that was rolled back.
            // Publishing it later would advance Journey without the matching
            // controller state.
            synchronouslyCapturedAutomaticBoundaryAction = nil
            throw error
        }
    }

    /// Captures a monotonic durability sidecar cursor without pausing,
    /// changing phase/stage, or accepting any consequence authority.
    public func checkpointForDurability() throws
        -> ResponsiveAudioProgramSnapshot {
        try synchronizeWithoutPausingTransport()
        return runtime.snapshot()
    }

    /// Captures cursor movement for one already-durable sidecar authority.
    /// Public phase, causal and stage identity cannot rotate through this API;
    /// Journey retires the old sidecar session only after the corresponding
    /// non-position action is durable.
    public func checkpointForDurability(
        constrainedTo durableAuthority: ResponsiveAudioProgramSnapshot
    ) throws -> ResponsiveAudioDurabilityCaptureResult {
        guard durableAuthority.programID == runtime.program.id,
              let authorityTimeline = timelinesByID[durableAuthority.timelineID] else {
            throw ResponsiveAudioProgramControllerError
                .automaticBoundaryContractViolation(
                    "cursor authority does not belong to this program"
                )
        }
        if constrainedDurabilityAuthority != durableAuthority {
            constrainedDurabilityAuthority = durableAuthority
            lastConstrainedDurabilityCheckpoint = durableAuthority
        }

        try synchronizeWithoutPausingTransport()
        let current = runtime.snapshot()
        let projected: ResponsiveAudioProgramSnapshot
        let isVerified: Bool
        if current.matchesNonPosition(of: durableAuthority) {
            projected = current.replacingPositionFrom(
                durableAuthority: durableAuthority
            )
            isVerified = true
        } else if durableAuthority.stage == .interaction,
                  current.stage == .interaction,
                  let currentTimeline = timelinesByID[current.timelineID],
                  currentTimeline.authoredDurationSamples
                    == authorityTimeline.authoredDurationSamples {
            projected = current.replacingPositionFrom(
                durableAuthority: durableAuthority
            )
            isVerified = false
        } else if durableAuthority.stage == .approach,
                  current.stage == .interaction {
            projected = durableAuthority.replacingPosition(
                cursorSample: authorityTimeline.authoredDurationSamples - 1,
                loopIteration: 0
            )
            isVerified = false
        } else if durableAuthority.stage == .consequence,
                  current.stage == .completed {
            projected = durableAuthority.replacingPosition(
                cursorSample: authorityTimeline.authoredDurationSamples - 1,
                loopIteration: 0
            )
            isVerified = false
        } else {
            // A stage whose public identity is not yet durable cannot lend its
            // physical clock to the prior authority. Keep the last accepted
            // position so the active sidecar stream never regresses.
            return .awaitingDurableAuthority(
                projectedOldSnapshot:
                    lastConstrainedDurabilityCheckpoint ?? durableAuthority
            )
        }

        guard projected.isMonotonic(after: lastConstrainedDurabilityCheckpoint) else {
            return .awaitingDurableAuthority(
                projectedOldSnapshot:
                    lastConstrainedDurabilityCheckpoint ?? durableAuthority
            )
        }
        lastConstrainedDurabilityCheckpoint = projected
        return isVerified
            ? .verified(projected)
            : .awaitingDurableAuthority(projectedOldSnapshot: projected)
    }

    /// Detaches only an already-authorized consequence. The returned handle
    /// owns its short authored fade independently of the next Journey beat.
    public func relinquishConsequence(
        exitPolicy: ResponsiveAudioExitPolicy
    ) throws -> ResponsiveAudioOutgoingTail? {
        guard runtime.stage == .consequence else {
            throw ResponsiveAudioProgramControllerError
                .outgoingTailRequiresConsequence
        }
        guard exitPolicy == runtime.program.exitPolicy else {
            throw ResponsiveAudioProgramControllerError
                .outgoingExitPolicyMismatch
        }
        invalidateAutomaticBoundaryOwnership()
        try synchronizeWithoutPausingTransport()
        let tail = try transport.relinquishOutgoingAudio(
            exitPolicy: exitPolicy
        )
        _ = runtime.pause()
        return tail
    }

    public func relinquishConsequence() throws -> ResponsiveAudioOutgoingTail? {
        try relinquishConsequence(exitPolicy: runtime.program.exitPolicy)
    }

    public func selectInteractionPhase(
        _ phase: ResponsiveInteractionAudioPhase
    ) throws -> JourneyAction {
        try synchronizeWithoutPausingTransport()
        var candidate = runtime
        try candidate.selectInteractionPhase(phase)
        try transition(
            candidate: &candidate,
            baselineCursor: runtime.cursorSample,
            baselineLoopIteration: runtime.loopIteration
        )
        runtime = candidate
        preparedRuntimeCursor = runtime.cursorSample
        preparedRuntimeLoopIteration = runtime.loopIteration
        return .setResponsiveAudioSnapshot(runtime.snapshot())
    }

    /// Applies only a causal stage proven by a prior write-ahead Journey
    /// commit. The timeline, cursor and loop iteration remain unchanged. Nil
    /// means the committed action did not cross a new audio-stage boundary.
    public func selectCausalStage(
        _ authority: DurableInteractionAudioCausalStageReceipt
    ) throws -> JourneyAction? {
        guard authority.scope == runtime.program.scope else {
            throw ResponsiveAudioProgramControllerError.causalStageAuthorityMismatch
        }
        guard runtime.causalStage != authority.causalStage else { return nil }
        if runtime.stage == .interaction, runtime.program.causalMix != nil {
            try synchronizeWithoutPausingTransport()
            var candidate = runtime
            _ = try candidate.selectCausalStage(authority.causalStage)
            try transition(
                candidate: &candidate,
                baselineCursor: runtime.cursorSample,
                baselineLoopIteration: runtime.loopIteration
            )
            runtime = candidate
            preparedRuntimeCursor = runtime.cursorSample
            preparedRuntimeLoopIteration = runtime.loopIteration
            return .setResponsiveAudioSnapshot(runtime.snapshot())
        }
        try synchronizeWithoutPausingTransport()
        let previousRuntime = runtime
        var candidate = runtime
        _ = try candidate.selectCausalStage(authority.causalStage)
        if runtime.stage == .approach {
            do {
                try configureAutomaticBoundary(for: candidate)
            } catch {
                do {
                    // Restaging never restarts the playing approach. If the new
                    // candidate cannot be prepared, restore the prior successor
                    // under a fresh generation before exposing the failure.
                    try configureAutomaticBoundary(for: previousRuntime)
                } catch let restorationError {
                    transport.stop()
                    _ = runtime.pause()
                    automaticBoundaryFailure =
                        .automaticBoundaryContractViolation(
                            "causal successor rollback failed: \(restorationError)"
                        )
                }
                throw error
            }
        }
        runtime = candidate
        preparedRuntimeCursor = runtime.cursorSample
        preparedRuntimeLoopIteration = runtime.loopIteration
        return .setResponsiveAudioSnapshot(runtime.snapshot())
    }

    /// Releases the consequence only after the exact interaction commit has
    /// been synchronously written. The returned follow-up action persists the
    /// new consequence cursor in the same journal.
    public func accept(
        durableCommit: DurableJourneyCommit
    ) throws -> JourneyAction {
        let stageAuthority = try DurableInteractionAudioCausalStageReceipt.make(
            from: durableCommit
        )
        let receipt = try DurableInteractionAudioCompletionReceipt.make(
            from: durableCommit
        )
        if let stageAuthority {
            guard stageAuthority.scope == runtime.program.scope else {
                throw ResponsiveAudioProgramControllerError.causalStageAuthorityMismatch
            }
        }
        try synchronizeWithoutPausingTransport()
        var candidate = runtime
        if let stageAuthority {
            _ = try candidate.selectCausalStage(stageAuthority.causalStage)
        }
        try candidate.accept(receipt)
        try transition(
            candidate: &candidate,
            baselineCursor: candidate.cursorSample,
            baselineLoopIteration: candidate.loopIteration
        )
        runtime = candidate
        preparedRuntimeCursor = runtime.cursorSample
        preparedRuntimeLoopIteration = runtime.loopIteration
        try configureAutomaticBoundaryForCurrentRuntime()
        return .setResponsiveAudioSnapshot(runtime.snapshot())
    }

    public func stopWithoutPersisting() {
        invalidateAutomaticBoundaryOwnership()
        pendingAutomaticBoundaryActions.removeAll()
        constrainedDurabilityAuthority = nil
        lastConstrainedDurabilityCheckpoint = nil
        transport.stop()
        _ = runtime.pause()
    }

    private func synchronizeAndPauseTransport(
        reason: ResponsiveAudioSuspensionReason
    ) throws -> Bool {
        let entryRuntime = runtime
        let entryPreparedRuntimeCursor = preparedRuntimeCursor
        let entryPreparedRuntimeLoopIteration = preparedRuntimeLoopIteration
        let wasPlaying = runtime.isPlaying
        do {
            let transportSnapshot = try transport.pause(for: reason)
            try synchronizeRuntime(to: transportSnapshot)
            _ = runtime.pause()
            if runtime.timelineID != transportSnapshot.timelineID
                || runtime.cursorSample != transportSnapshot.cursorSample
                || runtime.loopIteration != transportSnapshot.loopIteration {
                try prepareCurrentTimeline()
            } else {
                preparedRuntimeCursor = runtime.cursorSample
                preparedRuntimeLoopIteration = runtime.loopIteration
            }
            return wasPlaying
        } catch {
            // The transport may already be physically paused, or a rebuild of
            // its newly observed position may have failed. Until this method
            // returns successfully, none of that later position owns the
            // deterministic controller. Restore the exact entry authority so
            // callers can either stop and persist that fallback or discard it.
            runtime = entryRuntime
            preparedRuntimeCursor = entryPreparedRuntimeCursor
            preparedRuntimeLoopIteration =
                entryPreparedRuntimeLoopIteration
            // The deterministic state rolls back; asynchronous ownership does
            // not. A pre-pause callback, or one installed by a failed rebuild,
            // must never become current again after this failed transaction.
            invalidateAutomaticBoundaryOwnership()
            throw error
        }
    }

    private func synchronizeWithoutPausingTransport() throws {
        let transportSnapshot = transport.snapshot()
        try synchronizeRuntime(to: transportSnapshot)
        preparedRuntimeCursor = runtime.cursorSample
        preparedRuntimeLoopIteration = runtime.loopIteration
    }

    private func synchronizeRuntime(
        to transportSnapshot: NativeTimelineTransportSnapshot
    ) throws {
        var candidate = runtime
        try synchronize(
            candidate: &candidate,
            to: transportSnapshot,
            baselineCursor: preparedRuntimeCursor,
            baselineLoopIteration: preparedRuntimeLoopIteration
        )
        runtime = candidate
    }

    private func synchronize(
        candidate: inout ResponsiveAudioProgramRuntime,
        to transportSnapshot: NativeTimelineTransportSnapshot,
        baselineCursor: Int64,
        baselineLoopIteration: UInt64
    ) throws {
        guard transportSnapshot.timelineID == candidate.timelineID else {
            throw ResponsiveAudioProgramControllerError.transportTimelineMismatch(
                expected: candidate.timelineID,
                actual: transportSnapshot.timelineID
            )
        }
        let delta: Int64
        if candidate.stage == .interaction {
            guard transportSnapshot.loopIteration >= baselineLoopIteration else {
                throw ResponsiveAudioProgramControllerError.transportLoopMovedBackwards(
                    expectedMinimum: baselineLoopIteration,
                    actual: transportSnapshot.loopIteration
                )
            }
            guard let timeline = timelinesByID[candidate.timelineID] else {
                throw ResponsiveAudioProgramControllerError.missingTimeline(candidate.timelineID)
            }
            let iterationDelta = transportSnapshot.loopIteration
                - baselineLoopIteration
            guard iterationDelta <= UInt64(Int64.max) else {
                throw ResponsiveAudioProgramControllerError.transportPositionOverflow
            }
            let (iterationSamples, overflow) = Int64(iterationDelta)
                .multipliedReportingOverflow(by: timeline.authoredDurationSamples)
            guard !overflow else {
                throw ResponsiveAudioProgramControllerError.transportPositionOverflow
            }
            let (positionAtCursor, additionOverflow) = iterationSamples
                .addingReportingOverflow(transportSnapshot.cursorSample)
            let (calculatedDelta, subtractionOverflow) = positionAtCursor
                .subtractingReportingOverflow(baselineCursor)
            guard !additionOverflow, !subtractionOverflow, calculatedDelta >= 0 else {
                throw ResponsiveAudioProgramControllerError.transportCursorMovedBackwards(
                    expectedMinimum: baselineCursor,
                    actual: transportSnapshot.cursorSample
                )
            }
            delta = calculatedDelta
        } else {
            guard transportSnapshot.loopIteration == 0,
                  transportSnapshot.cursorSample >= baselineCursor else {
                throw ResponsiveAudioProgramControllerError.transportCursorMovedBackwards(
                    expectedMinimum: baselineCursor,
                    actual: transportSnapshot.cursorSample
                )
            }
            delta = transportSnapshot.cursorSample - baselineCursor
        }
        if delta > 0 {
            guard candidate.isPlaying else {
                throw ResponsiveAudioProgramControllerError.transportCursorMovedBackwards(
                    expectedMinimum: baselineCursor,
                    actual: transportSnapshot.cursorSample
                )
            }
            try candidate.advance(bySamples: delta)
        }
    }

    private func prepareCurrentTimeline() throws {
        guard runtime.stage != .completed else {
            invalidateAutomaticBoundaryOwnership()
            transport.stop()
            preparedRuntimeCursor = runtime.cursorSample
            preparedRuntimeLoopIteration = runtime.loopIteration
            return
        }
        guard let plan = try runtime.makeTimelineTransportPlan() else {
            throw ResponsiveAudioProgramControllerError.missingTimeline(runtime.timelineID)
        }
        try transport.prepareResponsiveAudio(plan: plan, resolver: resolver)
        preparedRuntimeCursor = runtime.cursorSample
        preparedRuntimeLoopIteration = runtime.loopIteration
        try configureAutomaticBoundaryForCurrentRuntime()
    }

    private func transition(
        candidate: inout ResponsiveAudioProgramRuntime,
        baselineCursor: Int64,
        baselineLoopIteration: UInt64
    ) throws {
        invalidateAutomaticBoundaryOwnership()
        guard let plan = try candidate.makeTimelineTransportPlan() else {
            throw ResponsiveAudioProgramControllerError.missingTimeline(
                candidate.timelineID
            )
        }
        _ = try transport.transitionResponsiveAudio(
            to: plan,
            resolver: resolver,
            validateBeforeCommit: { authoritativeSnapshot in
                try synchronize(
                    candidate: &candidate,
                    to: authoritativeSnapshot,
                    baselineCursor: baselineCursor,
                    baselineLoopIteration: baselineLoopIteration
                )
            }
        )
    }

    private func configureAutomaticBoundaryForCurrentRuntime() throws {
        try configureAutomaticBoundary(for: runtime)
    }

    private func configureAutomaticBoundary(
        for sourceRuntime: ResponsiveAudioProgramRuntime
    ) throws {
        let successorPlan: ResponsiveAudioTimelineTransportPlan?
        switch sourceRuntime.stage {
        case .approach:
            guard let approach = timelinesByID[sourceRuntime.timelineID] else {
                throw ResponsiveAudioProgramControllerError
                    .missingTimeline(sourceRuntime.timelineID)
            }
            var successor = sourceRuntime
            if !successor.isPlaying {
                try successor.resume()
            }
            try successor.advance(
                bySamples: approach.authoredDurationSamples
                    - successor.cursorSample
            )
            _ = successor.pause()
            successorPlan = try successor.makeTimelineTransportPlan()
        case .consequence:
            successorPlan = nil
        case .interaction, .completed:
            return
        }

        automaticBoundaryGeneration &+= 1
        let generation = automaticBoundaryGeneration
        try transport.configureAutomaticBoundary(
            successorPlan: successorPlan,
            resolver: resolver,
            handler: { [weak self] event in
                self?.acceptAutomaticBoundaryEvent(
                    event,
                    generation: generation
                )
            }
        )
    }

    private func acceptAutomaticBoundaryEvent(
        _ event: ResponsiveAudioAutomaticBoundaryEvent,
        generation: UInt64
    ) {
        guard generation == automaticBoundaryGeneration else { return }
        do {
            var candidate = runtime
            switch event {
            case let .successorStarted(snapshot):
                guard candidate.stage == .approach,
                      candidate.isPlaying,
                      let approach = timelinesByID[candidate.timelineID] else {
                    throw ResponsiveAudioProgramControllerError
                        .automaticBoundaryContractViolation(
                            "successor callback did not own a playing approach"
                        )
                }
                try candidate.advance(
                    bySamples: approach.authoredDurationSamples
                        - candidate.cursorSample
                )
                guard candidate.stage == .interaction,
                      candidate.interactionPhase == .waiting,
                      candidate.timelineID == snapshot.timelineID,
                      candidate.cursorSample == 0,
                      candidate.loopIteration == 0,
                      snapshot.cursorSample == 0,
                      snapshot.loopIteration == 0,
                      snapshot.isPlaying else {
                    throw ResponsiveAudioProgramControllerError
                        .automaticBoundaryContractViolation(
                            "approach successor was not waiting sample zero"
                        )
                }
            case let .completed(snapshot):
                guard candidate.stage == .consequence,
                      candidate.isPlaying,
                      let consequence = timelinesByID[candidate.timelineID] else {
                    throw ResponsiveAudioProgramControllerError
                        .automaticBoundaryContractViolation(
                            "completion callback did not own a playing consequence"
                        )
                }
                try candidate.advance(
                    bySamples: consequence.authoredDurationSamples
                        - candidate.cursorSample
                )
                guard candidate.stage == .completed,
                      candidate.timelineID == snapshot.timelineID,
                      candidate.cursorSample == consequence.authoredDurationSamples,
                      snapshot.cursorSample == consequence.authoredDurationSamples,
                      snapshot.loopIteration == 0,
                      !snapshot.isPlaying else {
                    throw ResponsiveAudioProgramControllerError
                        .automaticBoundaryContractViolation(
                            "consequence completion did not own its exact sentinel"
                        )
                }
            }
            runtime = candidate
            preparedRuntimeCursor = candidate.cursorSample
            preparedRuntimeLoopIteration = candidate.loopIteration
            automaticBoundaryGeneration &+= 1
            let action = JourneyAction.setResponsiveAudioSnapshot(
                candidate.snapshot()
            )
            if suppressesAutomaticBoundaryDelivery {
                synchronouslyCapturedAutomaticBoundaryAction = action
            } else if let automaticBoundaryActionHandler {
                automaticBoundaryActionHandler(action)
            } else {
                pendingAutomaticBoundaryActions.append(action)
            }
        } catch {
            automaticBoundaryGeneration &+= 1
            transport.stop()
            _ = runtime.pause()
            automaticBoundaryFailure = .automaticBoundaryContractViolation(
                String(describing: error)
            )
        }
    }

    private func invalidateAutomaticBoundaryOwnership() {
        automaticBoundaryGeneration &+= 1
    }
}
