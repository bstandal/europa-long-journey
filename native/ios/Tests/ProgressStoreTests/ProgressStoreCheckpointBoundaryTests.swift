import CryptoKit
import Foundation
import JourneyDomain
@testable import ProgressStore
import XCTest

final class ProgressStoreCheckpointBoundaryTests: XCTestCase {
    func testSnapshotSuccessAndJournalResetFailureLocksMutationsUntilRestore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let replacement = CheckpointReplacementHarness(mode: .failJournalResetBeforeReplacement)
        let store = try ProgressStore(
            directoryURL: directory,
            journalAppendOperation: appendAndSynchronize,
            atomicReplacementOperation: { data, url in
                try replacement.replace(data, at: url)
            }
        )
        let reducer = JourneyReducer()
        var expected = JourneyState.initial

        let firstSequence = try await store.append(Self.firstEvent)
        XCTAssertEqual(firstSequence, 1)
        reducer.reduce(state: &expected, event: Self.firstEvent)

        do {
            try await store.checkpoint(expected)
            XCTFail("The injected journal reset must fail after the new snapshot is visible")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? CheckpointBoundaryError,
                .journalResetFailed
            )
        }
        XCTAssertEqual(replacement.attemptCount, 2)

        try await assertMutationLock(store)

        let restored = try await store.restore()
        XCTAssertEqual(restored.state, expected)
        XCTAssertEqual(restored.replayedEventCount, 0)
        XCTAssertEqual(restored.lastSequence, 1)

        let secondSequence = try await store.append(Self.secondEvent)
        XCTAssertEqual(secondSequence, 2)
        reducer.reduce(state: &expected, event: Self.secondEvent)
        expected.prepareForColdRestore()

        let reopened = try ProgressStore(directoryURL: directory)
        let final = try await reopened.restore()
        XCTAssertEqual(final.state, expected)
        XCTAssertEqual(final.replayedEventCount, 1)
        XCTAssertEqual(final.lastSequence, 2)
    }

    func testFailureAfterSnapshotReplacementRestoresTheVisibleGeneration() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let replacement = CheckpointReplacementHarness(mode: .failSnapshotAfterReplacement)
        let store = try ProgressStore(
            directoryURL: directory,
            journalAppendOperation: appendAndSynchronize,
            atomicReplacementOperation: { data, url in
                try replacement.replace(data, at: url)
            }
        )
        let reducer = JourneyReducer()
        var expected = JourneyState.initial

        _ = try await store.append(Self.firstEvent)
        reducer.reduce(state: &expected, event: Self.firstEvent)

        do {
            try await store.checkpoint(expected)
            XCTFail("A replacement that reports failure cannot publish checkpoint success")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? CheckpointBoundaryError,
                .snapshotReplacementFailed
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.snapshotFileURL.path))
        try await assertMutationLock(store)

        let restored = try await store.restore()
        XCTAssertEqual(restored.state, expected)
        XCTAssertEqual(restored.replayedEventCount, 0)
        XCTAssertEqual(restored.lastSequence, 1)
    }

    func testFailedCheckpointReconciliationLeavesStoreLocked() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let replacement = CheckpointReplacementHarness(mode: .failJournalResetBeforeReplacement)
        let reconciliation = AlwaysFailingReconciliation()
        let store = try ProgressStore(
            directoryURL: directory,
            journalAppendOperation: appendAndSynchronize,
            journalReconciliationOperation: { url in
                try reconciliation.synchronize(url)
            },
            atomicReplacementOperation: { data, url in
                try replacement.replace(data, at: url)
            }
        )
        let reducer = JourneyReducer()
        var expected = JourneyState.initial

        _ = try await store.append(Self.firstEvent)
        reducer.reduce(state: &expected, event: Self.firstEvent)
        do {
            try await store.checkpoint(expected)
            XCTFail("The checkpoint reset failure must engage reconciliation")
        } catch is ProgressStoreAppendFailure {}

        do {
            _ = try await store.restore()
            XCTFail("Restore must not unlock state whose accepted files could not be synchronized")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? CheckpointBoundaryError,
                .reconciliationFailed
            )
        }
        XCTAssertEqual(reconciliation.attemptCount, 1)
        try await assertMutationLock(store)

        do {
            _ = try await store.restore()
            XCTFail("A later failed reconciliation must leave the same lock engaged")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
        }
        XCTAssertEqual(reconciliation.attemptCount, 2)
    }

    func testPartialAppendAfterDurablePrefixRestoresPrefixAndReusesNextSequence() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let appender = FailSecondAppendAfterPartialWrite()
        let store = try ProgressStore(
            directoryURL: directory,
            journalAppendOperation: { data, url in
                try appender.append(data, to: url)
            }
        )

        let firstSequence = try await store.append(Self.firstEvent)
        XCTAssertEqual(firstSequence, 1)
        do {
            _ = try await store.append(Self.secondEvent)
            XCTFail("The second record must fail after a torn suffix is visible")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? CheckpointBoundaryError,
                .partialAppendFailed
            )
        }
        XCTAssertEqual(appender.attemptCount, 2)

        let restored = try await store.restore()
        XCTAssertEqual(restored.lastSequence, 1)
        XCTAssertEqual(restored.replayedEventCount, 1)
        XCTAssertEqual(restored.state.prologue.traceProgress, 0.25)

        let secondSequence = try await store.append(Self.secondEvent)
        XCTAssertEqual(secondSequence, 2)
        XCTAssertEqual(appender.attemptCount, 3)
        let reopened = try ProgressStore(directoryURL: directory)
        let final = try await reopened.restore()
        XCTAssertEqual(final.lastSequence, 2)
        XCTAssertEqual(final.replayedEventCount, 2)
        XCTAssertEqual(final.state.prologue.traceProgress, 0.75)
    }

    func testAppendAtMaximumSnapshotSequenceFailsBeforeWriting() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let generation = "maximum-sequence-generation"
        let store = try ProgressStore(directoryURL: directory)
        try writeBoundarySnapshot(
            state: .initial,
            sequence: UInt64.max,
            generation: generation,
            to: store.snapshotFileURL
        )
        try Data().write(to: store.journalFileURL, options: .atomic)
        let journalBefore = try Data(contentsOf: store.journalFileURL)

        do {
            _ = try await store.append(Self.firstEvent)
            XCTFail("No sequence exists after UInt64.max")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .noJournalRecordWriteAttempted)
            XCTAssertEqual(
                failure.underlyingError as? ProgressStoreError,
                .sequenceExhausted
            )
        }
        XCTAssertEqual(try Data(contentsOf: store.journalFileURL), journalBefore)
    }

    func testVerificationAtMaximumSnapshotSequenceFailsWithTypedExhaustion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let generation = "maximum-sequence-generation"
        let store = try ProgressStore(directoryURL: directory)
        try writeBoundarySnapshot(
            state: .initial,
            sequence: UInt64.max,
            generation: generation,
            to: store.snapshotFileURL
        )
        let decodableHeader = "{\"formatVersion\":1,\"generation\":\"\(generation)\",\"sequence\":0}\n"
        try Data(decodableHeader.utf8).write(to: store.journalFileURL, options: .atomic)

        do {
            _ = try await store.restore()
            XCTFail("A record cannot follow the maximum accepted sequence")
        } catch {
            XCTAssertEqual(error as? ProgressStoreError, .sequenceExhausted)
        }

        do {
            _ = try await store.append(Self.firstEvent)
            XCTFail("A failed restore must retain the reconciliation lock")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? ProgressStoreError,
                .appendRequiresReconciliation
            )
        }
    }

    private func assertMutationLock(
        _ store: ProgressStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            _ = try await store.append(Self.secondEvent)
            XCTFail("Append must remain blocked until a successful restore", file: file, line: line)
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate, file: file, line: line)
            XCTAssertEqual(
                failure.underlyingError as? ProgressStoreError,
                .appendRequiresReconciliation,
                file: file,
                line: line
            )
        }

        do {
            try await store.checkpoint(.initial)
            XCTFail("Checkpoint must remain blocked until a successful restore", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? ProgressStoreError,
                .appendRequiresReconciliation,
                file: file,
                line: line
            )
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "progress-checkpoint-boundary-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private static let firstEvent = JourneyEvent(
        logicalTimeMillis: 1,
        action: .updatePrologueTrace(0.25)
    )

    private static let secondEvent = JourneyEvent(
        logicalTimeMillis: 2,
        action: .updatePrologueTrace(0.75)
    )
}

private enum CheckpointBoundaryError: Error, Equatable, Sendable {
    case journalResetFailed
    case snapshotReplacementFailed
    case reconciliationFailed
    case partialAppendFailed
}

private final class CheckpointReplacementHarness: @unchecked Sendable {
    enum Mode: Sendable {
        case failJournalResetBeforeReplacement
        case failSnapshotAfterReplacement
    }

    private let lock = NSLock()
    private let mode: Mode
    private var attempts = 0

    init(mode: Mode) {
        self.mode = mode
    }

    var attemptCount: Int {
        lock.withLock { attempts }
    }

    func replace(_ data: Data, at url: URL) throws {
        let attempt = lock.withLock {
            attempts += 1
            return attempts
        }
        switch (mode, attempt) {
        case (.failSnapshotAfterReplacement, 1):
            try replaceAndSynchronizeForTest(data, at: url)
            throw CheckpointBoundaryError.snapshotReplacementFailed
        case (.failJournalResetBeforeReplacement, 2):
            throw CheckpointBoundaryError.journalResetFailed
        default:
            try replaceAndSynchronizeForTest(data, at: url)
        }
    }
}

private final class AlwaysFailingReconciliation: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0

    var attemptCount: Int {
        lock.withLock { attempts }
    }

    func synchronize(_ url: URL) throws {
        _ = url
        lock.withLock { attempts += 1 }
        throw CheckpointBoundaryError.reconciliationFailed
    }
}

private final class FailSecondAppendAfterPartialWrite: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0

    var attemptCount: Int {
        lock.withLock { attempts }
    }

    func append(_ data: Data, to url: URL) throws {
        let attempt = lock.withLock {
            attempts += 1
            return attempts
        }
        guard attempt == 2 else {
            try appendAndSynchronize(data, to: url)
            return
        }

        let handle = try writableJournalHandle(for: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data.prefix(max(1, data.count / 2)))
        throw CheckpointBoundaryError.partialAppendFailed
    }
}

private struct BoundarySnapshotRecord: Codable {
    let envelopeFormatVersion: Int
    let sequence: UInt64
    let journalGeneration: String
    let snapshot: SaveSnapshot
    let digest: String
}

private struct BoundarySnapshotDigestMaterial: Codable {
    let envelopeFormatVersion: Int
    let sequence: UInt64
    let journalGeneration: String
    let snapshot: SaveSnapshot
}

private func writeBoundarySnapshot(
    state: JourneyState,
    sequence: UInt64,
    generation: String,
    to url: URL
) throws {
    let snapshot = SaveSnapshot(state: state)
    let material = BoundarySnapshotDigestMaterial(
        envelopeFormatVersion: 1,
        sequence: sequence,
        journalGeneration: generation,
        snapshot: snapshot
    )
    let digest = SHA256.hash(data: try boundaryEncoder.encode(material))
        .map { String(format: "%02x", $0) }
        .joined()
    let record = BoundarySnapshotRecord(
        envelopeFormatVersion: 1,
        sequence: sequence,
        journalGeneration: generation,
        snapshot: snapshot,
        digest: digest
    )
    try boundaryEncoder.encode(record).write(to: url, options: .atomic)
}

private let boundaryEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
}()

private func replaceAndSynchronizeForTest(_ data: Data, at url: URL) throws {
    try data.write(to: url, options: .atomic)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.synchronize()
}

private func writableJournalHandle(for url: URL) throws -> FileHandle {
    if !FileManager.default.fileExists(atPath: url.path) {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    return try FileHandle(forWritingTo: url)
}

private func appendAndSynchronize(_ data: Data, to url: URL) throws {
    let handle = try writableJournalHandle(for: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.synchronize()
}
