import ContentKit
import DramaticAudio
import XCTest

final class SemanticHapticTransportTests: XCTestCase {
    func testCanonicalVocabularyHasValidDistinctPatterns() throws {
        XCTAssertNoThrow(try FranchiseSemanticHapticProfile.validate())

        let semantics: [HapticSemantic] = [
            .contact,
            .drag,
            .resistance,
            .transfer,
            .break,
            .seal,
        ]
        let patterns = semantics.map(FranchiseSemanticHapticProfile.pulses)
        XCTAssertEqual(Set(patterns.map(String.init(describing:))).count, semantics.count)
        XCTAssertTrue(patterns.allSatisfy { !$0.isEmpty })
    }

    func testRateLimiterBoundsRepeatedGestureEventsWithoutSwallowingConsequence() {
        var limiter = SemanticHapticRateLimiter()

        XCTAssertTrue(limiter.shouldEmit(.drag, atUptimeNanoseconds: 1_000_000_000))
        XCTAssertFalse(limiter.shouldEmit(.drag, atUptimeNanoseconds: 1_049_999_999))
        XCTAssertTrue(limiter.shouldEmit(.drag, atUptimeNanoseconds: 1_050_000_000))

        // A different semantic is independent and can immediately close the
        // action after the final gesture update.
        XCTAssertTrue(limiter.shouldEmit(.seal, atUptimeNanoseconds: 1_050_000_000))
        XCTAssertFalse(limiter.shouldEmit(.seal, atUptimeNanoseconds: 1_229_999_999))
        XCTAssertTrue(limiter.shouldEmit(.seal, atUptimeNanoseconds: 1_230_000_000))
    }

    func testClockResetOrWrapFailsOpenForTheNextIntentionalPulse() {
        var limiter = SemanticHapticRateLimiter()
        XCTAssertTrue(limiter.shouldEmit(.contact, atUptimeNanoseconds: 500))
        XCTAssertTrue(limiter.shouldEmit(.contact, atUptimeNanoseconds: 100))
    }

    func testLifecycleGateCoalescesSuspensionAndRejectsLateEngineReset() {
        var gate = SemanticHapticLifecycleGate()
        let firstEngine = gate.registerEngine()
        XCTAssertNotNil(firstEngine)
        XCTAssertTrue(gate.suspend())
        XCTAssertFalse(gate.suspend())
        XCTAssertFalse(gate.ownsEngine(generation: firstEngine!))
        XCTAssertNil(gate.registerEngine())

        XCTAssertTrue(gate.resume())
        XCTAssertFalse(gate.resume())
        let replacement = gate.registerEngine()
        XCTAssertNotNil(replacement)
        XCTAssertNotEqual(replacement, firstEngine)
        XCTAssertFalse(gate.ownsEngine(generation: firstEngine!))
        XCTAssertTrue(gate.ownsEngine(generation: replacement!))
    }
}
