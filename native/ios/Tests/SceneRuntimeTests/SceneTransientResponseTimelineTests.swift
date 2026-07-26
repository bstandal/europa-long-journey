@testable import SceneRuntime
import XCTest

final class SceneTransientResponseTimelineTests: XCTestCase {
    func testSnapBackSamplesStartMiddleAndClearsAtBoundedEnd() throws {
        let response = SceneInteractionResponsePlan(
            phase: .snapBack,
            targetID: "frame-slot",
            transferLayerID: "post",
            viewportTransferLayerAnchor: SceneFramePoint(x: 0.2, y: 0.7),
            viewportMaterialPosition: SceneFramePoint(x: 0.8, y: 0.3),
            viewportTransferPath: [
                SceneFramePoint(x: 0.8, y: 0.3),
                SceneFramePoint(x: 0.5, y: 0.5),
                SceneFramePoint(x: 0.2, y: 0.7),
            ],
            progress: 1,
            contactAmount: 0.8,
            resistanceAmount: 1
        )
        let timeline = SceneTransientResponseTimeline(
            response: response,
            startedAtMilliseconds: 1_000
        )

        XCTAssertEqual(
            try XCTUnwrap(timeline.sample(at: 1_000)).viewportMaterialPosition,
            response.viewportTransferPath.first
        )
        let middle = try XCTUnwrap(
            try XCTUnwrap(timeline.sample(at: 1_110)).viewportMaterialPosition
        )
        XCTAssertLessThan(middle.x, 0.5)
        XCTAssertGreaterThan(middle.x, 0.2)
        XCTAssertGreaterThan(middle.y, 0.5)
        XCTAssertLessThan(middle.y, 0.7)
        XCTAssertNil(timeline.sample(at: 1_220))
        XCTAssertNil(timeline.sample(at: 9_999))
    }

    func testClockRegressionClampsToStartAndNonSnapBackPassesThrough() throws {
        let response = SceneInteractionResponsePlan(
            phase: .carrying,
            targetID: nil,
            transferLayerID: "post",
            viewportMaterialPosition: SceneFramePoint(x: 0.6, y: 0.4),
            viewportTransferPath: [],
            progress: 0.5,
            contactAmount: 0.15,
            resistanceAmount: 0
        )
        let timeline = SceneTransientResponseTimeline(
            response: response,
            startedAtMilliseconds: 1_000
        )
        XCTAssertEqual(timeline.sample(at: 999), response)
        XCTAssertEqual(timeline.sample(at: UInt64.max), response)
    }

    func testMalformedSnapBackFailsClosed() {
        let response = SceneInteractionResponsePlan(
            phase: .snapBack,
            targetID: nil,
            transferLayerID: "post",
            viewportMaterialPosition: SceneFramePoint(x: 0.5, y: 0.5),
            viewportTransferPath: [],
            progress: 1,
            contactAmount: 0.8,
            resistanceAmount: 1
        )
        XCTAssertNil(
            SceneTransientResponseTimeline(
                response: response,
                startedAtMilliseconds: 0
            ).sample(at: 0)
        )
    }

    func testMetalOffsetUsesClockSampleAndFallsBackAtTimelineEnd() throws {
        let response = SceneInteractionResponsePlan(
            phase: .snapBack,
            targetID: "frame-slot",
            transferLayerID: "post",
            viewportTransferLayerAnchor: SceneFramePoint(x: 0.2, y: 0.7),
            viewportMaterialPosition: SceneFramePoint(x: 0.2, y: 0.7),
            viewportTransferPath: [
                SceneFramePoint(x: 0.8, y: 0.3),
                SceneFramePoint(x: 0.2, y: 0.7),
            ],
            progress: 1,
            contactAmount: 0.8,
            resistanceAmount: 1
        )
        let timeline = SceneTransientResponseTimeline(
            response: response,
            startedAtMilliseconds: 2_000
        )
        let start = try XCTUnwrap(timeline.sample(at: 2_000))
        let middle = try XCTUnwrap(timeline.sample(at: 2_110))

        let startOffset = offset(for: start)
        let middleOffset = offset(for: middle)
        XCTAssertEqual(startOffset.dx, 0.6, accuracy: 0.000_000_001)
        XCTAssertEqual(startOffset.dy, -0.4, accuracy: 0.000_000_001)
        XCTAssertLessThan(abs(middleOffset.dx), abs(startOffset.dx))
        XCTAssertLessThan(abs(middleOffset.dy), abs(startOffset.dy))
        XCTAssertNil(timeline.sample(at: 2_220))
        XCTAssertEqual(offset(for: nil), .zero)
        XCTAssertEqual(offset(for: start, reduceMotion: true), .zero)
    }

    private func offset(
        for response: SceneInteractionResponsePlan?,
        reduceMotion: Bool = false
    ) -> SceneFrameVector {
        SceneMetalInteractionOffsetResolver.resolve(
            source: .layer("post", variantID: "available"),
            viewportFrame: SceneFrameRect(x: 0, y: 0, width: 1, height: 1),
            response: response,
            reduceMotion: reduceMotion,
            fallback: .zero
        )
    }
}
