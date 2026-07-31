import ContentKit
import Foundation

public enum SceneViewportCropSelectionError: Error, Equatable, Sendable {
    case invalidViewportSize
    case nonPortraitViewport
    case emptyAuthoredCropSet(reduceMotion: Bool)
    case invalidAuthoredCrop(String)
    case duplicateAuthoredCropID(String)
    case normalAndReducedCropSetsMismatch
    case insufficientAuthoredCoverage
    case ambiguousSelection([String])
}

/// Selects one authored causal crop for the actual portrait scene surface.
/// It never synthesises geometry, stretches an authored viewport or silently
/// accepts an uncovered device size.
public enum SceneViewportCropSelector {
    /// A nearby surface may differ by at most three percent on either point
    /// dimension. This covers small iPhone point-size variation without
    /// treating materially different layouts as interchangeable.
    public static let maximumRelativeDimensionDelta = 0.03

    /// Aspect is the stricter gate because an authored crop's composition,
    /// safe text and interaction geometry depend directly on it.
    public static let maximumRelativeAspectDelta = 0.005

    private static let exactPointTolerance = 0.000_001
    private static let scoreEqualityTolerance = 0.000_000_000_001

    public static func selectCropID(
        scene: SceneSpec,
        viewport: SceneFrameSize,
        reduceMotion: Bool
    ) throws -> String {
        guard viewport.width.isFinite, viewport.height.isFinite,
              viewport.width >= 1, viewport.height >= 1 else {
            throw SceneViewportCropSelectionError.invalidViewportSize
        }
        guard viewport.height > viewport.width else {
            throw SceneViewportCropSelectionError.nonPortraitViewport
        }

        let normal = try cropMap(
            scene.sceneCanvas.viewportCrops,
            reduceMotion: false
        )
        let reduced = try cropMap(
            scene.reduceMotionComposition.viewportCrops,
            reduceMotion: true
        )
        guard Set(normal.keys) == Set(reduced.keys),
              normal.allSatisfy({ id, crop in
                  reduced[id]?.viewport == crop.viewport
              }) else {
            throw SceneViewportCropSelectionError.normalAndReducedCropSetsMismatch
        }

        let active = reduceMotion ? reduced : normal
        let candidates = active.values.sorted { $0.id < $1.id }
        let exact = candidates.filter { crop in
            abs(Double(crop.viewport.widthPoints) - viewport.width)
                <= exactPointTolerance
                && abs(Double(crop.viewport.heightPoints) - viewport.height)
                <= exactPointTolerance
        }
        if exact.count == 1 {
            return exact[0].id
        }
        if exact.count > 1 {
            throw SceneViewportCropSelectionError
                .ambiguousSelection(exact.map(\.id).sorted())
        }

        let maximumDimensionLogDelta = log1p(maximumRelativeDimensionDelta)
        let maximumAspectLogDelta = log1p(maximumRelativeAspectDelta)
        let scored = candidates.compactMap { crop -> Candidate? in
            let authoredWidth = Double(crop.viewport.widthPoints)
            let authoredHeight = Double(crop.viewport.heightPoints)
            let widthDelta = abs(log(authoredWidth / viewport.width))
            let heightDelta = abs(log(authoredHeight / viewport.height))
            let authoredAspect = authoredWidth / authoredHeight
            let actualAspect = viewport.width / viewport.height
            let aspectDelta = abs(log(authoredAspect / actualAspect))
            guard widthDelta <= maximumDimensionLogDelta,
                  heightDelta <= maximumDimensionLogDelta,
                  aspectDelta <= maximumAspectLogDelta else {
                return nil
            }
            return Candidate(
                id: crop.id,
                score: sqrt(
                    widthDelta * widthDelta
                        + heightDelta * heightDelta
                        + aspectDelta * aspectDelta
                )
            )
        }.sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > scoreEqualityTolerance {
                return lhs.score < rhs.score
            }
            return lhs.id < rhs.id
        }

        guard let best = scored.first else {
            throw SceneViewportCropSelectionError.insufficientAuthoredCoverage
        }
        let tiedIDs = scored.prefix { candidate in
            abs(candidate.score - best.score) <= scoreEqualityTolerance
        }.map(\.id).sorted()
        guard tiedIDs.count == 1 else {
            throw SceneViewportCropSelectionError.ambiguousSelection(tiedIDs)
        }
        return best.id
    }

    private struct Candidate {
        let id: String
        let score: Double
    }

    private static func cropMap(
        _ crops: [SceneViewportCrop],
        reduceMotion: Bool
    ) throws -> [String: SceneViewportCrop] {
        guard !crops.isEmpty else {
            throw SceneViewportCropSelectionError
                .emptyAuthoredCropSet(reduceMotion: reduceMotion)
        }
        var result: [String: SceneViewportCrop] = [:]
        for crop in crops {
            guard !crop.id.isEmpty,
                  crop.viewport.widthPoints > 0,
                  crop.viewport.heightPoints > crop.viewport.widthPoints else {
                throw SceneViewportCropSelectionError.invalidAuthoredCrop(crop.id)
            }
            guard result.updateValue(crop, forKey: crop.id) == nil else {
                throw SceneViewportCropSelectionError.duplicateAuthoredCropID(crop.id)
            }
        }
        return result
    }
}
