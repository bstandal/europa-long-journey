@testable import JourneyPersistence
import XCTest

final class JourneyAudioRouteChangeSuspensionPolicyTests: XCTestCase {
    func testCurrentOutputBecomingUnavailableSuspends() {
        XCTAssertTrue(
            JourneyAudioRouteChangeSuspensionPolicy.shouldSuspend(
                reasonRawValue: 2
            )
        )
    }

    func testNoSuitableOutputForCategorySuspends() {
        XCTAssertTrue(
            JourneyAudioRouteChangeSuspensionPolicy.shouldSuspend(
                reasonRawValue: 7
            )
        )
    }

    func testOnlyTransportCategorySetupIsSuppressed() {
        XCTAssertFalse(
            JourneyAudioRouteChangeSuspensionPolicy.shouldSuspend(
                reasonRawValue: 3
            )
        )
    }

    func testEveryOtherDeliveredOrUnknownChangeSuspends() {
        let outputAuthorityChanges: [UInt?] = [
            0, // unknown
            1, // new device available
            4, // override
            6, // wake from sleep
            8, // route configuration change
            9, // future or unrecognised value
            nil,
        ]

        for reason in outputAuthorityChanges {
            XCTAssertTrue(
                JourneyAudioRouteChangeSuspensionPolicy.shouldSuspend(
                    reasonRawValue: reason
                ),
                "Missing suspension for route-change reason \(String(describing: reason))"
            )
        }
    }

    func testSilentReadingDoesNotAcquireAFalseRouteSuspension() {
        XCTAssertFalse(
            JourneyAudioRouteChangeSuspensionPolicy
                .journeyAudioRequiresSuspension(
                    controllerIsPlaying: false,
                    playbackStartIsInFlight: false,
                    crashCursorIsArmed: false,
                    outgoingTailIsActive: false
                )
        )
    }

    func testEveryOwnedAudioPhaseRequiresRouteSuspension() {
        let ownedPhases: [(Bool, Bool, Bool, Bool)] = [
            (true, false, false, false),
            (false, true, false, false),
            (false, false, true, false),
            (false, false, false, true),
        ]

        for phase in ownedPhases {
            XCTAssertTrue(
                JourneyAudioRouteChangeSuspensionPolicy
                    .journeyAudioRequiresSuspension(
                        controllerIsPlaying: phase.0,
                        playbackStartIsInFlight: phase.1,
                        crashCursorIsArmed: phase.2,
                        outgoingTailIsActive: phase.3
                    )
            )
        }
    }
}
