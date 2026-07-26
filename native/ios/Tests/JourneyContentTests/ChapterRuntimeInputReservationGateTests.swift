@testable import JourneyPersistence
import XCTest

final class ChapterRuntimeInputReservationGateTests: XCTestCase {
    func testReservationsAreUniqueOwnedAndCountedUntilFinished() throws {
        var gate = ChapterRuntimeInputReservationGate()

        XCTAssertEqual(gate.activeCount, 0)
        XCTAssertFalse(gate.hasActiveReservations)

        let first = try XCTUnwrap(gate.reserve())
        let second = try XCTUnwrap(gate.reserve())

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 2)
        XCTAssertTrue(gate.owns(first))
        XCTAssertTrue(gate.owns(second))
        XCTAssertEqual(gate.activeCount, 2)
        XCTAssertEqual(gate.activeCount(excluding: first), 1)
        XCTAssertEqual(gate.activeCount(excluding: second), 1)
        XCTAssertTrue(gate.hasActiveReservations)

        XCTAssertTrue(gate.finish(first))
        XCTAssertFalse(gate.owns(first))
        XCTAssertTrue(gate.owns(second))
        XCTAssertEqual(gate.activeCount, 1)
        XCTAssertEqual(gate.activeCount(excluding: first), 1)
        XCTAssertEqual(gate.activeCount(excluding: second), 0)

        XCTAssertTrue(gate.finish(second))
        XCTAssertEqual(gate.activeCount, 0)
        XCTAssertFalse(gate.hasActiveReservations)
    }

    func testFinishIsIdempotentAndForeignTokensCannotReleaseOwnership() throws {
        var owner = ChapterRuntimeInputReservationGate()
        var foreignGate = ChapterRuntimeInputReservationGate()
        let owned = try XCTUnwrap(owner.reserve())
        let foreign = try XCTUnwrap(foreignGate.reserve())

        XCTAssertFalse(owner.owns(foreign))
        XCTAssertFalse(owner.finish(foreign))
        XCTAssertTrue(owner.owns(owned))
        XCTAssertEqual(owner.activeCount, 1)

        XCTAssertTrue(owner.finish(owned))
        XCTAssertFalse(owner.finish(owned))
        XCTAssertFalse(owner.owns(owned))
        XCTAssertEqual(owner.activeCount, 0)
    }

    func testGenerationExhaustionFailsClosedWithoutReleasingExistingToken()
        throws {
        var gate = ChapterRuntimeInputReservationGate(
            generation: UInt64.max - 1
        )

        let finalToken = try XCTUnwrap(gate.reserve())
        XCTAssertTrue(gate.owns(finalToken))
        XCTAssertEqual(gate.activeCount, 1)

        XCTAssertNil(gate.reserve())
        XCTAssertNil(gate.reserve())
        XCTAssertTrue(gate.owns(finalToken))
        XCTAssertEqual(gate.activeCount, 1)
        XCTAssertTrue(gate.hasActiveReservations)

        XCTAssertTrue(gate.finish(finalToken))
        XCTAssertFalse(gate.hasActiveReservations)
        XCTAssertNil(gate.reserve())
    }
}
