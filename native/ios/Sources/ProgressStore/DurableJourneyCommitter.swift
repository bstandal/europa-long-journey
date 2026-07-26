import Foundation
import JourneyDomain

/// An opaque version of the state owned by a `DurableJourneyCommitter`.
///
/// A revision is valid only for the committer that issued it. Callers use the
/// value to prove that the state they prepared against is still authoritative;
/// they do not construct or advance revisions themselves.
public struct DurableJourneyRevision: Equatable, Hashable, Sendable {
    fileprivate let authorityID: UUID
    fileprivate let ordinal: UInt64

    fileprivate init(authorityID: UUID, ordinal: UInt64) {
        self.authorityID = authorityID
        self.ordinal = ordinal
    }

    fileprivate static func detached(sequence: UInt64) -> Self {
        Self(authorityID: detachedAuthorityID, ordinal: sequence)
    }

    private static let detachedAuthorityID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// One actor-isolated read of all state needed to prepare a causal transition.
///
/// Reading these values together prevents a caller from combining a Journey
/// state from one commit with the logical clock or revision from another.
public struct DurableJourneyStateSnapshot: Equatable, Sendable {
    public let state: JourneyState
    public let logicalTimeMillis: Int64
    public let revision: DurableJourneyRevision
    public let sequence: UInt64

    public init(
        state: JourneyState,
        logicalTimeMillis: Int64,
        revision: DurableJourneyRevision,
        sequence: UInt64
    ) {
        self.state = state
        self.logicalTimeMillis = logicalTimeMillis
        self.revision = revision
        self.sequence = sequence
    }
}

/// A state transition whose event has already crossed the durable journal boundary.
///
/// Callers may publish `state` and its effects immediately. Before `commit(_:)`
/// returns, the transition remains private and must not be presented as lasting
/// Journey state.
public struct DurableJourneyCommit: Equatable, Sendable {
    public let sequence: UInt64
    public let revision: DurableJourneyRevision
    public let event: JourneyEvent
    public let state: JourneyState
    public let effects: [JourneyEffect]

    /// Retained for source compatibility with callers that construct a commit
    /// value outside the committer. A normally produced commit receives its
    /// revision from `DurableJourneyCommitter` instead.
    public init(
        sequence: UInt64,
        event: JourneyEvent,
        state: JourneyState,
        effects: [JourneyEffect]
    ) {
        self.init(
            sequence: sequence,
            revision: DurableJourneyRevision.detached(sequence: sequence),
            event: event,
            state: state,
            effects: effects
        )
    }

    public init(
        sequence: UInt64,
        revision: DurableJourneyRevision,
        event: JourneyEvent,
        state: JourneyState,
        effects: [JourneyEffect]
    ) {
        self.sequence = sequence
        self.revision = revision
        self.event = event
        self.state = state
        self.effects = effects
    }

    public var requiresCheckpoint: Bool {
        effects.contains { effect in
            if case .checkpoint = effect { return true }
            return false
        }
    }
}

public enum DurableJourneyCommitterError: Error, Equatable, Sendable {
    case logicalClockExhausted
    case revisionExhausted
    /// The last append may already exist on disk. This committer is
    /// permanently retired; only a new committer built from a fresh
    /// `JourneyRestoration` may accept another action.
    case persistenceRestoreRequired
    /// The append boundary returned a journal sequence other than the exact
    /// successor prepared by this authority. The write may nevertheless be
    /// durable, so the committer is retired rather than permitting a retry.
    case unexpectedAppendSequence(expected: UInt64, actual: UInt64)
    case staleRevision(
        expected: DurableJourneyRevision,
        actual: DurableJourneyRevision
    )
    /// A later legitimate commit superseded the receipt before optional
    /// compaction began. The journal remains authoritative and no restore is
    /// required merely because this checkpoint was skipped.
    case staleCheckpoint(
        expected: DurableJourneyRevision,
        actual: DurableJourneyRevision
    )
    case checkpointReceiptMismatch
    case checkpointUnavailable
    case rejectedTransition(String)
}

/// Serialises causal Journey transitions around a write-ahead commit point.
///
/// Reduction happens against a private copy. The copy becomes committed only
/// after `append` returns, which for `ProgressStore` means the complete journal
/// record has been written and synchronised. A checkpoint is deliberately not
/// part of this boundary: it compacts state that is already recoverable by
/// replaying the journal.
public actor DurableJourneyCommitter {
    public typealias AppendOperation = @Sendable (
        ConditionalJourneyAppendRequest
    ) async throws -> UInt64
    public typealias CheckpointOperation = @Sendable (
        DurableJourneyCommit
    ) async throws -> Void

    private let reducer: JourneyReducer
    private let append: AppendOperation
    private let checkpoint: CheckpointOperation?
    private let revisionAuthorityID: UUID
    private var committedState: JourneyState
    private var logicalTimeMillis: Int64
    private var revision: DurableJourneyRevision
    private var persistenceRestoreIsRequired = false
#if DEBUG
    private var persistenceRestoreDiagnosticForTesting: String?
#endif
    private var lastCommit: DurableJourneyCommit?
    private var commitIsInFlight = false
    private var commitWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        restoredState: JourneyState,
        lastSequence: UInt64,
        reducer: JourneyReducer = JourneyReducer(),
        append: @escaping AppendOperation,
        checkpoint: CheckpointOperation? = nil
    ) {
        self.reducer = reducer
        self.append = append
        self.checkpoint = checkpoint
        revisionAuthorityID = UUID()
        committedState = restoredState
        logicalTimeMillis = max(
            restoredState.lastLogicalTimeMillis,
            Int64(clamping: lastSequence)
        )
        revision = DurableJourneyRevision(
            authorityID: revisionAuthorityID,
            ordinal: lastSequence
        )
    }

    public func commit(_ action: JourneyAction) async throws -> DurableJourneyCommit {
        try await performCommit(action, expectedRevision: nil)
    }

    /// Commits only if no durable transition has superseded `expectedRevision`.
    ///
    /// Revision validation happens while this caller owns the commit slot and
    /// before event construction, reduction or journal append. A stale caller
    /// therefore cannot consume logical time or produce any persistence work.
    public func commit(
        _ action: JourneyAction,
        expectedRevision: DurableJourneyRevision
    ) async throws -> DurableJourneyCommit {
        try await performCommit(action, expectedRevision: expectedRevision)
    }

    public func currentCommittedSnapshot() -> DurableJourneyStateSnapshot {
        DurableJourneyStateSnapshot(
            state: committedState,
            logicalTimeMillis: logicalTimeMillis,
            revision: revision,
            sequence: revision.ordinal
        )
    }

    public func currentCommittedState() -> JourneyState {
        committedState
    }

    public func currentLogicalTimeMillis() -> Int64 {
        logicalTimeMillis
    }

    /// Returns the journal sequence owned by the same actor-isolated authority
    /// as `currentCommittedState()`. Presentation owners use this after a
    /// controller-managed commit so they cannot publish the returned receipt
    /// over a newer transition from another route owner.
    public func currentCommittedSequence() -> UInt64 {
        revision.ordinal
    }

#if DEBUG
    public func persistenceRestoreDiagnosticForTestingValue() -> String? {
        persistenceRestoreDiagnosticForTesting
    }
#endif

    /// Compacts only the exact latest commit while owning the same FIFO slot as
    /// causal appends. If another accepted commit won the slot first, this
    /// checkpoint is safely stale and the journal remains complete.
    public func checkpoint(_ commit: DurableJourneyCommit) async throws {
        await acquireCommitSlot()
        defer { releaseCommitSlot() }

        guard !persistenceRestoreIsRequired else {
            throw DurableJourneyCommitterError.persistenceRestoreRequired
        }
        guard commit.revision == revision else {
            throw DurableJourneyCommitterError.staleCheckpoint(
                expected: commit.revision,
                actual: revision
            )
        }
        guard lastCommit == commit,
              commit.sequence == revision.ordinal,
              commit.state == committedState else {
            throw DurableJourneyCommitterError.checkpointReceiptMismatch
        }
        guard let checkpoint else {
            throw DurableJourneyCommitterError.checkpointUnavailable
        }

        do {
            try await checkpoint(commit)
        } catch let failure as ProgressStoreAppendFailure {
            switch failure.disposition {
            case .noJournalRecordWriteAttempted:
                throw failure
            case .canonicalAuthorityMismatch, .durabilityIndeterminate:
#if DEBUG
                persistenceRestoreDiagnosticForTesting =
                    "checkpoint:\(failure.disposition):"
                        + String(reflecting: failure.underlyingError)
#endif
                persistenceRestoreIsRequired = true
                throw DurableJourneyCommitterError.persistenceRestoreRequired
            }
        } catch {
#if DEBUG
            persistenceRestoreDiagnosticForTesting =
                "checkpoint:unclassified:" + String(reflecting: error)
#endif
            persistenceRestoreIsRequired = true
            throw DurableJourneyCommitterError.persistenceRestoreRequired
        }
    }

    private func performCommit(
        _ action: JourneyAction,
        expectedRevision: DurableJourneyRevision?
    ) async throws -> DurableJourneyCommit {
        await acquireCommitSlot()
        defer { releaseCommitSlot() }

        guard !persistenceRestoreIsRequired else {
            throw DurableJourneyCommitterError.persistenceRestoreRequired
        }
        if let expectedRevision, expectedRevision != revision {
            throw DurableJourneyCommitterError.staleRevision(
                expected: expectedRevision,
                actual: revision
            )
        }

        guard revision.ordinal < UInt64.max else {
            throw DurableJourneyCommitterError.revisionExhausted
        }
        let expectedSequence = revision.ordinal + 1
        guard logicalTimeMillis < Int64.max else {
            throw DurableJourneyCommitterError.logicalClockExhausted
        }

        let event = JourneyEvent(
            logicalTimeMillis: logicalTimeMillis + 1,
            action: action
        )
        var candidate = committedState
        let effects = reducer.reduce(state: &candidate, event: event)

        // A reducer rejection is a failed preflight, not a Journey event. In
        // particular it must not consume a journal sequence or logical time,
        // and the reducer's private candidate must never become observable.
        if let reason = effects.compactMap({ effect -> String? in
            guard case let .rejected(reason) = effect else { return nil }
            return reason
        }).first {
            throw DurableJourneyCommitterError.rejectedTransition(reason)
        }

        // There is intentionally no mutation of committedState before this
        // write-ahead operation has completed.
        let sequence: UInt64
        do {
            sequence = try await append(
                ConditionalJourneyAppendRequest(
                    expectedPreviousSequence: revision.ordinal,
                    expectedPreviousState: committedState,
                    event: event,
                    expectedCandidateState: candidate
                )
            )
        } catch let failure as ProgressStoreAppendFailure {
            switch failure.disposition {
            case .noJournalRecordWriteAttempted:
                throw failure
            case .canonicalAuthorityMismatch, .durabilityIndeterminate:
#if DEBUG
                persistenceRestoreDiagnosticForTesting =
                    "append:\(failure.disposition):"
                        + String(reflecting: failure.underlyingError)
#endif
                persistenceRestoreIsRequired = true
                throw DurableJourneyCommitterError.persistenceRestoreRequired
            }
        } catch {
            // An unclassified failure, including cancellation after the
            // append call began, cannot prove that no journal bytes crossed
            // the boundary. Retire this authority before releasing its FIFO
            // slot so no queued caller can duplicate the event.
#if DEBUG
            persistenceRestoreDiagnosticForTesting =
                "append:unclassified:" + String(reflecting: error)
#endif
            persistenceRestoreIsRequired = true
            throw DurableJourneyCommitterError.persistenceRestoreRequired
        }
        guard sequence == expectedSequence else {
            persistenceRestoreIsRequired = true
            throw DurableJourneyCommitterError.unexpectedAppendSequence(
                expected: expectedSequence,
                actual: sequence
            )
        }

        // No suspension point is allowed between the durable commit and the
        // in-memory commit. A process kill here is recovered from the journal.
        let resultingRevision = DurableJourneyRevision(
            authorityID: revisionAuthorityID,
            ordinal: revision.ordinal + 1
        )
        committedState = candidate
        logicalTimeMillis = event.logicalTimeMillis
        revision = resultingRevision
        let commit = DurableJourneyCommit(
            sequence: sequence,
            revision: resultingRevision,
            event: event,
            state: candidate,
            effects: effects
        )
        lastCommit = commit
        return commit
    }

    private func acquireCommitSlot() async {
        guard commitIsInFlight else {
            commitIsInFlight = true
            return
        }
        await withCheckedContinuation { continuation in
            commitWaiters.append(continuation)
        }
    }

    private func releaseCommitSlot() {
        guard !commitWaiters.isEmpty else {
            commitIsInFlight = false
            return
        }
        commitWaiters.removeFirst().resume()
    }
}
