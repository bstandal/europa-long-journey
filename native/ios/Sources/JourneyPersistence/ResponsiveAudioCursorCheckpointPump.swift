import ContentKit
import Foundation

public enum ResponsiveAudioCursorCaptureResult: Equatable, Sendable {
    case verified(ResponsiveAudioProgramSnapshot)
    case awaitingDurableAuthority(
        projectedOldSnapshot: ResponsiveAudioProgramSnapshot
    )

    public var snapshot: ResponsiveAudioProgramSnapshot {
        switch self {
        case let .verified(snapshot),
             let .awaitingDurableAuthority(snapshot):
            snapshot
        }
    }

    public var verifiesCurrentAuthority: Bool {
        if case .verified = self { return true }
        return false
    }
}

public enum ResponsiveAudioCursorCheckpointPumpFailureOrigin:
    String,
    Equatable,
    Sendable {
    case writerCapture
    case writerPersist
    case writerDeadline
    case handoffDeadline
}

#if DEBUG
public struct ResponsiveAudioCursorCheckpointPumpFailureDiagnostic:
    Equatable,
    Sendable,
    CustomStringConvertible {
    public let origin: ResponsiveAudioCursorCheckpointPumpFailureOrigin
    public let generation: UInt64
    public let observedAtNanoseconds: UInt64
    public let baselineNanoseconds: UInt64?
    public let elapsedNanoseconds: UInt64?
    public let writerPersistStartedAtNanoseconds: UInt64?
    public let obsoleteWriterGeneration: UInt64?
    public let obsoleteWriterPersistStartedAtNanoseconds: UInt64?
    public let detail: String

    public var description: String {
        "\(origin.rawValue);generation=\(generation)"
            + ";observed=\(observedAtNanoseconds)"
            + ";baseline=\(Self.render(baselineNanoseconds))"
            + ";elapsed=\(Self.render(elapsedNanoseconds))"
            + ";writerStarted=\(Self.render(writerPersistStartedAtNanoseconds))"
            + ";obsoleteGeneration=\(Self.render(obsoleteWriterGeneration))"
            + ";obsoleteWriterStarted="
            + Self.render(obsoleteWriterPersistStartedAtNanoseconds)
            + ";detail=\(detail)"
    }

    private static func render<T>(_ value: T?) -> String {
        value.map(String.init(describing:)) ?? "none"
    }
}
#endif

/// Keeps the crash-recovery cursor no more than a bounded age behind rendered
/// audio. The first deadline is covered by the journaled session baseline.
/// A write failure or missed deadline invokes `failClosed` exactly once; the
/// app uses that callback to physically pause audio rather than continue with
/// an unverifiable cursor.
@MainActor
public final class ResponsiveAudioCursorCheckpointPump {
    public typealias Capture = @MainActor () throws
        -> ResponsiveAudioCursorCaptureResult
    public typealias Persist = @MainActor (
        ResponsiveAudioProgramSnapshot,
        UInt64
    ) async throws -> Void
    public typealias FailClosed = @MainActor () -> Void
    public typealias MonotonicNow = @Sendable () -> UInt64
    public typealias Sleep = @Sendable (UInt64) async throws -> Void

    public static let productionIntervalNanoseconds: UInt64 = 125_000_000
    public static let productionMaximumAgeNanoseconds: UInt64 = 250_000_000

    public struct HandoffDeadlineToken: Hashable, Sendable {
        fileprivate let generation: UInt64
        fileprivate let candidateCapturedAtNanoseconds: UInt64
        fileprivate let lastRecoverableCaptureNanoseconds: UInt64
    }

    public private(set) var isRunning = false
    public private(set) var didFailClosed = false
    public private(set) var lastVerifiedCaptureNanoseconds: UInt64?
#if DEBUG
    public private(set) var failureDiagnosticForTesting:
        ResponsiveAudioCursorCheckpointPumpFailureDiagnostic?
#endif

    public var isPeriodicallyProtectingPlayback: Bool {
        isRunning
            && !didFailClosed
            && writerTask != nil
            && watchdogTask != nil
    }

    private let intervalNanoseconds: UInt64
    private let maximumAgeNanoseconds: UInt64
    private let now: MonotonicNow
    private let sleep: Sleep
    private var generation: UInt64 = 0
    private var writerTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
#if DEBUG
    private var writerPersistStartedByGeneration: [UInt64: UInt64] = [:]
    private var handoffObsoleteWriterGeneration: UInt64?
#endif
    private enum InitialVerificationState: Equatable {
        case idle
        case pending
        case succeeded
        case failed
    }
    private var initialVerificationState = InitialVerificationState.idle
    private var initialVerificationWaiters: [
        CheckedContinuation<Bool, Never>
    ] = []

    public init(
        intervalNanoseconds: UInt64 = productionIntervalNanoseconds,
        maximumAgeNanoseconds: UInt64 = productionMaximumAgeNanoseconds,
        now: @escaping MonotonicNow = { DispatchTime.now().uptimeNanoseconds },
        sleep: @escaping Sleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        precondition(intervalNanoseconds > 0)
        precondition(maximumAgeNanoseconds >= intervalNanoseconds)
        self.intervalNanoseconds = intervalNanoseconds
        self.maximumAgeNanoseconds = maximumAgeNanoseconds
        self.now = now
        self.sleep = sleep
    }

    public func start(
        lastVerifiedCaptureNanoseconds: UInt64? = nil,
        capture: @escaping Capture,
        persist: @escaping Persist,
        failClosed: @escaping FailClosed
    ) {
        stop()
#if DEBUG
        failureDiagnosticForTesting = nil
        handoffObsoleteWriterGeneration = nil
#endif
        guard generation < UInt64.max else {
            didFailClosed = true
            recordFailureDiagnostic(
                origin: .writerDeadline,
                generation: generation,
                detail: "generation-exhausted"
            )
            failClosed()
            return
        }
        generation += 1
        let activeGeneration = generation
        isRunning = true
        didFailClosed = false
        initialVerificationState = .pending
        self.lastVerifiedCaptureNanoseconds =
            lastVerifiedCaptureNanoseconds ?? now()
        guard let baseline = self.lastVerifiedCaptureNanoseconds,
              age(since: baseline, at: now())
                < maximumAgeNanoseconds else {
            fail(
                generation: activeGeneration,
                origin: .writerDeadline,
                detail: "start-baseline-expired",
                baselineNanoseconds: self.lastVerifiedCaptureNanoseconds,
                failClosed: failClosed
            )
            return
        }

        writerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var isInitialWrite = true
            while self.owns(activeGeneration) {
                do {
                    if isInitialWrite {
                        isInitialWrite = false
                    } else {
                        try await self.sleep(self.intervalNanoseconds)
                    }
                    guard self.owns(activeGeneration) else { return }
                    let capturedAt = self.now()
                    let result: ResponsiveAudioCursorCaptureResult
                    do {
                        result = try capture()
                    } catch is CancellationError {
                        return
                    } catch {
                        self.fail(
                            generation: activeGeneration,
                            origin: .writerCapture,
                            detail: Self.errorType(error),
                            failClosed: failClosed
                        )
                        return
                    }
                    let persistStartedAt = self.now()
                    self.recordWriterPersistStarted(
                        generation: activeGeneration,
                        at: persistStartedAt
                    )
                    do {
                        try await persist(result.snapshot, capturedAt)
                    } catch is CancellationError {
                        self.recordWriterPersistEnded(
                            generation: activeGeneration
                        )
                        return
                    } catch {
                        self.fail(
                            generation: activeGeneration,
                            origin: .writerPersist,
                            detail: Self.errorType(error),
                            writerPersistStartedAtNanoseconds:
                                persistStartedAt,
                            failClosed: failClosed
                        )
                        self.recordWriterPersistEnded(
                            generation: activeGeneration
                        )
                        return
                    }
                    self.recordWriterPersistEnded(
                        generation: activeGeneration
                    )
                    guard self.owns(activeGeneration) else { return }
                    if result.verifiesCurrentAuthority {
                        self.lastVerifiedCaptureNanoseconds = capturedAt
                        self.completeInitialVerification(
                            true,
                            generation: activeGeneration
                        )
                        if self.age(since: capturedAt, at: self.now())
                            >= self.maximumAgeNanoseconds {
                            self.fail(
                                generation: activeGeneration,
                                origin: .writerDeadline,
                                detail: "post-persist-expired",
                                baselineNanoseconds: capturedAt,
                                writerPersistStartedAtNanoseconds:
                                    persistStartedAt,
                                failClosed: failClosed
                            )
                            return
                        }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self.fail(
                        generation: activeGeneration,
                        origin: .writerDeadline,
                        detail: "writer-loop-unexpected-"
                            + Self.errorType(error),
                        failClosed: failClosed
                    )
                    return
                }
            }
        }

        armWatchdog(
            generation: activeGeneration,
            origin: .writerDeadline,
            failClosed: failClosed
        )
    }

    /// Test and diagnostic seam that observes the first verified sidecar
    /// result for the current generation. Production playback deliberately
    /// does not await this: the journaled session baseline and the absolute
    /// watchdog already cover the first 250 ms, including a valid automatic
    /// boundary that replaces this generation before its first fsync returns.
    public func awaitInitialVerification() async -> Bool {
        switch initialVerificationState {
        case .succeeded:
            return true
        case .failed, .idle:
            return false
        case .pending:
            return await withCheckedContinuation { continuation in
                initialVerificationWaiters.append(continuation)
            }
        }
    }

    /// Replaces the periodic old-authority writer with one absolute watchdog
    /// before an async sidecar handoff begins. The watchdog remains anchored
    /// to the last cursor that crash recovery can actually restore. The newer
    /// candidate timestamp identifies the sidecar write but cannot refresh the
    /// deadline until that write has returned durable.
    public func beginHandoffDeadline(
        candidateCapturedAtNanoseconds: UInt64,
        lastRecoverableCaptureNanoseconds: UInt64,
        failClosed: @escaping FailClosed
    ) -> HandoffDeadlineToken? {
#if DEBUG
        handoffObsoleteWriterGeneration = generation
#endif
        guard isRunning, !didFailClosed,
              generation < UInt64.max else {
            failCurrentIfNeeded(
                origin: .handoffDeadline,
                detail: "handoff-pump-not-running",
                baselineNanoseconds:
                    lastRecoverableCaptureNanoseconds,
                failClosed: failClosed
            )
            return nil
        }
        let observedAt = now()
        guard candidateCapturedAtNanoseconds
                >= lastRecoverableCaptureNanoseconds else {
            failCurrentIfNeeded(
                origin: .handoffDeadline,
                detail: "handoff-candidate-predates-recoverable-baseline",
                baselineNanoseconds:
                    lastRecoverableCaptureNanoseconds,
                failClosed: failClosed
            )
            return nil
        }
        guard age(
            since: lastRecoverableCaptureNanoseconds,
            at: observedAt
        ) < maximumAgeNanoseconds else {
            failCurrentIfNeeded(
                origin: .handoffDeadline,
                detail: "handoff-recoverable-baseline-expired",
                baselineNanoseconds:
                    lastRecoverableCaptureNanoseconds,
                failClosed: failClosed
            )
            return nil
        }
        guard age(since: candidateCapturedAtNanoseconds, at: observedAt)
                < maximumAgeNanoseconds else {
            failCurrentIfNeeded(
                origin: .handoffDeadline,
                detail: "handoff-capture-expired",
                baselineNanoseconds:
                    lastRecoverableCaptureNanoseconds,
                failClosed: failClosed
            )
            return nil
        }

        completeInitialVerification(false)
        generation += 1
        let activeGeneration = generation
        writerTask?.cancel()
        watchdogTask?.cancel()
        writerTask = nil
        watchdogTask = nil
        isRunning = true
        lastVerifiedCaptureNanoseconds =
            lastRecoverableCaptureNanoseconds
        initialVerificationState = .idle
        armWatchdog(
            generation: activeGeneration,
            origin: .handoffDeadline,
            failClosed: failClosed
        )
        return HandoffDeadlineToken(
            generation: activeGeneration,
            candidateCapturedAtNanoseconds:
                candidateCapturedAtNanoseconds,
            lastRecoverableCaptureNanoseconds:
                lastRecoverableCaptureNanoseconds
        )
    }

    public func ownsHandoffDeadline(
        _ token: HandoffDeadlineToken,
        candidateCapturedAtNanoseconds: UInt64,
        lastRecoverableCaptureNanoseconds: UInt64
    ) -> Bool {
        owns(token.generation)
            && !didFailClosed
            && token.candidateCapturedAtNanoseconds
                == candidateCapturedAtNanoseconds
            && token.lastRecoverableCaptureNanoseconds
                == lastRecoverableCaptureNanoseconds
            && lastVerifiedCaptureNanoseconds
                == lastRecoverableCaptureNanoseconds
            && age(
                since: lastRecoverableCaptureNanoseconds,
                at: now()
            )
                < maximumAgeNanoseconds
    }

    public func stop() {
        completeInitialVerification(false)
        if generation < UInt64.max { generation += 1 }
        writerTask?.cancel()
        watchdogTask?.cancel()
        writerTask = nil
        watchdogTask = nil
        isRunning = false
        lastVerifiedCaptureNanoseconds = nil
        initialVerificationState = .idle
    }

    private func owns(_ candidate: UInt64) -> Bool {
        isRunning && generation == candidate
    }

    private func fail(
        generation candidate: UInt64,
        origin: ResponsiveAudioCursorCheckpointPumpFailureOrigin,
        detail: String,
        baselineNanoseconds: UInt64? = nil,
        writerPersistStartedAtNanoseconds: UInt64? = nil,
        failClosed: FailClosed
    ) {
        guard owns(candidate), !didFailClosed else { return }
        recordFailureDiagnostic(
            origin: origin,
            generation: candidate,
            detail: detail,
            baselineNanoseconds:
                baselineNanoseconds ?? lastVerifiedCaptureNanoseconds,
            writerPersistStartedAtNanoseconds:
                writerPersistStartedAtNanoseconds
        )
        didFailClosed = true
        isRunning = false
        writerTask?.cancel()
        watchdogTask?.cancel()
        writerTask = nil
        watchdogTask = nil
        lastVerifiedCaptureNanoseconds = nil
        completeInitialVerification(false, generation: candidate)
        failClosed()
    }

    private func failCurrentIfNeeded(
        origin: ResponsiveAudioCursorCheckpointPumpFailureOrigin,
        detail: String,
        baselineNanoseconds: UInt64?,
        failClosed: FailClosed
    ) {
        guard !didFailClosed else { return }
        if isRunning {
            fail(
                generation: generation,
                origin: origin,
                detail: detail,
                baselineNanoseconds: baselineNanoseconds,
                failClosed: failClosed
            )
            return
        }
        recordFailureDiagnostic(
            origin: origin,
            generation: generation,
            detail: detail,
            baselineNanoseconds: baselineNanoseconds
        )
        didFailClosed = true
        failClosed()
    }

    private func armWatchdog(
        generation activeGeneration: UInt64,
        origin: ResponsiveAudioCursorCheckpointPumpFailureOrigin,
        failClosed: @escaping FailClosed
    ) {
        watchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.owns(activeGeneration) {
                guard self.owns(activeGeneration),
                      let lastVerified = self.lastVerifiedCaptureNanoseconds else {
                    return
                }
                let elapsed = self.age(
                    since: lastVerified,
                    at: self.now()
                )
                if elapsed >= self.maximumAgeNanoseconds {
                    self.fail(
                        generation: activeGeneration,
                        origin: origin,
                        detail: origin == .handoffDeadline
                            ? "handoff-watchdog"
                            : "writer-watchdog",
                        baselineNanoseconds: lastVerified,
                        failClosed: failClosed
                    )
                    return
                }
                do {
                    try await self.sleep(
                        self.maximumAgeNanoseconds - elapsed
                    )
                } catch {
                    return
                }
            }
        }
    }

    private func completeInitialVerification(
        _ succeeded: Bool,
        generation candidate: UInt64? = nil
    ) {
        if let candidate, generation != candidate { return }
        guard initialVerificationState == .pending else { return }
        initialVerificationState = succeeded ? .succeeded : .failed
        let waiters = initialVerificationWaiters
        initialVerificationWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume(returning: succeeded) }
    }

    private func age(since earlier: UInt64, at later: UInt64) -> UInt64 {
        later >= earlier ? later - earlier : UInt64.max
    }

    private static func errorType(_ error: Error) -> String {
        String(reflecting: type(of: error))
    }

    private func recordWriterPersistStarted(
        generation: UInt64,
        at nanoseconds: UInt64
    ) {
#if DEBUG
        writerPersistStartedByGeneration[generation] = nanoseconds
#endif
    }

    private func recordWriterPersistEnded(generation: UInt64) {
#if DEBUG
        writerPersistStartedByGeneration.removeValue(forKey: generation)
#endif
    }

    private func recordFailureDiagnostic(
        origin: ResponsiveAudioCursorCheckpointPumpFailureOrigin,
        generation: UInt64,
        detail: String,
        baselineNanoseconds: UInt64? = nil,
        writerPersistStartedAtNanoseconds: UInt64? = nil
    ) {
#if DEBUG
        let observedAt = now()
        let obsoleteGeneration = handoffObsoleteWriterGeneration
        let resolvedWriterStarted = writerPersistStartedAtNanoseconds
            ?? writerPersistStartedByGeneration[generation]
        let obsoleteWriterStarted = obsoleteGeneration.flatMap {
            writerPersistStartedByGeneration[$0]
        }
        failureDiagnosticForTesting =
            ResponsiveAudioCursorCheckpointPumpFailureDiagnostic(
                origin: origin,
                generation: generation,
                observedAtNanoseconds: observedAt,
                baselineNanoseconds: baselineNanoseconds,
                elapsedNanoseconds: baselineNanoseconds.map {
                    age(since: $0, at: observedAt)
                },
                writerPersistStartedAtNanoseconds: resolvedWriterStarted,
                obsoleteWriterGeneration: obsoleteGeneration,
                obsoleteWriterPersistStartedAtNanoseconds:
                    obsoleteWriterStarted,
                detail: detail
            )
#endif
    }
}
