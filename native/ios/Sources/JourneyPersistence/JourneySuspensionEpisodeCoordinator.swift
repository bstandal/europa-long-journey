import Foundation

public enum JourneySuspensionTrigger: Equatable, Sendable {
    case sceneInactive
    case sceneBackground
    case audioInterruption
    case audioRouteChange
    case cursorDurabilityFailure
}

public enum JourneySuspensionFlushResult: Equatable, Sendable {
    case durable
    case failed
}

/// Finite process-lifetime extension owned by one suspension episode. The
/// production adapter wraps `UIApplication.beginBackgroundTask`; tests use a
/// deterministic handle. Expiration never cancels an admitted append because
/// cancellation cannot prove whether journal bytes crossed the boundary.
@MainActor
public protocol JourneySuspensionExecutionLease: AnyObject {
    func end()
}

@MainActor
public final class JourneySuspensionEpisodeCoordinator {
    public typealias QuiesceOperation = @MainActor (
        JourneySuspensionTrigger
    ) -> Void
    public typealias FlushOperation = @MainActor (
        JourneySuspensionTrigger
    ) async throws -> Void
    public typealias LeaseFactory = @MainActor (
        @escaping @MainActor () -> Void
    ) -> (any JourneySuspensionExecutionLease)?

    public private(set) var episodeID: UInt64?
    public private(set) var firstTrigger: JourneySuspensionTrigger?
    public private(set) var expirationWasReported = false
    public private(set) var lastResult: JourneySuspensionFlushResult?

    private let leaseFactory: LeaseFactory
    private let quiesce: QuiesceOperation
    private let flush: FlushOperation
    private var nextEpisodeID: UInt64 = 0
    private var task: Task<JourneySuspensionFlushResult, Never>?
    private var activeLease: (any JourneySuspensionExecutionLease)?
    private var activeLeaseEpisodeID: UInt64?
    private var sceneIsActive = true
    private var resetAfterFlush = false
    private var teardownWasRequested = false

    public init(
        leaseFactory: @escaping LeaseFactory,
        quiesce: @escaping QuiesceOperation = { _ in },
        flush: @escaping FlushOperation
    ) {
        self.leaseFactory = leaseFactory
        self.quiesce = quiesce
        self.flush = flush
    }

    /// Starts at most one durable flush until the episode is explicitly reset
    /// by a return to the active scene. `inactive -> background`, route-change
    /// and interruption notifications therefore share one pause and journal
    /// cursor even when the system delivers all of them.
    @discardableResult
    public func requestSuspension(
        _ trigger: JourneySuspensionTrigger
    ) -> UInt64? {
        if trigger == .sceneInactive || trigger == .sceneBackground {
            sceneIsActive = false
        }
        guard task == nil, episodeID == nil, !teardownWasRequested,
              nextEpisodeID < UInt64.max else {
            return episodeID
        }
        nextEpisodeID += 1
        let id = nextEpisodeID
        episodeID = id
        firstTrigger = trigger
        expirationWasReported = false
        lastResult = nil
        // This callback cannot suspend. Audio/haptics stop before request
        // returns even if a previously admitted scene or disk transaction
        // keeps the durability flush waiting.
        quiesce(trigger)
        let lease = leaseFactory { [weak self] in
            guard let self, self.episodeID == id else { return }
            self.expirationWasReported = true
        }
        activeLease = lease
        activeLeaseEpisodeID = id

        task = Task { @MainActor [weak self] in
            guard let self else { return .failed }
            let result: JourneySuspensionFlushResult
            do {
                try await self.flush(trigger)
                result = .durable
            } catch {
                result = .failed
            }
            self.completeEpisode(id: id, result: result)
            return result
        }
        return id
    }

    /// Scene activation ends a completed episode. If persistence is still in
    /// flight, reset waits for the exact append/checkpoint completion first.
    public func sceneBecameActive() {
        sceneIsActive = true
        guard task == nil else {
            resetAfterFlush = true
            return
        }
        resetCompletedEpisodeIfPossible()
    }

    /// Explicit user-controlled audio resume can close an interruption-only or
    /// route-change-only episode while the scene itself remained active.
    public func playbackDidResume() {
        guard sceneIsActive else { return }
        sceneBecameActive()
    }

    /// A verified scene rebuild or durable route exit resolves the physical
    /// pause even when the reader elects to continue without sound. Completed
    /// scene-active episodes must then make room for the next suspension.
    public func physicalPauseDidResolve() {
        guard sceneIsActive else { return }
        sceneBecameActive()
    }

    /// A full durable restoration supersedes every process-local suspension
    /// event. The caller must first await any admitted flush so its storage
    /// transaction cannot outlive the authority it started under.
    @discardableResult
    public func acceptDurableRestoration() -> Bool {
        guard task == nil, !teardownWasRequested else { return false }
        endLeaseIfOwned(by: episodeID)
        episodeID = nil
        firstTrigger = nil
        expirationWasReported = false
        lastResult = nil
        resetAfterFlush = false
        return true
    }

    public func awaitCurrentFlush() async -> JourneySuspensionFlushResult? {
        guard let task else { return lastResult }
        return await task.value
    }

    /// Teardown is idempotent and never cancels a possibly admitted append.
    /// The caller may await the returned task before releasing app-owned state.
    public func finishForTeardown() async -> JourneySuspensionFlushResult? {
        teardownWasRequested = true
        resetAfterFlush = false
        let result = await awaitCurrentFlush()
        endLeaseIfOwned(by: episodeID)
        task = nil
        return result
    }

    private func completeEpisode(
        id: UInt64,
        result: JourneySuspensionFlushResult
    ) {
        guard episodeID == id else { return }
        lastResult = result
        task = nil
        endLeaseIfOwned(by: id)
        if resetAfterFlush, sceneIsActive, !teardownWasRequested {
            resetAfterFlush = false
            resetCompletedEpisodeIfPossible()
        }
    }

    private func endLeaseIfOwned(by id: UInt64?) {
        guard let id, activeLeaseEpisodeID == id else { return }
        activeLease?.end()
        activeLease = nil
        activeLeaseEpisodeID = nil
    }

    private func resetCompletedEpisodeIfPossible() {
        guard task == nil, sceneIsActive, !teardownWasRequested else { return }
        episodeID = nil
        firstTrigger = nil
        expirationWasReported = false
    }
}
