import Foundation

public enum ResponsiveAudioProgramIDDomain: Sendable {}
public enum ResponsiveAudioMaterialLayerIDDomain: Sendable {}

/// Stable, title-independent identity for one user-paced dramatic-audio program.
public typealias ResponsiveAudioProgramID = StableID<ResponsiveAudioProgramIDDomain>

/// Stable identity for one material loop whose sample clock is shared across
/// every interaction phase. It is authored explicitly; runtime code never
/// infers a layer from a cue ID or file name.
public typealias ResponsiveAudioMaterialLayerID =
    StableID<ResponsiveAudioMaterialLayerIDDomain>

/// The only transient interaction states allowed to select an authored bed.
/// Historical completion is deliberately absent: it is a durable transition
/// into the consequence timeline, not a presentation state.
public enum ResponsiveInteractionAudioPhase: String, CaseIterable, Codable, Equatable, Sendable {
    case waiting
    case engaged
    case resistance
}

/// Persisted program stage. This lives in ContentKit rather than the audio
/// renderer so JourneyState can save an exact offline cursor without making
/// the domain layer depend on AVFAudio.
public enum ResponsiveAudioProgramStage: String, Codable, Equatable, Sendable {
    case approach
    case interaction
    case consequence
    case completed
}

/// Authored route-exit behavior for a finite consequence. The duration is
/// expressed in that timeline's sample domain; runtime code must never replace
/// it with a hidden wall-clock constant.
public enum ResponsiveAudioExitPolicy: Codable, Equatable, Sendable {
    case boundedFade(durationSamples: Int64)

    private enum CodingKeys: String, CodingKey {
        case kind
        case durationSamples
    }

    private enum Kind: String, Codable {
        case boundedFade = "bounded-fade"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .boundedFade:
            self = .boundedFade(
                durationSamples: try container.decode(
                    Int64.self,
                    forKey: .durationSamples
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .boundedFade(durationSamples):
            try container.encode(Kind.boundedFade, forKey: .kind)
            try container.encode(durationSamples, forKey: .durationSamples)
        }
    }

    public var boundedFadeDurationSamples: Int64 {
        switch self {
        case let .boundedFade(durationSamples): durationSamples
        }
    }

    public func validate(field: String = "responsiveAudioExitPolicy") throws {
        let duration = boundedFadeDurationSamples
        guard duration > 0, duration <= Int64(UInt32.max) else {
            throw ContentValidationError.invalidValue(
                field: "\(field).durationSamples",
                reason: "must fit one positive sample-accurate audio-unit ramp"
            )
        }
    }
}

/// An audio-facing record of irreversible progress through an authored
/// historical mechanism. The number deliberately carries no stage names or
/// Transform controls into DramaticAudio; JourneyDomain remains the authority
/// that derives it from `TransformProgress.completedStageCount`.
///
/// Existing phase-only programs leave this value absent. A future transport
/// may use it to select authored stems or gains, but the persisted value is
/// already independent of that rendering choice.
public struct ResponsiveAudioCausalStage: Codable, Equatable, Sendable {
    public let completedStageCount: Int

    public init(completedStageCount: Int) {
        self.completedStageCount = completedStageCount
    }
}

/// Complete durable playback position. Playback intent is deliberately not
/// persisted: a cold restore always returns paused at these exact samples.
public struct ResponsiveAudioProgramSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let programID: ResponsiveAudioProgramID
    public let stage: ResponsiveAudioProgramStage
    public let interactionPhase: ResponsiveInteractionAudioPhase?
    public let timelineID: AudioTimelineID
    public let cursorSample: Int64
    public let loopIteration: UInt64
    public let causalStage: ResponsiveAudioCausalStage?
    public let durableCompletionSequence: UInt64?

    public init(
        formatVersion: Int = currentFormatVersion,
        programID: ResponsiveAudioProgramID,
        stage: ResponsiveAudioProgramStage,
        interactionPhase: ResponsiveInteractionAudioPhase?,
        timelineID: AudioTimelineID,
        cursorSample: Int64,
        loopIteration: UInt64,
        causalStage: ResponsiveAudioCausalStage? = nil,
        durableCompletionSequence: UInt64?
    ) {
        self.formatVersion = formatVersion
        self.programID = programID
        self.stage = stage
        self.interactionPhase = interactionPhase
        self.timelineID = timelineID
        self.cursorSample = cursorSample
        self.loopIteration = loopIteration
        self.causalStage = causalStage
        self.durableCompletionSequence = durableCompletionSequence
    }
}

public struct ResponsiveAudioProgramScope: Codable, Hashable, Sendable {
    public let chapterID: ChapterID
    public let arcID: ArcID
    public let beatID: BeatID
    public let interactionID: InteractionID

    public init(
        chapterID: ChapterID,
        arcID: ArcID,
        beatID: BeatID,
        interactionID: InteractionID
    ) {
        self.chapterID = chapterID
        self.arcID = arcID
        self.beatID = beatID
        self.interactionID = interactionID
    }

    fileprivate func validate() throws {
        try requireNonempty(chapterID, field: "responsiveAudioProgram.scope.chapterID")
        try requireNonempty(arcID, field: "responsiveAudioProgram.scope.arcID")
        try requireNonempty(beatID, field: "responsiveAudioProgram.scope.beatID")
        try requireNonempty(interactionID, field: "responsiveAudioProgram.scope.interactionID")
    }
}

/// Named score and soundscape states make phase selection inspectable even
/// when several stems are mixed inside one finite AudioTimeline. A nil state
/// is an explicit instruction that the corresponding role is silent.
public struct ResponsiveAudioLayerStateSelection: Codable, Equatable, Sendable {
    public let scoreStateID: String?
    public let soundscapeStateID: String?

    public init(scoreStateID: String?, soundscapeStateID: String?) {
        self.scoreStateID = scoreStateID
        self.soundscapeStateID = soundscapeStateID
    }

    fileprivate func validate(field: String) throws {
        for (name, value) in [
            ("scoreStateID", scoreStateID),
            ("soundscapeStateID", soundscapeStateID),
        ] {
            if let value, !isStableStringIdentifier(value) {
                throw ContentValidationError.invalidValue(
                    field: "\(field).\(name)",
                    reason: "must be a stable kebab-case identifier when the layer is audible"
                )
            }
        }
    }
}

public struct ResponsiveInteractionAudioBedSpec: Codable, Equatable, Sendable {
    public let phase: ResponsiveInteractionAudioPhase
    public let timelineID: AudioTimelineID
    public let layerStates: ResponsiveAudioLayerStateSelection

    public init(
        phase: ResponsiveInteractionAudioPhase,
        timelineID: AudioTimelineID,
        layerStates: ResponsiveAudioLayerStateSelection
    ) {
        self.phase = phase
        self.timelineID = timelineID
        self.layerStates = layerStates
    }
}

/// Exact cue identity for one material layer in each authored phase timeline.
/// Separate fields make a missing or duplicated phase impossible to hide in
/// array ordering or a cue-name convention.
public struct ResponsiveAudioPhaseCueIDs: Codable, Equatable, Sendable {
    public let waiting: AudioCueID
    public let engaged: AudioCueID
    public let resistance: AudioCueID

    public init(
        waiting: AudioCueID,
        engaged: AudioCueID,
        resistance: AudioCueID
    ) {
        self.waiting = waiting
        self.engaged = engaged
        self.resistance = resistance
    }

    public func cueID(for phase: ResponsiveInteractionAudioPhase) -> AudioCueID {
        switch phase {
        case .waiting: waiting
        case .engaged: engaged
        case .resistance: resistance
        }
    }
}

/// One retained material player. The three phase-local cues must resolve to
/// this single offline asset and one shared sample geometry.
public struct ResponsiveAudioMaterialLayerSpec: Codable, Equatable, Sendable {
    public let id: ResponsiveAudioMaterialLayerID
    public let assetPath: String
    public let cueIDs: ResponsiveAudioPhaseCueIDs

    public init(
        id: ResponsiveAudioMaterialLayerID,
        assetPath: String,
        cueIDs: ResponsiveAudioPhaseCueIDs
    ) {
        self.id = id
        self.assetPath = assetPath
        self.cueIDs = cueIDs
    }
}

public struct ResponsiveAudioLayerGainSpec: Codable, Equatable, Sendable {
    public let layerID: ResponsiveAudioMaterialLayerID
    public let gain: Double

    public init(layerID: ResponsiveAudioMaterialLayerID, gain: Double) {
        self.layerID = layerID
        self.gain = gain
    }
}

/// One irreversible historical state, keyed only by the completed Transform
/// count supplied by JourneyDomain.
public struct ResponsiveAudioCausalMixStateSpec: Codable, Equatable, Sendable {
    public let completedStageCount: Int
    public let layerGains: [ResponsiveAudioLayerGainSpec]

    public init(
        completedStageCount: Int,
        layerGains: [ResponsiveAudioLayerGainSpec]
    ) {
        self.completedStageCount = completedStageCount
        self.layerGains = layerGains
    }
}

/// Optional common-player contract for Transform interactions. Existing
/// phase-only programs omit the field and retain their original wire shape.
public struct ResponsiveAudioCausalMixSpec: Codable, Equatable, Sendable {
    public let rampDurationSamples: Int64
    public let layers: [ResponsiveAudioMaterialLayerSpec]
    public let states: [ResponsiveAudioCausalMixStateSpec]

    public init(
        rampDurationSamples: Int64,
        layers: [ResponsiveAudioMaterialLayerSpec],
        states: [ResponsiveAudioCausalMixStateSpec]
    ) {
        self.rampDurationSamples = rampDurationSamples
        self.layers = layers
        self.states = states
    }

    public func state(
        forCompletedStageCount completedStageCount: Int
    ) -> ResponsiveAudioCausalMixStateSpec? {
        states.first { $0.completedStageCount == completedStageCount }
    }
}

/// Three finite authored regions form one user-paced program. The approach and
/// consequence play once. One of the phase beds loops indefinitely at their
/// shared sample position until the durable Journey commit arrives.
public struct ResponsiveAudioProgramSpec: Codable, Equatable, Identifiable, Sendable {
    public let id: ResponsiveAudioProgramID
    public let scope: ResponsiveAudioProgramScope
    public let approachTimelineID: AudioTimelineID
    public let interactionBeds: [ResponsiveInteractionAudioBedSpec]
    public let consequenceTimelineID: AudioTimelineID
    public let exitPolicy: ResponsiveAudioExitPolicy
    public let causalMix: ResponsiveAudioCausalMixSpec?

    public init(
        id: ResponsiveAudioProgramID,
        scope: ResponsiveAudioProgramScope,
        approachTimelineID: AudioTimelineID,
        interactionBeds: [ResponsiveInteractionAudioBedSpec],
        consequenceTimelineID: AudioTimelineID,
        exitPolicy: ResponsiveAudioExitPolicy,
        causalMix: ResponsiveAudioCausalMixSpec? = nil
    ) {
        self.id = id
        self.scope = scope
        self.approachTimelineID = approachTimelineID
        self.interactionBeds = interactionBeds
        self.consequenceTimelineID = consequenceTimelineID
        self.exitPolicy = exitPolicy
        self.causalMix = causalMix
    }

    public func interactionBed(
        for phase: ResponsiveInteractionAudioPhase
    ) -> ResponsiveInteractionAudioBedSpec? {
        interactionBeds.first { $0.phase == phase }
    }

    /// Binds an optional causal mix to the exact public interaction contract.
    /// Package validation calls this after resolving the full chapter scope;
    /// laboratories can use it directly before assembling a package.
    public func validateCausalMixBinding(to interaction: InteractionSpec) throws {
        guard let causalMix else { return }
        guard interaction.id == scope.interactionID,
              case let .transform(transform) = interaction.grammar else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.causalMix",
                reason: "requires the exact scoped Transform interaction"
            )
        }
        guard causalMix.states.count == transform.stages.count + 1 else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.causalMix.states",
                reason: "requires state zero plus exactly one state per Transform stage"
            )
        }
    }

    /// Validates the program against the exact offline timelines that will be
    /// available at runtime. Ambiguous references and implicit fallbacks fail.
    public func validate(timelines: [AudioTimeline]) throws {
        try requireNonempty(id, field: "responsiveAudioProgram.id")
        try scope.validate()
        try requireNonempty(
            approachTimelineID,
            field: "responsiveAudioProgram.approachTimelineID"
        )
        try requireNonempty(
            consequenceTimelineID,
            field: "responsiveAudioProgram.consequenceTimelineID"
        )

        let expectedPhases = Set(ResponsiveInteractionAudioPhase.allCases)
        let actualPhases = interactionBeds.map(\.phase)
        guard interactionBeds.count == expectedPhases.count,
              Set(actualPhases) == expectedPhases else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.interactionBeds",
                reason: "requires exactly one waiting, engaged and resistance bed"
            )
        }

        let referencedTimelineIDs = [approachTimelineID, consequenceTimelineID]
            + interactionBeds.map(\.timelineID)
        guard Set(referencedTimelineIDs).count == referencedTimelineIDs.count else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.timelineIDs",
                reason: "each program region requires its own authored timeline"
            )
        }

        let groupedTimelines = Dictionary(grouping: timelines, by: \.id)
        guard groupedTimelines.values.allSatisfy({ $0.count == 1 }) else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.timelines",
                reason: "timeline IDs must resolve unambiguously"
            )
        }
        let timelineByID = groupedTimelines.mapValues { $0[0] }
        for timelineID in referencedTimelineIDs {
            guard let timeline = timelineByID[timelineID] else {
                throw ContentValidationError.missingReference(
                    field: "responsiveAudioProgram.timelineIDs",
                    identifier: timelineID.rawValue
                )
            }
            try timeline.validate()
            guard timeline.authoredDurationSamples > 0 else {
                throw ContentValidationError.invalidValue(
                    field: "responsiveAudioProgram.timelineIDs",
                    reason: "timeline '\(timelineID)' must have a positive authored duration"
                )
            }
        }

        try exitPolicy.validate(field: "responsiveAudioProgram.exitPolicy")
        guard let consequenceTimeline = timelineByID[consequenceTimelineID],
              exitPolicy.boundedFadeDurationSamples
                <= consequenceTimeline.authoredDurationSamples else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.exitPolicy.durationSamples",
                reason: "must not exceed the full authored consequence timeline"
            )
        }

        var interactionDurations: Set<Int64> = []
        for bed in interactionBeds {
            try requireNonempty(
                bed.timelineID,
                field: "responsiveAudioProgram.interactionBeds.timelineID"
            )
            try bed.layerStates.validate(
                field: "responsiveAudioProgram.interactionBeds.\(bed.phase.rawValue).layerStates"
            )
            guard let timeline = timelineByID[bed.timelineID] else {
                // Every reference was resolved above. Keep this branch fail-closed
                // if the validation order is changed later.
                throw ContentValidationError.missingReference(
                    field: "responsiveAudioProgram.interactionBeds.timelineID",
                    identifier: bed.timelineID.rawValue
                )
            }
            guard !timeline.events.contains(where: { $0.role == .narration }) else {
                throw ContentValidationError.invalidValue(
                    field: "responsiveAudioProgram.interactionBeds.\(bed.phase.rawValue)",
                    reason: "an indefinite interaction bed cannot contain narration"
                )
            }
            guard timeline.haptics.isEmpty else {
                throw ContentValidationError.invalidValue(
                    field: "responsiveAudioProgram.interactionBeds.\(bed.phase.rawValue)",
                    reason: "looped beds cannot repeat authored haptics"
                )
            }
            guard timeline.events.allSatisfy({ event in
                event.role == .silence || event.durationSamples > 0
            }) else {
                throw ContentValidationError.invalidValue(
                    field: "responsiveAudioProgram.interactionBeds.\(bed.phase.rawValue)",
                    reason: "every audible loop event requires a positive duration"
                )
            }

            let hasScore = timeline.events.contains { $0.role == .score }
            let hasSoundscape = timeline.events.contains { $0.role == .soundscape }
            guard hasScore == (bed.layerStates.scoreStateID != nil),
                  hasSoundscape == (bed.layerStates.soundscapeStateID != nil) else {
                throw ContentValidationError.invalidValue(
                    field: "responsiveAudioProgram.interactionBeds.\(bed.phase.rawValue).layerStates",
                    reason: "named score and soundscape states must exactly match audible timeline roles"
                )
            }
            interactionDurations.insert(timeline.authoredDurationSamples)
        }
        guard interactionDurations.count == 1 else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.interactionBeds",
                reason: "all phase beds must share one sample-exact loop duration"
            )
        }
        guard let interactionDuration = interactionDurations.first,
              interactionDuration <= Int64(UInt32.max) else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.interactionBeds",
                reason: "the shared interaction loop must fit the native UInt32 frame boundary"
            )
        }
        if let causalMix {
            try validateCausalMix(
                causalMix,
                timelineByID: timelineByID,
                loopDuration: interactionDuration
            )
        }
    }

    private func validateCausalMix(
        _ mix: ResponsiveAudioCausalMixSpec,
        timelineByID: [AudioTimelineID: AudioTimeline],
        loopDuration: Int64
    ) throws {
        guard mix.rampDurationSamples > 0,
              mix.rampDurationSamples <= loopDuration,
              mix.rampDurationSamples <= Int64(UInt32.max) else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.causalMix.rampDurationSamples",
                reason: "must fit one deterministic audio-unit ramp and be no longer than the shared interaction loop"
            )
        }
        guard !mix.layers.isEmpty else {
            throw ContentValidationError.invalidCount(
                field: "responsiveAudioProgram.causalMix.layers",
                expected: "at least one",
                actual: 0
            )
        }
        try requireUnique(mix.layers.map(\.id))
        let layerOrder = mix.layers.map(\.id)
        for layer in mix.layers {
            try requireNonempty(layer.id, field: "responsiveAudioProgram.causalMix.layers.id")
            try requireSafePackageAssetPath(layer.assetPath)
            for phase in ResponsiveInteractionAudioPhase.allCases {
                try requireNonempty(
                    layer.cueIDs.cueID(for: phase),
                    field: "responsiveAudioProgram.causalMix.layers.cueIDs.\(phase.rawValue)"
                )
            }
        }
        for phase in ResponsiveInteractionAudioPhase.allCases {
            try requireUnique(mix.layers.map { $0.cueIDs.cueID(for: phase) })
        }

        guard !mix.states.isEmpty else {
            throw ContentValidationError.invalidCount(
                field: "responsiveAudioProgram.causalMix.states",
                expected: "at least state zero",
                actual: 0
            )
        }
        let expectedCounts = Array(0 ..< mix.states.count)
        guard mix.states.map(\.completedStageCount) == expectedCounts else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.causalMix.states.completedStageCount",
                reason: "states must be ordered and contiguous from zero"
            )
        }
        for state in mix.states {
            guard state.layerGains.map(\.layerID) == layerOrder else {
                throw ContentValidationError.invalidValue(
                    field: "responsiveAudioProgram.causalMix.states.layerGains",
                    reason: "every state must cover every layer exactly once in authored layer order"
                )
            }
            for target in state.layerGains {
                guard target.gain.isFinite, (0 ... 4).contains(target.gain) else {
                    throw ContentValidationError.invalidValue(
                        field: "responsiveAudioProgram.causalMix.states.layerGains.gain",
                        reason: "linear gain must be finite and between zero and four"
                    )
                }
            }
        }
        guard let initialState = mix.states.first else {
            throw ContentValidationError.invalidValue(
                field: "responsiveAudioProgram.causalMix.states",
                reason: "state zero is required"
            )
        }
        let initialGains = Dictionary(uniqueKeysWithValues: initialState.layerGains.map {
            ($0.layerID, $0.gain)
        })

        for layer in mix.layers {
            var sharedSignature: (AudioTrackRole, Int64, Int64, String)?
            for phase in ResponsiveInteractionAudioPhase.allCases {
                guard let bed = interactionBed(for: phase),
                      let timeline = timelineByID[bed.timelineID] else {
                    throw ContentValidationError.missingReference(
                        field: "responsiveAudioProgram.causalMix.layers.cueIDs",
                        identifier: phase.rawValue
                    )
                }
                let cueID = layer.cueIDs.cueID(for: phase)
                guard let event = timeline.events.first(where: { $0.cueID == cueID }) else {
                    throw ContentValidationError.missingReference(
                        field: "responsiveAudioProgram.causalMix.layers.cueIDs.\(phase.rawValue)",
                        identifier: cueID.rawValue
                    )
                }
                guard event.role == .soundscape || event.role == .spatialDetail,
                      event.assetPath == layer.assetPath,
                      event.gain == initialGains[layer.id] else {
                    throw ContentValidationError.invalidValue(
                        field: "responsiveAudioProgram.causalMix.layers.\(layer.id.rawValue)",
                        reason: "mapped cues must be material roles using the explicit shared asset path and state-zero gain"
                    )
                }
                let signature = (
                    event.role,
                    event.startSample,
                    event.durationSamples,
                    layer.assetPath
                )
                if let sharedSignature {
                    guard signature == sharedSignature else {
                        throw ContentValidationError.invalidValue(
                            field: "responsiveAudioProgram.causalMix.layers.\(layer.id.rawValue)",
                            reason: "all phase cues must share role, start, duration and asset path"
                        )
                    }
                } else {
                    sharedSignature = signature
                }
            }
            guard let sharedSignature,
                  sharedSignature.1 == 0,
                  sharedSignature.2 == loopDuration else {
                throw ContentValidationError.invalidValue(
                    field: "responsiveAudioProgram.causalMix.layers.\(layer.id.rawValue)",
                    reason: "shared material geometry must span the complete loop from sample zero"
                )
            }
        }
    }
}

public extension AudioTimeline {
    /// The final authored sample boundary, including explicit silence and
    /// haptics. AudioEvent positions are already bounded well below Int64.max.
    var authoredDurationSamples: Int64 {
        let eventEnd = events.reduce(Int64(0)) { current, event in
            max(current, event.startSample + event.durationSamples)
        }
        return haptics.reduce(eventEnd) { current, haptic in
            max(current, haptic.sample)
        }
    }
}
