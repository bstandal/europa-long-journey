import Foundation

/// Converts the safe-area-constrained SwiftUI route proposal back to the
/// complete portrait scene surface used by authored viewport crops.
public enum SceneViewportCanvasMetrics {
    public static func fullCanvasSize(
        contentSize: SceneFrameSize,
        safeAreaTop: Double,
        safeAreaLeading: Double,
        safeAreaBottom: Double,
        safeAreaTrailing: Double
    ) -> SceneFrameSize {
        SceneFrameSize(
            width: contentSize.width + max(safeAreaLeading, 0) + max(safeAreaTrailing, 0),
            height: contentSize.height + max(safeAreaTop, 0) + max(safeAreaBottom, 0)
        )
    }
}
