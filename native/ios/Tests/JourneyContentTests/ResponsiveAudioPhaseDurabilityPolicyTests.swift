import ContentKit
import JourneyPersistence
import XCTest

final class ResponsiveAudioPhaseDurabilityPolicyTests: XCTestCase {
    func testRepeatedTouchAndVoiceOverPhaseProducesOneCommit() {
        for inputSource in ["touch", "voice-over"] {
            var current: ResponsiveInteractionAudioPhase? = .waiting
            var commitCount = 0

            for desired in [
                ResponsiveInteractionAudioPhase.engaged,
                .engaged,
                .engaged,
            ] {
                let decision = ResponsiveAudioPhaseDurabilityPolicy.decision(
                    desiredPhase: desired,
                    currentStage: .interaction,
                    currentPhase: current,
                    isUserAuthorized: true,
                    suspensionIsActive: false
                )
                if decision == .commit {
                    commitCount += 1
                    current = desired
                }
            }

            XCTAssertEqual(commitCount, 1, inputSource)
        }
    }

    func testSuspensionBlocksNewPhaseAndApproachDefersLatestIntent() {
        XCTAssertEqual(
            ResponsiveAudioPhaseDurabilityPolicy.decision(
                desiredPhase: .resistance,
                currentStage: .interaction,
                currentPhase: .waiting,
                isUserAuthorized: true,
                suspensionIsActive: true
            ),
            .ignore
        )
        XCTAssertEqual(
            ResponsiveAudioPhaseDurabilityPolicy.decision(
                desiredPhase: .resistance,
                currentStage: .approach,
                currentPhase: nil,
                isUserAuthorized: true,
                suspensionIsActive: false
            ),
            .deferUntilInteraction
        )
    }
}
