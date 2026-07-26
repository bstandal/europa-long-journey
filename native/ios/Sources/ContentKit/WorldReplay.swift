import CryptoKit
import Foundation

/// Hidden nodes and dormant traces required before any independently selectable
/// chapter can apply its authored consequences. The seed is public experience
/// data, never research or evidence metadata.
public struct WorldSeedSpec: Codable, Equatable, Sendable {
    public let nodes: [WorldNodeBlueprint]
    public let traces: [WorldTraceBlueprint]

    public init(nodes: [WorldNodeBlueprint], traces: [WorldTraceBlueprint]) {
        self.nodes = nodes
        self.traces = traces
    }

    public func validate() throws {
        try requireUnique(nodes.map(\.id))
        try requireUnique(traces.map(\.id))
        let nodeIDs = Set(nodes.map(\.id))
        for node in nodes {
            try validateSeedNode(node)
        }
        for trace in traces {
            try validateSeedTrace(trace)
            guard nodeIDs.contains(trace.origin) else {
                throw WorldReplayError.missingNode(trace.origin)
            }
            guard nodeIDs.contains(trace.destination) else {
                throw WorldReplayError.missingNode(trace.destination)
            }
        }
    }
}

public struct ChapterWorldDigest: Equatable, Sendable {
    public let chapterID: ChapterID
    public let digest: String

    public init(chapterID: ChapterID, digest: String) {
        self.chapterID = chapterID
        self.digest = digest
    }
}

public struct WorldReplayReport: Equatable, Sendable {
    public let perChapter: [ChapterWorldDigest]
    public let cumulativeDigest: String

    public init(perChapter: [ChapterWorldDigest], cumulativeDigest: String) {
        self.perChapter = perChapter
        self.cumulativeDigest = cumulativeDigest
    }
}

public enum WorldReplayError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingNode(WorldNodeID)
    case missingTrace(WorldTraceID)
    case conflictingNode(WorldNodeID)
    case conflictingTrace(WorldTraceID)
    case conflictingEffect(WorldEffectID)
    case nonDeterministicReplay

    public var description: String {
        switch self {
        case let .missingNode(id):
            "World replay is missing node: \(id)"
        case let .missingTrace(id):
            "World replay is missing trace: \(id)"
        case let .conflictingNode(id):
            "World replay has a conflicting node: \(id)"
        case let .conflictingTrace(id):
            "World replay has a conflicting trace: \(id)"
        case let .conflictingEffect(id):
            "World replay has a conflicting effect: \(id)"
        case .nonDeterministicReplay:
            "Identical canonical world replays produced different digests"
        }
    }
}

/// Runs every chapter from the same authored seed and then runs the package in
/// canonical array order twice. Compilation and the runtime decoder use the
/// same rules, so a signed package cannot contain an impossible consequence.
public enum WorldReplayValidator {
    public static func validate(
        seed: WorldSeedSpec,
        chapters: [ChapterSpec]
    ) throws -> WorldReplayReport {
        try seed.validate()
        let initial = try ReplayState(seed: seed)
        let perChapter = try chapters.map { chapter in
            var state = initial
            try state.apply(chapter: chapter)
            return try ChapterWorldDigest(
                chapterID: chapter.id,
                digest: state.digest()
            )
        }

        var first = initial
        for chapter in chapters { try first.apply(chapter: chapter) }
        var second = initial
        for chapter in chapters { try second.apply(chapter: chapter) }
        let firstDigest = try first.digest()
        let secondDigest = try second.digest()
        guard firstDigest == secondDigest else {
            throw WorldReplayError.nonDeterministicReplay
        }
        return WorldReplayReport(perChapter: perChapter, cumulativeDigest: firstDigest)
    }
}

private enum ReplayNodeVisibility: String, Encodable {
    case hidden
    case revealed
    case transformed
}

private enum ReplayTraceState: String, Encodable {
    case dormant
    case active
    case superseded
}

private struct ReplayNode: Equatable {
    var blueprint: WorldNodeBlueprint
    var visibility: ReplayNodeVisibility
    var revision: Int
}

private struct ReplayTrace: Equatable {
    var blueprint: WorldTraceBlueprint
    var state: ReplayTraceState
}

private struct ReplayState {
    var nodes: [WorldNodeID: ReplayNode]
    var traces: [WorldTraceID: ReplayTrace]
    var effects: [WorldEffectID: WorldEffect]

    init(seed: WorldSeedSpec) throws {
        nodes = Dictionary(uniqueKeysWithValues: seed.nodes.map { node in
            (node.id, ReplayNode(
                blueprint: normalized(node),
                visibility: .hidden,
                revision: 0
            ))
        })
        traces = Dictionary(uniqueKeysWithValues: seed.traces.map { trace in
            (trace.id, ReplayTrace(blueprint: trace, state: .dormant))
        })
        effects = [:]
    }

    mutating func apply(chapter: ChapterSpec) throws {
        for arc in chapter.arcs {
            for beat in arc.beats {
                if let interaction = beat.interaction {
                    try apply(interaction.completionEffects)
                } else {
                    try apply(beat.completionEffects)
                }
            }
        }
        try apply(chapter.completionEffects)
    }

    mutating func apply(_ authoredEffects: [WorldEffect]) throws {
        for effect in authoredEffects { try apply(effect) }
    }

    mutating func apply(_ effect: WorldEffect) throws {
        if let previous = effects[effect.id] {
            guard previous == effect else {
                throw WorldReplayError.conflictingEffect(effect.id)
            }
            return
        }

        switch effect.mutation {
        case let .revealNode(authoredNode):
            let node = normalized(authoredNode)
            if var existing = nodes[node.id] {
                guard existing.blueprint.kind == node.kind,
                      existing.blueprint.position == node.position else {
                    throw WorldReplayError.conflictingNode(node.id)
                }
                switch existing.visibility {
                case .hidden:
                    existing.blueprint = node
                    existing.visibility = .revealed
                    existing.revision += 1
                    nodes[node.id] = existing
                case .revealed:
                    guard existing.blueprint == node else {
                        throw WorldReplayError.conflictingNode(node.id)
                    }
                case .transformed:
                    throw WorldReplayError.conflictingNode(node.id)
                }
            } else {
                nodes[node.id] = ReplayNode(
                    blueprint: node,
                    visibility: .revealed,
                    revision: 0
                )
            }

        case let .establishTrace(trace):
            guard nodes[trace.origin] != nil else {
                throw WorldReplayError.missingNode(trace.origin)
            }
            guard nodes[trace.destination] != nil else {
                throw WorldReplayError.missingNode(trace.destination)
            }
            if var existing = traces[trace.id] {
                guard existing.blueprint == trace else {
                    throw WorldReplayError.conflictingTrace(trace.id)
                }
                switch existing.state {
                case .dormant:
                    existing.state = .active
                    traces[trace.id] = existing
                case .active:
                    break
                case .superseded:
                    throw WorldReplayError.conflictingTrace(trace.id)
                }
            } else {
                traces[trace.id] = ReplayTrace(blueprint: trace, state: .active)
            }

        case let .transformNode(nodeID, form, authoredAttributes):
            guard var node = nodes[nodeID] else {
                throw WorldReplayError.missingNode(nodeID)
            }
            node.blueprint = WorldNodeBlueprint(
                id: node.blueprint.id,
                kind: node.blueprint.kind,
                form: form,
                position: node.blueprint.position,
                attributes: merging(node.blueprint.attributes, with: authoredAttributes)
            )
            node.visibility = .transformed
            node.revision += 1 + authoredAttributes.count
            nodes[nodeID] = node

        case let .setNodeAttribute(nodeID, value):
            guard var node = nodes[nodeID] else {
                throw WorldReplayError.missingNode(nodeID)
            }
            node.blueprint = WorldNodeBlueprint(
                id: node.blueprint.id,
                kind: node.blueprint.kind,
                form: node.blueprint.form,
                position: node.blueprint.position,
                attributes: merging(node.blueprint.attributes, with: [value])
            )
            node.revision += 1
            nodes[nodeID] = node

        case let .supersedeTrace(traceID):
            guard var trace = traces[traceID] else {
                throw WorldReplayError.missingTrace(traceID)
            }
            trace.state = .superseded
            traces[traceID] = trace
        }
        effects[effect.id] = effect
    }

    func digest() throws -> String {
        let snapshot = ReplaySnapshot(
            nodes: nodes.values.map { node in
                ReplayNodeSnapshot(
                    id: node.blueprint.id,
                    kind: node.blueprint.kind,
                    form: node.blueprint.form,
                    position: node.blueprint.position,
                    attributes: sorted(node.blueprint.attributes),
                    visibility: node.visibility,
                    revision: node.revision
                )
            }.sorted { $0.id < $1.id },
            traces: traces.values.map { trace in
                ReplayTraceSnapshot(
                    id: trace.blueprint.id,
                    kind: trace.blueprint.kind,
                    origin: trace.blueprint.origin,
                    destination: trace.blueprint.destination,
                    strength: trace.blueprint.strength,
                    state: trace.state
                )
            }.sorted { $0.id < $1.id },
            appliedEffectIDs: effects.keys.sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct ReplaySnapshot: Encodable {
    let nodes: [ReplayNodeSnapshot]
    let traces: [ReplayTraceSnapshot]
    let appliedEffectIDs: [WorldEffectID]
}

private struct ReplayNodeSnapshot: Encodable {
    let id: WorldNodeID
    let kind: WorldNodeKind
    let form: String
    let position: NormalizedPoint
    let attributes: [NamedValue]
    let visibility: ReplayNodeVisibility
    let revision: Int
}

private struct ReplayTraceSnapshot: Encodable {
    let id: WorldTraceID
    let kind: WorldTraceKind
    let origin: WorldNodeID
    let destination: WorldNodeID
    let strength: Double
    let state: ReplayTraceState
}

private func normalized(_ node: WorldNodeBlueprint) -> WorldNodeBlueprint {
    WorldNodeBlueprint(
        id: node.id,
        kind: node.kind,
        form: node.form,
        position: node.position,
        attributes: sorted(node.attributes)
    )
}

private func sorted(_ values: [NamedValue]) -> [NamedValue] {
    values.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
}

private func merging(_ existing: [NamedValue], with replacements: [NamedValue]) -> [NamedValue] {
    var values = Dictionary(uniqueKeysWithValues: existing.map { ($0.key, $0) })
    for replacement in replacements { values[replacement.key] = replacement }
    return values.values.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
}

private func validateSeedNode(_ node: WorldNodeBlueprint) throws {
    try requireNonempty(node.id, field: "worldSeed.nodes.id")
    guard node.position.isUnitPoint,
          !node.form.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          validSeedAttributes(node.attributes) else {
        throw ContentValidationError.invalidValue(
            field: "worldSeed.nodes",
            reason: "requires a unit-space position, concrete form and unique finite attributes"
        )
    }
}

private func validateSeedTrace(_ trace: WorldTraceBlueprint) throws {
    try requireNonempty(trace.id, field: "worldSeed.traces.id")
    try requireNonempty(trace.origin, field: "worldSeed.traces.origin")
    try requireNonempty(trace.destination, field: "worldSeed.traces.destination")
    guard trace.strength.isFinite, trace.strength > 0 else {
        throw ContentValidationError.invalidValue(
            field: "worldSeed.traces.strength",
            reason: "must be finite and positive"
        )
    }
}

private func validSeedAttributes(_ values: [NamedValue]) -> Bool {
    let keys = values.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard keys.allSatisfy({ !$0.isEmpty }), Set(keys).count == keys.count else { return false }
    return values.allSatisfy { value in
        switch value.value {
        case let .decimal(number): number.isFinite
        case let .text(text): !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .boolean, .integer: true
        }
    }
}
