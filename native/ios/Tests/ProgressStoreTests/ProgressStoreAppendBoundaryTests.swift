import Foundation
import JourneyDomain
@testable import ProgressStore
import XCTest

final class ProgressStoreAppendBoundaryTests: XCTestCase {
    func testKnownPreWriteFailureDoesNotLockStoreAndRetryUsesFirstSequence() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let appender = FailBeforeWriteOnceAppender()
        let store = try ProgressStore(
            directoryURL: directory,
            journalAppendOperation: { data, url in
                try appender.append(data, to: url)
            }
        )

        do {
            _ = try await store.append(Self.firstEvent)
            XCTFail("The first append must fail before attempting a journal-record write")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .noJournalRecordWriteAttempted)
            XCTAssertEqual(
                failure.underlyingError as? InjectedJournalAppendError,
                .beforeWrite
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.journalFileURL.path))
        XCTAssertEqual(appender.attemptCount, 1)

        let retrySequence = try await store.append(Self.firstEvent)
        XCTAssertEqual(retrySequence, 1)
        XCTAssertEqual(appender.attemptCount, 2)

        let reopened = try ProgressStore(directoryURL: directory)
        let restoration = try await reopened.restore()
        XCTAssertEqual(restoration.lastSequence, 1)
        XCTAssertEqual(restoration.replayedEventCount, 1)
        XCTAssertEqual(restoration.state.prologue.traceProgress, 0.25)
    }

    func testCompleteRecordThenSynchronizeFailureIsIndeterminateUntilRestore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let appender = FailAfterCompleteWriteOnceAppender()
        let reconciliation = RecordingJournalReconciliation()
        let store = try ProgressStore(
            directoryURL: directory,
            journalAppendOperation: { data, url in
                try appender.append(data, to: url)
            },
            journalReconciliationOperation: { url in
                try reconciliation.synchronize(url)
            }
        )

        do {
            _ = try await store.append(Self.firstEvent)
            XCTFail("Visible bytes without a successful synchronize must not return success")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? InjectedJournalAppendError,
                .synchronizeFailed
            )
        }

        let visibleUnsynchronisedRecord = try Data(contentsOf: store.journalFileURL)
        XCTAssertFalse(visibleUnsynchronisedRecord.isEmpty)
        XCTAssertEqual(visibleUnsynchronisedRecord.last, 0x0A)
        XCTAssertEqual(appender.attemptCount, 1)

        do {
            _ = try await store.append(Self.secondEvent)
            XCTFail("An indeterminate store must reject retry until it has reconciled the journal")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? ProgressStoreError,
                .appendRequiresReconciliation
            )
        }
        XCTAssertEqual(appender.attemptCount, 1)
        XCTAssertEqual(
            try Data(contentsOf: store.journalFileURL),
            visibleUnsynchronisedRecord
        )

        do {
            try await store.checkpoint(.initial)
            XCTFail("Checkpointing stale in-memory state could discard the indeterminate event")
        } catch {
            XCTAssertEqual(error as? ProgressStoreError, .appendRequiresReconciliation)
        }

        let reconciled = try await store.restore()
        XCTAssertEqual(reconciled.lastSequence, 1)
        XCTAssertEqual(reconciled.replayedEventCount, 1)
        XCTAssertEqual(reconciled.state.prologue.traceProgress, 0.25)
        XCTAssertEqual(reconciliation.attemptCount, 1)

        let nextSequence = try await store.append(Self.secondEvent)
        XCTAssertEqual(nextSequence, 2)
        XCTAssertEqual(appender.attemptCount, 2)

        let reopened = try ProgressStore(directoryURL: directory)
        let final = try await reopened.restore()
        XCTAssertEqual(final.lastSequence, 2)
        XCTAssertEqual(final.replayedEventCount, 2)
        XCTAssertEqual(final.state.prologue.traceProgress, 0.75)
    }

    func testPartialRecordFailureRemainsIndeterminateAndRestoreRemovesTornTail() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let appender = FailAfterPartialWriteOnceAppender()
        let reconciliation = RecordingJournalReconciliation()
        let store = try ProgressStore(
            directoryURL: directory,
            journalAppendOperation: { data, url in
                try appender.append(data, to: url)
            },
            journalReconciliationOperation: { url in
                try reconciliation.synchronize(url)
            }
        )

        do {
            _ = try await store.append(Self.firstEvent)
            XCTFail("A partial record must never be reported as an append success")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? InjectedJournalAppendError,
                .partialWriteFailed
            )
        }

        let tornTail = try Data(contentsOf: store.journalFileURL)
        XCTAssertFalse(tornTail.isEmpty)
        XCTAssertNotEqual(tornTail.last, 0x0A)

        do {
            _ = try await store.append(Self.secondEvent)
            XCTFail("Retry must not append behind a torn, indeterminate record")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? ProgressStoreError,
                .appendRequiresReconciliation
            )
        }
        XCTAssertEqual(appender.attemptCount, 1)
        XCTAssertEqual(try Data(contentsOf: store.journalFileURL), tornTail)

        let reconciled = try await store.restore()
        XCTAssertEqual(reconciled.lastSequence, 0)
        XCTAssertEqual(reconciled.replayedEventCount, 0)
        XCTAssertEqual(reconciled.state, .initial)
        XCTAssertTrue(try Data(contentsOf: store.journalFileURL).isEmpty)
        XCTAssertEqual(reconciliation.attemptCount, 1)

        let retrySequence = try await store.append(Self.firstEvent)
        XCTAssertEqual(retrySequence, 1)
        XCTAssertEqual(appender.attemptCount, 2)

        let reopened = try ProgressStore(directoryURL: directory)
        let final = try await reopened.restore()
        XCTAssertEqual(final.lastSequence, 1)
        XCTAssertEqual(final.replayedEventCount, 1)
        XCTAssertEqual(final.state.prologue.traceProgress, 0.25)
    }

    func testFailedReconciliationKeepsIndeterminateStoreLocked() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let appender = FailAfterCompleteWriteOnceAppender()
        let reconciliation = FailingJournalReconciliation()
        let store = try ProgressStore(
            directoryURL: directory,
            journalAppendOperation: { data, url in
                try appender.append(data, to: url)
            },
            journalReconciliationOperation: { url in
                try reconciliation.synchronize(url)
            }
        )

        do {
            _ = try await store.append(Self.firstEvent)
            XCTFail("The injected synchronize failure must remain indeterminate")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
        }

        do {
            _ = try await store.restore()
            XCTFail("Visible bytes cannot clear the lock when reconciliation also fails")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? InjectedJournalAppendError,
                .reconciliationSynchronizeFailed
            )
        }
        XCTAssertEqual(reconciliation.attemptCount, 1)

        do {
            _ = try await store.append(Self.secondEvent)
            XCTFail("A failed reconciliation must leave the mutation lock engaged")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .durabilityIndeterminate)
            XCTAssertEqual(
                failure.underlyingError as? ProgressStoreError,
                .appendRequiresReconciliation
            )
        }
        XCTAssertEqual(appender.attemptCount, 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-append-boundary-\(UUID().uuidString)", isDirectory: true)
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

private enum InjectedJournalAppendError: Error, Equatable, Sendable {
    case beforeWrite
    case synchronizeFailed
    case partialWriteFailed
    case reconciliationSynchronizeFailed
}

private final class FailBeforeWriteOnceAppender: @unchecked Sendable {
    private let attempts = AttemptCounter()

    var attemptCount: Int { attempts.value }

    func append(_ data: Data, to url: URL) throws {
        guard attempts.increment() > 1 else {
            throw ProgressStoreAppendFailure(
                disposition: .noJournalRecordWriteAttempted,
                underlyingError: InjectedJournalAppendError.beforeWrite
            )
        }
        try appendAndSynchronize(data, to: url)
    }
}

private final class FailAfterCompleteWriteOnceAppender: @unchecked Sendable {
    private let attempts = AttemptCounter()

    var attemptCount: Int { attempts.value }

    func append(_ data: Data, to url: URL) throws {
        guard attempts.increment() > 1 else {
            let handle = try journalHandle(for: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            // The record is visible, but the simulated synchronize operation
            // failed. Visibility is not treated as proof of durability.
            throw InjectedJournalAppendError.synchronizeFailed
        }
        try appendAndSynchronize(data, to: url)
    }
}

private final class FailAfterPartialWriteOnceAppender: @unchecked Sendable {
    private let attempts = AttemptCounter()

    var attemptCount: Int { attempts.value }

    func append(_ data: Data, to url: URL) throws {
        guard attempts.increment() > 1 else {
            let handle = try journalHandle(for: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data.prefix(max(1, data.count / 2)))
            throw InjectedJournalAppendError.partialWriteFailed
        }
        try appendAndSynchronize(data, to: url)
    }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

private final class RecordingJournalReconciliation: @unchecked Sendable {
    private let attempts = AttemptCounter()

    var attemptCount: Int { attempts.value }

    func synchronize(_ url: URL) throws {
        _ = attempts.increment()
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }
}

private final class FailingJournalReconciliation: @unchecked Sendable {
    private let attempts = AttemptCounter()

    var attemptCount: Int { attempts.value }

    func synchronize(_ url: URL) throws {
        _ = url
        _ = attempts.increment()
        throw InjectedJournalAppendError.reconciliationSynchronizeFailed
    }
}

private func journalHandle(for url: URL) throws -> FileHandle {
    if !FileManager.default.fileExists(atPath: url.path) {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    return try FileHandle(forWritingTo: url)
}

private func appendAndSynchronize(_ data: Data, to url: URL) throws {
    let handle = try journalHandle(for: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.synchronize()
}
