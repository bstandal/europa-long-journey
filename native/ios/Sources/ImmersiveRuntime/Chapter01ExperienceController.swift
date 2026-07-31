import ContentKit
import Foundation
import JourneyDomain
import SwiftUI

public enum Chapter01AssistanceTier: Int, Codable, Comparable, Sendable {
    case baseline
    case intensified
    case shortCue
    case expandedContact
    case semanticStep

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    fileprivate init(_ tier: AdaptiveAssistanceTier) {
        switch tier {
        case .diegetic:
            self = .baseline
        case .strengthenedDiegetic:
            self = .intensified
        case .actionCue:
            self = .shortCue
        case .stabilizedInput:
            self = .expandedContact
        case .semanticStep:
            self = .semanticStep
        }
    }
}

public enum Chapter01SensoryEvent: String, CaseIterable, Sendable {
    case contact
    case resistance
    case transfer
    case threshold
    case seal
    case transition
}

public struct Chapter01DurableState: Codable, Equatable, Sendable {
    public static let formatVersion = 3
    public static let deterministicSeed: UInt64 = 0x4649_5253_5446_4152

    public var formatVersion: Int
    public var experience: ExperienceRuntimeState
    public var interactions: [String: InteractionRuntimeState]
    public var completedEffectIDs: [String]
    /// Millisecond cursor in the approved 13:35 director timeline. Time only
    /// advances while the player is actively carrying the current action.
    public var authoredCursorMillis: Int64
    /// At most eight seconds of authored movement may continue after the last
    /// purposeful contact. This prevents passive stretches while preserving a
    /// fluid hold/drag interaction.
    public var engagementBudgetMillis: Int64
    public var beatActionSatisfied: Bool
    /// The renderer is a projection of this durable carrier transition. The
    /// target beat is committed only after all sixteen transition ticks land.
    public var pendingBeatID: String?

    /// Compatibility projection for the first immersive review surface. The
    /// persisted authority is `experience.beatID`, not a renderer array index.
    public var beatIndex: Int {
        get {
            Chapter01ExperienceScript.beats.firstIndex {
                $0.id == experience.beatID.rawValue
            } ?? 0
        }
        set {
            let bounded = min(
                max(newValue, 0),
                Chapter01ExperienceScript.beats.count - 1
            )
            let beat = Chapter01ExperienceScript.beats[bounded]
            experience.beatID = BeatID(beat.id)
            experience.worldCellID = beat.cell.rawValue
            experience.camera = ExperienceCameraState(
                trackID: "camera-\(beat.id)",
                progress: experience.camera.progress
            )
        }
    }

    /// Compatibility projection for callers already using the controller's
    /// first review API. `experience.sequenceID` remains the durable source.
    public var sequence: Chapter01Sequence {
        get {
            Chapter01Sequence.allCases.first {
                Self.sequenceID(for: $0) == experience.sequenceID
            } ?? .keepTheFutureAlive
        }
        set {
            experience.sequenceID = Self.sequenceID(for: newValue)
            experience.interactionStateReference = ExperienceInteractionStateReference(
                interactionID: InteractionID(newValue.interactionID)
            )
        }
    }

    public var assistanceTier: Chapter01AssistanceTier {
        get { Chapter01AssistanceTier(experience.assistance.tier) }
        set {
            experience.assistance = Self.makeAssistance(
                tier: newValue,
                missCount: experience.assistance.missCount
            )
        }
    }

    public var missCount: Int {
        get { experience.assistance.missCount }
        set {
            experience.assistance = Self.makeAssistance(
                tier: assistanceTier,
                missCount: max(newValue, 0)
            )
        }
    }

    public var narrationSampleCursor: Int64 {
        get { experience.sampleCursor }
        set { experience.sampleCursor = max(newValue, 0) }
    }

    public var deterministicTick: UInt64 {
        get { experience.deterministicTick }
        set { experience.deterministicTick = newValue }
    }

    public init(
        beatIndex: Int = 0,
        sequence: Chapter01Sequence = .keepTheFutureAlive,
        interactions: [String: InteractionRuntimeState] = [:],
        completedEffectIDs: [String] = [],
        assistanceTier: Chapter01AssistanceTier = .baseline,
        missCount: Int = 0,
        narrationSampleCursor: Int64 = 0,
        deterministicTick: UInt64 = 0,
        authoredCursorMillis: Int64? = nil,
        engagementBudgetMillis: Int64 = 0,
        beatActionSatisfied: Bool = false,
        pendingBeatID: String? = nil
    ) {
        formatVersion = Self.formatVersion
        let boundedBeatIndex = min(
            max(beatIndex, 0),
            Chapter01ExperienceScript.beats.count - 1
        )
        let requestedBeat = Chapter01ExperienceScript.beats[boundedBeatIndex]
        let sequenceBeat = requestedBeat.sequence == sequence
            ? requestedBeat
            : Chapter01ExperienceScript.beats[
                Chapter01ExperienceScript.firstBeatIndex(for: sequence)
            ]
        let assistance = Self.makeAssistance(
            tier: assistanceTier,
            missCount: max(missCount, 0)
        )
        experience = try! ExperienceRuntimeState(
            worldCellID: sequenceBeat.cell.rawValue,
            sequenceID: Self.sequenceID(for: sequence),
            beatID: BeatID(sequenceBeat.id),
            materialChannels: [
                StableMaterialChannelState(
                    channelID: "interaction-progress",
                    value: 0
                ),
            ],
            deterministicTick: deterministicTick,
            deterministicSeed: Self.deterministicSeed,
            camera: ExperienceCameraState(
                trackID: "camera-\(sequenceBeat.id)",
                progress: 0
            ),
            assistance: assistance,
            interactionStateReference: ExperienceInteractionStateReference(
                interactionID: InteractionID(sequence.interactionID)
            ),
            sampleCursor: max(narrationSampleCursor, 0)
        )
        self.interactions = interactions
        self.completedEffectIDs = completedEffectIDs
        self.authoredCursorMillis = authoredCursorMillis
            ?? Chapter01ExperienceScript.authoredStartMillis(
                forBeatAt: Chapter01ExperienceScript.beats.firstIndex(of: sequenceBeat)
                    ?? boundedBeatIndex
            )
        self.engagementBudgetMillis = max(engagementBudgetMillis, 0)
        self.beatActionSatisfied = beatActionSatisfied
        self.pendingBeatID = pendingBeatID
    }

    fileprivate static func sequenceID(for sequence: Chapter01Sequence) -> String {
        switch sequence {
        case .keepTheFutureAlive:
            "keep-the-future-alive"
        case .harvestHadToLast:
            "the-harvest-had-to-last"
        case .riverKnowsTheLanding:
            "the-river-knows-the-landing"
        case .houseOutlives:
            "the-house-outlives"
        case .moreMouthsMoreLand:
            "more-mouths-more-land"
        case .continentRemade:
            "a-continent-remade"
        }
    }

    private static func makeAssistance(
        tier: Chapter01AssistanceTier,
        missCount: Int
    ) -> AdaptiveAssistanceState {
        var state = AdaptiveAssistanceState()
        let requiredMisses: Int
        switch tier {
        case .shortCue:
            requiredMisses = max(
                missCount,
                AdaptiveAssistancePolicy.actionCueMinimumMissCount
            )
        default:
            requiredMisses = missCount
        }
        for _ in 0 ..< requiredMisses {
            _ = try? AdaptiveAssistancePolicy.reduce(
                state: &state,
                event: .missedAttempt
            )
        }

        let elapsed: Int64
        switch tier {
        case .baseline:
            elapsed = 0
        case .intensified:
            elapsed = AdaptiveAssistancePolicy.strengthenedDiegeticThresholdMillis
        case .shortCue:
            elapsed = AdaptiveAssistancePolicy.actionCueThresholdMillis
        case .expandedContact:
            elapsed = state.tier == .stabilizedInput
                ? 0
                : AdaptiveAssistancePolicy.stabilizedInputThresholdMillis
        case .semanticStep:
            elapsed = AdaptiveAssistancePolicy.semanticStepThresholdMillis
        }
        if elapsed > 0 {
            _ = try? AdaptiveAssistancePolicy.reduce(
                state: &state,
                event: .hesitationElapsed(elapsed)
            )
        }
        return state
    }
}

@MainActor
public final class Chapter01ExperienceController: ObservableObject {
    @Published public private(set) var state: Chapter01DurableState
    @Published public private(set) var transientManipulation: Double = 0
    @Published public private(set) var isTransitioning = false
    @Published public private(set) var sensoryEvent: Chapter01SensoryEvent?
    @Published public private(set) var sensoryEventGeneration: UInt64 = 0

    public let storageURL: URL

    private let reviewMetrics: Chapter01ReviewMetricsRecorder
    private var assistanceTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var manipulationTask: Task<Void, Never>?
    private var activeEntityName: String?
    private var activeManipulationStrength: Double = 0

    private static let directorTickMillis: Int64 = 250
    private static let directEngagementBudgetMillis: Int64 = 8_000

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        reviewMetrics = Chapter01ReviewMetricsRecorder(
            storageURL: self.storageURL
        )
        let restored = Self.restore(from: self.storageURL)
        if let restored {
            state = restored
        } else {
            state = Self.initialState()
        }
        normalizeRestoredState()
        isTransitioning = state.experience.transition != nil
        reviewMetrics.record(restored == nil ? "chapter-start" : "chapter-resume", state: state)
    }

    deinit {
        assistanceTask?.cancel()
        transitionTask?.cancel()
        manipulationTask?.cancel()
    }

    public var currentBeat: Chapter01Beat {
        Chapter01ExperienceScript.beats[
            min(max(state.beatIndex, 0), Chapter01ExperienceScript.beats.count - 1)
        ]
    }

    public var currentSequence: Chapter01Sequence { state.sequence }
    public var currentCell: Chapter01WorldCell { currentBeat.cell }
    public var chapterIsComplete: Bool {
        state.sequence == .continentRemade
            && runtime(for: .continentRemade).phase == .complete
            && state.completedEffectIDs.contains(
                Chapter01InteractionCatalog.continentRemade
                    .completionEffects[0].id.rawValue
            )
            && state.authoredCursorMillis
                >= Chapter01ExperienceScript.authoredDurationMillis
            && state.experience.transition == nil
    }

    public var normalizedExperienceProgress: Double {
        min(
            max(
                Double(state.authoredCursorMillis)
                    / Double(Chapter01ExperienceScript.authoredDurationMillis),
                0
            ),
            1
        )
    }

    public var currentBeatProgress: Double {
        let start = Chapter01ExperienceScript.authoredStartMillis(
            forBeatAt: state.beatIndex
        )
        let duration = Chapter01ExperienceScript.authoredDurationMillis(
            forBeatAt: state.beatIndex
        )
        return min(
            max(Double(state.authoredCursorMillis - start) / Double(duration), 0),
            1
        )
    }

    public var normalizedSequenceProgress: Double {
        let range = Chapter01ExperienceScript.authoredRangeMillis(
            for: state.sequence
        )
        let duration = max(range.upperBound - range.lowerBound, 1)
        return min(
            max(
                Double(state.authoredCursorMillis - range.lowerBound)
                    / Double(duration),
                0
            ),
            1
        )
    }

    public var actionCue: String? {
        assistanceDirective.actionCue?.text
    }

    public var contactScale: Double {
        assistanceDirective.hitTargetScale
    }

    public var semanticStepIsAvailable: Bool {
        assistanceDirective.offersSemanticStep
    }

    public var strengthensDiegeticSignals: Bool {
        assistanceDirective.strengthensDiegeticSignals
    }

    public var stabilizesInput: Bool {
        assistanceDirective.stabilizesInput
    }

    private var assistanceCue: AdaptiveAssistanceCue? {
        try? AdaptiveAssistanceCue(state.sequence.shortAction)
    }

    private var assistanceDirective: AdaptiveAssistanceDirective {
        AdaptiveAssistancePolicy.directive(
            for: state.experience.assistance,
            cue: assistanceCue
        )
    }

    public var normalizedInteractionProgress: Double {
        let spec = Chapter01InteractionCatalog.spec(for: state.sequence)
        let runtime = runtime(for: state.sequence)
        switch (runtime.progress, spec.grammar) {
        case let (.trace(progress), .trace(configuration)):
            return Double(progress.reachedAnchorCount)
                / Double(max(configuration.anchors.count, 1))
        case let (.allocate(progress), .allocate(configuration)):
            return Double(progress.allocations.reduce(0) { $0 + $1.units })
                / Double(max(configuration.totalUnits, 1))
        case let (.assemble(progress), .assemble(configuration)):
            return Double(progress.placements.count)
                / Double(max(configuration.components.count, 1))
        case let (.transform(progress), .transform(configuration)):
            let stageProgress = progress.currentAmount
            return (Double(progress.completedStageCount) + stageProgress)
                / Double(max(configuration.stages.count, 1))
        default:
            return 0
        }
    }

    public var allocationValues: [String: Int] {
        guard case let .allocate(progress) = runtime(for: .harvestHadToLast).progress else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: progress.allocations.map {
            ($0.destinationID, $0.units)
        })
    }

    public func start() {
        guard assistanceTask == nil else { return }
        if state.experience.transition != nil {
            scheduleTransitionAdvance()
        }
        assistanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .milliseconds(Self.directorTickMillis)
                )
                guard !Task.isCancelled else { return }
                self?.advanceDirectedExperience(
                    elapsedMillis: Self.directorTickMillis
                )
                self?.updateAssistance()
            }
        }
    }

    public func stop() {
        assistanceTask?.cancel()
        assistanceTask = nil
        transitionTask?.cancel()
        transitionTask = nil
        endContinuousManipulation()
        save()
        reviewMetrics.record("suspend", state: state)
    }

    public func updateNarrationSampleCursor(
        _ sample: Int64,
        forBeatID beatID: String? = nil
    ) {
        guard sample >= 0,
              beatID == nil || beatID == currentBeat.id,
              state.narrationSampleCursor != sample else { return }
        state.narrationSampleCursor = sample
        save()
    }

    public func updateTransientManipulation(_ value: Double) {
        transientManipulation = min(max(value, 0), 1)
    }

    public func cancelManipulation() {
        endContinuousManipulation()
        transientManipulation = 0
        registerMiss()
    }

    public func beginContinuousManipulation(
        entityName: String,
        strength: Double
    ) {
        guard !isTransitioning, !chapterIsComplete,
              state.sequence != .harvestHadToLast else { return }
        activeEntityName = entityName
        activeManipulationStrength = min(max(strength, 0.16), 1)
        transientManipulation = activeManipulationStrength
        if !state.beatActionSatisfied {
            activateEntity(named: entityName)
        } else {
            refreshPurposefulEngagement()
        }
        guard manipulationTask == nil else { return }
        manipulationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                if self.state.beatActionSatisfied {
                    self.refreshPurposefulEngagement()
                } else if let entityName = self.activeEntityName {
                    self.activateEntity(named: entityName)
                }
            }
        }
    }

    public func updateContinuousManipulation(strength: Double) {
        activeManipulationStrength = min(max(strength, 0.16), 1)
        transientManipulation = activeManipulationStrength
    }

    public func endContinuousManipulation() {
        manipulationTask?.cancel()
        manipulationTask = nil
        activeEntityName = nil
        activeManipulationStrength = 0
        transientManipulation = 0
    }

    /// Commits one direct manipulation. Repeated gestures expose changing
    /// resistance and advance the reducer's next semantic threshold; a render
    /// path cannot skip or manufacture completion.
    public func commitPrimaryManipulation(strength: Double) {
        guard !isTransitioning, !chapterIsComplete else { return }
        if runtime(for: state.sequence).phase == .complete {
            acceptPurposefulInput(event: .contact)
            save()
            return
        }
        let admitted = min(max(strength, 0), 1)
        guard admitted >= 0.16 else {
            transientManipulation = 0
            registerMiss()
            return
        }

        switch state.sequence {
        case .keepTheFutureAlive:
            advanceTrace()
        case .harvestHadToLast:
            // Directional grain transfer is handled separately.
            registerMiss()
        case .riverKnowsTheLanding, .moreMouthsMoreLand, .continentRemade:
            advanceTransform(strength: admitted)
        case .houseOutlives:
            placeNextHouseComponent()
        }
        transientManipulation = 0
    }

    public func transferGrain(to destinationID: String) {
        guard state.sequence == .harvestHadToLast, !isTransitioning else { return }
        let spec = Chapter01InteractionCatalog.harvestHadToLast
        var runtime = runtime(for: .harvestHadToLast)
        guard case let .allocate(progress) = runtime.progress,
              case let .allocate(configuration) = spec.grammar,
              let current = progress.allocations.first(where: {
                  $0.destinationID == destinationID
              })?.units,
              let maximum = InteractionReducer.maximumAllocatableUnits(
                  for: destinationID,
                  progress: progress,
                  configuration: configuration
              ), current < maximum else {
            registerMiss()
            return
        }
        let next = min(current + 2, maximum)
        apply(.allocate(destinationID: destinationID, units: next), to: spec, runtime: &runtime)
        if case let .allocate(updated) = runtime.progress,
           InteractionReducer.allocationCanCommit(
               progress: updated,
               configuration: configuration
           ) {
            apply(.commitAllocation, to: spec, runtime: &runtime)
        }
        state.interactions[spec.id.rawValue] = runtime
        acceptPurposefulInput(event: runtime.phase == .complete ? .seal : .transfer)
        synchronizeExperienceProjection(progress: normalizedInteractionProgress)
        if runtime.phase == .complete { commitCompletedEffects(spec: spec) }
        save()
    }

    public func activateEntity(named name: String) {
        guard !isTransitioning else { return }
        switch state.sequence {
        case .harvestHadToLast:
            if name.contains("food") { transferGrain(to: "food") }
            else if name.contains("reserve") { transferGrain(to: "reserve") }
            else if name.contains("seed") { transferGrain(to: "seed") }
            else { semanticStep() }
        case .houseOutlives:
            placeNextHouseComponent(preferredID: componentID(from: name))
        default:
            commitPrimaryManipulation(strength: activeManipulationStrength == 0
                ? 1
                : activeManipulationStrength)
        }
    }

    public func semanticStep() {
        guard !isTransitioning, !chapterIsComplete else { return }
        if runtime(for: state.sequence).phase == .complete {
            acceptPurposefulInput(event: .contact)
            grantSemanticBeatBudget()
            save()
            return
        }
        switch state.sequence {
        case .keepTheFutureAlive:
            advanceTrace()
        case .harvestHadToLast:
            transferNextRequiredGrain()
        case .riverKnowsTheLanding, .moreMouthsMoreLand, .continentRemade:
            advanceTransform(strength: 1)
        case .houseOutlives:
            placeNextHouseComponent()
        }
        if state.beatActionSatisfied {
            grantSemanticBeatBudget()
            save()
        }
    }

    public func resetReview() {
        transitionTask?.cancel()
        manipulationTask?.cancel()
        manipulationTask = nil
        state = Self.initialState()
        transientManipulation = 0
        isTransitioning = false
        save()
    }

#if DEBUG || NON_SHIPPING_LIVE_TEST
    /// Produces the editor's second simulator entry point exclusively through
    /// accepted reducer actions and durable carrier transitions.
    @discardableResult
    public func prepareNonShippingSpringResume() -> Bool {
        resetReview()
        var admittedMutations = 0
        while currentBeat.id != "spring-return",
              !chapterIsComplete,
              admittedMutations < 96 {
            if isTransitioning {
                _ = advanceTransitionByOneStep()
            } else {
                semanticStep()
                advanceDirectedExperience(elapsedMillis: 1_000_000)
            }
            admittedMutations += 1
        }
        stop()
        return currentBeat.id == "spring-return"
            && currentCell == .thessalianHousehold
    }
#endif

    private func advanceTrace() {
        let spec = Chapter01InteractionCatalog.householdCrosses
        var runtime = runtime(for: .keepTheFutureAlive)
        guard case let .trace(progress) = runtime.progress,
              case let .trace(configuration) = spec.grammar,
              progress.reachedAnchorCount < configuration.anchors.count else {
            return
        }
        apply(
            .trace(configuration.anchors[progress.reachedAnchorCount]),
            to: spec,
            runtime: &runtime
        )
        state.interactions[spec.id.rawValue] = runtime
        acceptPurposefulInput(event: runtime.phase == .complete ? .seal : .contact)
        synchronizeExperienceProjection(progress: normalizedInteractionProgress)
        if runtime.phase == .complete { commitCompletedEffects(spec: spec) }
        save()
    }

    private func advanceTransform(strength: Double) {
        let spec = Chapter01InteractionCatalog.spec(for: state.sequence)
        var runtime = runtime(for: state.sequence)
        guard case let .transform(progress) = runtime.progress,
              case let .transform(configuration) = spec.grammar,
              progress.completedStageCount < configuration.stages.count else {
            return
        }
        let stage = configuration.stages[progress.completedStageCount]
        let amount = max(stage.requiredAmount, strength)
        apply(.transform(controlID: stage.controlID, amount: amount), to: spec, runtime: &runtime)
        state.interactions[spec.id.rawValue] = runtime
        acceptPurposefulInput(event: runtime.phase == .complete ? .seal : .threshold)
        synchronizeExperienceProjection(progress: normalizedInteractionProgress)
        if runtime.phase == .complete { commitCompletedEffects(spec: spec) }
        save()
    }

    private func placeNextHouseComponent(preferredID: String? = nil) {
        let spec = Chapter01InteractionCatalog.houseOutlives
        var runtime = runtime(for: .houseOutlives)
        guard case let .assemble(progress) = runtime.progress,
              case let .assemble(configuration) = spec.grammar else { return }
        let placed = Set(progress.placements.map(\.componentID))
        let available = configuration.components.filter { component in
            !placed.contains(component.id)
                && component.prerequisites.allSatisfy(placed.contains)
        }
        guard let component = preferredID.flatMap({ preferred in
            available.first(where: { $0.id == preferred })
        }) ?? available.first else {
            registerMiss()
            return
        }
        apply(
            .place(componentID: component.id, slotID: component.targetSlot),
            to: spec,
            runtime: &runtime
        )
        state.interactions[spec.id.rawValue] = runtime
        acceptPurposefulInput(event: runtime.phase == .complete ? .seal : .contact)
        synchronizeExperienceProjection(progress: normalizedInteractionProgress)
        if runtime.phase == .complete { commitCompletedEffects(spec: spec) }
        save()
    }

    private func transferNextRequiredGrain() {
        let values = allocationValues
        let order: [(String, Int)] = [("food", 4), ("reserve", 2), ("seed", 3)]
        if let next = order.first(where: { values[$0.0, default: 0] < $0.1 }) {
            transferGrain(to: next.0)
            return
        }
        let total = values.values.reduce(0, +)
        let surplusOrder = ["reserve", "food", "seed"]
        if total < 12, let destination = surplusOrder.first {
            transferGrain(to: destination)
        }
    }

    private func apply(
        _ action: InteractionAction,
        to spec: InteractionSpec,
        runtime: inout InteractionRuntimeState
    ) {
        do {
            let reduction = try InteractionReducer.reduce(
                state: &runtime,
                spec: spec,
                action: action
            )
            if reduction.feedback == .resistance { registerMiss() }
        } catch {
            registerMiss()
        }
    }

    private func commitCompletedEffects(spec: InteractionSpec) {
        for effect in spec.completionEffects where
            !state.completedEffectIDs.contains(effect.id.rawValue) {
            state.completedEffectIDs.append(effect.id.rawValue)
        }
        state.completedEffectIDs.sort()
        synchronizeExperienceProjection(progress: 1)
        emit(.seal)
        save()
    }

    /// Advances the authored clock only while the current beat is supported by
    /// recent purposeful input. The clock is deterministic and is the sole
    /// authority for beat, camera and material projection.
    func advanceDirectedExperience(elapsedMillis: Int64) {
        guard elapsedMillis > 0,
              !isTransitioning,
              !chapterIsComplete,
              state.beatActionSatisfied,
              state.engagementBudgetMillis > 0 else { return }

        let beatEnd = Chapter01ExperienceScript.authoredEndMillis(
            forBeatAt: state.beatIndex
        )
        let untilBoundary = max(beatEnd - state.authoredCursorMillis, 0)
        let admitted = min(
            elapsedMillis,
            state.engagementBudgetMillis,
            untilBoundary
        )
        if admitted > 0 {
            state.authoredCursorMillis += admitted
            state.engagementBudgetMillis -= admitted
            state.deterministicTick &+= UInt64((admitted + 249) / 250)
            synchronizeExperienceProjection(progress: normalizedInteractionProgress)
            save()
        }

        if state.authoredCursorMillis >= beatEnd {
            finishCurrentBeatBoundary()
        } else if state.engagementBudgetMillis == 0 {
            state.beatActionSatisfied = false
            state.experience.assistance = AdaptiveAssistanceState()
            save()
        }
    }

    private func finishCurrentBeatBoundary() {
        let currentIndex = state.beatIndex
        let currentSequence = state.sequence
        let currentRuntime = runtime(for: currentSequence)

        if currentIndex == Chapter01ExperienceScript.beats.count - 1 {
            guard currentRuntime.phase == .complete else {
                resetBeatActionGate()
                return
            }
            commitCompletedEffects(
                spec: Chapter01InteractionCatalog.spec(for: currentSequence)
            )
            state.authoredCursorMillis = Chapter01ExperienceScript
                .authoredDurationMillis
            state.engagementBudgetMillis = 0
            state.beatActionSatisfied = true
            synchronizeExperienceProjection(progress: 1)
            save()
            reviewMetrics.record("chapter-complete", state: state)
            return
        }

        let nextIndex = currentIndex + 1
        let nextBeat = Chapter01ExperienceScript.beats[nextIndex]
        if nextBeat.sequence != currentSequence {
            guard currentRuntime.phase == .complete else {
                resetBeatActionGate()
                return
            }
            commitCompletedEffects(
                spec: Chapter01InteractionCatalog.spec(for: currentSequence)
            )
        }

        if nextBeat.cell != currentBeat.cell {
            beginTransition(toBeatAt: nextIndex)
        } else {
            advance(toBeatAt: nextIndex)
        }
    }

    private func resetBeatActionGate() {
        state.engagementBudgetMillis = 0
        state.beatActionSatisfied = false
        state.experience.assistance = AdaptiveAssistanceState()
        save()
    }

    private func beginTransition(toBeatAt nextIndex: Int) {
        let nextBeat = Chapter01ExperienceScript.beats[nextIndex]
        state.pendingBeatID = nextBeat.id
        state.experience.transition = transitionState(
            from: currentBeat,
            to: nextBeat
        )
        state.engagementBudgetMillis = 0
        state.beatActionSatisfied = false
        endContinuousManipulation()
        isTransitioning = true
        save()
        reviewMetrics.record("transition-begin", state: state)
        scheduleTransitionAdvance()
    }

    private func scheduleTransitionAdvance() {
        guard transitionTask == nil,
              state.experience.transition != nil,
              state.pendingBeatID != nil else { return }
        isTransitioning = true
        transitionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                if self.advanceTransitionByOneStep() {
                    return
                }
            }
        }
    }

    /// Transition progress is durable carrier state. Sixteen authored steps
    /// yield the same 3.2-second transition while allowing a hard-killed
    /// process to resume at the exact saved step rather than replaying it.
    func advanceTransitionStep() -> Bool {
        guard var transition = state.experience.transition else { return true }
        transition.progress = min(transition.progress + 0.0625, 1)
        state.experience.transition = transition
        state.deterministicTick &+= 1
        save()
        return transition.progress >= 1
    }

    @discardableResult
    func advanceTransitionByOneStep() -> Bool {
        guard advanceTransitionStep() else { return false }
        transitionTask?.cancel()
        transitionTask = nil
        completePendingTransition()
        return true
    }

    private func completePendingTransition() {
        guard let pendingBeatID = state.pendingBeatID,
              let nextIndex = Chapter01ExperienceScript.beats.firstIndex(where: {
                  $0.id == pendingBeatID
              }) else {
            state.experience.transition = nil
            state.pendingBeatID = nil
            isTransitioning = false
            save()
            return
        }
        state.experience.transition = nil
        state.pendingBeatID = nil
        advance(toBeatAt: nextIndex, emitTransition: true)
        isTransitioning = false
        reviewMetrics.record("transition-complete", state: state)
    }

    private func advance(
        toBeatAt nextIndex: Int,
        emitTransition: Bool = false
    ) {
        let nextBeat = Chapter01ExperienceScript.beats[nextIndex]
        let sequenceChanged = nextBeat.sequence != state.sequence
        state.sequence = nextBeat.sequence
        state.beatIndex = nextIndex
        state.authoredCursorMillis = Chapter01ExperienceScript
            .authoredStartMillis(forBeatAt: nextIndex)
        // The sample cursor is scoped to one locked narration beat. Reset at
        // every beat boundary so a completed or interrupted recording can
        // never leak into, seek, or replay under a later beat.
        state.narrationSampleCursor = 0
        state.engagementBudgetMillis = 0
        state.beatActionSatisfied = false
        state.experience.assistance = AdaptiveAssistanceState()
        state.deterministicTick &+= 1
        synchronizeExperienceProjection(progress: normalizedInteractionProgress)
        if emitTransition || sequenceChanged { emit(.transition) }
        save()
        reviewMetrics.record("beat-enter", state: state)
    }

    private func synchronizeExperienceProjection(progress: Double) {
        let boundedProgress = min(max(progress, 0), 1)
        state.experience.materialChannels = [
            StableMaterialChannelState(
                channelID: "beat-progress",
                value: currentBeatProgress
            ),
            StableMaterialChannelState(
                channelID: "chapter-progress",
                value: normalizedExperienceProgress
            ),
            StableMaterialChannelState(
                channelID: "interaction-progress",
                value: boundedProgress
            ),
        ]
        state.experience.camera.progress = normalizedSequenceProgress
        state.experience.interactionStateReference = ExperienceInteractionStateReference(
            interactionID: InteractionID(state.sequence.interactionID)
        )
    }

    private func transitionState(
        from current: Chapter01Beat,
        to next: Chapter01Beat
    ) -> ExperienceTransitionState {
        let carrierID: String
        switch (current.cell, next.cell) {
        case (.aegeanPassage, .thessalianHousehold):
            carrierID = "carrier-seed-vessel"
        case (.thessalianHousehold, .ironGates):
            carrierID = "carrier-spring-seed"
        case (.ironGates, .longhouseGround):
            carrierID = "carrier-landing-line"
        case (.longhouseGround, .settlementLandscape):
            carrierID = "carrier-load-line"
        default:
            carrierID = "carrier-field-edge"
        }
        return ExperienceTransitionState(
            transitionID: "transition-\(current.id)-to-\(next.id)",
            carrierID: carrierID,
            progress: 0
        )
    }

    private func runtime(for sequence: Chapter01Sequence) -> InteractionRuntimeState {
        let spec = Chapter01InteractionCatalog.spec(for: sequence)
        return state.interactions[spec.id.rawValue]
            ?? InteractionRuntimeState(spec: spec)
    }

    private func acceptPurposefulInput(event: Chapter01SensoryEvent) {
        _ = try? AdaptiveAssistancePolicy.reduce(
            state: &state.experience.assistance,
            event: .purposefulContact,
            cue: assistanceCue
        )
        state.beatActionSatisfied = true
        state.engagementBudgetMillis = max(
            state.engagementBudgetMillis,
            Self.directEngagementBudgetMillis
        )
        emit(event)
        reviewMetrics.record("purposeful-input", state: state)
    }

    private func refreshPurposefulEngagement() {
        guard !isTransitioning, !chapterIsComplete else { return }
        _ = try? AdaptiveAssistancePolicy.reduce(
            state: &state.experience.assistance,
            event: .purposefulContact,
            cue: assistanceCue
        )
        state.beatActionSatisfied = true
        state.engagementBudgetMillis = max(
            state.engagementBudgetMillis,
            Self.directEngagementBudgetMillis
        )
    }

    private func grantSemanticBeatBudget() {
        let remaining = max(
            Chapter01ExperienceScript.authoredEndMillis(
                forBeatAt: state.beatIndex
            ) - state.authoredCursorMillis,
            Self.directorTickMillis
        )
        state.engagementBudgetMillis = max(
            state.engagementBudgetMillis,
            remaining
        )
    }

    private func registerMiss() {
        _ = try? AdaptiveAssistancePolicy.reduce(
            state: &state.experience.assistance,
            event: .missedAttempt,
            cue: assistanceCue
        )
        emit(.resistance)
        save()
        reviewMetrics.record("miss", state: state)
    }

    private func updateAssistance() {
        guard !isTransitioning,
              !chapterIsComplete,
              !state.beatActionSatisfied else { return }
        let priorTier = state.experience.assistance.tier
        _ = try? AdaptiveAssistancePolicy.reduce(
            state: &state.experience.assistance,
            event: .hesitationElapsed(250),
            cue: assistanceCue
        )
        if state.experience.assistance.tier != priorTier {
            save()
            reviewMetrics.record("assistance-tier", state: state)
        }
    }

    private func emit(_ event: Chapter01SensoryEvent) {
        sensoryEvent = event
        sensoryEventGeneration &+= 1
    }

    private func componentID(from entityName: String) -> String? {
        ["posts", "hearth", "storage", "roof"].first(where: entityName.contains)
    }

    private func save() {
        do {
            let directory = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.canonical.encode(state)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Review runtime remains usable in memory. The caller can surface
            // persistence diagnostics without replacing the historical world.
        }
    }

    private func normalizeRestoredState() {
        let restoredSequence = Chapter01Sequence.allCases.first {
            Chapter01DurableState.sequenceID(for: $0)
                == state.experience.sequenceID
        }
        let restoredBeatIndex = Chapter01ExperienceScript.beats.firstIndex {
            $0.id == state.experience.beatID.rawValue
        }
        guard state.formatVersion == Chapter01DurableState.formatVersion,
              state.experience.isStructurallyValid,
              state.experience.deterministicSeed
                == Chapter01DurableState.deterministicSeed,
              let restoredSequence,
              let restoredBeatIndex,
              Chapter01ExperienceScript.beats[restoredBeatIndex].sequence
                == restoredSequence,
              Chapter01ExperienceScript.beats[restoredBeatIndex].cell.rawValue
                == state.experience.worldCellID,
              state.experience.interactionStateReference?.interactionID.rawValue
                == restoredSequence.interactionID,
              state.authoredCursorMillis
                >= Chapter01ExperienceScript.authoredStartMillis(
                    forBeatAt: restoredBeatIndex
                ),
              state.authoredCursorMillis
                <= Chapter01ExperienceScript.authoredEndMillis(
                    forBeatAt: restoredBeatIndex
                ),
              state.engagementBudgetMillis >= 0,
              (state.experience.transition == nil)
                == (state.pendingBeatID == nil) else {
            state = Self.initialState()
            save()
            return
        }
        for sequence in Chapter01Sequence.allCases {
            let spec = Chapter01InteractionCatalog.spec(for: sequence)
            if state.interactions[spec.id.rawValue] == nil {
                state.interactions[spec.id.rawValue] = InteractionRuntimeState(spec: spec)
            }
        }
        if let pendingBeatID = state.pendingBeatID {
            guard restoredBeatIndex + 1 < Chapter01ExperienceScript.beats.count,
                  Chapter01ExperienceScript.beats[restoredBeatIndex + 1].id
                    == pendingBeatID else {
                state = Self.initialState()
                save()
                return
            }
        }
        synchronizeExperienceProjection(progress: normalizedInteractionProgress)
        save()
    }

    private static func initialState() -> Chapter01DurableState {
        Chapter01DurableState(
            interactions: Dictionary(uniqueKeysWithValues:
                Chapter01Sequence.allCases.map { sequence in
                    let spec = Chapter01InteractionCatalog.spec(for: sequence)
                    return (spec.id.rawValue, InteractionRuntimeState(spec: spec))
                }
            )
        )
    }

    private static func restore(from url: URL) -> Chapter01DurableState? {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(Chapter01DurableState.self, from: data),
              state.formatVersion == Chapter01DurableState.formatVersion else {
            return nil
        }
        return state
    }

    private static func defaultStorageURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return root
            .appendingPathComponent("chapter01-immersive-v2", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }
}

private extension JSONEncoder {
    static var canonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
