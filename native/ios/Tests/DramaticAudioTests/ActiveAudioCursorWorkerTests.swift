import ContentKit
@testable import DramaticAudio
import Foundation
import JourneyDomain
@testable import ProgressStore
import XCTest

final class ActiveAudioCursorWorkerTests: XCTestCase {
    func testInitialCheckpointMustBecomeDurableBeforeGateAuthorization()
        async throws {
        let fixture = try Fixture()
        let writes = DurableWriteProbe(blockedCall: 1)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: writes.write
        )
        let session = try await store.beginSession(authority: fixture.authority())
        let gate = GateProbe()
        let binding = try binding(
            capture: .verified(fixture.snapshot(cursor: 2_200)),
            graphSample: 100,
            gate: gate
        )
        let worker = ActiveAudioCursorWorker(store: store)
        let token = ActiveAudioCursorActivationToken()

        let start = Task {
            await worker.start(
                token: token,
                binding: binding,
                session: session
            )
        }
        XCTAssertTrue(writes.waitUntilBlocked())
        XCTAssertEqual(gate.authorizedCutoffs, [])
        writes.releaseBlockedCall()

        let protection = try protection(from: await start.value)
        XCTAssertEqual(protection.session, session)
        XCTAssertEqual(
            protection.latestPersistedSnapshot(),
            fixture.snapshot(cursor: 2_200)
        )
        let persisted = PersistedSnapshotProbe()
        protection.setPersistedSnapshotObserver { snapshot in
            persisted.record(snapshot)
        }
        XCTAssertEqual(
            persisted.snapshots,
            [fixture.snapshot(cursor: 2_200)]
        )
        XCTAssertEqual(gate.authorizedCutoffs, [12_100])
        protection.setPersistedSnapshotObserver(nil)
        await worker.stop()
        let terminal = await protection.terminalResult()
        XCTAssertEqual(terminal, .stopped)
    }

    func testSupersededInitialWriteCannotAuthorizeOldGeneration() async throws {
        let fixture = try Fixture()
        let writes = DurableWriteProbe(blockedCall: 1)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: writes.write
        )
        let session = try await store.beginSession(authority: fixture.authority())
        let gate = GateProbe()
        let first = try binding(
            capture: .verified(fixture.snapshot(cursor: 2_200)),
            graphSample: 100,
            gate: gate
        )
        let successor = try binding(
            capture: .verified(fixture.snapshot(cursor: 2_300)),
            graphSample: 100,
            gate: gate
        )
        let worker = ActiveAudioCursorWorker(store: store)
        let obsoleteToken = ActiveAudioCursorActivationToken()
        let successorToken = ActiveAudioCursorActivationToken()

        let obsolete = Task {
            await worker.start(
                token: obsoleteToken,
                binding: first,
                session: session
            )
        }
        XCTAssertTrue(writes.waitUntilBlocked())
        let stoppedObsolete = await worker.stop(
            expectedToken: obsoleteToken
        )
        XCTAssertTrue(stoppedObsolete)
        let successorProtection = try protection(
            from: await worker.start(
                token: successorToken,
                binding: successor,
                session: session
            )
        )
        XCTAssertEqual(gate.authorizedCutoffs, [12_100])

        writes.releaseBlockedCall()
        guard case .superseded = await obsolete.value else {
            return XCTFail("Obsolete generation must report superseded")
        }
        XCTAssertEqual(gate.authorizedCutoffs, [12_100])
        await worker.stop()
        let terminal = await successorProtection.terminalResult()
        XCTAssertEqual(terminal, .stopped)
    }

    func testHandoffSupersedesAnInitialActivationBlockedOnItsFirstWrite()
        async throws {
        let prior = try Fixture(generation: 3, baseCursor: 2_000)
        let successor = try Fixture(generation: 4, baseCursor: 3_000)
        let writes = DurableWriteProbe(blockedCall: 1)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: writes.write
        )
        let priorSession = try await store.beginSession(
            authority: prior.authority()
        )
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(store: store)
        let priorToken = ActiveAudioCursorActivationToken()
        let successorToken = ActiveAudioCursorActivationToken()
        let priorBinding = try binding(
            capture: .verified(prior.snapshot(cursor: 2_200)),
            graphSample: 100,
            gate: gate
        )
        let successorAuthority = try successor.authority()
        let successorBinding = try binding(
            capture: .verified(successor.snapshot(cursor: 3_200)),
            graphSample: 100,
            gate: gate
        )

        let starting = Task {
            await worker.start(
                token: priorToken,
                binding: priorBinding,
                session: priorSession
            )
        }
        XCTAssertTrue(writes.waitUntilBlocked())

        let handoff = Task {
            await worker.handoff(
                from: priorToken,
                activating: successorToken,
                to: successorAuthority,
                binding: successorBinding
            )
        }
        writes.releaseBlockedCall()

        guard case .superseded = await starting.value else {
            return XCTFail("Initial activation must report superseded")
        }
        let successorProtection = try protection(from: await handoff.value)
        XCTAssertNotEqual(successorProtection.session, priorSession)
        XCTAssertEqual(
            successorProtection.latestPersistedSnapshot(),
            successor.snapshot(cursor: 3_200)
        )
        XCTAssertEqual(gate.authorizedCutoffs, [12_100])
        await worker.stop()
    }

    func testAwaitingAuthorityPersistsProjectionWithoutExtendingCutoff()
        async throws {
        let fixture = try Fixture()
        let authority = try fixture.authority()
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let session = try await store.beginSession(authority: authority)
        let clock = LockedClock(now: 1_000)
        let sleeper = ControlledSleeper()
        let feed = FeedProbe([
            .init(
                result: .verified(fixture.snapshot(cursor: 2_200)),
                renderedGraphSample: 100
            ),
            .init(
                result: .awaitingDurableAuthority(
                    projectedOldSnapshot: fixture.snapshot(cursor: 2_300)
                ),
                renderedGraphSample: 200
            ),
        ])
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(
            store: store,
            intervalNanoseconds: 125,
            now: { clock.value },
            sleep: { try await sleeper.sleep($0) }
        )
        let binding = try makeBinding(feed: feed, gate: gate)
        let protection = try protection(
            from: await worker.start(
                token: ActiveAudioCursorActivationToken(),
                binding: binding,
                session: session
            )
        )
        let persisted = PersistedSnapshotProbe()
        protection.setPersistedSnapshotObserver { snapshot in
            persisted.record(snapshot)
        }

        try await waitUntil {
            await sleeper.pendingDurations.contains(125)
        }
        clock.set(1_125)
        let resumed = await sleeper.resumeFirst(duration: 125)
        XCTAssertTrue(resumed)
        try await waitUntil {
            guard feed.callCount >= 2 else { return false }
            return (try? await store.recover(authority: authority))?
                .cursorSample == 2_300
        }

        let recovered = try await store.recover(
            authority: authority
        )
        XCTAssertEqual(
            recovered?.cursorSample,
            2_300
        )
        XCTAssertEqual(
            protection.latestPersistedSnapshot()?.cursorSample,
            2_300
        )
        XCTAssertEqual(
            persisted.snapshots.map(\.cursorSample),
            [2_200, 2_300]
        )
        protection.setPersistedSnapshotObserver(nil)
        XCTAssertEqual(gate.authorizedCutoffs, [12_100])
        await worker.stop()
        await sleeper.resumeAll()
        let terminal = await protection.terminalResult()
        XCTAssertEqual(terminal, .stopped)
    }

    func testPeriodicStoreFailurePublishesOneImmutableTerminalResult()
        async throws {
        let fixture = try Fixture()
        let writes = DurableWriteProbe(failedCall: 2)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: writes.write
        )
        let session = try await store.beginSession(authority: fixture.authority())
        let clock = LockedClock(now: 2_000)
        let sleeper = ControlledSleeper()
        let feed = FeedProbe([
            .init(
                result: .verified(fixture.snapshot(cursor: 2_200)),
                renderedGraphSample: 100
            ),
            .init(
                result: .verified(fixture.snapshot(cursor: 2_300)),
                renderedGraphSample: 200
            ),
        ])
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(
            store: store,
            intervalNanoseconds: 125,
            now: { clock.value },
            sleep: { try await sleeper.sleep($0) }
        )
        let protection = try protection(
            from: await worker.start(
                token: ActiveAudioCursorActivationToken(),
                binding: try makeBinding(feed: feed, gate: gate),
                session: session
            )
        )
        try await waitUntil {
            await sleeper.pendingDurations.contains(125)
        }
        clock.set(2_125)
        let resumed = await sleeper.resumeFirst(duration: 125)
        XCTAssertTrue(resumed)
        try await waitUntil {
            if case .failed = await worker.status { return true }
            return false
        }

        async let first = protection.terminalResult()
        async let second = protection.terminalResult()
        let terminalResults = await (first, second)
        XCTAssertEqual(terminalResults.0, .failed(.persistenceUnavailable))
        XCTAssertEqual(terminalResults.1, .failed(.persistenceUnavailable))
        await worker.stop()
        let terminalAfterStop = await protection.terminalResult()
        XCTAssertEqual(terminalAfterStop, .failed(.persistenceUnavailable))
        XCTAssertEqual(gate.authorizedCutoffs, [12_100])
        await sleeper.resumeAll()
    }

    func testLateDurableCompletionCannotReopenLatchedGate() async throws {
        let fixture = try Fixture()
        let writes = DurableWriteProbe(blockedCall: 2)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: writes.write
        )
        let session = try await store.beginSession(authority: fixture.authority())
        let clock = LockedClock(now: 3_000)
        let sleeper = ControlledSleeper()
        let feed = FeedProbe([
            .init(
                result: .verified(fixture.snapshot(cursor: 2_200)),
                renderedGraphSample: 100
            ),
            .init(
                result: .verified(fixture.snapshot(cursor: 2_300)),
                renderedGraphSample: 200
            ),
        ])
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(
            store: store,
            intervalNanoseconds: 125,
            now: { clock.value },
            sleep: { try await sleeper.sleep($0) }
        )
        let protection = try protection(
            from: await worker.start(
                token: ActiveAudioCursorActivationToken(),
                binding: try makeBinding(feed: feed, gate: gate),
                session: session
            )
        )
        try await waitUntil {
            await sleeper.pendingDurations.contains(125)
        }
        clock.set(3_125)
        let resumed = await sleeper.resumeFirst(duration: 125)
        XCTAssertTrue(resumed)
        XCTAssertTrue(writes.waitUntilBlocked())
        gate.latchClosed()
        writes.releaseBlockedCall()

        let terminal = await protection.terminalResult()
        XCTAssertEqual(terminal, .failed(.gateClosed))
        XCTAssertEqual(gate.authorizedCutoffs, [12_100])
        await sleeper.resumeAll()
    }

    func testWakeAfterCutoffFailsBeforeAnyNewStoreWrite() async throws {
        let fixture = try Fixture()
        let writes = DurableWriteProbe()
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: writes.write
        )
        let session = try await store.beginSession(authority: fixture.authority())
        let clock = LockedClock(now: 3_500)
        let sleeper = ControlledSleeper()
        let feed = FeedProbe([
            .init(
                result: .verified(fixture.snapshot(cursor: 2_200)),
                renderedGraphSample: 100
            ),
            .init(
                result: .verified(fixture.snapshot(cursor: 2_300)),
                renderedGraphSample: 12_101
            ),
        ])
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(
            store: store,
            intervalNanoseconds: 125,
            now: { clock.value },
            sleep: { try await sleeper.sleep($0) }
        )
        let protection = try protection(
            from: await worker.start(
                token: ActiveAudioCursorActivationToken(),
                binding: try makeBinding(feed: feed, gate: gate),
                session: session
            )
        )
        XCTAssertEqual(writes.callCount, 1)
        try await waitUntil {
            await sleeper.pendingDurations.contains(125)
        }
        clock.set(3_625)
        let resumed = await sleeper.resumeFirst(duration: 125)
        XCTAssertTrue(resumed)

        let terminal = await protection.terminalResult()
        XCTAssertEqual(terminal, .failed(.gateClosed))
        XCTAssertEqual(writes.callCount, 1)
        XCTAssertEqual(gate.authorizedCutoffs, [12_100])
        await sleeper.resumeAll()
    }

    func testStopCancelsCadenceWithoutFurtherCaptureOrAuthorization()
        async throws {
        let fixture = try Fixture()
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let session = try await store.beginSession(authority: fixture.authority())
        let clock = LockedClock(now: 4_000)
        let sleeper = ControlledSleeper()
        let feed = FeedProbe([
            .init(
                result: .verified(fixture.snapshot(cursor: 2_200)),
                renderedGraphSample: 100
            ),
            .init(
                result: .verified(fixture.snapshot(cursor: 2_300)),
                renderedGraphSample: 200
            ),
        ])
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(
            store: store,
            intervalNanoseconds: 125,
            now: { clock.value },
            sleep: { try await sleeper.sleep($0) }
        )
        let protection = try protection(
            from: await worker.start(
                token: ActiveAudioCursorActivationToken(),
                binding: try makeBinding(feed: feed, gate: gate),
                session: session
            )
        )
        try await waitUntil {
            await sleeper.pendingDurations.contains(125)
        }
        await worker.stop()
        clock.set(4_125)
        await sleeper.resumeAll()
        for _ in 0 ..< 10 { await Task.yield() }

        XCTAssertEqual(feed.callCount, 1)
        XCTAssertEqual(gate.authorizedCutoffs, [12_100])
        let terminal = await protection.terminalResult()
        XCTAssertEqual(terminal, .stopped)
    }

    func testScopedStopFromSupersededProtectionCannotStopSuccessor()
        async throws {
        let priorFixture = try Fixture(generation: 3, baseCursor: 2_000)
        let successorFixture = try Fixture(generation: 4, baseCursor: 3_000)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let session = try await store.beginSession(
            authority: priorFixture.authority()
        )
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(store: store)
        let priorToken = ActiveAudioCursorActivationToken()
        let successorToken = ActiveAudioCursorActivationToken()
        let prior = try protection(
            from: await worker.start(
                token: priorToken,
                binding: try binding(
                    capture: .verified(
                        priorFixture.snapshot(cursor: 2_200)
                    ),
                    graphSample: 100,
                    gate: gate
                ),
                session: session
            )
        )
        let successor = try protection(
            from: await worker.handoff(
                from: priorToken,
                activating: successorToken,
                to: successorFixture.authority(),
                binding: try binding(
                    capture: .verified(
                        successorFixture.snapshot(cursor: 3_200)
                    ),
                    graphSample: 200,
                    gate: gate
                )
            )
        )

        let priorTerminal = await prior.terminalResult()
        XCTAssertEqual(priorTerminal, .superseded)
        let obsoleteStopSucceeded = await worker.stop(prior)
        XCTAssertFalse(obsoleteStopSucceeded)
        if case .running = await worker.status {
            // Expected: the scoped obsolete cleanup left the successor alive.
        } else {
            XCTFail("Obsolete scoped stop changed the successor status")
        }
        let successorStopSucceeded = await worker.stop(successor)
        XCTAssertTrue(successorStopSucceeded)
        let successorTerminal = await successor.terminalResult()
        XCTAssertEqual(successorTerminal, .stopped)
    }

    func testObsoleteHandoffTokenCannotReplaceCurrentSuccessor()
        async throws {
        let prior = try Fixture(generation: 3, baseCursor: 2_000)
        let successor = try Fixture(generation: 4, baseCursor: 3_000)
        let intruder = try Fixture(generation: 5, baseCursor: 4_000)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let session = try await store.beginSession(
            authority: prior.authority()
        )
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(store: store)
        let priorToken = ActiveAudioCursorActivationToken()
        let successorToken = ActiveAudioCursorActivationToken()
        let priorProtection = try protection(
            from: await worker.start(
                token: priorToken,
                binding: try binding(
                    capture: .verified(prior.snapshot(cursor: 2_200)),
                    graphSample: 100,
                    gate: gate
                ),
                session: session
            )
        )
        let successorProtection = try protection(
            from: await worker.handoff(
                from: priorToken,
                activating: successorToken,
                to: successor.authority(),
                binding: try binding(
                    capture: .verified(successor.snapshot(cursor: 3_200)),
                    graphSample: 200,
                    gate: gate
                )
            )
        )

        let stale = await worker.handoff(
            from: priorToken,
            activating: ActiveAudioCursorActivationToken(),
            to: try intruder.authority(),
            binding: try binding(
                capture: .verified(intruder.snapshot(cursor: 4_200)),
                graphSample: 300,
                gate: gate
            )
        )
        guard case .superseded = stale else {
            return XCTFail("Obsolete handoff must not replace the successor")
        }
        let priorTerminal = await priorProtection.terminalResult()
        XCTAssertEqual(priorTerminal, .superseded)
        if case .running = await worker.status {
            // Expected: the successor still owns the cadence.
        } else {
            XCTFail("Obsolete handoff changed successor status")
        }
        let storeOwnsSuccessor = await store.owns(
            successorProtection.session
        )
        XCTAssertTrue(storeOwnsSuccessor)
        let stoppedSuccessor = await worker.stop(successorProtection)
        XCTAssertTrue(stoppedSuccessor)
    }

    func testActivationTokenCannotBeReusedAfterStop() async throws {
        let fixture = try Fixture()
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let session = try await store.beginSession(
            authority: fixture.authority()
        )
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(store: store)
        let token = ActiveAudioCursorActivationToken()
        let protection = try protection(
            from: await worker.start(
                token: token,
                binding: try binding(
                    capture: .verified(fixture.snapshot(cursor: 2_200)),
                    graphSample: 100,
                    gate: gate
                ),
                session: session
            )
        )
        let didStop = await worker.stop(protection)
        XCTAssertTrue(didStop)

        let reused = await worker.start(
            token: token,
            binding: try binding(
                capture: .verified(fixture.snapshot(cursor: 2_300)),
                graphSample: 200,
                gate: gate
            ),
            session: session
        )
        guard case .failed(.activationTokenReused) = reused else {
            return XCTFail("A retired activation token must be single-use")
        }
    }

    func testNestedHandoffWhileSuccessorWriteIsBlockedDoesNotDamageIt()
        async throws {
        let prior = try Fixture(generation: 3, baseCursor: 2_000)
        let successor = try Fixture(generation: 4, baseCursor: 3_000)
        let queued = try Fixture(generation: 5, baseCursor: 4_000)
        let writes = DurableWriteProbe(blockedCall: 2)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: writes.write
        )
        let session = try await store.beginSession(
            authority: prior.authority()
        )
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(store: store)
        let priorToken = ActiveAudioCursorActivationToken()
        let successorToken = ActiveAudioCursorActivationToken()
        _ = try protection(
            from: await worker.start(
                token: priorToken,
                binding: try binding(
                    capture: .verified(prior.snapshot(cursor: 2_200)),
                    graphSample: 100,
                    gate: gate
                ),
                session: session
            )
        )
        let successorAuthority = try successor.authority()
        let successorBinding = try binding(
            capture: .verified(successor.snapshot(cursor: 3_200)),
            graphSample: 200,
            gate: gate
        )
        let handoff = Task {
            await worker.handoff(
                from: priorToken,
                activating: successorToken,
                to: successorAuthority,
                binding: successorBinding
            )
        }
        XCTAssertTrue(writes.waitUntilBlocked())

        let nested = await worker.handoff(
            from: successorToken,
            activating: ActiveAudioCursorActivationToken(),
            to: try queued.authority(),
            binding: try binding(
                capture: .verified(queued.snapshot(cursor: 4_200)),
                graphSample: 300,
                gate: gate
            )
        )
        guard case .failed(.activationInProgress) = nested else {
            writes.releaseBlockedCall()
            return XCTFail("A nested handoff must wait for the current one")
        }

        writes.releaseBlockedCall()
        let successorProtection = try protection(from: await handoff.value)
        let storeOwnsSuccessor = await store.owns(
            successorProtection.session
        )
        XCTAssertTrue(storeOwnsSuccessor)
        let didStop = await worker.stop(successorProtection)
        XCTAssertTrue(didStop)
    }

    func testScopedStopDuringBlockedHandoffRetiresLateSuccessor()
        async throws {
        let prior = try Fixture(generation: 3, baseCursor: 2_000)
        let successor = try Fixture(generation: 4, baseCursor: 3_000)
        let writes = DurableWriteProbe(blockedCall: 2)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: writes.write
        )
        let session = try await store.beginSession(
            authority: prior.authority()
        )
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(store: store)
        let priorToken = ActiveAudioCursorActivationToken()
        let successorToken = ActiveAudioCursorActivationToken()
        _ = try protection(
            from: await worker.start(
                token: priorToken,
                binding: try binding(
                    capture: .verified(prior.snapshot(cursor: 2_200)),
                    graphSample: 100,
                    gate: gate
                ),
                session: session
            )
        )
        let successorAuthority = try successor.authority()
        let successorBinding = try binding(
            capture: .verified(successor.snapshot(cursor: 3_200)),
            graphSample: 200,
            gate: gate
        )
        let handoff = Task {
            await worker.handoff(
                from: priorToken,
                activating: successorToken,
                to: successorAuthority,
                binding: successorBinding
            )
        }
        XCTAssertTrue(writes.waitUntilBlocked())
        let didStop = await worker.stop(expectedToken: successorToken)
        XCTAssertTrue(didStop)
        writes.releaseBlockedCall()

        guard case .superseded = await handoff.value else {
            return XCTFail("Stopped handoff must resolve as superseded")
        }
        let recordedSuccessor = await worker
            .mostRecentHandoffSuccessorSessionForTesting()
        let successorSession = try XCTUnwrap(recordedSuccessor)
        let storeOwnsSuccessor = await store.owns(successorSession)
        XCTAssertFalse(storeOwnsSuccessor)
    }

    func testReusedSuccessorTokenLeavesPriorActivationRunning()
        async throws {
        let prior = try Fixture(generation: 3, baseCursor: 2_000)
        let successor = try Fixture(generation: 4, baseCursor: 3_000)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let session = try await store.beginSession(
            authority: prior.authority()
        )
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(store: store)
        let token = ActiveAudioCursorActivationToken()
        let priorProtection = try protection(
            from: await worker.start(
                token: token,
                binding: try binding(
                    capture: .verified(prior.snapshot(cursor: 2_200)),
                    graphSample: 100,
                    gate: gate
                ),
                session: session
            )
        )

        let reused = await worker.handoff(
            from: token,
            activating: token,
            to: try successor.authority(),
            binding: try binding(
                capture: .verified(successor.snapshot(cursor: 3_200)),
                graphSample: 200,
                gate: gate
            )
        )
        guard case .failed(.activationTokenReused) = reused else {
            return XCTFail("A handoff cannot reuse the active token")
        }
        if case .running = await worker.status {
            // Expected: validation failed before ownership changed.
        } else {
            XCTFail("Token reuse changed the prior activation status")
        }
        let didStop = await worker.stop(priorProtection)
        XCTAssertTrue(didStop)
    }

    func testHandoffSeedsSuccessorBeforeExtendingItsCutoff() async throws {
        let prior = try Fixture(generation: 3, baseCursor: 2_000)
        let successor = try Fixture(generation: 4, baseCursor: 3_000)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let priorSession = try await store.beginSession(
            authority: prior.authority()
        )
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(store: store)
        let priorToken = ActiveAudioCursorActivationToken()
        let successorToken = ActiveAudioCursorActivationToken()
        let priorProtection = try protection(
            from: await worker.start(
                token: priorToken,
                binding: try binding(
                    capture: .verified(prior.snapshot(cursor: 2_200)),
                    graphSample: 100,
                    gate: gate
                ),
                session: priorSession
            )
        )
        let successorProtection = try protection(
            from: await worker.handoff(
                from: priorToken,
                activating: successorToken,
                to: successor.authority(),
                binding: try binding(
                    capture: .verified(successor.snapshot(cursor: 3_200)),
                    graphSample: 300,
                    gate: gate
                )
            )
        )

        let priorTerminal = await priorProtection.terminalResult()
        XCTAssertEqual(priorTerminal, .superseded)
        XCTAssertEqual(gate.authorizedCutoffs, [12_100, 12_300])
        XCTAssertNotEqual(successorProtection.session, priorSession)
        XCTAssertEqual(
            successorProtection.latestPersistedSnapshot(),
            successor.snapshot(cursor: 3_200)
        )
        let storeOwnsProtectionSession = await store.owns(
            successorProtection.session
        )
        XCTAssertTrue(storeOwnsProtectionSession)
        let recovered = try await store.recover(
            authority: successor.authority()
        )
        XCTAssertEqual(
            recovered?.cursorSample,
            3_200
        )
        await worker.stop()
        let successorTerminal = await successorProtection.terminalResult()
        XCTAssertEqual(successorTerminal, .stopped)
    }

    func testGateLatchingAfterHandoffWriteRetiresActiveSuccessor()
        async throws {
        let prior = try Fixture(generation: 3, baseCursor: 2_000)
        let successor = try Fixture(generation: 4, baseCursor: 3_000)
        let writes = DurableWriteProbe(blockedCall: 2)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory(),
            durableWrite: writes.write
        )
        let priorSession = try await store.beginSession(
            authority: prior.authority()
        )
        let gate = GateProbe()
        let worker = ActiveAudioCursorWorker(store: store)
        let priorToken = ActiveAudioCursorActivationToken()
        let successorToken = ActiveAudioCursorActivationToken()
        let priorProtection = try protection(
            from: await worker.start(
                token: priorToken,
                binding: try binding(
                    capture: .verified(prior.snapshot(cursor: 2_200)),
                    graphSample: 100,
                    gate: gate
                ),
                session: priorSession
            )
        )

        let successorAuthority = try successor.authority()
        let successorBinding = try binding(
            capture: .verified(successor.snapshot(cursor: 3_200)),
            graphSample: 300,
            gate: gate
        )
        let handoff = Task {
            await worker.handoff(
                from: priorToken,
                activating: successorToken,
                to: successorAuthority,
                binding: successorBinding
            )
        }
        XCTAssertTrue(writes.waitUntilBlocked())
        gate.latchClosed()
        writes.releaseBlockedCall()
        guard case .failed(.gateClosed) = await handoff.value else {
            return XCTFail("Latched gate must fail the handoff")
        }
        let recordedSuccessor = await worker
            .mostRecentHandoffSuccessorSessionForTesting()
        let successorSession = try XCTUnwrap(recordedSuccessor)
        let storeStillOwnsSuccessor = await store.owns(successorSession)

        XCTAssertFalse(storeStillOwnsSuccessor)
        let priorTerminal = await priorProtection.terminalResult()
        XCTAssertEqual(priorTerminal, .superseded)
        XCTAssertEqual(gate.authorizedCutoffs, [12_100])
    }

    func testScheduleOverflowAfterHandoffRetiresActiveSuccessor()
        async throws {
        let prior = try Fixture(generation: 3, baseCursor: 2_000)
        let successor = try Fixture(generation: 4, baseCursor: 3_000)
        let store = try ResponsiveAudioCursorCheckpointStore(
            directoryURL: temporaryDirectory()
        )
        let priorSession = try await store.beginSession(
            authority: prior.authority()
        )
        let clock = LockedClock(now: UInt64.max - 250)
        let sleeper = ControlledSleeper()
        let gate = GateProbe()
        let priorToken = ActiveAudioCursorActivationToken()
        let successorToken = ActiveAudioCursorActivationToken()
        let worker = ActiveAudioCursorWorker(
            store: store,
            intervalNanoseconds: 125,
            now: { clock.value },
            sleep: { try await sleeper.sleep($0) }
        )
        let priorProtection = try protection(
            from: await worker.start(
                token: priorToken,
                binding: try binding(
                    capture: .verified(prior.snapshot(cursor: 2_200)),
                    graphSample: 100,
                    gate: gate
                ),
                session: priorSession
            )
        )
        try await waitUntil {
            await sleeper.pendingDurations.contains(125)
        }
        clock.set(UInt64.max)
        let successorAuthority = try successor.authority()

        let handoff = await worker.handoff(
            from: priorToken,
            activating: successorToken,
            to: successorAuthority,
            binding: try binding(
                capture: .verified(successor.snapshot(cursor: 3_200)),
                graphSample: 300,
                gate: gate
            )
        )
        guard case .failed(.scheduleOverflow) = handoff else {
            return XCTFail("Overflow must fail the handoff")
        }
        let recordedSuccessor = await worker
            .mostRecentHandoffSuccessorSessionForTesting()
        let successorSession = try XCTUnwrap(recordedSuccessor)
        let storeStillOwnsSuccessor = await store.owns(successorSession)

        XCTAssertFalse(storeStillOwnsSuccessor)
        let priorTerminal = await priorProtection.terminalResult()
        XCTAssertEqual(priorTerminal, .superseded)
        await sleeper.resumeAll()
    }

    private func binding(
        capture: ResponsiveAudioDurabilityCaptureResult,
        graphSample: Int64,
        gate: GateProbe
    ) throws -> ActiveAudioCursorBinding {
        try ActiveAudioCursorBinding(
            renderedGraphSampleRate: 48_000,
            feed: ActiveAudioCursorFeed {
                ActiveAudioCursorFeedCapture(
                    result: capture,
                    renderedGraphSample: graphSample
                )
            },
            gate: gate
        )
    }

    private func makeBinding(
        feed: FeedProbe,
        gate: GateProbe
    ) throws -> ActiveAudioCursorBinding {
        try ActiveAudioCursorBinding(
            renderedGraphSampleRate: 48_000,
            feed: ActiveAudioCursorFeed(capture: feed.next),
            gate: gate
        )
    }

    private func protection(
        from result: ActiveAudioCursorWorker.ActivationResult
    ) throws -> ActiveAudioCursorProtection {
        guard case let .protecting(protection) = result else {
            throw UnexpectedActivation(result)
        }
        return protection
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "active-audio-cursor-worker-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds
            + timeoutNanoseconds
        while !(await condition()) {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                XCTFail("Timed out waiting for worker")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private struct UnexpectedActivation: Error {
    let result: ActiveAudioCursorWorker.ActivationResult
    init(_ result: ActiveAudioCursorWorker.ActivationResult) {
        self.result = result
    }
}

private struct InjectedWriteFailure: Error {}

private final class PersistedSnapshotProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ResponsiveAudioProgramSnapshot] = []

    var snapshots: [ResponsiveAudioProgramSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ snapshot: ResponsiveAudioProgramSnapshot) {
        lock.lock()
        recorded.append(snapshot)
        lock.unlock()
    }
}

private final class DurableWriteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let blockedCall: Int?
    private let failedCall: Int?
    private var calls = 0
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    init(blockedCall: Int? = nil, failedCall: Int? = nil) {
        self.blockedCall = blockedCall
        self.failedCall = failedCall
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func write(_ data: Data, _ url: URL) throws {
        lock.lock()
        calls += 1
        let call = calls
        lock.unlock()
        if call == blockedCall {
            entered.signal()
            release.wait()
        }
        if call == failedCall { throw InjectedWriteFailure() }
        try data.write(to: url, options: [])
    }

    func waitUntilBlocked(timeout: TimeInterval = 1) -> Bool {
        entered.wait(timeout: .now() + timeout) == .success
    }

    func releaseBlockedCall() {
        release.signal()
    }
}

private final class GateProbe: ActiveAudioCursorGateAuthorizing,
    @unchecked Sendable {
    private let lock = NSLock()
    private var cutoffs: [Int64] = []
    private var isLatchedClosed = false
    private var currentCutoff: Int64 = 100

    var authorizedCutoffs: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return cutoffs
    }

    func claimCapture(atRenderedGraphSample sample: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isLatchedClosed, sample <= currentCutoff else {
            isLatchedClosed = true
            return false
        }
        return true
    }

    func authorizeAudio(throughRenderedGraphSample cutoff: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isLatchedClosed,
              cutoff >= currentCutoff else {
            return false
        }
        currentCutoff = cutoff
        cutoffs.append(cutoff)
        return true
    }

    func latchClosed() {
        lock.lock()
        isLatchedClosed = true
        lock.unlock()
    }
}

private final class FeedProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let captures: [ActiveAudioCursorFeedCapture]
    private var index = 0

    init(_ captures: [ActiveAudioCursorFeedCapture]) {
        precondition(!captures.isEmpty)
        self.captures = captures
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return index
    }

    func next() throws -> ActiveAudioCursorFeedCapture {
        lock.lock()
        defer { lock.unlock() }
        let capture = captures[min(index, captures.count - 1)]
        index += 1
        return capture
    }
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now: UInt64

    init(now: UInt64) { self.now = now }

    var value: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return now
    }

    func set(_ value: UInt64) {
        lock.lock()
        now = value
        lock.unlock()
    }
}

private actor ControlledSleeper {
    private struct Pending {
        let duration: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var pending: [Pending] = []

    var pendingDurations: [UInt64] { pending.map(\.duration) }

    func sleep(_ duration: UInt64) async throws {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(.init(duration: duration, continuation: continuation))
        }
    }

    func resumeFirst(duration: UInt64) -> Bool {
        guard let index = pending.firstIndex(where: {
            $0.duration == duration
        }) else { return false }
        pending.remove(at: index).continuation.resume()
        return true
    }

    func resumeAll() {
        let pending = pending
        self.pending.removeAll()
        for sleeper in pending { sleeper.continuation.resume() }
    }
}

private struct Fixture {
    let interaction: InteractionSpec
    let program: ResponsiveAudioProgramSpec
    let timeline: AudioTimeline
    let state: JourneyState
    let baseSnapshot: ResponsiveAudioProgramSnapshot

    init(generation: UInt64 = 3, baseCursor: Int64 = 2_000) throws {
        interaction = InteractionSpec(
            id: "worker-interaction",
            prompt: "Move",
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
            accessibilityID: "worker-interaction"
        )
        timeline = AudioTimeline(
            id: "waiting",
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
            id: "worker-program",
            scope: ResponsiveAudioProgramScope(
                chapterID: "worker-chapter",
                arcID: "worker-arc",
                beatID: "worker-beat",
                interactionID: interaction.id
            ),
            approachTimelineID: "approach",
            interactionBeds: [
                .init(
                    phase: .waiting,
                    timelineID: timeline.id,
                    layerStates: .init(
                        scoreStateID: nil,
                        soundscapeStateID: nil
                    )
                ),
            ],
            consequenceTimelineID: "consequence",
            exitPolicy: .boundedFade(durationSamples: 480)
        )
        baseSnapshot = ResponsiveAudioProgramSnapshot(
            programID: program.id,
            stage: .interaction,
            interactionPhase: .waiting,
            timelineID: timeline.id,
            cursorSample: baseCursor,
            loopIteration: 0,
            durableCompletionSequence: nil
        )
        state = JourneyState(
            route: .chapter("worker-chapter"),
            activeChapter: ChapterSession(
                chapterID: "worker-chapter",
                packageID: "worker-package",
                contentVersion: SchemaVersion(major: 1),
                arcID: "worker-arc",
                beatID: "worker-beat",
                interaction: InteractionRuntimeState(spec: interaction),
                responsiveAudioSnapshot: baseSnapshot,
                responsiveAudioChapterOpenNonce: UUID(
                    uuidString: "00000000-0000-0000-0000-00000000c011"
                ),
                responsiveAudioSessionGeneration: generation,
                responsiveAudioSessionIsActive: true
            )
        )
    }

    func authority() throws -> ResponsiveAudioCursorAuthority {
        try ResponsiveAudioCursorAuthority.make(
            durableState: state,
            contentRevision: 17,
            program: program,
            timeline: timeline
        )
    }

    func snapshot(cursor: Int64) -> ResponsiveAudioProgramSnapshot {
        ResponsiveAudioProgramSnapshot(
            programID: program.id,
            stage: .interaction,
            interactionPhase: .waiting,
            timelineID: timeline.id,
            cursorSample: cursor,
            loopIteration: 0,
            durableCompletionSequence: nil
        )
    }
}
