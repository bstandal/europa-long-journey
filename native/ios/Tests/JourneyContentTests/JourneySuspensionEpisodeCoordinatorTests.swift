import Foundation
@testable import JourneyPersistence
import XCTest

@MainActor
final class JourneySuspensionEpisodeCoordinatorTests: XCTestCase {
    func testQuiesceIsImmediateAndOnceWhileDurabilityFlushIsBlocked() async {
        let probe = FlushProbe()
        let leases = LeaseProbe()
        var renderIsPlaying = true
        var quiesced: [JourneySuspensionTrigger] = []
        let coordinator = JourneySuspensionEpisodeCoordinator(
            leaseFactory: { expiration in leases.make(expiration: expiration) },
            quiesce: { trigger in
                renderIsPlaying = false
                quiesced.append(trigger)
            },
            flush: { trigger in try await probe.flush(trigger) }
        )

        let id = coordinator.requestSuspension(.sceneInactive)
        XCTAssertFalse(renderIsPlaying)
        XCTAssertEqual(quiesced, [.sceneInactive])
        XCTAssertEqual(
            coordinator.requestSuspension(.audioInterruption),
            id
        )
        XCTAssertEqual(quiesced, [.sceneInactive])

        await probe.waitUntilStarted()
        XCTAssertEqual(leases.endedCount, 0)
        probe.complete()
        let result = await coordinator.awaitCurrentFlush()
        XCTAssertEqual(result, .durable)
        XCTAssertEqual(leases.endedCount, 1)
    }

    func testInactiveBackgroundRouteAndInterruptionShareOneDurableEpisode() async {
        let probe = FlushProbe()
        let leases = LeaseProbe()
        let coordinator = JourneySuspensionEpisodeCoordinator(
            leaseFactory: { expiration in leases.make(expiration: expiration) },
            flush: { trigger in try await probe.flush(trigger) }
        )

        let id = coordinator.requestSuspension(.sceneInactive)
        XCTAssertEqual(coordinator.requestSuspension(.sceneBackground), id)
        XCTAssertEqual(coordinator.requestSuspension(.audioRouteChange), id)
        XCTAssertEqual(coordinator.requestSuspension(.audioInterruption), id)
        await probe.waitUntilStarted()
        XCTAssertEqual(probe.triggers, [.sceneInactive])
        XCTAssertEqual(leases.createdCount, 1)
        XCTAssertEqual(leases.endedCount, 0)

        probe.complete()
        let firstResult = await coordinator.awaitCurrentFlush()
        XCTAssertEqual(firstResult, .durable)
        XCTAssertEqual(leases.endedCount, 1)
        XCTAssertEqual(probe.triggers.count, 1)

        coordinator.sceneBecameActive()
        XCTAssertNil(coordinator.episodeID)
        XCTAssertNotNil(coordinator.requestSuspension(.audioRouteChange))
        await probe.waitUntilStarted(count: 2)
        probe.complete()
        let secondResult = await coordinator.awaitCurrentFlush()
        XCTAssertEqual(secondResult, .durable)
        XCTAssertEqual(leases.endedCount, 2)
    }

    func testDelayedFlushKeepsFiniteLeaseUntilAppendCompletes() async {
        let probe = FlushProbe()
        let leases = LeaseProbe()
        let coordinator = JourneySuspensionEpisodeCoordinator(
            leaseFactory: { expiration in leases.make(expiration: expiration) },
            flush: { trigger in try await probe.flush(trigger) }
        )

        _ = coordinator.requestSuspension(.sceneBackground)
        await probe.waitUntilStarted()
        leases.expireCurrent()
        XCTAssertTrue(coordinator.expirationWasReported)
        XCTAssertEqual(leases.endedCount, 0)
        XCTAssertEqual(probe.cancelledCount, 0)

        probe.complete()
        let result = await coordinator.awaitCurrentFlush()
        XCTAssertEqual(result, .durable)
        XCTAssertEqual(leases.endedCount, 1)
        XCTAssertEqual(probe.cancelledCount, 0)
    }

    func testFailedFlushEndsLeaseOnceAndDoesNotDuplicateOnLaterCallbacks() async {
        let probe = FlushProbe()
        let leases = LeaseProbe()
        let coordinator = JourneySuspensionEpisodeCoordinator(
            leaseFactory: { expiration in leases.make(expiration: expiration) },
            flush: { trigger in try await probe.flush(trigger) }
        )

        let id = coordinator.requestSuspension(.audioInterruption)
        await probe.waitUntilStarted()
        probe.fail()
        let result = await coordinator.awaitCurrentFlush()
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(leases.endedCount, 1)
        XCTAssertEqual(coordinator.requestSuspension(.sceneBackground), id)
        XCTAssertEqual(probe.triggers.count, 1)
        XCTAssertEqual(leases.endedCount, 1)
    }

    func testActivationDuringFlushResetsOnlyAfterDurableCompletion() async {
        let probe = FlushProbe()
        let leases = LeaseProbe()
        let coordinator = JourneySuspensionEpisodeCoordinator(
            leaseFactory: { expiration in leases.make(expiration: expiration) },
            flush: { trigger in try await probe.flush(trigger) }
        )

        _ = coordinator.requestSuspension(.sceneInactive)
        await probe.waitUntilStarted()
        coordinator.sceneBecameActive()
        XCTAssertNotNil(coordinator.episodeID)
        XCTAssertEqual(leases.endedCount, 0)
        probe.complete()
        let result = await coordinator.awaitCurrentFlush()
        XCTAssertEqual(result, .durable)
        XCTAssertNil(coordinator.episodeID)
        XCTAssertEqual(leases.endedCount, 1)
    }

    func testResolvedSceneActivePauseMakesRoomForNextSuspensionWithoutPlayback() async {
        let probe = FlushProbe()
        let leases = LeaseProbe()
        let coordinator = JourneySuspensionEpisodeCoordinator(
            leaseFactory: { expiration in leases.make(expiration: expiration) },
            flush: { trigger in try await probe.flush(trigger) }
        )

        _ = coordinator.requestSuspension(.audioRouteChange)
        await probe.waitUntilStarted()
        probe.complete()
        let firstResult = await coordinator.awaitCurrentFlush()
        XCTAssertEqual(firstResult, .durable)
        XCTAssertNotNil(coordinator.episodeID)

        coordinator.physicalPauseDidResolve()
        XCTAssertNil(coordinator.episodeID)
        XCTAssertNotNil(coordinator.requestSuspension(.sceneInactive))
        await probe.waitUntilStarted(count: 2)
        probe.complete()
        let secondResult = await coordinator.awaitCurrentFlush()
        XCTAssertEqual(secondResult, .durable)
    }

    func testAcceptedRestorationSupersedesCompletedFailedEpisode() async {
        let probe = FlushProbe()
        let leases = LeaseProbe()
        let coordinator = JourneySuspensionEpisodeCoordinator(
            leaseFactory: { expiration in leases.make(expiration: expiration) },
            flush: { trigger in try await probe.flush(trigger) }
        )

        _ = coordinator.requestSuspension(.audioInterruption)
        await probe.waitUntilStarted()
        XCTAssertFalse(coordinator.acceptDurableRestoration())
        probe.fail()
        let failedResult = await coordinator.awaitCurrentFlush()
        XCTAssertEqual(failedResult, .failed)

        XCTAssertTrue(coordinator.acceptDurableRestoration())
        XCTAssertNil(coordinator.episodeID)
        XCTAssertNil(coordinator.firstTrigger)
        XCTAssertNil(coordinator.lastResult)
        XCTAssertNotNil(coordinator.requestSuspension(.audioRouteChange))
        await probe.waitUntilStarted(count: 2)
        probe.complete()
        let nextResult = await coordinator.awaitCurrentFlush()
        XCTAssertEqual(nextResult, .durable)
    }

    func testTeardownAwaitsAdmittedFlushAndIsIdempotent() async {
        let probe = FlushProbe()
        let leases = LeaseProbe()
        let coordinator = JourneySuspensionEpisodeCoordinator(
            leaseFactory: { expiration in leases.make(expiration: expiration) },
            flush: { trigger in try await probe.flush(trigger) }
        )
        _ = coordinator.requestSuspension(.sceneInactive)
        await probe.waitUntilStarted()

        let teardown = Task { @MainActor in
            await coordinator.finishForTeardown()
        }
        await Task.yield()
        XCTAssertEqual(leases.endedCount, 0)
        probe.complete()
        let firstResult = await teardown.value
        XCTAssertEqual(firstResult, .durable)
        let secondResult = await coordinator.finishForTeardown()
        XCTAssertEqual(secondResult, .durable)
        XCTAssertEqual(leases.endedCount, 1)
    }
}

@MainActor
private final class FlushProbe {
    private(set) var triggers: [JourneySuspensionTrigger] = []
    private(set) var cancelledCount = 0
    private var continuation: CheckedContinuation<Void, Error>?

    func flush(_ trigger: JourneySuspensionTrigger) async throws {
        triggers.append(trigger)
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancelledCount += 1 }
            }
        } catch {
            throw error
        }
    }

    func waitUntilStarted(count: Int = 1) async {
        while triggers.count < count { await Task.yield() }
    }

    func complete() {
        continuation?.resume()
        continuation = nil
    }

    func fail() {
        continuation?.resume(throwing: InjectedSuspensionFailure())
        continuation = nil
    }
}

private struct InjectedSuspensionFailure: Error {}

@MainActor
private final class LeaseProbe {
    private(set) var createdCount = 0
    private(set) var endedCount = 0
    private var current: Lease?

    func make(
        expiration: @escaping @MainActor () -> Void
    ) -> any JourneySuspensionExecutionLease {
        createdCount += 1
        let lease = Lease(owner: self, expiration: expiration)
        current = lease
        return lease
    }

    func expireCurrent() { current?.expire() }

    fileprivate func didEnd(_ lease: Lease) {
        guard !lease.didEnd else { return }
        lease.didEnd = true
        endedCount += 1
    }

    fileprivate final class Lease: JourneySuspensionExecutionLease {
        weak var owner: LeaseProbe?
        let expiration: @MainActor () -> Void
        var didEnd = false

        init(owner: LeaseProbe, expiration: @escaping @MainActor () -> Void) {
            self.owner = owner
            self.expiration = expiration
        }

        func expire() { expiration() }
        func end() { owner?.didEnd(self) }
    }
}
