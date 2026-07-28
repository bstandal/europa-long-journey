import Combine
import ContentKit
import Foundation
import Metal
import MetalKit
import QualityInstrumentation
import simd

/// The sampling interpretation is part of a texture's identity. Reusing the
/// same signed bytes as colour and mask data therefore cannot accidentally
/// make one decoder configuration win by cache insertion order.
public enum SceneTextureSampling: String, Equatable, Hashable, Sendable {
    case colorSRGB
    case linearMask
}

/// Stable identity for decoded GPU content. Every field comes from the
/// activated package's signed file record through `SceneResolvedAsset`.
public struct SceneMetalTextureKey: Equatable, Hashable, Sendable {
    public let packagePath: String
    public let byteCount: Int64
    public let sha256: String
    public let sampling: SceneTextureSampling

    public init(
        packagePath: String,
        byteCount: Int64,
        sha256: String,
        sampling: SceneTextureSampling
    ) {
        self.packagePath = packagePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.sampling = sampling
    }

    fileprivate init(asset: SceneResolvedAsset, sampling: SceneTextureSampling) {
        self.init(
            packagePath: asset.packagePath,
            byteCount: asset.byteCount,
            sha256: asset.sha256,
            sampling: sampling
        )
    }
}

public struct SceneMetalTextureRequest: Equatable, Sendable {
    public let key: SceneMetalTextureKey
    public let asset: SceneResolvedAsset

    fileprivate init(asset: SceneResolvedAsset, sampling: SceneTextureSampling) {
        self.key = SceneMetalTextureKey(asset: asset, sampling: sampling)
        self.asset = asset
    }
}

public struct SceneMetalMaskBindings: Equatable, Sendable {
    public let alpha: SceneMetalTextureKey?
    public let occlusion: SceneMetalTextureKey?
    public let depth: SceneMetalTextureKey?
    public let light: SceneMetalTextureKey?

    public init(
        alpha: SceneMetalTextureKey?,
        occlusion: SceneMetalTextureKey?,
        depth: SceneMetalTextureKey?,
        light: SceneMetalTextureKey?
    ) {
        self.alpha = alpha
        self.occlusion = occlusion
        self.depth = depth
        self.light = light
    }

    public var all: [SceneMetalTextureKey] {
        [alpha, occlusion, depth, light].compactMap { $0 }
    }
}

/// A pure, Metal-independent command that is safe to compare in simulator
/// tests. Its order is the authored back-to-front order from `SceneFramePlan`.
public struct SceneMetalDrawPlan: Equatable, Sendable {
    public let source: SceneDrawSource
    public let authoredOrder: Int
    public let depth: Double
    public let viewportFrame: SceneFrameRect
    public let opacity: Double
    public let blendMode: SceneBlendMode
    public let motion: SceneLayerMotionState
    public let interactionOffset: SceneFrameVector
    /// Static, non-transport feedback authored by the current interaction.
    /// These values remain available in Reduce Motion where spatial offsets
    /// are deliberately suppressed.
    public let interactionContactAmount: Double
    public let interactionResistanceAmount: Double
    public let colorTexture: SceneMetalTextureKey
    public let masks: SceneMetalMaskBindings

    public init(
        source: SceneDrawSource,
        authoredOrder: Int,
        depth: Double,
        viewportFrame: SceneFrameRect,
        opacity: Double,
        blendMode: SceneBlendMode,
        motion: SceneLayerMotionState,
        interactionOffset: SceneFrameVector,
        interactionContactAmount: Double,
        interactionResistanceAmount: Double,
        colorTexture: SceneMetalTextureKey,
        masks: SceneMetalMaskBindings
    ) {
        self.source = source
        self.authoredOrder = authoredOrder
        self.depth = depth
        self.viewportFrame = viewportFrame
        self.opacity = opacity
        self.blendMode = blendMode
        self.motion = motion
        self.interactionOffset = interactionOffset
        self.interactionContactAmount = interactionContactAmount
        self.interactionResistanceAmount = interactionResistanceAmount
        self.colorTexture = colorTexture
        self.masks = masks
    }
}

/// Immutable bridge between the pure frame planner and GPU preparation.
/// Texture requests are deduplicated in deterministic first-use order.
public struct SceneMetalPreparationPlan: Equatable, Sendable {
    public let sceneID: SceneID
    public let viewport: SceneFrameSize
    public let deterministicTick: UInt64
    public let reduceMotion: Bool
    public let textureRequests: [SceneMetalTextureRequest]
    public let drawCommands: [SceneMetalDrawPlan]
    public let atmosphere: [SceneAtmosphereState]

    public init(
        sceneID: SceneID,
        viewport: SceneFrameSize,
        deterministicTick: UInt64,
        reduceMotion: Bool,
        textureRequests: [SceneMetalTextureRequest],
        drawCommands: [SceneMetalDrawPlan],
        atmosphere: [SceneAtmosphereState]
    ) {
        self.sceneID = sceneID
        self.viewport = viewport
        self.deterministicTick = deterministicTick
        self.reduceMotion = reduceMotion
        self.textureRequests = textureRequests
        self.drawCommands = drawCommands
        self.atmosphere = atmosphere
    }
}

public enum SceneMetalPreparationError: Error, Equatable, Sendable {
    case invalidViewport
    case emptyComposition
    case invalidCamera
    case ambiguousAuthoredOrder(Int)
    case unorderedAuthoredOrder(previous: Int, next: Int)
    case invalidDrawCommand(Int)
    case conflictingSignedIdentity(String)
    case reduceMotionContainsMotion(Int)
    case reduceMotionContainsCameraTravel
    case reduceMotionContainsAtmosphereTravel(Int)
    case reduceMotionMissingStaticComposition
    case normalCompositionContainsStaticStratum(Int)
}

/// Converts an already immutable `SceneFramePlan` into a deterministic GPU
/// preparation plan. It never reads a file, decodes an image or touches Metal.
public enum SceneMetalPreparationPlanner {
    public static func make(
        from framePlan: SceneFramePlan
    ) throws -> SceneMetalPreparationPlan {
        guard isFinitePositive(framePlan.viewport.width),
              isFinitePositive(framePlan.viewport.height) else {
            throw SceneMetalPreparationError.invalidViewport
        }
        guard !framePlan.drawCommands.isEmpty else {
            throw SceneMetalPreparationError.emptyComposition
        }
        guard valid(framePlan.camera) else {
            throw SceneMetalPreparationError.invalidCamera
        }

        var seenOrders: Set<Int> = []
        var previousOrder: Int?
        var signedIdentityByPath: [String: (bytes: Int64, digest: String)] = [:]
        var textureRequests: [SceneMetalTextureRequest] = []
        var seenTextureKeys: Set<SceneMetalTextureKey> = []
        var drawPlans: [SceneMetalDrawPlan] = []
        var containsReducedStaticComposition = false

        func request(
            _ asset: SceneResolvedAsset,
            sampling: SceneTextureSampling
        ) throws -> SceneMetalTextureKey {
            if let identity = signedIdentityByPath[asset.packagePath],
               identity.bytes != asset.byteCount || identity.digest != asset.sha256 {
                throw SceneMetalPreparationError.conflictingSignedIdentity(asset.packagePath)
            }
            signedIdentityByPath[asset.packagePath] = (asset.byteCount, asset.sha256)
            let textureRequest = SceneMetalTextureRequest(asset: asset, sampling: sampling)
            if seenTextureKeys.insert(textureRequest.key).inserted {
                textureRequests.append(textureRequest)
            }
            return textureRequest.key
        }

        for (index, command) in framePlan.drawCommands.enumerated() {
            guard seenOrders.insert(command.authoredOrder).inserted else {
                throw SceneMetalPreparationError.ambiguousAuthoredOrder(command.authoredOrder)
            }
            if let previousOrder, previousOrder >= command.authoredOrder {
                throw SceneMetalPreparationError.unorderedAuthoredOrder(
                    previous: previousOrder,
                    next: command.authoredOrder
                )
            }
            previousOrder = command.authoredOrder
            guard valid(command) else {
                throw SceneMetalPreparationError.invalidDrawCommand(index)
            }

            switch command.source {
            case .reduceMotionStaticStratum:
                containsReducedStaticComposition = true
                guard framePlan.reduceMotion else {
                    throw SceneMetalPreparationError.normalCompositionContainsStaticStratum(index)
                }
            case .layer:
                break
            }

            if framePlan.reduceMotion, command.motion != .still {
                throw SceneMetalPreparationError.reduceMotionContainsMotion(index)
            }

            let color = try request(command.asset, sampling: .colorSRGB)
            let masks = SceneMetalMaskBindings(
                alpha: try command.masks.alpha.map { try request($0, sampling: .linearMask) },
                occlusion: try command.masks.occlusion.map {
                    try request($0, sampling: .linearMask)
                },
                depth: try command.masks.depth.map { try request($0, sampling: .linearMask) },
                light: try command.masks.light.map { try request($0, sampling: .linearMask) }
            )
            let interactionAmounts = interactionAmounts(
                for: command,
                response: framePlan.interactionResponse
            )
            drawPlans.append(
                SceneMetalDrawPlan(
                    source: command.source,
                    authoredOrder: command.authoredOrder,
                    depth: command.depth,
                    viewportFrame: command.viewportFrame,
                    opacity: command.opacity,
                    blendMode: command.blendMode,
                    motion: command.motion,
                    interactionOffset: interactionOffset(
                        for: command,
                        response: framePlan.interactionResponse,
                        reduceMotion: framePlan.reduceMotion
                    ),
                    interactionContactAmount: interactionAmounts.contact,
                    interactionResistanceAmount: interactionAmounts.resistance,
                    colorTexture: color,
                    masks: masks
                )
            )
        }

        if framePlan.reduceMotion {
            guard !framePlan.camera.followsAuthoredRail else {
                throw SceneMetalPreparationError.reduceMotionContainsCameraTravel
            }
            guard containsReducedStaticComposition else {
                throw SceneMetalPreparationError.reduceMotionMissingStaticComposition
            }
            for atmosphere in framePlan.atmosphere where atmosphere.travel != .zero {
                throw SceneMetalPreparationError.reduceMotionContainsAtmosphereTravel(
                    atmosphere.authoredIndex
                )
            }
        }

        return SceneMetalPreparationPlan(
            sceneID: framePlan.sceneID,
            viewport: framePlan.viewport,
            deterministicTick: framePlan.deterministicTick,
            reduceMotion: framePlan.reduceMotion,
            textureRequests: textureRequests,
            drawCommands: drawPlans,
            atmosphere: framePlan.atmosphere
        )
    }

    private static func isFinitePositive(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    private static func valid(_ camera: SceneCameraTransform) -> Bool {
        camera.masterCenter.x.isFinite && camera.masterCenter.y.isFinite
            && camera.viewportCenter.x.isFinite && camera.viewportCenter.y.isFinite
            && isFinitePositive(camera.scale)
            && valid(camera.sourceRect)
    }

    private static func valid(_ command: SceneDrawCommand) -> Bool {
        valid(command.viewportFrame)
            && command.depth.isFinite && (0 ... 1).contains(command.depth)
            && command.opacity.isFinite && (0 ... 1).contains(command.opacity)
            && valid(command.motion.parallaxOffset)
            && valid(command.motion.windOffset)
            && command.motion.focusAmount.isFinite
            && (0 ... 1).contains(command.motion.focusAmount)
    }

    private static func valid(_ rect: SceneFrameRect) -> Bool {
        rect.x.isFinite && rect.y.isFinite
            && isFinitePositive(rect.width) && isFinitePositive(rect.height)
    }

    private static func valid(_ vector: SceneFrameVector) -> Bool {
        vector.dx.isFinite && vector.dy.isFinite
    }

    private static func interactionOffset(
        for command: SceneDrawCommand,
        response: SceneInteractionResponsePlan?,
        reduceMotion: Bool
    ) -> SceneFrameVector {
        SceneMetalInteractionOffsetResolver.resolve(
            source: command.source,
            viewportFrame: command.viewportFrame,
            response: response,
            reduceMotion: reduceMotion,
            fallback: .zero
        )
    }

    private static func interactionAmounts(
        for command: SceneDrawCommand,
        response: SceneInteractionResponsePlan?
    ) -> (contact: Double, resistance: Double) {
        guard let response,
              case let .layer(layerID, _) = command.source,
              layerID == response.transferLayerID else {
            return (0, 0)
        }
        return (
            min(1, max(0, response.contactAmount)),
            min(1, max(0, response.resistanceAmount))
        )
    }
}

/// Shared pure geometry for the prepared frame and a clock-sampled transient
/// response. Keeping this outside the renderer prevents the 60 Hz snap-back
/// path from inventing a second coordinate system.
enum SceneMetalInteractionOffsetResolver {
    static func resolve(
        source: SceneDrawSource,
        viewportFrame: SceneFrameRect,
        response: SceneInteractionResponsePlan?,
        reduceMotion: Bool,
        fallback: SceneFrameVector
    ) -> SceneFrameVector {
        guard !reduceMotion, let response,
              let position = response.viewportMaterialPosition,
              case let .layer(layerID, _) = source,
              layerID == response.transferLayerID else {
            return fallback
        }
        let anchor = response.viewportTransferLayerAnchor ?? SceneFramePoint(
            x: viewportFrame.x + viewportFrame.width * 0.5,
            y: viewportFrame.y + viewportFrame.height * 0.5
        )
        return SceneFrameVector(
            dx: position.x - anchor.x,
            dy: position.y - anchor.y
        )
    }
}

public enum SceneMetalTextureResolutionError: Error, Equatable, Sendable {
    case duplicateResolvedTexture(SceneMetalTextureKey)
    case missingTexture(SceneMetalTextureKey)
    case unexpectedTexture(SceneMetalTextureKey)
}

/// The renderer commits a scene only after this exact-set check succeeds.
/// Partial image or mask resolution can therefore never produce a frame.
public enum SceneMetalTextureResolutionGate {
    public static func validate(
        required: [SceneMetalTextureKey],
        resolved: [SceneMetalTextureKey]
    ) throws {
        let requiredSet = Set(required)
        var resolvedSet: Set<SceneMetalTextureKey> = []
        for key in resolved {
            guard resolvedSet.insert(key).inserted else {
                throw SceneMetalTextureResolutionError.duplicateResolvedTexture(key)
            }
        }
        if let missing = required.first(where: { !resolvedSet.contains($0) }) {
            throw SceneMetalTextureResolutionError.missingTexture(missing)
        }
        if let unexpected = resolved.first(where: { !requiredSet.contains($0) }) {
            throw SceneMetalTextureResolutionError.unexpectedTexture(unexpected)
        }
    }
}

public enum SceneMetalCompositorFailure: Error, Equatable, Sendable {
    case metalDeviceUnavailable
    case shaderLibraryCompilationFailed
    case vertexFunctionMissing
    case fragmentFunctionMissing
    case blendPipelineCreationFailed(SceneBlendMode)
    case commandQueueCreationFailed
    case samplerCreationFailed
    case neutralMaskCreationFailed
    case invalidFramePlan(SceneMetalPreparationError)
    case assetVerificationFailed(String)
    case textureDecodeFailed(String)
    case textureResolutionFailed(SceneMetalTextureResolutionError)
    case sceneNotPrepared
    case commandBufferCreationFailed
    case renderCommandEncoderCreationFailed
    case gpuExecutionFailed

    public var diagnosticCode: String {
        switch self {
        case .metalDeviceUnavailable: "SCENE_METAL_DEVICE_UNAVAILABLE"
        case .shaderLibraryCompilationFailed: "SCENE_SHADER_LIBRARY_FAILED"
        case .vertexFunctionMissing: "SCENE_VERTEX_FUNCTION_MISSING"
        case .fragmentFunctionMissing: "SCENE_FRAGMENT_FUNCTION_MISSING"
        case let .blendPipelineCreationFailed(mode):
            "SCENE_\(mode.rawValue.uppercased())_PIPELINE_FAILED"
        case .commandQueueCreationFailed: "SCENE_COMMAND_QUEUE_FAILED"
        case .samplerCreationFailed: "SCENE_SAMPLER_FAILED"
        case .neutralMaskCreationFailed: "SCENE_NEUTRAL_MASK_FAILED"
        case .invalidFramePlan: "SCENE_FRAME_PLAN_REJECTED"
        case .assetVerificationFailed: "SCENE_SIGNED_ASSET_REJECTED"
        case .textureDecodeFailed: "SCENE_TEXTURE_DECODE_FAILED"
        case .textureResolutionFailed: "SCENE_TEXTURE_SET_INCOMPLETE"
        case .sceneNotPrepared: "SCENE_NOT_PREPARED"
        case .commandBufferCreationFailed: "SCENE_COMMAND_BUFFER_FAILED"
        case .renderCommandEncoderCreationFailed: "SCENE_RENDER_ENCODER_FAILED"
        case .gpuExecutionFailed: "SCENE_GPU_EXECUTION_FAILED"
        }
    }
}

#if DEBUG
public enum SceneMetalFrameCaptureEncoding: String, Equatable, Sendable {
    case renderComposition
    case exactStaticPlateCopy
    case referenceBytes
}

/// Test-only BGRA readback from the same signed-texture, shader and authored
/// draw-command path used by `MTKView`. It is absent from Release builds.
public struct SceneMetalCapturedFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let bgra8UnormSRGB: Data
    public let encoding: SceneMetalFrameCaptureEncoding

    public init(
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bgra8UnormSRGB: Data,
        encoding: SceneMetalFrameCaptureEncoding
    ) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.bgra8UnormSRGB = bgra8UnormSRGB
        self.encoding = encoding
    }
}

public enum SceneMetalFrameCaptureError: Error, Equatable, Sendable {
    case invalidPixelSize
    case compositorFailure(SceneMetalCompositorFailure)
    case renderTargetCreationFailed
    case commandBufferCreationFailed
    case renderCommandEncoderCreationFailed
    case blitCommandEncoderCreationFailed
    case gpuExecutionFailed
}
#endif

public enum SceneMetalCompositorState: Equatable, Sendable {
    case notConfigured
    case readyForScene
    case preparing(sceneID: SceneID)
    case sceneReady(sceneID: SceneID, deterministicTick: UInt64, reduceMotion: Bool)
    case failed(SceneMetalCompositorFailure)

    public var failure: SceneMetalCompositorFailure? {
        if case let .failed(failure) = self { failure } else { nil }
    }
}

public struct SceneMetalResourceAvailability: Equatable, Sendable {
    public var metalDevice = false
    public var shaderLibrary = false
    public var vertexFunction = false
    public var fragmentFunction = false
    public var normalPipeline = false
    public var multiplyPipeline = false
    public var screenPipeline = false
    public var additivePipeline = false
    public var commandQueue = false
    public var sampler = false
    public var neutralMask = false

    public init() {}

    public static let ready: SceneMetalResourceAvailability = {
        var result = SceneMetalResourceAvailability()
        result.metalDevice = true
        result.shaderLibrary = true
        result.vertexFunction = true
        result.fragmentFunction = true
        result.normalPipeline = true
        result.multiplyPipeline = true
        result.screenPipeline = true
        result.additivePipeline = true
        result.commandQueue = true
        result.sampler = true
        result.neutralMask = true
        return result
    }()
}

public enum SceneMetalConfigurationValidator {
    public static func validate(
        _ availability: SceneMetalResourceAvailability
    ) -> SceneMetalCompositorState {
        guard availability.metalDevice else { return .failed(.metalDeviceUnavailable) }
        guard availability.shaderLibrary else {
            return .failed(.shaderLibraryCompilationFailed)
        }
        guard availability.vertexFunction else { return .failed(.vertexFunctionMissing) }
        guard availability.fragmentFunction else { return .failed(.fragmentFunctionMissing) }
        guard availability.normalPipeline else {
            return .failed(.blendPipelineCreationFailed(.normal))
        }
        guard availability.multiplyPipeline else {
            return .failed(.blendPipelineCreationFailed(.multiply))
        }
        guard availability.screenPipeline else {
            return .failed(.blendPipelineCreationFailed(.screen))
        }
        guard availability.additivePipeline else {
            return .failed(.blendPipelineCreationFailed(.additive))
        }
        guard availability.commandQueue else { return .failed(.commandQueueCreationFailed) }
        guard availability.sampler else { return .failed(.samplerCreationFailed) }
        guard availability.neutralMask else { return .failed(.neutralMaskCreationFailed) }
        return .readyForScene
    }
}

public struct SceneMetalFallbackPresentation: Equatable, Sendable {
    public let title: String
    public let action: String
    public let diagnosticCode: String
    public let backgroundRGBA: SIMD4<Float>
    public let foregroundRGBA: SIMD4<Float>

    public init(failure: SceneMetalCompositorFailure) {
        self.title = "This scene could not be opened."
        self.action = "Return to the road"
        self.diagnosticCode = failure.diagnosticCode
        self.backgroundRGBA = SIMD4(0.035, 0.029, 0.027, 1)
        self.foregroundRGBA = SIMD4(0.86, 0.79, 0.65, 1)
    }
}

@MainActor
public final class SceneMetalCompositor: NSObject, ObservableObject, MTKViewDelegate {
    private struct DrawUniforms {
        var viewportFrame: SIMD4<Float>
        var motionOpacityDepth: SIMD4<Float>
        var focusAndMaskFlags: SIMD4<Float>
        var lightAndReserved: SIMD4<Float>
    }

    private struct PipelineSet {
        let normal: any MTLRenderPipelineState
        let multiply: any MTLRenderPipelineState
        let screen: any MTLRenderPipelineState
        let additive: any MTLRenderPipelineState

        func pipeline(for blendMode: SceneBlendMode) -> any MTLRenderPipelineState {
            switch blendMode {
            case .normal: normal
            case .multiply: multiply
            case .screen: screen
            case .additive: additive
            }
        }
    }

    private struct PreparedDrawCommand {
        let plan: SceneMetalDrawPlan
        let color: any MTLTexture
        let alpha: any MTLTexture
        let occlusion: any MTLTexture
        let depth: any MTLTexture
        let light: any MTLTexture
    }

    private struct PreparedScene {
        let plan: SceneMetalPreparationPlan
        let commands: [PreparedDrawCommand]
        let transientResponse: SceneInteractionResponsePlan?
    }

    private struct MetalDeviceReference: @unchecked Sendable {
        let value: any MTLDevice
    }

    private struct MetalCommandBufferReference: @unchecked Sendable {
        let value: any MTLCommandBuffer
    }

    private struct DecodedTextures: @unchecked Sendable {
        let values: [SceneMetalTextureKey: any MTLTexture]
    }

    private enum TextureLoadFailure: Error, Sendable {
        case assetVerification(String)
        case textureDecode(String)
    }

    @Published public private(set) var state: SceneMetalCompositorState = .notConfigured

    private var device: (any MTLDevice)?
    private var pipelines: PipelineSet?
    private var commandQueue: (any MTLCommandQueue)?
    private var sampler: (any MTLSamplerState)?
    private var neutralMask: (any MTLTexture)?
    private var preparedScene: PreparedScene?
    private var transientResponseStartedAtMilliseconds: UInt64?
    private var textureCache: [SceneMetalTextureKey: any MTLTexture] = [:]
    private var preparationGeneration: UInt64 = 0
    private let performanceRecorder: (any PerformanceRecording)?
    private let monotonicMilliseconds: @Sendable () -> UInt64
    private var completionProxyActionTokensForNextFrame: [PerformanceActionToken] = []
    private var nextFrameMarksRestoredCompletionProxy = false

    public init(
        performanceRecorder: (any PerformanceRecording)? =
            PerformanceCaptureRuntime.shared.recorder,
        monotonicMilliseconds: @escaping @Sendable () -> UInt64 = {
            UInt64(ProcessInfo.processInfo.systemUptime * 1_000)
        }
    ) {
        self.performanceRecorder = performanceRecorder
        self.monotonicMilliseconds = monotonicMilliseconds
        super.init()
    }

    /// Binds an already-started touch or VoiceOver action to the next Metal
    /// command buffer. Its completion is a local proxy; retained Metal System
    /// Trace evidence owns the input-to-display gate.
    public func expectFirstCommandBufferCompletionProxy(for token: PerformanceActionToken) {
        guard !completionProxyActionTokensForNextFrame.contains(token) else { return }
        completionProxyActionTokensForNextFrame.append(token)
    }

    /// Marks the next command-buffer completion as a local restore proxy. The
    /// restore-to-display gate still requires retained Metal System Trace.
    public func markNextCommandBufferCompletionProxyAsRestored() {
        nextFrameMarksRestoredCompletionProxy = true
    }

    /// Configures immutable GPU state. A caller may inject a device for a test
    /// host; production uses the system default. No package asset is read here.
    @discardableResult
    public func configure(
        device requestedDevice: (any MTLDevice)? = MTLCreateSystemDefaultDevice()
    ) -> SceneMetalCompositorState {
        resetGPUResources()
        var availability = SceneMetalResourceAvailability()
        guard let device = requestedDevice else {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }
        availability.metalDevice = true

        let library: any MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }
        availability.shaderLibrary = true
        guard let vertexFunction = library.makeFunction(name: "sceneLayerVertex") else {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }
        availability.vertexFunction = true
        guard let fragmentFunction = library.makeFunction(name: "sceneLayerFragment") else {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }
        availability.fragmentFunction = true

        let normal: any MTLRenderPipelineState
        do {
            normal = try Self.makePipeline(
                device: device,
                vertexFunction: vertexFunction,
                fragmentFunction: fragmentFunction,
                blendMode: .normal
            )
            availability.normalPipeline = true
        } catch {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }
        let multiply: any MTLRenderPipelineState
        do {
            multiply = try Self.makePipeline(
                device: device,
                vertexFunction: vertexFunction,
                fragmentFunction: fragmentFunction,
                blendMode: .multiply
            )
            availability.multiplyPipeline = true
        } catch {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }
        let screen: any MTLRenderPipelineState
        do {
            screen = try Self.makePipeline(
                device: device,
                vertexFunction: vertexFunction,
                fragmentFunction: fragmentFunction,
                blendMode: .screen
            )
            availability.screenPipeline = true
        } catch {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }
        let additive: any MTLRenderPipelineState
        do {
            additive = try Self.makePipeline(
                device: device,
                vertexFunction: vertexFunction,
                fragmentFunction: fragmentFunction,
                blendMode: .additive
            )
            availability.additivePipeline = true
        } catch {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }

        guard let commandQueue = device.makeCommandQueue() else {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }
        availability.commandQueue = true
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.label = "Scene layer sampling"
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }
        availability.sampler = true
        guard let neutralMask = Self.makeNeutralMask(device: device) else {
            return transition(to: SceneMetalConfigurationValidator.validate(availability))
        }
        availability.neutralMask = true

        self.device = device
        self.pipelines = PipelineSet(
            normal: normal,
            multiply: multiply,
            screen: screen,
            additive: additive
        )
        self.commandQueue = commandQueue
        self.sampler = sampler
        self.neutralMask = neutralMask
        return transition(to: SceneMetalConfigurationValidator.validate(availability))
    }

    /// Reads and digest-checks every signed asset before decoding any draw
    /// packet not already present in the digest-keyed cache. The local packet
    /// is committed atomically only when every colour and mask texture
    /// resolves; `draw(in:)` performs no file-system access.
    @discardableResult
    public func prepare(_ framePlan: SceneFramePlan) async -> SceneMetalCompositorState {
        guard let device, neutralMask != nil, pipelines != nil,
              commandQueue != nil, sampler != nil else {
            preparedScene = nil
            return transition(to: .failed(.sceneNotPrepared))
        }
        preparationGeneration &+= 1
        let generation = preparationGeneration
        preparedScene = nil
        transientResponseStartedAtMilliseconds = nil
        transition(to: .preparing(sceneID: framePlan.sceneID))

        let preparation: SceneMetalPreparationPlan
        do {
            preparation = try SceneMetalPreparationPlanner.make(from: framePlan)
        } catch let error as SceneMetalPreparationError {
            return transition(to: .failed(.invalidFramePlan(error)))
        } catch {
            return transition(to: .failed(.sceneNotPrepared))
        }

        // Build the next texture working set locally. The displayed scene may
        // still receive direct-manipulation updates while missing textures are
        // decoded, so its cache must remain intact until the replacement can
        // be committed atomically.
        let requiredTextureKeys = Set(preparation.textureRequests.map(\.key))
        var candidateTextureCache = textureCache.filter {
            requiredTextureKeys.contains($0.key)
        }

        let missingRequests = preparation.textureRequests.filter {
            candidateTextureCache[$0.key] == nil
        }
        if missingRequests.isEmpty {
            let committed = commit(
                preparation,
                using: candidateTextureCache,
                transientResponse: framePlan.interactionResponse
            )
            if case .sceneReady = committed {
                textureCache = candidateTextureCache
            }
            return committed
        }

        let deviceReference = MetalDeviceReference(value: device)
        let decodedResult = await Task.detached(priority: .userInitiated) {
            Self.decodeTextures(
                missingRequests,
                device: deviceReference.value
            )
        }.value
        guard preparationGeneration == generation else {
            return state
        }
        let textures: [SceneMetalTextureKey: any MTLTexture]
        switch decodedResult {
        case let .success(decoded):
            textures = decoded.values
        case let .failure(.assetVerification(path)):
            return transition(to: .failed(.assetVerificationFailed(path)))
        case let .failure(.textureDecode(path)):
            return transition(to: .failed(.textureDecodeFailed(path)))
        }

        // Decoded textures remain local until every missing request succeeds.
        // A failed preparation therefore cannot evict or partially mutate the
        // cache backing the scene that is still on screen.
        candidateTextureCache.merge(textures) { _, replacement in replacement }
        let committed = commit(
            preparation,
            using: candidateTextureCache,
            transientResponse: framePlan.interactionResponse
        )
        if case .sceneReady = committed {
            // A production scene can contain many full-resolution state
            // variants. Retain only the exact replacement working set after
            // its draw packet is ready.
            textureCache = candidateTextureCache
        }
        return committed
    }

    /// Advances camera, deterministic tick, interaction response or a state
    /// variant using textures already prepared for this compositor. This is
    /// the per-frame path and performs neither file I/O nor image decoding.
    @discardableResult
    public func update(_ framePlan: SceneFramePlan) -> SceneMetalCompositorState {
        guard device != nil, neutralMask != nil, pipelines != nil,
              commandQueue != nil, sampler != nil else {
            preparedScene = nil
            return transition(to: .failed(.sceneNotPrepared))
        }
        let preparation: SceneMetalPreparationPlan
        do {
            preparation = try SceneMetalPreparationPlanner.make(from: framePlan)
        } catch let error as SceneMetalPreparationError {
            preparedScene = nil
            return transition(to: .failed(.invalidFramePlan(error)))
        } catch {
            preparedScene = nil
            return transition(to: .failed(.sceneNotPrepared))
        }
        return commit(
            preparation,
            using: textureCache,
            transientResponse: framePlan.interactionResponse
        )
    }

    /// Releases decoded scene assets at a chapter or package boundary. It does
    /// not affect immutable package files or the compositor's GPU pipelines.
    public func purgeTextureCache() {
        preparationGeneration &+= 1
        preparedScene = nil
        transientResponseStartedAtMilliseconds = nil
        completionProxyActionTokensForNextFrame.removeAll(keepingCapacity: false)
        nextFrameMarksRestoredCompletionProxy = false
        textureCache.removeAll(keepingCapacity: false)
        if device != nil, pipelines != nil, commandQueue != nil,
           sampler != nil, neutralMask != nil {
            transition(to: .readyForScene)
        } else {
            transition(to: .notConfigured)
        }
    }

    private func commit(
        _ preparation: SceneMetalPreparationPlan,
        using cache: [SceneMetalTextureKey: any MTLTexture],
        transientResponse: SceneInteractionResponsePlan?
    ) -> SceneMetalCompositorState {
        guard let neutralMask else {
            preparedScene = nil
            return transition(to: .failed(.sceneNotPrepared))
        }
        let requiredKeys = preparation.textureRequests.map(\.key)
        let selectedTextures = Dictionary(
            uniqueKeysWithValues: requiredKeys.compactMap { key in
                cache[key].map { (key, $0) }
            }
        )
        do {
            try SceneMetalTextureResolutionGate.validate(
                required: requiredKeys,
                resolved: Array(selectedTextures.keys)
            )
        } catch let error as SceneMetalTextureResolutionError {
            preparedScene = nil
            return transition(to: .failed(.textureResolutionFailed(error)))
        } catch {
            preparedScene = nil
            return transition(to: .failed(.sceneNotPrepared))
        }

        var commands: [PreparedDrawCommand] = []
        for command in preparation.drawCommands {
            guard let color = selectedTextures[command.colorTexture] else {
                let required = command.masks.all.first(where: {
                    selectedTextures[$0] == nil
                })
                    ?? command.colorTexture
                preparedScene = nil
                return transition(
                    to: .failed(.textureResolutionFailed(.missingTexture(required)))
                )
            }
            let alpha = texture(command.masks.alpha, in: selectedTextures) ?? neutralMask
            let occlusion = texture(command.masks.occlusion, in: selectedTextures) ?? neutralMask
            let depth = texture(command.masks.depth, in: selectedTextures) ?? neutralMask
            let light = texture(command.masks.light, in: selectedTextures) ?? neutralMask
            commands.append(
                PreparedDrawCommand(
                    plan: command,
                    color: color,
                    alpha: alpha,
                    occlusion: occlusion,
                    depth: depth,
                    light: light
                )
            )
        }

        let boundedTransientResponse: SceneInteractionResponsePlan?
        if !preparation.reduceMotion,
           let transientResponse,
           transientResponse.phase == .snapBack {
            boundedTransientResponse = transientResponse
        } else {
            boundedTransientResponse = nil
        }
        transientResponseStartedAtMilliseconds = nil
        preparedScene = PreparedScene(
            plan: preparation,
            commands: commands,
            transientResponse: boundedTransientResponse
        )
        return transition(
            to: .sceneReady(
                sceneID: preparation.sceneID,
                deterministicTick: preparation.deterministicTick,
                reduceMotion: preparation.reduceMotion
            )
        )
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        requestDisplay(for: view)
    }

    public func draw(in view: MTKView) {
        guard case .sceneReady = state, let preparedScene else {
            if state == .readyForScene {
                transition(to: .failed(.sceneNotPrepared))
            }
            return
        }
        guard let pipelines, let commandQueue, let sampler else {
            transition(to: .failed(.sceneNotPrepared))
            return
        }
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            // Being offscreen or backgrounded is a transient frame condition.
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            transition(to: .failed(.commandBufferCreationFailed))
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            transition(to: .failed(.renderCommandEncoderCreationFailed))
            return
        }

        let transientResponse: SceneInteractionResponsePlan?
        if let response = preparedScene.transientResponse {
            let now = monotonicMilliseconds()
            let startedAt = transientResponseStartedAtMilliseconds ?? now
            transientResponseStartedAtMilliseconds = startedAt
            transientResponse = SceneTransientResponseTimeline(
                response: response,
                startedAtMilliseconds: startedAt
            ).sample(at: now)
        } else {
            transientResponse = nil
        }

        Self.encode(
            preparedScene,
            with: encoder,
            pipelines: pipelines,
            sampler: sampler,
            transientResponse: transientResponse
        )
        encoder.endEncoding()
        let completionProxyActions = completionProxyActionTokensForNextFrame
        let marksRestoredFrameCompletionProxy = nextFrameMarksRestoredCompletionProxy
        let performanceRecorder = performanceRecorder
        let performanceFrame = performanceRecorder?.beginFrame(
            sceneID: preparedScene.plan.sceneID.rawValue,
            completionProxyActions: completionProxyActions,
            marksRestoredFrameCompletionProxy: marksRestoredFrameCompletionProxy
        )
        if performanceFrame != nil {
            completionProxyActionTokensForNextFrame.removeAll(keepingCapacity: true)
            nextFrameMarksRestoredCompletionProxy = false
        }
        if let performanceFrame {
            commandBuffer.addScheduledHandler { _ in
                performanceRecorder?.recordFrameCommandBufferScheduled(performanceFrame)
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] completed in
            if let performanceFrame {
                performanceRecorder?.recordFrameCommandBufferCompleted(
                    performanceFrame,
                    gpuStartTimeSeconds: completed.gpuStartTime > 0
                        ? completed.gpuStartTime : nil,
                    gpuEndTimeSeconds: completed.gpuEndTime > 0
                        ? completed.gpuEndTime : nil
                )
            }
            guard completed.status == .error else { return }
            Task { @MainActor in
                self?.preparedScene = nil
                self?.transition(to: .failed(.gpuExecutionFailed))
            }
        }
        commandBuffer.commit()
        if preparedScene.transientResponse != nil,
           transientResponse == nil {
            view.isPaused = true
            view.enableSetNeedsDisplay = true
        }
    }

#if DEBUG
    /// Produces deterministic simulator evidence. Signed assets are verified
    /// by `prepare`; the default permits an exact DEBUG-only static-plate copy.
    /// Passing `false` exercises the same shader encoder as production MTKView.
    public func capture(
        _ framePlan: SceneFramePlan,
        pixelWidth: Int,
        pixelHeight: Int,
        useExactStaticPlateCopy: Bool = true
    ) async throws -> SceneMetalCapturedFrame {
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw SceneMetalFrameCaptureError.invalidPixelSize
        }
        let preparedState = await prepare(framePlan)
        guard case .sceneReady = preparedState, let preparedScene else {
            throw SceneMetalFrameCaptureError.compositorFailure(
                preparedState.failure ?? .sceneNotPrepared
            )
        }
        guard let device, let pipelines, let commandQueue, let sampler else {
            throw SceneMetalFrameCaptureError.compositorFailure(.sceneNotPrepared)
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: pixelWidth,
            height: pixelHeight,
            mipmapped: false
        )
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = [.renderTarget]
        guard let target = device.makeTexture(descriptor: textureDescriptor) else {
            throw SceneMetalFrameCaptureError.renderTargetCreationFailed
        }
        target.label = "Development scene evidence target"

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.018,
            green: 0.020,
            blue: 0.019,
            alpha: 1
        )
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SceneMetalFrameCaptureError.commandBufferCreationFailed
        }
        let captureEncoding: SceneMetalFrameCaptureEncoding
        if useExactStaticPlateCopy, let staticTexture = Self.exactStaticPlateTexture(
            in: preparedScene,
            target: target
        ) {
            guard let blit = commandBuffer.makeBlitCommandEncoder() else {
                throw SceneMetalFrameCaptureError.blitCommandEncoderCreationFailed
            }
            Self.encodeExactStaticPlateCopy(staticTexture, to: target, with: blit)
            blit.endEncoding()
            captureEncoding = .exactStaticPlateCopy
        } else {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                throw SceneMetalFrameCaptureError.renderCommandEncoderCreationFailed
            }
            Self.encode(
                preparedScene,
                with: encoder,
                pipelines: pipelines,
                sampler: sampler,
                transientResponse: nil
            )
            encoder.endEncoding()
            captureEncoding = .renderComposition
        }
        let commandBufferReference = MetalCommandBufferReference(value: commandBuffer)
        let completionStatus = await withCheckedContinuation { continuation in
            commandBufferReference.value.addCompletedHandler { completed in
                continuation.resume(returning: completed.status)
            }
            commandBufferReference.value.commit()
        }
        guard completionStatus == .completed else {
            throw SceneMetalFrameCaptureError.gpuExecutionFailed
        }

        let bytesPerRow = pixelWidth * 4
        var bytes = Data(count: bytesPerRow * pixelHeight)
        bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            target.getBytes(
                baseAddress,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight),
                mipmapLevel: 0
            )
        }
        return SceneMetalCapturedFrame(
            width: pixelWidth,
            height: pixelHeight,
            bytesPerRow: bytesPerRow,
            bgra8UnormSRGB: bytes,
            encoding: captureEncoding
        )
    }
#endif

    fileprivate func attach(to view: MTKView) {
        guard let device else { return }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        // Normal and Reduce Motion presentation retain Apple's display-only
        // allocation path. Exact raw-copy diagnostics live only in DEBUG
        // offscreen capture and never weaken production drawable allocation.
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.clearColor = MTLClearColor(red: 0.018, green: 0.020, blue: 0.019, alpha: 1)
    }

    fileprivate func requestDisplay(for view: MTKView) {
        let transientResponseIsActive: Bool
        if let response = preparedScene?.transientResponse {
            if let startedAt = transientResponseStartedAtMilliseconds {
                transientResponseIsActive = SceneTransientResponseTimeline(
                    response: response,
                    startedAtMilliseconds: startedAt
                ).sample(at: monotonicMilliseconds()) != nil
            } else {
                // The clock begins with the first drawable frame, so scene
                // preparation and SwiftUI reconciliation cannot consume the
                // opening of the material response offscreen.
                transientResponseIsActive = true
            }
        } else {
            transientResponseIsActive = false
        }
        if transientResponseIsActive {
            view.preferredFramesPerSecond = 60
            view.enableSetNeedsDisplay = false
            view.isPaused = false
            return
        }
        view.isPaused = true
        view.enableSetNeedsDisplay = true
#if os(macOS)
        view.setNeedsDisplay(view.bounds)
#else
        view.setNeedsDisplay()
#endif
    }

    private static func uniforms(
        for command: SceneMetalDrawPlan,
        transientResponse: SceneInteractionResponsePlan?,
        reduceMotion: Bool
    ) -> DrawUniforms {
        let interactionOffset = SceneMetalInteractionOffsetResolver.resolve(
            source: command.source,
            viewportFrame: command.viewportFrame,
            response: transientResponse,
            reduceMotion: reduceMotion,
            fallback: command.interactionOffset
        )
        let totalDX = command.motion.parallaxOffset.dx
            + command.motion.windOffset.dx
            + interactionOffset.dx
        let totalDY = command.motion.parallaxOffset.dy
            + command.motion.windOffset.dy
            + interactionOffset.dy
        return DrawUniforms(
            viewportFrame: SIMD4(
                Float(command.viewportFrame.x),
                Float(command.viewportFrame.y),
                Float(command.viewportFrame.width),
                Float(command.viewportFrame.height)
            ),
            motionOpacityDepth: SIMD4(
                Float(totalDX),
                Float(totalDY),
                Float(command.opacity),
                Float(command.depth)
            ),
            focusAndMaskFlags: SIMD4(
                Float(command.motion.focusAmount),
                command.masks.alpha == nil ? 0 : 1,
                command.masks.occlusion == nil ? 0 : 1,
                command.masks.depth == nil ? 0 : 1
            ),
            lightAndReserved: SIMD4(
                command.masks.light == nil ? 0 : 1,
                Float(command.interactionContactAmount),
                Float(command.interactionResistanceAmount),
                0
            )
        )
    }

    private static func encode(
        _ preparedScene: PreparedScene,
        with encoder: any MTLRenderCommandEncoder,
        pipelines: PipelineSet,
        sampler: any MTLSamplerState,
        transientResponse: SceneInteractionResponsePlan?
    ) {
        encoder.label = "Authored 2.5D scene layers"
        encoder.setFragmentSamplerState(sampler, index: 0)
        for command in preparedScene.commands {
            var uniforms = uniforms(
                for: command.plan,
                transientResponse: transientResponse,
                reduceMotion: preparedScene.plan.reduceMotion
            )
            encoder.setRenderPipelineState(pipelines.pipeline(for: command.plan.blendMode))
            encoder.setVertexBytes(
                &uniforms,
                length: MemoryLayout<DrawUniforms>.stride,
                index: 0
            )
            encoder.setFragmentBytes(
                &uniforms,
                length: MemoryLayout<DrawUniforms>.stride,
                index: 0
            )
            encoder.setFragmentTexture(command.color, index: 0)
            encoder.setFragmentTexture(command.alpha, index: 1)
            encoder.setFragmentTexture(command.occlusion, index: 2)
            encoder.setFragmentTexture(command.depth, index: 3)
            encoder.setFragmentTexture(command.light, index: 4)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }

#if DEBUG
    private static func exactStaticPlateTexture(
        in preparedScene: PreparedScene,
        target: any MTLTexture
    ) -> (any MTLTexture)? {
        guard preparedScene.plan.reduceMotion,
              preparedScene.commands.count == 1,
              let command = preparedScene.commands.first,
              case .reduceMotionStaticStratum = command.plan.source,
              command.plan.viewportFrame == SceneFrameRect(
                  x: 0,
                  y: 0,
                  width: 1,
                  height: 1
              ),
              command.plan.opacity == 1,
              command.plan.blendMode == .normal,
              command.plan.motion == .still,
              command.plan.interactionOffset == .zero,
              command.plan.masks.all.isEmpty,
              command.color.textureType == .type2D,
              target.textureType == .type2D,
              command.color.pixelFormat == .bgra8Unorm_srgb,
              target.pixelFormat == .bgra8Unorm_srgb,
              command.color.width == target.width,
              command.color.height == target.height,
              command.color.depth == 1,
              target.depth == 1,
              command.color.arrayLength == 1,
              target.arrayLength == 1,
              command.color.mipmapLevelCount == 1,
              target.mipmapLevelCount == 1,
              command.color.sampleCount == 1,
              target.sampleCount == 1 else {
            return nil
        }
        return command.color
    }

    private static func encodeExactStaticPlateCopy(
        _ source: any MTLTexture,
        to target: any MTLTexture,
        with encoder: any MTLBlitCommandEncoder
    ) {
        encoder.label = "Exact Reduce Motion static plate"
        encoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: target,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
    }
#endif

    private static func makePipeline(
        device: any MTLDevice,
        vertexFunction: any MTLFunction,
        fragmentFunction: any MTLFunction,
        blendMode: SceneBlendMode
    ) throws -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Scene \(blendMode.rawValue) composition"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        guard let attachment = descriptor.colorAttachments[0] else {
            throw SceneMetalCompositorFailure.blendPipelineCreationFailed(blendMode)
        }
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        switch blendMode {
        case .normal:
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        case .multiply:
            attachment.sourceRGBBlendFactor = .destinationColor
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        case .screen:
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceColor
        case .additive:
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
        }
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeNeutralMask(device: any MTLDevice) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Neutral scene mask"
        var white = UInt8.max
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &white,
            bytesPerRow: 1
        )
        return texture
    }

    private nonisolated static func textureOptions(
        for sampling: SceneTextureSampling
    ) -> [MTKTextureLoader.Option: Any] {
        [
            .SRGB: sampling == .colorSRGB,
            .origin: MTKTextureLoader.Origin.topLeft,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            .generateMipmaps: false,
        ]
    }

    private nonisolated static func decodeTextures(
        _ requests: [SceneMetalTextureRequest],
        device: any MTLDevice
    ) -> Result<DecodedTextures, TextureLoadFailure> {
        var textures: [SceneMetalTextureKey: any MTLTexture] = [:]
        for request in requests {
            // MTKTextureLoader crosses ImageIO/CoreGraphics and Metal staging
            // paths which create autoreleased Objective-C objects. Swift
            // concurrency workers do not provide a useful per-asset drain
            // boundary here; without one, the CPU decode backing for every
            // full-resolution layer can survive until the whole batch (and,
            // under a long-lived worker, longer) has completed. Keep the
            // verified MTLTexture, but drain the signed Data bridge, loader and
            // decode intermediates before admitting the next asset.
            let decoded: Result<any MTLTexture, TextureLoadFailure> =
                autoreleasepool {
                    let data: Data
                    do {
                        data = try SceneAssetDataLoader.load(request.asset)
                    } catch {
                        return .failure(
                            .assetVerification(request.key.packagePath)
                        )
                    }
                    do {
                        let loader = MTKTextureLoader(device: device)
                        return .success(
                            try loader.newTexture(
                                data: data,
                                options: textureOptions(
                                    for: request.key.sampling
                                )
                            )
                        )
                    } catch {
                        return .failure(
                            .textureDecode(request.key.packagePath)
                        )
                    }
                }
            switch decoded {
            case let .success(texture):
                textures[request.key] = texture
            case let .failure(failure):
                return .failure(failure)
            }
        }
        return .success(DecodedTextures(values: textures))
    }

    private func texture(
        _ key: SceneMetalTextureKey?,
        in textures: [SceneMetalTextureKey: any MTLTexture]
    ) -> (any MTLTexture)? {
        key.flatMap { textures[$0] }
    }

    private func resetGPUResources() {
        preparationGeneration &+= 1
        preparedScene = nil
        transientResponseStartedAtMilliseconds = nil
        textureCache.removeAll(keepingCapacity: false)
        device = nil
        pipelines = nil
        commandQueue = nil
        sampler = nil
        neutralMask = nil
    }

    @discardableResult
    fileprivate func transition(
        to newState: SceneMetalCompositorState
    ) -> SceneMetalCompositorState {
        state = newState
        return newState
    }

    private static let shaderSource = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct DrawUniforms {
        float4 viewportFrame;
        float4 motionOpacityDepth;
        float4 focusAndMaskFlags;
        float4 lightAndReserved;
    };

    struct RasterData {
        float4 position [[position]];
        float2 uv;
    };

    vertex RasterData sceneLayerVertex(
        uint vertexID [[vertex_id]],
        constant DrawUniforms &uniforms [[buffer(0)]]
    ) {
        const float2 corners[6] = {
            float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
            float2(0.0, 1.0), float2(1.0, 0.0), float2(1.0, 1.0)
        };
        float2 corner = corners[vertexID];
        float2 unitPosition = uniforms.viewportFrame.xy
            + uniforms.motionOpacityDepth.xy
            + corner * uniforms.viewportFrame.zw;
        RasterData out;
        out.position = float4(
            unitPosition.x * 2.0 - 1.0,
            1.0 - unitPosition.y * 2.0,
            0.0,
            1.0
        );
        out.uv = corner;
        return out;
    }

    fragment float4 sceneLayerFragment(
        RasterData in [[stage_in]],
        constant DrawUniforms &uniforms [[buffer(0)]],
        texture2d<float> colorTexture [[texture(0)]],
        texture2d<float> alphaTexture [[texture(1)]],
        texture2d<float> occlusionTexture [[texture(2)]],
        texture2d<float> depthTexture [[texture(3)]],
        texture2d<float> lightTexture [[texture(4)]],
        sampler linearSampler [[sampler(0)]]
    ) {
        float4 source = colorTexture.sample(linearSampler, in.uv);
        float alphaMask = mix(
            1.0,
            alphaTexture.sample(linearSampler, in.uv).r,
            uniforms.focusAndMaskFlags.y
        );
        float occlusionMask = mix(
            1.0,
            occlusionTexture.sample(linearSampler, in.uv).r,
            uniforms.focusAndMaskFlags.z
        );
        float depth = mix(
            uniforms.motionOpacityDepth.w,
            depthTexture.sample(linearSampler, in.uv).r,
            uniforms.focusAndMaskFlags.w
        );
        float light = mix(
            0.0,
            lightTexture.sample(linearSampler, in.uv).r,
            uniforms.lightAndReserved.x
        );

        float alpha = source.a * uniforms.motionOpacityDepth.z
            * alphaMask * occlusionMask;
        float depthResponse = 0.65 + 0.35 * (1.0 - saturate(depth));
        float focusLift = uniforms.focusAndMaskFlags.x * depthResponse * 0.12;
        float contactLift = uniforms.lightAndReserved.y * depthResponse * 0.08;
        float resistance = saturate(uniforms.lightAndReserved.z);
        float3 linearColor = source.rgb
            * (1.0 + focusLift + contactLift + light * 0.35);
        // A compressed, earth-weighted response remains visible without
        // translating the layer. It is the Reduce Motion equivalent of
        // material resistance, not a success flash or interface tint.
        linearColor *= mix(float3(1.0), float3(0.91, 0.87, 0.80), resistance * 0.55);
        return float4(linearColor * alpha, alpha);
    }
    """#
}

#if os(iOS)
import SwiftUI

public struct SceneMetalView: UIViewRepresentable {
    public let compositor: SceneMetalCompositor

    public init(compositor: SceneMetalCompositor) {
        self.compositor = compositor
    }

    public func makeCoordinator() -> SceneMetalCompositor { compositor }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        context.coordinator.attach(to: view)
        view.delegate = context.coordinator
        context.coordinator.requestDisplay(for: view)
        return view
    }

    public func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.requestDisplay(for: view)
    }
}

/// The near-black field is always present. A renderer failure replaces the
/// Metal scene with a legible recovery surface instead of leaving a black or
/// stale frame behind.
public struct SceneMetalSurface: View {
    @ObservedObject private var compositor: SceneMetalCompositor
    private let onReturnToRoad: () -> Void

    public init(
        compositor: SceneMetalCompositor,
        onReturnToRoad: @escaping () -> Void
    ) {
        self.compositor = compositor
        self.onReturnToRoad = onReturnToRoad
    }

    public var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.020, blue: 0.019)
            if case .sceneReady = compositor.state {
                SceneMetalView(compositor: compositor)
            }
            if let failure = compositor.state.failure {
                SceneMetalFailureView(
                    presentation: SceneMetalFallbackPresentation(failure: failure),
                    onReturnToRoad: onReturnToRoad
                )
            }
        }
    }
}

private struct SceneMetalFailureView: View {
    let presentation: SceneMetalFallbackPresentation
    let onReturnToRoad: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(presentation.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color(red: 0.86, green: 0.79, blue: 0.65))
                .accessibilityAddTraits(.isHeader)
            Button(presentation.action, action: onReturnToRoad)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.34, green: 0.23, blue: 0.15))
            Text(presentation.diagnosticCode)
                .font(.caption.monospaced())
                .foregroundStyle(Color(red: 0.58, green: 0.54, blue: 0.48))
                .accessibilityLabel("Diagnostic code \(presentation.diagnosticCode)")
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.035, green: 0.029, blue: 0.027))
    }
}
#endif
