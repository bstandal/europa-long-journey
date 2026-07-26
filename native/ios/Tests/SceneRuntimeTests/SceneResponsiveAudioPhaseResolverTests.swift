import ContentKit
import JourneyDomain
@testable import SceneRuntime
import XCTest

final class SceneResponsiveAudioPhaseResolverTests: XCTestCase {
    func testInitialAndReducerFeedbackMapWithoutGrammarBranches() {
        XCTAssertEqual(resolve(feedback: nil), .waiting)
        XCTAssertEqual(resolve(feedback: InteractionFeedback.none), .waiting)
        XCTAssertEqual(resolve(feedback: .contact), .engaged)
        XCTAssertEqual(resolve(feedback: .progress), .engaged)
        XCTAssertEqual(resolve(feedback: .threshold), .engaged)
        XCTAssertEqual(resolve(feedback: .resistance), .resistance)
        XCTAssertNil(resolve(feedback: .completed))
    }

    func testDurableCompletionSuppressesEveryTransientBed() {
        XCTAssertNil(
            SceneResponsiveAudioPhaseResolver.phase(
                interactionPhase: .complete,
                feedback: .resistance,
                directManipulation: nil
            )
        )
    }

    func testCancelledSnapBackReturnsToWaitingWhileReducerRejectionResists() {
        let position = NormalizedPoint(x: 0.5, y: 0.5)
        let cancelled = SceneDirectManipulationState.assemblySnapBack(
            componentID: "roof",
            sourceTargetID: "roof-source",
            from: position,
            grabOffset: .zero,
            progress: 0.7,
            rejectedByReducer: false
        )
        let rejected = SceneDirectManipulationState.assemblySnapBack(
            componentID: "roof",
            sourceTargetID: "roof-source",
            targetID: "roof-slot",
            slotID: "cover",
            from: position,
            grabOffset: .zero,
            progress: 1,
            rejectedByReducer: true
        )

        XCTAssertEqual(cancelled.outcome, .cancelled)
        XCTAssertEqual(rejected.outcome, .rejectedByReducer)
        XCTAssertEqual(resolve(directManipulation: cancelled), .waiting)
        XCTAssertEqual(resolve(directManipulation: rejected), .resistance)
    }

    private func resolve(
        feedback: InteractionFeedback? = nil,
        directManipulation: SceneDirectManipulationState? = nil
    ) -> ResponsiveInteractionAudioPhase? {
        SceneResponsiveAudioPhaseResolver.phase(
            interactionPhase: .active,
            feedback: feedback,
            directManipulation: directManipulation
        )
    }
}
