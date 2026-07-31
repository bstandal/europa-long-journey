import Foundation

/// A short-lived, presentation-only response clock. The timeline owns no
/// Journey state and receives monotonic time explicitly, which keeps animation
/// sampling deterministic in tests and prevents a wall-clock change from
/// affecting the causal state.
public struct SceneTransientResponseTimeline: Equatable, Sendable {
    public static let snapBackDurationMilliseconds: UInt64 = 220

    public let response: SceneInteractionResponsePlan
    public let startedAtMilliseconds: UInt64

    public init(
        response: SceneInteractionResponsePlan,
        startedAtMilliseconds: UInt64
    ) {
        self.response = response
        self.startedAtMilliseconds = startedAtMilliseconds
    }

    /// Returns nil after a bounded response has ended. Other phases are not
    /// clock-driven and pass through unchanged.
    public func sample(
        at monotonicMilliseconds: UInt64
    ) -> SceneInteractionResponsePlan? {
        guard response.phase == .snapBack else { return response }
        guard response.viewportTransferPath.count >= 2 else { return nil }

        let elapsed = monotonicMilliseconds >= startedAtMilliseconds
            ? monotonicMilliseconds - startedAtMilliseconds
            : 0
        guard elapsed < Self.snapBackDurationMilliseconds else { return nil }

        let linear = Double(elapsed)
            / Double(Self.snapBackDurationMilliseconds)
        let eased = 1 - pow(1 - linear, 3)
        guard let position = Self.point(
            along: response.viewportTransferPath,
            fraction: eased
        ) else { return nil }
        return response.replacingMaterialPosition(position)
    }

    private static func point(
        along path: [SceneFramePoint],
        fraction: Double
    ) -> SceneFramePoint? {
        guard path.count >= 2,
              fraction.isFinite else { return nil }
        let bounded = min(1, max(0, fraction))
        let segmentLengths = zip(path, path.dropFirst()).map { start, end in
            let dx = end.x - start.x
            let dy = end.y - start.y
            return (dx * dx + dy * dy).squareRoot()
        }
        let total = segmentLengths.reduce(0, +)
        guard total.isFinite, total > 0 else { return path.last }
        var remaining = bounded * total
        for index in segmentLengths.indices {
            let length = segmentLengths[index]
            if remaining <= length || index == segmentLengths.index(before: segmentLengths.endIndex) {
                let local = length > 0 ? min(1, max(0, remaining / length)) : 1
                let start = path[index]
                let end = path[index + 1]
                return SceneFramePoint(
                    x: start.x + (end.x - start.x) * local,
                    y: start.y + (end.y - start.y) * local
                )
            }
            remaining -= length
        }
        return path.last
    }
}

public extension SceneInteractionResponsePlan {
    func replacingMaterialPosition(
        _ position: SceneFramePoint?
    ) -> SceneInteractionResponsePlan {
        SceneInteractionResponsePlan(
            phase: phase,
            targetID: targetID,
            transferLayerID: transferLayerID,
            viewportTransferLayerAnchor: viewportTransferLayerAnchor,
            viewportMaterialPosition: position,
            viewportTransferPath: viewportTransferPath,
            progress: progress,
            contactAmount: contactAmount,
            resistanceAmount: resistanceAmount
        )
    }
}
