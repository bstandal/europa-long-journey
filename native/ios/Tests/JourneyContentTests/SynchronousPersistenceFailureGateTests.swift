import JourneyPersistence
import XCTest

@MainActor
final class SynchronousPersistenceFailureGateTests: XCTestCase {
    func testCommitAndCheckpointFailuresStopBeforeLock() {
        for failure in ["commit", "checkpoint"] {
            var events: [String] = []
            SynchronousPersistenceFailureGate.close(
                physicalStop: { events.append("stop") },
                lockPersistence: { events.append("lock") }
            )
            XCTAssertEqual(events, ["stop", "lock"], failure)
        }
    }
}
