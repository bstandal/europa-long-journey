import ContentKit
import Foundation

/// Decodes one digest-bound alpha mask at the rendering boundary. The resolver
/// supplies coordinates in the selected layer variant's unit space; callers
/// must not substitute a different mask or infer opacity from the polygon.
public protocol SceneAlphaMaskSampling: Sendable {
    func isOpaque(
        in alphaMask: SceneResolvedAsset,
        at unitPoint: NormalizedPoint
    ) throws -> Bool
}

public struct SceneTouchTargetHit: Equatable, Sendable {
    public let interactionTargetID: String
    public let accessibilityElementID: String
    public let layerID: SceneLayerID
    public let viewportPosition: SceneFramePoint
    public let masterPosition: NormalizedPoint

    public init(
        interactionTargetID: String,
        accessibilityElementID: String,
        layerID: SceneLayerID,
        viewportPosition: SceneFramePoint,
        masterPosition: NormalizedPoint
    ) {
        self.interactionTargetID = interactionTargetID
        self.accessibilityElementID = accessibilityElementID
        self.layerID = layerID
        self.viewportPosition = viewportPosition
        self.masterPosition = masterPosition
    }
}

public struct SceneTouchSourceContact: Equatable, Sendable {
    public let interactionID: InteractionID
    public let layerID: SceneLayerID
    public let viewportPosition: SceneFramePoint
    public let masterPosition: NormalizedPoint
    public let alphaMaskPosition: NormalizedPoint

    public init(
        interactionID: InteractionID,
        layerID: SceneLayerID,
        viewportPosition: SceneFramePoint,
        masterPosition: NormalizedPoint,
        alphaMaskPosition: NormalizedPoint
    ) {
        self.interactionID = interactionID
        self.layerID = layerID
        self.viewportPosition = viewportPosition
        self.masterPosition = masterPosition
        self.alphaMaskPosition = alphaMaskPosition
    }
}

public enum SceneTouchGeometryError: Error, Equatable, Sendable {
    case mismatchedScene
    case invalidViewportPoint
    case missingLayer(SceneLayerID)
    case ambiguousLayer(SceneLayerID)
    case invalidMasterProjection
    case ambiguousTarget
    case sourceNotAuthored
    case outsideSourcePolygon
    case unsupportedSourceHitTest
    case invalidAlphaMaskProjection
    case sourceAlphaRejected
}

/// Resolves touch geometry from the immutable frame that Metal is displaying.
/// It uses the frame's exact camera and layer motion, so touch, hit regions and
/// rendered pixels cannot drift onto different coordinate systems.
public enum SceneTouchGeometryResolver {
    public static func masterPoint(
        for viewportPoint: SceneFramePoint,
        in frame: SceneFramePlan,
        boundTo layerID: SceneLayerID? = nil
    ) throws -> NormalizedPoint {
        try requireViewportPoint(viewportPoint)
        let motion: SceneLayerMotionState
        if let layerID {
            motion = try layerCommand(layerID, in: frame).motion
        } else {
            motion = .still
        }
        let source = frame.camera.sourceRect
        let master = NormalizedPoint(
            x: source.x + (viewportPoint.x - motion.parallaxOffset.dx
                - motion.windOffset.dx) * source.width,
            y: source.y + (viewportPoint.y - motion.parallaxOffset.dy
                - motion.windOffset.dy) * source.height
        )
        guard master.isUnitPoint else {
            throw SceneTouchGeometryError.invalidMasterProjection
        }
        return master
    }

    public static func target(
        at viewportPoint: SceneFramePoint,
        in frame: SceneFramePlan
    ) throws -> SceneTouchTargetHit? {
        try requireViewportPoint(viewportPoint)
        let matches = frame.interactionHitRegions.filter {
            contains(viewportPoint, polygon: $0.viewportPath)
        }
        guard matches.count <= 1 else {
            throw SceneTouchGeometryError.ambiguousTarget
        }
        guard let match = matches.first else { return nil }
        return SceneTouchTargetHit(
            interactionTargetID: match.interactionTargetID,
            accessibilityElementID: match.accessibilityElementID,
            layerID: match.layerID,
            viewportPosition: viewportPoint,
            masterPosition: try masterPoint(
                for: viewportPoint,
                in: frame,
                boundTo: match.layerID
            )
        )
    }

    public static func sourceContact(
        at viewportPoint: SceneFramePoint,
        in frame: SceneFramePlan,
        alphaSampler: any SceneAlphaMaskSampling
    ) throws -> SceneTouchSourceContact {
        try requireViewportPoint(viewportPoint)
        guard let source = frame.interactionSourceHitRegion else {
            throw SceneTouchGeometryError.sourceNotAuthored
        }
        guard contains(viewportPoint, polygon: source.viewportPath) else {
            throw SceneTouchGeometryError.outsideSourcePolygon
        }
        guard source.hitTest == .selectedVariantAlpha else {
            throw SceneTouchGeometryError.unsupportedSourceHitTest
        }

        let command = try layerCommand(source.layerID, in: frame)
        let offset = SceneFrameVector(
            dx: command.motion.parallaxOffset.dx + command.motion.windOffset.dx,
            dy: command.motion.parallaxOffset.dy + command.motion.windOffset.dy
        )
        guard command.viewportFrame.width.isFinite,
              command.viewportFrame.height.isFinite,
              command.viewportFrame.width > 0,
              command.viewportFrame.height > 0 else {
            throw SceneTouchGeometryError.invalidAlphaMaskProjection
        }
        let alphaPoint = NormalizedPoint(
            x: (viewportPoint.x - command.viewportFrame.x - offset.dx)
                / command.viewportFrame.width,
            y: (viewportPoint.y - command.viewportFrame.y - offset.dy)
                / command.viewportFrame.height
        )
        guard alphaPoint.isUnitPoint else {
            throw SceneTouchGeometryError.invalidAlphaMaskProjection
        }
        guard try alphaSampler.isOpaque(
            in: source.selectedVariantAlphaMask,
            at: alphaPoint
        ) else {
            throw SceneTouchGeometryError.sourceAlphaRejected
        }

        return SceneTouchSourceContact(
            interactionID: source.interactionID,
            layerID: source.layerID,
            viewportPosition: viewportPoint,
            masterPosition: try masterPoint(
                for: viewportPoint,
                in: frame,
                boundTo: source.layerID
            ),
            alphaMaskPosition: alphaPoint
        )
    }

    private static func layerCommand(
        _ layerID: SceneLayerID,
        in frame: SceneFramePlan
    ) throws -> SceneDrawCommand {
        let matches = frame.drawCommands.filter { command in
            guard case let .layer(candidate, _) = command.source else { return false }
            return candidate == layerID
        }
        guard !matches.isEmpty else {
            throw SceneTouchGeometryError.missingLayer(layerID)
        }
        guard matches.count == 1, let command = matches.first else {
            throw SceneTouchGeometryError.ambiguousLayer(layerID)
        }
        return command
    }

    private static func requireViewportPoint(_ point: SceneFramePoint) throws {
        guard point.x.isFinite, point.y.isFinite,
              (0 ... 1).contains(point.x),
              (0 ... 1).contains(point.y) else {
            throw SceneTouchGeometryError.invalidViewportPoint
        }
    }

    private static func contains(
        _ point: SceneFramePoint,
        polygon: [SceneFramePoint]
    ) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
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
