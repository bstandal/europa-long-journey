import ContentKit
import Foundation

public enum WorldNodeVisibility: String, Codable, Equatable, Sendable {
    case hidden
    case revealed
    case transformed
}

public struct WorldNodeState: Codable, Equatable, Identifiable, Sendable {
    public let id: WorldNodeID
    public let kind: WorldNodeKind
    public var form: String
    public let position: NormalizedPoint
    public var visibility: WorldNodeVisibility
    public var attributes: [NamedValue]
    public var revision: Int

    public init(
        id: WorldNodeID,
        kind: WorldNodeKind,
        form: String,
        position: NormalizedPoint,
        visibility: WorldNodeVisibility,
        attributes: [NamedValue],
        revision: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.form = form
        self.position = position
        self.visibility = visibility
        self.attributes = attributes.sorted { $0.key < $1.key }
        self.revision = revision
    }

    mutating func setAttribute(_ namedValue: NamedValue) {
        attributes.removeAll { $0.key == namedValue.key }
        attributes.append(namedValue)
        attributes.sort { $0.key < $1.key }
        revision += 1
    }
}

public enum WorldTraceState: String, Codable, Equatable, Sendable {
    case dormant
    case active
    case superseded
}

public struct WorldTraceStateRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: WorldTraceID
    public let kind: WorldTraceKind
    public let origin: WorldNodeID
    public let destination: WorldNodeID
    public let strength: Double
    public var state: WorldTraceState

    public init(
        blueprint: WorldTraceBlueprint,
        state: WorldTraceState = .active
    ) {
        id = blueprint.id
        kind = blueprint.kind
        origin = blueprint.origin
        destination = blueprint.destination
        strength = blueprint.strength
        self.state = state
    }
}

public enum WorldGraphError: Error, Equatable, Sendable {
    case missingNode(WorldNodeID)
    case missingTrace(WorldTraceID)
    case conflictingNode(WorldNodeID)
    case conflictingTrace(WorldTraceID)
    case conflictingEffect(WorldEffectID)
}

/// The cumulative historical world. Arrays remain sorted so snapshots have a canonical order.
public struct WorldGraph: Codable, Equatable, Sendable {
    public private(set) var nodes: [WorldNodeState]
    public private(set) var traces: [WorldTraceStateRecord]
    public private(set) var appliedEffects: [WorldEffect]

    public var appliedEffectIDs: [WorldEffectID] {
        appliedEffects.map(\.id)
    }

    public init(
        nodes: [WorldNodeState] = [],
        traces: [WorldTraceStateRecord] = [],
        appliedEffects: [WorldEffect] = []
    ) {
        self.nodes = nodes.sorted { $0.id < $1.id }
        self.traces = traces.sorted { $0.id < $1.id }
        self.appliedEffects = appliedEffects.sorted { $0.id < $1.id }
    }

    /// Creates the hidden/dormant baseline shared by independently selectable
    /// chapters. Seed validation happens again here even after package decoding
    /// so an in-memory caller cannot bypass the content gate.
    public init(seed: WorldSeedSpec) throws {
        try seed.validate()
        nodes = seed.nodes.map { blueprint in
            WorldNodeState(
                id: blueprint.id,
                kind: blueprint.kind,
                form: blueprint.form,
                position: blueprint.position,
                visibility: .hidden,
                attributes: blueprint.attributes
            )
        }.sorted { $0.id < $1.id }
        traces = seed.traces.map {
            WorldTraceStateRecord(blueprint: $0, state: .dormant)
        }.sorted { $0.id < $1.id }
        appliedEffects = []
    }

    /// Rebuilds the cumulative world in collection chronology. The same set of
    /// completed chapters therefore produces one result regardless of the order
    /// in which the user entered those chapters.
    public static func replay(
        seed: WorldSeedSpec,
        orderedCompletedChapters: [ChapterSpec]
    ) throws -> WorldGraph {
        var graph = try WorldGraph(seed: seed)
        for chapter in orderedCompletedChapters {
            for arc in chapter.arcs {
                for beat in arc.beats {
                    if let interaction = beat.interaction {
                        try graph.applyAtomically(interaction.completionEffects)
                    } else {
                        try graph.applyAtomically(beat.completionEffects)
                    }
                }
            }
            try graph.applyAtomically(chapter.completionEffects)
        }
        return graph
    }

    public func node(_ id: WorldNodeID) -> WorldNodeState? {
        nodes.first { $0.id == id }
    }

    public func trace(_ id: WorldTraceID) -> WorldTraceStateRecord? {
        traces.first { $0.id == id }
    }

    public func hasApplied(_ id: WorldEffectID) -> Bool {
        appliedEffects.contains { $0.id == id }
    }

    /// Applies a causal consequence once. Replaying the same effect is intentionally a no-op.
    public mutating func apply(_ effect: WorldEffect) throws {
        if let previous = appliedEffects.first(where: { $0.id == effect.id }) {
            guard previous == effect else {
                throw WorldGraphError.conflictingEffect(effect.id)
            }
            return
        }

        switch effect.mutation {
        case let .revealNode(blueprint):
            if let index = nodes.firstIndex(where: { $0.id == blueprint.id }) {
                let existing = nodes[index]
                guard existing.kind == blueprint.kind, existing.position == blueprint.position else {
                    throw WorldGraphError.conflictingNode(blueprint.id)
                }
                switch existing.visibility {
                case .hidden:
                    nodes[index].form = blueprint.form
                    nodes[index].attributes = blueprint.attributes.sorted { $0.key < $1.key }
                    nodes[index].visibility = .revealed
                    nodes[index].revision += 1
                case .revealed:
                    guard existing.form == blueprint.form,
                          existing.attributes == blueprint.attributes.sorted(by: { $0.key < $1.key }) else {
                        throw WorldGraphError.conflictingNode(blueprint.id)
                    }
                case .transformed:
                    throw WorldGraphError.conflictingNode(blueprint.id)
                }
            } else {
                nodes.append(
                    WorldNodeState(
                        id: blueprint.id,
                        kind: blueprint.kind,
                        form: blueprint.form,
                        position: blueprint.position,
                        visibility: .revealed,
                        attributes: blueprint.attributes
                    )
                )
                nodes.sort { $0.id < $1.id }
            }

        case let .establishTrace(blueprint):
            guard node(blueprint.origin) != nil else {
                throw WorldGraphError.missingNode(blueprint.origin)
            }
            guard node(blueprint.destination) != nil else {
                throw WorldGraphError.missingNode(blueprint.destination)
            }
            if let index = traces.firstIndex(where: { $0.id == blueprint.id }) {
                let existing = traces[index]
                guard existing.origin == blueprint.origin,
                      existing.destination == blueprint.destination,
                      existing.kind == blueprint.kind,
                      existing.strength == blueprint.strength else {
                    throw WorldGraphError.conflictingTrace(blueprint.id)
                }
                switch existing.state {
                case .dormant:
                    traces[index].state = .active
                case .active:
                    break
                case .superseded:
                    throw WorldGraphError.conflictingTrace(blueprint.id)
                }
            } else {
                traces.append(WorldTraceStateRecord(blueprint: blueprint))
                traces.sort { $0.id < $1.id }
            }

        case let .transformNode(nodeID, form, attributes):
            guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else {
                throw WorldGraphError.missingNode(nodeID)
            }
            nodes[index].form = form
            nodes[index].visibility = .transformed
            nodes[index].revision += 1
            for attribute in attributes {
                nodes[index].setAttribute(attribute)
            }

        case let .setNodeAttribute(nodeID, value):
            guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else {
                throw WorldGraphError.missingNode(nodeID)
            }
            nodes[index].setAttribute(value)

        case let .supersedeTrace(traceID):
            guard let index = traces.firstIndex(where: { $0.id == traceID }) else {
                throw WorldGraphError.missingTrace(traceID)
            }
            traces[index].state = .superseded
        }

        appliedEffects.append(effect)
        appliedEffects.sort { $0.id < $1.id }
    }

    /// Either all effects become visible or none do.
    public mutating func applyAtomically(_ effects: [WorldEffect]) throws {
        var candidate = self
        for effect in effects {
            try candidate.apply(effect)
        }
        self = candidate
    }
}

private extension Array where Element: Comparable {
    func binarySearch(_ value: Element) -> Bool {
        var lower = startIndex
        var upper = endIndex
        while lower < upper {
            let distance = self.distance(from: lower, to: upper)
            let middle = index(lower, offsetBy: distance / 2)
            if self[middle] == value { return true }
            if self[middle] < value {
                lower = index(after: middle)
            } else {
                upper = middle
            }
        }
        return false
    }
}
