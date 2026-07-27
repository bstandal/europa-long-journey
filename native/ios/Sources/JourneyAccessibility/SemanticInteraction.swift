import ContentKit
import Foundation
import JourneyDomain

public enum SemanticControlKind: String, Codable, Equatable, Sendable {
    case action
    case adjustable
    case status
}

public struct SemanticControl: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: SemanticControlKind
    public let label: String
    public let value: String?
    public let hint: String?
    public let actions: [AccessibilityActionSpec]

    public init(
        id: String,
        kind: SemanticControlKind,
        label: String,
        value: String? = nil,
        hint: String? = nil,
        actions: [AccessibilityActionSpec]
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.value = value
        self.hint = hint
        self.actions = actions
    }

    public var availableActions: [AccessibilityActionKind] {
        actions.map(\.kind)
    }
}

public struct SemanticInteractionModel: Codable, Equatable, Sendable {
    public let label: String
    public let controls: [SemanticControl]

    public init(label: String, controls: [SemanticControl]) {
        self.label = label
        self.controls = controls
    }
}

public enum SemanticInteractionError: Error, Equatable, Sendable {
    case mismatchedAccessibilityID
    case mismatchedInteractionState
    case unknownElement(String)
    case unauthoredAction(String)
    case actionUnavailable(String)
    case unboundAction(String)
    case inaccessibleCompletion(String)
    case divergentConsequence
}

public struct AccessibilityParityResult: Equatable, Sendable {
    public let standardEffects: [WorldEffect]
    public let voiceOverEffects: [WorldEffect]

    public init(standardEffects: [WorldEffect], voiceOverEffects: [WorldEffect]) {
        self.standardEffects = standardEffects
        self.voiceOverEffects = voiceOverEffects
    }
}

/// Builds the runtime VoiceOver model from authored AccessibilitySpec data and
/// translates its typed actions into the exact InteractionAction values used
/// by touch input. No parallel accessibility reducer exists.
public enum SemanticInteractionAdapter {
    public static func model(
        for spec: InteractionSpec,
        accessibility: AccessibilitySpec,
        state: InteractionRuntimeState
    ) throws -> SemanticInteractionModel {
        try requireMatching(spec: spec, accessibility: accessibility, state: state)
        let controls = accessibility.elements.compactMap { element -> SemanticControl? in
            let available = element.actions.filter {
                (try? interactionAction(for: $0, spec: spec, state: state)) != nil
            }
            let isOperable = element.role == .action || element.role == .adjustable
            if isOperable, available.isEmpty { return nil }
            return SemanticControl(
                id: element.id,
                kind: semanticKind(for: element.role),
                label: element.label.launchEnglish,
                value: dynamicValue(for: element, spec: spec, state: state)
                    ?? element.value?.launchEnglish,
                hint: element.hint?.launchEnglish,
                actions: available
            )
        }
        return SemanticInteractionModel(
            label: accessibility.sceneSummary.launchEnglish,
            controls: controls
        )
    }

    public static func action(
        for elementID: String,
        authoredAction: AccessibilityActionSpec,
        spec: InteractionSpec,
        accessibility: AccessibilitySpec,
        state: InteractionRuntimeState
    ) throws -> InteractionAction {
        try requireMatching(spec: spec, accessibility: accessibility, state: state)
        guard let element = accessibility.elements.first(where: { $0.id == elementID }) else {
            throw SemanticInteractionError.unknownElement(elementID)
        }
        guard element.actions.contains(authoredAction) else {
            throw SemanticInteractionError.unauthoredAction(elementID)
        }
        return try interactionAction(for: authoredAction, spec: spec, state: state)
    }

    @discardableResult
    public static func reduce(
        state: inout InteractionRuntimeState,
        elementID: String,
        authoredAction: AccessibilityActionSpec,
        spec: InteractionSpec,
        accessibility: AccessibilitySpec
    ) throws -> InteractionReduction {
        let reducerAction = try action(
            for: elementID,
            authoredAction: authoredAction,
            spec: spec,
            accessibility: accessibility,
            state: state
        )
        return try InteractionReducer.reduce(state: &state, spec: spec, action: reducerAction)
    }

    /// Simulates the canonical touch path and the complete authored VoiceOver
    /// path through the same deterministic reducer, then compares the exact
    /// persistent world effects. The package compiler mirrors this gate for
    /// every shipping interaction.
    public static func verifyParity(
        spec: InteractionSpec,
        accessibility: AccessibilitySpec
    ) throws -> AccessibilityParityResult {
        try spec.validate()
        try accessibility.validate()
        try accessibility.validateBinding(to: spec)

        let pressureTarget = try accessiblePressureTarget(spec: spec, accessibility: accessibility)
        let standard = try simulateStandard(spec: spec, pressureTarget: pressureTarget)
        let voiceOver = try simulateVoiceOver(
            spec: spec,
            accessibility: accessibility,
            pressureTarget: pressureTarget
        )
        guard standard == spec.completionEffects,
              voiceOver == spec.completionEffects,
              standard == voiceOver else {
            throw SemanticInteractionError.divergentConsequence
        }
        return AccessibilityParityResult(
            standardEffects: standard,
            voiceOverEffects: voiceOver
        )
    }

    private static func requireMatching(
        spec: InteractionSpec,
        accessibility: AccessibilitySpec,
        state: InteractionRuntimeState
    ) throws {
        guard accessibility.id == spec.accessibilityID else {
            throw SemanticInteractionError.mismatchedAccessibilityID
        }
        guard state.interactionID == spec.id else {
            throw SemanticInteractionError.mismatchedInteractionState
        }
    }

    private static func semanticKind(for role: AccessibilityRole) -> SemanticControlKind {
        switch role {
        case .action: .action
        case .adjustable: .adjustable
        default: .status
        }
    }

    private static func interactionAction(
        for action: AccessibilityActionSpec,
        spec: InteractionSpec,
        state: InteractionRuntimeState
    ) throws -> InteractionAction {
        guard state.phase != .complete else {
            throw SemanticInteractionError.actionUnavailable("interaction-complete")
        }
        switch (spec.grammar, state.progress, action.kind, action.token) {
        case let (.trace(configuration), .trace(progress), .increment, .traceNext):
            guard progress.reachedAnchorCount < configuration.anchors.count else {
                throw SemanticInteractionError.actionUnavailable("trace-next")
            }
            return .trace(configuration.anchors[progress.reachedAnchorCount])

        case let (
            .allocate(configuration),
            .allocate(progress),
            kind,
            .allocate(destinationID, unitsPerStep)
        ) where kind == .increment || kind == .decrement:
            guard let current = progress.allocations.first(where: {
                $0.destinationID == destinationID
            })?.units else {
                throw SemanticInteractionError.unboundAction(destinationID)
            }
            let delta = kind == .increment ? unitsPerStep : -unitsPerStep
            let next = min(max(current + delta, 0), configuration.totalUnits)
            guard next != current else {
                throw SemanticInteractionError.actionUnavailable(destinationID)
            }
            return .allocate(destinationID: destinationID, units: next)

        case (.allocate, .allocate, .activate, .commitAllocation):
            return .commitAllocation

        case let (
            .assemble(configuration),
            .assemble(progress),
            .activate,
            .placeComponent(componentID)
        ):
            guard let component = configuration.components.first(where: { $0.id == componentID }),
                  !progress.placements.contains(where: { $0.componentID == componentID }) else {
                throw SemanticInteractionError.actionUnavailable(componentID)
            }
            // Keep every unplaced authored component operable. The shared
            // reducer, rather than the accessibility projection, owns its
            // prerequisite rule and returns the same resistance response as a
            // premature physical drop.
            return .place(componentID: componentID, slotID: component.targetSlot)

        case let (
            .pressure(configuration),
            .pressure(progress),
            kind,
            .adjustPressure(forceID, step)
        ) where kind == .increment || kind == .decrement:
            guard configuration.forces.contains(where: { $0.id == forceID && $0.userControllable }),
                  let current = progress.values.first(where: { $0.forceID == forceID })?.magnitude else {
                throw SemanticInteractionError.unboundAction(forceID)
            }
            let delta = kind == .increment ? step : -step
            let next = min(max(current + delta, 0), 1)
            guard abs(next - current) > 0.000_000_001 else {
                throw SemanticInteractionError.actionUnavailable(forceID)
            }
            return .setPressure(forceID: forceID, magnitude: next)

        case let (.pressure(configuration), .pressure(progress), .activate, .holdPressure):
            let remaining = max(configuration.requiredHoldMillis - progress.stableMillis, 1)
            return .advancePressure(elapsedMillis: min(remaining, 1_000))

        case let (
            .transform(configuration),
            .transform(progress),
            .increment,
            .advanceTransform(stageID, step)
        ):
            guard progress.completedStageCount < configuration.stages.count else {
                throw SemanticInteractionError.actionUnavailable(stageID)
            }
            let stage = configuration.stages[progress.completedStageCount]
            guard stage.id == stageID else {
                throw SemanticInteractionError.actionUnavailable(stageID)
            }
            return .transform(
                controlID: stage.controlID,
                amount: min(progress.currentAmount + step, 1)
            )

        default:
            throw SemanticInteractionError.unboundAction(String(describing: action.token))
        }
    }

    private static func dynamicValue(
        for element: AccessibilityElementSpec,
        spec: InteractionSpec,
        state: InteractionRuntimeState
    ) -> String? {
        guard let token = element.actions.first?.token else { return nil }
        switch (spec.grammar, state.progress, token) {
        case let (.trace(configuration), .trace(progress), .traceNext):
            return "\(progress.reachedAnchorCount) of \(configuration.anchors.count) route points reached"
        case let (.allocate(configuration), .allocate(progress), .allocate(destinationID, _)):
            let units = progress.allocations.first { $0.destinationID == destinationID }?.units ?? 0
            return "\(units) \(configuration.resourceName)"
        case let (
            .assemble(configuration),
            .assemble(progress),
            .placeComponent(componentID)
        ):
            if progress.placements.contains(where: { $0.componentID == componentID }) {
                return "Placed"
            }
            guard let component = configuration.components.first(where: {
                $0.id == componentID
            }) else { return nil }
            return component.prerequisites.allSatisfy { prerequisite in
                progress.placements.contains(where: {
                    $0.componentID == prerequisite
                })
            } ? "Ready" : "Waiting"
        case let (.pressure, .pressure(progress), .adjustPressure(forceID, _)):
            let magnitude = progress.values.first { $0.forceID == forceID }?.magnitude ?? 0
            return "\(Int((magnitude * 100).rounded())) percent"
        case let (.pressure(configuration), .pressure(progress), .holdPressure):
            return "\(progress.stableMillis) of \(configuration.requiredHoldMillis) milliseconds held"
        case let (
            .transform(configuration),
            .transform(progress),
            .advanceTransform(stageID, _)
        ):
            guard let stageIndex = configuration.stages.firstIndex(where: {
                $0.id == stageID
            }) else { return nil }
            if stageIndex < progress.completedStageCount {
                return "Complete"
            }
            if stageIndex == progress.completedStageCount {
                return "\(Int((progress.currentAmount * 100).rounded())) percent"
            }
            return "Waiting"
        default:
            return nil
        }
    }

    private static func authoredAction(
        in accessibility: AccessibilitySpec,
        kind: AccessibilityActionKind,
        tokenMatches: (AccessibilityActionToken) -> Bool
    ) throws -> (elementID: String, action: AccessibilityActionSpec) {
        let matches = accessibility.elements.flatMap { element in
            element.actions.compactMap { action in
                action.kind == kind && tokenMatches(action.token)
                    ? (element.id, action) : nil
            }
        }
        guard matches.count == 1, let match = matches.first else {
            throw SemanticInteractionError.inaccessibleCompletion("missing-or-ambiguous-action")
        }
        return match
    }

    private static func applyStandard(
        _ action: InteractionAction,
        spec: InteractionSpec,
        state: inout InteractionRuntimeState,
        completedEffects: inout [WorldEffect]
    ) throws {
        let result = try InteractionReducer.reduce(state: &state, spec: spec, action: action)
        if !result.completedEffects.isEmpty { completedEffects = result.completedEffects }
    }

    private static func applyVoiceOver(
        _ binding: (elementID: String, action: AccessibilityActionSpec),
        spec: InteractionSpec,
        accessibility: AccessibilitySpec,
        state: inout InteractionRuntimeState,
        completedEffects: inout [WorldEffect]
    ) throws {
        let result = try reduce(
            state: &state,
            elementID: binding.elementID,
            authoredAction: binding.action,
            spec: spec,
            accessibility: accessibility
        )
        if !result.completedEffects.isEmpty { completedEffects = result.completedEffects }
    }

    private static func simulateStandard(
        spec: InteractionSpec,
        pressureTarget: [String: Double]?
    ) throws -> [WorldEffect] {
        var state = InteractionRuntimeState(spec: spec)
        var completedEffects: [WorldEffect] = []
        switch spec.grammar {
        case let .trace(configuration):
            for anchor in configuration.anchors {
                try applyStandard(.trace(anchor), spec: spec, state: &state, completedEffects: &completedEffects)
            }
        case let .allocate(configuration):
            let minimumTotal = configuration.destinations.reduce(0) {
                $0 + $1.minimumUnits
            }
            let surplus = configuration.totalUnits - minimumTotal
            for (index, destination) in configuration.destinations.enumerated() {
                try applyStandard(
                    .allocate(
                        destinationID: destination.id,
                        units: destination.minimumUnits + (index == 0 ? surplus : 0)
                    ),
                    spec: spec,
                    state: &state,
                    completedEffects: &completedEffects
                )
            }
            try applyStandard(.commitAllocation, spec: spec, state: &state, completedEffects: &completedEffects)
        case let .assemble(configuration):
            var remaining = configuration.components
            while !remaining.isEmpty {
                guard let component = remaining.first(where: { candidate in
                    candidate.prerequisites.allSatisfy { prerequisite in
                        guard case let .assemble(progress) = state.progress else { return false }
                        return progress.placements.contains { $0.componentID == prerequisite }
                    }
                }) else {
                    throw SemanticInteractionError.inaccessibleCompletion("assemble")
                }
                try applyStandard(
                    .place(componentID: component.id, slotID: component.targetSlot),
                    spec: spec,
                    state: &state,
                    completedEffects: &completedEffects
                )
                remaining.removeAll { $0.id == component.id }
            }
        case let .pressure(configuration):
            guard let pressureTarget else {
                throw SemanticInteractionError.inaccessibleCompletion("pressure")
            }
            for force in configuration.forces where force.userControllable {
                guard let magnitude = pressureTarget[force.id] else {
                    throw SemanticInteractionError.inaccessibleCompletion("pressure-\(force.id)")
                }
                try applyStandard(
                    .setPressure(forceID: force.id, magnitude: magnitude),
                    spec: spec,
                    state: &state,
                    completedEffects: &completedEffects
                )
            }
            while state.phase != .complete {
                guard case let .pressure(progress) = state.progress else {
                    throw SemanticInteractionError.inaccessibleCompletion("pressure")
                }
                let remaining = max(configuration.requiredHoldMillis - progress.stableMillis, 1)
                try applyStandard(
                    .advancePressure(elapsedMillis: min(remaining, 1_000)),
                    spec: spec,
                    state: &state,
                    completedEffects: &completedEffects
                )
            }
        case let .transform(configuration):
            for stage in configuration.stages {
                try applyStandard(
                    .transform(controlID: stage.controlID, amount: stage.requiredAmount),
                    spec: spec,
                    state: &state,
                    completedEffects: &completedEffects
                )
            }
        }
        guard state.phase == .complete else {
            throw SemanticInteractionError.inaccessibleCompletion("standard")
        }
        return completedEffects
    }

    private static func simulateVoiceOver(
        spec: InteractionSpec,
        accessibility: AccessibilitySpec,
        pressureTarget: [String: Double]?
    ) throws -> [WorldEffect] {
        var state = InteractionRuntimeState(spec: spec)
        var completedEffects: [WorldEffect] = []
        var operationCount = 0

        func apply(_ binding: (elementID: String, action: AccessibilityActionSpec)) throws {
            operationCount += 1
            guard operationCount <= 100_000 else {
                throw SemanticInteractionError.inaccessibleCompletion("operation-limit")
            }
            try applyVoiceOver(
                binding,
                spec: spec,
                accessibility: accessibility,
                state: &state,
                completedEffects: &completedEffects
            )
        }

        switch spec.grammar {
        case let .trace(configuration):
            let next = try authoredAction(in: accessibility, kind: .increment) {
                if case .traceNext = $0 { return true }
                return false
            }
            for _ in configuration.anchors { try apply(next) }

        case let .allocate(configuration):
            let minimumTotal = configuration.destinations.reduce(0) {
                $0 + $1.minimumUnits
            }
            let surplus = configuration.totalUnits - minimumTotal
            for (index, destination) in configuration.destinations.enumerated() {
                let increment = try authoredAction(in: accessibility, kind: .increment) {
                    if case let .allocate(destinationID, _) = $0 {
                        return destinationID == destination.id
                    }
                    return false
                }
                let targetUnits = destination.minimumUnits + (index == 0 ? surplus : 0)
                while case let .allocate(progress) = state.progress,
                      progress.allocations.first(where: { $0.destinationID == destination.id })?.units
                        != targetUnits {
                    try apply(increment)
                }
            }
            let commit = try authoredAction(in: accessibility, kind: .activate) {
                $0 == .commitAllocation
            }
            try apply(commit)

        case let .assemble(configuration):
            var remaining = Set(configuration.components.map(\.id))
            while !remaining.isEmpty {
                guard case let .assemble(progress) = state.progress,
                      let component = configuration.components.first(where: { candidate in
                          remaining.contains(candidate.id)
                              && candidate.prerequisites.allSatisfy { prerequisite in
                                  progress.placements.contains { $0.componentID == prerequisite }
                              }
                      }) else {
                    throw SemanticInteractionError.inaccessibleCompletion("assemble")
                }
                let place = try authoredAction(in: accessibility, kind: .activate) {
                    if case let .placeComponent(componentID) = $0 {
                        return componentID == component.id
                    }
                    return false
                }
                try apply(place)
                remaining.remove(component.id)
            }

        case let .pressure(configuration):
            guard let pressureTarget else {
                throw SemanticInteractionError.inaccessibleCompletion("pressure")
            }
            for force in configuration.forces where force.userControllable {
                guard let target = pressureTarget[force.id] else {
                    throw SemanticInteractionError.inaccessibleCompletion("pressure-\(force.id)")
                }
                while case let .pressure(progress) = state.progress,
                      let current = progress.values.first(where: { $0.forceID == force.id })?.magnitude,
                      abs(current - target) > 0.000_000_001 {
                    let kind: AccessibilityActionKind = current < target ? .increment : .decrement
                    let adjust = try authoredAction(in: accessibility, kind: kind) {
                        if case let .adjustPressure(forceID, _) = $0 { return forceID == force.id }
                        return false
                    }
                    try apply(adjust)
                }
            }
            let hold = try authoredAction(in: accessibility, kind: .activate) {
                $0 == .holdPressure
            }
            while state.phase != .complete { try apply(hold) }

        case let .transform(configuration):
            for stage in configuration.stages {
                let advance = try authoredAction(in: accessibility, kind: .increment) {
                    if case let .advanceTransform(stageID, _) = $0 { return stageID == stage.id }
                    return false
                }
                while case let .transform(progress) = state.progress,
                      progress.completedStageCount < configuration.stages.count,
                      configuration.stages[progress.completedStageCount].id == stage.id {
                    try apply(advance)
                }
            }
        }
        guard state.phase == .complete else {
            throw SemanticInteractionError.inaccessibleCompletion("voiceover")
        }
        return completedEffects
    }

    private static func accessiblePressureTarget(
        spec: InteractionSpec,
        accessibility: AccessibilitySpec
    ) throws -> [String: Double]? {
        guard case let .pressure(configuration) = spec.grammar else { return nil }
        struct CandidateForce {
            let id: String
            let direction: Double
            let values: [Double]
        }

        let fixed = configuration.forces.filter { !$0.userControllable }.reduce(0.0) {
            $0 + $1.direction * $1.initialMagnitude
        }
        let candidates: [CandidateForce] = try configuration.forces
            .filter(\.userControllable)
            .map { force in
                let increment = try authoredAction(in: accessibility, kind: .increment) {
                    if case let .adjustPressure(forceID, _) = $0 { return forceID == force.id }
                    return false
                }
                guard case let .adjustPressure(_, step) = increment.action.token else {
                    throw SemanticInteractionError.unboundAction(force.id)
                }
                var reachable: Set<Double> = [rounded(force.initialMagnitude)]
                var value = force.initialMagnitude
                while value < 1 - 0.000_000_001 {
                    value = min(value + step, 1)
                    reachable.insert(rounded(value))
                }
                value = force.initialMagnitude
                while value > 0.000_000_001 {
                    value = max(value - step, 0)
                    reachable.insert(rounded(value))
                }
                return CandidateForce(
                    id: force.id,
                    direction: force.direction,
                    values: reachable.sorted {
                        abs($0 - force.initialMagnitude) < abs($1 - force.initialMagnitude)
                    }
                )
            }

        var suffixMinimum = Array(repeating: 0.0, count: candidates.count + 1)
        var suffixMaximum = Array(repeating: 0.0, count: candidates.count + 1)
        if !candidates.isEmpty {
            for index in stride(from: candidates.count - 1, through: 0, by: -1) {
                let contributions = candidates[index].values.map { candidates[index].direction * $0 }
                suffixMinimum[index] = suffixMinimum[index + 1] + (contributions.min() ?? 0)
                suffixMaximum[index] = suffixMaximum[index + 1] + (contributions.max() ?? 0)
            }
        }

        var result: [String: Double] = [:]
        var visited = 0
        func search(index: Int, net: Double) -> Bool {
            visited += 1
            if visited > 200_000 { return false }
            if net + suffixMaximum[index] < configuration.stableRange.lowerBound - 0.000_000_001
                || net + suffixMinimum[index] > configuration.stableRange.upperBound + 0.000_000_001 {
                return false
            }
            if index == candidates.count {
                return configuration.stableRange.contains(net)
                    || abs(net - configuration.stableRange.lowerBound) < 0.000_000_001
                    || abs(net - configuration.stableRange.upperBound) < 0.000_000_001
            }
            let force = candidates[index]
            for value in force.values {
                result[force.id] = value
                if search(index: index + 1, net: net + force.direction * value) { return true }
            }
            result.removeValue(forKey: force.id)
            return false
        }
        guard search(index: 0, net: fixed) else {
            throw SemanticInteractionError.inaccessibleCompletion("pressure-discrete-range")
        }
        return result
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1_000_000_000).rounded() / 1_000_000_000
    }
}
