import Combine
import Metal
import MetalKit
import simd

public enum PrologueRendererConfigurationFailure: String, Error, Equatable, Sendable {
    case metalDeviceUnavailable = "METAL_DEVICE_UNAVAILABLE"
    case shaderLibraryCompilationFailed = "SHADER_LIBRARY_COMPILATION_FAILED"
    case vertexFunctionMissing = "VERTEX_FUNCTION_MISSING"
    case fragmentFunctionMissing = "FRAGMENT_FUNCTION_MISSING"
    case renderPipelineCreationFailed = "RENDER_PIPELINE_CREATION_FAILED"
    case commandQueueCreationFailed = "COMMAND_QUEUE_CREATION_FAILED"
    case commandBufferCreationFailed = "COMMAND_BUFFER_CREATION_FAILED"
    case renderCommandEncoderCreationFailed = "RENDER_COMMAND_ENCODER_CREATION_FAILED"
}

public enum PrologueRendererConfigurationState: Equatable, Sendable {
    case notConfigured
    case ready
    case failed(PrologueRendererConfigurationFailure)
}

public struct PrologueRendererResourceAvailability: Equatable, Sendable {
    public var metalDevice: Bool
    public var shaderLibrary: Bool
    public var vertexFunction: Bool
    public var fragmentFunction: Bool
    public var renderPipeline: Bool
    public var commandQueue: Bool

    public init(
        metalDevice: Bool = false,
        shaderLibrary: Bool = false,
        vertexFunction: Bool = false,
        fragmentFunction: Bool = false,
        renderPipeline: Bool = false,
        commandQueue: Bool = false
    ) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary
        self.vertexFunction = vertexFunction
        self.fragmentFunction = fragmentFunction
        self.renderPipeline = renderPipeline
        self.commandQueue = commandQueue
    }

    public static let ready = PrologueRendererResourceAvailability(
        metalDevice: true,
        shaderLibrary: true,
        vertexFunction: true,
        fragmentFunction: true,
        renderPipeline: true,
        commandQueue: true
    )
}

public enum PrologueRendererConfigurationValidator {
    public static func validate(
        _ availability: PrologueRendererResourceAvailability
    ) -> PrologueRendererConfigurationState {
        guard availability.metalDevice else { return .failed(.metalDeviceUnavailable) }
        guard availability.shaderLibrary else {
            return .failed(.shaderLibraryCompilationFailed)
        }
        guard availability.vertexFunction else { return .failed(.vertexFunctionMissing) }
        guard availability.fragmentFunction else { return .failed(.fragmentFunctionMissing) }
        guard availability.renderPipeline else {
            return .failed(.renderPipelineCreationFailed)
        }
        guard availability.commandQueue else { return .failed(.commandQueueCreationFailed) }
        return .ready
    }
}

public enum PrologueRendererDrawPreflightState: Equatable, Sendable {
    case render
    case skipTransientFrame
    case failed(PrologueRendererConfigurationFailure)
}

public struct PrologueRendererDrawResourceAvailability: Equatable, Sendable {
    public var renderPassDescriptor: Bool
    public var drawable: Bool
    public var commandBuffer: Bool
    public var renderCommandEncoder: Bool

    public init(
        renderPassDescriptor: Bool,
        drawable: Bool,
        commandBuffer: Bool,
        renderCommandEncoder: Bool
    ) {
        self.renderPassDescriptor = renderPassDescriptor
        self.drawable = drawable
        self.commandBuffer = commandBuffer
        self.renderCommandEncoder = renderCommandEncoder
    }

    public static let ready = PrologueRendererDrawResourceAvailability(
        renderPassDescriptor: true,
        drawable: true,
        commandBuffer: true,
        renderCommandEncoder: true
    )
}

public enum PrologueRendererDrawPreflightValidator {
    public static func validate(
        _ availability: PrologueRendererDrawResourceAvailability
    ) -> PrologueRendererDrawPreflightState {
        guard availability.renderPassDescriptor, availability.drawable else {
            return .skipTransientFrame
        }
        guard availability.commandBuffer else {
            return .failed(.commandBufferCreationFailed)
        }
        guard availability.renderCommandEncoder else {
            return .failed(.renderCommandEncoderCreationFailed)
        }
        return .render
    }
}

public struct PrologueSceneState: Equatable, Sendable {
    public var routeReveal: Float
    public var focus: Float
    public var reducesMotion: Bool

    public init(routeReveal: Float, focus: Float = 0.5, reducesMotion: Bool = false) {
        self.routeReveal = min(max(routeReveal, 0), 1)
        self.focus = min(max(focus, 0), 1)
        self.reducesMotion = reducesMotion
    }
}

@MainActor
public final class PrologueRenderer: NSObject, ObservableObject, MTKViewDelegate {
    private struct Uniforms {
        var routeReveal: Float
        var focus: Float
        var reducesMotion: Float
        var aspectRatio: Float
    }

    @Published public private(set) var configurationState: PrologueRendererConfigurationState = .notConfigured

    private var device: MTLDevice?
    private var pipeline: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?
    private var sceneState = PrologueSceneState(routeReveal: 0)

    public override init() {
        super.init()
    }

    @discardableResult
    public func configure() -> PrologueRendererConfigurationState {
        self.device = nil
        pipeline = nil
        commandQueue = nil
        var availability = PrologueRendererResourceAvailability()

        guard let device = MTLCreateSystemDefaultDevice() else {
            return transition(to: PrologueRendererConfigurationValidator.validate(availability))
        }
        availability.metalDevice = true

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            return transition(to: PrologueRendererConfigurationValidator.validate(availability))
        }
        availability.shaderLibrary = true

        guard let vertexFunction = library.makeFunction(name: "prologueVertex") else {
            return transition(to: PrologueRendererConfigurationValidator.validate(availability))
        }
        availability.vertexFunction = true
        guard let fragmentFunction = library.makeFunction(name: "prologueFragment") else {
            return transition(to: PrologueRendererConfigurationValidator.validate(availability))
        }
        availability.fragmentFunction = true

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Deterministic prologue foundation"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        let pipeline: MTLRenderPipelineState
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return transition(to: PrologueRendererConfigurationValidator.validate(availability))
        }
        availability.renderPipeline = true

        guard let commandQueue = device.makeCommandQueue() else {
            return transition(to: PrologueRendererConfigurationValidator.validate(availability))
        }
        availability.commandQueue = true

        self.device = device
        self.pipeline = pipeline
        self.commandQueue = commandQueue
        return transition(to: PrologueRendererConfigurationValidator.validate(availability))
    }

    public func update(_ state: PrologueSceneState, view: MTKView) {
        sceneState = state
        requestDisplay(for: view)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        requestDisplay(for: view)
    }

    public func draw(in view: MTKView) {
        guard configurationState == .ready else { return }
        guard let pipeline else {
            transition(to: .failed(.renderPipelineCreationFailed))
            return
        }
        guard let commandQueue else {
            transition(to: .failed(.commandQueueCreationFailed))
            return
        }

        let descriptor = view.currentRenderPassDescriptor
        let drawable = view.currentDrawable
        guard let descriptor, let drawable else {
            // A view may be offscreen, backgrounded or between drawable sizes.
            // Those frames are skipped without turning a healthy renderer into
            // a persistent failure state.
            assert(
                PrologueRendererDrawPreflightValidator.validate(
                    PrologueRendererDrawResourceAvailability(
                        renderPassDescriptor: descriptor != nil,
                        drawable: drawable != nil,
                        commandBuffer: false,
                        renderCommandEncoder: false
                    )
                ) == .skipTransientFrame
            )
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

        let height = max(Float(view.drawableSize.height), 1)
        var uniforms = Uniforms(
            routeReveal: sceneState.routeReveal,
            focus: sceneState.focus,
            reducesMotion: sceneState.reducesMotion ? 1 : 0,
            aspectRatio: Float(view.drawableSize.width) / height
        )

        encoder.label = "Prologue layers"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func requestDisplay(for view: MTKView) {
#if os(macOS)
        view.setNeedsDisplay(view.bounds)
#else
        view.setNeedsDisplay()
#endif
    }

    @discardableResult
    private func transition(
        to state: PrologueRendererConfigurationState
    ) -> PrologueRendererConfigurationState {
        configurationState = state
        return state
    }

    fileprivate func attach(to view: MTKView) {
        guard configurationState == .ready, let device else { return }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.clearColor = MTLClearColor(red: 0.015, green: 0.018, blue: 0.019, alpha: 1)
    }

    private static let shaderSource = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct RasterData {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        float routeReveal;
        float focus;
        float reducesMotion;
        float aspectRatio;
    };

    vertex RasterData prologueVertex(uint vertexID [[vertex_id]]) {
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        RasterData out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = positions[vertexID] * 0.5 + 0.5;
        return out;
    }

    float hash21(float2 point) {
        point = fract(point * float2(123.34, 456.21));
        point += dot(point, point + 45.32);
        return fract(point.x * point.y);
    }

    fragment float4 prologueFragment(RasterData in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;
        float3 charcoal = float3(0.012, 0.015, 0.016);
        float3 slate = float3(0.075, 0.085, 0.079);
        float3 earth = float3(0.145, 0.120, 0.080);
        float3 routeGold = float3(0.80, 0.61, 0.30);

        float horizon = exp(-pow((uv.y - 0.39) * 5.0, 2.0));
        float3 colour = mix(charcoal, slate, horizon * 0.54);

        float farHill = 0.49 + sin(uv.x * 8.0 + 0.7) * 0.025;
        float middleHill = 0.63 + sin(uv.x * 5.2 + 2.2) * 0.055;
        float nearHill = 0.79 + sin(uv.x * 7.7 + 4.0) * 0.045;
        colour = mix(colour, float3(0.032, 0.043, 0.039), smoothstep(farHill - 0.01, farHill, uv.y));
        colour = mix(colour, float3(0.022, 0.030, 0.028), smoothstep(middleHill - 0.01, middleHill, uv.y));
        colour = mix(colour, float3(0.010, 0.014, 0.014), smoothstep(nearHill - 0.01, nearHill, uv.y));

        float routeY = 0.86 - 0.54 * uv.x + sin(uv.x * 12.0) * 0.018;
        float routeDistance = abs(uv.y - routeY);
        float revealMask = 1.0 - smoothstep(u.routeReveal - 0.025, u.routeReveal + 0.02, uv.x);
        float route = (1.0 - smoothstep(0.002, 0.010, routeDistance)) * revealMask;
        float routeGlow = (1.0 - smoothstep(0.005, 0.040, routeDistance)) * revealMask;
        colour += routeGold * routeGlow * 0.18;
        colour = mix(colour, routeGold, route * 0.82);

        float focusLight = exp(-pow((uv.x - u.focus) * 4.5, 2.0)) * horizon;
        colour += earth * focusLight * 0.18;
        float grain = hash21(floor(uv * float2(420.0, 860.0))) - 0.5;
        colour += grain * 0.012;
        float vignette = smoothstep(0.95, 0.26, distance(uv, float2(0.5, 0.52)));
        colour *= 0.72 + 0.28 * vignette;
        return float4(max(colour, 0.0), 1.0);
    }
    """#
}

#if os(iOS)
import SwiftUI

public struct PrologueMetalView: UIViewRepresentable {
    public let renderer: PrologueRenderer
    public var sceneState: PrologueSceneState

    public init(renderer: PrologueRenderer, sceneState: PrologueSceneState) {
        self.renderer = renderer
        self.sceneState = sceneState
    }

    public func makeCoordinator() -> PrologueRenderer {
        renderer
    }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        context.coordinator.attach(to: view)
        view.delegate = context.coordinator
        context.coordinator.update(sceneState, view: view)
        return view
    }

    public func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(sceneState, view: view)
    }
}
#endif
