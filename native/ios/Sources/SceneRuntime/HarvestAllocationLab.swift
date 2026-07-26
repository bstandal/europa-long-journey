#if DEBUG
import ContentKit
import CryptoKit
import Foundation
import JourneyDomain

/// A debug-only proof of the unresolved Harvest allocation decision.
///
/// This type deliberately does not extend the public content wire format. It
/// can prove the interaction before editor approval, while Release builds and
/// shipping package compilation remain unable to reference the draft.
public enum HarvestAllocationLabStatus {
    public static let editorialStatus = "DRAFT_AWAITING_EDITOR_APPROVAL"
    public static let shippingState = "PROHIBITED"
}

public struct HarvestAllocationMinimum: Codable, Equatable, Sendable {
    public let destinationID: String
    public let minimumUnits: Int

    public init(destinationID: String, minimumUnits: Int) {
        self.destinationID = destinationID
        self.minimumUnits = minimumUnits
    }
}

public struct HarvestAllocationLabSpec: Codable, Equatable, Sendable {
    public let totalUnits: Int
    public let destinations: [HarvestAllocationMinimum]
    public let completionEffects: [WorldEffect]

    public init(
        totalUnits: Int,
        destinations: [HarvestAllocationMinimum],
        completionEffects: [WorldEffect]
    ) throws {
        self.totalUnits = totalUnits
        self.destinations = destinations.sorted { $0.destinationID < $1.destinationID }
        self.completionEffects = completionEffects
        try validate()
    }

    public var minimumUnits: Int {
        destinations.reduce(0) { $0 + $1.minimumUnits }
    }

    public var surplusUnits: Int {
        totalUnits - minimumUnits
    }

    public func validate() throws {
        guard totalUnits > 0,
              destinations.count >= 2,
              completionEffects.count == 1 else {
            throw HarvestAllocationLabError.invalidSpec
        }

        var ids = Set<String>()
        var minimumTotal = 0
        for destination in destinations {
            guard !destination.destinationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(destination.destinationID).inserted,
                  destination.minimumUnits >= 0 else {
                throw HarvestAllocationLabError.invalidSpec
            }
            let (nextTotal, overflow) = minimumTotal.addingReportingOverflow(
                destination.minimumUnits
            )
            guard !overflow else {
                throw HarvestAllocationLabError.invalidSpec
            }
            minimumTotal = nextTotal
        }

        // The laboratory exists to prove a real choice after the obligations
        // have been met. A fully prescribed distribution would recreate the
        // hidden-answer interaction it replaces.
        guard minimumTotal < totalUnits else {
            throw HarvestAllocationLabError.invalidSpec
        }
    }

    public static func harvestDraftV1() throws -> HarvestAllocationLabSpec {
        try HarvestAllocationLabSpec(
            totalUnits: 12,
            destinations: [
                HarvestAllocationMinimum(destinationID: "food", minimumUnits: 4),
                HarvestAllocationMinimum(destinationID: "reserve", minimumUnits: 2),
                HarvestAllocationMinimum(destinationID: "seed", minimumUnits: 3),
            ],
            completionEffects: [
                WorldEffect(
                    id: WorldEffectID(
                        "effect-first-farmers-the-harvest-had-to-last"
                    ),
                    mutation: .revealNode(
                        WorldNodeBlueprint(
                            id: WorldNodeID("node-seasonal-store"),
                            kind: .institution,
                            form: "The divided store binds present consumption to reserve, seed and the next agricultural year.",
                            position: NormalizedPoint(x: 0.5, y: 0.5)
                        )
                    )
                ),
            ]
        )
    }
}

public enum HarvestAllocationLabAction: Codable, Equatable, Sendable {
    case set(destinationID: String, units: Int)
    case adjust(destinationID: String, delta: Int)
    case commit
    case reset
}

public enum HarvestAllocationLabInput: Codable, Equatable, Sendable {
    case touch(HarvestAllocationLabAction)
    case semantic(HarvestAllocationLabAction)

    public var domainAction: HarvestAllocationLabAction {
        switch self {
        case let .touch(action), let .semantic(action):
            action
        }
    }
}

public struct HarvestAllocationObligation: Codable, Equatable, Sendable {
    public let destinationID: String
    public let minimumUnits: Int
    public let allocatedUnits: Int
    public let unmetUnits: Int

    public init(
        destinationID: String,
        minimumUnits: Int,
        allocatedUnits: Int,
        unmetUnits: Int
    ) {
        self.destinationID = destinationID
        self.minimumUnits = minimumUnits
        self.allocatedUnits = allocatedUnits
        self.unmetUnits = unmetUnits
    }
}

public struct HarvestAllocationLabState: Codable, Equatable, Sendable {
    public var phase: InteractionPhase
    public var allocations: [AllocationValue]

    public init(phase: InteractionPhase, allocations: [AllocationValue]) {
        self.phase = phase
        self.allocations = allocations.sorted { $0.destinationID < $1.destinationID }
    }
}

public struct HarvestAllocationLabSnapshot: Codable, Equatable, Sendable {
    public let phase: InteractionPhase
    public let totalUnits: Int
    public let minimumUnits: Int
    public let surplusUnits: Int
    public let allocatedUnits: Int
    public let remainingUnits: Int
    public let allocations: [AllocationValue]
    public let obligations: [HarvestAllocationObligation]
    public let allMinimumsMet: Bool
    public let canCommit: Bool
}

public struct HarvestAllocationLabCheckpoint: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let specDigest: String
    public let sequenceNumber: UInt64
    public let state: HarvestAllocationLabState

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        specDigest: String,
        sequenceNumber: UInt64,
        state: HarvestAllocationLabState
    ) {
        self.formatVersion = formatVersion
        self.specDigest = specDigest
        self.sequenceNumber = sequenceNumber
        self.state = state
    }
}

public struct HarvestAllocationLabResponse: Codable, Equatable, Sendable {
    public let sequenceNumber: UInt64
    public let action: HarvestAllocationLabAction
    public let feedback: InteractionFeedback
    public let before: HarvestAllocationLabSnapshot
    public let after: HarvestAllocationLabSnapshot
    public let completedEffects: [WorldEffect]
    public let checkpoint: HarvestAllocationLabCheckpoint
}

public enum HarvestAllocationLabError: Error, Equatable, Sendable {
    case invalidSpec
    case invalidState
    case unsupportedCheckpointVersion(Int)
    case checkpointSpecMismatch
    case sequenceOverflow
}

public struct HarvestAllocationLabDriver: Sendable {
    public let spec: HarvestAllocationLabSpec
    public private(set) var state: HarvestAllocationLabState
    public private(set) var sequenceNumber: UInt64

    private let specDigest: String

    public init(spec: HarvestAllocationLabSpec) throws {
        try spec.validate()
        self.spec = spec
        state = HarvestAllocationLabState(
            phase: .ready,
            allocations: spec.destinations.map {
                AllocationValue(destinationID: $0.destinationID, units: 0)
            }
        )
        sequenceNumber = 0
        specDigest = try Self.digest(spec)
        try Self.validate(state: state, against: spec)
    }

    public init(
        spec: HarvestAllocationLabSpec,
        restoring checkpoint: HarvestAllocationLabCheckpoint
    ) throws {
        try spec.validate()
        let digest = try Self.digest(spec)
        guard checkpoint.formatVersion == HarvestAllocationLabCheckpoint.currentFormatVersion else {
            throw HarvestAllocationLabError.unsupportedCheckpointVersion(
                checkpoint.formatVersion
            )
        }
        guard checkpoint.specDigest == digest else {
            throw HarvestAllocationLabError.checkpointSpecMismatch
        }
        try Self.validate(state: checkpoint.state, against: spec)

        self.spec = spec
        state = checkpoint.state
        sequenceNumber = checkpoint.sequenceNumber
        specDigest = digest
    }

    public func snapshot() throws -> HarvestAllocationLabSnapshot {
        try Self.validate(state: state, against: spec)
        return try Self.snapshot(state: state, spec: spec)
    }

    public func checkpoint() throws -> HarvestAllocationLabCheckpoint {
        try Self.validate(state: state, against: spec)
        return makeCheckpoint(state: state, sequenceNumber: sequenceNumber)
    }

    @discardableResult
    public mutating func submit(
        _ input: HarvestAllocationLabInput
    ) throws -> HarvestAllocationLabResponse {
        try Self.validate(state: state, against: spec)
        guard sequenceNumber < UInt64.max else {
            throw HarvestAllocationLabError.sequenceOverflow
        }

        let action = input.domainAction
        let before = try Self.snapshot(state: state, spec: spec)
        var candidate = state
        var feedback = InteractionFeedback.resistance
        var completedEffects: [WorldEffect] = []

        if state.phase == .complete {
            feedback = .none
        } else {
            switch action {
            case let .set(destinationID, units):
                if Self.set(
                    destinationID: destinationID,
                    units: units,
                    state: &candidate,
                    spec: spec
                ) {
                    feedback = .progress
                }

            case let .adjust(destinationID, delta):
                guard let current = candidate.allocations.first(where: {
                    $0.destinationID == destinationID
                })?.units else {
                    break
                }
                let (next, overflow) = current.addingReportingOverflow(delta)
                if !overflow,
                   Self.set(
                       destinationID: destinationID,
                       units: next,
                       state: &candidate,
                       spec: spec
                   ) {
                    feedback = .progress
                }

            case .commit:
                let snapshot = try Self.snapshot(state: candidate, spec: spec)
                if snapshot.canCommit {
                    candidate.phase = .complete
                    feedback = .completed
                    completedEffects = spec.completionEffects
                }

            case .reset:
                candidate.allocations = spec.destinations.map {
                    AllocationValue(destinationID: $0.destinationID, units: 0)
                }
                candidate.phase = .ready
                feedback = .progress
            }
        }

        try Self.validate(state: candidate, against: spec)
        let nextSequence = sequenceNumber + 1
        let after = try Self.snapshot(state: candidate, spec: spec)
        let checkpoint = makeCheckpoint(
            state: candidate,
            sequenceNumber: nextSequence
        )
        let response = HarvestAllocationLabResponse(
            sequenceNumber: nextSequence,
            action: action,
            feedback: feedback,
            before: before,
            after: after,
            completedEffects: completedEffects,
            checkpoint: checkpoint
        )

        state = candidate
        sequenceNumber = nextSequence
        return response
    }

    private func makeCheckpoint(
        state: HarvestAllocationLabState,
        sequenceNumber: UInt64
    ) -> HarvestAllocationLabCheckpoint {
        HarvestAllocationLabCheckpoint(
            specDigest: specDigest,
            sequenceNumber: sequenceNumber,
            state: state
        )
    }

    private static func set(
        destinationID: String,
        units: Int,
        state: inout HarvestAllocationLabState,
        spec: HarvestAllocationLabSpec
    ) -> Bool {
        guard units >= 0,
              let index = state.allocations.firstIndex(where: {
                  $0.destinationID == destinationID
              }) else {
            return false
        }

        var allocatedWithoutDestination = 0
        for allocation in state.allocations where allocation.destinationID != destinationID {
            let (next, overflow) = allocatedWithoutDestination.addingReportingOverflow(
                allocation.units
            )
            guard !overflow else {
                return false
            }
            allocatedWithoutDestination = next
        }
        let (candidateTotal, overflow) = allocatedWithoutDestination.addingReportingOverflow(units)
        guard !overflow, candidateTotal <= spec.totalUnits else {
            return false
        }

        state.allocations[index].units = units
        state.phase = state.allocations.allSatisfy { $0.units == 0 } ? .ready : .active
        return true
    }

    private static func snapshot(
        state: HarvestAllocationLabState,
        spec: HarvestAllocationLabSpec
    ) throws -> HarvestAllocationLabSnapshot {
        let allocatedUnits = try total(state.allocations, limit: spec.totalUnits)
        let obligations = spec.destinations.map { destination in
            let allocated = state.allocations.first(where: {
                $0.destinationID == destination.destinationID
            })?.units ?? 0
            return HarvestAllocationObligation(
                destinationID: destination.destinationID,
                minimumUnits: destination.minimumUnits,
                allocatedUnits: allocated,
                unmetUnits: max(0, destination.minimumUnits - allocated)
            )
        }
        let allMinimumsMet = obligations.allSatisfy { $0.unmetUnits == 0 }
        let remainingUnits = spec.totalUnits - allocatedUnits

        return HarvestAllocationLabSnapshot(
            phase: state.phase,
            totalUnits: spec.totalUnits,
            minimumUnits: spec.minimumUnits,
            surplusUnits: spec.surplusUnits,
            allocatedUnits: allocatedUnits,
            remainingUnits: remainingUnits,
            allocations: state.allocations,
            obligations: obligations,
            allMinimumsMet: allMinimumsMet,
            canCommit: remainingUnits == 0 && allMinimumsMet
        )
    }

    private static func validate(
        state: HarvestAllocationLabState,
        against spec: HarvestAllocationLabSpec
    ) throws {
        let expectedIDs = spec.destinations.map(\.destinationID)
        guard state.allocations.map(\.destinationID) == expectedIDs,
              state.allocations.allSatisfy({ $0.units >= 0 }) else {
            throw HarvestAllocationLabError.invalidState
        }

        let allocatedUnits = try total(state.allocations, limit: spec.totalUnits)
        let allMinimumsMet = spec.destinations.allSatisfy { destination in
            state.allocations.first(where: {
                $0.destinationID == destination.destinationID
            })?.units ?? -1 >= destination.minimumUnits
        }

        switch state.phase {
        case .ready:
            guard allocatedUnits == 0 else {
                throw HarvestAllocationLabError.invalidState
            }
        case .active:
            guard allocatedUnits > 0 else {
                throw HarvestAllocationLabError.invalidState
            }
        case .complete:
            guard allocatedUnits == spec.totalUnits, allMinimumsMet else {
                throw HarvestAllocationLabError.invalidState
            }
        }
    }

    private static func total(
        _ allocations: [AllocationValue],
        limit: Int
    ) throws -> Int {
        var sum = 0
        for allocation in allocations {
            let (next, overflow) = sum.addingReportingOverflow(allocation.units)
            guard !overflow, next <= limit else {
                throw HarvestAllocationLabError.invalidState
            }
            sum = next
        }
        return sum
    }

    private static func digest(_ spec: HarvestAllocationLabSpec) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes: Data
        do {
            bytes = try encoder.encode(spec)
        } catch {
            throw HarvestAllocationLabError.invalidSpec
        }
        return SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
#endif
