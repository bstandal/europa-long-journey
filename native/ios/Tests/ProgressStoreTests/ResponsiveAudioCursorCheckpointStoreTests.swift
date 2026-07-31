import ContentKit
import Foundation
@testable import JourneyDomain
import JourneyPersistence
@testable import ProgressStore
import XCTest

final class ResponsiveAudioCursorCheckpointStoreTests: XCTestCase {
    func testPeriodicCheckpointUsesOneFileBarrierAndNoSlotReadback()
        async throws {
        let root = temporaryDirectory()
        let io = CheckpointIORecorder()
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root,
            ioObserver: { io.record($0) }
        )
        let expectedSlots = Set([
            store.slotAURL,
            store.slotBURL,
            store.slotCURL,
        ])

        XCTAssertEqual(Set(io.preparedSlots), expectedSlots)
        XCTAssertEqual(Set(io.readSlots), expectedSlots)
        XCTAssertEqual(io.readSlots.count, 3)
        XCTAssertEqual(io.directoryBarriers.count, 1)
        XCTAssertTrue(io.checkpointFileBarriers.isEmpty)
        for url in expectedSlots {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        let fixture = try Fixture()
        let authority = try fixture.authority()
        let session = try await store.beginSession(authority: authority)
        let first = fixture.snapshot(cursor: 3_000)
        try await store.checkpoint(
            first,
            session: session,
            capturedAtMonotonicNanoseconds: 1
        )
        try await store.checkpoint(
            first,
            session: session,
            capturedAtMonotonicNanoseconds: 2
        )
        try await store.checkpoint(
            fixture.snapshot(cursor: 4_000),
            session: session,
            capturedAtMonotonicNanoseconds: 3
        )

        XCTAssertEqual(
            io.checkpointFileBarriers,
            [store.slotAURL, store.slotBURL]
        )
        XCTAssertEqual(io.directoryBarriers.count, 1)
        XCTAssertEqual(
            io.readSlots.count,
            3,
            "Successful periodic checkpoints must not reread their slots"
        )

        let recovered = try await store.recover(authority: authority)
        XCTAssertEqual(recovered?.cursorSample, 4_000)
        XCTAssertEqual(
            io.readSlots.count,
            6,
            "Explicit recovery must checksum-scan all three slots"
        )
        let directoryEntries = try FileManager.default.contentsOfDirectory(
            at: store.directoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(
            Set(directoryEntries.map(\.lastPathComponent)),
            Set(expectedSlots.map(\.lastPathComponent))
        )
    }

    func testRecoveryChangesOnlyPositionAndSurvivesUnrelatedJourneyCommit() async throws {
        let root = temporaryDirectory()
        let store = try ResponsiveAudioCursorCheckpointStore(directoryURL: root)
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let session = try await store.beginSession(
            authority: authority,
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
        )
        let advanced = fixture.snapshot(cursor: 12_000)
        try await store.checkpoint(
            advanced,
            session: session,
            capturedAtMonotonicNanoseconds: 200_000_000
        )

        var unrelatedState = fixture.state
        unrelatedState.lastLogicalTimeMillis = 99
        unrelatedState.appliedEventCount = 44
        let recreated = try ResponsiveAudioCursorAuthority.make(
            durableState: unrelatedState,
            contentRevision: fixture.contentRevision,
            program: fixture.program,
            timeline: fixture.timeline
        )
        XCTAssertEqual(recreated, authority)

        let recovered = try await store.recover(authority: recreated)
        XCTAssertEqual(recovered, advanced)
        XCTAssertEqual(recovered?.stage, fixture.snapshot.stage)
        XCTAssertEqual(recovered?.interactionPhase, fixture.snapshot.interactionPhase)
        XCTAssertEqual(recovered?.causalStage, fixture.snapshot.causalStage)
        XCTAssertNil(recovered?.durableCompletionSequence)
    }

    func testNewDurableGenerationAndClosedReopenRejectOldSlot() async throws {
        let root = temporaryDirectory()
        let store = try ResponsiveAudioCursorCheckpointStore(directoryURL: root)
        let old = try Fixture(generation: 4)
        let oldAuthority = try old.authority()
        let writer = try await store.beginSession(authority: oldAuthority)
        try await store.checkpoint(
            old.snapshot(cursor: 8_000),
            session: writer,
            capturedAtMonotonicNanoseconds: 10
        )

        var newState = old.state
        newState.activeChapter?.responsiveAudioSessionGeneration = 5
        let newAuthority = try ResponsiveAudioCursorAuthority.make(
            durableState: newState,
            contentRevision: old.contentRevision,
            program: old.program,
            timeline: old.timeline
        )
        let staleRecovery = try await store.recover(authority: newAuthority)
        XCTAssertNil(staleRecovery)

        newState.activeChapter?.responsiveAudioSessionIsActive = false
        newState.activeChapter?.responsiveAudioChapterOpenNonce = nil
        XCTAssertThrowsError(
            try ResponsiveAudioCursorAuthority.make(
                durableState: newState,
                contentRevision: old.contentRevision,
                program: old.program,
                timeline: old.timeline
            )
        )
    }

    func testPackageMigrationContentRevisionAndTimelineDigestRejectOldSlot() async throws {
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let session = try await store.beginSession(authority: authority)
        try await store.checkpoint(
            fixture.snapshot(cursor: 9_000),
            session: session,
            capturedAtMonotonicNanoseconds: 1
        )

        let revisionChanged = try ResponsiveAudioCursorAuthority.make(
            durableState: fixture.state,
            contentRevision: fixture.contentRevision + 1,
            program: fixture.program,
            timeline: fixture.timeline
        )
        let revisionRecovery = try await store.recover(authority: revisionChanged)
        XCTAssertNil(revisionRecovery)

        let changedTimeline = AudioTimeline(
            id: fixture.timeline.id,
            sampleRate: fixture.timeline.sampleRate,
            events: [
                AudioEvent(
                    cueID: "changed",
                    role: .silence,
                    startSample: 0,
                    durationSamples: fixture.timeline.authoredDurationSamples,
                    assetPath: nil,
                    gain: 0
                ),
            ],
            haptics: []
        )
        let timelineChanged = try ResponsiveAudioCursorAuthority.make(
            durableState: fixture.state,
            contentRevision: fixture.contentRevision,
            program: fixture.program,
            timeline: changedTimeline
        )
        let timelineRecovery = try await store.recover(authority: timelineChanged)
        XCTAssertNil(timelineRecovery)
    }

    func testTornNewestSlotFallsBackToPreviousVerifiedPosition() async throws {
        let root = temporaryDirectory()
        let store = try ResponsiveAudioCursorCheckpointStore(directoryURL: root)
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let session = try await store.beginSession(authority: authority)
        try await store.checkpoint(
            fixture.snapshot(cursor: 5_000),
            session: session,
            capturedAtMonotonicNanoseconds: 1
        )
        try await store.checkpoint(
            fixture.snapshot(cursor: 6_000),
            session: session,
            capturedAtMonotonicNanoseconds: 2
        )
        try Data("{torn".utf8).write(to: store.slotBURL)

        let recovered = try await store.recover(authority: authority)
        XCTAssertEqual(recovered?.cursorSample, 5_000)
    }

    func testPartialNewestOverwriteIsRejectedInProcessAndAfterRestart()
        async throws {
        let root = temporaryDirectory()
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let stableStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root
        )
        let stableSession = try await stableStore.beginSession(
            authority: authority
        )
        try await stableStore.checkpoint(
            fixture.snapshot(cursor: 4_000),
            session: stableSession,
            capturedAtMonotonicNanoseconds: 1
        )
        try await stableStore.checkpoint(
            fixture.snapshot(cursor: 5_000),
            session: stableSession,
            capturedAtMonotonicNanoseconds: 2
        )
        await stableStore.retire(stableSession)

        let partialStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root,
            durableWrite: { data, url in
                let partial = Data(data.prefix(max(1, data.count / 2)))
                try partial.write(to: url, options: [])
                throw InjectedFailure()
            }
        )
        let partialSession = try await partialStore.beginSession(
            authority: authority
        )
        await XCTAssertThrowsErrorAsync {
            try await partialStore.checkpoint(
                fixture.snapshot(cursor: 6_000),
                session: partialSession,
                capturedAtMonotonicNanoseconds: 3
            )
        }

        let sameProcessRecovery = try await partialStore.recover(
            authority: authority
        )
        XCTAssertEqual(sameProcessRecovery?.cursorSample, 5_000)

        let restartedStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root
        )
        let restartedRecovery = try await restartedStore.recover(
            authority: authority
        )
        XCTAssertEqual(restartedRecovery?.cursorSample, 5_000)
    }

    func testSilentCorruptWriterSuccessIsRejectedByRecoveryAndRestart()
        async throws {
        let root = temporaryDirectory()
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let stableStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root
        )
        let stableSession = try await stableStore.beginSession(
            authority: authority
        )
        try await stableStore.checkpoint(
            fixture.snapshot(cursor: 4_000),
            session: stableSession,
            capturedAtMonotonicNanoseconds: 1
        )
        try await stableStore.checkpoint(
            fixture.snapshot(cursor: 5_000),
            session: stableSession,
            capturedAtMonotonicNanoseconds: 2
        )
        await stableStore.retire(stableSession)

        // An injected operation that returns success is asserting that it
        // wrote and synchronised the supplied bytes. Deliberately violating
        // that contract is invisible to the steady writer, but the required
        // checksum scan at recovery must reject it and retain the fallback.
        let corruptStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root,
            durableWrite: { _, url in
                try Data("{\"formatVersion\":1}".utf8).write(to: url)
            }
        )
        let corruptSession = try await corruptStore.beginSession(
            authority: authority
        )
        try await corruptStore.checkpoint(
            fixture.snapshot(cursor: 6_000),
            session: corruptSession,
            capturedAtMonotonicNanoseconds: 3
        )

        let sameProcessRecovery = try await corruptStore.recover(
            authority: authority
        )
        XCTAssertEqual(sameProcessRecovery?.cursorSample, 5_000)

        let restartedStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root
        )
        let restartedRecovery = try await restartedStore.recover(
            authority: authority
        )
        XCTAssertEqual(restartedRecovery?.cursorSample, 5_000)
    }

    func testRestartFullyScansSlotsAndRebuildsCachedGenerationHead()
        async throws {
        let root = temporaryDirectory()
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let firstStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root
        )
        let firstSession = try await firstStore.beginSession(
            authority: authority
        )
        for (index, cursor) in [3_000, 4_000, 5_000].enumerated() {
            try await firstStore.checkpoint(
                fixture.snapshot(cursor: Int64(cursor)),
                session: firstSession,
                capturedAtMonotonicNanoseconds: UInt64(index + 1)
            )
        }
        await firstStore.retire(firstSession)

        let io = CheckpointIORecorder()
        let restartedStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root,
            ioObserver: { io.record($0) }
        )
        XCTAssertEqual(io.readSlots.count, 3)
        XCTAssertEqual(
            Set(io.readSlots),
            Set([
                restartedStore.slotAURL,
                restartedStore.slotBURL,
                restartedStore.slotCURL,
            ])
        )

        let recovered = try await restartedStore.recover(
            authority: authority
        )
        XCTAssertEqual(recovered?.cursorSample, 5_000)
        XCTAssertEqual(io.readSlots.count, 6)

        let restartedSession = try await restartedStore.beginSession(
            authority: authority
        )
        try await restartedStore.checkpoint(
            fixture.snapshot(cursor: 6_000),
            session: restartedSession,
            capturedAtMonotonicNanoseconds: 4
        )
        XCTAssertEqual(
            io.checkpointFileBarriers,
            [restartedStore.slotAURL]
        )
        XCTAssertEqual(io.readSlots.count, 6)
    }

    func testSidecarCannotPromotePhaseStageTimelineCausalStageOrCompletion() async throws {
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let session = try await store.beginSession(authority: authority)

        for forged in [
            ResponsiveAudioProgramSnapshot(
                programID: fixture.program.id,
                stage: .consequence,
                interactionPhase: nil,
                timelineID: fixture.program.consequenceTimelineID,
                cursorSample: 0,
                loopIteration: 0,
                durableCompletionSequence: 99
            ),
            ResponsiveAudioProgramSnapshot(
                programID: fixture.program.id,
                stage: .interaction,
                interactionPhase: .engaged,
                timelineID: fixture.timeline.id,
                cursorSample: 1,
                loopIteration: 0,
                causalStage: ResponsiveAudioCausalStage(completedStageCount: 1),
                durableCompletionSequence: nil
            ),
        ] {
            await XCTAssertThrowsErrorAsync {
                try await store.checkpoint(
                    forged,
                    session: session,
                    capturedAtMonotonicNanoseconds: 1
                )
            }
        }
        let recovered = try await store.recover(authority: authority)
        XCTAssertNil(recovered)
    }

    func testFiniteStagesRejectBoundaryWithoutDurableStagePromotion() async throws {
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let fixture = try Fixture(stage: .approach)
        let authority = try fixture.authority()
        let session = try await store.beginSession(authority: authority)

        await XCTAssertThrowsErrorAsync {
            try await store.checkpoint(
                fixture.snapshot(
                    stage: .approach,
                    phase: nil,
                    cursor: fixture.timeline.authoredDurationSamples
                ),
                session: session,
                capturedAtMonotonicNanoseconds: 1
            )
        }
        let recovered = try await store.recover(authority: authority)
        XCTAssertNil(recovered)
    }

    func testLoopPositionIsMonotonicAndOverflowFailsClosed() async throws {
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let fixture = try Fixture(baseCursor: 47_000, baseLoop: 1)
        let authority = try fixture.authority()
        let session = try await store.beginSession(authority: authority)
        let wrapped = fixture.snapshot(cursor: 100, loop: 2)
        try await store.checkpoint(
            wrapped,
            session: session,
            capturedAtMonotonicNanoseconds: 1
        )
        let recovered = try await store.recover(authority: authority)
        XCTAssertEqual(recovered, wrapped)

        await XCTAssertThrowsErrorAsync {
            try await store.checkpoint(
                fixture.snapshot(cursor: 99, loop: 2),
                session: session,
                capturedAtMonotonicNanoseconds: 2
            )
        }
        await XCTAssertThrowsErrorAsync {
            try await store.checkpoint(
                fixture.snapshot(cursor: 0, loop: UInt64.max),
                session: session,
                capturedAtMonotonicNanoseconds: 3
            )
        }
    }

    func testWriterSessionIDCannotBeReusedAndFailedWritePreservesOldSlot() async throws {
        let root = temporaryDirectory()
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let stableStore = try ResponsiveAudioCursorCheckpointStore(directoryURL: root)
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000f1")!
        let stableSession = try await stableStore.beginSession(authority: authority, id: id)
        try await stableStore.checkpoint(
            fixture.snapshot(cursor: 4_000),
            session: stableSession,
            capturedAtMonotonicNanoseconds: 1
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await stableStore.beginSession(authority: authority, id: id)
        }

        let failingStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root,
            durableWrite: { _, _ in throw InjectedFailure() }
        )
        let failingSession = try await failingStore.beginSession(authority: authority)
        await XCTAssertThrowsErrorAsync {
            try await failingStore.checkpoint(
                fixture.snapshot(cursor: 5_000),
                session: failingSession,
                capturedAtMonotonicNanoseconds: 2
            )
        }
        let recovered = try await failingStore.recover(authority: authority)
        XCTAssertEqual(recovered?.cursorSample, 4_000)

        await XCTAssertThrowsErrorAsync {
            _ = try await failingStore.beginSession(
                authority: authority,
                id: failingSession.id
            )
        }
    }

    func testCompletedButReportedFailedOverwriteIsQuarantinedUntilRestart()
        async throws {
        let root = temporaryDirectory()
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let stableStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root
        )
        let stableSession = try await stableStore.beginSession(
            authority: authority
        )
        try await stableStore.checkpoint(
            fixture.snapshot(cursor: 4_000),
            session: stableSession,
            capturedAtMonotonicNanoseconds: 1
        )

        let uncertainStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root,
            durableWrite: { data, url in
                try data.write(to: url)
                throw InjectedFailure()
            }
        )
        let uncertainSession = try await uncertainStore.beginSession(
            authority: authority
        )
        await XCTAssertThrowsErrorAsync {
            try await uncertainStore.checkpoint(
                fixture.snapshot(cursor: 5_000),
                session: uncertainSession,
                capturedAtMonotonicNanoseconds: 2
            )
        }
        let sameProcessRecovery = try await uncertainStore.recover(
            authority: authority
        )
        XCTAssertEqual(sameProcessRecovery?.cursorSample, 4_000)

        // A new process has no memory-only quarantine. If the complete write
        // survived the crash boundary, digest verification may recover it.
        let restartedStore = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: root
        )
        let restartedRecovery = try await restartedStore.recover(
            authority: authority
        )
        XCTAssertEqual(restartedRecovery?.cursorSample, 5_000)
    }

    func testNewWriterCannotRegressSameDurableAuthority() async throws {
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let writerA = try await store.beginSession(authority: authority)
        try await store.checkpoint(
            fixture.snapshot(cursor: 12_000),
            session: writerA,
            capturedAtMonotonicNanoseconds: 20
        )
        await store.retire(writerA)

        let writerB = try await store.beginSession(authority: authority)
        await XCTAssertThrowsErrorAsync {
            try await store.checkpoint(
                fixture.snapshot(cursor: 8_000),
                session: writerB,
                capturedAtMonotonicNanoseconds: 1
            )
        }
        try await store.checkpoint(
            fixture.snapshot(cursor: 12_000),
            session: writerB,
            capturedAtMonotonicNanoseconds: 2
        )
        try await store.checkpoint(
            fixture.snapshot(cursor: 13_000),
            session: writerB,
            capturedAtMonotonicNanoseconds: 3
        )

        let recovered = try await store.recover(authority: authority)
        XCTAssertEqual(recovered?.cursorSample, 13_000)
    }

    func testHandoffDurablySeedsSuccessorBeforePriorWriterRetires()
        async throws {
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let approach = try Fixture(stage: .approach, baseCursor: 4_000)
        let interaction = try Fixture(stage: .interaction, baseCursor: 0)
        let prior = try await store.beginSession(
            authority: approach.authority()
        )
        try await store.checkpoint(
            approach.snapshot(stage: .approach, phase: nil, cursor: 5_000),
            session: prior,
            capturedAtMonotonicNanoseconds: 100
        )

        let successorSnapshot = interaction.snapshot(cursor: 240)
        let successor = try await store.handoffSession(
            from: prior,
            to: interaction.authority(),
            initialSnapshot: successorSnapshot,
            capturedAtMonotonicNanoseconds: 200
        )

        let recoveredSuccessor = try await store.recover(
            authority: interaction.authority()
        )
        XCTAssertEqual(recoveredSuccessor, successorSnapshot)
        await XCTAssertThrowsErrorAsync {
            try await store.checkpoint(
                approach.snapshot(
                    stage: .approach,
                    phase: nil,
                    cursor: 6_000
                ),
                session: prior,
                capturedAtMonotonicNanoseconds: 300
            )
        }
        try await store.checkpoint(
            interaction.snapshot(cursor: 480),
            session: successor,
            capturedAtMonotonicNanoseconds: 300
        )
    }

    func testFailedHandoffRetainsPriorSessionAndConsumesSuccessorID()
        async throws {
        let writes = FailSelectedDurableWrite(failingCalls: [2])
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: { data, url in
                try writes.write(data, to: url)
            }
        )
        let approach = try Fixture(stage: .approach, baseCursor: 2_000)
        let interaction = try Fixture(stage: .interaction, baseCursor: 2_000)
        let prior = try await store.beginSession(
            authority: approach.authority()
        )
        try await store.checkpoint(
            approach.snapshot(stage: .approach, phase: nil, cursor: 2_400),
            session: prior,
            capturedAtMonotonicNanoseconds: 1
        )
        let successorID = UUID()

        await XCTAssertThrowsErrorAsync {
            _ = try await store.handoffSession(
                from: prior,
                to: interaction.authority(),
                initialSnapshot: interaction.snapshot(cursor: 2_400),
                capturedAtMonotonicNanoseconds: 2,
                id: successorID
            )
        }
        let stillOwnsPrior = await store.owns(prior)
        XCTAssertTrue(stillOwnsPrior)
        await XCTAssertThrowsErrorAsync {
            _ = try await store.handoffSession(
                from: prior,
                to: interaction.authority(),
                initialSnapshot: interaction.snapshot(cursor: 2_400),
                capturedAtMonotonicNanoseconds: 3,
                id: successorID
            )
        }
        try await store.checkpoint(
            approach.snapshot(stage: .approach, phase: nil, cursor: 2_800),
            session: prior,
            capturedAtMonotonicNanoseconds: 4
        )
        let recoveredPrior = try await store.recover(
            authority: approach.authority()
        )
        XCTAssertEqual(recoveredPrior?.cursorSample, 2_800)
    }

    @MainActor
    func testRetireDuringHandoffPreventsStaleSuccessorPromotion()
        async throws {
        let writes = BlockingDurableWrites()
        defer { writes.releaseAll() }
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: { data, url in
                try writes.write(data, to: url)
            }
        )
        let approach = try Fixture(stage: .approach, baseCursor: 2_000)
        let interaction = try Fixture(stage: .interaction, baseCursor: 2_000)
        let prior = try await store.beginSession(
            authority: approach.authority()
        )
        let handoff = Task {
            try await store.handoffSession(
                from: prior,
                to: interaction.authority(),
                initialSnapshot: interaction.snapshot(cursor: 2_400),
                capturedAtMonotonicNanoseconds: 1
            )
        }
        try await waitUntil { writes.callCount == 1 }
        let retirement = Task { @MainActor in
            await store.retire(prior)
        }
        var ownsRetiringSession = await store.owns(prior)
        let retirementDeadline = DispatchTime.now().uptimeNanoseconds
            + 500_000_000
        while ownsRetiringSession,
              DispatchTime.now().uptimeNanoseconds < retirementDeadline {
            try await Task.sleep(nanoseconds: 1_000_000)
            ownsRetiringSession = await store.owns(prior)
        }
        XCTAssertFalse(ownsRetiringSession)
        writes.releaseFirst()
        await retirement.value
        do {
            _ = try await handoff.value
            XCTFail("A retired prior session cannot promote its successor")
        } catch {
            XCTAssertEqual(
                error as? ResponsiveAudioCursorCheckpointError,
                .staleSession
            )
        }
    }

    @MainActor
    func testRetireWaitsForAdmittedWriterBeforeRecoveryBecomesFinal()
        async throws {
        let writes = BlockingDurableWrites()
        defer { writes.releaseAll() }
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: { data, url in
                try writes.write(data, to: url)
            }
        )
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let session = try await store.beginSession(authority: authority)
        let admitted = fixture.snapshot(cursor: 8_000)
        let checkpoint = Task { @MainActor in
            try await store.checkpoint(
                admitted,
                session: session,
                capturedAtMonotonicNanoseconds: 1
            )
        }
        try await waitUntil { writes.callCount == 1 }

        var retirementCompleted = false
        let retirement = Task { @MainActor in
            await store.retire(session)
            retirementCompleted = true
        }
        await Task.yield()
        XCTAssertFalse(retirementCompleted)
        XCTAssertEqual(writes.completedCallCount, 0)

        writes.releaseFirst()
        try await checkpoint.value
        await retirement.value
        XCTAssertTrue(retirementCompleted)
        XCTAssertEqual(writes.completedCallCount, 1)
        let recovered = try await store.recover(authority: authority)
        XCTAssertEqual(recovered, admitted)
    }

    @MainActor
    func testThirdConcurrentWriteCannotConsumeCrashFallbackSlot()
        async throws {
        let writes = BlockingDurableWrites()
        defer { writes.releaseAll() }
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: { data, url in
                try writes.write(data, to: url)
            }
        )
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let session = try await store.beginSession(authority: authority)
        let first = Task {
            try await store.checkpoint(
                fixture.snapshot(cursor: 3_000),
                session: session,
                capturedAtMonotonicNanoseconds: 1
            )
        }
        try await waitUntil { writes.callCount == 1 }
        let second = Task {
            try await store.checkpoint(
                fixture.snapshot(cursor: 4_000),
                session: session,
                capturedAtMonotonicNanoseconds: 2
            )
        }
        try await waitUntil { writes.callCount == 2 }

        do {
            try await store.checkpoint(
                fixture.snapshot(cursor: 5_000),
                session: session,
                capturedAtMonotonicNanoseconds: 3
            )
            XCTFail("A third physical write cannot consume the fallback slot")
        } catch {
            XCTAssertEqual(
                error as? ResponsiveAudioCursorCheckpointError,
                .durabilityFailure
            )
        }
        XCTAssertEqual(writes.callCount, 2)
        XCTAssertEqual(Set(writes.destinations).count, 2)
        XCTAssertEqual(Set(writes.generations).count, 2)
        XCTAssertFalse(writes.destinations.contains(store.slotCURL))

        writes.releaseSecond()
        try await second.value
        writes.releaseFirst()
        try await first.value
        let recovered = try await store.recover(authority: authority)
        XCTAssertEqual(recovered?.cursorSample, 4_000)
    }

    @MainActor
    func testStaleOldPumpCompletionAfterHandoffCannotFailClosedNewGeneration()
        async throws {
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let approach = try Fixture(stage: .approach, baseCursor: 2_000)
        let interaction = try Fixture(stage: .interaction, baseCursor: 2_000)
        let priorSession = try await store.beginSession(
            authority: approach.authority()
        )
        let oldPersistEntered = PumpTestGate()
        let releaseOldPersist = PumpTestGate()
        var oldPersistError: ResponsiveAudioCursorCheckpointError?
        var oldFailClosedCount = 0
        var successorFailClosedCount = 0
        var successorPersistCount = 0
        var successorCursor: Int64 = 2_400
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 1_000_000,
            maximumAgeNanoseconds: 1_000_000_000
        )

        let oldStart = Task { @MainActor in
            await pump.start(
                capture: {
                    .verified(
                        approach.snapshot(
                            stage: .approach,
                            phase: nil,
                            cursor: 2_400
                        )
                    )
                },
                persist: { snapshot, capturedAt in
                    oldPersistEntered.open()
                    await releaseOldPersist.wait()
                    do {
                        try await store.checkpoint(
                            snapshot,
                            session: priorSession,
                            capturedAtMonotonicNanoseconds: capturedAt
                        )
                    } catch let error as ResponsiveAudioCursorCheckpointError {
                        oldPersistError = error
                        throw error
                    }
                },
                failClosed: { oldFailClosedCount += 1 }
            )
        }
        await oldPersistEntered.wait()

        // This is the exact JourneyModel ordering: retire the old pump
        // generation, durably seed the successor authority, then start the
        // successor while an admitted old persist remains suspended.
        pump.stop()
        let handoffCapturedAt = DispatchTime.now().uptimeNanoseconds
        let successorSession = try await store.handoffSession(
            from: priorSession,
            to: interaction.authority(),
            initialSnapshot: interaction.snapshot(cursor: successorCursor),
            capturedAtMonotonicNanoseconds: handoffCapturedAt
        )
        let successorStart = await pump.start(
            lastVerifiedCaptureNanoseconds: handoffCapturedAt,
            capture: {
                successorCursor += 480
                return .verified(
                    interaction.snapshot(cursor: successorCursor)
                )
            },
            persist: { snapshot, capturedAt in
                try await store.checkpoint(
                    snapshot,
                    session: successorSession,
                    capturedAtMonotonicNanoseconds: capturedAt
                )
                successorPersistCount += 1
            },
            failClosed: { successorFailClosedCount += 1 }
        )
        XCTAssertEqual(successorStart, .protecting)

        releaseOldPersist.open()
        let obsoleteStartResult = await oldStart.value
        XCTAssertEqual(obsoleteStartResult, .superseded)
        try await waitUntil {
            oldPersistError != nil && successorPersistCount > 0
        }

        XCTAssertEqual(oldPersistError, .staleSession)
        XCTAssertEqual(oldFailClosedCount, 0)
        XCTAssertEqual(successorFailClosedCount, 0)
        XCTAssertFalse(pump.didFailClosed)
        XCTAssertTrue(pump.isRunning)
        let recovered = try await store.recover(
            authority: interaction.authority()
        )
        XCTAssertGreaterThan(recovered?.cursorSample ?? -1, 2_400)
        pump.stop()
    }

    /// An admitted obsolete fsync must not hold actor isolation. The successor
    /// receives a distinct destination and becomes durable inside the same
    /// absolute deadline; a late old completion cannot reactivate or replace
    /// the successor authority.
    @MainActor
    func testAdmittedOldStoreWriteCannotBlockOrOverwriteSuccessorHandoff()
        async throws {
        let writes = BlockingDurableWrites()
        defer { writes.releaseAll() }
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: { data, url in
                try writes.write(data, to: url)
            }
        )
        let approach = try Fixture(stage: .approach, baseCursor: 2_000)
        let interaction = try Fixture(stage: .interaction, baseCursor: 2_000)
        let priorSession = try await store.beginSession(
            authority: approach.authority()
        )
        var failClosedCount = 0
        let handoffClock: UInt64 = 10_000
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 20_000_000,
            maximumAgeNanoseconds: 250_000_000,
            now: { handoffClock },
            sleep: { _ in
                try await Task.sleep(nanoseconds: UInt64.max)
            }
        )
        let oldStart = Task { @MainActor in
            await pump.start(
                capture: {
                    .verified(
                        approach.snapshot(
                            stage: .approach,
                            phase: nil,
                            cursor: 2_400
                        )
                    )
                },
                persist: { snapshot, capturedAt in
                    try await store.checkpoint(
                        snapshot,
                        session: priorSession,
                        capturedAtMonotonicNanoseconds: capturedAt
                    )
                },
                failClosed: { failClosedCount += 1 }
            )
        }
        try await waitUntil { writes.callCount == 1 }

        let lastRecoverableCapture = try XCTUnwrap(
            pump.lastVerifiedCaptureNanoseconds
        )
        let handoffCapturedAt = handoffClock
        let token = try XCTUnwrap(pump.beginHandoffDeadline(
            candidateCapturedAtNanoseconds: handoffCapturedAt,
            lastRecoverableCaptureNanoseconds: lastRecoverableCapture,
            failClosed: { failClosedCount += 1 }
        ))
        let handoff = Task { @MainActor in
            try await store.handoffSession(
                from: priorSession,
                to: interaction.authority(),
                initialSnapshot: interaction.snapshot(cursor: 2_400),
                capturedAtMonotonicNanoseconds: handoffCapturedAt
            )
        }

        try await waitUntil { writes.callCount == 2 }
        XCTAssertEqual(Set(writes.destinations).count, 2)
        XCTAssertEqual(failClosedCount, 0)
        writes.releaseSecond()
        let successor = try await handoff.value
        let ownsSuccessorBeforeOldCompletion = await store.owns(successor)
        XCTAssertTrue(ownsSuccessorBeforeOldCompletion)
        XCTAssertTrue(
            pump.ownsHandoffDeadline(
                token,
                candidateCapturedAtNanoseconds: handoffCapturedAt,
                lastRecoverableCaptureNanoseconds:
                    lastRecoverableCapture
            )
        )
        let successorBeforeOldCompletion = try await store.recover(
            authority: interaction.authority()
        )
        XCTAssertEqual(successorBeforeOldCompletion?.cursorSample, 2_400)
        XCTAssertEqual(failClosedCount, 0)

        pump.stop()
        writes.releaseFirst()
        let obsoleteStartResult = await oldStart.value
        XCTAssertEqual(obsoleteStartResult, .superseded)
        try await waitUntil { writes.completedCallCount == 2 }
        XCTAssertEqual(writes.callCount, 2)
        let ownsSuccessorAfterOldCompletion = await store.owns(successor)
        XCTAssertTrue(ownsSuccessorAfterOldCompletion)
        let successorAfterOldCompletion = try await store.recover(
            authority: interaction.authority()
        )
        XCTAssertEqual(successorAfterOldCompletion?.cursorSample, 2_400)
        XCTAssertEqual(failClosedCount, 0)
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 500_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds
            + timeoutNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds > deadline {
                XCTFail("Timed out waiting for checkpoint handoff")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "responsive-audio-cursor-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

private struct InjectedFailure: Error {}

private final class CheckpointIORecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ResponsiveAudioCursorCheckpointStore.IOEvent] = []

    var preparedSlots: [URL] {
        recordedURLs { event in
            if case let .slotPrepared(url) = event { return url }
            return nil
        }
    }

    var readSlots: [URL] {
        recordedURLs { event in
            if case let .slotRead(url) = event { return url }
            return nil
        }
    }

    var checkpointFileBarriers: [URL] {
        recordedURLs { event in
            if case let .checkpointFileSynchronized(url) = event { return url }
            return nil
        }
    }

    var directoryBarriers: [URL] {
        recordedURLs { event in
            if case let .directorySynchronized(url) = event { return url }
            return nil
        }
    }

    func record(_ event: ResponsiveAudioCursorCheckpointStore.IOEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    private func recordedURLs(
        _ transform: (ResponsiveAudioCursorCheckpointStore.IOEvent) -> URL?
    ) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return events.compactMap(transform)
    }
}

private final class FailSelectedDurableWrite: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private let failingCalls: Set<Int>

    init(failingCalls: Set<Int>) {
        self.failingCalls = failingCalls
    }

    func write(_ data: Data, to url: URL) throws {
        lock.lock()
        callCount += 1
        let call = callCount
        lock.unlock()
        if failingCalls.contains(call) { throw InjectedFailure() }
        try data.write(to: url)
    }
}

private final class BlockingDurableWrites: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var completedCalls = 0
    private var recordedDestinations: [URL] = []
    private var recordedGenerations: [UInt64] = []
    private let releaseFirstSemaphore = DispatchSemaphore(value: 0)
    private let releaseSecondSemaphore = DispatchSemaphore(value: 0)

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    var completedCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completedCalls
    }

    var destinations: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recordedDestinations
    }

    var generations: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return recordedGenerations
    }

    func write(_ data: Data, to url: URL) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let generation = dictionary["generation"] as? NSNumber else {
            throw InjectedFailure()
        }
        lock.lock()
        calls += 1
        let call = calls
        recordedDestinations.append(url)
        recordedGenerations.append(generation.uint64Value)
        lock.unlock()

        if call == 1 {
            releaseFirstSemaphore.wait()
        } else if call == 2 {
            releaseSecondSemaphore.wait()
        }
        try data.write(to: url)
        lock.lock()
        completedCalls += 1
        lock.unlock()
    }

    func releaseFirst() {
        releaseFirstSemaphore.signal()
    }

    func releaseSecond() {
        releaseSecondSemaphore.signal()
    }

    func releaseAll() {
        releaseFirstSemaphore.signal()
        releaseSecondSemaphore.signal()
    }
}

@MainActor
private final class PumpTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private struct Fixture {
    let contentRevision: UInt64 = 17
    let interaction: InteractionSpec
    let program: ResponsiveAudioProgramSpec
    let timeline: AudioTimeline
    let snapshot: ResponsiveAudioProgramSnapshot
    let state: JourneyState

    init(
        stage: ResponsiveAudioProgramStage = .interaction,
        generation: UInt64 = 3,
        baseCursor: Int64 = 2_000,
        baseLoop: UInt64 = 0
    ) throws {
        interaction = InteractionSpec(
            id: "fixture-interaction",
            prompt: "Move the material",
            grammar: .trace(
                TraceInteractionSpec(
                    anchors: [
                        NormalizedPoint(x: 0.1, y: 0.1),
                        NormalizedPoint(x: 0.9, y: 0.9),
                    ],
                    tolerance: 0.1
                )
            ),
            completionEffects: [],
            accessibilityID: "fixture-accessibility"
        )
        timeline = AudioTimeline(
            id: stage == .approach ? "approach" : "waiting",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "silence",
                    role: .silence,
                    startSample: 0,
                    durationSamples: 48_000,
                    assetPath: nil,
                    gain: 0
                ),
            ],
            haptics: []
        )
        program = ResponsiveAudioProgramSpec(
            id: "fixture-program",
            scope: ResponsiveAudioProgramScope(
                chapterID: "fixture-chapter",
                arcID: "fixture-arc",
                beatID: "fixture-beat",
                interactionID: interaction.id
            ),
            approachTimelineID: "approach",
            interactionBeds: [
                ResponsiveInteractionAudioBedSpec(
                    phase: .waiting,
                    timelineID: "waiting",
                    layerStates: ResponsiveAudioLayerStateSelection(
                        scoreStateID: nil,
                        soundscapeStateID: nil
                    )
                ),
                ResponsiveInteractionAudioBedSpec(
                    phase: .engaged,
                    timelineID: "engaged",
                    layerStates: ResponsiveAudioLayerStateSelection(
                        scoreStateID: nil,
                        soundscapeStateID: nil
                    )
                ),
                ResponsiveInteractionAudioBedSpec(
                    phase: .resistance,
                    timelineID: "resistance",
                    layerStates: ResponsiveAudioLayerStateSelection(
                        scoreStateID: nil,
                        soundscapeStateID: nil
                    )
                ),
            ],
            consequenceTimelineID: "consequence",
            exitPolicy: .boundedFade(durationSamples: 480)
        )
        snapshot = ResponsiveAudioProgramSnapshot(
            programID: program.id,
            stage: stage,
            interactionPhase: stage == .interaction ? .waiting : nil,
            timelineID: timeline.id,
            cursorSample: baseCursor,
            loopIteration: stage == .interaction ? baseLoop : 0,
            durableCompletionSequence: nil
        )
        state = JourneyState(
            route: .chapter("fixture-chapter"),
            activeChapter: ChapterSession(
                chapterID: "fixture-chapter",
                packageID: "fixture-package",
                contentVersion: SchemaVersion(major: 1),
                arcID: "fixture-arc",
                beatID: "fixture-beat",
                interaction: InteractionRuntimeState(spec: interaction),
                responsiveAudioSnapshot: snapshot,
                responsiveAudioChapterOpenNonce: UUID(
                    uuidString: "00000000-0000-0000-0000-00000000c001"
                ),
                responsiveAudioSessionGeneration: generation,
                responsiveAudioSessionIsActive: true
            )
        )
    }

    func authority() throws -> ResponsiveAudioCursorAuthority {
        try ResponsiveAudioCursorAuthority.make(
            durableState: state,
            contentRevision: contentRevision,
            program: program,
            timeline: timeline
        )
    }

    func snapshot(
        stage: ResponsiveAudioProgramStage? = nil,
        phase: ResponsiveInteractionAudioPhase? = .waiting,
        cursor: Int64,
        loop: UInt64 = 0
    ) -> ResponsiveAudioProgramSnapshot {
        ResponsiveAudioProgramSnapshot(
            programID: program.id,
            stage: stage ?? snapshot.stage,
            interactionPhase: stage == .approach ? nil : phase,
            timelineID: snapshot.timelineID,
            cursorSample: cursor,
            loopIteration: loop,
            causalStage: snapshot.causalStage,
            durableCompletionSequence: snapshot.durableCompletionSequence
        )
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {}
    }
}
