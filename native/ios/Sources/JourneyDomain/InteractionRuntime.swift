import ContentKit
import Foundation

public enum InteractionPhase: String, Codable, Equatable, Sendable {
    case ready
    case active
    case complete
}

public struct TraceProgress: Codable, Equatable, Sendable {
    public var reachedAnchorCount: Int
    public var lastPoint: NormalizedPoint?

    public init(reachedAnchorCount: Int = 0, lastPoint: NormalizedPoint? = nil) {
        self.reachedAnchorCount = reachedAnchorCount
        self.lastPoint = lastPoint
    }
}

public struct AllocationValue: Codable, Equatable, Sendable {
    public let destinationID: String
    public var units: Int

    public init(destinationID: String, units: Int) {
        self.destinationID = destinationID
        self.units = units
    }
}

public struct AllocateProgress: Codable, Equatable, Sendable {
    public var allocations: [AllocationValue]

    public init(allocations: [AllocationValue]) {
        self.allocations = allocations.sorted { $0.destinationID < $1.destinationID }
    }
}

public struct AssemblyPlacement: Codable, Equatable, Sendable {
    public let componentID: String
    public let slotID: String

    public init(componentID: String, slotID: String) {
        self.componentID = componentID
        self.slotID = slotID
    }
}

public struct AssembleProgress: Codable, Equatable, Sendable {
    public var placements: [AssemblyPlacement]

    public init(placements: [AssemblyPlacement] = []) {
        self.placements = placements.sorted { $0.componentID < $1.componentID }
    }
}

public struct PressureValue: Codable, Equatable, Sendable {
    public let forceID: String
    public var magnitude: Double

    public init(forceID: String, magnitude: Double) {
        self.forceID = forceID
        self.magnitude = magnitude
    }
}

public struct PressureProgress: Codable, Equatable, Sendable {
    public var values: [PressureValue]
    public var stableMillis: Int64

    public init(values: [PressureValue], stableMillis: Int64 = 0) {
        self.values = values.sorted { $0.forceID < $1.forceID }
        self.stableMillis = stableMillis
    }
}

public struct TransformProgress: Codable, Equatable, Sendable {
    public var completedStageCount: Int
    public var currentAmount: Double

    public init(completedStageCount: Int = 0, currentAmount: Double = 0) {
        self.completedStageCount = completedStageCount
        self.currentAmount = currentAmount
    }
}

public enum InteractionProgress: Codable, Equatable, Sendable {
    case trace(TraceProgress)
    case allocate(AllocateProgress)
    case assemble(AssembleProgress)
    case pressure(PressureProgress)
    case transform(TransformProgress)
}

public struct InteractionRuntimeState: Codable, Equatable, Sendable {
    public let interactionID: InteractionID
    public var phase: InteractionPhase
    public var progress: InteractionProgress

    public init(spec: InteractionSpec) {
        interactionID = spec.id
        phase = .ready
        switch spec.grammar {
        case .trace:
            progress = .trace(TraceProgress())
        case let .allocate(configuration):
            progress = .allocate(
                AllocateProgress(
                    allocations: configuration.destinations.map {
                        AllocationValue(destinationID: $0.id, units: 0)
                    }
                )
            )
        case .assemble:
            progress = .assemble(AssembleProgress())
        case let .pressure(configuration):
            progress = .pressure(
                PressureProgress(
                    values: configuration.forces.map {
                        PressureValue(forceID: $0.id, magnitude: $0.initialMagnitude)
                    }
                )
            )
        case .transform:
            progress = .transform(TransformProgress())
        }
    }
}

public enum InteractionAction: Codable, Equatable, Sendable {
    case begin
    case trace(NormalizedPoint)
    case allocate(destinationID: String, units: Int)
    case commitAllocation
    case place(componentID: String, slotID: String)
    case setPressure(forceID: String, magnitude: Double)
    case advancePressure(elapsedMillis: Int64)
    case transform(controlID: String, amount: Double)
    case reset
}

public enum InteractionFeedback: String, Codable, Equatable, Sendable {
    case none
    /// A discrete authored bearing point was accepted without completing the
    /// interaction. Trace uses this for its origin and intermediate anchors;
    /// continuous movement remains `progress`.
    case contact
    case progress
    case resistance
    case threshold
    case completed
}

public struct InteractionReduction: Equatable, Sendable {
    public let feedback: InteractionFeedback
    public let completedEffects: [WorldEffect]

    public init(feedback: InteractionFeedback, completedEffects: [WorldEffect] = []) {
        self.feedback = feedback
        self.completedEffects = completedEffects
    }
}

public enum InteractionRuntimeError: Error, Equatable, Sendable {
    case mismatchedIdentifier
    case mismatchedGrammar
    case invalidAction
}

public enum InteractionReducer {
    public static func reduce(
        state: inout InteractionRuntimeState,
        spec: InteractionSpec,
        action: InteractionAction
    ) throws -> InteractionReduction {
        guard state.interactionID == spec.id else {
            throw InteractionRuntimeError.mismatchedIdentifier
        }

        guard state.phase != .complete else {
            return InteractionReduction(feedback: .none)
        }

        if action == .reset {
            // A Transform may clear work inside its current stage, but a
            // crossed historical threshold is irreversible. This keeps the
            // Journey authority monotonic for responsive audio and for the
            // visual world that later beats inherit.
            if case let .transform(progress) = state.progress {
                state.phase = progress.completedStageCount == 0 ? .ready : .active
                state.progress = .transform(
                    TransformProgress(
                        completedStageCount: progress.completedStageCount,
                        currentAmount: 0
                    )
                )
            } else {
                state = InteractionRuntimeState(spec: spec)
            }
            return InteractionReduction(feedback: .none)
        }

        if action == .begin {
            state.phase = .active
            return InteractionReduction(feedback: .progress)
        }
        if state.phase == .ready { state.phase = .active }

        let feedback: InteractionFeedback
        switch (spec.grammar, state.progress, action) {
        case let (.trace(configuration), .trace(progress), .trace(point)):
            var next = progress
            let nextAnchorIndex = next.reachedAnchorCount
            guard nextAnchorIndex < configuration.anchors.count else {
                throw InteractionRuntimeError.mismatchedGrammar
            }
            let nextAnchor = configuration.anchors[nextAnchorIndex]
            let reachedDirectly = point.distance(to: nextAnchor) <= configuration.tolerance
            let crossedBetweenAdmittedSamples = !reachedDirectly
                && traceSweepCrossesNextAnchor(
                    from: progress.lastPoint,
                    to: point,
                    nextAnchorIndex: nextAnchorIndex,
                    configuration: configuration
                )
            if reachedDirectly || crossedBetweenAdmittedSamples {
                next.reachedAnchorCount += 1
                // One admitted sample may cross one bearing point after input
                // coalescing. Canonicalising at that point preserves ordered
                // history and gives the following sample a valid new segment.
                next.lastPoint = nextAnchor
                feedback = .contact
            } else {
                next.lastPoint = point
                if next.reachedAnchorCount > 0,
                      isInsideTraceCorridor(
                          point,
                          from: configuration.anchors[next.reachedAnchorCount - 1],
                          to: configuration.anchors[next.reachedAnchorCount],
                          tolerance: configuration.tolerance
                      ) {
                    // Route movement is causal input even before the next named
                    // bearing point is reached. It updates the exact resumable
                    // position without advancing historical anchor authority.
                    feedback = .progress
                } else {
                    feedback = .resistance
                }
            }
            state.progress = .trace(next)
            if next.reachedAnchorCount == configuration.anchors.count {
                return complete(&state, effects: spec.completionEffects)
            }

        case let (.allocate(configuration), .allocate(progress), .allocate(destinationID, units)):
            guard units >= 0,
                  configuration.destinations.contains(where: { $0.id == destinationID }) else {
                return InteractionReduction(feedback: .resistance)
            }
            var next = progress
            guard let index = next.allocations.firstIndex(where: { $0.destinationID == destinationID }) else {
                throw InteractionRuntimeError.mismatchedGrammar
            }
            let otherUnits = next.allocations.enumerated().reduce(0) {
                $0 + ($1.offset == index ? 0 : $1.element.units)
            }
            guard otherUnits + units <= configuration.totalUnits else {
                return InteractionReduction(feedback: .resistance)
            }
            next.allocations[index].units = units
            state.progress = .allocate(next)
            feedback = .progress

        case let (.allocate(configuration), .allocate(progress), .commitAllocation):
            let allocatedUnits = progress.allocations.reduce(0) { $0 + $1.units }
            let matchesMinimums = configuration.destinations.allSatisfy { destination in
                (progress.allocations.first(where: {
                    $0.destinationID == destination.id
                })?.units ?? -1) >= destination.minimumUnits
            }
            if allocatedUnits == configuration.totalUnits, matchesMinimums {
                return complete(&state, effects: spec.completionEffects)
            }
            feedback = .resistance

        case let (.assemble(configuration), .assemble(progress), .place(componentID, slotID)):
            guard let component = configuration.components.first(where: { $0.id == componentID }),
                  component.targetSlot == slotID,
                  !progress.placements.contains(where: { $0.componentID == componentID }),
                  component.prerequisites.allSatisfy({ prerequisite in
                      progress.placements.contains(where: { $0.componentID == prerequisite })
                  }) else {
                return InteractionReduction(feedback: .resistance)
            }
            var next = progress
            next.placements.append(AssemblyPlacement(componentID: componentID, slotID: slotID))
            next.placements.sort { $0.componentID < $1.componentID }
            state.progress = .assemble(next)
            if next.placements.count == configuration.components.count {
                return complete(&state, effects: spec.completionEffects)
            }
            feedback = .progress

        case let (.pressure(configuration), .pressure(progress), .setPressure(forceID, magnitude)):
            guard let authoredForce = configuration.forces.first(where: { $0.id == forceID }),
                  authoredForce.userControllable,
                  (0 ... 1).contains(magnitude) else {
                return InteractionReduction(feedback: .resistance)
            }
            var next = progress
            guard let index = next.values.firstIndex(where: { $0.forceID == forceID }) else {
                throw InteractionRuntimeError.mismatchedGrammar
            }
            next.values[index].magnitude = magnitude
            let netPressure = configuration.forces.reduce(0.0) { partial, force in
                let currentMagnitude = next.values.first(where: {
                    $0.forceID == force.id
                })?.magnitude ?? 0
                return partial + force.direction * currentMagnitude
            }
            if !configuration.stableRange.contains(netPressure) {
                // Hold time is continuous evidence. Crossing outside the
                // authored stable range invalidates it at this input boundary,
                // even when the next periodic hold tick is coalesced later.
                next.stableMillis = 0
            }
            state.progress = .pressure(next)
            feedback = .progress

        case let (.pressure(configuration), .pressure(progress), .advancePressure(elapsedMillis)):
            guard elapsedMillis > 0, elapsedMillis <= 1_000 else {
                return InteractionReduction(feedback: .resistance)
            }
            var next = progress
            let netPressure = configuration.forces.reduce(0.0) { partial, force in
                let magnitude = next.values.first(where: { $0.forceID == force.id })?.magnitude ?? 0
                return partial + force.direction * magnitude
            }
            if configuration.stableRange.contains(netPressure) {
                next.stableMillis += elapsedMillis
                feedback = .threshold
            } else {
                next.stableMillis = 0
                feedback = .resistance
            }
            state.progress = .pressure(next)
            if next.stableMillis >= configuration.requiredHoldMillis {
                return complete(&state, effects: spec.completionEffects)
            }

        case let (.transform(configuration), .transform(progress), .transform(controlID, amount)):
            guard progress.completedStageCount < configuration.stages.count,
                  (0 ... 1).contains(amount) else {
                return InteractionReduction(feedback: .resistance)
            }
            let stage = configuration.stages[progress.completedStageCount]
            guard stage.controlID == controlID else {
                return InteractionReduction(feedback: .resistance)
            }
            var next = progress
            next.currentAmount = max(next.currentAmount, amount)
            let crossedStageThreshold = next.currentAmount >= stage.requiredAmount
            if crossedStageThreshold {
                next.completedStageCount += 1
                next.currentAmount = 0
            }
            state.progress = .transform(next)
            if next.completedStageCount == configuration.stages.count {
                return complete(&state, effects: spec.completionEffects)
            }
            feedback = crossedStageThreshold ? .threshold : .progress

        default:
            throw InteractionRuntimeError.invalidAction
        }

        return InteractionReduction(feedback: feedback)
    }

    private static func traceSweepCrossesNextAnchor(
        from previousPoint: NormalizedPoint?,
        to point: NormalizedPoint,
        nextAnchorIndex: Int,
        configuration: TraceInteractionSpec
    ) -> Bool {
        guard nextAnchorIndex > 0,
              let previousPoint else {
            // The authored origin must be contacted directly.
            return false
        }
        let inboundStart = configuration.anchors[nextAnchorIndex - 1]
        let anchor = configuration.anchors[nextAnchorIndex]
        let tolerance = configuration.tolerance
        guard isInsideTraceCorridor(
            previousPoint,
            from: inboundStart,
            to: anchor,
            tolerance: tolerance
        ),
        let crossingProjection = traceProjection(
            anchor,
            from: previousPoint,
            to: point
        ),
        crossingProjection > 0,
        crossingProjection <= 1,
        distance(
            from: anchor,
            toSegmentFrom: previousPoint,
            to: point
        ) <= tolerance else {
            return false
        }
        // Input coalescing may deliver a point after the route has already
        // crossed this bearing, including when the authored path turns here.
        // Crossing grants this anchor only. The canonical anchor then becomes
        // the authority from which the following sample may progress or resist.
        return true
    }

    private static func isInsideTraceCorridor(
        _ point: NormalizedPoint,
        from start: NormalizedPoint,
        to end: NormalizedPoint,
        tolerance: Double
    ) -> Bool {
        distance(from: point, toSegmentFrom: start, to: end) <= tolerance
    }

    private static func traceProjection(
        _ point: NormalizedPoint,
        from start: NormalizedPoint,
        to end: NormalizedPoint
    ) -> Double? {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        guard lengthSquared > 0 else { return nil }
        return (
            (point.x - start.x) * deltaX
                + (point.y - start.y) * deltaY
        ) / lengthSquared
    }

    private static func distance(
        from point: NormalizedPoint,
        toSegmentFrom start: NormalizedPoint,
        to end: NormalizedPoint
    ) -> Double {
        guard let rawProjection = traceProjection(point, from: start, to: end) else {
            return point.distance(to: start)
        }
        let projection = min(max(rawProjection, 0), 1)
        let nearest = NormalizedPoint(
            x: start.x + projection * (end.x - start.x),
            y: start.y + projection * (end.y - start.y)
        )
        return point.distance(to: nearest)
    }

    private static func complete(
        _ state: inout InteractionRuntimeState,
        effects: [WorldEffect]
    ) -> InteractionReduction {
        state.phase = .complete
        return InteractionReduction(feedback: .completed, completedEffects: effects)
    }
}
