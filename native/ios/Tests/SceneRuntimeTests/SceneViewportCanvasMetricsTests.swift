@testable import SceneRuntime
import XCTest

final class SceneViewportCanvasMetricsTests: XCTestCase {
    func testSafeAreaConstrainedRouteRecoversFull393By852Canvas() {
        let canvas = SceneViewportCanvasMetrics.fullCanvasSize(
            contentSize: SceneFrameSize(width: 393, height: 759),
            safeAreaTop: 59,
            safeAreaLeading: 0,
            safeAreaBottom: 34,
            safeAreaTrailing: 0
        )

        XCTAssertEqual(canvas, SceneFrameSize(width: 393, height: 852))
    }
}
