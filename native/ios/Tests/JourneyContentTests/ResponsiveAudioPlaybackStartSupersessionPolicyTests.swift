import Foundation
import ContentKit
import JourneyPersistence
import XCTest

final class ResponsiveAudioPlaybackStartSupersessionPolicyTests: XCTestCase {
    func testExactAlreadyPlayingProtectedAuthoritySucceedsWithoutSecondPlay() {
        XCTAssertEqual(
            ResponsiveAudioPlaybackStartAdmissionPolicy.decide(
                controllerIsPlaying: true,
                controllerIsCurrent: true,
                sessionProgramAndAuthorityAreCurrent: true,
                lifecycleIsCurrent: true,
                suspensionIsActive: false,
                runtimeTransitionIsInactive: true,
                cursorPumpIsRunning: true,
                cursorPumpDidFailClosed: false,
                sidecarSessionIsCurrent: true,
                durableSnapshotIsCurrent: true
            ),
            .acceptProtectedCurrentPlayback
        )
    }

    func testAlreadyPlayingWithoutCrashCursorProtectionFailsClosed() {
        XCTAssertEqual(
            ResponsiveAudioPlaybackStartAdmissionPolicy.decide(
                controllerIsPlaying: true,
                controllerIsCurrent: true,
                sessionProgramAndAuthorityAreCurrent: true,
                lifecycleIsCurrent: true,
                suspensionIsActive: false,
                runtimeTransitionIsInactive: true,
                cursorPumpIsRunning: false,
                cursorPumpDidFailClosed: false,
                sidecarSessionIsCurrent: true,
                durableSnapshotIsCurrent: true
            ),
            .failClosedUnprotectedPlayback
        )
    }

    func testPausedControllerUsesExistingStartPath() {
        XCTAssertEqual(
            ResponsiveAudioPlaybackStartAdmissionPolicy.decide(
                controllerIsPlaying: false,
                controllerIsCurrent: false,
                sessionProgramAndAuthorityAreCurrent: false,
                lifecycleIsCurrent: false,
                suspensionIsActive: true,
                runtimeTransitionIsInactive: false,
                cursorPumpIsRunning: false,
                cursorPumpDidFailClosed: true,
                sidecarSessionIsCurrent: false,
                durableSnapshotIsCurrent: false
            ),
            .startPausedTransport
        )
    }

    func testAlreadyPlayingDuringRuntimeTransitionFailsClosed() {
        XCTAssertEqual(
            ResponsiveAudioPlaybackStartAdmissionPolicy.decide(
                controllerIsPlaying: true,
                controllerIsCurrent: true,
                sessionProgramAndAuthorityAreCurrent: true,
                lifecycleIsCurrent: true,
                suspensionIsActive: false,
                runtimeTransitionIsInactive: false,
                cursorPumpIsRunning: true,
                cursorPumpDidFailClosed: false,
                sidecarSessionIsCurrent: true,
                durableSnapshotIsCurrent: true
            ),
            .failClosedUnprotectedPlayback
        )
    }

    func testCurrentCallerRetriesCancelledStartAfterControllerRebind() {
        let oldToken = UUID()
        let reboundToken = UUID()

        XCTAssertTrue(
            ResponsiveAudioPlaybackStartSupersessionPolicy.shouldRetry(
                didStart: false,
                callerIsCancelled: false,
                operationLifecycleToken: oldToken,
                currentLifecycleToken: reboundToken,
                suspensionIsActive: false
            )
        )
    }

    func testSuspensionAndStaleCallerCannotTurnCancellationIntoAutoplay() {
        let oldToken = UUID()
        let suspendedToken = UUID()

        XCTAssertFalse(
            ResponsiveAudioPlaybackStartSupersessionPolicy.shouldRetry(
                didStart: false,
                callerIsCancelled: false,
                operationLifecycleToken: oldToken,
                currentLifecycleToken: suspendedToken,
                suspensionIsActive: true
            )
        )
        XCTAssertFalse(
            ResponsiveAudioPlaybackStartSupersessionPolicy.shouldRetry(
                didStart: false,
                callerIsCancelled: true,
                operationLifecycleToken: oldToken,
                currentLifecycleToken: suspendedToken,
                suspensionIsActive: false
            )
        )
    }

    func testGenuineFailureInCurrentLifecycleIsNotRetried() {
        let token = UUID()

        XCTAssertFalse(
            ResponsiveAudioPlaybackStartSupersessionPolicy.shouldRetry(
                didStart: false,
                callerIsCancelled: false,
                operationLifecycleToken: token,
                currentLifecycleToken: token,
                suspensionIsActive: false
            )
        )
        XCTAssertFalse(
            ResponsiveAudioPlaybackStartSupersessionPolicy.shouldRetry(
                didStart: true,
                callerIsCancelled: false,
                operationLifecycleToken: UUID(),
                currentLifecycleToken: token,
                suspensionIsActive: false
            )
        )
    }

    func testContinuationDecisionAwaitsAuthorityButStopsAtOrderedJourneyBoundary() {
        let lease = playbackLease()

        XCTAssertEqual(
            continuationDecision(
                expected: lease,
                current: lease,
                authorityPreparationIsInFlight: true
            ),
            .awaitAuthority
        )
        XCTAssertEqual(
            continuationDecision(
                expected: lease,
                current: lease,
                authorityRestoreIsInFlight: true
            ),
            .awaitAuthority
        )
        XCTAssertEqual(
            continuationDecision(
                expected: lease,
                current: lease,
                orderedTransitionIsInFlight: true,
                authorityPreparationIsInFlight: true
            ),
            .stop
        )
    }

    func testContinuationDecisionRequiresSettledAuthorityAndInactiveRuntime() {
        let lease = playbackLease()

        XCTAssertEqual(
            continuationDecision(
                expected: lease,
                current: lease,
                acceptedAuthorityMatchesDesired: false
            ),
            .stop
        )
        XCTAssertEqual(
            continuationDecision(
                expected: lease,
                current: lease,
                runtimeTransitionIsInactive: false
            ),
            .stop
        )
        XCTAssertEqual(
            continuationDecision(expected: lease, current: lease),
            .retry
        )
    }

    func testContinuationDecisionRejectsCancellationSuspensionAndMissingLease() {
        let lease = playbackLease()

        XCTAssertEqual(
            ResponsiveAudioPlaybackStartContinuationPolicy.decide(
                expectedAuthorization: lease,
                currentAuthorization: lease,
                callerIsCancelled: true,
                suspensionIsActive: false,
                orderedTransitionIsInFlight: false,
                authorityPreparationIsInFlight: false,
                authorityRestoreIsInFlight: false,
                acceptedAuthorityMatchesDesired: true,
                runtimeTransitionIsInactive: true
            ),
            .stop
        )
        XCTAssertEqual(
            ResponsiveAudioPlaybackStartContinuationPolicy.decide(
                expectedAuthorization: lease,
                currentAuthorization: lease,
                callerIsCancelled: false,
                suspensionIsActive: true,
                orderedTransitionIsInFlight: false,
                authorityPreparationIsInFlight: false,
                authorityRestoreIsInFlight: false,
                acceptedAuthorityMatchesDesired: true,
                runtimeTransitionIsInactive: true
            ),
            .stop
        )
        XCTAssertEqual(
            continuationDecision(expected: lease, current: nil),
            .stop
        )
    }

    func testContinuationDecisionRejectsEveryStaleAuthoredLeaseField() {
        let expected = playbackLease()
        let stale: [(String, ResponsiveAudioPlaybackStartLease)] = [
            ("chapter", playbackLease(chapterID: "other-chapter")),
            ("package", playbackLease(packageID: "other-package")),
            ("manifest", playbackLease(packageManifestDigest: "other-digest")),
            ("beat", playbackLease(beatID: "other-beat")),
            ("program", playbackLease(programID: "other-program")),
            (
                "scope",
                playbackLease(
                    programScope: ResponsiveAudioProgramScope(
                        chapterID: "chapter",
                        arcID: "other-arc",
                        beatID: "beat",
                        interactionID: "interaction"
                    )
                )
            ),
        ]

        for (field, current) in stale {
            XCTAssertEqual(
                continuationDecision(expected: expected, current: current),
                .stop,
                field
            )
        }
    }

    private func continuationDecision(
        expected: ResponsiveAudioPlaybackStartLease,
        current: ResponsiveAudioPlaybackStartLease?,
        orderedTransitionIsInFlight: Bool = false,
        authorityPreparationIsInFlight: Bool = false,
        authorityRestoreIsInFlight: Bool = false,
        acceptedAuthorityMatchesDesired: Bool = true,
        runtimeTransitionIsInactive: Bool = true
    ) -> ResponsiveAudioPlaybackStartContinuationPolicy.Decision {
        ResponsiveAudioPlaybackStartContinuationPolicy.decide(
            expectedAuthorization: expected,
            currentAuthorization: current,
            callerIsCancelled: false,
            suspensionIsActive: false,
            orderedTransitionIsInFlight: orderedTransitionIsInFlight,
            authorityPreparationIsInFlight:
                authorityPreparationIsInFlight,
            authorityRestoreIsInFlight: authorityRestoreIsInFlight,
            acceptedAuthorityMatchesDesired:
                acceptedAuthorityMatchesDesired,
            runtimeTransitionIsInactive: runtimeTransitionIsInactive
        )
    }

    private func playbackLease(
        chapterID: ChapterID = "chapter",
        packageID: PackageID = "package",
        packageManifestDigest: String = "digest",
        beatID: BeatID = "beat",
        programID: ResponsiveAudioProgramID = "program",
        programScope: ResponsiveAudioProgramScope =
            ResponsiveAudioProgramScope(
                chapterID: "chapter",
                arcID: "arc",
                beatID: "beat",
                interactionID: "interaction"
            )
    ) -> ResponsiveAudioPlaybackStartLease {
        ResponsiveAudioPlaybackStartLease(
            chapterID: chapterID,
            packageID: packageID,
            packageManifestDigest: packageManifestDigest,
            beatID: beatID,
            programID: programID,
            programScope: programScope
        )
    }
}
