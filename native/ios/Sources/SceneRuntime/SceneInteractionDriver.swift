import ContentKit
import CryptoKit
import Foundation
import JourneyDomain

/// The input path is recorded only until it reaches this boundary. Touch and
/// semantic controls must both resolve to the same `InteractionAction`; the
/// input path is deliberately excluded from the domain response and checkpoint.
public enum SceneInteractionInput: Codable, Equatable, Sendable {
    case touch(InteractionAction)
    case semantic(InteractionAction)

    public var domainAction: InteractionAction {
        switch self {
        case let .touch(action), let .semantic(action):
            action
        }
    }
}

public struct SceneTraceSnapshot: Codable, Equatable, Sendable {
    public let reachedAnchorCount: Int
    public let totalAnchorCount: Int
    public let lastPoint: NormalizedPoint?
}

public struct SceneAllocateSnapshot: Codable, Equatable, Sendable {
    public let resourceName: LocalizedStringSpec
    public let totalUnits: Int
    public let allocatedUnits: Int
    public let remainingUnits: Int
    public let allocations: [AllocationValue]
}

public struct SceneAssembleSnapshot: Codable, Equatable, Sendable {
    public let placements: [AssemblyPlacement]
    public let availableComponentIDs: [String]
    public let totalComponentCount: Int
}

public struct ScenePressureSnapshot: Codable, Equatable, Sendable {
    public let values: [PressureValue]
    public let netPressure: Double
    public let stableMillis: Int64
    public let requiredHoldMillis: Int64
}

public struct SceneTransformSnapshot: Codable, Equatable, Sendable {
    public let completedStageCount: Int
    public let totalStageCount: Int
    public let currentStageID: String?
    public let currentControlID: String?
    public let currentAmount: Double
}

/// A grammar-neutral envelope around the mechanism-specific state that visual,
/// audio and haptic adapters need. Arrays are canonicalised before they reach
/// this boundary, so identical reducer state produces byte-identical snapshots.
public enum SceneInteractionMechanismSnapshot: Codable, Equatable, Sendable {
    case trace(SceneTraceSnapshot)
    case allocate(SceneAllocateSnapshot)
    case assemble(SceneAssembleSnapshot)
    case pressure(ScenePressureSnapshot)
    case transform(SceneTransformSnapshot)
}

public struct SceneInteractionSnapshot: Codable, Equatable, Sendable {
    public let interactionID: InteractionID
    public let phase: InteractionPhase
    public let mechanism: SceneInteractionMechanismSnapshot
}

/// An isolated scene-lab checkpoint. It contains reducer state only; gesture
/// positions and other ephemeral presentation state never survive a restore.
/// Production Journey persistence uses `ChapterSession.interaction` as its one
/// authority and must not store this value beside it.
public struct SceneInteractionCheckpoint: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let interactionID: InteractionID
    public let authoredSpecDigest: String
    public let sequenceNumber: UInt64
    public let state: InteractionRuntimeState

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        interactionID: InteractionID,
        authoredSpecDigest: String,
        sequenceNumber: UInt64,
        state: InteractionRuntimeState
    ) {
        self.formatVersion = formatVersion
        self.interactionID = interactionID
        self.authoredSpecDigest = authoredSpecDigest
        self.sequenceNumber = sequenceNumber
        self.state = state
    }
}

/// The deterministic result of one domain action. It intentionally has no
/// touch/VoiceOver field: once both paths resolve to the same domain action,
/// they must produce an `Equatable`-identical response.
public struct SceneInteractionResponse: Codable, Equatable, Sendable {
    public let sequenceNumber: UInt64
    public let action: InteractionAction
    public let feedback: InteractionFeedback
    public let before: SceneInteractionSnapshot
    public let after: SceneInteractionSnapshot
    public let completedEffects: [WorldEffect]
    public let checkpoint: SceneInteractionCheckpoint
}

/// A pure proposal for one authored action. It deliberately carries neither
/// the touch/VoiceOver input source nor a second persistence cursor. A chapter
/// runtime may compare `candidateState` with the state returned by the durable
/// Journey commit before publishing the visual and audio response.
public struct SceneInteractionPreview: Codable, Equatable, Sendable {
    public let action: InteractionAction
    public let feedback: InteractionFeedback
    public let before: SceneInteractionSnapshot
    public let after: SceneInteractionSnapshot
    public let completedEffects: [WorldEffect]
    public let candidateState: InteractionRuntimeState

    public init(
        action: InteractionAction,
        feedback: InteractionFeedback,
        before: SceneInteractionSnapshot,
        after: SceneInteractionSnapshot,
        completedEffects: [WorldEffect],
        candidateState: InteractionRuntimeState
    ) {
        self.action = action
        self.feedback = feedback
        self.before = before
        self.after = after
        self.completedEffects = completedEffects
        self.candidateState = candidateState
    }
}

public enum SceneInteractionDriverError: Error, Equatable, Sendable {
    case invalidSpec
    case mismatchedInteraction
    case mismatchedAction
    case invalidActionValue
    case invalidRuntimeState
    case unsupportedCheckpointVersion(Int)
    case checkpointSpecMismatch
    case sequenceOverflow
}

/// A deterministic runtime adapter shared by all five interaction grammars.
/// `preview` is the production preflight boundary and never mutates Journey
/// state. The instance API remains useful for isolated scene labs and replay
/// tests; it is not a second authority beside durable `JourneyState`.
public struct SceneInteractionDriver: Sendable {
    public let spec: InteractionSpec
    public private(set) var state: InteractionRuntimeState
    public private(set) var sequenceNumber: UInt64

    private let authoredSpecDigest: String

    public init(spec: InteractionSpec) throws {
        try Self.validate(spec: spec)
        let state = InteractionRuntimeState(spec: spec)
        try Self.validate(state: state, against: spec)

        self.spec = spec
        self.state = state
        sequenceNumber = 0
        authoredSpecDigest = try Self.digest(of: spec)
    }

    public init(spec: InteractionSpec, restoring checkpoint: SceneInteractionCheckpoint) throws {
        try Self.validate(spec: spec)
        let digest = try Self.digest(of: spec)
        guard checkpoint.formatVersion == SceneInteractionCheckpoint.currentFormatVersion else {
            throw SceneInteractionDriverError.unsupportedCheckpointVersion(
                checkpoint.formatVersion
            )
        }
        guard checkpoint.interactionID == spec.id,
              checkpoint.state.interactionID == spec.id else {
            throw SceneInteractionDriverError.mismatchedInteraction
        }
        guard checkpoint.authoredSpecDigest == digest else {
            throw SceneInteractionDriverError.checkpointSpecMismatch
        }
        try Self.validate(state: checkpoint.state, against: spec)

        self.spec = spec
        state = checkpoint.state
        sequenceNumber = checkpoint.sequenceNumber
        authoredSpecDigest = digest
    }

    public func snapshot() throws -> SceneInteractionSnapshot {
        try Self.validate(state: state, against: spec)
        return try Self.snapshot(state: state, spec: spec)
    }

    public func checkpoint() throws -> SceneInteractionCheckpoint {
        try Self.validate(state: state, against: spec)
        return makeCheckpoint(state: state, sequenceNumber: sequenceNumber)
    }

    /// Validates and reduces one action against a copy of the committed state.
    /// The caller must still cross the durable Journey commit boundary before
    /// publishing this proposal or playing its causal haptic/audio response.
    public static func preview(
        spec: InteractionSpec,
        state: InteractionRuntimeState,
        input: SceneInteractionInput
    ) throws -> SceneInteractionPreview {
        try validate(spec: spec)
        try validate(state: state, against: spec)
        let action = input.domainAction
        try validate(action: action, for: spec, state: state)

        let before = try snapshot(state: state, spec: spec)
        var candidate = state
        let reduction: InteractionReduction
        do {
            reduction = try InteractionReducer.reduce(
                state: &candidate,
                spec: spec,
                action: action
            )
        } catch let error as InteractionRuntimeError {
            switch error {
            case .mismatchedIdentifier:
                throw SceneInteractionDriverError.mismatchedInteraction
            case .mismatchedGrammar:
                throw SceneInteractionDriverError.invalidRuntimeState
            case .invalidAction:
                throw SceneInteractionDriverError.mismatchedAction
            }
        } catch {
            throw SceneInteractionDriverError.invalidRuntimeState
        }

        try validate(state: candidate, against: spec)
        return SceneInteractionPreview(
            action: action,
            feedback: reduction.feedback,
            before: before,
            after: try snapshot(state: candidate, spec: spec),
            completedEffects: reduction.completedEffects,
            candidateState: candidate
        )
    }

    @discardableResult
    public mutating func submit(_ input: SceneInteractionInput) throws -> SceneInteractionResponse {
        guard sequenceNumber < UInt64.max else {
            throw SceneInteractionDriverError.sequenceOverflow
        }
        let preview = try Self.preview(spec: spec, state: state, input: input)
        let nextSequence = sequenceNumber + 1
        let checkpoint = makeCheckpoint(
            state: preview.candidateState,
            sequenceNumber: nextSequence
        )
        let response = SceneInteractionResponse(
            sequenceNumber: nextSequence,
            action: preview.action,
            feedback: preview.feedback,
            before: preview.before,
            after: preview.after,
            completedEffects: preview.completedEffects,
            checkpoint: checkpoint
        )

        state = preview.candidateState
        sequenceNumber = nextSequence
        return response
    }

    private func makeCheckpoint(
        state: InteractionRuntimeState,
        sequenceNumber: UInt64
    ) -> SceneInteractionCheckpoint {
        SceneInteractionCheckpoint(
            interactionID: spec.id,
            authoredSpecDigest: authoredSpecDigest,
            sequenceNumber: sequenceNumber,
            state: state
        )
    }

    private static func validate(spec: InteractionSpec) throws {
        do {
            try spec.validate()
        } catch {
            throw SceneInteractionDriverError.invalidSpec
        }
    }

    private static func digest(of spec: InteractionSpec) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(spec)
        } catch {
            throw SceneInteractionDriverError.invalidSpec
        }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func validate(
        action: InteractionAction,
        for spec: InteractionSpec,
        state: InteractionRuntimeState
    ) throws {
        switch (spec.grammar, action) {
        case (_, .begin), (_, .reset):
            return
        case (.trace, let .trace(point)):
            guard point.isUnitPoint else {
                throw SceneInteractionDriverError.invalidActionValue
            }
        case let (.allocate(configuration), .allocate(destinationID, units)):
            guard units >= 0 else {
                throw SceneInteractionDriverError.invalidActionValue
            }
            guard configuration.destinations.contains(where: { $0.id == destinationID }) else {
                return
            }
            guard case let .allocate(progress) = state.progress else {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            let otherUnits = try allocationTotal(
                progress.allocations.filter { $0.destinationID != destinationID },
                limit: configuration.totalUnits
            )
            let (_, overflow) = otherUnits.addingReportingOverflow(units)
            guard !overflow else {
                throw SceneInteractionDriverError.invalidActionValue
            }
        case (.allocate, .commitAllocation):
            return
        case (.assemble, .place):
            return
        case (.pressure, let .setPressure(_, magnitude)):
            guard magnitude.isFinite else {
                throw SceneInteractionDriverError.invalidActionValue
            }
        case (.pressure, .advancePressure):
            return
        case (.transform, let .transform(_, amount)):
            guard amount.isFinite else {
                throw SceneInteractionDriverError.invalidActionValue
            }
        default:
            throw SceneInteractionDriverError.mismatchedAction
        }
    }

    static func validate(
        state: InteractionRuntimeState,
        against spec: InteractionSpec
    ) throws {
        guard state.interactionID == spec.id else {
            throw SceneInteractionDriverError.mismatchedInteraction
        }

        switch (spec.grammar, state.progress) {
        case let (.trace(configuration), .trace(progress)):
            guard (0 ... configuration.anchors.count).contains(progress.reachedAnchorCount),
                  progress.lastPoint.map(\.isUnitPoint) ?? true else {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            switch state.phase {
            case .ready:
                guard progress.reachedAnchorCount == 0, progress.lastPoint == nil else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            case .active:
                guard progress.reachedAnchorCount < configuration.anchors.count else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            case .complete:
                guard progress.reachedAnchorCount == configuration.anchors.count else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            }

        case let (.allocate(configuration), .allocate(progress)):
            let expectedIDs = configuration.destinations.map(\.id).sorted()
            let actualIDs = progress.allocations.map(\.destinationID)
            let allocatedUnits = try allocationTotal(
                progress.allocations,
                limit: configuration.totalUnits
            )
            guard actualIDs == expectedIDs,
                  allocatedUnits <= configuration.totalUnits else {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            let meetsMinimums = configuration.destinations.allSatisfy { destination in
                (progress.allocations.first(where: {
                    $0.destinationID == destination.id
                })?.units ?? -1) >= destination.minimumUnits
            }
            let isCompleteAllocation = allocatedUnits == configuration.totalUnits && meetsMinimums
            switch state.phase {
            case .ready:
                guard progress.allocations.allSatisfy({ $0.units == 0 }) else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            case .active:
                break
            case .complete:
                guard isCompleteAllocation else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            }

        case let (.assemble(configuration), .assemble(progress)):
            let sortedPlacements = progress.placements.sorted { $0.componentID < $1.componentID }
            guard progress.placements == sortedPlacements,
                  Set(progress.placements.map(\.componentID)).count == progress.placements.count else {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            let placedIDs = Set(progress.placements.map(\.componentID))
            for placement in progress.placements {
                guard let component = configuration.components.first(where: {
                    $0.id == placement.componentID
                }), component.targetSlot == placement.slotID,
                component.prerequisites.allSatisfy(placedIDs.contains) else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            }
            switch state.phase {
            case .ready:
                guard progress.placements.isEmpty else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            case .active:
                guard progress.placements.count < configuration.components.count else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            case .complete:
                guard progress.placements.count == configuration.components.count else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            }

        case let (.pressure(configuration), .pressure(progress)):
            let expectedIDs = configuration.forces.map(\.id).sorted()
            let actualIDs = progress.values.map(\.forceID)
            let netPressure = try netPressure(
                configuration: configuration,
                progress: progress
            )
            guard actualIDs == expectedIDs,
                  progress.values.allSatisfy({
                      $0.magnitude.isFinite && (0 ... 1).contains($0.magnitude)
                  }),
                  configuration.forces.allSatisfy({ force in
                      force.userControllable
                          || progress.values.first(where: {
                              $0.forceID == force.id
                          })?.magnitude == force.initialMagnitude
                  }),
                  progress.stableMillis >= 0,
                  progress.stableMillis <= configuration.requiredHoldMillis + 999 else {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            switch state.phase {
            case .ready:
                guard progress.stableMillis == 0,
                      configuration.forces.allSatisfy({ force in
                          progress.values.first(where: {
                              $0.forceID == force.id
                          })?.magnitude == force.initialMagnitude
                      }) else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            case .active:
                guard progress.stableMillis < configuration.requiredHoldMillis else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            case .complete:
                guard progress.stableMillis >= configuration.requiredHoldMillis,
                      configuration.stableRange.contains(netPressure) else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            }

        case let (.transform(configuration), .transform(progress)):
            guard (0 ... configuration.stages.count).contains(progress.completedStageCount),
                  progress.currentAmount.isFinite,
                  (0 ... 1).contains(progress.currentAmount) else {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            if progress.completedStageCount < configuration.stages.count {
                let stage = configuration.stages[progress.completedStageCount]
                guard progress.currentAmount < stage.requiredAmount else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            } else if progress.currentAmount != 0 {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            switch state.phase {
            case .ready:
                guard progress.completedStageCount == 0, progress.currentAmount == 0 else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            case .active:
                guard progress.completedStageCount < configuration.stages.count else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            case .complete:
                guard progress.completedStageCount == configuration.stages.count else {
                    throw SceneInteractionDriverError.invalidRuntimeState
                }
            }

        default:
            throw SceneInteractionDriverError.invalidRuntimeState
        }
    }

    private static func snapshot(
        state: InteractionRuntimeState,
        spec: InteractionSpec
    ) throws -> SceneInteractionSnapshot {
        let mechanism: SceneInteractionMechanismSnapshot
        switch (spec.grammar, state.progress) {
        case let (.trace(configuration), .trace(progress)):
            mechanism = .trace(
                SceneTraceSnapshot(
                    reachedAnchorCount: progress.reachedAnchorCount,
                    totalAnchorCount: configuration.anchors.count,
                    lastPoint: progress.lastPoint
                )
            )

        case let (.allocate(configuration), .allocate(progress)):
            let allocatedUnits = try allocationTotal(
                progress.allocations,
                limit: configuration.totalUnits
            )
            mechanism = .allocate(
                SceneAllocateSnapshot(
                    resourceName: configuration.resourceName,
                    totalUnits: configuration.totalUnits,
                    allocatedUnits: allocatedUnits,
                    remainingUnits: configuration.totalUnits - allocatedUnits,
                    allocations: progress.allocations
                )
            )

        case let (.assemble(configuration), .assemble(progress)):
            let placedIDs = Set(progress.placements.map(\.componentID))
            let available = configuration.components.compactMap { component -> String? in
                guard !placedIDs.contains(component.id),
                      component.prerequisites.allSatisfy(placedIDs.contains) else {
                    return nil
                }
                return component.id
            }.sorted()
            mechanism = .assemble(
                SceneAssembleSnapshot(
                    placements: progress.placements,
                    availableComponentIDs: available,
                    totalComponentCount: configuration.components.count
                )
            )

        case let (.pressure(configuration), .pressure(progress)):
            let netPressure = try netPressure(
                configuration: configuration,
                progress: progress
            )
            mechanism = .pressure(
                ScenePressureSnapshot(
                    values: progress.values,
                    netPressure: netPressure,
                    stableMillis: progress.stableMillis,
                    requiredHoldMillis: configuration.requiredHoldMillis
                )
            )

        case let (.transform(configuration), .transform(progress)):
            let currentStage = progress.completedStageCount < configuration.stages.count
                ? configuration.stages[progress.completedStageCount]
                : nil
            mechanism = .transform(
                SceneTransformSnapshot(
                    completedStageCount: progress.completedStageCount,
                    totalStageCount: configuration.stages.count,
                    currentStageID: currentStage?.id,
                    currentControlID: currentStage?.controlID,
                    currentAmount: progress.currentAmount
                )
            )

        default:
            throw SceneInteractionDriverError.invalidRuntimeState
        }
        return SceneInteractionSnapshot(
            interactionID: state.interactionID,
            phase: state.phase,
            mechanism: mechanism
        )
    }

    private static func allocationTotal(
        _ allocations: [AllocationValue],
        limit: Int
    ) throws -> Int {
        var total = 0
        for allocation in allocations {
            guard allocation.units >= 0, allocation.units <= limit else {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            let (next, overflow) = total.addingReportingOverflow(allocation.units)
            guard !overflow, next <= limit else {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            total = next
        }
        return total
    }

    private static func netPressure(
        configuration: PressureInteractionSpec,
        progress: PressureProgress
    ) throws -> Double {
        var total = 0.0
        for force in configuration.forces {
            guard let magnitude = progress.values.first(where: {
                $0.forceID == force.id
            })?.magnitude else {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            let contribution = force.direction * magnitude
            let next = total + contribution
            guard contribution.isFinite, next.isFinite else {
                throw SceneInteractionDriverError.invalidRuntimeState
            }
            total = next
        }
        return total
    }
}
