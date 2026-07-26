import ContentKit
import Foundation

public enum ResponsiveAudioPlaybackRepetition: Equatable, Sendable {
    case once
    case loop(iteration: UInt64, durationSamples: Int64)
}

public struct ResponsiveAudioCausalLayerPlaybackTarget: Equatable, Sendable {
    public let layerID: ResponsiveAudioMaterialLayerID
    public let cueID: AudioCueID
    public let role: AudioTrackRole
    public let assetPath: String
    public let startSample: Int64
    public let durationSamples: Int64
    public let targetGain: Double

    public init(
        layerID: ResponsiveAudioMaterialLayerID,
        cueID: AudioCueID,
        role: AudioTrackRole,
        assetPath: String,
        startSample: Int64,
        durationSamples: Int64,
        targetGain: Double
    ) {
        self.layerID = layerID
        self.cueID = cueID
        self.role = role
        self.assetPath = assetPath
        self.startSample = startSample
        self.durationSamples = durationSamples
        self.targetGain = targetGain
    }
}

/// Fully resolved common-player mix for the current interaction phase. A nil
/// persisted causal stage deliberately selects state zero here.
public struct ResponsiveAudioCausalMixPlaybackPlan: Equatable, Sendable {
    public let completedStageCount: Int
    public let rampDurationSamples: Int64
    public let layers: [ResponsiveAudioCausalLayerPlaybackTarget]

    public init(
        completedStageCount: Int,
        rampDurationSamples: Int64,
        layers: [ResponsiveAudioCausalLayerPlaybackTarget]
    ) {
        self.completedStageCount = completedStageCount
        self.rampDurationSamples = rampDurationSamples
        self.layers = layers
    }
}

/// Exact deterministic request at the native transport boundary. Interaction
/// requests carry both the persisted loop iteration and the resolved common
/// material mix; approach and consequence requests remain conventional.
public struct ResponsiveAudioTimelineTransportPlan: Equatable, Sendable {
    public let timeline: AudioTimeline
    public let cursorSample: Int64
    public let loopIteration: UInt64
    public let repetition: ResponsiveAudioPlaybackRepetition
    public let causalMix: ResponsiveAudioCausalMixPlaybackPlan?

    public init(
        timeline: AudioTimeline,
        cursorSample: Int64,
        loopIteration: UInt64,
        repetition: ResponsiveAudioPlaybackRepetition,
        causalMix: ResponsiveAudioCausalMixPlaybackPlan?
    ) {
        self.timeline = timeline
        self.cursorSample = cursorSample
        self.loopIteration = loopIteration
        self.repetition = repetition
        self.causalMix = causalMix
    }
}

/// One finite scheduling window. Interaction windows end at the current loop
/// boundary and are planned again from sample zero for the next iteration.
public struct ResponsiveAudioPlaybackPlan: Equatable, Sendable {
    public let stage: ResponsiveAudioProgramStage
    public let interactionPhase: ResponsiveInteractionAudioPhase?
    /// Persisted causal progress available to a later common-player stem/gain
    /// implementation. The current transport intentionally does not invent a
    /// discontinuous stage mix when no authored stage transport exists.
    public let causalStage: ResponsiveAudioCausalStage?
    public let causalMix: ResponsiveAudioCausalMixPlaybackPlan?
    public let layerStates: ResponsiveAudioLayerStateSelection?
    public let repetition: ResponsiveAudioPlaybackRepetition
    public let authoredSilenceCueIDs: [AudioCueID]
    public let timelinePlan: TimelinePlaybackPlan

    public var isInsideAuthoredSilence: Bool {
        !authoredSilenceCueIDs.isEmpty
    }

    public init(
        stage: ResponsiveAudioProgramStage,
        interactionPhase: ResponsiveInteractionAudioPhase?,
        causalStage: ResponsiveAudioCausalStage?,
        causalMix: ResponsiveAudioCausalMixPlaybackPlan?,
        layerStates: ResponsiveAudioLayerStateSelection?,
        repetition: ResponsiveAudioPlaybackRepetition,
        authoredSilenceCueIDs: [AudioCueID],
        timelinePlan: TimelinePlaybackPlan
    ) {
        self.stage = stage
        self.interactionPhase = interactionPhase
        self.causalStage = causalStage
        self.causalMix = causalMix
        self.layerStates = layerStates
        self.repetition = repetition
        self.authoredSilenceCueIDs = authoredSilenceCueIDs
        self.timelinePlan = timelinePlan
    }
}

public enum ResponsiveAudioRuntimeError: Error, Equatable, Sendable {
    case invalidProgram(String)
    case unsupportedSnapshotVersion(Int)
    case snapshotProgramMismatch(
        expected: ResponsiveAudioProgramID,
        actual: ResponsiveAudioProgramID
    )
    case invalidSnapshot(String)
    case programCompleted
    case playbackPaused
    case invalidSampleAdvance(Int64)
    case invalidPhaseTransition(
        stage: ResponsiveAudioProgramStage,
        phase: ResponsiveInteractionAudioPhase
    )
    case invalidCausalStage(Int)
    case causalStageUnavailable(ResponsiveAudioProgramStage)
    case causalStageRegression(current: Int, proposed: Int)
    case causalStageSkip(current: Int?, proposed: Int)
    case invalidDurableCompletion
    case loopIterationOverflow
}

/// Pure sample-clock state machine for an interactive beat. No wall clock and
/// no network state enter the transition rules, so replaying the same program,
/// snapshot and inputs yields the same audio position.
public struct ResponsiveAudioProgramRuntime: Sendable {
    public let program: ResponsiveAudioProgramSpec

    public private(set) var stage: ResponsiveAudioProgramStage
    public private(set) var interactionPhase: ResponsiveInteractionAudioPhase?
    public private(set) var timelineID: AudioTimelineID
    public private(set) var cursorSample: Int64
    public private(set) var loopIteration: UInt64
    public private(set) var causalStage: ResponsiveAudioCausalStage?
    public private(set) var durableCompletionSequence: UInt64?
    public private(set) var isPlaying: Bool

    private let timelinesByID: [AudioTimelineID: AudioTimeline]

    public init(
        program: ResponsiveAudioProgramSpec,
        timelines: [AudioTimeline]
    ) throws {
        do {
            try program.validate(timelines: timelines)
        } catch {
            throw ResponsiveAudioRuntimeError.invalidProgram(String(describing: error))
        }
        self.program = program
        timelinesByID = Dictionary(uniqueKeysWithValues: timelines.map { ($0.id, $0) })
        stage = .approach
        interactionPhase = nil
        timelineID = program.approachTimelineID
        cursorSample = 0
        loopIteration = 0
        causalStage = nil
        durableCompletionSequence = nil
        isPlaying = false
    }

    public init(
        program: ResponsiveAudioProgramSpec,
        timelines: [AudioTimeline],
        restoring snapshot: ResponsiveAudioProgramSnapshot,
        durableCompletionReceipt: DurableInteractionAudioCompletionReceipt? = nil,
        restoredCausalStage: ResponsiveAudioCausalStage? = nil
    ) throws {
        try self.init(program: program, timelines: timelines)
        try restore(snapshot, durableCompletionReceipt: durableCompletionReceipt)
        try reconcileRestoredCausalStage(restoredCausalStage)
    }

    public mutating func resume() throws {
        guard stage != .completed else {
            throw ResponsiveAudioRuntimeError.programCompleted
        }
        isPlaying = true
    }

    @discardableResult
    public mutating func pause() -> ResponsiveAudioProgramSnapshot {
        isPlaying = false
        return snapshot()
    }

    public func snapshot() -> ResponsiveAudioProgramSnapshot {
        ResponsiveAudioProgramSnapshot(
            programID: program.id,
            stage: stage,
            interactionPhase: interactionPhase,
            timelineID: timelineID,
            cursorSample: cursorSample,
            loopIteration: loopIteration,
            causalStage: causalStage,
            durableCompletionSequence: durableCompletionSequence
        )
    }

    /// Advances authored time. In the interaction stage this can only loop the
    /// active bed; it has no path into the consequence stage.
    public mutating func advance(bySamples samples: Int64) throws {
        guard samples >= 0 else {
            throw ResponsiveAudioRuntimeError.invalidSampleAdvance(samples)
        }
        guard isPlaying else {
            throw ResponsiveAudioRuntimeError.playbackPaused
        }
        guard stage != .completed else {
            throw ResponsiveAudioRuntimeError.programCompleted
        }

        var candidate = self
        try candidate.advanceUnchecked(bySamples: samples)
        self = candidate
    }

    /// Changes only the authored interaction bed. Equal-duration phase beds
    /// retain the exact cursor and iteration, preventing timing drift.
    public mutating func selectInteractionPhase(
        _ phase: ResponsiveInteractionAudioPhase
    ) throws {
        guard stage == .interaction,
              let bed = program.interactionBed(for: phase) else {
            throw ResponsiveAudioRuntimeError.invalidPhaseTransition(
                stage: stage,
                phase: phase
            )
        }
        interactionPhase = phase
        timelineID = bed.timelineID
    }

    /// Advances the opaque historical stage without selecting a different
    /// timeline or touching the sample clock. A live update may establish the
    /// initial zero state or cross one threshold; later updates can neither
    /// skip nor undo a durable stage.
    @discardableResult
    public mutating func selectCausalStage(
        _ proposed: ResponsiveAudioCausalStage
    ) throws -> Bool {
        guard stage == .approach || stage == .interaction else {
            throw ResponsiveAudioRuntimeError.causalStageUnavailable(stage)
        }
        let proposedCount = proposed.completedStageCount
        guard proposedCount >= 0 else {
            throw ResponsiveAudioRuntimeError.invalidCausalStage(proposedCount)
        }
        if let mix = program.causalMix,
           mix.state(forCompletedStageCount: proposedCount) == nil {
            throw ResponsiveAudioRuntimeError.invalidCausalStage(proposedCount)
        }
        if let current = causalStage?.completedStageCount {
            guard proposedCount >= current else {
                throw ResponsiveAudioRuntimeError.causalStageRegression(
                    current: current,
                    proposed: proposedCount
                )
            }
            guard proposedCount <= current + 1 else {
                throw ResponsiveAudioRuntimeError.causalStageSkip(
                    current: current,
                    proposed: proposedCount
                )
            }
            guard proposedCount != current else { return false }
        } else {
            guard proposedCount <= 1 else {
                throw ResponsiveAudioRuntimeError.causalStageSkip(
                    current: nil,
                    proposed: proposedCount
                )
            }
        }
        causalStage = proposed
        return true
    }

    /// The sole interaction-to-consequence transition. The receipt can only be
    /// produced from a completed DurableJourneyCommit by DramaticAudio.
    public mutating func accept(
        _ receipt: DurableInteractionAudioCompletionReceipt
    ) throws {
        guard stage == .approach || stage == .interaction,
              receipt.scope == program.scope,
              receipt.sequence > 0,
              durableCompletionSequence == nil else {
            throw ResponsiveAudioRuntimeError.invalidDurableCompletion
        }
        stage = .consequence
        interactionPhase = nil
        timelineID = program.consequenceTimelineID
        cursorSample = 0
        loopIteration = 0
        durableCompletionSequence = receipt.sequence
    }

    public func makePlaybackPlan(
        assetMetadata: [String: AudioAssetMetadata]
    ) throws -> ResponsiveAudioPlaybackPlan? {
        guard stage != .completed else { return nil }
        guard let timeline = timelinesByID[timelineID] else {
            throw ResponsiveAudioRuntimeError.invalidProgram(
                "Current timeline '\(timelineID)' is unavailable"
            )
        }
        let timelinePlan = try TimelinePlaybackPlanner.makePlan(
            timeline: timeline,
            cursorSample: cursorSample,
            assetMetadata: assetMetadata
        )
        let silenceCueIDs = timeline.events.compactMap { event -> AudioCueID? in
            guard event.role == .silence,
                  event.startSample <= cursorSample,
                  cursorSample < event.startSample + event.durationSamples else {
                return nil
            }
            return event.cueID
        }.sorted()

        let bed = interactionPhase.flatMap(program.interactionBed(for:))
        let causalMix = try makeCausalMixPlaybackPlan()
        let repetition: ResponsiveAudioPlaybackRepetition = if stage == .interaction {
            .loop(
                iteration: loopIteration,
                durationSamples: timeline.authoredDurationSamples
            )
        } else {
            .once
        }
        return ResponsiveAudioPlaybackPlan(
            stage: stage,
            interactionPhase: interactionPhase,
            causalStage: causalStage,
            causalMix: causalMix,
            layerStates: bed?.layerStates,
            repetition: repetition,
            authoredSilenceCueIDs: silenceCueIDs,
            timelinePlan: timelinePlan
        )
    }

    public func makeTimelineTransportPlan() throws -> ResponsiveAudioTimelineTransportPlan? {
        guard stage != .completed else { return nil }
        guard let timeline = timelinesByID[timelineID] else {
            throw ResponsiveAudioRuntimeError.invalidProgram(
                "Current timeline '\(timelineID)' is unavailable"
            )
        }
        let repetition: ResponsiveAudioPlaybackRepetition = if stage == .interaction {
            .loop(
                iteration: loopIteration,
                durationSamples: timeline.authoredDurationSamples
            )
        } else {
            .once
        }
        return ResponsiveAudioTimelineTransportPlan(
            timeline: timeline,
            cursorSample: cursorSample,
            loopIteration: loopIteration,
            repetition: repetition,
            causalMix: try makeCausalMixPlaybackPlan()
        )
    }

    private func makeCausalMixPlaybackPlan() throws
        -> ResponsiveAudioCausalMixPlaybackPlan? {
        guard stage == .interaction,
              let phase = interactionPhase,
              let mix = program.causalMix else {
            return nil
        }
        let completedStageCount = causalStage?.completedStageCount ?? 0
        guard let state = mix.state(
            forCompletedStageCount: completedStageCount
        ), let timeline = timelinesByID[timelineID] else {
            throw ResponsiveAudioRuntimeError.invalidProgram(
                "Causal mix has no state for completed stage count \(completedStageCount)"
            )
        }
        let gains = Dictionary(uniqueKeysWithValues: state.layerGains.map {
            ($0.layerID, $0.gain)
        })
        let targets = try mix.layers.map { layer in
            let cueID = layer.cueIDs.cueID(for: phase)
            guard let event = timeline.events.first(where: { $0.cueID == cueID }),
                  let targetGain = gains[layer.id] else {
                throw ResponsiveAudioRuntimeError.invalidProgram(
                    "Causal layer '\(layer.id)' is not resolved in timeline '\(timeline.id)'"
                )
            }
            return ResponsiveAudioCausalLayerPlaybackTarget(
                layerID: layer.id,
                cueID: cueID,
                role: event.role,
                assetPath: layer.assetPath,
                startSample: event.startSample,
                durationSamples: event.durationSamples,
                targetGain: targetGain
            )
        }
        return ResponsiveAudioCausalMixPlaybackPlan(
            completedStageCount: completedStageCount,
            rampDurationSamples: mix.rampDurationSamples,
            layers: targets
        )
    }

    private mutating func restore(
        _ snapshot: ResponsiveAudioProgramSnapshot,
        durableCompletionReceipt: DurableInteractionAudioCompletionReceipt?
    ) throws {
        guard snapshot.formatVersion == ResponsiveAudioProgramSnapshot.currentFormatVersion else {
            throw ResponsiveAudioRuntimeError.unsupportedSnapshotVersion(snapshot.formatVersion)
        }
        guard snapshot.programID == program.id else {
            throw ResponsiveAudioRuntimeError.snapshotProgramMismatch(
                expected: program.id,
                actual: snapshot.programID
            )
        }
        guard snapshot.cursorSample >= 0 else {
            throw ResponsiveAudioRuntimeError.invalidSnapshot("cursor cannot be negative")
        }
        if let count = snapshot.causalStage?.completedStageCount,
           count < 0 {
            throw ResponsiveAudioRuntimeError.invalidSnapshot(
                "causal stage cannot be negative"
            )
        }
        if let count = snapshot.causalStage?.completedStageCount,
           let mix = program.causalMix,
           mix.state(forCompletedStageCount: count) == nil {
            throw ResponsiveAudioRuntimeError.invalidSnapshot(
                "causal stage is not authored by this program"
            )
        }

        let expectedTimelineID: AudioTimelineID
        let expectedDuration: Int64
        switch snapshot.stage {
        case .approach:
            guard snapshot.interactionPhase == nil,
                  snapshot.loopIteration == 0,
                  snapshot.durableCompletionSequence == nil,
                  durableCompletionReceipt == nil else {
                throw ResponsiveAudioRuntimeError.invalidSnapshot(
                    "approach cannot contain interaction or completion state"
                )
            }
            expectedTimelineID = program.approachTimelineID
            expectedDuration = try duration(of: expectedTimelineID)
            guard snapshot.cursorSample < expectedDuration else {
                throw ResponsiveAudioRuntimeError.invalidSnapshot(
                    "approach cursor must precede its terminal boundary"
                )
            }

        case .interaction:
            guard let phase = snapshot.interactionPhase,
                  let bed = program.interactionBed(for: phase),
                  snapshot.durableCompletionSequence == nil,
                  durableCompletionReceipt == nil else {
                throw ResponsiveAudioRuntimeError.invalidSnapshot(
                    "interaction requires one authored phase and no completion receipt"
                )
            }
            expectedTimelineID = bed.timelineID
            expectedDuration = try duration(of: expectedTimelineID)
            guard snapshot.cursorSample < expectedDuration else {
                throw ResponsiveAudioRuntimeError.invalidSnapshot(
                    "interaction cursor must remain inside the current loop"
                )
            }

        case .consequence:
            guard snapshot.interactionPhase == nil,
                  snapshot.loopIteration == 0,
                  let sequence = snapshot.durableCompletionSequence,
                  sequence > 0,
                  durableCompletionReceipt?.sequence == sequence,
                  durableCompletionReceipt?.scope == program.scope else {
                throw ResponsiveAudioRuntimeError.invalidSnapshot(
                    "consequence requires a durable completion sequence"
                )
            }
            expectedTimelineID = program.consequenceTimelineID
            expectedDuration = try duration(of: expectedTimelineID)
            guard snapshot.cursorSample < expectedDuration else {
                throw ResponsiveAudioRuntimeError.invalidSnapshot(
                    "consequence cursor must precede its terminal boundary"
                )
            }

        case .completed:
            guard snapshot.interactionPhase == nil,
                  snapshot.loopIteration == 0,
                  let sequence = snapshot.durableCompletionSequence,
                  sequence > 0,
                  durableCompletionReceipt?.sequence == sequence,
                  durableCompletionReceipt?.scope == program.scope else {
                throw ResponsiveAudioRuntimeError.invalidSnapshot(
                    "completed state requires a durable completion sequence"
                )
            }
            expectedTimelineID = program.consequenceTimelineID
            expectedDuration = try duration(of: expectedTimelineID)
            guard snapshot.cursorSample == expectedDuration else {
                throw ResponsiveAudioRuntimeError.invalidSnapshot(
                    "completed cursor must equal the consequence boundary"
                )
            }
        }

        guard snapshot.timelineID == expectedTimelineID else {
            throw ResponsiveAudioRuntimeError.invalidSnapshot(
                "timeline does not match the authored stage or interaction phase"
            )
        }
        stage = snapshot.stage
        interactionPhase = snapshot.interactionPhase
        timelineID = snapshot.timelineID
        cursorSample = snapshot.cursorSample
        loopIteration = snapshot.loopIteration
        causalStage = snapshot.causalStage
        durableCompletionSequence = snapshot.durableCompletionSequence
        isPlaying = false
    }

    /// Reconciles an integrity-checked Journey restoration with an older audio
    /// snapshot. A missing field is a compatible legacy save. A present field
    /// may lag by one journalled Transform action if the process stopped in the
    /// intentional interaction/audio follow-up gap; it can never lead, regress
    /// or conceal several missing stage commits.
    mutating func reconcileRestoredCausalStage(
        _ restored: ResponsiveAudioCausalStage?
    ) throws {
        guard let restored else { return }
        let restoredCount = restored.completedStageCount
        guard restoredCount >= 0 else {
            throw ResponsiveAudioRuntimeError.invalidSnapshot(
                "restored causal stage cannot be negative"
            )
        }
        if let mix = program.causalMix,
           mix.state(forCompletedStageCount: restoredCount) == nil {
            throw ResponsiveAudioRuntimeError.invalidSnapshot(
                "restored causal stage is not authored by this program"
            )
        }
        if let savedCount = causalStage?.completedStageCount {
            guard savedCount <= restoredCount,
                  restoredCount - savedCount <= 1 else {
                throw ResponsiveAudioRuntimeError.invalidSnapshot(
                    "saved causal stage did not match durable Transform progress"
                )
            }
        }
        causalStage = restored
    }

    private mutating func advanceUnchecked(bySamples samples: Int64) throws {
        switch stage {
        case .approach:
            let duration = try duration(of: timelineID)
            let remaining = duration - cursorSample
            if samples < remaining {
                cursorSample += samples
                return
            }
            try enterInteraction()
            try advanceInteraction(bySamples: samples - remaining)

        case .interaction:
            try advanceInteraction(bySamples: samples)

        case .consequence:
            let duration = try duration(of: timelineID)
            let remaining = duration - cursorSample
            if samples < remaining {
                cursorSample += samples
                return
            }
            cursorSample = duration
            stage = .completed
            isPlaying = false

        case .completed:
            throw ResponsiveAudioRuntimeError.programCompleted
        }
    }

    private mutating func enterInteraction() throws {
        let phase = ResponsiveInteractionAudioPhase.waiting
        guard let bed = program.interactionBed(for: phase) else {
            throw ResponsiveAudioRuntimeError.invalidProgram(
                "The waiting interaction bed is unavailable"
            )
        }
        stage = .interaction
        interactionPhase = phase
        timelineID = bed.timelineID
        cursorSample = 0
        loopIteration = 0
    }

    private mutating func advanceInteraction(bySamples samples: Int64) throws {
        guard samples > 0 else { return }
        let duration = try duration(of: timelineID)
        let samplesToBoundary = duration - cursorSample
        guard samples >= samplesToBoundary else {
            cursorSample += samples
            return
        }

        var additionalIterations: UInt64 = 1
        let afterBoundary = samples - samplesToBoundary
        additionalIterations += UInt64(afterBoundary / duration)
        let (nextIteration, overflow) = loopIteration.addingReportingOverflow(
            additionalIterations
        )
        guard !overflow else {
            throw ResponsiveAudioRuntimeError.loopIterationOverflow
        }
        loopIteration = nextIteration
        cursorSample = afterBoundary % duration
    }

    private func duration(of timelineID: AudioTimelineID) throws -> Int64 {
        guard let timeline = timelinesByID[timelineID],
              timeline.authoredDurationSamples > 0 else {
            throw ResponsiveAudioRuntimeError.invalidProgram(
                "Timeline '\(timelineID)' has no positive duration"
            )
        }
        return timeline.authoredDurationSamples
    }
}
