import ContentKit
import Foundation
import ProgressStore

public struct ActiveAudioCursorFeedCapture: Equatable, Sendable {
    public let result: ResponsiveAudioDurabilityCaptureResult
    public let renderedGraphSample: Int64

    public init(
        result: ResponsiveAudioDurabilityCaptureResult,
        renderedGraphSample: Int64
    ) {
        self.result = result
        self.renderedGraphSample = renderedGraphSample
    }
}

public struct ActiveAudioCursorFeed: Sendable {
    public typealias Capture = @Sendable () throws
        -> ActiveAudioCursorFeedCapture

    private let captureOperation: Capture

    public init(capture: @escaping Capture) {
        captureOperation = capture
    }

    public func capture() throws -> ActiveAudioCursorFeedCapture {
        try captureOperation()
    }
}

/// Implementations must accept only monotone extensions. Once rendered audio
/// reaches the current cutoff, they permanently latch closed and return false;
/// a late durable write can therefore never reopen audio.
public protocol ActiveAudioCursorGateAuthorizing: Sendable {
    /// Atomically verifies that this capture belongs to audio that could still
    /// be heard under the current cutoff. A false result is permanently
    /// closed and must not be followed by a store write.
    @discardableResult
    func claimCapture(atRenderedGraphSample sample: Int64) -> Bool

    @discardableResult
    func authorizeAudio(throughRenderedGraphSample cutoff: Int64) -> Bool
}

public enum ActiveAudioCursorBindingError: Error, Equatable, Sendable {
    case invalidRenderedGraphSampleRate
}

public struct ActiveAudioCursorBinding: Sendable {
    public static let maximumUndurableDurationNanoseconds: UInt64 = 250_000_000

    public let feed: ActiveAudioCursorFeed
    public let renderedGraphSampleRate: Double
    public let maximumUndurableGraphSampleCount: Int64
    fileprivate let gate: any ActiveAudioCursorGateAuthorizing

    public init(
        renderedGraphSampleRate: Double,
        feed: ActiveAudioCursorFeed,
        gate: any ActiveAudioCursorGateAuthorizing
    ) throws {
        let rawBudget = renderedGraphSampleRate / 4
        guard renderedGraphSampleRate.isFinite,
              renderedGraphSampleRate > 0,
              rawBudget >= 1,
              rawBudget <= Double(Int64.max) else {
            throw ActiveAudioCursorBindingError
                .invalidRenderedGraphSampleRate
        }
        self.feed = feed
        self.renderedGraphSampleRate = renderedGraphSampleRate
        maximumUndurableGraphSampleCount = Int64(rawBudget.rounded(.down))
        self.gate = gate
    }
}

public enum ActiveAudioCursorWorkerFailure: Equatable, Sendable {
    case captureUnavailable
    case persistenceUnavailable
    case invalidRenderedGraphSample
    case scheduleOverflow
    case gateClosed
    case handoffRequiresVerifiedAuthority
    case activationInProgress
    case activationTokenReused
    case generationExhausted
}

public enum ActiveAudioCursorTerminalResult: Equatable, Sendable {
    case failed(ActiveAudioCursorWorkerFailure)
    case stopped
    case superseded
}

fileprivate final class ActiveAudioCursorTerminalSignal: @unchecked Sendable {
    typealias PersistedObserver = @Sendable (
        ResponsiveAudioProgramSnapshot
    ) -> Void

    private let lock = NSLock()
    private var result: ActiveAudioCursorTerminalResult?
    private var persistedSnapshot: ResponsiveAudioProgramSnapshot?
    private var persistedObserver: PersistedObserver?
    private var waiters: [
        CheckedContinuation<ActiveAudioCursorTerminalResult, Never>
    ] = []

    func wait() async -> ActiveAudioCursorTerminalResult {
        await withCheckedContinuation { continuation in
            enqueue(continuation)
        }
    }

    func resolve(_ result: ActiveAudioCursorTerminalResult) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let waiters = waiters
        self.waiters.removeAll(keepingCapacity: false)
        lock.unlock()
        for waiter in waiters { waiter.resume(returning: result) }
    }

    func recordPersisted(_ snapshot: ResponsiveAudioProgramSnapshot) {
        lock.lock()
        persistedSnapshot = snapshot
        let observer = persistedObserver
        lock.unlock()
        observer?(snapshot)
    }

    func latestPersistedSnapshot() -> ResponsiveAudioProgramSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return persistedSnapshot
    }

    func setPersistedObserver(_ observer: PersistedObserver?) {
        lock.lock()
        persistedObserver = observer
        let latest = persistedSnapshot
        lock.unlock()
        if let observer, let latest { observer(latest) }
    }

    private func enqueue(
        _ continuation:
            CheckedContinuation<ActiveAudioCursorTerminalResult, Never>
    ) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(returning: result)
        } else {
            waiters.append(continuation)
            lock.unlock()
        }
    }
}

/// Caller-published ownership identity for one activation attempt. Journey
/// creates and records this token before entering an actor `await`, so a
/// lifecycle or automatic boundary that re-enters meanwhile can scope its
/// operation to the exact activation it observed. Tokens are single-use.
public struct ActiveAudioCursorActivationToken: Hashable, Sendable {
    fileprivate let id: UUID

    public init() {
        id = UUID()
    }
}

public struct ActiveAudioCursorProtection: Sendable {
    public let activationToken: ActiveAudioCursorActivationToken
    public let session: ResponsiveAudioCursorCheckpointSession
    fileprivate let signal: ActiveAudioCursorTerminalSignal

    fileprivate init(
        activationToken: ActiveAudioCursorActivationToken,
        session: ResponsiveAudioCursorCheckpointSession,
        signal: ActiveAudioCursorTerminalSignal
    ) {
        self.activationToken = activationToken
        self.session = session
        self.signal = signal
    }

    public func terminalResult() async -> ActiveAudioCursorTerminalResult {
        await signal.wait()
    }

    /// The newest checkpoint whose store write completed while this exact
    /// protection generation still owned the worker. This mirror never claims
    /// that an obsolete generation is current; Journey still fences it by the
    /// protection identity before presenting diagnostics or rotating authority.
    public func latestPersistedSnapshot() -> ResponsiveAudioProgramSnapshot? {
        signal.latestPersistedSnapshot()
    }

    /// Installs one event-driven mirror for diagnostics. The observer is
    /// invoked outside the signal lock and immediately receives the newest
    /// already-durable value, if any. Production playback never depends on it.
    public func setPersistedSnapshotObserver(
        _ observer: (@Sendable (ResponsiveAudioProgramSnapshot) -> Void)?
    ) {
        signal.setPersistedObserver(observer)
    }
}

public actor ActiveAudioCursorWorker {
    public static let productionIntervalNanoseconds: UInt64 = 125_000_000

    public enum ActivationResult: Sendable {
        case protecting(ActiveAudioCursorProtection)
        case superseded
        case failed(ActiveAudioCursorWorkerFailure)
    }

    public enum Status: Equatable, Sendable {
        case stopped
        case starting(generation: UInt64)
        case running(generation: UInt64)
        case failed(
            generation: UInt64,
            reason: ActiveAudioCursorWorkerFailure
        )
    }

    public private(set) var status: Status = .stopped

    typealias MonotonicNow = @Sendable () -> UInt64
    typealias Sleep = @Sendable (UInt64) async throws -> Void

    private struct Context: Sendable {
        let generation: UInt64
        let activationToken: ActiveAudioCursorActivationToken
        let binding: ActiveAudioCursorBinding
        let session: ResponsiveAudioCursorCheckpointSession
        var nextDeadlineNanoseconds: UInt64
        var lastAuthorizedCutoff: Int64?
    }

    private enum CheckpointResult {
        case verified(cutoff: Int64)
        case awaitingAuthority
        case superseded
        case failed(ActiveAudioCursorWorkerFailure)
    }

    private let store: ResponsiveAudioCursorCheckpointStore
    private let intervalNanoseconds: UInt64
    private let now: MonotonicNow
    private let sleep: Sleep
    private var generation: UInt64 = 0
    private var currentActivationToken: ActiveAudioCursorActivationToken?
    private var usedActivationTokens: Set<ActiveAudioCursorActivationToken> = []
    private var activationIsAwaitingHandoff = false
    private var cadenceTask: Task<Void, Never>?
    private var context: Context?
    private var terminalSignal: ActiveAudioCursorTerminalSignal?
#if DEBUG
    private var mostRecentHandoffSuccessorForTesting:
        ResponsiveAudioCursorCheckpointSession?
#endif

    public init(store: ResponsiveAudioCursorCheckpointStore) {
        self.store = store
        intervalNanoseconds = Self.productionIntervalNanoseconds
        now = { DispatchTime.now().uptimeNanoseconds }
        sleep = { try await Task.sleep(nanoseconds: $0) }
    }

    init(
        store: ResponsiveAudioCursorCheckpointStore,
        intervalNanoseconds: UInt64,
        now: @escaping MonotonicNow,
        sleep: @escaping Sleep
    ) {
        precondition(intervalNanoseconds > 0)
        self.store = store
        self.intervalNanoseconds = intervalNanoseconds
        self.now = now
        self.sleep = sleep
    }

    @discardableResult
    public func start(
        token: ActiveAudioCursorActivationToken,
        binding: ActiveAudioCursorBinding,
        session: ResponsiveAudioCursorCheckpointSession
    ) async -> ActivationResult {
        guard currentActivationToken == nil else { return .superseded }
        guard let activation = beginActivation(token: token) else {
            return activationFailure(for: token)
        }
        let startedAt = now()
        guard let firstDeadline = addingInterval(to: startedAt) else {
            failCurrent(.scheduleOverflow, generation: activation.generation)
            return .failed(.scheduleOverflow)
        }
        // Publish the starting session before the first fsync. Actors are
        // reentrant at that await: an automatic boundary may already have
        // reached Journey durability and must be able to hand off from this
        // exact session rather than failing merely because activation is still
        // waiting on disk. The obsolete start generation can never authorize
        // audio after beginActivation supersedes it.
        context = Context(
            generation: activation.generation,
            activationToken: token,
            binding: binding,
            session: session,
            nextDeadlineNanoseconds: firstDeadline,
            lastAuthorizedCutoff: nil
        )
        let checkpoint = await checkpoint(
            binding: binding,
            session: session,
            generation: activation.generation,
            capturedAt: startedAt,
            previousCutoff: nil
        )
        return finishActivation(
            checkpoint,
            binding: binding,
            session: session,
            generation: activation.generation,
            activationToken: token,
            signal: activation.signal,
            nextDeadline: firstDeadline
        )
    }

    @discardableResult
    public func handoff(
        from expectedToken: ActiveAudioCursorActivationToken,
        activating nextToken: ActiveAudioCursorActivationToken,
        to authority: ResponsiveAudioCursorAuthority,
        binding: ActiveAudioCursorBinding
    ) async -> ActivationResult {
        guard currentActivationToken == expectedToken else {
            return .superseded
        }
        guard !activationIsAwaitingHandoff,
              let prior = context,
              prior.activationToken == expectedToken else {
            return .failed(.activationInProgress)
        }
        guard let activation = beginActivation(token: nextToken) else {
            return activationFailure(for: nextToken)
        }
        activationIsAwaitingHandoff = true
        defer {
            if currentActivationToken == nextToken {
                activationIsAwaitingHandoff = false
            }
        }
        let capturedAt = now()
        let capture: ActiveAudioCursorFeedCapture
        do {
            capture = try binding.feed.capture()
        } catch {
            failCurrent(.captureUnavailable, generation: activation.generation)
            return .failed(.captureUnavailable)
        }
        guard case let .verified(snapshot) = capture.result else {
            failCurrent(
                .handoffRequiresVerifiedAuthority,
                generation: activation.generation
            )
            return .failed(.handoffRequiresVerifiedAuthority)
        }
        guard let proposedCutoff = claim(
            capture,
            binding: binding,
            previousCutoff: prior.lastAuthorizedCutoff,
            generation: activation.generation
        ) else {
            return .failed(currentFailure(for: activation.generation))
        }
        let successor: ResponsiveAudioCursorCheckpointSession
        do {
            successor = try await store.handoffSession(
                from: prior.session,
                to: authority,
                initialSnapshot: snapshot,
                capturedAtMonotonicNanoseconds: capturedAt
            )
        } catch {
            guard owns(activation.generation) else { return .superseded }
            failCurrent(
                .persistenceUnavailable,
                generation: activation.generation
            )
            return .failed(.persistenceUnavailable)
        }
#if DEBUG
        mostRecentHandoffSuccessorForTesting = successor
#endif
        guard owns(activation.generation) else {
            await store.retire(successor)
            return .superseded
        }
        activation.signal.recordPersisted(snapshot)
        let authorization = authorizeAfterPersistence(
            proposedCutoff,
            binding: binding,
            generation: activation.generation
        )
        if case let .failed(reason) = authorization {
            return await retireFailedHandoffSuccessor(
                successor,
                reason: reason,
                generation: activation.generation
            )
        }
        let nextDeadline = captureDeadline(
            after: capturedAt,
            currentDeadline: prior.nextDeadlineNanoseconds
        )
        guard let nextDeadline else {
            failCurrent(.scheduleOverflow, generation: activation.generation)
            return await retireFailedHandoffSuccessor(
                successor,
                reason: .scheduleOverflow,
                generation: activation.generation
            )
        }
        return finishActivation(
            authorization,
            binding: binding,
            session: successor,
            generation: activation.generation,
            activationToken: nextToken,
            signal: activation.signal,
            nextDeadline: nextDeadline
        )
    }

    /// Stops only the generation represented by this protection. A delayed
    /// lifecycle cleanup can therefore never tear down a successor which won a
    /// start or handoff while the caller was suspended.
    @discardableResult
    public func stop(_ protection: ActiveAudioCursorProtection) -> Bool {
        guard currentActivationToken == protection.activationToken,
              terminalSignal === protection.signal else { return false }
        stopCurrentGeneration()
        return true
    }

    /// Stops a starting activation whose protection has not returned yet.
    /// Token reuse is forbidden, so this scope cannot match a successor.
    @discardableResult
    public func stop(expectedToken: ActiveAudioCursorActivationToken) -> Bool {
        guard currentActivationToken == expectedToken else { return false }
        stopCurrentGeneration()
        return true
    }

    /// Unscoped shutdown is reserved for owners that are destroying the whole
    /// worker and cannot admit a successor concurrently.
    func stop() {
        stopCurrentGeneration()
    }

    private func stopCurrentGeneration() {
        cadenceTask?.cancel()
        cadenceTask = nil
        terminalSignal?.resolve(.stopped)
        terminalSignal = nil
        context = nil
        currentActivationToken = nil
        activationIsAwaitingHandoff = false
        if generation < UInt64.max { generation += 1 }
        status = .stopped
    }

#if DEBUG
    func mostRecentHandoffSuccessorSessionForTesting()
        -> ResponsiveAudioCursorCheckpointSession? {
        mostRecentHandoffSuccessorForTesting
    }
#endif

    private func beginActivation(
        token: ActiveAudioCursorActivationToken
    ) -> (
        generation: UInt64,
        signal: ActiveAudioCursorTerminalSignal
    )? {
        guard !usedActivationTokens.contains(token),
              generation < UInt64.max else { return nil }
        cadenceTask?.cancel()
        cadenceTask = nil
        terminalSignal?.resolve(.superseded)
        terminalSignal = nil
        context = nil
        usedActivationTokens.insert(token)
        generation += 1
        let signal = ActiveAudioCursorTerminalSignal()
        terminalSignal = signal
        currentActivationToken = token
        status = .starting(generation: generation)
        return (generation, signal)
    }

    private func activationFailure(
        for token: ActiveAudioCursorActivationToken
    ) -> ActivationResult {
        if usedActivationTokens.contains(token) {
            return .failed(.activationTokenReused)
        }
        // A handoff that cannot allocate another generation has not taken
        // ownership from the old token. Keep its running status coherent so
        // the caller can close it with that exact token. A failed initial
        // start has no prior owner and may expose the terminal state.
        if currentActivationToken == nil {
            status = .failed(
                generation: generation,
                reason: .generationExhausted
            )
        }
        return .failed(.generationExhausted)
    }

    private func finishActivation(
        _ checkpoint: CheckpointResult,
        binding: ActiveAudioCursorBinding,
        session: ResponsiveAudioCursorCheckpointSession,
        generation activeGeneration: UInt64,
        activationToken: ActiveAudioCursorActivationToken,
        signal: ActiveAudioCursorTerminalSignal,
        nextDeadline: UInt64
    ) -> ActivationResult {
        guard owns(activeGeneration) else { return .superseded }
        let cutoff: Int64?
        switch checkpoint {
        case let .verified(value): cutoff = value
        case .awaitingAuthority: cutoff = nil
        case .superseded: return .superseded
        case let .failed(reason): return .failed(reason)
        }
        context = Context(
            generation: activeGeneration,
            activationToken: activationToken,
            binding: binding,
            session: session,
            nextDeadlineNanoseconds: nextDeadline,
            lastAuthorizedCutoff: cutoff
        )
        status = .running(generation: activeGeneration)
        cadenceTask = Task { [weak self] in
            await self?.runCadence(generation: activeGeneration)
        }
        return .protecting(ActiveAudioCursorProtection(
            activationToken: activationToken,
            session: session,
            signal: signal
        ))
    }

    private func runCadence(generation activeGeneration: UInt64) async {
        while owns(activeGeneration), !Task.isCancelled {
            guard let active = context,
                  active.generation == activeGeneration else { return }
            let observedAt = now()
            if observedAt < active.nextDeadlineNanoseconds {
                do {
                    try await sleep(
                        active.nextDeadlineNanoseconds - observedAt
                    )
                } catch {
                    return
                }
                continue
            }
            guard let nextDeadline = captureDeadline(
                after: observedAt,
                currentDeadline: active.nextDeadlineNanoseconds
            ) else {
                failCurrent(.scheduleOverflow, generation: activeGeneration)
                return
            }
            context?.nextDeadlineNanoseconds = nextDeadline
            let result = await checkpoint(
                binding: active.binding,
                session: active.session,
                generation: activeGeneration,
                capturedAt: observedAt,
                previousCutoff: active.lastAuthorizedCutoff
            )
            guard owns(activeGeneration) else { return }
            switch result {
            case let .verified(cutoff):
                context?.lastAuthorizedCutoff = cutoff
            case .awaitingAuthority:
                break
            case .superseded, .failed:
                return
            }
        }
    }

    private func checkpoint(
        binding: ActiveAudioCursorBinding,
        session: ResponsiveAudioCursorCheckpointSession,
        generation activeGeneration: UInt64,
        capturedAt: UInt64,
        previousCutoff: Int64?
    ) async -> CheckpointResult {
        guard owns(activeGeneration) else { return .superseded }
        let capture: ActiveAudioCursorFeedCapture
        do {
            capture = try binding.feed.capture()
        } catch {
            failCurrent(.captureUnavailable, generation: activeGeneration)
            return .failed(.captureUnavailable)
        }
        guard let proposedCutoff = claim(
            capture,
            binding: binding,
            previousCutoff: previousCutoff,
            generation: activeGeneration
        ) else {
            return .failed(currentFailure(for: activeGeneration))
        }
        do {
            try await store.checkpoint(
                capture.result.snapshot,
                session: session,
                capturedAtMonotonicNanoseconds: capturedAt
            )
        } catch {
            guard owns(activeGeneration) else { return .superseded }
            failCurrent(
                .persistenceUnavailable,
                generation: activeGeneration
            )
            return .failed(.persistenceUnavailable)
        }
        guard owns(activeGeneration) else { return .superseded }
        terminalSignal?.recordPersisted(capture.result.snapshot)
        guard capture.result.verifiesCurrentAuthority else {
            return .awaitingAuthority
        }
        return authorizeAfterPersistence(
            proposedCutoff,
            binding: binding,
            generation: activeGeneration
        )
    }

    private func claim(
        _ capture: ActiveAudioCursorFeedCapture,
        binding: ActiveAudioCursorBinding,
        previousCutoff: Int64?,
        generation activeGeneration: UInt64
    ) -> Int64? {
        guard capture.renderedGraphSample >= 0 else {
            failCurrent(
                .invalidRenderedGraphSample,
                generation: activeGeneration
            )
            return nil
        }
        let addition = capture.renderedGraphSample.addingReportingOverflow(
            binding.maximumUndurableGraphSampleCount
        )
        guard !addition.overflow,
              previousCutoff.map({ addition.partialValue >= $0 }) ?? true else {
            failCurrent(
                .invalidRenderedGraphSample,
                generation: activeGeneration
            )
            return nil
        }
        guard binding.gate.claimCapture(
            atRenderedGraphSample: capture.renderedGraphSample
        ) else {
            failCurrent(.gateClosed, generation: activeGeneration)
            return nil
        }
        return addition.partialValue
    }

    private func authorizeAfterPersistence(
        _ cutoff: Int64,
        binding: ActiveAudioCursorBinding,
        generation activeGeneration: UInt64
    ) -> CheckpointResult {
        guard binding.gate.authorizeAudio(
            throughRenderedGraphSample: cutoff
        ) else {
            failCurrent(.gateClosed, generation: activeGeneration)
            return .failed(.gateClosed)
        }
        return .verified(cutoff: cutoff)
    }

    private func currentFailure(
        for activeGeneration: UInt64
    ) -> ActiveAudioCursorWorkerFailure {
        if case let .failed(generation, reason) = status,
           generation == activeGeneration {
            return reason
        }
        return .gateClosed
    }

    private func retireFailedHandoffSuccessor(
        _ successor: ResponsiveAudioCursorCheckpointSession,
        reason: ActiveAudioCursorWorkerFailure,
        generation activeGeneration: UInt64
    ) async -> ActivationResult {
        guard owns(activeGeneration) else { return .superseded }
        await store.retire(successor)
        guard generation == activeGeneration else { return .superseded }
        return .failed(reason)
    }

    private func failCurrent(
        _ reason: ActiveAudioCursorWorkerFailure,
        generation activeGeneration: UInt64
    ) {
        guard owns(activeGeneration) else { return }
        cadenceTask?.cancel()
        cadenceTask = nil
        context = nil
        status = .failed(generation: activeGeneration, reason: reason)
        terminalSignal?.resolve(.failed(reason))
    }

    private func owns(_ candidate: UInt64) -> Bool {
        generation == candidate && terminalSignal != nil
    }

    private func addingInterval(to instant: UInt64) -> UInt64? {
        let addition = instant.addingReportingOverflow(intervalNanoseconds)
        return addition.overflow ? nil : addition.partialValue
    }

    private func captureDeadline(
        after observedAt: UInt64,
        currentDeadline: UInt64
    ) -> UInt64? {
        guard observedAt >= currentDeadline else { return currentDeadline }
        let elapsed = observedAt - currentDeadline
        let missedIntervals = elapsed / intervalNanoseconds
        guard missedIntervals < UInt64.max else { return nil }
        let intervalCount = missedIntervals + 1
        let product = intervalCount.multipliedReportingOverflow(
            by: intervalNanoseconds
        )
        guard !product.overflow else { return nil }
        let addition = currentDeadline.addingReportingOverflow(product.partialValue)
        return addition.overflow ? nil : addition.partialValue
    }
}

private extension ResponsiveAudioDurabilityCaptureResult {
    var snapshot: ResponsiveAudioProgramSnapshot {
        switch self {
        case let .verified(snapshot),
             let .awaitingDurableAuthority(snapshot):
            snapshot
        }
    }

    var verifiesCurrentAuthority: Bool {
        if case .verified = self { return true }
        return false
    }
}
