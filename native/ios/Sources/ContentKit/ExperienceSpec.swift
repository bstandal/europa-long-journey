import Foundation

public struct NormalizedPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: Self) -> Double {
        let deltaX = x - other.x
        let deltaY = y - other.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }

    public var isUnitPoint: Bool {
        (0 ... 1).contains(x) && (0 ... 1).contains(y)
    }
}

public enum ScalarValue: Codable, Equatable, Sendable {
    case boolean(Bool)
    case integer(Int)
    case decimal(Double)
    case text(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .decimal(value)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .boolean(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .decimal(value): try container.encode(value)
        case let .text(value): try container.encode(value)
        }
    }
}

public struct NamedValue: Codable, Equatable, Sendable {
    public let key: String
    public let value: ScalarValue

    public init(key: String, value: ScalarValue) {
        self.key = key
        self.value = value
    }
}

public enum WorldNodeKind: String, Codable, Equatable, Sendable {
    case settlement
    case city
    case frontier
    case institution
    case landscape
    case object
}

public struct WorldNodeBlueprint: Codable, Equatable, Sendable {
    public let id: WorldNodeID
    public let kind: WorldNodeKind
    public let form: String
    public let position: NormalizedPoint
    public let attributes: [NamedValue]

    public init(
        id: WorldNodeID,
        kind: WorldNodeKind,
        form: String,
        position: NormalizedPoint,
        attributes: [NamedValue] = []
    ) {
        self.id = id
        self.kind = kind
        self.form = form
        self.position = position
        self.attributes = attributes
    }
}

public enum WorldTraceKind: String, Codable, Equatable, Sendable {
    case road
    case seaRoute
    case riverRoute
    case frontier
    case jurisdiction
    case exchange
    case transmission
}

public struct WorldTraceBlueprint: Codable, Equatable, Sendable {
    public let id: WorldTraceID
    public let kind: WorldTraceKind
    public let origin: WorldNodeID
    public let destination: WorldNodeID
    public let strength: Double

    public init(
        id: WorldTraceID,
        kind: WorldTraceKind,
        origin: WorldNodeID,
        destination: WorldNodeID,
        strength: Double = 1
    ) {
        self.id = id
        self.kind = kind
        self.origin = origin
        self.destination = destination
        self.strength = strength
    }
}

public struct WorldEffect: Codable, Equatable, Identifiable, Sendable {
    public enum Mutation: Codable, Equatable, Sendable {
        case revealNode(WorldNodeBlueprint)
        case establishTrace(WorldTraceBlueprint)
        case transformNode(nodeID: WorldNodeID, form: String, attributes: [NamedValue])
        case setNodeAttribute(nodeID: WorldNodeID, value: NamedValue)
        case supersedeTrace(traceID: WorldTraceID)
    }

    public let id: WorldEffectID
    public let mutation: Mutation

    public init(id: WorldEffectID, mutation: Mutation) {
        self.id = id
        self.mutation = mutation
    }

    private enum MutationKind: String, Codable {
        case revealNode = "reveal-node"
        case establishTrace = "establish-trace"
        case transformNode = "transform-node"
        case setNodeAttribute = "set-node-attribute"
        case supersedeTrace = "supersede-trace"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case mutation
        case node
        case trace
        case nodeID
        case form
        case attributes
        case value
        case traceID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(WorldEffectID.self, forKey: .id)
        switch try container.decode(MutationKind.self, forKey: .mutation) {
        case .revealNode:
            mutation = .revealNode(try container.decode(WorldNodeBlueprint.self, forKey: .node))
        case .establishTrace:
            mutation = .establishTrace(try container.decode(WorldTraceBlueprint.self, forKey: .trace))
        case .transformNode:
            mutation = .transformNode(
                nodeID: try container.decode(WorldNodeID.self, forKey: .nodeID),
                form: try container.decode(String.self, forKey: .form),
                attributes: try container.decode([NamedValue].self, forKey: .attributes)
            )
        case .setNodeAttribute:
            mutation = .setNodeAttribute(
                nodeID: try container.decode(WorldNodeID.self, forKey: .nodeID),
                value: try container.decode(NamedValue.self, forKey: .value)
            )
        case .supersedeTrace:
            mutation = .supersedeTrace(
                traceID: try container.decode(WorldTraceID.self, forKey: .traceID)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch mutation {
        case let .revealNode(node):
            try container.encode(MutationKind.revealNode, forKey: .mutation)
            try container.encode(node, forKey: .node)
        case let .establishTrace(trace):
            try container.encode(MutationKind.establishTrace, forKey: .mutation)
            try container.encode(trace, forKey: .trace)
        case let .transformNode(nodeID, form, attributes):
            try container.encode(MutationKind.transformNode, forKey: .mutation)
            try container.encode(nodeID, forKey: .nodeID)
            try container.encode(form, forKey: .form)
            try container.encode(attributes, forKey: .attributes)
        case let .setNodeAttribute(nodeID, value):
            try container.encode(MutationKind.setNodeAttribute, forKey: .mutation)
            try container.encode(nodeID, forKey: .nodeID)
            try container.encode(value, forKey: .value)
        case let .supersedeTrace(traceID):
            try container.encode(MutationKind.supersedeTrace, forKey: .mutation)
            try container.encode(traceID, forKey: .traceID)
        }
    }

    public func validate() throws {
        try requireNonempty(id, field: "worldEffect.id")
        switch mutation {
        case let .revealNode(node):
            try requireNonempty(node.id, field: "worldEffect.node.id")
            guard node.position.isUnitPoint,
                  !node.form.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  validNamedValues(node.attributes) else {
                throw ContentValidationError.invalidValue(
                    field: "worldEffect.node",
                    reason: "requires a unit-space position, concrete form and unique attributes"
                )
            }
        case let .establishTrace(trace):
            try requireNonempty(trace.id, field: "worldEffect.trace.id")
            try requireNonempty(trace.origin, field: "worldEffect.trace.origin")
            try requireNonempty(trace.destination, field: "worldEffect.trace.destination")
            guard trace.strength.isFinite, trace.strength > 0 else {
                throw ContentValidationError.invalidValue(
                    field: "worldEffect.trace.strength",
                    reason: "must be finite and positive"
                )
            }
        case let .transformNode(nodeID, form, attributes):
            try requireNonempty(nodeID, field: "worldEffect.nodeID")
            guard !form.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  validNamedValues(attributes) else {
                throw ContentValidationError.invalidValue(
                    field: "worldEffect.transformNode",
                    reason: "requires a form and unique attributes"
                )
            }
        case let .setNodeAttribute(nodeID, value):
            try requireNonempty(nodeID, field: "worldEffect.nodeID")
            guard !value.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContentValidationError.invalidValue(
                    field: "worldEffect.value.key",
                    reason: "must be authored"
                )
            }
        case let .supersedeTrace(traceID):
            try requireNonempty(traceID, field: "worldEffect.traceID")
        }
    }
}

public struct NarrativeText: Codable, Equatable, Sendable {
    public let eyebrow: LocalizedStringSpec?
    public let heading: LocalizedStringSpec
    public let paragraphs: [LocalizedStringSpec]
    public let actionPrompt: LocalizedStringSpec?

    public init(
        eyebrow: LocalizedStringSpec? = nil,
        heading: LocalizedStringSpec,
        paragraphs: [LocalizedStringSpec],
        actionPrompt: LocalizedStringSpec? = nil
    ) {
        self.eyebrow = eyebrow
        self.heading = heading
        self.paragraphs = paragraphs
        self.actionPrompt = actionPrompt
    }

    /// The exact public reading segments eligible for pre-produced narration.
    public var manuscriptSegments: [LocalizedStringSpec] {
        [heading] + paragraphs
    }

    var allLocalizedStrings: [LocalizedStringSpec] {
        [eyebrow, heading, actionPrompt].compactMap { $0 } + paragraphs
    }

    func validate(field: String) throws {
        guard !paragraphs.isEmpty else {
            throw ContentValidationError.invalidCount(
                field: "\(field).paragraphs",
                expected: "at least one",
                actual: 0
            )
        }
        try requireConsistentLocalizedStrings(allLocalizedStrings, field: field)
    }
}

public enum CheckpointPolicy: String, Codable, Equatable, Sendable {
    case onEntry
    case afterInteraction
    case onExit
    case continuous
}

public struct ChapterSpec: Codable, Equatable, Sendable {
    public let schemaVersion: SchemaVersion
    public let id: ChapterID
    public let title: LocalizedStringSpec
    public let period: LocalizedStringSpec
    public let arcs: [ArcSpec]
    public let completionEffects: [WorldEffect]

    public init(
        schemaVersion: SchemaVersion,
        id: ChapterID,
        title: LocalizedStringSpec,
        period: LocalizedStringSpec,
        arcs: [ArcSpec],
        completionEffects: [WorldEffect]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.period = period
        self.arcs = arcs
        self.completionEffects = completionEffects
    }

    public func validate() throws {
        try requireNonempty(id, field: "chapter.id")
        try title.validate(field: "chapter.title")
        try period.validate(field: "chapter.period")
        guard schemaVersion.isValid else {
            throw ContentValidationError.invalidValue(
                field: "chapter.metadata",
                reason: "requires a valid schema version"
            )
        }
        guard (1 ... 3).contains(arcs.count) else {
            throw ContentValidationError.invalidCount(
                field: "chapter.arcs",
                expected: "1...3",
                actual: arcs.count
            )
        }
        try requireUnique(arcs.map(\.id))
        try requireUnique(completionEffects.map(\.id))
        guard !completionEffects.isEmpty else {
            throw ContentValidationError.invalidValue(
                field: "chapter.completionEffects",
                reason: "every completed chapter must leave a permanent world effect"
            )
        }
        for arc in arcs {
            try arc.validate()
        }
        for effect in completionEffects {
            try effect.validate()
        }
    }
}

public struct ArcSpec: Codable, Equatable, Identifiable, Sendable {
    public let id: ArcID
    public let title: LocalizedStringSpec
    public let targetDurationMinutes: Int
    public let situation: LocalizedStringSpec
    public let mechanism: LocalizedStringSpec
    public let turn: LocalizedStringSpec
    public let consequence: LocalizedStringSpec
    public let handoff: LocalizedStringSpec
    public let beats: [BeatSpec]

    public init(
        id: ArcID,
        title: LocalizedStringSpec,
        targetDurationMinutes: Int,
        situation: LocalizedStringSpec,
        mechanism: LocalizedStringSpec,
        turn: LocalizedStringSpec,
        consequence: LocalizedStringSpec,
        handoff: LocalizedStringSpec,
        beats: [BeatSpec]
    ) {
        self.id = id
        self.title = title
        self.targetDurationMinutes = targetDurationMinutes
        self.situation = situation
        self.mechanism = mechanism
        self.turn = turn
        self.consequence = consequence
        self.handoff = handoff
        self.beats = beats
    }

    public func validate() throws {
        try requireNonempty(id, field: "arc.id")
        guard (8 ... 15).contains(targetDurationMinutes) else {
            throw ContentValidationError.invalidValue(
                field: "arc.targetDurationMinutes",
                reason: "must be 8–15 minutes"
            )
        }
        try requireConsistentLocalizedStrings(
            [title, situation, mechanism, turn, consequence, handoff],
            field: "arc.dramaticContract"
        )
        guard !beats.isEmpty else {
            throw ContentValidationError.invalidCount(
                field: "arc.beats",
                expected: "at least one",
                actual: beats.count
            )
        }
        try requireUnique(beats.map(\.id))
        for beat in beats {
            try beat.validate()
        }
    }
}

public struct BeatSpec: Codable, Equatable, Identifiable, Sendable {
    public let id: BeatID
    public let sceneID: SceneID
    public let narrative: NarrativeText
    public let narrationCueIDs: [AudioCueID]
    public let interaction: InteractionSpec?
    public let completionEffects: [WorldEffect]
    public let checkpoint: CheckpointPolicy

    public init(
        id: BeatID,
        sceneID: SceneID,
        narrative: NarrativeText,
        narrationCueIDs: [AudioCueID] = [],
        interaction: InteractionSpec? = nil,
        completionEffects: [WorldEffect] = [],
        checkpoint: CheckpointPolicy
    ) {
        self.id = id
        self.sceneID = sceneID
        self.narrative = narrative
        self.narrationCueIDs = narrationCueIDs
        self.interaction = interaction
        self.completionEffects = completionEffects
        self.checkpoint = checkpoint
    }

    public func validate() throws {
        try requireNonempty(id, field: "beat.id")
        try requireNonempty(sceneID, field: "beat.sceneID")
        try requireUnique(narrationCueIDs)
        for cueID in narrationCueIDs {
            try requireNonempty(cueID, field: "beat.narrationCueIDs")
        }
        try narrative.validate(field: "beat.narrative")
        try requireUnique(completionEffects.map(\.id))
        for effect in completionEffects { try effect.validate() }
        if interaction != nil, !completionEffects.isEmpty {
            throw ContentValidationError.invalidValue(
                field: "beat.completionEffects",
                reason: "an interactive beat keeps its persistent effects on the interaction"
            )
        }
        try interaction?.validate()
    }
}

public struct TraceInteractionSpec: Codable, Equatable, Sendable {
    public static let maximumAnchorCount = 64

    public let anchors: [NormalizedPoint]
    /// Stable authored identities parallel to `anchors`.
    ///
    /// Nil preserves the original wire form. When present, every anchor has
    /// one identity so a scene can bind durable visual stages to route
    /// progress without inferring meaning from coordinates.
    public let anchorIDs: [String]?
    public let tolerance: Double

    public init(
        anchors: [NormalizedPoint],
        anchorIDs: [String]? = nil,
        tolerance: Double
    ) {
        self.anchors = anchors
        self.anchorIDs = anchorIDs
        self.tolerance = tolerance
    }
}

public struct AllocationDestination: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// The irreducible obligation for this use. Any units left after every
    /// minimum is met remain a real authored choice; there is no hidden exact
    /// allocation.
    public let minimumUnits: Int

    public init(id: String, minimumUnits: Int) {
        self.id = id
        self.minimumUnits = minimumUnits
    }
}

public struct AllocateInteractionSpec: Codable, Equatable, Sendable {
    public let resourceName: LocalizedStringSpec
    public let totalUnits: Int
    public let destinations: [AllocationDestination]

    public init(
        resourceName: LocalizedStringSpec,
        totalUnits: Int,
        destinations: [AllocationDestination]
    ) {
        self.resourceName = resourceName
        self.totalUnits = totalUnits
        self.destinations = destinations
    }
}

public struct AssemblyComponent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let targetSlot: String
    public let prerequisites: [String]

    public init(id: String, targetSlot: String, prerequisites: [String] = []) {
        self.id = id
        self.targetSlot = targetSlot
        self.prerequisites = prerequisites
    }
}

public struct AssembleInteractionSpec: Codable, Equatable, Sendable {
    public let components: [AssemblyComponent]

    public init(components: [AssemblyComponent]) {
        self.components = components
    }
}

public struct PressureForce: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let direction: Double
    public let initialMagnitude: Double
    public let userControllable: Bool

    public init(
        id: String,
        direction: Double,
        initialMagnitude: Double,
        userControllable: Bool
    ) {
        self.id = id
        self.direction = direction
        self.initialMagnitude = initialMagnitude
        self.userControllable = userControllable
    }
}

public struct PressureInteractionSpec: Codable, Equatable, Sendable {
    public let forces: [PressureForce]
    public let stableRange: ClosedRange<Double>
    public let requiredHoldMillis: Int64

    public init(
        forces: [PressureForce],
        stableRange: ClosedRange<Double>,
        requiredHoldMillis: Int64
    ) {
        self.forces = forces
        self.stableRange = stableRange
        self.requiredHoldMillis = requiredHoldMillis
    }
}

public struct TransformationStage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let controlID: String
    public let requiredAmount: Double

    public init(id: String, controlID: String, requiredAmount: Double) {
        self.id = id
        self.controlID = controlID
        self.requiredAmount = requiredAmount
    }
}

public struct TransformInteractionSpec: Codable, Equatable, Sendable {
    public let stages: [TransformationStage]

    public init(stages: [TransformationStage]) {
        self.stages = stages
    }
}

public struct InteractionSpec: Codable, Equatable, Identifiable, Sendable {
    public enum Grammar: Codable, Equatable, Sendable {
        case trace(TraceInteractionSpec)
        case allocate(AllocateInteractionSpec)
        case assemble(AssembleInteractionSpec)
        case pressure(PressureInteractionSpec)
        case transform(TransformInteractionSpec)
    }

    public let id: InteractionID
    public let prompt: LocalizedStringSpec
    public let grammar: Grammar
    public let completionEffects: [WorldEffect]
    public let accessibilityID: AccessibilityID

    public init(
        id: InteractionID,
        prompt: LocalizedStringSpec,
        grammar: Grammar,
        completionEffects: [WorldEffect],
        accessibilityID: AccessibilityID
    ) {
        self.id = id
        self.prompt = prompt
        self.grammar = grammar
        self.completionEffects = completionEffects
        self.accessibilityID = accessibilityID
    }

    private enum GrammarKind: String, Codable {
        case trace
        case allocate
        case assemble
        case pressure
        case transform
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case grammar
        case configuration
        case completionEffects
        case accessibilityID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(InteractionID.self, forKey: .id)
        prompt = try container.decode(LocalizedStringSpec.self, forKey: .prompt)
        completionEffects = try container.decode([WorldEffect].self, forKey: .completionEffects)
        accessibilityID = try container.decode(AccessibilityID.self, forKey: .accessibilityID)
        switch try container.decode(GrammarKind.self, forKey: .grammar) {
        case .trace:
            grammar = .trace(try container.decode(TraceInteractionSpec.self, forKey: .configuration))
        case .allocate:
            grammar = .allocate(try container.decode(AllocateInteractionSpec.self, forKey: .configuration))
        case .assemble:
            grammar = .assemble(try container.decode(AssembleInteractionSpec.self, forKey: .configuration))
        case .pressure:
            grammar = .pressure(try container.decode(PressureInteractionSpec.self, forKey: .configuration))
        case .transform:
            grammar = .transform(try container.decode(TransformInteractionSpec.self, forKey: .configuration))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(completionEffects, forKey: .completionEffects)
        try container.encode(accessibilityID, forKey: .accessibilityID)
        switch grammar {
        case let .trace(configuration):
            try container.encode(GrammarKind.trace, forKey: .grammar)
            try container.encode(configuration, forKey: .configuration)
        case let .allocate(configuration):
            try container.encode(GrammarKind.allocate, forKey: .grammar)
            try container.encode(configuration, forKey: .configuration)
        case let .assemble(configuration):
            try container.encode(GrammarKind.assemble, forKey: .grammar)
            try container.encode(configuration, forKey: .configuration)
        case let .pressure(configuration):
            try container.encode(GrammarKind.pressure, forKey: .grammar)
            try container.encode(configuration, forKey: .configuration)
        case let .transform(configuration):
            try container.encode(GrammarKind.transform, forKey: .grammar)
            try container.encode(configuration, forKey: .configuration)
        }
    }

    public func validate() throws {
        try requireNonempty(id, field: "interaction.id")
        try requireNonempty(accessibilityID, field: "interaction.accessibilityID")
        try prompt.validate(field: "interaction.prompt")
        try requireUnique(completionEffects.map(\.id))
        guard !completionEffects.isEmpty else {
            throw ContentValidationError.invalidValue(
                field: "interaction.completionEffects",
                reason: "a principal interaction must produce a historical consequence"
            )
        }
        for effect in completionEffects {
            try effect.validate()
        }

        switch grammar {
        case let .trace(spec):
            guard (2 ... TraceInteractionSpec.maximumAnchorCount)
                    .contains(spec.anchors.count),
                  spec.anchors.allSatisfy(\.isUnitPoint),
                  spec.tolerance > 0, spec.tolerance <= 1 else {
                throw ContentValidationError.invalidValue(
                    field: "interaction.trace",
                    reason: "requires 2–64 unit-space anchors and a valid tolerance"
                )
            }
            if let anchorIDs = spec.anchorIDs {
                guard anchorIDs.count == spec.anchors.count,
                      anchorIDs.allSatisfy(isStableStringIdentifier),
                      Set(anchorIDs).count == anchorIDs.count else {
                    throw ContentValidationError.invalidValue(
                        field: "interaction.trace.anchorIDs",
                        reason: "must provide one unique stable identity for every authored anchor"
                    )
                }
            }
        case let .allocate(spec):
            let destinationIDs = spec.destinations.map(\.id)
            let minimumTotal = spec.destinations.reduce(0) { $0 + $1.minimumUnits }
            try spec.resourceName.validate(field: "interaction.allocate.resourceName")
            guard spec.totalUnits > 0, spec.destinations.count >= 2,
                  destinationIDs.allSatisfy(isStableStringIdentifier),
                  Set(destinationIDs).count == destinationIDs.count,
                  spec.destinations.allSatisfy({ $0.minimumUnits > 0 }),
                  minimumTotal < spec.totalUnits else {
                throw ContentValidationError.invalidValue(
                    field: "interaction.allocate",
                    reason: "at least two positive obligations must leave authored surplus for a real allocation choice"
                )
            }
        case let .assemble(spec):
            let componentIDs = spec.components.map(\.id)
            let knownComponents = Set(componentIDs)
            guard !spec.components.isEmpty,
                  componentIDs.allSatisfy(isStableStringIdentifier),
                  Set(componentIDs).count == componentIDs.count,
                  spec.components.allSatisfy({ component in
                      isStableStringIdentifier(component.targetSlot)
                          && Set(component.prerequisites).count == component.prerequisites.count
                          && component.prerequisites.allSatisfy { prerequisite in
                              prerequisite != component.id && knownComponents.contains(prerequisite)
                          }
                  }),
                  !assemblyContainsCycle(spec.components) else {
                throw ContentValidationError.invalidValue(
                    field: "interaction.assemble",
                    reason: "requires unique components with valid, acyclic prerequisites"
                )
            }
        case let .pressure(spec):
            let forceIDs = spec.forces.map(\.id)
            let reachableRange = spec.forces.reduce(into: (minimum: 0.0, maximum: 0.0)) { range, force in
                if force.userControllable {
                    range.minimum += min(0, force.direction)
                    range.maximum += max(0, force.direction)
                } else {
                    let contribution = force.direction * force.initialMagnitude
                    range.minimum += contribution
                    range.maximum += contribution
                }
            }
            guard !spec.forces.isEmpty,
                  forceIDs.allSatisfy(isStableStringIdentifier),
                  Set(forceIDs).count == forceIDs.count,
                  spec.forces.allSatisfy({
                      $0.direction.isFinite && $0.direction != 0
                          && $0.initialMagnitude.isFinite
                          && (0 ... 1).contains($0.initialMagnitude)
                  }),
                  spec.stableRange.lowerBound.isFinite,
                  spec.stableRange.upperBound.isFinite,
                  spec.stableRange.upperBound >= reachableRange.minimum,
                  spec.stableRange.lowerBound <= reachableRange.maximum,
                  (100 ... 15_000).contains(spec.requiredHoldMillis),
                  spec.forces.contains(where: \.userControllable) else {
                throw ContentValidationError.invalidValue(
                    field: "interaction.pressure",
                    reason: "requires a reachable stable range, a controllable force and a valid hold duration"
                )
            }
        case let .transform(spec):
            let stageIDs = spec.stages.map(\.id)
            guard !spec.stages.isEmpty,
                  stageIDs.allSatisfy(isStableStringIdentifier),
                  Set(stageIDs).count == stageIDs.count,
                  spec.stages.allSatisfy({ isStableStringIdentifier($0.controlID) }),
                  spec.stages.allSatisfy({ $0.requiredAmount > 0 && $0.requiredAmount <= 1 }) else {
                throw ContentValidationError.invalidValue(
                    field: "interaction.transform",
                    reason: "requires ordered stages with unit-space thresholds"
                )
            }
        }
    }
}

private func assemblyContainsCycle(_ components: [AssemblyComponent]) -> Bool {
    let prerequisites = Dictionary(uniqueKeysWithValues: components.map { ($0.id, $0.prerequisites) })
    var visiting: Set<String> = []
    var visited: Set<String> = []

    func visit(_ id: String) -> Bool {
        if visiting.contains(id) { return true }
        if visited.contains(id) { return false }
        visiting.insert(id)
        for prerequisite in prerequisites[id] ?? [] where visit(prerequisite) {
            return true
        }
        visiting.remove(id)
        visited.insert(id)
        return false
    }

    return components.contains { visit($0.id) }
}

private func validNamedValues(_ values: [NamedValue]) -> Bool {
    let keys = values.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) }
    return keys.allSatisfy { !$0.isEmpty } && Set(keys).count == keys.count
}
