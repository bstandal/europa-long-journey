import ContentKit
import Foundation
import JourneyDomain

public enum SceneTouchIntent: Equatable, Sendable {
    case trace(viewportPoint: SceneFramePoint)
    case allocateContact(viewportPoint: SceneFramePoint, progress: Double)
    case allocateCarry(
        sourceViewportPoint: SceneFramePoint,
        currentViewportPoint: SceneFramePoint,
        progress: Double
    )
    case allocateDrop(
        sourceViewportPoint: SceneFramePoint,
        destinationViewportPoint: SceneFramePoint,
        destinationUnits: Int,
        progress: Double
    )
    /// Returns one authored semantic allocation step from a destination to
    /// the visible resource. The resolver derives the absolute domain value
    /// from the current durable state and the destination's exact VoiceOver
    /// decrement binding; callers cannot invent a parallel touch step.
    case allocateReturn(
        destinationViewportPoint: SceneFramePoint,
        resourceViewportPoint: SceneFramePoint,
        progress: Double
    )
    case assembleContact(viewportPoint: SceneFramePoint, progress: Double)
    case assembleLift(
        sourceViewportPoint: SceneFramePoint,
        currentViewportPoint: SceneFramePoint,
        progress: Double
    )
    case assembleCarry(
        sourceViewportPoint: SceneFramePoint,
        currentViewportPoint: SceneFramePoint,
        progress: Double
    )
    case assembleSlotApproach(
        sourceViewportPoint: SceneFramePoint,
        slotViewportPoint: SceneFramePoint,
        progress: Double
    )
    case assembleDrop(
        sourceViewportPoint: SceneFramePoint,
        slotViewportPoint: SceneFramePoint,
        progress: Double
    )
    case assembleCancel(
        sourceViewportPoint: SceneFramePoint,
        currentViewportPoint: SceneFramePoint,
        progress: Double
    )
    case activateTarget(viewportPoint: SceneFramePoint)
    case adjustTarget(viewportPoint: SceneFramePoint, amount: Double)
    case holdPressure(elapsedMillis: Int64)
    case commitAllocation
}

/// Filters transport-level duplicate samples from one physical Trace gesture.
/// A stationary endpoint emitted twice has no new historical meaning and must
/// not become reducer resistance. Returning to an earlier point after real
/// movement remains admissible, and a new gesture begins with fresh authority.
public struct TraceTouchSampleAdmissionPolicy: Equatable, Sendable {
    private var lastObservedPoint: SceneFramePoint?

    public init() {}

    public mutating func admits(_ point: SceneFramePoint) -> Bool {
        guard point != lastObservedPoint else { return false }
        lastObservedPoint = point
        return true
    }

    public mutating func endGesture() {
        lastObservedPoint = nil
    }
}

/// Marks an authored Trace-anchor contact that must survive bounded transport
/// coalescing. The absolute index stays meaningful while earlier admitted
/// samples are still waiting for their durable commits.
public struct TraceDeferredSamplePriority: Equatable, Sendable {
    public let protectedAnchorIndex: Int?

    public init(protectedAnchorIndex: Int? = nil) {
        self.protectedAnchorIndex = protectedAnchorIndex
    }

    public static func classify(
        masterPoint: NormalizedPoint,
        configuration: TraceInteractionSpec,
        reachedAnchorCount: Int
    ) -> Self {
        guard (0 ... configuration.anchors.count).contains(reachedAnchorCount)
        else { return Self() }
        let protectedIndex = configuration.anchors.indices
            .dropFirst(reachedAnchorCount)
            .first { index in
                masterPoint.distance(to: configuration.anchors[index])
                    <= configuration.tolerance
        }
        return Self(protectedAnchorIndex: protectedIndex)
    }

    /// Uses the same authored target hit and moving-layer inverse projection
    /// as `SceneTouchActionResolver`. Transport coalescing must not classify a
    /// visible Trace contact in still camera space while the reducer will
    /// later receive its parallax- and wind-corrected master position.
    public static func classify(
        viewportPoint: SceneFramePoint,
        frame: SceneFramePlan,
        visual: SceneTraceVisualBinding,
        configuration: TraceInteractionSpec,
        reachedAnchorCount: Int
    ) -> Self {
        let hit: SceneTouchTargetHit
        do {
            guard let resolved = try SceneTouchGeometryResolver.target(
                at: viewportPoint,
                in: frame
            ) else { return Self() }
            hit = resolved
        } catch {
            return Self()
        }
        guard hit.interactionTargetID == visual.interactionTargetID,
              hit.layerID == visual.layerID else {
            return Self()
        }
        return classify(
            masterPoint: hit.masterPosition,
            configuration: configuration,
            reachedAnchorCount: reachedAnchorCount
        )
    }
}

public struct SceneTouchActionResolution: Equatable, Sendable {
    public let action: InteractionAction?
    public let directManipulation: SceneDirectManipulationState?
    public let targetID: String?
    public let progress: Double

    public init(
        action: InteractionAction?,
        directManipulation: SceneDirectManipulationState?,
        targetID: String?,
        progress: Double
    ) {
        self.action = action
        self.directManipulation = directManipulation
        self.targetID = targetID
        self.progress = progress
    }
}

public enum SceneTouchActionResolverError: Error, Equatable, Sendable {
    case mismatchedScene
    case mismatchedInteraction
    case mismatchedVisualBinding
    case mismatchedGrammar
    case invalidRuntimeState
    case invalidProgress
    case invalidAmount
    case targetNotHit
    case wrongTarget(String)
    case alphaSamplerRequired
    case actionRequired
    case previewActionMismatch
    case feedbackNotApplicable
    case assemblyDirectPlacementUnavailable
    case invalidAssemblyGrabOffset
}

/// Converts concrete scene gestures into the same `InteractionAction` values
/// used by VoiceOver. It owns no reducer and no persistent state. Allocate and
/// Assemble manipulation remain ephemeral until a pure preview and durable
/// Journey commit have accepted the returned action.
public enum SceneTouchActionResolver {
    public static func resolve(
        _ intent: SceneTouchIntent,
        scene: SceneSpec,
        interaction: InteractionSpec,
        runtimeState: InteractionRuntimeState,
        frame: SceneFramePlan,
        accessibility: AccessibilitySpec? = nil,
        alphaSampler: (any SceneAlphaMaskSampling)? = nil
    ) throws -> SceneTouchActionResolution {
        guard frame.sceneID == scene.id else {
            throw SceneTouchActionResolverError.mismatchedScene
        }
        guard runtimeState.interactionID == interaction.id else {
            throw SceneTouchActionResolverError.mismatchedInteraction
        }
        guard let binding = scene.interactionVisualBinding else {
            throw SceneTouchActionResolverError.mismatchedVisualBinding
        }
        do {
            try scene.validateInteractionVisualBinding(to: interaction)
        } catch {
            throw SceneTouchActionResolverError.mismatchedVisualBinding
        }

        switch (intent, binding, interaction.grammar, runtimeState.progress) {
        case let (
            .trace(viewportPoint),
            .trace(visual),
            .trace(configuration),
            .trace(progress)
        ):
            let hit = try requireTarget(at: viewportPoint, in: frame)
            guard hit.interactionTargetID == visual.interactionTargetID else {
                throw SceneTouchActionResolverError.wrongTarget(hit.interactionTargetID)
            }
            let canonicalPoint: NormalizedPoint
            if progress.reachedAnchorCount < configuration.anchors.count {
                let nextAnchor = configuration.anchors[progress.reachedAnchorCount]
                if hit.masterPosition.distance(to: nextAnchor)
                    <= configuration.tolerance {
                    canonicalPoint = nextAnchor
                } else if progress.reachedAnchorCount > 0 {
                    let previousAnchor = configuration.anchors[
                        progress.reachedAnchorCount - 1
                    ]
                    if progress.lastPoint == previousAnchor,
                       hit.masterPosition.distance(to: previousAnchor)
                        <= configuration.tolerance {
                        // SwiftUI may emit a slightly shifted endpoint after
                        // the reducer has already accepted an anchor. While
                        // the finger remains inside that authored tolerance
                        // field, it carries no new causal meaning. Once it
                        // leaves the field the ordinary Trace action resumes;
                        // returning later is therefore real resistance.
                        return SceneTouchActionResolution(
                            action: nil,
                            directManipulation: nil,
                            targetID: hit.interactionTargetID,
                            progress: 0
                        )
                    }
                    canonicalPoint = hit.masterPosition
                } else {
                    canonicalPoint = hit.masterPosition
                }
            } else {
                canonicalPoint = hit.masterPosition
            }
            return SceneTouchActionResolution(
                action: .trace(canonicalPoint),
                directManipulation: nil,
                targetID: hit.interactionTargetID,
                progress: 0
            )

        case let (
            .allocateContact(viewportPoint, progress),
            .allocate(visual),
            .allocate,
            .allocate
        ):
            try requireProgress(progress)
            let contact = try requireSourceContact(
                at: viewportPoint,
                frame: frame,
                visual: visual,
                alphaSampler: alphaSampler
            )
            return SceneTouchActionResolution(
                action: nil,
                directManipulation: .contact(
                    at: contact.masterPosition,
                    progress: progress,
                    sourceAlphaHitConfirmed: true
                ),
                targetID: nil,
                progress: progress
            )

        case let (
            .allocateCarry(sourcePoint, currentPoint, progress),
            .allocate(visual),
            .allocate,
            .allocate
        ):
            try requireProgress(progress)
            _ = try requireSourceContact(
                at: sourcePoint,
                frame: frame,
                visual: visual,
                alphaSampler: alphaSampler
            )
            let currentMasterPoint = try SceneTouchGeometryResolver.masterPoint(
                for: currentPoint,
                in: frame,
                boundTo: visual.resource.layerID
            )
            return SceneTouchActionResolution(
                action: nil,
                directManipulation: .carrying(
                    at: currentMasterPoint,
                    progress: progress,
                    sourceAlphaHitConfirmed: true
                ),
                targetID: nil,
                progress: progress
            )

        case let (
            .allocateDrop(sourcePoint, destinationPoint, destinationUnits, progress),
            .allocate(visual),
            .allocate(configuration),
            .allocate(allocation)
        ):
            try requireProgress(progress)
            guard destinationUnits > 0, destinationUnits <= configuration.totalUnits else {
                throw SceneTouchActionResolverError.invalidAmount
            }
            _ = try requireSourceContact(
                at: sourcePoint,
                frame: frame,
                visual: visual,
                alphaSampler: alphaSampler
            )
            let hit = try requireTarget(at: destinationPoint, in: frame)
            guard let destination = visual.destinations.first(where: {
                $0.interactionTargetID == hit.interactionTargetID
            }) else {
                throw SceneTouchActionResolverError.wrongTarget(hit.interactionTargetID)
            }
            guard allocation.allocations.first(where: {
                $0.destinationID == destination.destinationID
            })?.units != destinationUnits else {
                throw SceneTouchActionResolverError.invalidAmount
            }
            return SceneTouchActionResolution(
                action: .allocate(
                    destinationID: destination.destinationID,
                    units: destinationUnits
                ),
                directManipulation: .targetContact(
                    targetID: hit.interactionTargetID,
                    progress: progress
                ),
                targetID: hit.interactionTargetID,
                progress: progress
            )

        case let (
            .allocateReturn(destinationPoint, resourcePoint, progress),
            .allocate(visual),
            .allocate,
            .allocate(allocation)
        ):
            try requireProgress(progress)
            let hit = try requireTarget(at: destinationPoint, in: frame)
            guard let destination = visual.destinations.first(where: {
                $0.interactionTargetID == hit.interactionTargetID
            }) else {
                throw SceneTouchActionResolverError.wrongTarget(hit.interactionTargetID)
            }
            _ = try requireSourceContact(
                at: resourcePoint,
                frame: frame,
                visual: visual,
                alphaSampler: alphaSampler
            )
            guard let accessibility,
                  let element = accessibility.elements.first(where: {
                      $0.id == hit.accessibilityElementID
                  }) else {
                throw SceneTouchActionResolverError.actionRequired
            }
            let decrementSteps = element.actions.compactMap { action -> Int? in
                guard action.kind == .decrement,
                      case let .allocate(destinationID, unitsPerStep) = action.token,
                      destinationID == destination.destinationID else {
                    return nil
                }
                return unitsPerStep
            }
            guard decrementSteps.count == 1,
                  let unitsPerStep = decrementSteps.first,
                  let current = allocation.allocations.first(where: {
                      $0.destinationID == destination.destinationID
                  })?.units else {
                throw SceneTouchActionResolverError.actionRequired
            }
            let next = max(current - unitsPerStep, 0)
            guard next != current else {
                throw SceneTouchActionResolverError.invalidAmount
            }
            return SceneTouchActionResolution(
                action: .allocate(
                    destinationID: destination.destinationID,
                    units: next
                ),
                directManipulation: .targetContact(
                    targetID: hit.interactionTargetID,
                    progress: progress
                ),
                targetID: hit.interactionTargetID,
                progress: progress
            )

        case let (
            .assembleContact(viewportPoint, progress),
            .assemble(visual),
            .assemble(configuration),
            .assemble(assembly)
        ):
            try requireProgress(progress)
            let source = try requireAssemblyComponent(
                at: viewportPoint,
                frame: frame,
                visual: visual,
                configuration: configuration,
                progress: assembly
            )
            let grabOffset = try requireAssemblyGrabOffset(
                sourceTargetID: source.visual.sourceInteractionTargetID,
                layerID: source.visual.layerID,
                sourceMasterPosition: source.hit.masterPosition,
                frame: frame
            )
            return SceneTouchActionResolution(
                action: nil,
                directManipulation: .assemblyContact(
                    componentID: source.component.id,
                    sourceTargetID: source.visual.sourceInteractionTargetID,
                    at: source.hit.masterPosition,
                    grabOffset: grabOffset,
                    progress: progress
                ),
                targetID: source.visual.sourceInteractionTargetID,
                progress: progress
            )

        case let (
            .assembleLift(sourcePoint, currentPoint, progress),
            .assemble(visual),
            .assemble(configuration),
            .assemble(assembly)
        ):
            try requireProgress(progress)
            let source = try requireAssemblyComponent(
                at: sourcePoint,
                frame: frame,
                visual: visual,
                configuration: configuration,
                progress: assembly
            )
            let current = try SceneTouchGeometryResolver.masterPoint(
                for: currentPoint,
                in: frame,
                boundTo: source.visual.layerID
            )
            let grabOffset = try requireAssemblyGrabOffset(
                sourceTargetID: source.visual.sourceInteractionTargetID,
                layerID: source.visual.layerID,
                sourceMasterPosition: source.hit.masterPosition,
                frame: frame
            )
            return SceneTouchActionResolution(
                action: nil,
                directManipulation: .assemblyLift(
                    componentID: source.component.id,
                    sourceTargetID: source.visual.sourceInteractionTargetID,
                    at: current,
                    grabOffset: grabOffset,
                    progress: progress
                ),
                targetID: nil,
                progress: progress
            )

        case let (
            .assembleCarry(sourcePoint, currentPoint, progress),
            .assemble(visual),
            .assemble(configuration),
            .assemble(assembly)
        ):
            try requireProgress(progress)
            let source = try requireAssemblyComponent(
                at: sourcePoint,
                frame: frame,
                visual: visual,
                configuration: configuration,
                progress: assembly
            )
            let current = try SceneTouchGeometryResolver.masterPoint(
                for: currentPoint,
                in: frame,
                boundTo: source.visual.layerID
            )
            let grabOffset = try requireAssemblyGrabOffset(
                sourceTargetID: source.visual.sourceInteractionTargetID,
                layerID: source.visual.layerID,
                sourceMasterPosition: source.hit.masterPosition,
                frame: frame
            )
            return SceneTouchActionResolution(
                action: nil,
                directManipulation: .assemblyCarrying(
                    componentID: source.component.id,
                    sourceTargetID: source.visual.sourceInteractionTargetID,
                    at: current,
                    grabOffset: grabOffset,
                    progress: progress
                ),
                targetID: nil,
                progress: progress
            )

        case let (
            .assembleSlotApproach(sourcePoint, slotPoint, progress),
            .assemble(visual),
            .assemble(configuration),
            .assemble(assembly)
        ):
            try requireProgress(progress)
            let source = try requireAssemblyComponent(
                at: sourcePoint,
                frame: frame,
                visual: visual,
                configuration: configuration,
                progress: assembly
            )
            let destination = try requireAssemblySlot(
                at: slotPoint,
                frame: frame,
                visual: visual,
                configuration: configuration
            )
            let grabOffset = try requireAssemblyGrabOffset(
                sourceTargetID: source.visual.sourceInteractionTargetID,
                layerID: source.visual.layerID,
                sourceMasterPosition: source.hit.masterPosition,
                frame: frame
            )
            return SceneTouchActionResolution(
                action: nil,
                directManipulation: .assemblySlotApproach(
                    componentID: source.component.id,
                    sourceTargetID: source.visual.sourceInteractionTargetID,
                    targetID: destination.slotTargetID,
                    slotID: destination.component.targetSlot,
                    at: destination.hit.masterPosition,
                    grabOffset: grabOffset,
                    progress: progress
                ),
                targetID: destination.slotTargetID,
                progress: progress
            )

        case let (
            .assembleDrop(sourcePoint, slotPoint, progress),
            .assemble(visual),
            .assemble(configuration),
            .assemble(assembly)
        ):
            try requireProgress(progress)
            let source = try requireAssemblyComponent(
                at: sourcePoint,
                frame: frame,
                visual: visual,
                configuration: configuration,
                progress: assembly
            )
            let destination = try requireAssemblySlot(
                at: slotPoint,
                frame: frame,
                visual: visual,
                configuration: configuration
            )
            let grabOffset = try requireAssemblyGrabOffset(
                sourceTargetID: source.visual.sourceInteractionTargetID,
                layerID: source.visual.layerID,
                sourceMasterPosition: source.hit.masterPosition,
                frame: frame
            )
            return SceneTouchActionResolution(
                action: .place(
                    componentID: source.component.id,
                    slotID: destination.component.targetSlot
                ),
                directManipulation: .assemblySlotApproach(
                    componentID: source.component.id,
                    sourceTargetID: source.visual.sourceInteractionTargetID,
                    targetID: destination.slotTargetID,
                    slotID: destination.component.targetSlot,
                    at: destination.hit.masterPosition,
                    grabOffset: grabOffset,
                    progress: progress
                ),
                targetID: destination.slotTargetID,
                progress: progress
            )

        case let (
            .assembleCancel(sourcePoint, currentPoint, progress),
            .assemble(visual),
            .assemble(configuration),
            .assemble(assembly)
        ):
            try requireProgress(progress)
            let source = try requireAssemblyComponent(
                at: sourcePoint,
                frame: frame,
                visual: visual,
                configuration: configuration,
                progress: assembly
            )
            let current = try SceneTouchGeometryResolver.masterPoint(
                for: currentPoint,
                in: frame,
                boundTo: source.visual.layerID
            )
            let grabOffset = try requireAssemblyGrabOffset(
                sourceTargetID: source.visual.sourceInteractionTargetID,
                layerID: source.visual.layerID,
                sourceMasterPosition: source.hit.masterPosition,
                frame: frame
            )
            return SceneTouchActionResolution(
                action: nil,
                directManipulation: .assemblySnapBack(
                    componentID: source.component.id,
                    sourceTargetID: source.visual.sourceInteractionTargetID,
                    from: current,
                    grabOffset: grabOffset,
                    progress: progress,
                    rejectedByReducer: false
                ),
                targetID: nil,
                progress: progress
            )

        case (.activateTarget, .assemble, .assemble, .assemble):
            // A physical source tap cannot stand in for carrying material to a
            // distinct bearing point. VoiceOver activation remains the direct
            // semantic `.place` path through SemanticInteractionAdapter.
            throw SceneTouchActionResolverError.assemblyDirectPlacementUnavailable

        case let (
            .adjustTarget(viewportPoint, amount),
            .pressure(visual),
            .pressure(configuration),
            .pressure
        ):
            try requireAmount(amount)
            let hit = try requireTarget(at: viewportPoint, in: frame)
            guard let forceVisual = visual.forces.first(where: {
                $0.interactionTargetID == hit.interactionTargetID
            }), let force = configuration.forces.first(where: {
                $0.id == forceVisual.forceID && $0.userControllable
            }) else {
                throw SceneTouchActionResolverError.wrongTarget(hit.interactionTargetID)
            }
            return SceneTouchActionResolution(
                action: .setPressure(forceID: force.id, magnitude: amount),
                directManipulation: nil,
                targetID: hit.interactionTargetID,
                progress: amount
            )

        case let (
            .adjustTarget(viewportPoint, amount),
            .transform(visual),
            .transform(configuration),
            .transform(progress)
        ):
            try requireAmount(amount)
            guard progress.completedStageCount < configuration.stages.count else {
                throw SceneTouchActionResolverError.invalidRuntimeState
            }
            let stage = configuration.stages[progress.completedStageCount]
            let hit = try requireTarget(at: viewportPoint, in: frame)
            guard visual.stages.contains(where: {
                $0.stageID == stage.id && $0.interactionTargetID == hit.interactionTargetID
            }) else {
                throw SceneTouchActionResolverError.wrongTarget(hit.interactionTargetID)
            }
            return SceneTouchActionResolution(
                action: .transform(controlID: stage.controlID, amount: amount),
                directManipulation: nil,
                targetID: hit.interactionTargetID,
                progress: amount
            )

        case let (
            .holdPressure(elapsedMillis),
            .pressure,
            .pressure,
            .pressure
        ):
            guard elapsedMillis > 0, elapsedMillis <= 1_000 else {
                throw SceneTouchActionResolverError.invalidAmount
            }
            return SceneTouchActionResolution(
                action: .advancePressure(elapsedMillis: elapsedMillis),
                directManipulation: nil,
                targetID: nil,
                progress: 0
            )

        case (.commitAllocation, .allocate, .allocate, .allocate):
            return SceneTouchActionResolution(
                action: .commitAllocation,
                directManipulation: nil,
                targetID: nil,
                progress: 1
            )

        default:
            throw SceneTouchActionResolverError.mismatchedGrammar
        }
    }

    /// Converts a reducer preview into the brief response overlay. Allocate
    /// still commits reducer resistance. Assemble publishes rejected drops as
    /// an ephemeral snap-back and crosses the journal only when this preview
    /// accepted the exact `.place` action.
    public static func directManipulationAfterPreview(
        resolution: SceneTouchActionResolution,
        preview: SceneInteractionPreview
    ) throws -> SceneDirectManipulationState? {
        guard let action = resolution.action else {
            throw SceneTouchActionResolverError.actionRequired
        }
        guard preview.action == action else {
            throw SceneTouchActionResolverError.previewActionMismatch
        }
        switch action {
        case let .allocate(_, destinationUnits):
            guard let targetID = resolution.targetID else { return nil }
            switch preview.feedback {
            case .resistance:
                return .resistanceAfterReducerRejection(
                    targetID: targetID,
                    progress: resolution.progress
                )
            case .progress, .completed:
                return .acceptedAfterReducer(
                    targetID: targetID,
                    destinationUnits: destinationUnits,
                    progress: resolution.progress
                )
            case .none, .contact, .threshold:
                throw SceneTouchActionResolverError.feedbackNotApplicable
            }

        case let .place(componentID, slotID):
            guard let pending = resolution.directManipulation,
                  pending.phase == .slotApproach,
                  pending.subjectID == componentID,
                  pending.slotID == slotID,
                  let sourceTargetID = pending.sourceTargetID,
                  let targetID = pending.targetID,
                  let position = pending.masterPosition,
                  let grabOffset = pending.grabOffset else {
                return nil
            }
            switch preview.feedback {
            case .resistance:
                return .assemblySnapBack(
                    componentID: componentID,
                    sourceTargetID: sourceTargetID,
                    targetID: targetID,
                    slotID: slotID,
                    from: position,
                    grabOffset: grabOffset,
                    progress: resolution.progress,
                    rejectedByReducer: true
                )
            case .progress, .completed:
                return .assemblyAcceptedAfterReducer(
                    componentID: componentID,
                    sourceTargetID: sourceTargetID,
                    targetID: targetID,
                    slotID: slotID,
                    progress: resolution.progress
                )
            case .none, .contact, .threshold:
                throw SceneTouchActionResolverError.feedbackNotApplicable
            }

        default:
            return nil
        }
    }

    /// Compatibility seam for existing callers; new code should name the
    /// pure preview boundary explicitly.
    public static func committedDirectManipulation(
        resolution: SceneTouchActionResolution,
        preview: SceneInteractionPreview
    ) throws -> SceneDirectManipulationState? {
        try directManipulationAfterPreview(
            resolution: resolution,
            preview: preview
        )
    }

    private static func requireSourceContact(
        at point: SceneFramePoint,
        frame: SceneFramePlan,
        visual: SceneAllocateVisualBinding,
        alphaSampler: (any SceneAlphaMaskSampling)?
    ) throws -> SceneTouchSourceContact {
        guard let alphaSampler else {
            throw SceneTouchActionResolverError.alphaSamplerRequired
        }
        let contact = try SceneTouchGeometryResolver.sourceContact(
            at: point,
            in: frame,
            alphaSampler: alphaSampler
        )
        guard contact.interactionID == visual.interactionID,
              contact.layerID == visual.resource.layerID else {
            throw SceneTouchActionResolverError.mismatchedVisualBinding
        }
        return contact
    }

    private static func requireTarget(
        at point: SceneFramePoint,
        in frame: SceneFramePlan
    ) throws -> SceneTouchTargetHit {
        guard let hit = try SceneTouchGeometryResolver.target(at: point, in: frame) else {
            throw SceneTouchActionResolverError.targetNotHit
        }
        return hit
    }

    private static func requireAssemblyComponent(
        at point: SceneFramePoint,
        frame: SceneFramePlan,
        visual: SceneAssembleVisualBinding,
        configuration: AssembleInteractionSpec,
        progress: AssembleProgress
    ) throws -> (
        hit: SceneTouchTargetHit,
        visual: SceneAssemblyComponentVisualBinding,
        component: AssemblyComponent
    ) {
        try requirePhysicalAssemblyBinding(visual)
        let hit = try requireTarget(at: point, in: frame)
        guard let componentVisual = visual.components.first(where: {
            $0.sourceInteractionTargetID == hit.interactionTargetID
        }), let component = configuration.components.first(where: {
            $0.id == componentVisual.componentID
        }) else {
            throw SceneTouchActionResolverError.wrongTarget(hit.interactionTargetID)
        }
        guard !progress.placements.contains(where: {
            $0.componentID == component.id
        }) else {
            throw SceneTouchActionResolverError.invalidRuntimeState
        }
        return (hit, componentVisual, component)
    }

    private static func requireAssemblySlot(
        at point: SceneFramePoint,
        frame: SceneFramePlan,
        visual: SceneAssembleVisualBinding,
        configuration: AssembleInteractionSpec
    ) throws -> (
        hit: SceneTouchTargetHit,
        visual: SceneAssemblyComponentVisualBinding,
        component: AssemblyComponent,
        slotTargetID: String
    ) {
        try requirePhysicalAssemblyBinding(visual)
        let hit = try requireTarget(at: point, in: frame)
        guard let componentVisual = visual.components.first(where: {
            $0.slotInteractionTargetID == hit.interactionTargetID
        }), let slotTargetID = componentVisual.slotInteractionTargetID,
              slotTargetID == hit.interactionTargetID,
              let component = configuration.components.first(where: {
            $0.id == componentVisual.componentID
        }) else {
            throw SceneTouchActionResolverError.wrongTarget(hit.interactionTargetID)
        }
        return (hit, componentVisual, component, slotTargetID)
    }

    private static func requireAssemblyGrabOffset(
        sourceTargetID: String,
        layerID: SceneLayerID,
        sourceMasterPosition: NormalizedPoint,
        frame: SceneFramePlan
    ) throws -> SceneFrameVector {
        let regions = frame.interactionHitRegions.filter {
            $0.interactionTargetID == sourceTargetID && $0.layerID == layerID
        }
        guard regions.count == 1,
              let path = regions.first?.viewportPath,
              !path.isEmpty else {
            throw SceneTouchActionResolverError.invalidAssemblyGrabOffset
        }
        let viewportCenter = SceneFramePoint(
            x: path.reduce(0) { $0 + $1.x } / Double(path.count),
            y: path.reduce(0) { $0 + $1.y } / Double(path.count)
        )
        let sourceCenter = try SceneTouchGeometryResolver.masterPoint(
            for: viewportCenter,
            in: frame,
            boundTo: layerID
        )
        let offset = SceneFrameVector(
            dx: sourceMasterPosition.x - sourceCenter.x,
            dy: sourceMasterPosition.y - sourceCenter.y
        )
        guard offset.dx.isFinite, offset.dy.isFinite,
              (-1 ... 1).contains(offset.dx),
              (-1 ... 1).contains(offset.dy) else {
            throw SceneTouchActionResolverError.invalidAssemblyGrabOffset
        }
        return offset
    }

    private static func requirePhysicalAssemblyBinding(
        _ visual: SceneAssembleVisualBinding
    ) throws {
        guard visual.components.allSatisfy({ component in
            guard let slotTargetID = component.slotInteractionTargetID else { return false }
            return slotTargetID != component.sourceInteractionTargetID
        }) else {
            throw SceneTouchActionResolverError.assemblyDirectPlacementUnavailable
        }
    }

    private static func requireProgress(_ progress: Double) throws {
        guard progress.isFinite, (0 ... 1).contains(progress) else {
            throw SceneTouchActionResolverError.invalidProgress
        }
    }

    private static func requireAmount(_ amount: Double) throws {
        guard amount.isFinite, (0 ... 1).contains(amount) else {
            throw SceneTouchActionResolverError.invalidAmount
        }
    }
}
