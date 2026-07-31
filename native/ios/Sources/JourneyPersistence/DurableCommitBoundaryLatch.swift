import Foundation

/// Fires an in-memory authority swap only after the exact journal action that
/// owns it has returned durable. Earlier actions may commit without exposing
/// the new authority; a failed boundary action leaves the old authority in
/// place. A later checkpoint failure cannot undo a boundary already present
/// in the synchronised journal, so the latch is intentionally one-shot.
@MainActor
public final class DurableCommitBoundaryLatch {
    public let boundaryActionIndex: Int
    public private(set) var didFire = false

    private let fire: @MainActor () -> Void

    public init(
        boundaryActionIndex: Int,
        fire: @escaping @MainActor () -> Void
    ) {
        precondition(boundaryActionIndex >= 0)
        self.boundaryActionIndex = boundaryActionIndex
        self.fire = fire
    }

    public func actionDidBecomeDurable(at index: Int) {
        guard !didFire, index == boundaryActionIndex else { return }
        didFire = true
        fire()
    }
}
