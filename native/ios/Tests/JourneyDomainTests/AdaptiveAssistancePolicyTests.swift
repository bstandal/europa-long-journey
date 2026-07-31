import Foundation
@testable import JourneyDomain
import XCTest

final class AdaptiveAssistancePolicyTests: XCTestCase {
    func testEveryEscalationBoundaryUsesTheLockedThresholds() throws {
        let cue = try AdaptiveAssistanceCue("Hold the line")
        let cases: [AssistanceCase] = [
            AssistanceCase(
                hesitationMillis: 2_999,
                misses: 0,
                tier: .diegetic,
                cueIsVisible: false,
                targetScale: 1,
                semanticStepIsOffered: false
            ),
            AssistanceCase(
                hesitationMillis: 3_000,
                misses: 0,
                tier: .strengthenedDiegetic,
                cueIsVisible: false,
                targetScale: 1,
                semanticStepIsOffered: false
            ),
            AssistanceCase(
                hesitationMillis: 5_999,
                misses: 2,
                tier: .strengthenedDiegetic,
                cueIsVisible: false,
                targetScale: 1,
                semanticStepIsOffered: false
            ),
            AssistanceCase(
                hesitationMillis: 6_000,
                misses: 1,
                tier: .strengthenedDiegetic,
                cueIsVisible: false,
                targetScale: 1,
                semanticStepIsOffered: false
            ),
            AssistanceCase(
                hesitationMillis: 6_000,
                misses: 2,
                tier: .actionCue,
                cueIsVisible: true,
                targetScale: 1,
                semanticStepIsOffered: false
            ),
            AssistanceCase(
                hesitationMillis: 9_999,
                misses: 3,
                tier: .stabilizedInput,
                cueIsVisible: true,
                targetScale: 1.3,
                semanticStepIsOffered: false
            ),
            AssistanceCase(
                hesitationMillis: 10_000,
                misses: 0,
                tier: .stabilizedInput,
                cueIsVisible: false,
                targetScale: 1.3,
                semanticStepIsOffered: false
            ),
            AssistanceCase(
                hesitationMillis: 14_999,
                misses: 0,
                tier: .stabilizedInput,
                cueIsVisible: false,
                targetScale: 1.3,
                semanticStepIsOffered: false
            ),
            AssistanceCase(
                hesitationMillis: 15_000,
                misses: 0,
                tier: .semanticStep,
                cueIsVisible: true,
                targetScale: 1.3,
                semanticStepIsOffered: true
            ),
        ]

        for testCase in cases {
            let state = try makeState(
                hesitationMillis: testCase.hesitationMillis,
                misses: testCase.misses
            )
            let directive = AdaptiveAssistancePolicy.directive(for: state, cue: cue)

            XCTAssertEqual(
                state.tier,
                testCase.tier,
                "Unexpected tier at \(testCase.hesitationMillis) ms and \(testCase.misses) misses"
            )
            XCTAssertEqual(directive.actionCue != nil, testCase.cueIsVisible)
            XCTAssertEqual(directive.hitTargetScale, testCase.targetScale)
            XCTAssertEqual(
                directive.stabilizesInput,
                testCase.targetScale == AdaptiveAssistancePolicy.expandedHitTargetScale
            )
            XCTAssertEqual(
                directive.offersSemanticStep,
                testCase.semanticStepIsOffered
            )
            XCTAssertFalse(directive.automaticallyCompletesInteraction)
        }
    }

    func testThreeMissesExpandAndStabilizeInputWithoutPrematureText() throws {
        let cue = try AdaptiveAssistanceCue("Hold the line")
        var state = AdaptiveAssistanceState()
        _ = try AdaptiveAssistancePolicy.reduce(
            state: &state,
            event: .hesitationElapsed(1_000),
            cue: cue
        )
        for _ in 0 ..< 3 {
            _ = try AdaptiveAssistancePolicy.reduce(
                state: &state,
                event: .missedAttempt,
                cue: cue
            )
        }

        let directive = AdaptiveAssistancePolicy.directive(for: state, cue: cue)
        XCTAssertEqual(state.tier, .stabilizedInput)
        XCTAssertEqual(directive.hitTargetScale, 1.3)
        XCTAssertTrue(directive.stabilizesInput)
        XCTAssertNil(directive.actionCue)
        XCTAssertFalse(directive.offersSemanticStep)
        XCTAssertFalse(directive.automaticallyCompletesInteraction)
    }

    func testPurposefulContactImmediatelyClearsAccumulatedAssistance() throws {
        let cue = try AdaptiveAssistanceCue("Lead them to water")
        var state = try makeState(hesitationMillis: 15_000, misses: 4)

        let directive = try AdaptiveAssistancePolicy.reduce(
            state: &state,
            event: .purposefulContact,
            cue: cue
        )

        XCTAssertEqual(state, AdaptiveAssistanceState())
        XCTAssertEqual(directive.tier, .diegetic)
        XCTAssertFalse(directive.strengthensDiegeticSignals)
        XCTAssertNil(directive.actionCue)
        XCTAssertEqual(directive.hitTargetScale, 1)
        XCTAssertFalse(directive.stabilizesInput)
        XCTAssertFalse(directive.offersSemanticStep)
        XCTAssertFalse(directive.automaticallyCompletesInteraction)
    }

    func testNegativeElapsedTimeFailsWithoutMutatingState() throws {
        var state = try makeState(hesitationMillis: 3_000, misses: 1)
        let before = state

        XCTAssertThrowsError(
            try AdaptiveAssistancePolicy.reduce(
                state: &state,
                event: .hesitationElapsed(-1)
            )
        ) { error in
            XCTAssertEqual(
                error as? AdaptiveAssistanceError,
                .negativeElapsedMillis
            )
        }
        XCTAssertEqual(state, before)
    }

    func testElapsedTimeSaturatesWithoutOverflow() throws {
        var state = AdaptiveAssistanceState()
        _ = try AdaptiveAssistancePolicy.reduce(
            state: &state,
            event: .hesitationElapsed(Int64.max)
        )
        _ = try AdaptiveAssistancePolicy.reduce(
            state: &state,
            event: .hesitationElapsed(1)
        )

        XCTAssertEqual(state.hesitationMillis, Int64.max)
        XCTAssertEqual(state.tier, .semanticStep)
    }

    func testCueAllowsOneToFourWordsAndNormalizesWhitespace() throws {
        XCTAssertEqual(try AdaptiveAssistanceCue(" Hold\n the   line ").text, "Hold the line")
        XCTAssertEqual(try AdaptiveAssistanceCue("Seal").text, "Seal")
        XCTAssertEqual(
            try AdaptiveAssistanceCue("Take the landing line").text,
            "Take the landing line"
        )

        XCTAssertThrowsError(try AdaptiveAssistanceCue("")) { error in
            XCTAssertEqual(
                error as? AdaptiveAssistanceError,
                .invalidCueWordCount(0)
            )
        }
        XCTAssertThrowsError(try AdaptiveAssistanceCue("one two three four five")) {
            error in
            XCTAssertEqual(
                error as? AdaptiveAssistanceError,
                .invalidCueWordCount(5)
            )
        }
    }

    func testAssistanceStateRoundTripsAtTheExactEscalationPoint() throws {
        let state = try makeState(hesitationMillis: 10_000, misses: 3)
        let encoded = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(
            AdaptiveAssistanceState.self,
            from: encoded
        )

        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.hesitationMillis, 10_000)
        XCTAssertEqual(restored.missCount, 3)
        XCTAssertEqual(restored.tier, .stabilizedInput)
    }

    func testDecodeRejectsAStateWhoseTierDoesNotMatchItsEvidence() {
        let invalid = Data(
            #"{"tier":"semanticStep","hesitationMillis":3000,"missCount":0}"#.utf8
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode(AdaptiveAssistanceState.self, from: invalid)
        )
    }

    func testDecodeRejectsAnOverlongCue() {
        let invalid = Data(#"{"text":"one two three four five"}"#.utf8)

        XCTAssertThrowsError(
            try JSONDecoder().decode(AdaptiveAssistanceCue.self, from: invalid)
        )
    }

    private func makeState(
        hesitationMillis: Int64,
        misses: Int
    ) throws -> AdaptiveAssistanceState {
        var state = AdaptiveAssistanceState()
        if hesitationMillis > 0 {
            _ = try AdaptiveAssistancePolicy.reduce(
                state: &state,
                event: .hesitationElapsed(hesitationMillis)
            )
        }
        for _ in 0 ..< misses {
            _ = try AdaptiveAssistancePolicy.reduce(
                state: &state,
                event: .missedAttempt
            )
        }
        return state
    }
}

private struct AssistanceCase {
    let hesitationMillis: Int64
    let misses: Int
    let tier: AdaptiveAssistanceTier
    let cueIsVisible: Bool
    let targetScale: Double
    let semanticStepIsOffered: Bool
}
