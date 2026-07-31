import Foundation

public enum SceneBlendMode: String, Codable, Equatable, Sendable {
    case normal
    case multiply
    case screen
    case additive
}

/// A rectangle in normalized unit space. Scene master frames, camera travel
/// and hit regions use master-canvas coordinates; safe-text rectangles use
/// the selected viewport crop's coordinates.
public struct NormalizedRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func contains(_ point: NormalizedPoint) -> Bool {
        point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
    }

    fileprivate var isValidUnitRect: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite
            && x >= 0 && y >= 0 && width > 0 && height > 0
            && maxX <= 1 && maxY <= 1
    }
}

public struct ScenePixelSize: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    fileprivate var isPortrait: Bool { width > 0 && height > width }
}

public struct SceneViewportSize: Codable, Equatable, Sendable {
    public let widthPoints: Int
    public let heightPoints: Int

    public init(widthPoints: Int, heightPoints: Int) {
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
    }

    fileprivate var isPortrait: Bool { widthPoints > 0 && heightPoints > widthPoints }
}

public struct SceneSafeTextRegion: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let rect: NormalizedRect

    public init(id: String, rect: NormalizedRect) {
        self.id = id
        self.rect = rect
    }
}

public struct SceneViewportCrop: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let viewport: SceneViewportSize
    public let sourceRect: NormalizedRect
    public let safeTextRegions: [SceneSafeTextRegion]

    public init(
        id: String,
        viewport: SceneViewportSize,
        sourceRect: NormalizedRect,
        safeTextRegions: [SceneSafeTextRegion]
    ) {
        self.id = id
        self.viewport = viewport
        self.sourceRect = sourceRect
        self.safeTextRegions = safeTextRegions
    }

    fileprivate func validate(canvas: ScenePixelSize, field: String) throws {
        guard isStableStringIdentifier(id), viewport.isPortrait, sourceRect.isValidUnitRect else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "requires a stable ID, portrait viewport and normalized source rect"
            )
        }
        guard !safeTextRegions.isEmpty,
              Set(safeTextRegions.map(\.id)).count == safeTextRegions.count,
              safeTextRegions.allSatisfy({
                  isStableStringIdentifier($0.id) && $0.rect.isValidUnitRect
              }) else {
            throw ContentValidationError.invalidValue(
                field: "\(field).safeTextRegions",
                reason: "requires uniquely named normalized regions"
            )
        }
        let sourceAspect = Double(canvas.width) * sourceRect.width
            / (Double(canvas.height) * sourceRect.height)
        let viewportAspect = Double(viewport.widthPoints) / Double(viewport.heightPoints)
        guard sourceAspect.isFinite, viewportAspect.isFinite,
              abs(sourceAspect / viewportAspect - 1) <= 0.01 else {
            throw ContentValidationError.invalidValue(
                field: "\(field).sourceRect",
                reason: "must match the authored viewport aspect within one percent"
            )
        }
    }
}

public struct SceneCanvasSpec: Codable, Equatable, Sendable {
    public let canvas: ScenePixelSize
    public let cameraTravelBounds: NormalizedRect
    public let authoredOverscanFraction: Double
    public let viewportCrops: [SceneViewportCrop]

    public init(
        canvas: ScenePixelSize,
        cameraTravelBounds: NormalizedRect,
        authoredOverscanFraction: Double,
        viewportCrops: [SceneViewportCrop]
    ) {
        self.canvas = canvas
        self.cameraTravelBounds = cameraTravelBounds
        self.authoredOverscanFraction = authoredOverscanFraction
        self.viewportCrops = viewportCrops
    }

    fileprivate func validate(field: String) throws {
        guard canvas.isPortrait, cameraTravelBounds.isValidUnitRect,
              authoredOverscanFraction.isFinite,
              (0.15 ... 0.5).contains(authoredOverscanFraction) else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "requires a portrait canvas, camera bounds and at least fifteen percent overscan"
            )
        }
        let horizontalMargin = cameraTravelBounds.width * authoredOverscanFraction
        let verticalMargin = cameraTravelBounds.height * authoredOverscanFraction
        guard cameraTravelBounds.x >= horizontalMargin,
              1 - cameraTravelBounds.maxX >= horizontalMargin,
              cameraTravelBounds.y >= verticalMargin,
              1 - cameraTravelBounds.maxY >= verticalMargin else {
            throw ContentValidationError.invalidValue(
                field: "\(field).cameraTravelBounds",
                reason: "master canvas must preserve authored overscan around camera travel"
            )
        }
        guard !viewportCrops.isEmpty,
              Set(viewportCrops.map(\.id)).count == viewportCrops.count else {
            throw ContentValidationError.invalidValue(
                field: "\(field).viewportCrops",
                reason: "requires uniquely named viewport crops"
            )
        }
        for crop in viewportCrops {
            try crop.validate(canvas: canvas, field: "\(field).viewportCrops.\(crop.id)")
        }
        guard viewportCrops.contains(where: {
            $0.id == "baseline-393x852"
                && $0.viewport.widthPoints == 393
                && $0.viewport.heightPoints == 852
        }) else {
            throw ContentValidationError.invalidValue(
                field: "\(field).viewportCrops",
                reason: "baseline-393x852 must author the 393 by 852 viewport"
            )
        }
    }
}

public struct SceneLayerMotion: Codable, Equatable, Sendable {
    public let parallaxFactor: Double
    public let windResponse: Double
    public let focusResponse: Double

    public init(parallaxFactor: Double, windResponse: Double = 0, focusResponse: Double = 0) {
        self.parallaxFactor = parallaxFactor
        self.windResponse = windResponse
        self.focusResponse = focusResponse
    }
}

public struct SceneLayerMaskSet: Codable, Equatable, Sendable {
    public let alphaMaskAssetPath: String?
    public let occlusionMaskAssetPath: String?
    public let depthMaskAssetPath: String?
    public let lightMaskAssetPath: String?

    public init(
        alphaMaskAssetPath: String? = nil,
        occlusionMaskAssetPath: String? = nil,
        depthMaskAssetPath: String? = nil,
        lightMaskAssetPath: String? = nil
    ) {
        self.alphaMaskAssetPath = alphaMaskAssetPath
        self.occlusionMaskAssetPath = occlusionMaskAssetPath
        self.depthMaskAssetPath = depthMaskAssetPath
        self.lightMaskAssetPath = lightMaskAssetPath
    }

    fileprivate var assetPaths: [String] {
        [alphaMaskAssetPath, occlusionMaskAssetPath, depthMaskAssetPath, lightMaskAssetPath]
            .compactMap { $0 }
    }

    fileprivate func validate() throws {
        for path in assetPaths { try requireSafePackageAssetPath(path) }
    }
}

public struct SceneLayerStateVariant: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let assetPath: String
    public let masks: SceneLayerMaskSet

    public init(id: String, assetPath: String, masks: SceneLayerMaskSet = .init()) {
        self.id = id
        self.assetPath = assetPath
        self.masks = masks
    }
}

public struct SceneLayerSpec: Codable, Equatable, Identifiable, Sendable {
    public let id: SceneLayerID
    public let order: Int
    public let assetPath: String
    public let frame: NormalizedRect
    public let depth: Double
    public let opacity: Double
    public let blendMode: SceneBlendMode
    public let masks: SceneLayerMaskSet
    public let motion: SceneLayerMotion
    public let stateVariants: [SceneLayerStateVariant]

    public init(
        id: SceneLayerID,
        order: Int,
        assetPath: String,
        frame: NormalizedRect,
        depth: Double,
        opacity: Double = 1,
        blendMode: SceneBlendMode = .normal,
        masks: SceneLayerMaskSet = .init(),
        motion: SceneLayerMotion,
        stateVariants: [SceneLayerStateVariant] = []
    ) {
        self.id = id
        self.order = order
        self.assetPath = assetPath
        self.frame = frame
        self.depth = depth
        self.opacity = opacity
        self.blendMode = blendMode
        self.masks = masks
        self.motion = motion
        self.stateVariants = stateVariants
    }
}

public struct CameraKeyframe: Codable, Equatable, Sendable {
    public let progress: Double
    public let center: NormalizedPoint
    public let scale: Double

    public init(progress: Double, center: NormalizedPoint, scale: Double) {
        self.progress = progress
        self.center = center
        self.scale = scale
    }
}

public struct CameraRail: Codable, Equatable, Sendable {
    public let keyframes: [CameraKeyframe]

    public init(keyframes: [CameraKeyframe]) {
        self.keyframes = keyframes
    }
}

public struct AtmosphereSpec: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case dust
        case embers
        case mist
        case rain
        case snow
        case smoke
    }

    public let kind: Kind
    public let density: Double
    public let velocity: SignedUnitVector
    public let deterministicSeed: UInt64

    public init(
        kind: Kind,
        density: Double,
        velocity: SignedUnitVector,
        deterministicSeed: UInt64
    ) {
        self.kind = kind
        self.density = density
        self.velocity = velocity
        self.deterministicSeed = deterministicSeed
    }
}

public struct SignedUnitVector: Codable, Equatable, Sendable {
    public let dx: Double
    public let dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    fileprivate var isValid: Bool {
        dx.isFinite && dy.isFinite
            && (-1 ... 1).contains(dx) && (-1 ... 1).contains(dy)
            && dx * dx + dy * dy <= 1
    }
}

public struct SceneHitRegion: Codable, Equatable, Sendable {
    /// A non-closed polygon in master-canvas normalized coordinates.
    public let path: [NormalizedPoint]

    public init(path: [NormalizedPoint]) {
        self.path = path
    }

    fileprivate var isValid: Bool {
        guard path.count >= 3,
              path.allSatisfy(\.isUnitPoint),
              Set(path.map { "\($0.x),\($0.y)" }).count == path.count else {
            return false
        }
        let doubledArea = zip(path, path.dropFirst() + [path[0]])
            .reduce(0.0) { result, edge in
                result + edge.0.x * edge.1.y - edge.1.x * edge.0.y
            }
        return doubledArea.isFinite && abs(doubledArea) > 0.000_000_01
    }

    fileprivate func isVisibleAndComfortablyTappable(in crop: SceneViewportCrop) -> Bool {
        guard isValid, crop.sourceRect.isValidUnitRect, crop.viewport.isPortrait,
              path.allSatisfy({ point in
                  let projectedX = (point.x - crop.sourceRect.x) / crop.sourceRect.width
                  let projectedY = (point.y - crop.sourceRect.y) / crop.sourceRect.height
                  return projectedX >= SceneRailGeometry.normalizedDeadBand
                      && projectedX <= 1 - SceneRailGeometry.normalizedDeadBand
                      && projectedY >= SceneRailGeometry.normalizedDeadBand
                      && projectedY <= 1 - SceneRailGeometry.normalizedDeadBand
              }) else {
            return false
        }
        let xValues = path.map(\.x)
        let yValues = path.map(\.y)
        guard let minimumX = xValues.min(), let maximumX = xValues.max(),
              let minimumY = yValues.min(), let maximumY = yValues.max() else {
            return false
        }
        let widthPoints = (maximumX - minimumX) / crop.sourceRect.width
            * Double(crop.viewport.widthPoints)
        let heightPoints = (maximumY - minimumY) / crop.sourceRect.height
            * Double(crop.viewport.heightPoints)
        return widthPoints.isFinite && heightPoints.isFinite
            && widthPoints >= 44 + SceneRailGeometry.normalizedDeadBand
            && heightPoints >= 44 + SceneRailGeometry.normalizedDeadBand
    }

    fileprivate func contains(_ point: NormalizedPoint) -> Bool {
        SceneHitRegionGeometry.contains(point, in: self)
    }
}

/// Pure master-space polygon containment used by shipping cross-binding
/// validation. Boundary points count as contained because authored Trace
/// anchors may deliberately sit on the route target's edge.
enum SceneHitRegionGeometry {
    static func contains(
        _ point: NormalizedPoint,
        in region: SceneHitRegion
    ) -> Bool {
        guard region.isValid, point.isUnitPoint else { return false }
        var inside = false
        var previous = region.path[region.path.count - 1]
        for current in region.path {
            let cross = (point.y - previous.y) * (current.x - previous.x)
                - (point.x - previous.x) * (current.y - previous.y)
            let onSegment = abs(cross) <= 0.000_000_001
                && point.x >= min(previous.x, current.x) - 0.000_000_001
                && point.x <= max(previous.x, current.x) + 0.000_000_001
                && point.y >= min(previous.y, current.y) - 0.000_000_001
                && point.y <= max(previous.y, current.y) + 0.000_000_001
            if onSegment { return true }
            let crossesY = (current.y > point.y) != (previous.y > point.y)
            if crossesY {
                let intersectionX = (previous.x - current.x)
                    * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < intersectionX { inside.toggle() }
            }
            previous = current
        }
        return inside
    }
}

public struct SceneInteractionTargetBinding: Codable, Equatable, Sendable {
    public let interactionTargetID: String
    public let layerID: SceneLayerID
    public let hitRegion: SceneHitRegion
    public let accessibilityElementID: String

    public init(
        interactionTargetID: String,
        layerID: SceneLayerID,
        hitRegion: SceneHitRegion,
        accessibilityElementID: String
    ) {
        self.interactionTargetID = interactionTargetID
        self.layerID = layerID
        self.hitRegion = hitRegion
        self.accessibilityElementID = accessibilityElementID
    }
}

public struct SceneRemainingUnitsVariant: Codable, Equatable, Sendable {
    public let maximumRemainingUnits: Int
    public let variantID: String

    public init(maximumRemainingUnits: Int, variantID: String) {
        self.maximumRemainingUnits = maximumRemainingUnits
        self.variantID = variantID
    }
}

public enum SceneResourceHitTest: String, Codable, Equatable, Sendable {
    case selectedVariantAlpha
}

public struct SceneAllocationResourceVisualBinding: Codable, Equatable, Sendable {
    public let layerID: SceneLayerID
    public let hitRegion: SceneHitRegion
    public let hitTest: SceneResourceHitTest
    public let variantsByRemainingUnits: [SceneRemainingUnitsVariant]

    public init(
        layerID: SceneLayerID,
        hitRegion: SceneHitRegion,
        hitTest: SceneResourceHitTest,
        variantsByRemainingUnits: [SceneRemainingUnitsVariant]
    ) {
        self.layerID = layerID
        self.hitRegion = hitRegion
        self.hitTest = hitTest
        self.variantsByRemainingUnits = variantsByRemainingUnits
    }
}

public struct SceneAllocationDestinationVisualBinding: Codable, Equatable, Sendable {
    public let destinationID: String
    public let interactionTargetID: String
    public let layerID: SceneLayerID
    public let emptyVariantID: String
    public let receivingVariantID: String
    public let completedVariantID: String
    /// Master-canvas points followed by the material response in the normal
    /// composition. Reduce Motion uses the same endpoints without spatial travel.
    public let transferPath: [NormalizedPoint]

    public init(
        destinationID: String,
        interactionTargetID: String,
        layerID: SceneLayerID,
        emptyVariantID: String,
        receivingVariantID: String,
        completedVariantID: String,
        transferPath: [NormalizedPoint]
    ) {
        self.destinationID = destinationID
        self.interactionTargetID = interactionTargetID
        self.layerID = layerID
        self.emptyVariantID = emptyVariantID
        self.receivingVariantID = receivingVariantID
        self.completedVariantID = completedVariantID
        self.transferPath = transferPath
    }
}

public struct SceneAllocateVisualBinding: Codable, Equatable, Sendable {
    public let interactionID: InteractionID
    public let resource: SceneAllocationResourceVisualBinding
    public let transferLayerID: SceneLayerID
    public let destinations: [SceneAllocationDestinationVisualBinding]

    public init(
        interactionID: InteractionID,
        resource: SceneAllocationResourceVisualBinding,
        transferLayerID: SceneLayerID,
        destinations: [SceneAllocationDestinationVisualBinding]
    ) {
        self.interactionID = interactionID
        self.resource = resource
        self.transferLayerID = transferLayerID
        self.destinations = destinations
    }
}

public struct SceneTraceReachedAnchorVisualBinding: Codable, Equatable, Sendable {
    public let anchorID: String
    public let variantID: String

    public init(anchorID: String, variantID: String) {
        self.anchorID = anchorID
        self.variantID = variantID
    }
}

public struct SceneTraceVisualBinding: Codable, Equatable, Sendable {
    public let interactionID: InteractionID
    public let interactionTargetID: String
    public let layerID: SceneLayerID
    public let idleVariantID: String
    public let tracingVariantID: String
    /// Ordered, durable visual results for every reached nonterminal anchor.
    /// Nil preserves the original three-state Trace wire form.
    public let reachedAnchorVariants: [SceneTraceReachedAnchorVisualBinding]?
    public let completedVariantID: String

    public init(
        interactionID: InteractionID,
        interactionTargetID: String,
        layerID: SceneLayerID,
        idleVariantID: String,
        tracingVariantID: String,
        reachedAnchorVariants: [SceneTraceReachedAnchorVisualBinding]? = nil,
        completedVariantID: String
    ) {
        self.interactionID = interactionID
        self.interactionTargetID = interactionTargetID
        self.layerID = layerID
        self.idleVariantID = idleVariantID
        self.tracingVariantID = tracingVariantID
        self.reachedAnchorVariants = reachedAnchorVariants
        self.completedVariantID = completedVariantID
    }
}

public struct SceneAssemblyComponentVisualBinding: Codable, Equatable, Sendable {
    public let componentID: String
    /// The handled material in its pre-placement position.
    public let sourceInteractionTargetID: String
    /// The distinct authored bearing point that accepts this component.
    ///
    /// Nil exists only when decoding the retired single-target development
    /// fixture wire form. New encodings and physical direct manipulation
    /// require a distinct value; SceneRuntime fails closed when this is nil.
    public let slotInteractionTargetID: String?
    public let layerID: SceneLayerID
    public let availableVariantID: String
    public let resistedVariantID: String
    public let placedVariantID: String

    public init(
        componentID: String,
        sourceInteractionTargetID: String,
        slotInteractionTargetID: String,
        layerID: SceneLayerID,
        availableVariantID: String,
        resistedVariantID: String,
        placedVariantID: String
    ) {
        self.componentID = componentID
        self.sourceInteractionTargetID = sourceInteractionTargetID
        self.slotInteractionTargetID = slotInteractionTargetID
        self.layerID = layerID
        self.availableVariantID = availableVariantID
        self.resistedVariantID = resistedVariantID
        self.placedVariantID = placedVariantID
    }

    private enum CodingKeys: String, CodingKey {
        case componentID
        case sourceInteractionTargetID
        case slotInteractionTargetID
        case interactionTargetID
        case layerID
        case availableVariantID
        case resistedVariantID
        case placedVariantID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        componentID = try container.decode(String.self, forKey: .componentID)
        layerID = try container.decode(SceneLayerID.self, forKey: .layerID)
        availableVariantID = try container.decode(String.self, forKey: .availableVariantID)
        resistedVariantID = try container.decode(String.self, forKey: .resistedVariantID)
        placedVariantID = try container.decode(String.self, forKey: .placedVariantID)

        let hasSourceTarget = container.contains(.sourceInteractionTargetID)
        let hasSlotTarget = container.contains(.slotInteractionTargetID)
        let hasLegacyTarget = container.contains(.interactionTargetID)
        if hasSourceTarget, hasSlotTarget, !hasLegacyTarget {
            sourceInteractionTargetID = try container.decode(
                String.self,
                forKey: .sourceInteractionTargetID
            )
            slotInteractionTargetID = try container.decode(
                String.self,
                forKey: .slotInteractionTargetID
            )
        } else if !hasSourceTarget, !hasSlotTarget, hasLegacyTarget {
            // Compatibility is deliberately decode-only for already-signed
            // development fixtures. The missing slot prevents every physical
            // Assemble placement path from crossing the durable boundary.
            sourceInteractionTargetID = try container.decode(
                String.self,
                forKey: .interactionTargetID
            )
            slotInteractionTargetID = nil
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Assemble bindings require either the legacy source target alone or distinct source and slot targets"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        guard let slotInteractionTargetID,
              slotInteractionTargetID != sourceInteractionTargetID else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Encoded Assemble bindings require distinct source and slot targets"
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(componentID, forKey: .componentID)
        try container.encode(sourceInteractionTargetID, forKey: .sourceInteractionTargetID)
        try container.encode(slotInteractionTargetID, forKey: .slotInteractionTargetID)
        try container.encode(layerID, forKey: .layerID)
        try container.encode(availableVariantID, forKey: .availableVariantID)
        try container.encode(resistedVariantID, forKey: .resistedVariantID)
        try container.encode(placedVariantID, forKey: .placedVariantID)
    }
}

public struct SceneAssembleVisualBinding: Codable, Equatable, Sendable {
    public let interactionID: InteractionID
    public let components: [SceneAssemblyComponentVisualBinding]

    public init(
        interactionID: InteractionID,
        components: [SceneAssemblyComponentVisualBinding]
    ) {
        self.interactionID = interactionID
        self.components = components
    }
}

public struct ScenePressureForceVisualBinding: Codable, Equatable, Sendable {
    public let forceID: String
    public let layerID: SceneLayerID
    public let interactionTargetID: String?

    public init(
        forceID: String,
        layerID: SceneLayerID,
        interactionTargetID: String? = nil
    ) {
        self.forceID = forceID
        self.layerID = layerID
        self.interactionTargetID = interactionTargetID
    }
}

public struct ScenePressureVisualBinding: Codable, Equatable, Sendable {
    public let interactionID: InteractionID
    public let forces: [ScenePressureForceVisualBinding]
    public let systemLayerID: SceneLayerID
    public let restingVariantID: String
    public let resistingVariantID: String
    public let stableVariantID: String
    public let brokenVariantID: String

    public init(
        interactionID: InteractionID,
        forces: [ScenePressureForceVisualBinding],
        systemLayerID: SceneLayerID,
        restingVariantID: String,
        resistingVariantID: String,
        stableVariantID: String,
        brokenVariantID: String
    ) {
        self.interactionID = interactionID
        self.forces = forces
        self.systemLayerID = systemLayerID
        self.restingVariantID = restingVariantID
        self.resistingVariantID = resistingVariantID
        self.stableVariantID = stableVariantID
        self.brokenVariantID = brokenVariantID
    }
}

public struct SceneTransformationStageVisualBinding: Codable, Equatable, Sendable {
    public let stageID: String
    public let interactionTargetID: String
    public let layerID: SceneLayerID
    public let beforeVariantID: String
    public let activeVariantID: String
    public let completedVariantID: String

    public init(
        stageID: String,
        interactionTargetID: String,
        layerID: SceneLayerID,
        beforeVariantID: String,
        activeVariantID: String,
        completedVariantID: String
    ) {
        self.stageID = stageID
        self.interactionTargetID = interactionTargetID
        self.layerID = layerID
        self.beforeVariantID = beforeVariantID
        self.activeVariantID = activeVariantID
        self.completedVariantID = completedVariantID
    }
}

public struct SceneTransformVisualBinding: Codable, Equatable, Sendable {
    public let interactionID: InteractionID
    public let stages: [SceneTransformationStageVisualBinding]

    public init(
        interactionID: InteractionID,
        stages: [SceneTransformationStageVisualBinding]
    ) {
        self.interactionID = interactionID
        self.stages = stages
    }
}

public enum SceneInteractionVisualBinding: Codable, Equatable, Sendable {
    case trace(SceneTraceVisualBinding)
    case allocate(SceneAllocateVisualBinding)
    case assemble(SceneAssembleVisualBinding)
    case pressure(ScenePressureVisualBinding)
    case transform(SceneTransformVisualBinding)

    private enum GrammarKind: String, Codable {
        case trace
        case allocate
        case assemble
        case pressure
        case transform
    }
    private enum CodingKeys: String, CodingKey { case grammar, configuration }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(GrammarKind.self, forKey: .grammar) {
        case .trace:
            self = .trace(
                try container.decode(SceneTraceVisualBinding.self, forKey: .configuration)
            )
        case .allocate:
            self = .allocate(
                try container.decode(SceneAllocateVisualBinding.self, forKey: .configuration)
            )
        case .assemble:
            self = .assemble(
                try container.decode(SceneAssembleVisualBinding.self, forKey: .configuration)
            )
        case .pressure:
            self = .pressure(
                try container.decode(ScenePressureVisualBinding.self, forKey: .configuration)
            )
        case .transform:
            self = .transform(
                try container.decode(SceneTransformVisualBinding.self, forKey: .configuration)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
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
}

public enum ReduceMotionStratumKind: String, Codable, Equatable, Sendable {
    case staticPlate
    case stateOverlay
}

public struct ReduceMotionStratum: Codable, Equatable, Sendable {
    public let id: String
    public let kind: ReduceMotionStratumKind
    public let assetPath: String?
    public let layerID: SceneLayerID?

    public init(
        id: String,
        kind: ReduceMotionStratumKind,
        assetPath: String? = nil,
        layerID: SceneLayerID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.assetPath = assetPath
        self.layerID = layerID
    }

    fileprivate func validate(field: String) throws {
        guard isStableStringIdentifier(id) else {
            throw ContentValidationError.invalidValue(
                field: "\(field).id",
                reason: "stable kebab-case ID required"
            )
        }
        switch kind {
        case .staticPlate:
            guard let assetPath, layerID == nil else {
                throw ContentValidationError.invalidValue(
                    field: field,
                    reason: "a static plate requires one assetPath and no layerID"
                )
            }
            try requireSafePackageAssetPath(assetPath)
        case .stateOverlay:
            guard assetPath == nil, let layerID,
                  isStableStringIdentifier(layerID.rawValue) else {
                throw ContentValidationError.invalidValue(
                    field: field,
                    reason: "a state overlay requires one stable layerID and no assetPath"
                )
            }
        }
    }
}

public struct ReduceMotionComposition: Codable, Equatable, Sendable {
    public let canvas: ScenePixelSize
    public let viewportCrops: [SceneViewportCrop]
    /// Explicit back-to-front reduced-motion composition. Static plates can
    /// sit below, between or above fixed causal overlays, preserving authored
    /// foreground occlusion without camera, parallax or material travel.
    public let strata: [ReduceMotionStratum]

    public init(
        canvas: ScenePixelSize,
        viewportCrops: [SceneViewportCrop],
        strata: [ReduceMotionStratum]
    ) {
        self.canvas = canvas
        self.viewportCrops = viewportCrops
        self.strata = strata
    }

    fileprivate func validate(field: String) throws {
        guard canvas.isPortrait, !viewportCrops.isEmpty,
              Set(viewportCrops.map(\.id)).count == viewportCrops.count,
              !strata.isEmpty,
              Set(strata.map(\.id)).count == strata.count else {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "requires a portrait canvas, unique viewport crops and unique ordered strata"
            )
        }
        for (index, stratum) in strata.enumerated() {
            try stratum.validate(field: "\(field).strata[\(index)]")
        }
        for crop in viewportCrops {
            try crop.validate(canvas: canvas, field: "\(field).viewportCrops.\(crop.id)")
        }
        guard viewportCrops.contains(where: {
            $0.id == "baseline-393x852"
                && $0.viewport.widthPoints == 393
                && $0.viewport.heightPoints == 852
        }) else {
            throw ContentValidationError.invalidValue(
                field: "\(field).viewportCrops",
                reason: "baseline-393x852 must author the 393 by 852 reduced composition"
            )
        }
    }
}

public struct SceneSpec: Codable, Equatable, Identifiable, Sendable {
    public let id: SceneID
    public let sceneCanvas: SceneCanvasSpec
    public let layers: [SceneLayerSpec]
    public let cameraRail: CameraRail
    public let atmosphere: [AtmosphereSpec]
    public let interactionTargets: [SceneInteractionTargetBinding]
    public let interactionVisualBinding: SceneInteractionVisualBinding?
    public let reduceMotionComposition: ReduceMotionComposition
    public let mechanismFocus: LocalizedStringSpec
    public let accessibilityID: AccessibilityID

    public init(
        id: SceneID,
        sceneCanvas: SceneCanvasSpec,
        layers: [SceneLayerSpec],
        cameraRail: CameraRail,
        atmosphere: [AtmosphereSpec],
        interactionTargets: [SceneInteractionTargetBinding],
        interactionVisualBinding: SceneInteractionVisualBinding? = nil,
        reduceMotionComposition: ReduceMotionComposition,
        mechanismFocus: LocalizedStringSpec,
        accessibilityID: AccessibilityID
    ) {
        self.id = id
        self.sceneCanvas = sceneCanvas
        self.layers = layers
        self.cameraRail = cameraRail
        self.atmosphere = atmosphere
        self.interactionTargets = interactionTargets
        self.interactionVisualBinding = interactionVisualBinding
        self.reduceMotionComposition = reduceMotionComposition
        self.mechanismFocus = mechanismFocus
        self.accessibilityID = accessibilityID
    }

    public func validate() throws {
        try requireNonempty(id, field: "scene.id")
        try requireNonempty(accessibilityID, field: "scene.accessibilityID")
        try sceneCanvas.validate(field: "scene.sceneCanvas")
        try reduceMotionComposition.validate(field: "scene.reduceMotionComposition")
        guard !layers.isEmpty else {
            throw ContentValidationError.invalidCount(
                field: "scene.layers",
                expected: "at least one",
                actual: 0
            )
        }
        try requireUnique(layers.map(\.id))
        for (index, layer) in layers.enumerated() {
            try requireNonempty(layer.id, field: "scene.layers.id")
            try requireSafePackageAssetPath(layer.assetPath)
            try layer.masks.validate()
            guard layer.order == index,
                  layer.frame.isValidUnitRect,
                  layer.depth.isFinite,
                  layer.opacity.isFinite,
                  (0 ... 1).contains(layer.depth),
                  (0 ... 1).contains(layer.opacity),
                  layer.motion.parallaxFactor.isFinite,
                  layer.motion.windResponse.isFinite,
                  layer.motion.focusResponse.isFinite,
                  (-1 ... 1).contains(layer.motion.parallaxFactor),
                  (0 ... 1).contains(layer.motion.windResponse),
                  (0 ... 1).contains(layer.motion.focusResponse) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.layers",
                    reason: "order, normalized frame, unit values and bounded finite motion are required"
                )
            }
            guard Set(layer.stateVariants.map(\.id)).count == layer.stateVariants.count else {
                throw ContentValidationError.invalidValue(
                    field: "scene.layers.stateVariants",
                    reason: "variant IDs must be unique per layer"
                )
            }
            for variant in layer.stateVariants {
                guard isStableStringIdentifier(variant.id) else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.layers.stateVariants.id",
                        reason: "stable kebab-case ID required"
                    )
                }
                try requireSafePackageAssetPath(variant.assetPath)
                try variant.masks.validate()
            }
        }
        let dynamicLayerAssetPaths = Set(
            layers.flatMap { layer in
                [layer.assetPath] + layer.stateVariants.map(\.assetPath)
            }
        )
        let staticStrata = reduceMotionComposition.strata.filter { $0.kind == .staticPlate }
        let staticAssetPaths = staticStrata.compactMap(\.assetPath)
        guard Set(staticAssetPaths).count == staticAssetPaths.count,
              staticAssetPaths.allSatisfy({ !dynamicLayerAssetPaths.contains($0) }) else {
            throw ContentValidationError.invalidValue(
                field: "scene.reduceMotionComposition.strata",
                reason: "static plates require unique offline assets not reused by dynamic layers"
            )
        }
        let statefulLayerIDs = Set(
            layers.filter { !$0.stateVariants.isEmpty }.map(\.id)
        )
        let overlayLayerIDs = reduceMotionComposition.strata.compactMap { stratum in
            stratum.kind == .stateOverlay ? stratum.layerID : nil
        }
        let layerOrder = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0.order) })
        guard Set(overlayLayerIDs) == statefulLayerIDs,
              Set(overlayLayerIDs).count == overlayLayerIDs.count,
              overlayLayerIDs.map({ layerOrder[$0] ?? -1 })
                == overlayLayerIDs.map({ layerOrder[$0] ?? -1 }).sorted() else {
            throw ContentValidationError.invalidValue(
                field: "scene.reduceMotionComposition.strata",
                reason: "must place every and only stateful layer once in authored back-to-front order"
            )
        }
        if !statefulLayerIDs.isEmpty {
            guard reduceMotionComposition.strata.first?.kind == .staticPlate,
                  reduceMotionComposition.strata.last?.kind == .staticPlate else {
                throw ContentValidationError.invalidValue(
                    field: "scene.reduceMotionComposition.strata",
                    reason: "stateful scenes require static underlay and foreground strata"
                )
            }
        }
        let normalCropByID = Dictionary(
            uniqueKeysWithValues: sceneCanvas.viewportCrops.map { ($0.id, $0) }
        )
        let reducedCropByID = Dictionary(
            uniqueKeysWithValues: reduceMotionComposition.viewportCrops.map { ($0.id, $0) }
        )
        guard Set(normalCropByID.keys) == Set(reducedCropByID.keys),
              normalCropByID.allSatisfy({ id, crop in
                  reducedCropByID[id]?.viewport == crop.viewport
              }) else {
            throw ContentValidationError.invalidValue(
                field: "scene.reduceMotionComposition.viewportCrops",
                reason: "must match the normal crop IDs and viewport dimensions"
            )
        }
        let keyframes = cameraRail.keyframes
        guard keyframes.count >= 2,
              keyframes.first?.progress == 0,
              keyframes.last?.progress == 1,
              keyframes.allSatisfy({
                      $0.progress.isFinite && (0 ... 1).contains($0.progress)
                      && $0.center.isUnitPoint
                      && sceneCanvas.cameraTravelBounds.contains($0.center)
                      && $0.scale.isFinite && (0.25 ... 4).contains($0.scale)
              }),
              zip(keyframes, keyframes.dropFirst()).allSatisfy({ $0.0.progress < $0.1.progress }) else {
            throw ContentValidationError.invalidValue(
                field: "scene.cameraRail",
                reason: "requires unique ordered progress from zero to one inside authored camera travel"
            )
        }
        try mechanismFocus.validate(field: "scene.mechanismFocus")
        for crop in sceneCanvas.viewportCrops {
            guard SceneRailGeometry.cameraSourceStaysInsideMaster(
                rail: cameraRail,
                crop: crop
            ) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.cameraRail",
                    reason: "active camera source must stay inside the authored master for crop '\(crop.id)' through the complete camera rail"
                )
            }
        }
        for item in atmosphere {
            guard item.density.isFinite, (0 ... 1).contains(item.density),
                  item.velocity.isValid,
                  item.deterministicSeed <= UInt64(UInt32.max) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.atmosphere",
                    reason: "requires unit density, signed unit velocity and a 32-bit deterministic seed"
                )
            }
        }
        guard Set(interactionTargets.map(\.interactionTargetID)).count == interactionTargets.count else {
            throw ContentValidationError.invalidValue(
                field: "scene.interactionTargets",
                reason: "interaction target IDs must be unique"
            )
        }
        let layerIDs = Set(layers.map(\.id))
        let layerByID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        guard let railOrigin = keyframes.first?.center else {
            throw ContentValidationError.invalidValue(
                field: "scene.cameraRail",
                reason: "requires an authored origin"
            )
        }
        var railAttachedRegions: [SceneRailGeometry.AttachedRegion] = []
        for binding in interactionTargets {
            guard isStableStringIdentifier(binding.interactionTargetID),
                  isStableStringIdentifier(binding.accessibilityElementID),
                  layerIDs.contains(binding.layerID),
                  binding.hitRegion.isValid else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionTargets",
                    reason: "each target requires a known layer, real normalized hit region and accessibility element ID"
                )
            }
            guard let boundLayer = layerByID[binding.layerID],
                  boundLayer.motion.windResponse == 0,
                  binding.hitRegion.path.allSatisfy({ boundLayer.frame.contains($0) }) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionTargets.layerID",
                    reason: "interactive target geometry must stay inside its fixed bound layer and cannot use continuous wind displacement"
                )
            }
            railAttachedRegions.append(
                SceneRailGeometry.AttachedRegion(
                    id: binding.interactionTargetID,
                    hitRegion: binding.hitRegion,
                    parallaxFactor: boundLayer.motion.parallaxFactor
                )
            )
            for crop in sceneCanvas.viewportCrops {
                guard SceneRailGeometry.regionStaysVisibleAndTappable(
                    binding.hitRegion,
                    parallaxFactor: boundLayer.motion.parallaxFactor,
                    rail: cameraRail,
                    crop: crop,
                    railOrigin: railOrigin
                ) else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.interactionTargets.hitRegion",
                        reason: "target '\(binding.interactionTargetID)' must be wholly visible, follow its rendered layer and stay at least 44 by 44 points through crop '\(crop.id)' and the complete camera rail"
                    )
                }
            }
            for crop in reduceMotionComposition.viewportCrops {
                guard binding.hitRegion.isVisibleAndComfortablyTappable(in: crop) else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.interactionTargets.hitRegion",
                        reason: "target '\(binding.interactionTargetID)' must be wholly visible and at least 44 by 44 points in reduced crop '\(crop.id)'"
                    )
                }
            }
        }
        if case let .allocate(configuration)? = interactionVisualBinding,
           let resourceLayer = layerByID[configuration.resource.layerID] {
            for crop in sceneCanvas.viewportCrops {
                guard SceneRailGeometry.regionStaysVisibleAndTappable(
                    configuration.resource.hitRegion,
                    parallaxFactor: resourceLayer.motion.parallaxFactor,
                    rail: cameraRail,
                    crop: crop,
                    railOrigin: railOrigin
                ) else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.interactionVisualBinding.allocate.resource.hitRegion",
                        reason: "source region must remain visible, follow the rendered resource and stay at least 44 by 44 points through every crop and the complete camera rail"
                    )
                }
            }
            for crop in reduceMotionComposition.viewportCrops {
                guard configuration.resource.hitRegion.isVisibleAndComfortablyTappable(
                    in: crop
                ) else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.interactionVisualBinding.allocate.resource.hitRegion",
                        reason: "source region must remain visible and at least 44 by 44 points in Reduce Motion"
                    )
                }
            }
            railAttachedRegions.append(
                SceneRailGeometry.AttachedRegion(
                    id: "allocation-resource",
                    hitRegion: configuration.resource.hitRegion,
                    parallaxFactor: resourceLayer.motion.parallaxFactor
                )
            )
        }
        for crop in sceneCanvas.viewportCrops {
            guard SceneRailGeometry.regionsMaintainClearance(
                railAttachedRegions,
                rail: cameraRail,
                crop: crop,
                railOrigin: railOrigin
            ) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionTargets.hitRegion",
                    reason: "destination and resource regions must not overlap or touch in crop '\(crop.id)' anywhere along the complete camera rail"
                )
            }
        }
        for crop in reduceMotionComposition.viewportCrops {
            guard SceneRailGeometry.regionsMaintainStaticClearance(
                railAttachedRegions,
                crop: crop
            ) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionTargets.hitRegion",
                    reason: "destination and resource regions must not overlap or touch in reduced crop '\(crop.id)'"
                )
            }
        }
        try validateInteractionVisualBindingStructure(
            layerByID: layerByID,
            targetByID: Dictionary(
                uniqueKeysWithValues: interactionTargets.map { ($0.interactionTargetID, $0) }
            )
        )
    }

    private func validateInteractionVisualBindingStructure(
        layerByID: [SceneLayerID: SceneLayerSpec],
        targetByID: [String: SceneInteractionTargetBinding]
    ) throws {
        guard let interactionVisualBinding else { return }
        switch interactionVisualBinding {
        case let .trace(configuration):
            try requireNonempty(
                configuration.interactionID,
                field: "scene.interactionVisualBinding.interactionID"
            )
            let reachedAnchorVariants = configuration.reachedAnchorVariants ?? []
            let hasValidReachedAnchorVariants = configuration.reachedAnchorVariants == nil
                || (
                    !reachedAnchorVariants.isEmpty
                        && reachedAnchorVariants.allSatisfy({
                            isStableStringIdentifier($0.anchorID)
                                && isStableStringIdentifier($0.variantID)
                        })
                        && Set(reachedAnchorVariants.map(\.anchorID)).count
                            == reachedAnchorVariants.count
                )
            guard isStableStringIdentifier(configuration.interactionTargetID),
                  let layer = layerByID[configuration.layerID],
                  let target = targetByID[configuration.interactionTargetID],
                  target.layerID == configuration.layerID,
                  hasValidReachedAnchorVariants,
                  visualVariants(
                      [
                          configuration.idleVariantID,
                          configuration.tracingVariantID,
                          configuration.completedVariantID,
                      ] + reachedAnchorVariants.map(\.variantID),
                      existOn: layer
                  ) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.trace",
                    reason: "requires one real route target, distinct route-state variants and unique named reached-anchor variants when authored"
                )
            }
        case let .allocate(configuration):
            try requireNonempty(
                configuration.interactionID,
                field: "scene.interactionVisualBinding.interactionID"
            )
            guard let resourceLayer = layerByID[configuration.resource.layerID],
                  let transferLayer = layerByID[configuration.transferLayerID],
                  configuration.resource.layerID != configuration.transferLayerID,
                  transferLayer.motion.parallaxFactor == 0,
                  transferLayer.motion.windResponse == 0,
                  configuration.resource.hitRegion.isValid,
                  configuration.resource.hitRegion.path.allSatisfy({
                      resourceLayer.frame.contains($0)
                  }),
                  resourceLayer.motion.windResponse == 0,
                  resourceLayer.stateVariants.allSatisfy({
                      $0.masks.alphaMaskAssetPath != nil
                  }) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.allocate",
                    reason: "requires a response-controlled transfer layer and a fixed alpha-bound source hit region inside every resource variant"
                )
            }
            let thresholds = configuration.resource.variantsByRemainingUnits
            guard thresholds.count >= 2,
                  thresholds.first?.maximumRemainingUnits == 0,
                  zip(thresholds, thresholds.dropFirst()).allSatisfy({
                      $0.0.maximumRemainingUnits < $0.1.maximumRemainingUnits
                  }),
                  thresholds.allSatisfy({
                      $0.maximumRemainingUnits >= 0
                          && isStableStringIdentifier($0.variantID)
                  }),
                  Set(thresholds.map(\.variantID)).count == thresholds.count,
                  Set(thresholds.map(\.variantID)) == Set(resourceLayer.stateVariants.map(\.id)) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.allocate.resource",
                    reason: "requires strictly increasing remaining-unit thresholds from zero covering every source variant"
                )
            }
            let destinations = configuration.destinations
            guard !destinations.isEmpty,
                  Set(destinations.map(\.destinationID)).count == destinations.count,
                  Set(destinations.map(\.interactionTargetID)).count == destinations.count,
                  Set(destinations.map(\.layerID)).count == destinations.count else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.allocate.destinations",
                    reason: "requires unique destination, target and layer bindings"
                )
            }
            for destination in destinations {
                guard isStableStringIdentifier(destination.destinationID),
                      isStableStringIdentifier(destination.interactionTargetID),
                      let layer = layerByID[destination.layerID],
                      let target = targetByID[destination.interactionTargetID],
                      target.layerID == destination.layerID,
                      layer.motion.windResponse == 0,
                      Set([
                          destination.emptyVariantID,
                          destination.receivingVariantID,
                          destination.completedVariantID,
                      ]).count == 3,
                      [
                          destination.emptyVariantID,
                          destination.receivingVariantID,
                          destination.completedVariantID,
                      ].allSatisfy({ variantID in
                          isStableStringIdentifier(variantID)
                              && layer.stateVariants.contains(where: { $0.id == variantID })
                      }),
                      destination.transferPath.count >= 2,
                      destination.transferPath.allSatisfy(\.isUnitPoint),
                      SceneRailGeometry.adjacentPathPointsAreDistinct(
                          destination.transferPath
                      ),
                      configuration.resource.hitRegion.contains(
                          destination.transferPath[0]
                      ),
                      target.hitRegion.contains(destination.transferPath[destination.transferPath.count - 1]) else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.interactionVisualBinding.allocate.destinations",
                        reason: "each destination requires a real target with fixed geometry, three distinct variants and a non-degenerate path from the source region into that target"
                    )
                }

                guard let railOrigin = cameraRail.keyframes.first?.center else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.cameraRail",
                        reason: "requires an authored origin"
                    )
                }
                for (pointIndex, point) in destination.transferPath.enumerated() {
                    let attachedLayer: SceneLayerSpec
                    if pointIndex == 0 {
                        attachedLayer = resourceLayer
                    } else if pointIndex == destination.transferPath.count - 1 {
                        attachedLayer = layer
                    } else {
                        attachedLayer = transferLayer
                    }
                    for crop in sceneCanvas.viewportCrops {
                        guard SceneRailGeometry.pointStaysVisible(
                            point,
                            parallaxFactor: attachedLayer.motion.parallaxFactor,
                            rail: cameraRail,
                            crop: crop,
                            railOrigin: railOrigin
                        ) else {
                            throw ContentValidationError.invalidValue(
                                field: "scene.interactionVisualBinding.allocate.destinations.transferPath[\(pointIndex)]",
                                reason: "every transfer control point must remain visible in crop '\(crop.id)' through the complete camera rail using its source, transfer or destination layer transform"
                            )
                        }
                    }
                    for crop in reduceMotionComposition.viewportCrops {
                        guard SceneRailGeometry.pointStaysVisibleInStaticCrop(
                            point,
                            crop: crop
                        ) else {
                            throw ContentValidationError.invalidValue(
                                field: "scene.interactionVisualBinding.allocate.destinations.transferPath[\(pointIndex)]",
                                reason: "every transfer control point must remain visible in reduced crop '\(crop.id)'"
                            )
                        }
                    }
                }
            }
        case let .assemble(configuration):
            try requireNonempty(
                configuration.interactionID,
                field: "scene.interactionVisualBinding.interactionID"
            )
            let sourceTargetIDs = configuration.components.map(\.sourceInteractionTargetID)
            let slotTargetIDs = configuration.components.compactMap(\.slotInteractionTargetID)
            let isLegacySingleTargetBinding = slotTargetIDs.isEmpty
            guard !configuration.components.isEmpty,
                  Set(configuration.components.map(\.componentID)).count
                    == configuration.components.count,
                  Set(sourceTargetIDs).count == configuration.components.count,
                  isLegacySingleTargetBinding
                    || (
                        slotTargetIDs.count == configuration.components.count
                            && Set(slotTargetIDs).count == configuration.components.count
                            && Set(sourceTargetIDs).isDisjoint(with: Set(slotTargetIDs))
                    ) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.assemble.components",
                    reason: "requires unique component bindings and globally distinct source and slot targets"
                )
            }
            for component in configuration.components {
                let slotTargetIsValid: Bool
                if let slotTargetID = component.slotInteractionTargetID {
                    slotTargetIsValid = isStableStringIdentifier(slotTargetID)
                        && targetByID[slotTargetID]?.layerID == component.layerID
                } else {
                    slotTargetIsValid = true
                }
                guard isStableStringIdentifier(component.componentID),
                      isStableStringIdentifier(component.sourceInteractionTargetID),
                      let layer = layerByID[component.layerID],
                      let sourceTarget = targetByID[component.sourceInteractionTargetID],
                      sourceTarget.layerID == component.layerID,
                      slotTargetIsValid,
                      visualVariants(
                          [
                              component.availableVariantID,
                              component.resistedVariantID,
                              component.placedVariantID,
                          ],
                          existOn: layer
                ) else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.interactionVisualBinding.assemble.components",
                        reason: "every component requires real layer-bound source and slot targets and three distinct component-state variants"
                    )
                }
            }
        case let .pressure(configuration):
            try requireNonempty(
                configuration.interactionID,
                field: "scene.interactionVisualBinding.interactionID"
            )
            guard !configuration.forces.isEmpty,
                  Set(configuration.forces.map(\.forceID)).count == configuration.forces.count,
                  configuration.forces.allSatisfy({ force in
                      guard isStableStringIdentifier(force.forceID),
                            layerByID[force.layerID] != nil else { return false }
                      guard let interactionTargetID = force.interactionTargetID else { return true }
                      return isStableStringIdentifier(interactionTargetID)
                        && targetByID[interactionTargetID]?.layerID == force.layerID
                  }),
                  let systemLayer = layerByID[configuration.systemLayerID],
                  visualVariants(
                      [
                          configuration.restingVariantID,
                          configuration.resistingVariantID,
                          configuration.stableVariantID,
                          configuration.brokenVariantID,
                      ],
                      existOn: systemLayer
                  ) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.pressure",
                    reason: "requires exact force layers, real controllable targets and four distinct system-state variants"
                )
            }
        case let .transform(configuration):
            try requireNonempty(
                configuration.interactionID,
                field: "scene.interactionVisualBinding.interactionID"
            )
            guard !configuration.stages.isEmpty,
                  Set(configuration.stages.map(\.stageID)).count == configuration.stages.count,
                  Set(configuration.stages.map(\.interactionTargetID)).count
                    == configuration.stages.count else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.transform.stages",
                    reason: "requires unique stage and target bindings"
                )
            }
            for stage in configuration.stages {
                guard isStableStringIdentifier(stage.stageID),
                      isStableStringIdentifier(stage.interactionTargetID),
                      let layer = layerByID[stage.layerID],
                      let target = targetByID[stage.interactionTargetID],
                      target.layerID == stage.layerID,
                      visualVariants(
                          [stage.beforeVariantID, stage.activeVariantID, stage.completedVariantID],
                          existOn: layer
                      ) else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.interactionVisualBinding.transform.stages",
                        reason: "every stage requires one real target and three distinct transformation variants"
                    )
                }
            }
        }
    }

    public func validateInteractionVisualBinding(to interaction: InteractionSpec) throws {
        guard let interactionVisualBinding else { return }
        switch (interactionVisualBinding, interaction.grammar) {
        case let (.trace(binding), .trace(configuration)):
            guard binding.interactionID == interaction.id else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.trace",
                    reason: "must bind the exact trace interaction"
                )
            }
            if configuration.anchorIDs != nil {
                let target = interactionTargets.first {
                    $0.interactionTargetID == binding.interactionTargetID
                }
                guard let target,
                      configuration.anchors.allSatisfy({
                          SceneHitRegionGeometry.contains($0, in: target.hitRegion)
                      }) else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.interactionVisualBinding.trace.interactionTargetID",
                        reason: "the bound route target must contain every named Trace anchor in master space"
                    )
                }
            }
            switch (configuration.anchorIDs, binding.reachedAnchorVariants) {
            case (nil, nil):
                break
            case let (.some(anchorIDs), .some(reachedAnchorVariants)):
                guard reachedAnchorVariants.map(\.anchorID)
                        == Array(anchorIDs.dropLast()) else {
                    throw ContentValidationError.invalidValue(
                        field: "scene.interactionVisualBinding.trace.reachedAnchorVariants",
                        reason: "must bind every nonterminal Trace anchor in authored order and by exact identity"
                    )
                }
            default:
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.trace.reachedAnchorVariants",
                    reason: "named Trace anchors and reached-anchor visual bindings must be authored together"
                )
            }
        case let (.allocate(binding), .allocate(configuration)):
            guard binding.interactionID == interaction.id,
                  Set(binding.destinations.map(\.destinationID))
                    == Set(configuration.destinations.map(\.id)),
                  binding.resource.variantsByRemainingUnits.last?.maximumRemainingUnits
                    == configuration.totalUnits,
                  binding.resource.variantsByRemainingUnits.allSatisfy({
                      $0.maximumRemainingUnits <= configuration.totalUnits
                  }) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.allocate",
                    reason: "must bind the exact interaction, destinations and finite resource total"
                )
            }
        case let (.assemble(binding), .assemble(configuration)):
            guard binding.interactionID == interaction.id,
                  Set(binding.components.map(\.componentID))
                    == Set(configuration.components.map(\.id)) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.assemble",
                    reason: "must bind the exact interaction and component set"
                )
            }
        case let (.pressure(binding), .pressure(configuration)):
            let forceByID = Dictionary(uniqueKeysWithValues: configuration.forces.map { ($0.id, $0) })
            guard binding.interactionID == interaction.id,
                  Set(binding.forces.map(\.forceID)) == Set(forceByID.keys),
                  binding.forces.allSatisfy({ forceBinding in
                      guard let force = forceByID[forceBinding.forceID] else { return false }
                      return force.userControllable == (forceBinding.interactionTargetID != nil)
                  }) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.pressure",
                    reason: "must bind every force and only controllable forces to interaction targets"
                )
            }
        case let (.transform(binding), .transform(configuration)):
            guard binding.interactionID == interaction.id,
                  Set(binding.stages.map(\.stageID)) == Set(configuration.stages.map(\.id)) else {
                throw ContentValidationError.invalidValue(
                    field: "scene.interactionVisualBinding.transform",
                    reason: "must bind the exact interaction and ordered-stage set"
                )
            }
        default:
            throw ContentValidationError.invalidValue(
                field: "scene.interactionVisualBinding",
                reason: "grammar must match the bound interaction"
            )
        }
    }

}

private func visualVariants(_ variantIDs: [String], existOn layer: SceneLayerSpec) -> Bool {
    variantIDs.allSatisfy(isStableStringIdentifier)
        && Set(variantIDs).count == variantIDs.count
        && variantIDs.allSatisfy { variantID in
            layer.stateVariants.contains(where: { $0.id == variantID })
        }
}

public enum AudioTrackRole: String, Codable, Equatable, Sendable {
    case narration
    case score
    case soundscape
    case spatialDetail
    case silence
}

public struct NarrationCueScope: Codable, Equatable, Sendable {
    public let chapterID: ChapterID
    public let arcID: ArcID
    public let beatID: BeatID

    public init(chapterID: ChapterID, arcID: ArcID, beatID: BeatID) {
        self.chapterID = chapterID
        self.arcID = arcID
        self.beatID = beatID
    }

    func validate(field: String) throws {
        try requireNonempty(chapterID, field: "\(field).chapterID")
        try requireNonempty(arcID, field: "\(field).arcID")
        try requireNonempty(beatID, field: "\(field).beatID")
    }
}

public struct NarrationCueBinding: Codable, Equatable, Sendable {
    public let manuscriptSegmentID: LocalizedStringID
    public let manuscriptSegmentSHA256: String
    public let scope: NarrationCueScope

    public init(
        manuscriptSegmentID: LocalizedStringID,
        manuscriptSegmentSHA256: String,
        scope: NarrationCueScope
    ) {
        self.manuscriptSegmentID = manuscriptSegmentID
        self.manuscriptSegmentSHA256 = manuscriptSegmentSHA256
        self.scope = scope
    }

    func validate(field: String) throws {
        try requireNonempty(manuscriptSegmentID, field: "\(field).manuscriptSegmentID")
        try scope.validate(field: "\(field).scope")
        guard manuscriptSegmentSHA256.count == 64,
              manuscriptSegmentSHA256.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
              }) else {
            throw ContentValidationError.invalidValue(
                field: "\(field).manuscriptSegmentSHA256",
                reason: "must be a lowercase SHA-256 digest"
            )
        }
    }
}

public struct AudioEvent: Codable, Equatable, Sendable {
    public let cueID: AudioCueID
    public let role: AudioTrackRole
    public let startSample: Int64
    public let durationSamples: Int64
    public let assetPath: String?
    public let gain: Double
    public let narrationBinding: NarrationCueBinding?

    public init(
        cueID: AudioCueID,
        role: AudioTrackRole,
        startSample: Int64,
        durationSamples: Int64,
        assetPath: String?,
        gain: Double,
        narrationBinding: NarrationCueBinding? = nil
    ) {
        self.cueID = cueID
        self.role = role
        self.startSample = startSample
        self.durationSamples = durationSamples
        self.assetPath = assetPath
        self.gain = gain
        self.narrationBinding = narrationBinding
    }
}

public enum HapticSemantic: String, Codable, Equatable, Hashable, Sendable {
    case contact
    case drag
    case resistance
    case transfer
    case `break`
    case seal
}

public struct HapticEvent: Codable, Equatable, Sendable {
    public let sample: Int64
    public let kind: HapticSemantic
    public let intensity: Double
    public let sharpness: Double

    public init(sample: Int64, kind: HapticSemantic, intensity: Double, sharpness: Double) {
        self.sample = sample
        self.kind = kind
        self.intensity = intensity
        self.sharpness = sharpness
    }
}

public struct AudioTimeline: Codable, Equatable, Sendable {
    public let id: AudioTimelineID
    public let sampleRate: Int
    public let events: [AudioEvent]
    public let haptics: [HapticEvent]

    public init(
        id: AudioTimelineID,
        sampleRate: Int,
        events: [AudioEvent],
        haptics: [HapticEvent]
    ) {
        self.id = id
        self.sampleRate = sampleRate
        self.events = events
        self.haptics = haptics
    }

    public func validate() throws {
        try requireNonempty(id, field: "audioTimeline.id")
        guard sampleRate == 48_000 else {
            throw ContentValidationError.invalidValue(
                field: "audioTimeline.sampleRate",
                reason: "authored masters must use 48 kHz"
            )
        }
        guard !events.isEmpty else {
            throw ContentValidationError.invalidCount(
                field: "audioTimeline.events",
                expected: "at least one",
                actual: 0
            )
        }
        try requireUnique(events.map(\.cueID))
        for event in events {
            try requireNonempty(event.cueID, field: "audioTimeline.events.cueID")
            guard (0 ... 9_007_199_254_740_991).contains(event.startSample),
                  (0 ... 9_007_199_254_740_991).contains(event.durationSamples),
                  event.gain.isFinite,
                  (0 ... 4).contains(event.gain) else {
                throw ContentValidationError.invalidValue(
                    field: "audioTimeline.events",
                    reason: "sample positions must be valid and linear gain must be between zero and four"
                )
            }
            if event.role == .silence {
                guard event.assetPath == nil else {
                    throw ContentValidationError.invalidValue(
                        field: "audioTimeline.events.assetPath",
                        reason: "silence cannot reference an asset"
                    )
                }
            } else {
                guard let assetPath = event.assetPath else {
                    throw ContentValidationError.invalidValue(
                        field: "audioTimeline.events.assetPath",
                        reason: "audible events require an offline asset"
                    )
                }
                try requireSafePackageAssetPath(assetPath)
            }
            if event.role == .narration {
                guard let narrationBinding = event.narrationBinding else {
                    throw ContentValidationError.invalidValue(
                        field: "audioTimeline.events.narrationBinding",
                        reason: "narration cues require an exact manuscript digest and chapter/arc/beat scope"
                    )
                }
                try narrationBinding.validate(field: "audioTimeline.events.narrationBinding")
            } else if event.narrationBinding != nil {
                throw ContentValidationError.invalidValue(
                    field: "audioTimeline.events.narrationBinding",
                    reason: "only narration cues can bind manuscript text"
                )
            }
        }
        for haptic in haptics {
            guard haptic.sample >= 0,
                  (0 ... 1).contains(haptic.intensity),
                  (0 ... 1).contains(haptic.sharpness) else {
                throw ContentValidationError.invalidValue(
                    field: "audioTimeline.haptics",
                    reason: "sample and unit-space values must be valid"
                )
            }
        }
    }
}

public enum AccessibilityRole: String, Codable, Equatable, Sendable {
    case image
    case heading
    case narration
    case mechanism
    case action
    case adjustable
    case status
}

public enum AccessibilityActionKind: String, Codable, Equatable, Sendable {
    case activate
    case increment
    case decrement
}

/// A closed, typed bridge from authored VoiceOver actions to the historical
/// interaction reducer. These commands are deliberately narrower than generic
/// UI callbacks: every token names a real operation in one of the five
/// interaction grammars.
public enum AccessibilityActionToken: Codable, Equatable, Hashable, Sendable {
    case traceNext
    case allocate(destinationID: String, unitsPerStep: Int)
    case commitAllocation
    case placeComponent(componentID: String)
    case adjustPressure(forceID: String, step: Double)
    case holdPressure
    case advanceTransform(stageID: String, step: Double)

    private enum Command: String, Codable {
        case traceNext = "trace-next"
        case allocate
        case commitAllocation = "commit-allocation"
        case placeComponent = "place-component"
        case adjustPressure = "adjust-pressure"
        case holdPressure = "hold-pressure"
        case advanceTransform = "advance-transform"
    }

    private enum CodingKeys: String, CodingKey {
        case command
        case targetID
        case unitsPerStep
        case step
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Command.self, forKey: .command) {
        case .traceNext:
            self = .traceNext
        case .allocate:
            self = .allocate(
                destinationID: try container.decode(String.self, forKey: .targetID),
                unitsPerStep: try container.decode(Int.self, forKey: .unitsPerStep)
            )
        case .commitAllocation:
            self = .commitAllocation
        case .placeComponent:
            self = .placeComponent(
                componentID: try container.decode(String.self, forKey: .targetID)
            )
        case .adjustPressure:
            self = .adjustPressure(
                forceID: try container.decode(String.self, forKey: .targetID),
                step: try container.decode(Double.self, forKey: .step)
            )
        case .holdPressure:
            self = .holdPressure
        case .advanceTransform:
            self = .advanceTransform(
                stageID: try container.decode(String.self, forKey: .targetID),
                step: try container.decode(Double.self, forKey: .step)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .traceNext:
            try container.encode(Command.traceNext, forKey: .command)
        case let .allocate(destinationID, unitsPerStep):
            try container.encode(Command.allocate, forKey: .command)
            try container.encode(destinationID, forKey: .targetID)
            try container.encode(unitsPerStep, forKey: .unitsPerStep)
        case .commitAllocation:
            try container.encode(Command.commitAllocation, forKey: .command)
        case let .placeComponent(componentID):
            try container.encode(Command.placeComponent, forKey: .command)
            try container.encode(componentID, forKey: .targetID)
        case let .adjustPressure(forceID, step):
            try container.encode(Command.adjustPressure, forKey: .command)
            try container.encode(forceID, forKey: .targetID)
            try container.encode(step, forKey: .step)
        case .holdPressure:
            try container.encode(Command.holdPressure, forKey: .command)
        case let .advanceTransform(stageID, step):
            try container.encode(Command.advanceTransform, forKey: .command)
            try container.encode(stageID, forKey: .targetID)
            try container.encode(step, forKey: .step)
        }
    }

    public func validate() throws {
        switch self {
        case .traceNext, .commitAllocation, .holdPressure:
            break
        case let .allocate(destinationID, unitsPerStep):
            guard isStableStringIdentifier(destinationID), unitsPerStep > 0 else {
                throw ContentValidationError.invalidValue(
                    field: "accessibility.elements.actions.token",
                    reason: "allocation tokens require a stable destination and positive integer step"
                )
            }
        case let .placeComponent(componentID):
            guard isStableStringIdentifier(componentID) else {
                throw ContentValidationError.invalidValue(
                    field: "accessibility.elements.actions.token",
                    reason: "component tokens require a stable component identifier"
                )
            }
        case let .adjustPressure(forceID, step):
            guard isStableStringIdentifier(forceID), step.isFinite, step > 0, step <= 1 else {
                throw ContentValidationError.invalidValue(
                    field: "accessibility.elements.actions.token",
                    reason: "pressure tokens require a stable force and a unit-space step"
                )
            }
        case let .advanceTransform(stageID, step):
            guard isStableStringIdentifier(stageID), step.isFinite, step > 0, step <= 1 else {
                throw ContentValidationError.invalidValue(
                    field: "accessibility.elements.actions.token",
                    reason: "transform tokens require a stable stage and a unit-space step"
                )
            }
        }
    }
}

public struct AccessibilityActionSpec: Codable, Equatable, Sendable {
    public let kind: AccessibilityActionKind
    public let label: LocalizedStringSpec
    public let token: AccessibilityActionToken

    public init(
        kind: AccessibilityActionKind,
        label: LocalizedStringSpec,
        token: AccessibilityActionToken
    ) {
        self.kind = kind
        self.label = label
        self.token = token
    }
}

public struct AccessibilityElementSpec: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let role: AccessibilityRole
    public let label: LocalizedStringSpec
    public let value: LocalizedStringSpec?
    public let hint: LocalizedStringSpec?
    public let actions: [AccessibilityActionSpec]

    public init(
        id: String,
        role: AccessibilityRole,
        label: LocalizedStringSpec,
        value: LocalizedStringSpec? = nil,
        hint: LocalizedStringSpec? = nil,
        actions: [AccessibilityActionSpec] = []
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.value = value
        self.hint = hint
        self.actions = actions
    }
}

public struct AccessibilitySpec: Codable, Equatable, Identifiable, Sendable {
    public let id: AccessibilityID
    public let sceneSummary: LocalizedStringSpec
    public let elements: [AccessibilityElementSpec]

    public init(
        id: AccessibilityID,
        sceneSummary: LocalizedStringSpec,
        elements: [AccessibilityElementSpec]
    ) {
        self.id = id
        self.sceneSummary = sceneSummary
        self.elements = elements
    }

    public func validate() throws {
        try requireNonempty(id, field: "accessibility.id")
        try sceneSummary.validate(field: "accessibility.sceneSummary")
        guard !elements.isEmpty,
              Set(elements.map(\.id)).count == elements.count else {
            throw ContentValidationError.invalidValue(
                field: "accessibility",
                reason: "requires a summary and uniquely identified elements"
            )
        }
        var localizedStrings = [sceneSummary]
        for element in elements {
            guard isStableStringIdentifier(element.id) else {
                throw ContentValidationError.invalidValue(
                    field: "accessibility.elements",
                    reason: "stable element IDs are required"
                )
            }
            try element.label.validate(field: "accessibility.elements.\(element.id).label")
            try element.value?.validate(field: "accessibility.elements.\(element.id).value")
            try element.hint?.validate(field: "accessibility.elements.\(element.id).hint")
            localizedStrings.append(element.label)
            localizedStrings.append(contentsOf: [element.value, element.hint].compactMap { $0 })
            let isOperableRole = element.role == .action || element.role == .adjustable
            guard isOperableRole == !element.actions.isEmpty else {
                throw ContentValidationError.invalidValue(
                    field: "accessibility.elements.actions",
                    reason: "action and adjustable elements must be operable; descriptive elements cannot carry actions"
                )
            }
            var actionBindings: Set<String> = []
            for action in element.actions {
                try action.label.validate(field: "accessibility.elements.actions.label")
                localizedStrings.append(action.label)
                guard (element.role == .action && action.kind == .activate)
                    || (element.role == .adjustable && action.kind != .activate) else {
                    throw ContentValidationError.invalidValue(
                        field: "accessibility.elements.actions.kind",
                        reason: "action elements activate; adjustable elements increment or decrement"
                    )
                }
                try action.token.validate()
                let key = "\(action.kind.rawValue):\(action.token)"
                guard actionBindings.insert(key).inserted else {
                    throw ContentValidationError.invalidValue(
                        field: "accessibility.elements.actions",
                        reason: "duplicate semantic action binding"
                    )
                }
            }
        }
        try requireConsistentLocalizedStrings(
            localizedStrings,
            field: "accessibility.localizedStrings"
        )
    }

    /// Validates that every authored semantic action is bound to this exact
    /// interaction grammar and that the complete causal path is operable with
    /// VoiceOver. Runtime parity is verified in JourneyAccessibility; this
    /// structural gate keeps malformed bindings out of a decoded package.
    public func validateBinding(to interaction: InteractionSpec) throws {
        guard id == interaction.accessibilityID else {
            throw ContentValidationError.invalidValue(
                field: "accessibility.id",
                reason: "must equal the interaction accessibilityID"
            )
        }
        let allActions = elements.flatMap(\.actions)

        func matchingActions(
            kind: AccessibilityActionKind,
            matching token: (AccessibilityActionToken) -> Bool
        ) -> [AccessibilityActionSpec] {
            allActions.filter { $0.kind == kind && token($0.token) }
        }

        func requireExactlyOne(
            _ matches: [AccessibilityActionSpec],
            description: String
        ) throws -> AccessibilityActionSpec {
            guard matches.count == 1, let action = matches.first else {
                throw ContentValidationError.invalidValue(
                    field: "accessibility.elements.actions",
                    reason: "requires exactly one \(description) binding"
                )
            }
            return action
        }

        switch interaction.grammar {
        case .trace:
            guard allActions.allSatisfy({
                if case .traceNext = $0.token { return $0.kind == .increment }
                return false
            }) else {
                throw invalidAccessibilityBinding(for: "trace")
            }
            _ = try requireExactlyOne(
                matchingActions(kind: .increment) {
                    if case .traceNext = $0 { return true }
                    return false
                },
                description: "trace-next"
            )

        case let .allocate(configuration):
            let knownDestinations = Set(configuration.destinations.map(\.id))
            let minimumTotal = configuration.destinations.reduce(0) {
                $0 + $1.minimumUnits
            }
            let surplus = configuration.totalUnits - minimumTotal
            guard allActions.allSatisfy({ action in
                switch action.token {
                case let .allocate(destinationID, _):
                    return knownDestinations.contains(destinationID)
                        && (action.kind == .increment || action.kind == .decrement)
                case .commitAllocation:
                    return action.kind == .activate
                default:
                    return false
                }
            }) else {
                throw invalidAccessibilityBinding(for: "allocate")
            }
            for (index, destination) in configuration.destinations.enumerated() {
                let increments = matchingActions(kind: .increment) {
                    if case let .allocate(destinationID, _) = $0 {
                        return destinationID == destination.id
                    }
                    return false
                }
                let decrements = matchingActions(kind: .decrement) {
                    if case let .allocate(destinationID, _) = $0 {
                        return destinationID == destination.id
                    }
                    return false
                }
                let increment = try requireExactlyOne(
                    increments,
                    description: "increment for allocation destination '\(destination.id)'"
                )
                let decrement = try requireExactlyOne(
                    decrements,
                    description: "decrement for allocation destination '\(destination.id)'"
                )
                guard case let .allocate(_, incrementStep) = increment.token,
                      case let .allocate(_, decrementStep) = decrement.token,
                      incrementStep > 0,
                      incrementStep == decrementStep,
                      (destination.minimumUnits + (index == 0 ? surplus : 0))
                        .isMultiple(of: incrementStep) else {
                    throw ContentValidationError.invalidValue(
                        field: "accessibility.elements.actions.token",
                        reason: "allocation steps must match and reach one complete minimum-plus-surplus distribution"
                    )
                }
            }
            _ = try requireExactlyOne(
                matchingActions(kind: .activate) { $0 == .commitAllocation },
                description: "commit-allocation"
            )

        case let .assemble(configuration):
            let knownComponents = Set(configuration.components.map(\.id))
            guard allActions.allSatisfy({ action in
                guard action.kind == .activate,
                      case let .placeComponent(componentID) = action.token else { return false }
                return knownComponents.contains(componentID)
            }) else {
                throw invalidAccessibilityBinding(for: "assemble")
            }
            for component in configuration.components {
                _ = try requireExactlyOne(
                    matchingActions(kind: .activate) {
                        if case let .placeComponent(componentID) = $0 {
                            return componentID == component.id
                        }
                        return false
                    },
                    description: "place-component for '\(component.id)'"
                )
            }

        case let .pressure(configuration):
            let controllableForces = configuration.forces.filter(\.userControllable)
            let knownForces = Set(controllableForces.map(\.id))
            guard allActions.allSatisfy({ action in
                switch action.token {
                case let .adjustPressure(forceID, _):
                    return knownForces.contains(forceID)
                        && (action.kind == .increment || action.kind == .decrement)
                case .holdPressure:
                    return action.kind == .activate
                default:
                    return false
                }
            }) else {
                throw invalidAccessibilityBinding(for: "pressure")
            }
            for force in controllableForces {
                let increments = matchingActions(kind: .increment) {
                    if case let .adjustPressure(forceID, _) = $0 { return forceID == force.id }
                    return false
                }
                let decrements = matchingActions(kind: .decrement) {
                    if case let .adjustPressure(forceID, _) = $0 { return forceID == force.id }
                    return false
                }
                let increment = try requireExactlyOne(
                    increments,
                    description: "increment for pressure force '\(force.id)'"
                )
                let decrement = try requireExactlyOne(
                    decrements,
                    description: "decrement for pressure force '\(force.id)'"
                )
                guard case let .adjustPressure(_, incrementStep) = increment.token,
                      case let .adjustPressure(_, decrementStep) = decrement.token,
                      abs(incrementStep - decrementStep) < 0.000_000_001 else {
                    throw ContentValidationError.invalidValue(
                        field: "accessibility.elements.actions.token",
                        reason: "pressure increment and decrement must use the same authored step"
                    )
                }
            }
            _ = try requireExactlyOne(
                matchingActions(kind: .activate) { $0 == .holdPressure },
                description: "hold-pressure"
            )

        case let .transform(configuration):
            let knownStages = Set(configuration.stages.map(\.id))
            guard allActions.allSatisfy({ action in
                guard action.kind == .increment,
                      case let .advanceTransform(stageID, _) = action.token else { return false }
                return knownStages.contains(stageID)
            }) else {
                throw invalidAccessibilityBinding(for: "transform")
            }
            for stage in configuration.stages {
                _ = try requireExactlyOne(
                    matchingActions(kind: .increment) {
                        if case let .advanceTransform(stageID, _) = $0 { return stageID == stage.id }
                        return false
                    },
                    description: "advance-transform for '\(stage.id)'"
                )
            }
        }
    }
}

private func invalidAccessibilityBinding(for grammar: String) -> ContentValidationError {
    .invalidValue(
        field: "accessibility.elements.actions.token",
        reason: "contains an action that is unbound to the \(grammar) interaction"
    )
}

public struct Release: Codable, Equatable, Identifiable, Sendable {
    public let id: ReleaseID
    public let contentID: String
    public let packageID: PackageID
    public let version: SchemaVersion
    public let chapterIDs: [ChapterID]
    public let maximumInstalledBytes: Int64
    public let publishedAtUnixMillis: Int64
    public let minimumRuntime: SchemaVersion

    public init(
        id: ReleaseID,
        contentID: String,
        packageID: PackageID,
        version: SchemaVersion,
        chapterIDs: [ChapterID],
        maximumInstalledBytes: Int64,
        publishedAtUnixMillis: Int64,
        minimumRuntime: SchemaVersion
    ) {
        self.id = id
        self.contentID = contentID
        self.packageID = packageID
        self.version = version
        self.chapterIDs = chapterIDs
        self.maximumInstalledBytes = maximumInstalledBytes
        self.publishedAtUnixMillis = publishedAtUnixMillis
        self.minimumRuntime = minimumRuntime
    }

    /// Validates the independently delivered release-catalog record before it
    /// becomes the trusted package specification for a downloaded deep dive.
    public func validate() throws {
        try requireNonempty(id, field: "release.id")
        try requireNonempty(packageID, field: "release.packageID")
        try requireUnique(chapterIDs)
        for chapterID in chapterIDs {
            try requireNonempty(chapterID, field: "release.chapterIDs")
        }
        guard isStableStringIdentifier(contentID),
              chapterIDs.contains(ChapterID(contentID)),
              !chapterIDs.isEmpty,
              version.isValid,
              minimumRuntime.isValid,
              maximumInstalledBytes > 0,
              publishedAtUnixMillis >= 0 else {
            throw ContentValidationError.invalidValue(
                field: "release",
                reason: "stable content ownership, valid versions, a positive byte budget and a publication time are required"
            )
        }
    }

    /// Derives the exact package contract consumed by `ContentPackageVerifier`.
    /// The caller must first obtain this Release through the trusted release
    /// catalog; a package may never trust a Release found only inside itself.
    public func packageSpecForVerification() throws -> ContentPackageSpec {
        try validate()
        return ContentPackageSpec(
            id: packageID,
            version: version,
            chapterIDs: chapterIDs,
            maximumInstalledBytes: maximumInstalledBytes,
            minimumRuntime: minimumRuntime,
            isEssentialInstall: false
        )
    }
}

/// Fail-closed decoder for independently delivered public Release records.
/// `JSONDecoder` alone ignores unknown fields, which is unsuitable for a record
/// that becomes the trusted package boundary.
public enum ReleaseCatalogDecoder {
    private static let releaseKeys: Set<String> = [
        "id", "contentID", "packageID", "version", "chapterIDs",
        "maximumInstalledBytes", "publishedAtUnixMillis", "minimumRuntime",
    ]
    private static let versionKeys: Set<String> = ["major", "minor", "patch"]

    public static func decode(_ data: Data) throws -> Release {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ContentValidationError.invalidValue(
                field: "release",
                reason: "valid JSON is required"
            )
        }
        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == releaseKeys,
              hasExactVersionShape(dictionary["version"]),
              hasExactVersionShape(dictionary["minimumRuntime"]) else {
            throw ContentValidationError.invalidValue(
                field: "release",
                reason: "the exact public Release wire fields are required"
            )
        }
        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: data)
        } catch {
            throw ContentValidationError.invalidValue(
                field: "release",
                reason: "field types do not match the Release wire contract"
            )
        }
        try release.validate()
        return release
    }

    private static func hasExactVersionShape(_ value: Any?) -> Bool {
        guard let dictionary = value as? [String: Any] else { return false }
        return Set(dictionary.keys) == versionKeys
    }
}
