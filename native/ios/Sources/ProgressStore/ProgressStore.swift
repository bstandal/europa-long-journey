import ContentKit
import CryptoKit
import Darwin
import Foundation
import JourneyDomain

public enum ProgressStoreError: Error, Equatable, Sendable {
    case invalidJournalRecord(Int)
    case unsupportedJournalVersion(Int)
    case brokenSequence(expected: UInt64, actual: UInt64)
    case brokenDigest(sequence: UInt64)
    case invalidSnapshot
    case unsupportedSnapshotVersion(Int)
    case appendRequiresReconciliation
    case sequenceExhausted
    case canonicalAuthorityUnavailable
    case canonicalAuthorityMismatch
    case conditionalPreviousStateMismatch
    case conditionalEventTimeMismatch(expected: Int64, actual: Int64)
    case conditionalCandidateStateMismatch
    case conditionalTransitionRejected
    case conditionalCheckpointReceiptMismatch
    case migrationInterrupted
    case migrationRollbackTampered
    case migrationRollbackAuthorityMismatch
    case migrationRollbackStale
    case migrationRollbackFailed
}

enum SaveMigrationCommitBoundary: Sendable {
    case backupDurable
    case snapshotActivated
    case journalReset
}

/// The complete causal assertion which must be true before a Journey event is
/// allowed to cross the journal boundary. `ProgressStore` independently checks
/// every value while holding the directory transaction lock.
public struct ConditionalJourneyAppendRequest: Equatable, Sendable {
    public let expectedPreviousSequence: UInt64
    public let expectedPreviousState: JourneyState
    public let event: JourneyEvent
    public let expectedCandidateState: JourneyState

    public init(
        expectedPreviousSequence: UInt64,
        expectedPreviousState: JourneyState,
        event: JourneyEvent,
        expectedCandidateState: JourneyState
    ) {
        self.expectedPreviousSequence = expectedPreviousSequence
        self.expectedPreviousState = expectedPreviousState
        self.event = event
        self.expectedCandidateState = expectedCandidateState
    }
}

/// What is known after a persistence mutation throws.
///
/// Only `noJournalRecordWriteAttempted` permits a caller to know that retrying
/// a rejected append cannot duplicate its event. Once a journal write or
/// checkpoint replacement has been attempted, a complete new state may already
/// be visible even though its durability could not be established. The store
/// must be restored before another mutation.
public enum ProgressStoreAppendFailureDisposition: Equatable, Sendable {
    case noJournalRecordWriteAttempted
    /// The request was prepared against another canonical history. No bytes
    /// were written, but the stale causal authority must be retired.
    case canonicalAuthorityMismatch
    case durabilityIndeterminate
}

/// A failed persistence mutation together with the strongest durability
/// conclusion the store can make.
public struct ProgressStoreAppendFailure: Error, Sendable {
    public let disposition: ProgressStoreAppendFailureDisposition
    public let underlyingError: any Error

    public init(
        disposition: ProgressStoreAppendFailureDisposition,
        underlyingError: any Error
    ) {
        self.disposition = disposition
        self.underlyingError = underlyingError
    }
}

public struct JourneyRestoration: Equatable, Sendable {
    public let state: JourneyState
    public let replayedEventCount: Int
    public let lastSequence: UInt64
    public let didCommitSaveMigration: Bool

    public init(
        state: JourneyState,
        replayedEventCount: Int,
        lastSequence: UInt64,
        didCommitSaveMigration: Bool = false
    ) {
        self.state = state
        self.replayedEventCount = replayedEventCount
        self.lastSequence = lastSequence
        self.didCommitSaveMigration = didCommitSaveMigration
    }
}

private struct JournalHeader: Decodable {
    let formatVersion: Int
    let generation: String
    let sequence: UInt64
}

private struct JournalRecord: Codable, Equatable, Sendable {
    let formatVersion: Int
    let generation: String
    let sequence: UInt64
    let previousDigest: String
    let event: JourneyEvent
    let digest: String
}

private struct JournalDigestMaterial: Codable, Sendable {
    let formatVersion: Int
    let generation: String
    let sequence: UInt64
    let previousDigest: String
    let event: JourneyEvent
}

private struct SnapshotRecord: Codable, Sendable {
    let envelopeFormatVersion: Int
    let sequence: UInt64
    let journalGeneration: String
    let snapshot: SaveSnapshot
    let lastEvent: JourneyEvent?
    let digest: String
}

private struct SnapshotDigestMaterial: Codable, Sendable {
    let envelopeFormatVersion: Int
    let sequence: UInt64
    let journalGeneration: String
    let snapshot: SaveSnapshot
    let lastEvent: JourneyEvent?
}

private struct SaveMigrationRollbackMaterial: Codable, Sendable {
    let formatVersion: Int
    let snapshotBytes: Data?
    let journalBytes: Data?
    let expectedMigratedSnapshotSHA256: String
    let expectedMigratedJournalSHA256: String
    let migrationAuthoritySetSHA256: String
}

private struct SaveMigrationRollbackRecord: Codable, Sendable {
    let formatVersion: Int
    let snapshotBytes: Data?
    let journalBytes: Data?
    let expectedMigratedSnapshotSHA256: String
    let expectedMigratedJournalSHA256: String
    let migrationAuthoritySetSHA256: String
    let digest: String
}

private struct SaveMigrationAuthorityDigestRecord: Codable, Sendable {
    let packageID: PackageID
    let targetContentVersion: SchemaVersion
    let manifestDigest: String
    let activeGeneration: ActiveSaveMigrationPackageGeneration
    let declarations: [PackageSaveMigrationDeclaration]
}

private struct JournalAnchor: Equatable {
    let sequence: UInt64
    let digest: String
    let generation: String
}

/// Crash-safe offline journal. A checkpoint is self-contained and starts a new journal generation,
/// so obsolete pre-snapshot event formats never need to decode again.
public actor ProgressStore {
    typealias JournalAppendOperation = @Sendable (Data, URL) throws -> Void
    typealias JournalReconciliationOperation = @Sendable (URL) throws -> Void
    typealias AtomicReplacementOperation = @Sendable (Data, URL) throws -> Void
    typealias SaveMigrationBoundaryOperation = @Sendable (SaveMigrationCommitBoundary) throws -> Void

    public nonisolated let directoryURL: URL
    public nonisolated let journalFileURL: URL
    public nonisolated let snapshotFileURL: URL
    public nonisolated let lockFileURL: URL
    public nonisolated let migrationLastKnownGoodFileURL: URL
    public nonisolated let migrationInFlightFileURL: URL

    private let reducer: JourneyReducer
    private let journalAppendOperation: JournalAppendOperation
    private let journalReconciliationOperation: JournalReconciliationOperation
    private let atomicReplacementOperation: AtomicReplacementOperation
    private let saveMigrationRegistry: SaveMigrationRegistry
    private let saveMigrationAuthorities: [VerifiedPackageSaveMigrationAuthority]
    private let saveMigrationBoundaryOperation: SaveMigrationBoundaryOperation
    private var head: (sequence: UInt64, digest: String)?
    private var journalGeneration: String?
    private var appendRequiresReconciliation = false
    private var canonicalState: JourneyState?
    private var canonicalAnchor: JournalAnchor?
    private var canonicalLastTransition: CanonicalTransition?
    private var canonicalReplayOrigin: CanonicalReplayOrigin?
    private var restorationInitialState: JourneyState?

    private struct CanonicalTransition {
        let previousState: JourneyState
        let event: JourneyEvent
        let candidateState: JourneyState
    }

    private struct CanonicalReplayOrigin {
        let anchor: JournalAnchor
        let state: JourneyState
    }

    private struct ReloadedCanonicalAuthority {
        let anchor: JournalAnchor
        let state: JourneyState
        let lastEvent: JourneyEvent?
    }

    public init(
        directoryURL: URL,
        reducer: JourneyReducer = JourneyReducer(),
        saveMigrationRegistry: SaveMigrationRegistry = .empty,
        saveMigrationAuthorities: [VerifiedPackageSaveMigrationAuthority] = []
    ) throws {
        let standardizedDirectory = directoryURL.standardizedFileURL
        try FileManager.default.createDirectory(
            at: standardizedDirectory,
            withIntermediateDirectories: true
        )
        let canonicalDirectory = standardizedDirectory.resolvingSymlinksInPath()
        self.directoryURL = canonicalDirectory
        journalFileURL = canonicalDirectory.appendingPathComponent("journey.events", isDirectory: false)
        snapshotFileURL = canonicalDirectory.appendingPathComponent("journey.snapshot", isDirectory: false)
        lockFileURL = canonicalDirectory.appendingPathComponent(".journey-progress.lock", isDirectory: false)
        migrationLastKnownGoodFileURL = canonicalDirectory.appendingPathComponent(
            "journey.migration-last-known-good",
            isDirectory: false
        )
        migrationInFlightFileURL = canonicalDirectory.appendingPathComponent(
            "journey.migration-inflight",
            isDirectory: false
        )
        self.reducer = reducer
        journalAppendOperation = Self.appendSynchronously
        journalReconciliationOperation = Self.synchronizeJournal
        atomicReplacementOperation = Self.replaceAtomicallyAndSynchronize
        self.saveMigrationRegistry = saveMigrationRegistry
        self.saveMigrationAuthorities = saveMigrationAuthorities
        saveMigrationBoundaryOperation = { _ in }
    }

    /// Test seam for exercising filesystem outcomes that cannot be produced
    /// deterministically by the platform APIs. Production always uses the
    /// public initializer and the synchronising append operation above.
    init(
        directoryURL: URL,
        reducer: JourneyReducer = JourneyReducer(),
        journalAppendOperation: @escaping JournalAppendOperation = ProgressStore.appendSynchronously,
        journalReconciliationOperation: JournalReconciliationOperation? = nil,
        atomicReplacementOperation: AtomicReplacementOperation? = nil,
        saveMigrationRegistry: SaveMigrationRegistry = .empty,
        saveMigrationAuthorities: [VerifiedPackageSaveMigrationAuthority] = [],
        saveMigrationBoundaryOperation: @escaping SaveMigrationBoundaryOperation = { _ in }
    ) throws {
        let standardizedDirectory = directoryURL.standardizedFileURL
        try FileManager.default.createDirectory(
            at: standardizedDirectory,
            withIntermediateDirectories: true
        )
        let canonicalDirectory = standardizedDirectory.resolvingSymlinksInPath()
        self.directoryURL = canonicalDirectory
        journalFileURL = canonicalDirectory.appendingPathComponent("journey.events", isDirectory: false)
        snapshotFileURL = canonicalDirectory.appendingPathComponent("journey.snapshot", isDirectory: false)
        lockFileURL = canonicalDirectory.appendingPathComponent(".journey-progress.lock", isDirectory: false)
        migrationLastKnownGoodFileURL = canonicalDirectory.appendingPathComponent(
            "journey.migration-last-known-good",
            isDirectory: false
        )
        migrationInFlightFileURL = canonicalDirectory.appendingPathComponent(
            "journey.migration-inflight",
            isDirectory: false
        )
        self.reducer = reducer
        self.journalAppendOperation = journalAppendOperation
        self.journalReconciliationOperation =
            journalReconciliationOperation ?? Self.synchronizeJournal
        self.atomicReplacementOperation =
            atomicReplacementOperation ?? Self.replaceAtomicallyAndSynchronize
        self.saveMigrationRegistry = saveMigrationRegistry
        self.saveMigrationAuthorities = saveMigrationAuthorities
        self.saveMigrationBoundaryOperation = saveMigrationBoundaryOperation
    }

    /// Production write-ahead boundary. The request is accepted only when its
    /// complete causal assertion still matches the canonical disk authority.
    @discardableResult
    public func append(_ request: ConditionalJourneyAppendRequest) throws -> UInt64 {
        do {
            return try withDirectoryTransaction {
                try appendConditionallyWhileLocked(request)
            }
        } catch let failure as ProgressStoreAppendFailure {
            if failure.disposition == .durabilityIndeterminate {
                appendRequiresReconciliation = true
            }
            throw failure
        } catch let failure as DirectoryTransactionFailure {
            let disposition: ProgressStoreAppendFailureDisposition = failure.bodyExecuted
                ? .durabilityIndeterminate
                : .noJournalRecordWriteAttempted
            if disposition == .durabilityIndeterminate {
                appendRequiresReconciliation = true
            }
            throw ProgressStoreAppendFailure(
                disposition: disposition,
                underlyingError: failure
            )
        } catch {
            throw ProgressStoreAppendFailure(
                disposition: .noJournalRecordWriteAttempted,
                underlyingError: error
            )
        }
    }

    /// Unsafe compatibility seam for persistence tests. Shipping callers must
    /// use the conditional request above through `DurableJourneyCommitter`.
    @discardableResult
    func append(_ event: JourneyEvent) throws -> UInt64 {
        do {
            return try withDirectoryTransaction {
                head = nil
                journalGeneration = nil
                return try appendUnconditionallyWhileLocked(event)
            }
        } catch let failure as ProgressStoreAppendFailure {
            if failure.disposition == .durabilityIndeterminate {
                appendRequiresReconciliation = true
            }
            throw failure
        } catch let failure as DirectoryTransactionFailure {
            let disposition: ProgressStoreAppendFailureDisposition = failure.bodyExecuted
                ? .durabilityIndeterminate
                : .noJournalRecordWriteAttempted
            if disposition == .durabilityIndeterminate {
                appendRequiresReconciliation = true
            }
            throw ProgressStoreAppendFailure(
                disposition: disposition,
                underlyingError: failure
            )
        }
    }

    private func appendUnconditionallyWhileLocked(_ event: JourneyEvent) throws -> UInt64 {
        guard !appendRequiresReconciliation else {
            throw ProgressStoreAppendFailure(
                disposition: .durabilityIndeterminate,
                underlyingError: ProgressStoreError.appendRequiresReconciliation
            )
        }

        let sequence: UInt64
        let digest: String
        let data: Data
        do {
            try ensureHead()
            sequence = try Self.nextSequence(after: head?.sequence ?? 0)
            let previousDigest = head?.digest ?? Self.genesisDigest
            let generation = journalGeneration ?? Self.initialJournalGeneration
            let material = JournalDigestMaterial(
                formatVersion: Self.currentJournalFormatVersion,
                generation: generation,
                sequence: sequence,
                previousDigest: previousDigest,
                event: event
            )
            digest = try Self.digest(material)
            let record = JournalRecord(
                formatVersion: Self.currentJournalFormatVersion,
                generation: generation,
                sequence: sequence,
                previousDigest: previousDigest,
                event: event,
                digest: digest
            )
            var encodedRecord = try Self.encoder.encode(record)
            encodedRecord.append(0x0A)
            data = encodedRecord
        } catch let failure as ProgressStoreAppendFailure {
            if failure.disposition == .durabilityIndeterminate {
                appendRequiresReconciliation = true
            }
            throw failure
        } catch {
            throw ProgressStoreAppendFailure(
                disposition: .noJournalRecordWriteAttempted,
                underlyingError: error
            )
        }

        do {
            try journalAppendOperation(data, journalFileURL)
        } catch let failure as ProgressStoreAppendFailure {
            if failure.disposition == .durabilityIndeterminate {
                appendRequiresReconciliation = true
            }
            throw failure
        } catch {
            // An injected or future append operation that does not provide a
            // stage is conservative by definition: it may have written bytes.
            appendRequiresReconciliation = true
            throw ProgressStoreAppendFailure(
                disposition: .durabilityIndeterminate,
                underlyingError: error
            )
        }

        head = (sequence, digest)
        canonicalState = nil
        canonicalAnchor = nil
        canonicalLastTransition = nil
        canonicalReplayOrigin = nil
        restorationInitialState = nil
        return sequence
    }

    /// Production compaction boundary. Only the exact most recent commit from
    /// the same causal authority can be compacted.
    public func checkpoint(_ commit: DurableJourneyCommit) throws {
        do {
            try withDirectoryTransaction {
                try checkpointConditionallyWhileLocked(commit)
            }
        } catch let failure as ProgressStoreAppendFailure {
            if failure.disposition == .durabilityIndeterminate {
                appendRequiresReconciliation = true
            }
            throw failure
        } catch let failure as DirectoryTransactionFailure {
            let disposition: ProgressStoreAppendFailureDisposition = failure.bodyExecuted
                ? .durabilityIndeterminate
                : .noJournalRecordWriteAttempted
            if disposition == .durabilityIndeterminate {
                appendRequiresReconciliation = true
            }
            throw ProgressStoreAppendFailure(
                disposition: disposition,
                underlyingError: failure
            )
        }
    }

    /// Unsafe compatibility seam for crash-boundary tests. Shipping callers
    /// must checkpoint an exact `DurableJourneyCommit`.
    func checkpoint(_ state: JourneyState) throws {
        try withDirectoryTransaction {
            head = nil
            journalGeneration = nil
            try checkpointUnconditionallyWhileLocked(state)
        }
    }

    private func checkpointUnconditionallyWhileLocked(_ state: JourneyState) throws {
        guard !appendRequiresReconciliation else {
            throw ProgressStoreError.appendRequiresReconciliation
        }
        try ensureHead()
        let sequence = head?.sequence ?? 0
        let generation = UUID().uuidString.lowercased()
        let snapshot = SaveSnapshot(state: state)
        let material = SnapshotDigestMaterial(
            envelopeFormatVersion: Self.currentSnapshotEnvelopeVersion,
            sequence: sequence,
            journalGeneration: generation,
            snapshot: snapshot,
            lastEvent: nil
        )
        let record = SnapshotRecord(
            envelopeFormatVersion: Self.currentSnapshotEnvelopeVersion,
            sequence: sequence,
            journalGeneration: generation,
            snapshot: snapshot,
            lastEvent: nil,
            digest: try Self.digest(material)
        )
        let snapshotData = try Self.encoder.encode(record)

        // The generation switch is a two-stage transaction. Once the snapshot
        // replacement starts, the visible filesystem may already name the new
        // generation even if this call throws. Mutations therefore remain
        // locked until restore verifies and synchronizes the visible pair.
        appendRequiresReconciliation = true
        do {
            // The new generation in the snapshot makes the old journal
            // obsolete if power fails before the journal reset.
            try atomicReplacementOperation(snapshotData, snapshotFileURL)
            try atomicReplacementOperation(Data(), journalFileURL)
        } catch {
            throw ProgressStoreAppendFailure(
                disposition: .durabilityIndeterminate,
                underlyingError: error
            )
        }
        journalGeneration = generation
        head = (sequence, record.digest)
        appendRequiresReconciliation = false
        canonicalState = nil
        canonicalAnchor = nil
        canonicalLastTransition = nil
        canonicalReplayOrigin = nil
        restorationInitialState = nil
    }

    public func restore(initialState: JourneyState = .initial) throws -> JourneyRestoration {
        do {
            return try withDirectoryTransaction {
                try restoreWhileLocked(initialState: initialState)
            }
        } catch let failure as DirectoryTransactionFailure {
            appendRequiresReconciliation = true
            throw ProgressStoreAppendFailure(
                disposition: failure.bodyExecuted
                    ? .durabilityIndeterminate
                    : .noJournalRecordWriteAttempted,
                underlyingError: failure
            )
        }
    }

    private func restoreWhileLocked(initialState: JourneyState) throws -> JourneyRestoration {
        // A restore is the only operation allowed to clear an uncertain
        // mutation. Keep the lock engaged until every accepted visible file
        // has been verified and explicitly synchronized again.
        appendRequiresReconciliation = true
        try recoverInterruptedSaveMigrationIfPresent()
        try removeInterruptedTailIfPresent()
        let snapshot = try verifiedSnapshot()
        var state = snapshot?.snapshot.state ?? initialState
        let anchor = JournalAnchor(
            sequence: snapshot?.sequence ?? 0,
            digest: snapshot?.digest ?? Self.genesisDigest,
            generation: snapshot?.journalGeneration ?? Self.initialJournalGeneration
        )
        journalGeneration = anchor.generation
        try discardJournalFromAnotherGeneration(expected: anchor.generation)
        let records = try verifiedRecords(anchor: anchor)
        var acceptedAnchor = records.last.map {
            JournalAnchor(sequence: $0.sequence, digest: $0.digest, generation: $0.generation)
        } ?? anchor

        for record in records {
            reducer.reduce(state: &state, event: record.event)
        }
        let migration = try saveMigrationRegistry.migrate(
            SaveSnapshot(state: state),
            authorities: saveMigrationAuthorities
        )
        if migration.didMigrate {
            acceptedAnchor = try commitSaveMigration(
                migration.snapshot,
                sequence: acceptedAnchor.sequence,
                lastEvent: records.last?.event ?? snapshot?.lastEvent
            )
            state = migration.snapshot.state
        }
        head = (acceptedAnchor.sequence, acceptedAnchor.digest)
        journalGeneration = acceptedAnchor.generation
        try synchronizeAcceptedFiles()
        state.prepareForColdRestore()
        canonicalState = state
        canonicalAnchor = acceptedAnchor
        canonicalLastTransition = nil
        canonicalReplayOrigin = CanonicalReplayOrigin(anchor: acceptedAnchor, state: state)
        restorationInitialState = initialState
        appendRequiresReconciliation = false
        return JourneyRestoration(
            state: state,
            replayedEventCount: records.count,
            lastSequence: head?.sequence ?? anchor.sequence,
            didCommitSaveMigration: migration.didMigrate
        )
    }

    /// Restores the exact pre-migration snapshot and journal bytes once, and
    /// only while disk still contains the exact post-migration save pair under
    /// the same active package-generation authority. Any later event or
    /// checkpoint makes this rollback stale instead of deleting progress.
    /// Package activation must already have selected the matching older
    /// package before the caller performs the next normal restore.
    public func rollbackToLastKnownGoodSave() throws {
        try withDirectoryTransaction {
            let rollback = try loadSaveMigrationRollback(
                at: migrationLastKnownGoodFileURL
            )
            guard rollback.migrationAuthoritySetSHA256
                == (try saveMigrationAuthoritySetSHA256()) else {
                throw ProgressStoreError.migrationRollbackAuthorityMismatch
            }
            guard try currentFileSHA256(snapshotFileURL)
                    == rollback.expectedMigratedSnapshotSHA256,
                  try currentFileSHA256(journalFileURL)
                    == rollback.expectedMigratedJournalSHA256 else {
                throw ProgressStoreError.migrationRollbackStale
            }

            appendRequiresReconciliation = true
            let rollbackData = try Self.encoder.encode(rollback)
            try Self.replaceAtomicallyAndSynchronize(
                rollbackData,
                at: migrationInFlightFileURL
            )
            do {
                try restoreSaveMigrationRollback(rollback)
                try removeMigrationControlFileIfPresent(
                    migrationLastKnownGoodFileURL
                )
                try removeMigrationControlFileIfPresent(migrationInFlightFileURL)
            } catch {
                // The durable in-flight record makes a partially restored pair
                // recoverable on the next normal restore.
                throw ProgressStoreError.migrationRollbackFailed
            }
            head = nil
            journalGeneration = nil
            canonicalState = nil
            canonicalAnchor = nil
            canonicalLastTransition = nil
            canonicalReplayOrigin = nil
            restorationInitialState = nil
            appendRequiresReconciliation = true
        }
    }

    private func commitSaveMigration(
        _ snapshot: SaveSnapshot,
        sequence: UInt64,
        lastEvent: JourneyEvent?
    ) throws -> JournalAnchor {
        guard snapshot.formatVersion == SaveSnapshot.currentFormatVersion,
              snapshot.state.stateSchemaVersion == JourneyState.currentStateSchemaVersion else {
            throw ProgressStoreError.unsupportedSnapshotVersion(snapshot.formatVersion)
        }
        let generation = UUID().uuidString.lowercased()
        let material = SnapshotDigestMaterial(
            envelopeFormatVersion: Self.currentSnapshotEnvelopeVersion,
            sequence: sequence,
            journalGeneration: generation,
            snapshot: snapshot,
            lastEvent: lastEvent
        )
        let record = SnapshotRecord(
            envelopeFormatVersion: Self.currentSnapshotEnvelopeVersion,
            sequence: sequence,
            journalGeneration: generation,
            snapshot: snapshot,
            lastEvent: lastEvent,
            digest: try Self.digest(material)
        )
        let snapshotData = try Self.encoder.encode(record)
        let journalData = Data()
        let rollback = try makeSaveMigrationRollback(
            expectedMigratedSnapshotData: snapshotData,
            expectedMigratedJournalData: journalData
        )
        let rollbackData = try Self.encoder.encode(rollback)
        try Self.replaceAtomicallyAndSynchronize(
            rollbackData,
            at: migrationLastKnownGoodFileURL
        )
        try Self.replaceAtomicallyAndSynchronize(
            rollbackData,
            at: migrationInFlightFileURL
        )

        do {
            try saveMigrationBoundaryOperation(.backupDurable)
            try atomicReplacementOperation(snapshotData, snapshotFileURL)
            try saveMigrationBoundaryOperation(.snapshotActivated)
            try atomicReplacementOperation(journalData, journalFileURL)
            try saveMigrationBoundaryOperation(.journalReset)

            guard try verifiedSnapshot()?.digest == record.digest else {
                throw ProgressStoreError.invalidSnapshot
            }
            try synchronizeAcceptedFiles()
            try removeMigrationControlFileIfPresent(migrationInFlightFileURL)
            return JournalAnchor(
                sequence: sequence,
                digest: record.digest,
                generation: generation
            )
        } catch {
            do {
                try restoreSaveMigrationRollback(rollback)
                try removeMigrationControlFileIfPresent(migrationInFlightFileURL)
            } catch {
                throw ProgressStoreError.migrationRollbackFailed
            }
            throw ProgressStoreError.migrationInterrupted
        }
    }

    private func makeSaveMigrationRollback(
        expectedMigratedSnapshotData: Data,
        expectedMigratedJournalData: Data
    ) throws -> SaveMigrationRollbackRecord {
        let snapshotBytes = FileManager.default.fileExists(atPath: snapshotFileURL.path)
            ? try Data(contentsOf: snapshotFileURL)
            : nil
        let journalBytes = FileManager.default.fileExists(atPath: journalFileURL.path)
            ? try Data(contentsOf: journalFileURL)
            : nil
        let expectedMigratedSnapshotSHA256 = Self.sha256(
            expectedMigratedSnapshotData
        )
        let expectedMigratedJournalSHA256 = Self.sha256(
            expectedMigratedJournalData
        )
        let migrationAuthoritySetSHA256 = try saveMigrationAuthoritySetSHA256()
        let material = SaveMigrationRollbackMaterial(
            formatVersion: Self.currentSaveMigrationRollbackVersion,
            snapshotBytes: snapshotBytes,
            journalBytes: journalBytes,
            expectedMigratedSnapshotSHA256: expectedMigratedSnapshotSHA256,
            expectedMigratedJournalSHA256: expectedMigratedJournalSHA256,
            migrationAuthoritySetSHA256: migrationAuthoritySetSHA256
        )
        return SaveMigrationRollbackRecord(
            formatVersion: material.formatVersion,
            snapshotBytes: snapshotBytes,
            journalBytes: journalBytes,
            expectedMigratedSnapshotSHA256: expectedMigratedSnapshotSHA256,
            expectedMigratedJournalSHA256: expectedMigratedJournalSHA256,
            migrationAuthoritySetSHA256: migrationAuthoritySetSHA256,
            digest: try Self.digest(material)
        )
    }

    private func recoverInterruptedSaveMigrationIfPresent() throws {
        guard FileManager.default.fileExists(atPath: migrationInFlightFileURL.path) else {
            return
        }
        let rollback = try loadSaveMigrationRollback(at: migrationInFlightFileURL)
        try restoreSaveMigrationRollback(rollback)
        try removeMigrationControlFileIfPresent(migrationInFlightFileURL)
    }

    private func loadSaveMigrationRollback(
        at url: URL
    ) throws -> SaveMigrationRollbackRecord {
        let record: SaveMigrationRollbackRecord
        do {
            record = try Self.decoder.decode(
                SaveMigrationRollbackRecord.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw ProgressStoreError.migrationRollbackTampered
        }
        let material = SaveMigrationRollbackMaterial(
            formatVersion: record.formatVersion,
            snapshotBytes: record.snapshotBytes,
            journalBytes: record.journalBytes,
            expectedMigratedSnapshotSHA256:
                record.expectedMigratedSnapshotSHA256,
            expectedMigratedJournalSHA256:
                record.expectedMigratedJournalSHA256,
            migrationAuthoritySetSHA256: record.migrationAuthoritySetSHA256
        )
        guard record.formatVersion == Self.currentSaveMigrationRollbackVersion,
              try Self.digest(material) == record.digest else {
            throw ProgressStoreError.migrationRollbackTampered
        }
        return record
    }

    private func restoreSaveMigrationRollback(
        _ rollback: SaveMigrationRollbackRecord
    ) throws {
        try restoreExactBytes(rollback.snapshotBytes, at: snapshotFileURL)
        try restoreExactBytes(rollback.journalBytes, at: journalFileURL)
    }

    private func restoreExactBytes(_ data: Data?, at url: URL) throws {
        if let data {
            try atomicReplacementOperation(data, url)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            try Self.synchronizeDirectory(directoryURL)
        }
    }

    private func currentFileSHA256(_ url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Self.sha256(Data("missing-file".utf8))
        }
        return Self.sha256(try Data(contentsOf: url))
    }

    private func saveMigrationAuthoritySetSHA256() throws -> String {
        let records = saveMigrationAuthorities
            .sorted { $0.packageID < $1.packageID }
            .map { authority in
                SaveMigrationAuthorityDigestRecord(
                    packageID: authority.packageID,
                    targetContentVersion: authority.targetContentVersion,
                    manifestDigest: authority.manifestDigest,
                    activeGeneration: authority.activeGeneration,
                    declarations: authority.declarations.sorted {
                        $0.id.utf8.lexicographicallyPrecedes($1.id.utf8)
                    }
                )
            }
        return try Self.digest(records)
    }

    private func removeMigrationControlFileIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
        try Self.synchronizeDirectory(directoryURL)
    }

    private func appendConditionallyWhileLocked(
        _ request: ConditionalJourneyAppendRequest
    ) throws -> UInt64 {
        guard !appendRequiresReconciliation else {
            throw ProgressStoreAppendFailure(
                disposition: .durabilityIndeterminate,
                underlyingError: ProgressStoreError.appendRequiresReconciliation
            )
        }
        guard let authoritativeState = canonicalState,
              let authoritativeAnchor = canonicalAnchor else {
            throw authorityMismatch(ProgressStoreError.canonicalAuthorityUnavailable)
        }

        let diskAuthority: ReloadedCanonicalAuthority
        do {
            diskAuthority = try loadCanonicalAuthority()
        } catch {
            throw authorityMismatch(error)
        }
        guard diskAuthority.anchor == authoritativeAnchor,
              diskAuthority.state == authoritativeState,
              request.expectedPreviousSequence == authoritativeAnchor.sequence else {
            throw authorityMismatch(ProgressStoreError.canonicalAuthorityMismatch)
        }
        guard request.expectedPreviousState == authoritativeState else {
            throw authorityMismatch(ProgressStoreError.conditionalPreviousStateMismatch)
        }

        let logicalBase = max(
            authoritativeState.lastLogicalTimeMillis,
            Int64(clamping: authoritativeAnchor.sequence)
        )
        guard logicalBase < Int64.max else {
            throw ProgressStoreAppendFailure(
                disposition: .noJournalRecordWriteAttempted,
                underlyingError: ProgressStoreError.sequenceExhausted
            )
        }
        let expectedTime = logicalBase + 1
        guard request.event.logicalTimeMillis == expectedTime else {
            throw authorityMismatch(
                ProgressStoreError.conditionalEventTimeMismatch(
                    expected: expectedTime,
                    actual: request.event.logicalTimeMillis
                )
            )
        }

        var independentlyDerived = authoritativeState
        let effects = reducer.reduce(state: &independentlyDerived, event: request.event)
        guard !effects.contains(where: { effect in
            if case .rejected = effect { return true }
            return false
        }) else {
            throw authorityMismatch(ProgressStoreError.conditionalTransitionRejected)
        }
        guard independentlyDerived == request.expectedCandidateState else {
            throw authorityMismatch(ProgressStoreError.conditionalCandidateStateMismatch)
        }

        let sequence = try Self.nextSequence(after: authoritativeAnchor.sequence)
        let material = JournalDigestMaterial(
            formatVersion: Self.currentJournalFormatVersion,
            generation: authoritativeAnchor.generation,
            sequence: sequence,
            previousDigest: authoritativeAnchor.digest,
            event: request.event
        )
        let digest = try Self.digest(material)
        let record = JournalRecord(
            formatVersion: Self.currentJournalFormatVersion,
            generation: authoritativeAnchor.generation,
            sequence: sequence,
            previousDigest: authoritativeAnchor.digest,
            event: request.event,
            digest: digest
        )
        var data = try Self.encoder.encode(record)
        data.append(0x0A)

        do {
            try journalAppendOperation(data, journalFileURL)
        } catch let failure as ProgressStoreAppendFailure {
            if failure.disposition == .durabilityIndeterminate {
                appendRequiresReconciliation = true
            }
            throw failure
        } catch {
            appendRequiresReconciliation = true
            throw ProgressStoreAppendFailure(
                disposition: .durabilityIndeterminate,
                underlyingError: error
            )
        }

        let resultingAnchor = JournalAnchor(
            sequence: sequence,
            digest: digest,
            generation: authoritativeAnchor.generation
        )
        head = (sequence, digest)
        journalGeneration = authoritativeAnchor.generation
        canonicalState = independentlyDerived
        canonicalAnchor = resultingAnchor
        canonicalLastTransition = CanonicalTransition(
            previousState: authoritativeState,
            event: request.event,
            candidateState: independentlyDerived
        )
        return sequence
    }

    private func checkpointConditionallyWhileLocked(
        _ commit: DurableJourneyCommit
    ) throws {
        guard !appendRequiresReconciliation else {
            throw ProgressStoreAppendFailure(
                disposition: .durabilityIndeterminate,
                underlyingError: ProgressStoreError.appendRequiresReconciliation
            )
        }
        guard let authoritativeState = canonicalState,
              let authoritativeAnchor = canonicalAnchor,
              let transition = canonicalLastTransition else {
            throw authorityMismatch(ProgressStoreError.canonicalAuthorityUnavailable)
        }

        let diskAuthority: ReloadedCanonicalAuthority
        do {
            diskAuthority = try loadCanonicalAuthority()
        } catch {
            throw authorityMismatch(error)
        }
        guard diskAuthority.anchor == authoritativeAnchor,
              diskAuthority.state == authoritativeState,
              diskAuthority.lastEvent == transition.event else {
            throw authorityMismatch(ProgressStoreError.canonicalAuthorityMismatch)
        }
        guard commit.sequence == authoritativeAnchor.sequence,
              commit.event == transition.event,
              commit.state == authoritativeState,
              transition.candidateState == authoritativeState else {
            throw authorityMismatch(ProgressStoreError.conditionalCheckpointReceiptMismatch)
        }

        var independentlyDerived = transition.previousState
        let independentlyDerivedEffects = reducer.reduce(
            state: &independentlyDerived,
            event: transition.event
        )
        guard independentlyDerived == authoritativeState,
              independentlyDerivedEffects == commit.effects else {
            throw authorityMismatch(ProgressStoreError.conditionalCheckpointReceiptMismatch)
        }

        let generation = UUID().uuidString.lowercased()
        let snapshot = SaveSnapshot(state: authoritativeState)
        let material = SnapshotDigestMaterial(
            envelopeFormatVersion: Self.currentSnapshotEnvelopeVersion,
            sequence: authoritativeAnchor.sequence,
            journalGeneration: generation,
            snapshot: snapshot,
            lastEvent: transition.event
        )
        let record = SnapshotRecord(
            envelopeFormatVersion: Self.currentSnapshotEnvelopeVersion,
            sequence: authoritativeAnchor.sequence,
            journalGeneration: generation,
            snapshot: snapshot,
            lastEvent: transition.event,
            digest: try Self.digest(material)
        )
        let snapshotData = try Self.encoder.encode(record)

        appendRequiresReconciliation = true
        do {
            try atomicReplacementOperation(snapshotData, snapshotFileURL)
            try atomicReplacementOperation(Data(), journalFileURL)
        } catch {
            throw ProgressStoreAppendFailure(
                disposition: .durabilityIndeterminate,
                underlyingError: error
            )
        }

        let resultingAnchor = JournalAnchor(
            sequence: authoritativeAnchor.sequence,
            digest: record.digest,
            generation: generation
        )
        journalGeneration = generation
        head = (resultingAnchor.sequence, resultingAnchor.digest)
        canonicalAnchor = resultingAnchor
        canonicalReplayOrigin = CanonicalReplayOrigin(
            anchor: resultingAnchor,
            state: authoritativeState
        )
        appendRequiresReconciliation = false
    }

    private func loadCanonicalAuthority() throws -> ReloadedCanonicalAuthority {
        guard let origin = canonicalReplayOrigin,
              let initialState = restorationInitialState else {
            throw ProgressStoreError.canonicalAuthorityUnavailable
        }
        if FileManager.default.fileExists(atPath: journalFileURL.path) {
            let journal = try Data(contentsOf: journalFileURL)
            guard journal.isEmpty || journal.last == 0x0A else {
                throw ProgressStoreError.appendRequiresReconciliation
            }
        }
        let snapshot = try verifiedSnapshot()
        let anchor = JournalAnchor(
            sequence: snapshot?.sequence ?? 0,
            digest: snapshot?.digest ?? Self.genesisDigest,
            generation: snapshot?.journalGeneration ?? Self.initialJournalGeneration
        )
        let records = try verifiedRecords(anchor: anchor)
        let acceptedAnchor = records.last.map {
            JournalAnchor(sequence: $0.sequence, digest: $0.digest, generation: $0.generation)
        } ?? anchor

        var state: JourneyState
        let recordsToReplay: ArraySlice<JournalRecord>
        if origin.anchor == anchor {
            state = origin.state
            recordsToReplay = records[records.startIndex...]
        } else if let originIndex = records.firstIndex(where: { record in
            record.sequence == origin.anchor.sequence
                && record.digest == origin.anchor.digest
                && record.generation == origin.anchor.generation
        }) {
            state = origin.state
            recordsToReplay = records[records.index(after: originIndex)...]
        } else {
            // This branch represents an authority which changed outside this
            // store instance (normally another actor/process checkpoint). It
            // is still fully decoded from disk so the caller can compare the
            // complete state before rejecting its stale local authority.
            state = snapshot?.snapshot.state ?? initialState
            recordsToReplay = records[records.startIndex...]
        }
        for record in recordsToReplay {
            reducer.reduce(state: &state, event: record.event)
        }
        return ReloadedCanonicalAuthority(
            anchor: acceptedAnchor,
            state: state,
            lastEvent: records.last?.event ?? snapshot?.lastEvent
        )
    }

    private func authorityMismatch(_ error: any Error) -> ProgressStoreAppendFailure {
        ProgressStoreAppendFailure(
            disposition: .canonicalAuthorityMismatch,
            underlyingError: error
        )
    }

    private func ensureHead() throws {
        guard head == nil else { return }
        try removeInterruptedTailIfPresent()
        let snapshot = try verifiedSnapshot()
        let anchor = JournalAnchor(
            sequence: snapshot?.sequence ?? 0,
            digest: snapshot?.digest ?? Self.genesisDigest,
            generation: snapshot?.journalGeneration ?? Self.initialJournalGeneration
        )
        journalGeneration = anchor.generation
        try discardJournalFromAnotherGeneration(expected: anchor.generation)
        let records = try verifiedRecords(anchor: anchor)
        head = records.last.map { ($0.sequence, $0.digest) } ?? (anchor.sequence, anchor.digest)
    }

    private func verifiedSnapshot() throws -> SnapshotRecord? {
        guard FileManager.default.fileExists(atPath: snapshotFileURL.path) else { return nil }
        let record: SnapshotRecord
        do {
            record = try Self.decoder.decode(
                SnapshotRecord.self,
                from: Data(contentsOf: snapshotFileURL)
            )
        } catch {
            throw ProgressStoreError.invalidSnapshot
        }
        guard record.envelopeFormatVersion == Self.currentSnapshotEnvelopeVersion else {
            throw ProgressStoreError.invalidSnapshot
        }
        guard record.snapshot.formatVersion == SaveSnapshot.currentFormatVersion else {
            throw ProgressStoreError.unsupportedSnapshotVersion(record.snapshot.formatVersion)
        }
        let material = SnapshotDigestMaterial(
            envelopeFormatVersion: record.envelopeFormatVersion,
            sequence: record.sequence,
            journalGeneration: record.journalGeneration,
            snapshot: record.snapshot,
            lastEvent: record.lastEvent
        )
        guard try Self.digest(material) == record.digest else {
            throw ProgressStoreError.invalidSnapshot
        }
        return record
    }

    private func discardJournalFromAnotherGeneration(expected: String) throws {
        guard FileManager.default.fileExists(atPath: journalFileURL.path) else { return }
        let data = try Data(contentsOf: journalFileURL)
        guard let firstLine = data.split(separator: 0x0A, omittingEmptySubsequences: true).first else {
            return
        }
        guard let header = try? Self.decoder.decode(JournalHeader.self, from: Data(firstLine)) else {
            throw ProgressStoreError.invalidJournalRecord(1)
        }
        if header.generation != expected {
            try replaceDuringReconciliation(Data(), at: journalFileURL)
        }
    }

    private func removeInterruptedTailIfPresent() throws {
        guard FileManager.default.fileExists(atPath: journalFileURL.path) else { return }
        let data = try Data(contentsOf: journalFileURL)
        guard !data.isEmpty, data.last != 0x0A else { return }
        let completePrefix: Data
        if let newline = data.lastIndex(of: 0x0A) {
            completePrefix = Data(data.prefix(through: newline))
        } else {
            completePrefix = Data()
        }
        try replaceDuringReconciliation(completePrefix, at: journalFileURL)
    }

    private func verifiedRecords(anchor: JournalAnchor) throws -> [JournalRecord] {
        guard FileManager.default.fileExists(atPath: journalFileURL.path) else { return [] }
        let data = try Data(contentsOf: journalFileURL)
        guard !data.isEmpty else { return [] }

        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        var result: [JournalRecord] = []
        var previousSequence = anchor.sequence
        var previousDigest = anchor.digest
        for (index, line) in lines.enumerated() {
            let expectedSequence = try Self.nextSequence(after: previousSequence)
            guard let record = try? Self.decoder.decode(JournalRecord.self, from: Data(line)) else {
                throw ProgressStoreError.invalidJournalRecord(index + 1)
            }
            guard record.formatVersion == Self.currentJournalFormatVersion else {
                throw ProgressStoreError.unsupportedJournalVersion(record.formatVersion)
            }
            guard record.generation == anchor.generation else {
                throw ProgressStoreError.invalidJournalRecord(index + 1)
            }
            guard record.sequence == expectedSequence else {
                throw ProgressStoreError.brokenSequence(
                    expected: expectedSequence,
                    actual: record.sequence
                )
            }
            guard record.previousDigest == previousDigest else {
                throw ProgressStoreError.brokenDigest(sequence: record.sequence)
            }
            let material = JournalDigestMaterial(
                formatVersion: record.formatVersion,
                generation: record.generation,
                sequence: record.sequence,
                previousDigest: record.previousDigest,
                event: record.event
            )
            guard try Self.digest(material) == record.digest else {
                throw ProgressStoreError.brokenDigest(sequence: record.sequence)
            }
            result.append(record)
            previousSequence = record.sequence
            previousDigest = record.digest
        }
        return result
    }

    private func replaceDuringReconciliation(_ data: Data, at url: URL) throws {
        do {
            try atomicReplacementOperation(data, url)
        } catch {
            appendRequiresReconciliation = true
            throw ProgressStoreAppendFailure(
                disposition: .durabilityIndeterminate,
                underlyingError: error
            )
        }
    }

    private func synchronizeAcceptedFiles() throws {
        do {
            if FileManager.default.fileExists(atPath: snapshotFileURL.path) {
                try journalReconciliationOperation(snapshotFileURL)
            }
            if FileManager.default.fileExists(atPath: journalFileURL.path) {
                try journalReconciliationOperation(journalFileURL)
            }
            try Self.synchronizeDirectory(directoryURL)
        } catch {
            appendRequiresReconciliation = true
            throw ProgressStoreAppendFailure(
                disposition: .durabilityIndeterminate,
                underlyingError: error
            )
        }
    }

    private struct DirectoryTransactionFailure: Error, Sendable {
        let operation: String
        let code: Int32
        let bodyExecuted: Bool
    }

    /// A stable lockfile is never replaced, unlike the snapshot and journal.
    /// `flock` serialises separate actors and separate cooperating processes;
    /// a process crash releases the advisory lock automatically.
    private func withDirectoryTransaction<Result>(
        _ body: () throws -> Result
    ) throws -> Result {
        let descriptor = lockFileURL.path.withCString { path in
            Darwin.open(
                path,
                O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw DirectoryTransactionFailure(
                operation: "open progress lock",
                code: errno,
                bodyExecuted: false
            )
        }

        var lockResult: Int32
        repeat {
            lockResult = flock(descriptor, LOCK_EX)
        } while lockResult != 0 && errno == EINTR
        guard lockResult == 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            throw DirectoryTransactionFailure(
                operation: "acquire progress lock",
                code: code,
                bodyExecuted: false
            )
        }

        let result: Swift.Result<Result, any Error>
        do {
            result = .success(try body())
        } catch {
            result = .failure(error)
        }

        var unlockResult: Int32
        repeat {
            unlockResult = flock(descriptor, LOCK_UN)
        } while unlockResult != 0 && errno == EINTR
        let unlockCode = unlockResult == 0 ? 0 : errno
        let closeResult = Darwin.close(descriptor)
        let closeCode = closeResult == 0 ? 0 : errno

        guard unlockResult == 0 else {
            throw DirectoryTransactionFailure(
                operation: "release progress lock",
                code: unlockCode,
                bodyExecuted: true
            )
        }
        guard closeResult == 0 else {
            throw DirectoryTransactionFailure(
                operation: "close progress lock",
                code: closeCode,
                bodyExecuted: true
            )
        }
        return try result.get()
    }

    private static func synchronizeJournal(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    private static func appendSynchronously(_ data: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try replaceAtomicallyAndSynchronize(Data(), at: url)
            } catch {
                // Even an empty-file replacement may have changed the
                // directory entry before reporting failure.
                throw ProgressStoreAppendFailure(
                    disposition: .durabilityIndeterminate,
                    underlyingError: error
                )
            }
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            throw ProgressStoreAppendFailure(
                disposition: .noJournalRecordWriteAttempted,
                underlyingError: error
            )
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            // After the handle has opened, even a seek or write error is
            // treated as indeterminate. FileHandle does not prove that no
            // bytes reached the file before returning the error.
            throw ProgressStoreAppendFailure(
                disposition: .durabilityIndeterminate,
                underlyingError: error
            )
        }
    }

    /// Writes and synchronizes a sibling temporary file, atomically renames it
    /// over the destination, then synchronizes the parent directory. This is
    /// the strongest ordering exposed by the local POSIX filesystem. It cannot
    /// make guarantees beyond the filesystem and storage device's own fsync
    /// contract (for example, faulty firmware or hardware is outside it).
    private static func replaceAtomicallyAndSynchronize(_ data: Data, at url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).replacement",
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw POSIXFailure(operation: "create replacement", code: EIO)
        }
        let handle = try FileHandle(forWritingTo: temporaryURL)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        let renameResult = temporaryURL.path.withCString { sourcePath in
            url.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard renameResult == 0 else {
            throw POSIXFailure(operation: "rename replacement", code: errno)
        }
        try synchronizeDirectory(directory)
    }

    private static func synchronizeDirectory(_ directoryURL: URL) throws {
        let descriptor = directoryURL.path.withCString { path in
            Darwin.open(path, O_RDONLY)
        }
        guard descriptor >= 0 else {
            throw POSIXFailure(operation: "open parent directory", code: errno)
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXFailure(operation: "synchronize parent directory", code: errno)
        }
    }

    private struct POSIXFailure: Error, Sendable {
        let operation: String
        let code: Int32
    }

    private static let currentJournalFormatVersion = 1
    private static let currentSnapshotEnvelopeVersion = 1
    private static let currentSaveMigrationRollbackVersion = 2
    private static let initialJournalGeneration = "initial-v1"
    private static let genesisDigest = String(repeating: "0", count: 64)

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static func nextSequence(after sequence: UInt64) throws -> UInt64 {
        let (next, overflow) = sequence.addingReportingOverflow(1)
        guard !overflow else { throw ProgressStoreError.sequenceExhausted }
        return next
    }

    private static func digest<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return sha256(data)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
