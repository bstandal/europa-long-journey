import Foundation
import JourneyDomain
@testable import ProgressStore
import XCTest

final class ProgressStoreAuthorityTests: XCTestCase {
    func testTwoCommittersSharingOneStoreRejectStaleAuthorityBeforeSecondWrite() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let restoration = try await store.restore()
        let first = committer(store: store, restoration: restoration)
        let stale = committer(store: store, restoration: restoration)

        let accepted = try await first.commit(.updatePrologueTrace(0.25))
        let journalAfterAccepted = try Data(contentsOf: store.journalFileURL)

        do {
            _ = try await stale.commit(.updatePrologueTrace(0.75))
            XCTFail("A second authority at the same sequence must not append")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .persistenceRestoreRequired
            )
        }

        XCTAssertEqual(accepted.sequence, 1)
        XCTAssertEqual(try Data(contentsOf: store.journalFileURL), journalAfterAccepted)
        let reopened = try ProgressStore(directoryURL: directory)
        let final = try await reopened.restore()
        XCTAssertEqual(final.lastSequence, 1)
        XCTAssertEqual(final.replayedEventCount, 1)
        XCTAssertEqual(final.state.prologue.traceProgress, 0.25)
        XCTAssertEqual(final.state.appliedEventCount, 1)
    }

    func testTwoStoresWithStaleCachedAuthorityCannotDuplicateSequence() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstStore = try ProgressStore(directoryURL: directory)
        let staleStore = try ProgressStore(directoryURL: directory)
        let firstRestoration = try await firstStore.restore()
        let staleRestoration = try await staleStore.restore()
        let first = committer(store: firstStore, restoration: firstRestoration)
        let stale = committer(store: staleStore, restoration: staleRestoration)

        _ = try await first.commit(.updatePrologueTrace(0.4))
        let bytesAfterFirst = try Data(contentsOf: firstStore.journalFileURL)
        do {
            _ = try await stale.commit(.updatePrologueTrace(0.8))
            XCTFail("The stale store must reload disk authority before writing")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .persistenceRestoreRequired
            )
        }

        XCTAssertEqual(try Data(contentsOf: firstStore.journalFileURL), bytesAfterFirst)
        let final = try await ProgressStore(directoryURL: directory).restore()
        XCTAssertEqual(final.lastSequence, 1)
        XCTAssertEqual(final.state.prologue.traceProgress, 0.4)
    }

    func testConcurrentConditionalAppendHasExactlyOneWinnerAndOneRecord() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstStore = try ProgressStore(directoryURL: directory)
        let secondStore = try ProgressStore(directoryURL: directory)
        let first = committer(store: firstStore, restoration: try await firstStore.restore())
        let second = committer(store: secondStore, restoration: try await secondStore.restore())

        let firstTask = Task { try await first.commit(.updatePrologueTrace(0.35)) }
        let secondTask = Task { try await second.commit(.updatePrologueTrace(0.65)) }
        let outcomes = [await firstTask.result, await secondTask.result]
        let commits = outcomes.compactMap { try? $0.get() }
        let failures = outcomes.compactMap { outcome -> DurableJourneyCommitterError? in
            guard case let .failure(error) = outcome else { return nil }
            return error as? DurableJourneyCommitterError
        }

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(failures, [.persistenceRestoreRequired])
        XCTAssertEqual(commits.first?.sequence, 1)
        let journal = try Data(contentsOf: firstStore.journalFileURL)
        XCTAssertEqual(journal.filter { $0 == 0x0A }.count, 1)

        let final = try await ProgressStore(directoryURL: directory).restore()
        XCTAssertEqual(final.lastSequence, 1)
        XCTAssertEqual(final.replayedEventCount, 1)
        XCTAssertEqual(final.state, commits.first?.state)
    }

    func testLaterCommitMakesEarlierCheckpointSafelyStaleWithoutCompaction() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let committer = committer(store: store, restoration: try await store.restore())

        let first = try await committer.commit(.updatePrologueTrace(0.25))
        let second = try await committer.commit(.updatePrologueTrace(0.75))
        let journalBeforeCheckpoint = try Data(contentsOf: store.journalFileURL)

        do {
            try await committer.checkpoint(first)
            XCTFail("A superseded checkpoint should be skipped before store mutation")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .staleCheckpoint(expected: first.revision, actual: second.revision)
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.snapshotFileURL.path))
        XCTAssertEqual(try Data(contentsOf: store.journalFileURL), journalBeforeCheckpoint)
        let final = try await ProgressStore(directoryURL: directory).restore()
        XCTAssertEqual(final.lastSequence, 2)
        XCTAssertEqual(final.state, second.state)
    }

    func testExactLatestCommitCheckpointsAndContinuesInTheNewGeneration() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let committer = committer(store: store, restoration: try await store.restore())

        let checkpointed = try await committer.commit(.updatePrologueTrace(0.25))
        try await committer.checkpoint(checkpointed)
        XCTAssertTrue(try Data(contentsOf: store.journalFileURL).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.snapshotFileURL.path))

        let continued = try await committer.commit(.updatePrologueTrace(0.75))
        XCTAssertEqual(continued.sequence, 2)
        let final = try await ProgressStore(directoryURL: directory).restore()
        XCTAssertEqual(final.lastSequence, 2)
        XCTAssertEqual(final.replayedEventCount, 1)
        XCTAssertEqual(final.state, continued.state)
    }

    func testForgedPreviousAndCandidateStatesRejectConditionalAppendBeforeWrite() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let restoration = try await store.restore()
        let event = JourneyEvent(logicalTimeMillis: 1, action: .updatePrologueTrace(0.25))
        var candidate = restoration.state
        _ = JourneyReducer().reduce(state: &candidate, event: event)

        var forgedPrevious = restoration.state
        forgedPrevious.prologue.traceProgress = 0.1
        let forgedPreviousRequest = ConditionalJourneyAppendRequest(
            expectedPreviousSequence: restoration.lastSequence,
            expectedPreviousState: forgedPrevious,
            event: event,
            expectedCandidateState: candidate
        )
        try await assertCanonicalAppendRejection(
            forgedPreviousRequest,
            expectedError: .conditionalPreviousStateMismatch,
            store: store
        )

        var forgedCandidate = candidate
        forgedCandidate.prologue.traceProgress = 0.9
        let forgedCandidateRequest = ConditionalJourneyAppendRequest(
            expectedPreviousSequence: restoration.lastSequence,
            expectedPreviousState: restoration.state,
            event: event,
            expectedCandidateState: forgedCandidate
        )
        try await assertCanonicalAppendRejection(
            forgedCandidateRequest,
            expectedError: .conditionalCandidateStateMismatch,
            store: store
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.journalFileURL.path))
        let final = try await ProgressStore(directoryURL: directory).restore()
        XCTAssertEqual(final.lastSequence, 0)
        XCTAssertEqual(final.state, .initial)
    }

    func testForgedCheckpointEventAndStateAreRejectedBeforeSnapshotMutation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let committer = committer(store: store, restoration: try await store.restore())
        let accepted = try await committer.commit(.updatePrologueTrace(0.25))
        let journal = try Data(contentsOf: store.journalFileURL)

        let forgedEvent = DurableJourneyCommit(
            sequence: accepted.sequence,
            revision: accepted.revision,
            event: JourneyEvent(
                logicalTimeMillis: accepted.event.logicalTimeMillis,
                action: .updatePrologueTrace(0.9)
            ),
            state: accepted.state,
            effects: accepted.effects
        )
        try await assertCanonicalCheckpointRejection(forgedEvent, store: store)

        var forgedState = accepted.state
        forgedState.prologue.traceProgress = 0.9
        let forgedCandidate = DurableJourneyCommit(
            sequence: accepted.sequence,
            revision: accepted.revision,
            event: accepted.event,
            state: forgedState,
            effects: accepted.effects
        )
        try await assertCanonicalCheckpointRejection(forgedCandidate, store: store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.snapshotFileURL.path))
        XCTAssertEqual(try Data(contentsOf: store.journalFileURL), journal)
        let final = try await ProgressStore(directoryURL: directory).restore()
        XCTAssertEqual(final.lastSequence, 1)
        XCTAssertEqual(final.state, accepted.state)
    }

    func testCompleteIndeterminateAppendIsReconciledByAnotherStoreBeforeContinuation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let appender = CompleteRecordThenFailAppender()
        let failedStore = try ProgressStore(
            directoryURL: directory,
            journalAppendOperation: { data, url in
                try appender.append(data, to: url)
            }
        )
        let failedAuthority = committer(
            store: failedStore,
            restoration: try await failedStore.restore()
        )

        do {
            _ = try await failedAuthority.commit(.updatePrologueTrace(0.25))
            XCTFail("The complete but unsynchronised append must remain indeterminate")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .persistenceRestoreRequired
            )
        }
        XCTAssertEqual(appender.attemptCount, 1)

        let recoveringStore = try ProgressStore(directoryURL: directory)
        let recovery = try await recoveringStore.restore()
        XCTAssertEqual(recovery.lastSequence, 1)
        XCTAssertEqual(recovery.state.prologue.traceProgress, 0.25)

        let recoveredAuthority = committer(store: recoveringStore, restoration: recovery)
        let continued = try await recoveredAuthority.commit(.updatePrologueTrace(0.75))
        XCTAssertEqual(continued.sequence, 2)

        let final = try await ProgressStore(directoryURL: directory).restore()
        XCTAssertEqual(final.lastSequence, 2)
        XCTAssertEqual(final.replayedEventCount, 2)
        XCTAssertEqual(final.state, continued.state)
        XCTAssertEqual(appender.attemptCount, 1)
    }

    private func committer(
        store: ProgressStore,
        restoration: JourneyRestoration
    ) -> DurableJourneyCommitter {
        DurableJourneyCommitter(
            restoredState: restoration.state,
            lastSequence: restoration.lastSequence,
            append: { request in try await store.append(request) },
            checkpoint: { commit in try await store.checkpoint(commit) }
        )
    }

    private func assertCanonicalCheckpointRejection(
        _ commit: DurableJourneyCommit,
        store: ProgressStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            try await store.checkpoint(commit)
            XCTFail("A forged checkpoint must not mutate the snapshot", file: file, line: line)
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(
                failure.disposition,
                .canonicalAuthorityMismatch,
                file: file,
                line: line
            )
            XCTAssertEqual(
                failure.underlyingError as? ProgressStoreError,
                .conditionalCheckpointReceiptMismatch,
                file: file,
                line: line
            )
        }
    }

    private func assertCanonicalAppendRejection(
        _ request: ConditionalJourneyAppendRequest,
        expectedError: ProgressStoreError,
        store: ProgressStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            _ = try await store.append(request)
            XCTFail("A forged append must not reach the journal", file: file, line: line)
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(
                failure.disposition,
                .canonicalAuthorityMismatch,
                file: file,
                line: line
            )
            XCTAssertEqual(
                failure.underlyingError as? ProgressStoreError,
                expectedError,
                file: file,
                line: line
            )
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "progress-authority-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

private enum CompleteRecordFailure: Error, Sendable {
    case afterWrite
}

private final class CompleteRecordThenFailAppender: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0

    var attemptCount: Int {
        lock.withLock { attempts }
    }

    func append(_ data: Data, to url: URL) throws {
        let shouldFail = lock.withLock {
            attempts += 1
            return attempts == 1
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        if shouldFail {
            throw CompleteRecordFailure.afterWrite
        }
        try handle.synchronize()
    }
}
