import ContentKit
@testable import JourneyPersistence
import XCTest

@MainActor
final class ResponsiveAudioCursorCheckpointPumpTests: XCTestCase {
    func testSlowPreRenderPreparationDoesNotAgeUnarmedCursor() async throws {
        var persisted = 0
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 5_000_000,
            maximumAgeNanoseconds: 25_000_000
        )

        // This stands in for synchronous AVAudioSession and graph setup. No
        // sample is renderable yet, so no cursor deadline is armed.
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(failCount, 0)
        XCTAssertFalse(pump.isRunning)

        let startResult = await pump.start(
            capture: { .verified(Self.snapshot(cursor: 240)) },
            persist: { _, _ in persisted += 1 },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(startResult, .protecting)
        let initialVerification = await pump.awaitInitialVerification()
        XCTAssertTrue(initialVerification)
        XCTAssertEqual(persisted, 1)
        XCTAssertEqual(failCount, 0)
        XCTAssertTrue(pump.isRunning)
        pump.stop()
    }

    func testFirstCaptureAndPersistBeginWithoutAnIntervalSleep() async throws {
        var captureCount = 0
        var persistCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 125_000_000,
            maximumAgeNanoseconds: 250_000_000
        )

        let startResult = await pump.start(
            capture: {
                captureCount += 1
                return .verified(Self.snapshot(cursor: 241))
            },
            persist: { _, _ in persistCount += 1 },
            failClosed: { XCTFail("Immediate persistence must not miss its deadline") }
        )
        XCTAssertEqual(startResult, .protecting)

        let initialVerification = await pump.awaitInitialVerification()
        XCTAssertTrue(initialVerification)
        XCTAssertEqual(captureCount, 1)
        XCTAssertEqual(persistCount, 1)
        pump.stop()
    }

    func testWriteLatencyDoesNotShiftAbsoluteCaptureDeadline() async throws {
        let clock = LockedMonotonicClock(now: 1_000)
        let sleeper = ControlledPumpSleeper()
        var captureTimes: [UInt64] = []
        var persistCount = 0
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 125,
            maximumAgeNanoseconds: 1_000,
            now: { clock.now },
            sleep: { try await sleeper.sleep($0) }
        )

        let startResult = await pump.start(
            capture: {
                captureTimes.append(clock.now)
                return .verified(Self.snapshot(cursor: Int64(captureTimes.count)))
            },
            persist: { _, _ in
                persistCount += 1
                clock.advance(by: 40)
            },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(startResult, .protecting)

        let initialVerification = await pump.awaitInitialVerification()
        XCTAssertTrue(initialVerification)
        try await waitUntilAsync {
            await sleeper.pendingDurations.contains(85)
        }
        XCTAssertEqual(captureTimes, [1_000])

        clock.setNow(1_125)
        let resumedFirstDeadline = await sleeper.resumeFirst(duration: 85)
        XCTAssertTrue(resumedFirstDeadline)
        try await waitUntil { captureTimes.count == 2 }

        XCTAssertEqual(captureTimes, [1_000, 1_125])
        XCTAssertEqual(persistCount, 2)
        XCTAssertEqual(failCount, 0)

        pump.stop()
        await sleeper.resumeAll()
    }

    func testSlowPersistCoalescesMissedTicksIntoOneFreshCapture()
        async throws {
        let clock = LockedMonotonicClock(now: 5_000)
        let sleeper = ControlledPumpSleeper()
        let firstPersist = PersistBarrier()
        var captureTimes: [UInt64] = []
        var persistCount = 0
        var activePersistCount = 0
        var maximumActivePersistCount = 0
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 125,
            maximumAgeNanoseconds: 1_000,
            now: { clock.now },
            sleep: { try await sleeper.sleep($0) }
        )

        let startTask = Task { @MainActor in
            await pump.start(
                capture: {
                    captureTimes.append(clock.now)
                    return .verified(
                        Self.snapshot(cursor: Int64(captureTimes.count))
                    )
                },
                persist: { _, _ in
                    persistCount += 1
                    activePersistCount += 1
                    maximumActivePersistCount = max(
                        maximumActivePersistCount,
                        activePersistCount
                    )
                    if persistCount == 1 {
                        await firstPersist.enterAndWait()
                    }
                    activePersistCount -= 1
                },
                failClosed: { failCount += 1 }
            )
        }

        await firstPersist.waitUntilEntered()
        clock.setNow(5_300)
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(captureTimes, [5_000])
        XCTAssertEqual(activePersistCount, 1)

        await firstPersist.release()
        let startResult = await startTask.value
        XCTAssertEqual(startResult, .protecting)
        let initialVerification = await pump.awaitInitialVerification()
        XCTAssertTrue(initialVerification)
        try await waitUntil { captureTimes.count == 2 && persistCount == 2 }
        try await waitUntilAsync {
            await sleeper.pendingDurations.contains(75)
        }

        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(
            captureTimes,
            [5_000, 5_300],
            "Ticks at 5,125 and 5,250 must become one fresh capture"
        )
        XCTAssertEqual(maximumActivePersistCount, 1)
        XCTAssertEqual(failCount, 0)

        clock.setNow(5_375)
        let resumedNextDeadline = await sleeper.resumeFirst(duration: 75)
        XCTAssertTrue(resumedNextDeadline)
        try await waitUntil { captureTimes.count == 3 }
        XCTAssertEqual(captureTimes, [5_000, 5_300, 5_375])

        pump.stop()
        await sleeper.resumeAll()
    }

    func testWriteCompletingWithin249MillisecondsDoesNotPause() async throws {
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 125_000_000,
            maximumAgeNanoseconds: 250_000_000
        )
        let startResult = await pump.start(
            capture: { .verified(Self.snapshot(cursor: 242)) },
            persist: { _, _ in
                try await Task.sleep(nanoseconds: 200_000_000)
            },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(startResult, .protecting)

        let initialVerification = await pump.awaitInitialVerification()
        XCTAssertTrue(initialVerification)
        XCTAssertEqual(failCount, 0)
        XCTAssertTrue(pump.isRunning)
        pump.stop()
    }

    func testAsyncPersistCompletionCannotLeapfrogExpiredWatchdogBaseline()
        async {
        let clock = LockedMonotonicClock(now: 10_000)
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 125,
            maximumAgeNanoseconds: 250,
            now: { clock.now },
            sleep: { _ in
                try await Task.sleep(nanoseconds: UInt64.max)
            }
        )

        let startResult = await pump.start(
            capture: { .verified(Self.snapshot(cursor: 243)) },
            persist: { _, _ in clock.setNow(10_250) },
            failClosed: { failCount += 1 }
        )

        XCTAssertEqual(startResult, .failed)
        XCTAssertEqual(failCount, 1)
        XCTAssertTrue(pump.didFailClosed)
#if DEBUG
        XCTAssertEqual(
            pump.failureDiagnosticForTesting?.detail,
            "persist-completed-after-recoverable-deadline"
        )
#endif
    }

    func testSuccessfulWritesKeepCursorWithinBoundUntilStopped() async throws {
        var persisted: [Int64] = []
        var cursor: Int64 = 0
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 10_000_000,
            maximumAgeNanoseconds: 40_000_000
        )
        let startResult = await pump.start(
            capture: {
                cursor += 480
                return .verified(Self.snapshot(cursor: cursor))
            },
            persist: { snapshot, _ in persisted.append(snapshot.cursorSample) },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(startResult, .protecting)
        try await waitUntil { persisted.count >= 3 }
        XCTAssertEqual(failCount, 0)
        XCTAssertTrue(pump.isRunning)
        XCTAssertEqual(persisted, persisted.sorted())

        pump.stop()
        let stoppedCount = persisted.count
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(persisted.count, stoppedCount)
        XCTAssertFalse(pump.isRunning)
    }

    func testWriteFailurePausesOnceBeforeMaximumAgeCanBeExceeded() async throws {
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 5_000_000,
            maximumAgeNanoseconds: 25_000_000
        )
        let startResult = await pump.start(
            capture: { .verified(Self.snapshot(cursor: 1_000)) },
            persist: { _, _ in throw PumpFailure() },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(startResult, .failed)
        try await waitUntil { failCount == 1 }
        XCTAssertTrue(pump.didFailClosed)
        XCTAssertFalse(pump.isRunning)
#if DEBUG
        XCTAssertEqual(
            pump.failureDiagnosticForTesting?.origin,
            .writerPersist
        )
#endif
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(failCount, 1)
    }

    func test250MillisecondDeadlinePausesWhileWriterStillWaits() async throws {
        var failCount = 0
        let barrier = PersistBarrier()
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 125_000_000,
            maximumAgeNanoseconds: 250_000_000
        )
        let startTask = Task { @MainActor in
            await pump.start(
                capture: { .verified(Self.snapshot(cursor: 1_500)) },
                persist: { _, _ in
                    await barrier.enterAndWait()
                },
                failClosed: { failCount += 1 }
            )
        }

        await barrier.waitUntilEntered()
        try await waitUntil(timeoutNanoseconds: 500_000_000) {
            failCount == 1
        }
        XCTAssertEqual(failCount, 1)
        XCTAssertFalse(pump.isRunning)
#if DEBUG
        XCTAssertEqual(
            pump.failureDiagnosticForTesting?.origin,
            .writerDeadline
        )
        XCTAssertEqual(
            pump.failureDiagnosticForTesting?.detail,
            "writer-watchdog"
        )
        XCTAssertNotNil(
            pump.failureDiagnosticForTesting?
                .writerPersistStartedAtNanoseconds
        )
#endif
        let writerWasReleased = await barrier.hasBeenReleased
        XCTAssertFalse(writerWasReleased)

        await barrier.release()
        let startResult = await startTask.value
        XCTAssertEqual(startResult, .failed)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(failCount, 1)
    }

    func testAutomaticBoundaryBeforeFirstPersistCannotTearDownSuccessorGeneration()
        async throws {
        let oldWrite = PersistBarrier()
        var oldFailCount = 0
        var successorPersistCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 25_000_000,
            maximumAgeNanoseconds: 250_000_000
        )
        let oldStart = Task { @MainActor in
            await pump.start(
                capture: { .verified(Self.snapshot(cursor: 1_600)) },
                persist: { _, _ in await oldWrite.enterAndWait() },
                failClosed: { oldFailCount += 1 }
            )
        }
        await oldWrite.waitUntilEntered()

        // The automatic boundary installs the next durable generation while
        // the old sidecar fsync remains admitted.
        let successorStart = await pump.start(
            capture: { .verified(Self.snapshot(cursor: 1_700)) },
            persist: { _, _ in successorPersistCount += 1 },
            failClosed: { XCTFail("A stale old completion cannot fail the successor") }
        )
        XCTAssertEqual(successorStart, .protecting)
        let successorVerified = await pump.awaitInitialVerification()
        XCTAssertTrue(successorVerified)
        XCTAssertEqual(successorPersistCount, 1)
        XCTAssertTrue(pump.isRunning)

        await oldWrite.release()
        let obsoleteStartResult = await oldStart.value
        XCTAssertEqual(obsoleteStartResult, .superseded)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(oldFailCount, 0)
        XCTAssertTrue(pump.isRunning)
        pump.stop()
    }

    func testAwaitingAuthorityPersistsProjectionButCannotRefresh250msWatchdog()
        async throws {
        var persisted = 0
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump()
        let startResult = await pump.start(
            capture: {
                .awaitingDurableAuthority(
                    projectedOldSnapshot: Self.snapshot(cursor: 2_000)
                )
            },
            persist: { _, _ in persisted += 1 },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(startResult, .protecting)

        try await waitUntil(timeoutNanoseconds: 600_000_000) {
            failCount == 1
        }
        XCTAssertGreaterThan(persisted, 0)
        XCTAssertTrue(pump.didFailClosed)
        XCTAssertFalse(pump.isRunning)
    }

    func testVerifiedHandoffInside250msPreservesContinuousFreshness()
        async throws {
        let now = DispatchTime.now().uptimeNanoseconds
        let baseline = now - 100_000_000
        var persisted = 0
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 20_000_000,
            maximumAgeNanoseconds: 250_000_000
        )
        let startResult = await pump.start(
            lastVerifiedCaptureNanoseconds: baseline,
            capture: { .verified(Self.snapshot(cursor: 2_500)) },
            persist: { _, _ in persisted += 1 },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(startResult, .protecting)

        try await waitUntil { persisted > 0 }
        XCTAssertEqual(failCount, 0)
        XCTAssertTrue(pump.isRunning)
        XCTAssertGreaterThan(
            try XCTUnwrap(pump.lastVerifiedCaptureNanoseconds),
            baseline
        )
        pump.stop()
    }

    func testHandoffDeadlinePausesBeforeGatedHandoffReturns() async throws {
        let handoffWrite = PersistBarrier()
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 125_000_000,
            maximumAgeNanoseconds: 250_000_000
        )
        let startResult = await pump.start(
            capture: { .verified(Self.snapshot(cursor: 2_600)) },
            persist: { _, _ in },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(startResult, .protecting)
        let initialVerified = await pump.awaitInitialVerification()
        XCTAssertTrue(initialVerified)

        let lastRecoverableCapture = try XCTUnwrap(
            pump.lastVerifiedCaptureNanoseconds
        )
        let capturedAt = DispatchTime.now().uptimeNanoseconds
        let token = pump.beginHandoffDeadline(
            candidateCapturedAtNanoseconds: capturedAt,
            lastRecoverableCaptureNanoseconds: lastRecoverableCapture,
            failClosed: { failCount += 1 }
        )
        XCTAssertNotNil(token)
        let admittedHandoff = Task {
            await handoffWrite.enterAndWait()
        }
        await handoffWrite.waitUntilEntered()

        try await waitUntil(timeoutNanoseconds: 500_000_000) {
            failCount == 1
        }
        XCTAssertTrue(pump.didFailClosed)
        XCTAssertFalse(pump.isRunning)
#if DEBUG
        XCTAssertEqual(
            pump.failureDiagnosticForTesting?.origin,
            .handoffDeadline
        )
        XCTAssertEqual(
            pump.failureDiagnosticForTesting?.detail,
            "handoff-watchdog"
        )
#endif
        let writeWasReleased = await handoffWrite.hasBeenReleased
        XCTAssertFalse(writeWasReleased)

        await handoffWrite.release()
        await admittedHandoff.value
        XCTAssertEqual(failCount, 1)
    }

    func testUndurableCandidateCannotRefreshExpiredRecoverableDeadline()
        async {
        let clock = LockedMonotonicClock(now: 100)
        var failCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 125,
            maximumAgeNanoseconds: 250,
            now: { clock.now },
            sleep: { _ in
                try await Task.sleep(nanoseconds: UInt64.max)
            }
        )
        let startResult = await pump.start(
            lastVerifiedCaptureNanoseconds: 100,
            capture: { .verified(Self.snapshot(cursor: 2_650)) },
            persist: { _, _ in },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(startResult, .protecting)

        clock.setNow(350)
        let token = pump.beginHandoffDeadline(
            candidateCapturedAtNanoseconds: 350,
            lastRecoverableCaptureNanoseconds: 100,
            failClosed: { failCount += 1 }
        )

        XCTAssertNil(token)
        XCTAssertEqual(failCount, 1)
        XCTAssertTrue(pump.didFailClosed)
        XCTAssertFalse(pump.isRunning)
#if DEBUG
        XCTAssertEqual(
            pump.failureDiagnosticForTesting?.detail,
            "handoff-recoverable-baseline-expired"
        )
        XCTAssertEqual(
            pump.failureDiagnosticForTesting?.baselineNanoseconds,
            100
        )
#endif
    }

    func testHandoffCompletingBefore250MillisecondsTransfersSameBaseline()
        async throws {
        var failCount = 0
        var successorPersistCount = 0
        let pump = ResponsiveAudioCursorCheckpointPump(
            intervalNanoseconds: 125_000_000,
            maximumAgeNanoseconds: 250_000_000
        )
        let startResult = await pump.start(
            capture: { .verified(Self.snapshot(cursor: 2_700)) },
            persist: { _, _ in },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(startResult, .protecting)
        let initialVerified = await pump.awaitInitialVerification()
        XCTAssertTrue(initialVerified)

        let lastRecoverableCapture = try XCTUnwrap(
            pump.lastVerifiedCaptureNanoseconds
        )
        let capturedAt = DispatchTime.now().uptimeNanoseconds
        let token = try XCTUnwrap(pump.beginHandoffDeadline(
            candidateCapturedAtNanoseconds: capturedAt,
            lastRecoverableCaptureNanoseconds: lastRecoverableCapture,
            failClosed: { failCount += 1 }
        ))
        XCTAssertEqual(
            pump.lastVerifiedCaptureNanoseconds,
            lastRecoverableCapture,
            "An undurable sidecar candidate cannot become the watchdog baseline"
        )
        try await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertTrue(pump.ownsHandoffDeadline(
            token,
            candidateCapturedAtNanoseconds: capturedAt,
            lastRecoverableCaptureNanoseconds: lastRecoverableCapture
        ))
        XCTAssertEqual(failCount, 0)

        let successorStart = await pump.start(
            lastVerifiedCaptureNanoseconds: capturedAt,
            capture: { .verified(Self.snapshot(cursor: 2_800)) },
            persist: { _, _ in successorPersistCount += 1 },
            failClosed: { failCount += 1 }
        )
        XCTAssertEqual(successorStart, .protecting)
        let successorVerified = await pump.awaitInitialVerification()
        XCTAssertTrue(successorVerified)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(pump.lastVerifiedCaptureNanoseconds),
            capturedAt
        )
        XCTAssertEqual(successorPersistCount, 1)
        XCTAssertEqual(failCount, 0)
        XCTAssertTrue(pump.isRunning)
        pump.stop()
    }

    private static func snapshot(cursor: Int64) -> ResponsiveAudioProgramSnapshot {
        ResponsiveAudioProgramSnapshot(
            programID: "pump-program",
            stage: .interaction,
            interactionPhase: .waiting,
            timelineID: "pump-timeline",
            cursorSample: cursor,
            loopIteration: 0,
            durableCompletionSequence: nil
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 500_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds > deadline {
                XCTFail("Timed out waiting for checkpoint pump")
                return
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func waitUntilAsync(
        timeoutNanoseconds: UInt64 = 500_000_000,
        _ condition: @escaping () async -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !(await condition()) {
            if DispatchTime.now().uptimeNanoseconds > deadline {
                XCTFail("Timed out waiting for checkpoint pump")
                return
            }
            await Task.yield()
        }
    }
}

private struct PumpFailure: Error {}

private final class LockedMonotonicClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(now: UInt64) {
        value = now
    }

    var now: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func setNow(_ newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func advance(by nanoseconds: UInt64) {
        lock.lock()
        value += nanoseconds
        lock.unlock()
    }
}

private actor ControlledPumpSleeper {
    private struct PendingSleep {
        let duration: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var pending: [PendingSleep] = []

    var pendingDurations: [UInt64] {
        pending.map(\.duration)
    }

    func sleep(_ duration: UInt64) async throws {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(
                PendingSleep(
                    duration: duration,
                    continuation: continuation
                )
            )
        }
    }

    func resumeFirst(duration: UInt64) -> Bool {
        guard let index = pending.firstIndex(where: {
            $0.duration == duration
        }) else { return false }
        let sleeper = pending.remove(at: index)
        sleeper.continuation.resume()
        return true
    }

    func resumeAll() {
        let sleepers = pending
        pending.removeAll()
        sleepers.forEach { $0.continuation.resume() }
    }
}

private actor PersistBarrier {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    var hasBeenReleased: Bool { released }

    func enterAndWait() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        guard !released else { return }
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
