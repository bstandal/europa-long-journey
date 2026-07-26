import Metal
import SceneRuntime
import XCTest

final class PrologueRendererTests: XCTestCase {
    func testCompleteResourceSetIsReady() {
        XCTAssertEqual(
            PrologueRendererConfigurationValidator.validate(.ready),
            .ready
        )
    }

    func testEachMissingResourceHasAStableFailureState() {
        let cases: [(PrologueRendererResourceAvailability, PrologueRendererConfigurationFailure)] = [
            (
                PrologueRendererResourceAvailability(),
                .metalDeviceUnavailable
            ),
            (
                PrologueRendererResourceAvailability(metalDevice: true),
                .shaderLibraryCompilationFailed
            ),
            (
                PrologueRendererResourceAvailability(
                    metalDevice: true,
                    shaderLibrary: true
                ),
                .vertexFunctionMissing
            ),
            (
                PrologueRendererResourceAvailability(
                    metalDevice: true,
                    shaderLibrary: true,
                    vertexFunction: true
                ),
                .fragmentFunctionMissing
            ),
            (
                PrologueRendererResourceAvailability(
                    metalDevice: true,
                    shaderLibrary: true,
                    vertexFunction: true,
                    fragmentFunction: true
                ),
                .renderPipelineCreationFailed
            ),
            (
                PrologueRendererResourceAvailability(
                    metalDevice: true,
                    shaderLibrary: true,
                    vertexFunction: true,
                    fragmentFunction: true,
                    renderPipeline: true
                ),
                .commandQueueCreationFailed
            ),
        ]

        for (availability, failure) in cases {
            XCTAssertEqual(
                PrologueRendererConfigurationValidator.validate(availability),
                .failed(failure)
            )
        }
    }

    func testFailureCodesAreDeterministicForDebugDiagnostics() {
        XCTAssertEqual(
            PrologueRendererConfigurationFailure.metalDeviceUnavailable.rawValue,
            "METAL_DEVICE_UNAVAILABLE"
        )
        XCTAssertEqual(
            PrologueRendererConfigurationFailure.shaderLibraryCompilationFailed.rawValue,
            "SHADER_LIBRARY_COMPILATION_FAILED"
        )
        XCTAssertEqual(
            PrologueRendererConfigurationFailure.vertexFunctionMissing.rawValue,
            "VERTEX_FUNCTION_MISSING"
        )
        XCTAssertEqual(
            PrologueRendererConfigurationFailure.fragmentFunctionMissing.rawValue,
            "FRAGMENT_FUNCTION_MISSING"
        )
        XCTAssertEqual(
            PrologueRendererConfigurationFailure.renderPipelineCreationFailed.rawValue,
            "RENDER_PIPELINE_CREATION_FAILED"
        )
        XCTAssertEqual(
            PrologueRendererConfigurationFailure.commandQueueCreationFailed.rawValue,
            "COMMAND_QUEUE_CREATION_FAILED"
        )
        XCTAssertEqual(
            PrologueRendererConfigurationFailure.commandBufferCreationFailed.rawValue,
            "COMMAND_BUFFER_CREATION_FAILED"
        )
        XCTAssertEqual(
            PrologueRendererConfigurationFailure.renderCommandEncoderCreationFailed.rawValue,
            "RENDER_COMMAND_ENCODER_CREATION_FAILED"
        )
    }

    func testOffscreenOrBackgroundFramesAreTransientRatherThanRendererFailures() {
        XCTAssertEqual(
            PrologueRendererDrawPreflightValidator.validate(
                PrologueRendererDrawResourceAvailability(
                    renderPassDescriptor: false,
                    drawable: true,
                    commandBuffer: false,
                    renderCommandEncoder: false
                )
            ),
            .skipTransientFrame
        )
        XCTAssertEqual(
            PrologueRendererDrawPreflightValidator.validate(
                PrologueRendererDrawResourceAvailability(
                    renderPassDescriptor: true,
                    drawable: false,
                    commandBuffer: false,
                    renderCommandEncoder: false
                )
            ),
            .skipTransientFrame
        )
    }

    func testDrawResourceFailuresHaveVisibleStableFailureStates() {
        XCTAssertEqual(
            PrologueRendererDrawPreflightValidator.validate(
                PrologueRendererDrawResourceAvailability(
                    renderPassDescriptor: true,
                    drawable: true,
                    commandBuffer: false,
                    renderCommandEncoder: false
                )
            ),
            .failed(.commandBufferCreationFailed)
        )
        XCTAssertEqual(
            PrologueRendererDrawPreflightValidator.validate(
                PrologueRendererDrawResourceAvailability(
                    renderPassDescriptor: true,
                    drawable: true,
                    commandBuffer: true,
                    renderCommandEncoder: false
                )
            ),
            .failed(.renderCommandEncoderCreationFailed)
        )
        XCTAssertEqual(
            PrologueRendererDrawPreflightValidator.validate(.ready),
            .render
        )
    }

    @MainActor
    func testRendererStartsInAnExplicitUnconfiguredState() {
        XCTAssertEqual(PrologueRenderer().configurationState, .notConfigured)
    }

    @MainActor
    func testRealMetalConfigurationWhenTheTestHostProvidesADevice() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("The current test host exposes no Metal device.")
        }
        XCTAssertEqual(PrologueRenderer().configure(), .ready)
    }
}
