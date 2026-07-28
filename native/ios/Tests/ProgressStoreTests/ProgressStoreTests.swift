import ContentKit
import ContentKitTestSupport
import Foundation
@testable import JourneyDomain
@testable import ProgressStore
import XCTest

final class ProgressStoreTests: XCTestCase {
    func testKillBeforeWriteAheadLeavesCausalStateUnpublishedAndUnrestored() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let gate = AppendBoundaryGate(store: store, pause: .beforeAppend)
        let committer = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in try await gate.append(request.event) }
        )

        let action = JourneyAction.completePrologue([Self.prologueEffect])
        async let pendingCommit = committer.commit(action)
        await gate.waitUntilPaused()

        let unpublishedState = await committer.currentCommittedState()
        XCTAssertEqual(unpublishedState, .initial)
        let killedStore = try ProgressStore(directoryURL: directory)
        let killedRestoration = try await killedStore.restore()
        XCTAssertEqual(killedRestoration.state, .initial)

        await gate.resume()
        let commit = try await pendingCommit
        XCTAssertEqual(commit.state.route, .world)
        XCTAssertEqual(commit.state.world.appliedEffectIDs, [Self.prologueEffect.id])
    }

    func testKillAfterWriteAheadBeforePublicationRestoresTheCausalTransition() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let gate = AppendBoundaryGate(store: store, pause: .afterAppend)
        let committer = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in try await gate.append(request.event) }
        )
        let beforeCommit = await committer.currentCommittedSnapshot()

        let action = JourneyAction.completePrologue([Self.prologueEffect])
        async let pendingCommit = committer.commit(action)
        await gate.waitUntilPaused()

        // The append closure has not returned, so no caller can publish the
        // transition and the committer still exposes its previous state.
        let unpublished = await committer.currentCommittedSnapshot()
        XCTAssertEqual(unpublished, beforeCommit)

        // A process killed at this exact boundary replays the synchronised
        // event and therefore cannot lose the historical consequence.
        let killedStore = try ProgressStore(directoryURL: directory)
        let restoration = try await killedStore.restore()
        XCTAssertEqual(restoration.state.route, .world)
        XCTAssertEqual(restoration.state.world.appliedEffectIDs, [Self.prologueEffect.id])

        await gate.resume()
        let commit = try await pendingCommit
        let published = await committer.currentCommittedSnapshot()
        XCTAssertEqual(commit.state, restoration.state)
        XCTAssertEqual(published.state, commit.state)
        XCTAssertEqual(published.logicalTimeMillis, commit.event.logicalTimeMillis)
        XCTAssertEqual(published.revision, commit.revision)
        XCTAssertTrue(commit.requiresCheckpoint)
    }

    func testKillAfterDocumentaryWriteAheadRestoresBeatAndWorldConsequenceTogether() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let gate = AppendBoundaryGate(store: store, pause: .afterAppend)
        let contract = Self.documentaryContract
        let initial = JourneyState(
            route: .chapter(contract.chapterID),
            activeChapter: ChapterSession(
                chapterID: contract.chapterID,
                packageID: contract.packageID,
                contentVersion: contract.contentVersion,
                arcID: contract.arcID,
                beatID: contract.beatID,
                beatCompletionContract: contract,
                sceneVisualSnapshot: SceneVisualSnapshot(
                    sceneID: "documentary-scene",
                    deterministicTick: 0
                )
            )
        )
        let committer = DurableJourneyCommitter(
            restoredState: initial,
            lastSequence: 0,
            append: { request in try await gate.append(request.event) }
        )

        async let pendingCommit = committer.commit(
            JourneyAction.completeDocumentaryBeat(contract)
        )
        await gate.waitUntilPaused()

        let unpublished = await committer.currentCommittedState()
        XCTAssertEqual(unpublished, initial)
        let killedStore = try ProgressStore(directoryURL: directory)
        let restoration = try await killedStore.restore(initialState: initial)
        XCTAssertEqual(restoration.replayedEventCount, 1)
        XCTAssertEqual(restoration.state.activeChapter?.completedBeatIDs, [contract.beatID])
        XCTAssertEqual(
            restoration.state.activeChapter?.completedBeatReviewRecords.map(\.beatID),
            [contract.beatID]
        )
        XCTAssertEqual(restoration.state.world.appliedEffects, contract.effects)

        await gate.resume()
        let commit = try await pendingCommit
        XCTAssertEqual(commit.state, restoration.state)
        XCTAssertEqual(commit.event.action, .completeDocumentaryBeat(contract))
    }

    func testKnownPreWriteAppendFailureCannotPublishOrConsumeLogicalTimeAndMayRetry() async throws {
        let append = FailOnceAppend()
        let committer = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in try await append.call(request.event) }
        )
        let beforeFailure = await committer.currentCommittedSnapshot()

        do {
            _ = try await committer.commit(.completePrologue([Self.prologueEffect]))
            XCTFail("The injected append failure should escape")
        } catch let failure as ProgressStoreAppendFailure {
            XCTAssertEqual(failure.disposition, .noJournalRecordWriteAttempted)
            XCTAssertEqual(
                failure.underlyingError as? InjectedPersistenceError,
                .appendFailed
            )
        }
        let afterFailure = await committer.currentCommittedSnapshot()
        XCTAssertEqual(afterFailure, beforeFailure)

        let retry = try await committer.commit(
            .completePrologue([Self.prologueEffect]),
            expectedRevision: beforeFailure.revision
        )
        XCTAssertEqual(retry.event.logicalTimeMillis, 1)
        XCTAssertEqual(retry.sequence, 1)
        XCTAssertEqual(retry.state.route, .world)
        XCTAssertEqual(retry.state.appliedEventCount, 1)
    }

    func testIndeterminateCompleteAppendPermanentlyRetiresOldCommitterAfterRestore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let appender = CompleteWriteThenFailOnceAppender()
        let store = try ProgressStore(
            directoryURL: directory,
            journalAppendOperation: { data, url in
                try appender.append(data, to: url)
            }
        )
        let initialRestoration = try await store.restore()
        let oldCommitter = DurableJourneyCommitter(
            restoredState: initialRestoration.state,
            lastSequence: initialRestoration.lastSequence,
            append: { request in try await store.append(request) }
        )
        let beforeFailure = await oldCommitter.currentCommittedSnapshot()

        do {
            _ = try await oldCommitter.commit(.updatePrologueTrace(0.25))
            XCTFail("An indeterminate append must retire its committer")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .persistenceRestoreRequired
            )
        }
        let afterFailure = await oldCommitter.currentCommittedSnapshot()
        XCTAssertEqual(afterFailure, beforeFailure)
        XCTAssertEqual(appender.attemptCount, 1)

        let restoration = try await store.restore()
        XCTAssertEqual(restoration.lastSequence, 1)
        XCTAssertEqual(restoration.replayedEventCount, 1)
        XCTAssertEqual(restoration.state.prologue.traceProgress, 0.25)

        do {
            _ = try await oldCommitter.commit(.updatePrologueTrace(0.25))
            XCTFail("Restoring the store must never revive the pre-failure committer")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .persistenceRestoreRequired
            )
        }
        XCTAssertEqual(appender.attemptCount, 1)

        let replacement = DurableJourneyCommitter(
            restoredState: restoration.state,
            lastSequence: restoration.lastSequence,
            append: { request in try await store.append(request) }
        )
        let continued = try await replacement.commit(.updatePrologueTrace(0.75))
        XCTAssertEqual(continued.sequence, 2)
        XCTAssertEqual(continued.event.logicalTimeMillis, 2)
        XCTAssertEqual(continued.state.prologue.traceProgress, 0.75)
        XCTAssertEqual(appender.attemptCount, 2)
    }

    func testUnexpectedReturnedSequenceRetiresCommitterWithoutPublishingCandidate() async throws {
        let append = WrongSequenceAppend(returnedSequence: 7)
        let committer = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in await append.call(request.event) }
        )
        let before = await committer.currentCommittedSnapshot()

        do {
            _ = try await committer.commit(.updatePrologueTrace(0.25))
            XCTFail("A sequence mismatch cannot be published or retried")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .unexpectedAppendSequence(expected: 1, actual: 7)
            )
        }
        let afterMismatch = await committer.currentCommittedSnapshot()
        let mismatchAppendCount = await append.callCount()
        XCTAssertEqual(afterMismatch, before)
        XCTAssertEqual(mismatchAppendCount, 1)

        do {
            _ = try await committer.commit(.updatePrologueTrace(0.75))
            XCTFail("The mismatched append permanently retires this committer")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .persistenceRestoreRequired
            )
        }
        let finalAppendCount = await append.callCount()
        XCTAssertEqual(finalAppendCount, 1)
    }

    func testCancellationAfterAppendAdmissionPoisonsAuthorityAndRejectsQueuedCaller() async throws {
        let append = CancellationBlockingAppend()
        let committer = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in try await append.call(request.event) }
        )
        let first = Task {
            try await committer.commit(.updatePrologueTrace(0.25))
        }
        await append.waitUntilEntered()
        let queued = Task {
            try await committer.commit(.updatePrologueTrace(0.75))
        }
        for _ in 0 ..< 10 { await Task.yield() }

        first.cancel()
        await append.release()

        for task in [first, queued] {
            do {
                _ = try await task.value
                XCTFail("Neither an indeterminate caller nor its queued successor may publish")
            } catch {
                XCTAssertEqual(
                    error as? DurableJourneyCommitterError,
                    .persistenceRestoreRequired
                )
            }
        }
        let appendCount = await append.callCount()
        let state = await committer.currentCommittedState()
        XCTAssertEqual(appendCount, 1)
        XCTAssertEqual(state, .initial)
    }

    func testRejectedPreflightNeverAppendsAdvancesSequenceOrChangesState() async throws {
        let append = RecordingAppend()
        let committer = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in await append.call(request.event) }
        )

        do {
            _ = try await committer.commit(
                .recordChapterVisit(
                    chapterID: "orphan-chapter",
                    atEpochMillis: 1
                )
            )
            XCTFail("A rejected reducer preflight must not cross the journal boundary")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .rejectedTransition(
                    "A chapter visit requires a saved chapter session and valid time"
                )
            )
        }

        let rejectedAppendCount = await append.callCount()
        let rejectedEvents = await append.events()
        let stateAfterRejection = await committer.currentCommittedState()
        let timeAfterRejection = await committer.currentLogicalTimeMillis()
        XCTAssertEqual(rejectedAppendCount, 0)
        XCTAssertEqual(rejectedEvents, [])
        XCTAssertEqual(stateAfterRejection, .initial)
        XCTAssertEqual(timeAfterRejection, 0)

        let firstAccepted = try await committer.commit(.updatePrologueTrace(0.25))
        XCTAssertEqual(firstAccepted.sequence, 1)
        XCTAssertEqual(firstAccepted.event.logicalTimeMillis, 1)
        XCTAssertEqual(firstAccepted.state.appliedEventCount, 1)
        let acceptedAppendCount = await append.callCount()
        XCTAssertEqual(acceptedAppendCount, 1)
    }

    func testPrematureAuthoredArcCompletionNeverCrossesTheJournalBoundary() async throws {
        let append = RecordingAppend()
        let initial = JourneyState(
            route: .chapter("first-farmers"),
            activeChapter: ChapterSession(
                chapterID: "first-farmers",
                packageID: "essential",
                contentVersion: SchemaVersion(major: 1),
                arcID: "first-farmers-arc-02",
                beatID: "harvest-beat",
                beatCompletionContract: Self.sceneBeatContract,
                sceneVisualSnapshot: SceneVisualSnapshot(
                    sceneID: "harvest-scene",
                    deterministicTick: 0
                )
            )
        )
        let committer = DurableJourneyCommitter(
            restoredState: initial,
            lastSequence: 0,
            append: { request in await append.call(request.event) }
        )

        do {
            _ = try await committer.commit(
                .completeAuthoredArc(Self.twoBeatArcCompletionContract)
            )
            XCTFail("An incomplete authored arc must fail before append")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .rejectedTransition(
                    "Arc completion did not match its full authored beat inventory"
                )
            )
        }

        let appendCount = await append.callCount()
        let committed = await committer.currentCommittedState()
        let logicalTime = await committer.currentLogicalTimeMillis()
        XCTAssertEqual(appendCount, 0)
        XCTAssertEqual(committed, initial)
        XCTAssertEqual(logicalTime, 0)
    }

    func testConcurrentCausalRequestsRemainStrictlyOrderedAcrossSuspendingAppends() async throws {
        let append = OrderedAppend()
        let committer = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in await append.call(request.event) }
        )

        async let first = committer.commit(.updatePrologueTrace(0.4))
        async let second = committer.commit(.updatePrologueTrace(0.8))
        let firstCommit = try await first
        let secondCommit = try await second
        let commits = [firstCommit, secondCommit].sorted { $0.sequence < $1.sequence }

        XCTAssertEqual(commits.map(\.sequence), [1, 2])
        XCTAssertEqual(commits.map(\.event.logicalTimeMillis), [1, 2])
        XCTAssertEqual(commits.last?.state.prologue.traceProgress, 0.8)
        let committedState = await committer.currentCommittedState()
        XCTAssertEqual(committedState, commits.last?.state)
    }

    func testAtomicSnapshotAndReturnedRevisionSupportChainedConditionalCommits() async throws {
        let append = RecordingAppend()
        let reducer = JourneyReducer()
        var restoredState = JourneyState.initial
        reducer.reduce(
            state: &restoredState,
            event: JourneyEvent(
                logicalTimeMillis: 41,
                action: .updatePrologueTrace(0.1)
            )
        )
        let committer = DurableJourneyCommitter(
            restoredState: restoredState,
            lastSequence: 0,
            append: { request in await append.call(request.event) }
        )

        let initial = await committer.currentCommittedSnapshot()
        XCTAssertEqual(initial.state, restoredState)
        XCTAssertEqual(initial.logicalTimeMillis, 41)

        let first = try await committer.commit(
            .updatePrologueTrace(0.4),
            expectedRevision: initial.revision
        )
        XCTAssertEqual(first.event.logicalTimeMillis, 42)
        XCTAssertNotEqual(first.revision, initial.revision)

        let second = try await committer.commit(
            .updatePrologueTrace(0.8),
            expectedRevision: first.revision
        )
        let final = await committer.currentCommittedSnapshot()
        XCTAssertEqual(second.event.logicalTimeMillis, 43)
        XCTAssertNotEqual(second.revision, first.revision)
        XCTAssertEqual(final.state, second.state)
        XCTAssertEqual(final.logicalTimeMillis, second.event.logicalTimeMillis)
        XCTAssertEqual(final.revision, second.revision)
        let appendCount = await append.callCount()
        XCTAssertEqual(appendCount, 2)
    }

    func testRevisionOverflowRejectsBeforeReducerAndAppend() async throws {
        let append = RecordingAppend()
        let committer = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: UInt64.max,
            append: { request in await append.call(request.event) }
        )
        let before = await committer.currentCommittedSnapshot()

        do {
            _ = try await committer.commit(.updatePrologueTrace(0.5))
            XCTFail("An exhausted revision cannot wrap")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .revisionExhausted
            )
        }

        let after = await committer.currentCommittedSnapshot()
        let appendCount = await append.callCount()
        XCTAssertEqual(after, before)
        XCTAssertEqual(appendCount, 0)
    }

    func testStaleRevisionFailsBeforeReducerAndProducesNoExtraAppend() async throws {
        let append = RecordingAppend()
        let committer = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in await append.call(request.event) }
        )
        let preparedAgainst = await committer.currentCommittedSnapshot()
        let accepted = try await committer.commit(
            .updatePrologueTrace(0.5),
            expectedRevision: preparedAgainst.revision
        )

        do {
            _ = try await committer.commit(
                .recordChapterVisit(chapterID: "orphan-chapter", atEpochMillis: 1),
                expectedRevision: preparedAgainst.revision
            )
            XCTFail("A stale revision must fail before reducer preflight")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .staleRevision(
                    expected: preparedAgainst.revision,
                    actual: accepted.revision
                )
            )
        }

        let appendCount = await append.callCount()
        let final = await committer.currentCommittedSnapshot()
        XCTAssertEqual(appendCount, 1)
        XCTAssertEqual(final.state, accepted.state)
        XCTAssertEqual(final.logicalTimeMillis, accepted.event.logicalTimeMillis)
        XCTAssertEqual(final.revision, accepted.revision)
    }

    func testConcurrentDriftMakesQueuedConditionalCommitStaleBeforeSecondAppend() async throws {
        let append = BlockingRecordingAppend()
        let committer = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in await append.call(request.event) }
        )
        let sharedSnapshot = await committer.currentCommittedSnapshot()

        let firstTask = Task {
            try await committer.commit(
                .updatePrologueTrace(0.4),
                expectedRevision: sharedSnapshot.revision
            )
        }
        await append.waitUntilFirstAppendStarts()
        let driftingTask = Task {
            try await committer.commit(
                .updatePrologueTrace(0.8),
                expectedRevision: sharedSnapshot.revision
            )
        }
        await Task.yield()
        let countWhileFirstAppendIsBlocked = await append.callCount()
        XCTAssertEqual(countWhileFirstAppendIsBlocked, 1)

        await append.resumeFirstAppend()
        let first = try await firstTask.value
        do {
            _ = try await driftingTask.value
            XCTFail("The queued caller must detect the commit that won the revision")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .staleRevision(
                    expected: sharedSnapshot.revision,
                    actual: first.revision
                )
            )
        }

        let finalAppendCount = await append.callCount()
        let final = await committer.currentCommittedSnapshot()
        XCTAssertEqual(finalAppendCount, 1)
        XCTAssertEqual(final.state, first.state)
        XCTAssertEqual(final.revision, first.revision)
    }

    func testRevisionFromAnotherCommitterIsNeverAcceptedAtTheSameOrdinal() async throws {
        let firstAppend = RecordingAppend()
        let secondAppend = RecordingAppend()
        let first = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in await firstAppend.call(request.event) }
        )
        let second = DurableJourneyCommitter(
            restoredState: .initial,
            lastSequence: 0,
            append: { request in await secondAppend.call(request.event) }
        )
        let foreign = await first.currentCommittedSnapshot()
        let local = await second.currentCommittedSnapshot()
        XCTAssertNotEqual(foreign.revision, local.revision)

        do {
            _ = try await second.commit(
                .updatePrologueTrace(0.5),
                expectedRevision: foreign.revision
            )
            XCTFail("Revision tokens must remain scoped to their issuing committer")
        } catch {
            XCTAssertEqual(
                error as? DurableJourneyCommitterError,
                .staleRevision(expected: foreign.revision, actual: local.revision)
            )
        }

        let firstAppendCount = await firstAppend.callCount()
        let secondAppendCount = await secondAppend.callCount()
        XCTAssertEqual(firstAppendCount, 0)
        XCTAssertEqual(secondAppendCount, 0)
    }

    func testSnapshotAndJournalRestoreExactCausalState() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let reducer = JourneyReducer()
        var expected = JourneyState.initial

        let first = JourneyEvent(logicalTimeMillis: 1, action: .updatePrologueTrace(0.5))
        _ = try await store.append(first)
        reducer.reduce(state: &expected, event: first)
        try await store.checkpoint(expected)

        let second = JourneyEvent(
            logicalTimeMillis: 2,
            action: .selectChapter(
                chapterID: "first-farmers",
                packageID: "essential",
                contentVersion: SchemaVersion(major: 1)
            )
        )
        _ = try await store.append(second)
        reducer.reduce(state: &expected, event: second)
        let narration = JourneyEvent(
            logicalTimeMillis: 3,
            action: .setNarration(cueID: "voice", sampleOffset: 99_999, enabled: true, playing: true)
        )
        _ = try await store.append(narration)
        reducer.reduce(state: &expected, event: narration)
        expected.prepareForColdRestore()

        let reopened = try ProgressStore(directoryURL: directory)
        let restoration = try await reopened.restore()
        XCTAssertEqual(restoration.state, expected)
        XCTAssertEqual(restoration.replayedEventCount, 2)
        XCTAssertEqual(restoration.lastSequence, 3)
        XCTAssertEqual(restoration.state.activeChapter?.packageID, "essential")
        XCTAssertEqual(restoration.state.activeChapter?.contentVersion, SchemaVersion(major: 1))
    }

    func testHardKillSnapshotPreservesSceneVisualStateAndPausesNarration() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let reducer = JourneyReducer()
        var expected = JourneyState.initial
        let events = [
            JourneyEvent(
                logicalTimeMillis: 1,
                action: .beginAuthoredChapter(Self.sceneBeatContract)
            ),
            JourneyEvent(
                logicalTimeMillis: 2,
                action: .activateScene(Self.sceneActivationContract)
            ),
            JourneyEvent(
                logicalTimeMillis: 3,
                action: .updateSceneVisualTick(
                    contract: Self.sceneActivationContract,
                    deterministicTick: 9_876_543
                )
            ),
            JourneyEvent(
                logicalTimeMillis: 4,
                action: .setNarration(
                    cueID: "harvest-narration",
                    sampleOffset: 48_123,
                    enabled: true,
                    playing: true
                )
            ),
        ]
        for event in events {
            _ = try await store.append(event)
            reducer.reduce(state: &expected, event: event)
        }
        try await store.checkpoint(expected)

        let reopened = try ProgressStore(directoryURL: directory)
        let restoration = try await reopened.restore()

        XCTAssertEqual(
            restoration.state.activeChapter?.sceneVisualSnapshot,
            SceneVisualSnapshot(sceneID: "harvest-scene", deterministicTick: 9_876_543)
        )
        XCTAssertEqual(restoration.state.activeChapter?.narration.sampleOffset, 48_123)
        XCTAssertTrue(restoration.state.activeChapter?.narration.isEnabled ?? false)
        XCTAssertFalse(restoration.state.activeChapter?.narration.isPlaying ?? true)
        XCTAssertEqual(restoration.replayedEventCount, 0)
        XCTAssertEqual(restoration.lastSequence, 4)
    }

    func testInterruptedFinalAppendIsIgnored() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        _ = try await store.append(
            JourneyEvent(logicalTimeMillis: 1, action: .updatePrologueTrace(0.25))
        )
        let handle = try FileHandle(forWritingTo: store.journalFileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"interrupted\"".utf8))
        try handle.close()

        let reopened = try ProgressStore(directoryURL: directory)
        let restoration = try await reopened.restore()
        XCTAssertEqual(restoration.lastSequence, 1)
        XCTAssertEqual(restoration.state.prologue.traceProgress, 0.25)
    }

    func testAppendAfterInterruptedTailRepairsTheJournal() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstStore = try ProgressStore(directoryURL: directory)
        _ = try await firstStore.append(
            JourneyEvent(logicalTimeMillis: 1, action: .updatePrologueTrace(0.25))
        )
        let handle = try FileHandle(forWritingTo: firstStore.journalFileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"interrupted\"".utf8))
        try handle.close()

        let reopened = try ProgressStore(directoryURL: directory)
        _ = try await reopened.append(
            JourneyEvent(logicalTimeMillis: 2, action: .updatePrologueTrace(0.75))
        )

        let finalStore = try ProgressStore(directoryURL: directory)
        let restoration = try await finalStore.restore()
        XCTAssertEqual(restoration.lastSequence, 2)
        XCTAssertEqual(restoration.state.prologue.traceProgress, 0.75)
    }

    func testTamperedCompletedRecordFailsClosed() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        _ = try await store.append(
            JourneyEvent(logicalTimeMillis: 1, action: .updatePrologueTrace(0.25))
        )
        var data = try Data(contentsOf: store.journalFileURL)
        if let index = data.firstIndex(of: Character("2").asciiValue!) {
            data[index] = Character("3").asciiValue!
        }
        try data.write(to: store.journalFileURL, options: .atomic)

        let reopened = try ProgressStore(directoryURL: directory)
        do {
            _ = try await reopened.restore()
            XCTFail("Tampered journal should not restore")
        } catch {
            XCTAssertTrue(error is ProgressStoreError)
        }
    }

    func testCheckpointIgnoresAnObsoleteJournalGenerationWithoutDecodingItsEvent() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(directoryURL: directory)
        let event = JourneyEvent(logicalTimeMillis: 1, action: .updatePrologueTrace(0.5))
        _ = try await store.append(event)
        let obsoleteJournal = try Data(contentsOf: store.journalFileURL)
        let reducer = JourneyReducer()
        var checkpointed = JourneyState.initial
        reducer.reduce(state: &checkpointed, event: event)
        try await store.checkpoint(checkpointed)

        let obsoleteText = String(decoding: obsoleteJournal, as: UTF8.self)
            .replacingOccurrences(of: "updatePrologueTrace", with: "removedAction")
        XCTAssertTrue(obsoleteText.contains("removedAction"))
        try Data(obsoleteText.utf8).write(to: store.journalFileURL, options: .atomic)

        let reopened = try ProgressStore(directoryURL: directory)
        let restoration = try await reopened.restore()
        XCTAssertEqual(restoration.state.prologue.traceProgress, 0.5)
        XCTAssertEqual(restoration.replayedEventCount, 0)
        XCTAssertEqual(restoration.lastSequence, 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-store-\(UUID().uuidString)", isDirectory: true)
    }

    private static let prologueEffect = WorldEffect(
        id: "prologue-road-awakened",
        mutation: .revealNode(
            WorldNodeBlueprint(
                id: "prologue-road",
                kind: .landscape,
                form: "awakened-road",
                position: NormalizedPoint(x: 0.5, y: 0.5)
            )
        )
    )

    private static let documentaryEffect = WorldEffect(
        id: "documentary-beat-consequence",
        mutation: .revealNode(
            WorldNodeBlueprint(
                id: "documentary-beat-node",
                kind: .settlement,
                form: "durable-settlement",
                position: NormalizedPoint(x: 0.4, y: 0.6)
            )
        )
    )

    private static let documentaryContract = BeatCompletionContract(
        packageID: "essential-free-v1",
        contentVersion: SchemaVersion(major: 1),
        chapterID: "first-farmers",
        arcID: "first-farmers-arc-one",
        beatID: "first-farmers-beat-one",
        arcIndex: 0,
        beatIndex: 0,
        absoluteBeatIndex: 0,
        mode: .documentary(effects: [documentaryEffect])
    )

    private static let sceneBeatContract = BeatCompletionContract(
        packageID: "essential",
        contentVersion: SchemaVersion(major: 1),
        chapterID: "first-farmers",
        arcID: "first-farmers-arc-02",
        beatID: "harvest-beat",
        arcIndex: 0,
        beatIndex: 0,
        absoluteBeatIndex: 0,
        mode: .documentary(effects: [])
    )

    private static let sceneActivationContract = SceneActivationContract(
        packageID: "essential",
        contentVersion: SchemaVersion(major: 1),
        chapterID: "first-farmers",
        arcID: "first-farmers-arc-02",
        beatID: "harvest-beat",
        sceneID: "harvest-scene",
        arcIndex: 0,
        beatIndex: 0,
        absoluteBeatIndex: 0
    )

    private static let secondSceneBeatContract = BeatCompletionContract(
        packageID: "essential",
        contentVersion: SchemaVersion(major: 1),
        chapterID: "first-farmers",
        arcID: "first-farmers-arc-02",
        beatID: "house-beat",
        arcIndex: 0,
        beatIndex: 1,
        absoluteBeatIndex: 1,
        mode: .documentary(effects: [])
    )

    private static let twoBeatArcCompletionContract = ArcCompletionContract(
        packageID: "essential",
        contentVersion: SchemaVersion(major: 1),
        chapterID: "first-farmers",
        arcID: "first-farmers-arc-02",
        arcIndex: 0,
        beats: [
            ArcCompletionContract.BeatInventory(
                sceneID: "harvest-scene",
                completion: sceneBeatContract,
                interaction: nil
            ),
            ArcCompletionContract.BeatInventory(
                sceneID: "house-scene",
                completion: secondSceneBeatContract,
                interaction: nil
            ),
        ],
        finalBeatID: "house-beat",
        finalSceneID: "house-scene"
    )
}

private enum AppendPausePoint: Equatable, Sendable {
    case beforeAppend
    case afterAppend
}

private actor AppendBoundaryGate {
    private let store: ProgressStore
    private let pause: AppendPausePoint
    private var didPause = false
    private var wasResumed = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    init(store: ProgressStore, pause: AppendPausePoint) {
        self.store = store
        self.pause = pause
    }

    func append(_ event: JourneyEvent) async throws -> UInt64 {
        if pause == .beforeAppend { await pauseHere() }
        let sequence = try await store.append(event)
        if pause == .afterAppend { await pauseHere() }
        return sequence
    }

    func waitUntilPaused() async {
        guard !didPause else { return }
        await withCheckedContinuation { continuation in
            pauseWaiters.append(continuation)
        }
    }

    func resume() {
        wasResumed = true
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    private func pauseHere() async {
        didPause = true
        pauseWaiters.forEach { $0.resume() }
        pauseWaiters.removeAll()
        guard !wasResumed else { return }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }
}

private enum InjectedPersistenceError: Error, Equatable {
    case appendFailed
}

private actor FailOnceAppend {
    private var shouldFail = true
    private var sequence: UInt64 = 0

    func call(_ event: JourneyEvent) throws -> UInt64 {
        _ = event
        if shouldFail {
            shouldFail = false
            throw ProgressStoreAppendFailure(
                disposition: .noJournalRecordWriteAttempted,
                underlyingError: InjectedPersistenceError.appendFailed
            )
        }
        sequence += 1
        return sequence
    }
}

private final class CompleteWriteThenFailOnceAppender: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0

    var attemptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    func append(_ data: Data, to url: URL) throws {
        lock.lock()
        attempts += 1
        let shouldFail = attempts == 1
        lock.unlock()

        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        if shouldFail {
            throw InjectedPersistenceError.appendFailed
        }
        try handle.synchronize()
    }
}

private actor WrongSequenceAppend {
    private let returnedSequence: UInt64
    private var events: [JourneyEvent] = []

    init(returnedSequence: UInt64) {
        self.returnedSequence = returnedSequence
    }

    func call(_ event: JourneyEvent) -> UInt64 {
        events.append(event)
        return returnedSequence
    }

    func callCount() -> Int { events.count }
}

private actor CancellationBlockingAppend {
    private var events: [JourneyEvent] = []
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func call(_ event: JourneyEvent) async throws -> UInt64 {
        events.append(event)
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        if !released {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        try Task.checkCancellation()
        return UInt64(events.count)
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func callCount() -> Int { events.count }
}

private actor OrderedAppend {
    private var sequence: UInt64 = 0

    func call(_ event: JourneyEvent) async -> UInt64 {
        _ = event
        await Task.yield()
        sequence += 1
        return sequence
    }
}

private actor BlockingRecordingAppend {
    private var recordedEvents: [JourneyEvent] = []
    private var firstAppendStarted = false
    private var firstAppendWasResumed = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func call(_ event: JourneyEvent) async -> UInt64 {
        recordedEvents.append(event)
        let sequence = UInt64(recordedEvents.count)
        guard sequence == 1 else { return sequence }

        firstAppendStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        guard !firstAppendWasResumed else { return sequence }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        return sequence
    }

    func waitUntilFirstAppendStarts() async {
        guard !firstAppendStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeFirstAppend() {
        firstAppendWasResumed = true
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func callCount() -> Int {
        recordedEvents.count
    }
}

private actor RecordingAppend {
    private var recordedEvents: [JourneyEvent] = []

    func call(_ event: JourneyEvent) -> UInt64 {
        recordedEvents.append(event)
        return UInt64(recordedEvents.count)
    }

    func callCount() -> Int {
        recordedEvents.count
    }

    func events() -> [JourneyEvent] {
        recordedEvents
    }
}
