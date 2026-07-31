import ContentKit
import Foundation
import JourneyDomain

public enum SceneDirectManipulationPhase: String, Equatable, Sendable {
    case contact
    case lift
    case carrying
    case targetContact
    case slotApproach
    case resistance
    case snapBack
    case accepted
}

fileprivate enum SceneDirectManipulationDisposition: Equatable, Sendable {
    case pending
    case cancelled
    case rejectedByReducer
    case acceptedAllocation(destinationUnits: Int)
    case acceptedAssembly(componentID: String, slotID: String)
}

/// Public lifecycle projection for presentation-only direct manipulation.
/// The associated reducer payload remains private; scene-facing systems need
/// only to distinguish an unfinished gesture, a neutral cancellation, a
/// reducer rejection and an accepted action.
public enum SceneDirectManipulationOutcome: String, Equatable, Sendable {
    case pending
    case cancelled
    case rejectedByReducer
    case accepted
}

/// Ephemeral input reconstructed from the current gesture. It is deliberately
/// excluded from JourneyDomain snapshots; only accepted reducer state survives
/// a process death.
public struct SceneDirectManipulationState: Equatable, Sendable {
    public let phase: SceneDirectManipulationPhase
    /// Stable authored subject currently being handled. Allocate has one
    /// implicit resource and leaves this nil; Assemble carries a component ID.
    public let subjectID: String?
    /// The authored target from which an Assemble component was lifted.
    public let sourceTargetID: String?
    public let targetID: String?
    /// The authored domain slot represented by `targetID` for Assemble.
    public let slotID: String?
    public let masterPosition: NormalizedPoint?
    /// Difference between the user's first contact point and the authored
    /// source anchor, expressed in master-canvas coordinates. Assemble keeps
    /// this presentation-only value for the complete gesture so a component
    /// never jumps beneath the finger when it is picked up away from centre.
    public let grabOffset: SceneFrameVector?
    public let progress: Double
    fileprivate let sourceAlphaHitConfirmed: Bool
    fileprivate let disposition: SceneDirectManipulationDisposition

    public var outcome: SceneDirectManipulationOutcome {
        switch disposition {
        case .pending:
            .pending
        case .cancelled:
            .cancelled
        case .rejectedByReducer:
            .rejectedByReducer
        case .acceptedAllocation, .acceptedAssembly:
            .accepted
        }
    }

    private init(
        phase: SceneDirectManipulationPhase,
        subjectID: String? = nil,
        sourceTargetID: String? = nil,
        targetID: String? = nil,
        slotID: String? = nil,
        masterPosition: NormalizedPoint? = nil,
        grabOffset: SceneFrameVector? = nil,
        progress: Double,
        sourceAlphaHitConfirmed: Bool,
        disposition: SceneDirectManipulationDisposition
    ) {
        self.phase = phase
        self.subjectID = subjectID
        self.sourceTargetID = sourceTargetID
        self.targetID = targetID
        self.slotID = slotID
        self.masterPosition = masterPosition
        self.grabOffset = grabOffset
        self.progress = progress
        self.sourceAlphaHitConfirmed = sourceAlphaHitConfirmed
        self.disposition = disposition
    }

    static func contact(
        at masterPosition: NormalizedPoint,
        progress: Double,
        sourceAlphaHitConfirmed: Bool
    ) -> Self {
        Self(
            phase: .contact,
            masterPosition: masterPosition,
            progress: progress,
            sourceAlphaHitConfirmed: sourceAlphaHitConfirmed,
            disposition: .pending
        )
    }

    static func carrying(
        at masterPosition: NormalizedPoint,
        progress: Double,
        sourceAlphaHitConfirmed: Bool
    ) -> Self {
        Self(
            phase: .carrying,
            masterPosition: masterPosition,
            progress: progress,
            sourceAlphaHitConfirmed: sourceAlphaHitConfirmed,
            disposition: .pending
        )
    }

    static func targetContact(targetID: String, progress: Double) -> Self {
        Self(
            phase: .targetContact,
            targetID: targetID,
            progress: progress,
            sourceAlphaHitConfirmed: true,
            disposition: .pending
        )
    }

    static func resistanceAfterReducerRejection(
        targetID: String,
        progress: Double
    ) -> Self {
        Self(
            phase: .resistance,
            targetID: targetID,
            progress: progress,
            sourceAlphaHitConfirmed: true,
            disposition: .rejectedByReducer
        )
    }

    static func acceptedAfterReducer(
        targetID: String,
        destinationUnits: Int,
        progress: Double
    ) -> Self {
        Self(
            phase: .accepted,
            targetID: targetID,
            progress: progress,
            sourceAlphaHitConfirmed: true,
            disposition: .acceptedAllocation(destinationUnits: destinationUnits)
        )
    }

    static func assemblyContact(
        componentID: String,
        sourceTargetID: String,
        at masterPosition: NormalizedPoint,
        grabOffset: SceneFrameVector,
        progress: Double
    ) -> Self {
        Self(
            phase: .contact,
            subjectID: componentID,
            sourceTargetID: sourceTargetID,
            masterPosition: masterPosition,
            grabOffset: grabOffset,
            progress: progress,
            sourceAlphaHitConfirmed: false,
            disposition: .pending
        )
    }

    static func assemblyLift(
        componentID: String,
        sourceTargetID: String,
        at masterPosition: NormalizedPoint,
        grabOffset: SceneFrameVector,
        progress: Double
    ) -> Self {
        Self(
            phase: .lift,
            subjectID: componentID,
            sourceTargetID: sourceTargetID,
            masterPosition: masterPosition,
            grabOffset: grabOffset,
            progress: progress,
            sourceAlphaHitConfirmed: false,
            disposition: .pending
        )
    }

    static func assemblyCarrying(
        componentID: String,
        sourceTargetID: String,
        at masterPosition: NormalizedPoint,
        grabOffset: SceneFrameVector,
        progress: Double
    ) -> Self {
        Self(
            phase: .carrying,
            subjectID: componentID,
            sourceTargetID: sourceTargetID,
            masterPosition: masterPosition,
            grabOffset: grabOffset,
            progress: progress,
            sourceAlphaHitConfirmed: false,
            disposition: .pending
        )
    }

    static func assemblySlotApproach(
        componentID: String,
        sourceTargetID: String,
        targetID: String,
        slotID: String,
        at masterPosition: NormalizedPoint,
        grabOffset: SceneFrameVector,
        progress: Double
    ) -> Self {
        Self(
            phase: .slotApproach,
            subjectID: componentID,
            sourceTargetID: sourceTargetID,
            targetID: targetID,
            slotID: slotID,
            masterPosition: masterPosition,
            grabOffset: grabOffset,
            progress: progress,
            sourceAlphaHitConfirmed: false,
            disposition: .pending
        )
    }

    static func assemblySnapBack(
        componentID: String,
        sourceTargetID: String,
        targetID: String? = nil,
        slotID: String? = nil,
        from masterPosition: NormalizedPoint,
        grabOffset: SceneFrameVector,
        progress: Double,
        rejectedByReducer: Bool
    ) -> Self {
        Self(
            phase: .snapBack,
            subjectID: componentID,
            sourceTargetID: sourceTargetID,
            targetID: targetID,
            slotID: slotID,
            masterPosition: masterPosition,
            grabOffset: grabOffset,
            progress: progress,
            sourceAlphaHitConfirmed: false,
            disposition: rejectedByReducer ? .rejectedByReducer : .cancelled
        )
    }

    static func assemblyAcceptedAfterReducer(
        componentID: String,
        sourceTargetID: String,
        targetID: String,
        slotID: String,
        progress: Double
    ) -> Self {
        Self(
            phase: .accepted,
            subjectID: componentID,
            sourceTargetID: sourceTargetID,
            targetID: targetID,
            slotID: slotID,
            progress: progress,
            sourceAlphaHitConfirmed: false,
            disposition: .acceptedAssembly(
                componentID: componentID,
                slotID: slotID
            )
        )
    }
}

public struct SceneInteractionVisualState: Equatable, Sendable {
    let activeLayerVariants: [SceneLayerID: String]
    public let directManipulation: SceneDirectManipulationState?

    init(
        activeLayerVariants: [SceneLayerID: String],
        directManipulation: SceneDirectManipulationState?
    ) {
        self.activeLayerVariants = activeLayerVariants
        self.directManipulation = directManipulation
    }
}

public enum SceneInteractionVisualStateError: Error, Equatable, Sendable {
    case sceneHasNoStaticVisualState
    case missingVisualBinding
    case mismatchedInteraction
    case mismatchedGrammar
    case invalidRuntimeState
    case invalidAllocation
    case missingVariant(SceneLayerID)
    case invalidDirectManipulation
    case unknownDirectManipulationTarget(String)
}

public enum SceneInteractionVisualStateResolver {
    public static func staticState(for scene: SceneSpec) throws -> SceneInteractionVisualState {
        guard scene.interactionVisualBinding == nil,
              scene.layers.allSatisfy({ $0.stateVariants.isEmpty }) else {
            throw SceneInteractionVisualStateError.sceneHasNoStaticVisualState
        }
        return SceneInteractionVisualState(
            activeLayerVariants: [:],
            directManipulation: nil
        )
    }

    public static func resolve(
        scene: SceneSpec,
        interaction: InteractionSpec,
        runtimeState: InteractionRuntimeState,
        directManipulation: SceneDirectManipulationState? = nil
    ) throws -> SceneInteractionVisualState {
        try scene.validate()
        try scene.validateInteractionVisualBinding(to: interaction)
        guard runtimeState.interactionID == interaction.id else {
            throw SceneInteractionVisualStateError.mismatchedInteraction
        }
        guard let visualBinding = scene.interactionVisualBinding else {
            throw SceneInteractionVisualStateError.missingVisualBinding
        }

        switch (visualBinding, interaction.grammar, runtimeState.progress) {
        case let (.trace(binding), .trace, .trace(progress)):
            return try resolveTrace(
                scene: scene,
                binding: binding,
                interaction: interaction,
                runtimeState: runtimeState,
                progress: progress,
                directManipulation: directManipulation
            )
        case let (.allocate(binding), .allocate(configuration), .allocate(progress)):
            return try resolveAllocate(
                scene: scene,
                binding: binding,
                interaction: interaction,
                configuration: configuration,
                runtimeState: runtimeState,
                progress: progress,
                directManipulation: directManipulation
            )
        case let (.assemble(binding), .assemble(configuration), .assemble(progress)):
            return try resolveAssemble(
                scene: scene,
                binding: binding,
                interaction: interaction,
                configuration: configuration,
                runtimeState: runtimeState,
                progress: progress,
                directManipulation: directManipulation
            )
        case let (.pressure(binding), .pressure(configuration), .pressure(progress)):
            return try resolvePressure(
                scene: scene,
                binding: binding,
                interaction: interaction,
                configuration: configuration,
                runtimeState: runtimeState,
                progress: progress,
                directManipulation: directManipulation
            )
        case let (.transform(binding), .transform(configuration), .transform(progress)):
            return try resolveTransform(
                scene: scene,
                binding: binding,
                interaction: interaction,
                configuration: configuration,
                runtimeState: runtimeState,
                progress: progress,
                directManipulation: directManipulation
            )
        default:
            throw SceneInteractionVisualStateError.mismatchedGrammar
        }
    }

    private static func resolveTrace(
        scene: SceneSpec,
        binding: SceneTraceVisualBinding,
        interaction: InteractionSpec,
        runtimeState: InteractionRuntimeState,
        progress: TraceProgress,
        directManipulation: SceneDirectManipulationState?
    ) throws -> SceneInteractionVisualState {
        guard directManipulation == nil else {
            throw SceneInteractionVisualStateError.invalidDirectManipulation
        }
        try validateRuntimeState(runtimeState, interaction: interaction)

        let variantID: String
        switch runtimeState.phase {
        case .ready:
            variantID = binding.idleVariantID
        case .active:
            // A miss still records the attempted point. The route remains visibly
            // active while the reducer withholds the next anchor.
            guard progress.lastPoint != nil || progress.reachedAnchorCount == 0 else {
                throw SceneInteractionVisualStateError.invalidRuntimeState
            }
            if progress.reachedAnchorCount > 0,
               let reachedAnchorVariants = binding.reachedAnchorVariants {
                let reachedAnchorIndex = progress.reachedAnchorCount - 1
                guard reachedAnchorVariants.indices.contains(reachedAnchorIndex) else {
                    throw SceneInteractionVisualStateError.invalidRuntimeState
                }
                variantID = reachedAnchorVariants[reachedAnchorIndex].variantID
            } else {
                variantID = binding.tracingVariantID
            }
        case .complete:
            variantID = binding.completedVariantID
        }
        return try makeVisualState(
            scene: scene,
            variants: [binding.layerID: variantID]
        )
    }

    private static func resolveAllocate(
        scene: SceneSpec,
        binding: SceneAllocateVisualBinding,
        interaction: InteractionSpec,
        configuration: AllocateInteractionSpec,
        runtimeState: InteractionRuntimeState,
        progress: AllocateProgress,
        directManipulation: SceneDirectManipulationState?
    ) throws -> SceneInteractionVisualState {
        let knownDestinationIDs = Set(configuration.destinations.map(\.id))
        guard progress.allocations.count == knownDestinationIDs.count,
              Set(progress.allocations.map(\.destinationID)) == knownDestinationIDs,
              progress.allocations.allSatisfy({ $0.units >= 0 }) else {
            throw SceneInteractionVisualStateError.invalidRuntimeState
        }
        var allocatedUnits = 0
        for allocation in progress.allocations {
            let (next, overflow) = allocatedUnits.addingReportingOverflow(allocation.units)
            guard !overflow, next <= configuration.totalUnits else {
                throw SceneInteractionVisualStateError.invalidAllocation
            }
            allocatedUnits = next
        }
        if runtimeState.phase == .complete {
            guard allocatedUnits == configuration.totalUnits,
                  configuration.destinations.allSatisfy({ destination in
                (progress.allocations.first(where: {
                    $0.destinationID == destination.id
                })?.units ?? -1) >= destination.minimumUnits
            }) else {
                throw SceneInteractionVisualStateError.invalidAllocation
            }
        }

        let remainingUnits = configuration.totalUnits - allocatedUnits
        guard let resourceVariant = binding.resource.variantsByRemainingUnits.first(where: {
            remainingUnits <= $0.maximumRemainingUnits
        }) else {
            throw SceneInteractionVisualStateError.missingVariant(binding.resource.layerID)
        }
        var variants: [SceneLayerID: String] = [
            binding.resource.layerID: resourceVariant.variantID,
        ]
        for destination in binding.destinations {
            guard let units = progress.allocations.first(where: {
                $0.destinationID == destination.destinationID
            })?.units else {
                throw SceneInteractionVisualStateError.invalidRuntimeState
            }
            variants[destination.layerID] = if runtimeState.phase == .complete {
                destination.completedVariantID
            } else if units == 0 {
                destination.emptyVariantID
            } else {
                destination.receivingVariantID
            }
        }
        try validateDirectManipulation(
            directManipulation,
            binding: binding,
            progress: progress
        )
        try validateRuntimeState(runtimeState, interaction: interaction)
        return try makeVisualState(
            scene: scene,
            variants: variants,
            directManipulation: directManipulation
        )
    }

    private static func resolveAssemble(
        scene: SceneSpec,
        binding: SceneAssembleVisualBinding,
        interaction: InteractionSpec,
        configuration: AssembleInteractionSpec,
        runtimeState: InteractionRuntimeState,
        progress: AssembleProgress,
        directManipulation: SceneDirectManipulationState?
    ) throws -> SceneInteractionVisualState {
        try validateRuntimeState(runtimeState, interaction: interaction)

        let placedComponentIDs = Set(progress.placements.map(\.componentID))
        let componentByID = Dictionary(
            uniqueKeysWithValues: configuration.components.map { ($0.id, $0) }
        )
        var variants: [SceneLayerID: String] = [:]
        for componentBinding in binding.components {
            guard let component = componentByID[componentBinding.componentID] else {
                throw SceneInteractionVisualStateError.invalidRuntimeState
            }
            let variantID: String
            if placedComponentIDs.contains(component.id) {
                variantID = componentBinding.placedVariantID
            } else if component.prerequisites.allSatisfy(placedComponentIDs.contains) {
                variantID = componentBinding.availableVariantID
            } else {
                variantID = componentBinding.resistedVariantID
            }
            guard variants.updateValue(variantID, forKey: componentBinding.layerID) == nil else {
                throw SceneInteractionVisualStateError.invalidRuntimeState
            }
        }
        try validateAssembleDirectManipulation(
            directManipulation,
            binding: binding,
            configuration: configuration,
            progress: progress
        )
        return try makeVisualState(
            scene: scene,
            variants: variants,
            directManipulation: directManipulation
        )
    }

    private static func resolvePressure(
        scene: SceneSpec,
        binding: ScenePressureVisualBinding,
        interaction: InteractionSpec,
        configuration: PressureInteractionSpec,
        runtimeState: InteractionRuntimeState,
        progress: PressureProgress,
        directManipulation: SceneDirectManipulationState?
    ) throws -> SceneInteractionVisualState {
        guard directManipulation == nil else {
            throw SceneInteractionVisualStateError.invalidDirectManipulation
        }
        try validateRuntimeState(runtimeState, interaction: interaction)

        var netPressure = 0.0
        for force in configuration.forces {
            guard let magnitude = progress.values.first(where: {
                $0.forceID == force.id
            })?.magnitude else {
                throw SceneInteractionVisualStateError.invalidRuntimeState
            }
            let next = netPressure + force.direction * magnitude
            guard next.isFinite else {
                throw SceneInteractionVisualStateError.invalidRuntimeState
            }
            netPressure = next
        }

        let variantID: String
        switch runtimeState.phase {
        case .ready:
            variantID = binding.restingVariantID
        case .active where !configuration.stableRange.contains(netPressure):
            variantID = binding.brokenVariantID
        case .active where progress.stableMillis == 0:
            variantID = binding.resistingVariantID
        case .active, .complete:
            variantID = binding.stableVariantID
        }
        return try makeVisualState(
            scene: scene,
            variants: [binding.systemLayerID: variantID]
        )
    }

    private static func resolveTransform(
        scene: SceneSpec,
        binding: SceneTransformVisualBinding,
        interaction: InteractionSpec,
        configuration: TransformInteractionSpec,
        runtimeState: InteractionRuntimeState,
        progress: TransformProgress,
        directManipulation: SceneDirectManipulationState?
    ) throws -> SceneInteractionVisualState {
        guard directManipulation == nil else {
            throw SceneInteractionVisualStateError.invalidDirectManipulation
        }
        try validateRuntimeState(runtimeState, interaction: interaction)

        let bindingByStageID = Dictionary(
            uniqueKeysWithValues: binding.stages.map { ($0.stageID, $0) }
        )
        let indexedBindings = try configuration.stages.enumerated().map { index, stage in
            guard let stageBinding = bindingByStageID[stage.id] else {
                throw SceneInteractionVisualStateError.invalidRuntimeState
            }
            return (index: index, binding: stageBinding)
        }
        let bindingsByLayer = Dictionary(grouping: indexedBindings, by: { $0.binding.layerID })
        var variants: [SceneLayerID: String] = [:]

        for (layerID, layerStages) in bindingsByLayer {
            let ordered = layerStages.sorted { $0.index < $1.index }
            let selected: (index: Int, binding: SceneTransformationStageVisualBinding)
            if runtimeState.phase == .complete {
                guard let last = ordered.last else {
                    throw SceneInteractionVisualStateError.invalidRuntimeState
                }
                selected = last
            } else if let current = ordered.first(where: {
                $0.index == progress.completedStageCount
            }) {
                selected = current
            } else if let latestCompleted = ordered.last(where: {
                $0.index < progress.completedStageCount
            }) {
                selected = latestCompleted
            } else if let firstFuture = ordered.first {
                selected = firstFuture
            } else {
                throw SceneInteractionVisualStateError.invalidRuntimeState
            }

            let variantID: String
            if selected.index < progress.completedStageCount || runtimeState.phase == .complete {
                variantID = selected.binding.completedVariantID
            } else if selected.index == progress.completedStageCount,
                      progress.currentAmount > 0 {
                variantID = selected.binding.activeVariantID
            } else {
                variantID = selected.binding.beforeVariantID
            }
            variants[layerID] = variantID
        }
        return try makeVisualState(scene: scene, variants: variants)
    }

    private static func validateRuntimeState(
        _ runtimeState: InteractionRuntimeState,
        interaction: InteractionSpec
    ) throws {
        do {
            try SceneInteractionDriver.validate(state: runtimeState, against: interaction)
        } catch {
            throw SceneInteractionVisualStateError.invalidRuntimeState
        }
    }

    private static func makeVisualState(
        scene: SceneSpec,
        variants: [SceneLayerID: String],
        directManipulation: SceneDirectManipulationState? = nil
    ) throws -> SceneInteractionVisualState {
        let statefulLayers = scene.layers.filter { !$0.stateVariants.isEmpty }
        guard Set(variants.keys) == Set(statefulLayers.map(\.id)) else {
            throw SceneInteractionVisualStateError.invalidRuntimeState
        }
        for (layerID, variantID) in variants {
            guard let layer = statefulLayers.first(where: { $0.id == layerID }),
                  layer.stateVariants.contains(where: { $0.id == variantID }) else {
                throw SceneInteractionVisualStateError.missingVariant(layerID)
            }
        }
        return SceneInteractionVisualState(
            activeLayerVariants: variants,
            directManipulation: directManipulation
        )
    }

    private static func validateDirectManipulation(
        _ state: SceneDirectManipulationState?,
        binding: SceneAllocateVisualBinding,
        progress: AllocateProgress
    ) throws {
        guard let state else { return }
        guard state.progress.isFinite, (0 ... 1).contains(state.progress),
              state.masterPosition?.isUnitPoint ?? true,
              state.grabOffset == nil else {
            throw SceneInteractionVisualStateError.invalidDirectManipulation
        }
        let knownTargets = Set(binding.destinations.map(\.interactionTargetID))
        if let targetID = state.targetID, !knownTargets.contains(targetID) {
            throw SceneInteractionVisualStateError.unknownDirectManipulationTarget(targetID)
        }
        switch state.phase {
        case .contact:
            guard let position = state.masterPosition,
                  state.sourceAlphaHitConfirmed,
                  state.disposition == .pending,
                  point(position, isInside: binding.resource.hitRegion.path) else {
                throw SceneInteractionVisualStateError.invalidDirectManipulation
            }
        case .carrying:
            guard state.masterPosition != nil,
                  state.sourceAlphaHitConfirmed,
                  state.disposition == .pending else {
                throw SceneInteractionVisualStateError.invalidDirectManipulation
            }
        case .targetContact:
            guard state.targetID != nil, state.disposition == .pending else {
                throw SceneInteractionVisualStateError.invalidDirectManipulation
            }
        case .resistance:
            guard state.targetID != nil,
                  state.disposition == .rejectedByReducer else {
                throw SceneInteractionVisualStateError.invalidDirectManipulation
            }
        case .accepted:
            guard let targetID = state.targetID,
                  let destination = binding.destinations.first(where: {
                      $0.interactionTargetID == targetID
                  }),
                  case let .acceptedAllocation(expectedUnits) = state.disposition,
                  progress.allocations.first(where: {
                      $0.destinationID == destination.destinationID
                  })?.units == expectedUnits,
                  expectedUnits > 0 else {
                throw SceneInteractionVisualStateError.invalidDirectManipulation
            }
        case .lift, .slotApproach, .snapBack:
            throw SceneInteractionVisualStateError.invalidDirectManipulation
        }
    }

    private static func validateAssembleDirectManipulation(
        _ state: SceneDirectManipulationState?,
        binding: SceneAssembleVisualBinding,
        configuration: AssembleInteractionSpec,
        progress: AssembleProgress
    ) throws {
        guard let state else { return }
        guard state.progress.isFinite, (0 ... 1).contains(state.progress),
              state.masterPosition?.isUnitPoint ?? true,
              state.grabOffset.map({ offset in
                  offset.dx.isFinite && offset.dy.isFinite
                      && (-1 ... 1).contains(offset.dx)
                      && (-1 ... 1).contains(offset.dy)
              }) ?? true,
              !state.sourceAlphaHitConfirmed,
              let componentID = state.subjectID,
              let sourceTargetID = state.sourceTargetID,
              let sourceBinding = binding.components.first(where: {
                  $0.componentID == componentID
                      && $0.sourceInteractionTargetID == sourceTargetID
              }),
              sourceBinding.slotInteractionTargetID != nil,
              configuration.components.contains(where: { $0.id == componentID }) else {
            throw SceneInteractionVisualStateError.invalidDirectManipulation
        }
        _ = sourceBinding

        let placement = progress.placements.first(where: {
            $0.componentID == componentID
        })
        let destination: (
            visual: SceneAssemblyComponentVisualBinding,
            component: AssemblyComponent
        )? = if let targetID = state.targetID {
            try {
                guard let visual = binding.components.first(where: {
                    $0.slotInteractionTargetID == targetID
                }), let component = configuration.components.first(where: {
                    $0.id == visual.componentID
                }), component.targetSlot == state.slotID else {
                    throw SceneInteractionVisualStateError.unknownDirectManipulationTarget(
                        targetID
                    )
                }
                return (visual, component)
            }()
        } else {
            nil
        }

        switch state.phase {
        case .contact, .lift, .carrying:
            guard placement == nil,
                  state.targetID == nil,
                  state.slotID == nil,
                  state.masterPosition != nil,
                  state.grabOffset != nil,
                  state.disposition == .pending else {
                throw SceneInteractionVisualStateError.invalidDirectManipulation
            }

        case .slotApproach:
            guard placement == nil,
                  destination != nil,
                  state.masterPosition != nil,
                  state.grabOffset != nil,
                  state.disposition == .pending else {
                throw SceneInteractionVisualStateError.invalidDirectManipulation
            }

        case .snapBack:
            guard placement == nil,
                  state.masterPosition != nil,
                  state.grabOffset != nil else {
                throw SceneInteractionVisualStateError.invalidDirectManipulation
            }
            switch state.disposition {
            case .cancelled:
                guard state.targetID == nil, state.slotID == nil else {
                    throw SceneInteractionVisualStateError.invalidDirectManipulation
                }
            case .rejectedByReducer:
                guard destination != nil else {
                    throw SceneInteractionVisualStateError.invalidDirectManipulation
                }
            default:
                throw SceneInteractionVisualStateError.invalidDirectManipulation
            }

        case .accepted:
            guard let destination,
                  let placement,
                  placement.slotID == state.slotID,
                  case let .acceptedAssembly(acceptedComponentID, acceptedSlotID) =
                    state.disposition,
                  acceptedComponentID == componentID,
                  acceptedSlotID == placement.slotID,
                  destination.component.targetSlot == placement.slotID,
                  state.grabOffset == nil else {
                throw SceneInteractionVisualStateError.invalidDirectManipulation
            }

        case .targetContact, .resistance:
            throw SceneInteractionVisualStateError.invalidDirectManipulation
        }
    }

    private static func point(
        _ point: NormalizedPoint,
        isInside path: [NormalizedPoint]
    ) -> Bool {
        guard path.count >= 3 else { return false }
        var inside = false
        var previous = path[path.count - 1]
        for current in path {
            let cross = (point.y - previous.y) * (current.x - previous.x)
                - (point.x - previous.x) * (current.y - previous.y)
            let onSegment = abs(cross) <= 0.000_000_001
                && point.x >= min(previous.x, current.x) - 0.000_000_001
                && point.x <= max(previous.x, current.x) + 0.000_000_001
                && point.y >= min(previous.y, current.y) - 0.000_000_001
                && point.y <= max(previous.y, current.y) + 0.000_000_001
            if onSegment { return true }
            if (current.y > point.y) != (previous.y > point.y) {
                let intersectionX = (previous.x - current.x)
                    * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < intersectionX { inside.toggle() }
            }
            previous = current
        }
        return inside
    }
}

public enum SceneFrameRequestFactoryError: Error, Equatable, Sendable {
    case missingSceneVisualSnapshot
    case unsupportedSceneVisualSnapshotVersion(Int)
    case mismatchedScene
    case missingInteraction
    case unexpectedInteraction
}

/// Couples the authored camera rail to durable causal progress. The camera is
/// presentation derived: it adds no second save authority, and restoration
/// reconstructs the same view from the interaction reducer state.
public enum SceneInteractionCameraProgressResolver {
    public static func resolve(
        authoredAnchor: Double,
        interaction: InteractionSpec?,
        runtimeState: InteractionRuntimeState?
    ) -> Double {
        let boundedAuthoredAnchor = min(max(authoredAnchor, 0), 1)
        guard let interaction, let runtimeState,
              runtimeState.interactionID == interaction.id else {
            return boundedAuthoredAnchor
        }
        if runtimeState.phase == .complete {
            return 1
        }

        let causalProgress: Double
        switch (interaction.grammar, runtimeState.progress) {
        case let (.trace(configuration), .trace(progress)):
            guard !configuration.anchors.isEmpty else {
                return boundedAuthoredAnchor
            }
            causalProgress = Double(progress.reachedAnchorCount)
                / Double(configuration.anchors.count)

        case let (.allocate(configuration), .allocate(progress)):
            guard configuration.totalUnits > 0 else {
                return boundedAuthoredAnchor
            }
            let allocatedUnits = progress.allocations.reduce(0) {
                $0 + $1.units
            }
            causalProgress = Double(allocatedUnits)
                / Double(configuration.totalUnits)

        case let (.assemble(configuration), .assemble(progress)):
            guard !configuration.components.isEmpty else {
                return boundedAuthoredAnchor
            }
            causalProgress = Double(progress.placements.count)
                / Double(configuration.components.count)

        case let (.pressure(configuration), .pressure(progress)):
            guard configuration.requiredHoldMillis > 0 else {
                return boundedAuthoredAnchor
            }
            causalProgress = Double(progress.stableMillis)
                / Double(configuration.requiredHoldMillis)

        case let (.transform(configuration), .transform(progress)):
            guard configuration.stages.indices.contains(
                progress.completedStageCount
            ) else {
                return boundedAuthoredAnchor
            }
            let stage = configuration.stages[
                progress.completedStageCount
            ]
            let withinStage = stage.requiredAmount > 0
                ? progress.currentAmount / stage.requiredAmount : 0
            causalProgress = (
                Double(progress.completedStageCount)
                    + min(max(withinStage, 0), 1)
            ) / Double(configuration.stages.count)

        default:
            return boundedAuthoredAnchor
        }
        return max(
            boundedAuthoredAnchor,
            min(max(causalProgress, 0), 1)
        )
    }
}

public enum SceneFrameRequestFactory {
    public static func make(
        scene: SceneSpec,
        session: ChapterSession,
        viewportCropID: String,
        interaction: InteractionSpec? = nil,
        directManipulation: SceneDirectManipulationState? = nil,
        reduceMotion: Bool
    ) throws -> SceneFrameRequest {
        guard let snapshot = session.sceneVisualSnapshot else {
            throw SceneFrameRequestFactoryError.missingSceneVisualSnapshot
        }
        guard snapshot.formatVersion == SceneVisualSnapshot.currentFormatVersion else {
            throw SceneFrameRequestFactoryError.unsupportedSceneVisualSnapshotVersion(
                snapshot.formatVersion
            )
        }
        guard snapshot.sceneID == scene.id else {
            throw SceneFrameRequestFactoryError.mismatchedScene
        }

        let visualState: SceneInteractionVisualState
        if scene.interactionVisualBinding != nil {
            guard let interaction, let runtimeState = session.interaction else {
                throw SceneFrameRequestFactoryError.missingInteraction
            }
            visualState = try SceneInteractionVisualStateResolver.resolve(
                scene: scene,
                interaction: interaction,
                runtimeState: runtimeState,
                directManipulation: directManipulation
            )
        } else {
            guard interaction == nil, session.interaction == nil,
                  directManipulation == nil else {
                throw SceneFrameRequestFactoryError.unexpectedInteraction
            }
            visualState = try SceneInteractionVisualStateResolver.staticState(for: scene)
        }
        let cameraProgress = SceneInteractionCameraProgressResolver.resolve(
            authoredAnchor: session.cameraAnchor,
            interaction: interaction,
            runtimeState: session.interaction
        )

        return SceneFrameRequest(
            viewportCropID: viewportCropID,
            cameraProgress: cameraProgress,
            visualState: visualState,
            deterministicTick: snapshot.deterministicTick,
            reduceMotion: reduceMotion
        )
    }
}
