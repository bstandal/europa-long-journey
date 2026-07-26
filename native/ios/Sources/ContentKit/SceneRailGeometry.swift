import Foundation

/// Exact, deterministic geometry checks for authored interaction geometry on
/// the piecewise-linear camera rail. The renderer linearly interpolates camera
/// centre and scale inside each segment, which makes a projected coordinate a
/// quadratic in local segment time. These checks inspect the quadratic's
/// endpoints and analytic vertex; they never depend on temporal sampling.
enum SceneRailGeometry {
    static let normalizedDeadBand = 1e-10

    struct AttachedRegion {
        let id: String
        let hitRegion: SceneHitRegion
        let parallaxFactor: Double
    }

    private enum Axis {
        case horizontal
        case vertical

        func component(of point: NormalizedPoint) -> Double {
            switch self {
            case .horizontal: point.x
            case .vertical: point.y
            }
        }

        func component(of rect: NormalizedRect) -> Double {
            switch self {
            case .horizontal: rect.width
            case .vertical: rect.height
            }
        }

    }

    private struct Quadratic {
        let q0: Double
        let q1: Double
        let q2: Double

        func value(at time: Double) -> Double {
            (q2 * time + q1) * time + q0
        }

        var extremaTimes: [Double] {
            var result = [0.0, 1.0]
            if q2 != 0 {
                let vertex = -q1 / (2 * q2)
                if vertex.isFinite, vertex > 0, vertex < 1 {
                    result.append(vertex)
                }
            }
            return result
        }
    }

    private struct Linear {
        let q0: Double
        let q1: Double

        func value(at time: Double) -> Double {
            q1 * time + q0
        }

        var internalRoot: Double? {
            guard q1 != 0 else { return nil }
            let root = -q0 / q1
            return root.isFinite && root > 0 && root < 1 ? root : nil
        }
    }

    static func regionStaysVisibleAndTappable(
        _ region: SceneHitRegion,
        parallaxFactor: Double,
        rail: CameraRail,
        crop: SceneViewportCrop,
        railOrigin: NormalizedPoint
    ) -> Bool {
        guard !region.path.isEmpty,
              let minimumX = region.path.map(\.x).min(),
              let maximumX = region.path.map(\.x).max(),
              let minimumY = region.path.map(\.y).min(),
              let maximumY = region.path.map(\.y).max() else {
            return false
        }

        for segmentIndex in 0 ..< rail.keyframes.count - 1 {
            let lower = rail.keyframes[segmentIndex]
            let upper = rail.keyframes[segmentIndex + 1]
            guard region.path.allSatisfy({ point in
                pointStaysVisible(
                    point,
                    parallaxFactor: parallaxFactor,
                    lower: lower,
                    upper: upper,
                    crop: crop,
                    railOrigin: railOrigin
                )
            }) else {
                return false
            }

            let minimumScale = min(lower.scale, upper.scale)
            let widthPoints = (maximumX - minimumX) * minimumScale
                / crop.sourceRect.width * Double(crop.viewport.widthPoints)
            let heightPoints = (maximumY - minimumY) * minimumScale
                / crop.sourceRect.height * Double(crop.viewport.heightPoints)
            guard widthPoints.isFinite, heightPoints.isFinite,
                  widthPoints >= 44 + normalizedDeadBand,
                  heightPoints >= 44 + normalizedDeadBand else {
                return false
            }
        }
        return true
    }

    static func pointStaysVisible(
        _ point: NormalizedPoint,
        parallaxFactor: Double,
        rail: CameraRail,
        crop: SceneViewportCrop,
        railOrigin: NormalizedPoint
    ) -> Bool {
        for segmentIndex in 0 ..< rail.keyframes.count - 1 {
            guard pointStaysVisible(
                point,
                parallaxFactor: parallaxFactor,
                lower: rail.keyframes[segmentIndex],
                upper: rail.keyframes[segmentIndex + 1],
                crop: crop,
                railOrigin: railOrigin
            ) else {
                return false
            }
        }
        return true
    }

    static func pointStaysVisibleInStaticCrop(
        _ point: NormalizedPoint,
        crop: SceneViewportCrop
    ) -> Bool {
        let projectedX = (point.x - crop.sourceRect.x) / crop.sourceRect.width
        let projectedY = (point.y - crop.sourceRect.y) / crop.sourceRect.height
        return projectedX.isFinite && projectedY.isFinite
            && projectedX >= normalizedDeadBand
            && projectedX <= 1 - normalizedDeadBand
            && projectedY >= normalizedDeadBand
            && projectedY <= 1 - normalizedDeadBand
    }

    static func cameraSourceStaysInsideMaster(
        rail: CameraRail,
        crop: SceneViewportCrop
    ) -> Bool {
        for segmentIndex in 0 ..< rail.keyframes.count - 1 {
            let lower = rail.keyframes[segmentIndex]
            let upper = rail.keyframes[segmentIndex + 1]
            for axis in [Axis.horizontal, Axis.vertical] {
                let lowerCenter = axis.component(of: lower.center)
                let upperCenter = axis.component(of: upper.center)
                let centerDelta = upperCenter - lowerCenter
                let scaleDelta = upper.scale - lower.scale
                let baseExtent = axis.component(of: crop.sourceRect)
                let minimumEdge = productPolynomial(
                    lowerScale: lower.scale,
                    scaleDelta: scaleDelta,
                    lowerValue: lowerCenter + normalizedDeadBand,
                    valueDelta: centerDelta,
                    constant: -baseExtent / 2
                )
                let maximumEdge = productPolynomial(
                    lowerScale: lower.scale,
                    scaleDelta: scaleDelta,
                    lowerValue: 1 + normalizedDeadBand - lowerCenter,
                    valueDelta: -centerDelta,
                    constant: -baseExtent / 2
                )
                guard [minimumEdge, maximumEdge].allSatisfy({ polynomial in
                    polynomial.extremaTimes.allSatisfy {
                        let value = polynomial.value(at: $0)
                        return value.isFinite && value >= 0
                    }
                }) else {
                    return false
                }
            }
        }
        return true
    }

    static func regionsMaintainClearance(
        _ regions: [AttachedRegion],
        rail: CameraRail,
        crop: SceneViewportCrop,
        railOrigin: NormalizedPoint
    ) -> Bool {
        for leftIndex in regions.indices {
            for rightIndex in regions.indices where rightIndex > leftIndex {
                guard pairMaintainsClearance(
                    regions[leftIndex],
                    regions[rightIndex],
                    rail: rail,
                    crop: crop,
                    railOrigin: railOrigin
                ) else {
                    return false
                }
            }
        }
        return true
    }

    static func regionsMaintainStaticClearance(
        _ regions: [AttachedRegion],
        crop: SceneViewportCrop
    ) -> Bool {
        let bounds: [(id: String, minimumX: Double, maximumX: Double, minimumY: Double, maximumY: Double)] = regions.compactMap { region in
            guard let minimumX = region.hitRegion.path.map(\.x).min(),
                  let maximumX = region.hitRegion.path.map(\.x).max(),
                  let minimumY = region.hitRegion.path.map(\.y).min(),
                  let maximumY = region.hitRegion.path.map(\.y).max() else {
                return nil
            }
            return (
                id: region.id,
                minimumX: (minimumX - crop.sourceRect.x) / crop.sourceRect.width,
                maximumX: (maximumX - crop.sourceRect.x) / crop.sourceRect.width,
                minimumY: (minimumY - crop.sourceRect.y) / crop.sourceRect.height,
                maximumY: (maximumY - crop.sourceRect.y) / crop.sourceRect.height
            )
        }
        guard bounds.count == regions.count else { return false }
        for leftIndex in bounds.indices {
            for rightIndex in bounds.indices where rightIndex > leftIndex {
                let left = bounds[leftIndex]
                let right = bounds[rightIndex]
                let adjustedOverlap = [
                    left.maximumX - right.minimumX + normalizedDeadBand,
                    right.maximumX - left.minimumX + normalizedDeadBand,
                    left.maximumY - right.minimumY + normalizedDeadBand,
                    right.maximumY - left.minimumY + normalizedDeadBand,
                ]
                guard adjustedOverlap.allSatisfy(\.isFinite),
                      !adjustedOverlap.allSatisfy({ $0 > 0 }) else {
                    return false
                }
            }
        }
        return true
    }

    static func adjacentPathPointsAreDistinct(_ path: [NormalizedPoint]) -> Bool {
        zip(path, path.dropFirst()).allSatisfy { lower, upper in
            let dx = upper.x - lower.x
            let dy = upper.y - lower.y
            return dx.isFinite && dy.isFinite
                && dx * dx + dy * dy > normalizedDeadBand * normalizedDeadBand
        }
    }

    private static func pointStaysVisible(
        _ point: NormalizedPoint,
        parallaxFactor: Double,
        lower: CameraKeyframe,
        upper: CameraKeyframe,
        crop: SceneViewportCrop,
        railOrigin: NormalizedPoint
    ) -> Bool {
        for axis in [Axis.horizontal, Axis.vertical] {
            let polynomial = projectedCoordinate(
                point: axis.component(of: point),
                parallaxFactor: parallaxFactor,
                lowerCenter: axis.component(of: lower.center),
                upperCenter: axis.component(of: upper.center),
                lowerScale: lower.scale,
                upperScale: upper.scale,
                baseExtent: axis.component(of: crop.sourceRect),
                railOrigin: axis.component(of: railOrigin)
            )
            for time in polynomial.extremaTimes {
                let value = polynomial.value(at: time)
                guard value.isFinite,
                      value >= normalizedDeadBand,
                      value <= 1 - normalizedDeadBand else {
                    return false
                }
            }
        }
        return true
    }

    private static func projectedCoordinate(
        point: Double,
        parallaxFactor: Double,
        lowerCenter: Double,
        upperCenter: Double,
        lowerScale: Double,
        upperScale: Double,
        baseExtent: Double,
        railOrigin: Double
    ) -> Quadratic {
        let centerDelta = upperCenter - lowerCenter
        let scaleDelta = upperScale - lowerScale
        let a0 = point - lowerCenter
            + parallaxFactor * (lowerCenter - railOrigin)
        let a1 = (parallaxFactor - 1) * centerDelta
        return Quadratic(
            q0: 0.5 + lowerScale * a0 / baseExtent,
            q1: (lowerScale * a1 + scaleDelta * a0) / baseExtent,
            q2: scaleDelta * a1 / baseExtent
        )
    }

    private static func productPolynomial(
        lowerScale: Double,
        scaleDelta: Double,
        lowerValue: Double,
        valueDelta: Double,
        constant: Double
    ) -> Quadratic {
        Quadratic(
            q0: lowerScale * lowerValue + constant,
            q1: lowerScale * valueDelta + scaleDelta * lowerValue,
            q2: scaleDelta * valueDelta
        )
    }

    private static func pairMaintainsClearance(
        _ left: AttachedRegion,
        _ right: AttachedRegion,
        rail: CameraRail,
        crop: SceneViewportCrop,
        railOrigin: NormalizedPoint
    ) -> Bool {
        guard let leftMinimumX = left.hitRegion.path.map(\.x).min(),
              let leftMaximumX = left.hitRegion.path.map(\.x).max(),
              let leftMinimumY = left.hitRegion.path.map(\.y).min(),
              let leftMaximumY = left.hitRegion.path.map(\.y).max(),
              let rightMinimumX = right.hitRegion.path.map(\.x).min(),
              let rightMaximumX = right.hitRegion.path.map(\.x).max(),
              let rightMinimumY = right.hitRegion.path.map(\.y).min(),
              let rightMaximumY = right.hitRegion.path.map(\.y).max() else {
            return false
        }

        for segmentIndex in 0 ..< rail.keyframes.count - 1 {
            let lower = rail.keyframes[segmentIndex]
            let upper = rail.keyframes[segmentIndex + 1]
            let expressions = [
                adjustedOverlapExpression(
                    leadingEdge: leftMaximumX,
                    leadingParallax: left.parallaxFactor,
                    trailingEdge: rightMinimumX,
                    trailingParallax: right.parallaxFactor,
                    lowerCenter: lower.center.x,
                    upperCenter: upper.center.x,
                    railOrigin: railOrigin.x
                ),
                adjustedOverlapExpression(
                    leadingEdge: rightMaximumX,
                    leadingParallax: right.parallaxFactor,
                    trailingEdge: leftMinimumX,
                    trailingParallax: left.parallaxFactor,
                    lowerCenter: lower.center.x,
                    upperCenter: upper.center.x,
                    railOrigin: railOrigin.x
                ),
                adjustedOverlapExpression(
                    leadingEdge: leftMaximumY,
                    leadingParallax: left.parallaxFactor,
                    trailingEdge: rightMinimumY,
                    trailingParallax: right.parallaxFactor,
                    lowerCenter: lower.center.y,
                    upperCenter: upper.center.y,
                    railOrigin: railOrigin.y
                ),
                adjustedOverlapExpression(
                    leadingEdge: rightMaximumY,
                    leadingParallax: right.parallaxFactor,
                    trailingEdge: leftMinimumY,
                    trailingParallax: left.parallaxFactor,
                    lowerCenter: lower.center.y,
                    upperCenter: upper.center.y,
                    railOrigin: railOrigin.y
                ),
            ]
            var boundaries = [0.0, 1.0]
            boundaries.append(contentsOf: expressions.compactMap(\.internalRoot))
            boundaries.sort()
            boundaries = boundaries.reduce(into: []) { result, value in
                if result.last != value { result.append(value) }
            }

            var testTimes = boundaries
            testTimes.append(contentsOf: zip(boundaries, boundaries.dropFirst()).map {
                ($0.0 + $0.1) / 2
            })
            for time in testTimes {
                // Each expression already includes the normalized dead band.
                // If all four are positive, the two rectangles overlap or come
                // closer than the deterministic clearance contract permits.
                if expressions.allSatisfy({ $0.value(at: time) > 0 }) {
                    return false
                }
            }
        }
        return true
    }

    private static func adjustedOverlapExpression(
        leadingEdge: Double,
        leadingParallax: Double,
        trailingEdge: Double,
        trailingParallax: Double,
        lowerCenter: Double,
        upperCenter: Double,
        railOrigin: Double
    ) -> Linear {
        let parallaxDelta = leadingParallax - trailingParallax
        return Linear(
            q0: leadingEdge - trailingEdge
                + parallaxDelta * (lowerCenter - railOrigin)
                + normalizedDeadBand,
            q1: parallaxDelta * (upperCenter - lowerCenter)
        )
    }
}
