import JourneyPersistence
import XCTest

@MainActor
final class DurableCommitBoundaryLatchTests: XCTestCase {
    func testFailedFinalAudioActionNeverSwapsRouteAuthority() {
        var swaps = 0
        let latch = DurableCommitBoundaryLatch(
            boundaryActionIndex: 1,
            fire: { swaps += 1 }
        )

        // Action zero failed before it became durable. No callback occurs.
        XCTAssertEqual(swaps, 0)
        XCTAssertFalse(latch.didFire)
    }

    func testFailedRouteActionAfterDurableAudioKeepsOldAuthority() {
        var swaps = 0
        let latch = DurableCommitBoundaryLatch(
            boundaryActionIndex: 1,
            fire: { swaps += 1 }
        )

        latch.actionDidBecomeDurable(at: 0)
        // The route append fails, so index one is never reported durable.
        XCTAssertEqual(swaps, 0)
        XCTAssertFalse(latch.didFire)
    }

    func testDurableRouteSwapsExactlyOnceEvenIfLaterWorkFails() {
        var swaps = 0
        let latch = DurableCommitBoundaryLatch(
            boundaryActionIndex: 1,
            fire: { swaps += 1 }
        )

        latch.actionDidBecomeDurable(at: 0)
        latch.actionDidBecomeDurable(at: 1)
        // A later record-visit/checkpoint outcome cannot roll back the route
        // journal record or fire the in-memory authority swap twice.
        latch.actionDidBecomeDurable(at: 2)
        latch.actionDidBecomeDurable(at: 1)

        XCTAssertEqual(swaps, 1)
        XCTAssertTrue(latch.didFire)
    }
}
