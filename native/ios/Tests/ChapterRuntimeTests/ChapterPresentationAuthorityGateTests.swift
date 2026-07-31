import ChapterRuntime
import XCTest

final class ChapterPresentationAuthorityGateTests: XCTestCase {
    func testMismatchedIdentityAdmitsNeitherPresentationNorInput() {
        XCTAssertFalse(
            ChapterPresentationAuthorityGate.admitsPresentation(
                expectedIdentity: "new-authority",
                sessionIdentity: "old-authority",
                runtimeIsReady: true
            )
        )
        XCTAssertFalse(
            ChapterPresentationAuthorityGate.admitsInput(
                expectedIdentity: "new-authority",
                sessionIdentity: "old-authority",
                runtimeIsReady: true,
                presentationIsReady: true
            )
        )
    }

    func testExactIdentityStillRequiresReadyRuntimeAndPresentation() {
        XCTAssertFalse(
            ChapterPresentationAuthorityGate.admitsPresentation(
                expectedIdentity: "authority",
                sessionIdentity: "authority",
                runtimeIsReady: false
            )
        )
        XCTAssertFalse(
            ChapterPresentationAuthorityGate.admitsInput(
                expectedIdentity: "authority",
                sessionIdentity: "authority",
                runtimeIsReady: true,
                presentationIsReady: false
            )
        )
        XCTAssertTrue(
            ChapterPresentationAuthorityGate.admitsInput(
                expectedIdentity: "authority",
                sessionIdentity: "authority",
                runtimeIsReady: true,
                presentationIsReady: true
            )
        )
    }
}

final class ChapterRuntimeInputAdmissionPolicyTests: XCTestCase {
    func testExactIdentityWithInactiveTransitionIsAdmitted() {
        XCTAssertTrue(
            ChapterRuntimeInputAdmissionPolicy.admits(
                expectedIdentity: "authority",
                currentIdentity: "authority",
                state: inactiveState()
            )
        )
    }

    func testExactIdentityMismatchAndMissingIdentityAreRejected() {
        XCTAssertFalse(
            ChapterRuntimeInputAdmissionPolicy.admits(
                expectedIdentity: "expected",
                currentIdentity: "other",
                state: inactiveState()
            )
        )
        XCTAssertFalse(
            ChapterRuntimeInputAdmissionPolicy.admits(
                expectedIdentity: "expected",
                currentIdentity: Optional<String>.none,
                state: inactiveState()
            )
        )
    }

    func testEveryTransitionBlockerRejectsInputIndependently() {
        let blockers: [(String, ChapterRuntimeInputAdmissionPolicy.State)] = [
            (
                "restoration",
                state(restorationIsInFlight: true)
            ),
            (
                "persistence-lock",
                state(persistenceIsLocked: true)
            ),
            (
                "authority-preparation",
                state(authorityPreparationIsInFlight: true)
            ),
            (
                "authority-transition",
                state(authorityTransitionIsInFlight: true)
            ),
            (
                "authority-restore",
                state(authorityRestoreIsInFlight: true)
            ),
            (
                "ordered-transition",
                state(orderedTransitionIsInFlight: true)
            ),
            (
                "chapter-transition",
                state(chapterTransitionIsPending: true)
            ),
        ]

        for (name, blocked) in blockers {
            XCTAssertFalse(
                ChapterRuntimeInputAdmissionPolicy.admits(
                    expectedIdentity: "authority",
                    currentIdentity: "authority",
                    state: blocked
                ),
                name
            )
            XCTAssertFalse(
                ChapterRuntimeInputAdmissionPolicy
                    .runtimeTransitionIsInactive(blocked),
                name
            )
        }
    }

    func testAuthorityPreparationRejectsWhenChapterPendingFlagIsFalse() {
        let preparation = state(
            authorityPreparationIsInFlight: true,
            chapterTransitionIsPending: false
        )

        XCTAssertFalse(
            ChapterRuntimeInputAdmissionPolicy.admits(
                expectedIdentity: "authority",
                currentIdentity: "authority",
                state: preparation
            )
        )
    }

    private func inactiveState() -> ChapterRuntimeInputAdmissionPolicy.State {
        state()
    }

    private func state(
        restorationIsInFlight: Bool = false,
        persistenceIsLocked: Bool = false,
        authorityPreparationIsInFlight: Bool = false,
        authorityTransitionIsInFlight: Bool = false,
        authorityRestoreIsInFlight: Bool = false,
        orderedTransitionIsInFlight: Bool = false,
        chapterTransitionIsPending: Bool = false
    ) -> ChapterRuntimeInputAdmissionPolicy.State {
        ChapterRuntimeInputAdmissionPolicy.State(
            restorationIsInFlight: restorationIsInFlight,
            persistenceIsLocked: persistenceIsLocked,
            authorityPreparationIsInFlight:
                authorityPreparationIsInFlight,
            authorityTransitionIsInFlight: authorityTransitionIsInFlight,
            authorityRestoreIsInFlight: authorityRestoreIsInFlight,
            orderedTransitionIsInFlight: orderedTransitionIsInFlight,
            chapterTransitionIsPending: chapterTransitionIsPending
        )
    }
}

final class ChapterRouteActivationRequestFenceTests: XCTestCase {
    func testOnlyLatestActivationRequestRemainsCurrent() {
        var fence = ChapterRouteActivationRequestFence()
        let first = fence.begin()
        let second = fence.begin()

        XCTAssertFalse(fence.isCurrent(first))
        XCTAssertTrue(fence.isCurrent(second))
    }

    func testInvalidationPreventsSuspendedRequestFromResuming() {
        var fence = ChapterRouteActivationRequestFence()
        let request = fence.begin()

        fence.invalidate()

        XCTAssertFalse(fence.isCurrent(request))
    }
}
