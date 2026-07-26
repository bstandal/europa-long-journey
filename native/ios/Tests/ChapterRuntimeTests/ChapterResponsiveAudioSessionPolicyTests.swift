import ChapterRuntime
import ContentKit
import XCTest

final class ChapterResponsiveAudioSessionPolicyTests: XCTestCase {
    private let farmers = ChapterID("first-farmers")
    private let frontiers = ChapterID("europe-holds-the-line")

    func testPlayingChoiceContinuesAcrossBeatAndProgramBindings() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: true),
            .none
        )
        let first = try XCTUnwrap(policy.chooseSound())
        XCTAssertTrue(policy.completePlayback(first, didStart: true))

        let nextBeat = policy.bind(
            chapterID: farmers,
            hasResponsiveAudio: true
        )
        guard case let .startAuthorizedPlayback(rebind) = nextBeat else {
            return XCTFail("The next authored program did not inherit chapter consent.")
        }
        XCTAssertEqual(policy.choice, .playing)
        XCTAssertTrue(policy.completePlayback(rebind, didStart: true))
        XCTAssertEqual(policy.choice, .playing)
    }

    func testPlayingChoiceContinuesAcrossCropAndReduceMotionRebinds() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let first = try XCTUnwrap(policy.chooseSound())
        XCTAssertTrue(policy.completePlayback(first, didStart: true))

        for _ in 0 ..< 2 {
            guard case let .startAuthorizedPlayback(rebind) = policy.bind(
                chapterID: farmers,
                hasResponsiveAudio: true
            ) else {
                return XCTFail("A same-chapter runtime rebind lost sound consent.")
            }
            XCTAssertTrue(policy.completePlayback(rebind, didStart: true))
        }
        XCTAssertEqual(policy.choice, .playing)
    }

    func testSilenceContinuesAcrossEverySameChapterBinding() {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        policy.continueInSilence()

        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: true),
            .none
        )
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: false),
            .none
        )
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: true),
            .none
        )
        XCTAssertEqual(policy.choice, .silent)
    }

    func testColdRestoredActiveSessionRequiresExplicitResume() {
        var policy = ChapterResponsiveAudioSessionPolicy()

        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: false),
            .none
        )
        XCTAssertEqual(policy.choice, .undecided)
        XCTAssertEqual(
            policy.bind(
                chapterID: farmers,
                hasResponsiveAudio: true,
                restoredSessionIsActive: true
            ),
            .none
        )
        XCTAssertEqual(policy.choice, .resumeRequired)
    }

    func testColdChapterWithoutActiveSessionStillRequiresInitialChoice() {
        var policy = ChapterResponsiveAudioSessionPolicy()

        XCTAssertEqual(
            policy.bind(
                chapterID: farmers,
                hasResponsiveAudio: true,
                restoredSessionIsActive: false
            ),
            .none
        )
        XCTAssertEqual(policy.choice, .undecided)
    }

    func testRestoredAuthorityDoesNotOverrideSameChapterSilence() {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        policy.continueInSilence()

        XCTAssertEqual(
            policy.bind(
                chapterID: farmers,
                hasResponsiveAudio: true,
                restoredSessionIsActive: true
            ),
            .none
        )
        XCTAssertEqual(policy.choice, .silent)
    }

    func testStaleSilenceActionCannotRelabelAudiblePlayback() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let attempt = try XCTUnwrap(policy.chooseSound())
        XCTAssertTrue(policy.completePlayback(attempt, didStart: true))

        policy.continueInSilence()

        XCTAssertEqual(policy.choice, .playing)
    }

    func testNewChapterBackgroundAndRouteExitNeverAutoplay() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let first = try XCTUnwrap(policy.chooseSound())
        XCTAssertTrue(policy.completePlayback(first, didStart: true))

        policy.requireExplicitResume()
        XCTAssertEqual(policy.choice, .resumeRequired)
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: true),
            .none
        )
        XCTAssertEqual(policy.choice, .resumeRequired)

        XCTAssertEqual(
            policy.bind(chapterID: frontiers, hasResponsiveAudio: true),
            .none
        )
        XCTAssertEqual(policy.choice, .undecided)

        policy.deactivate()
        XCTAssertEqual(policy.choice, .undecided)
        XCTAssertEqual(
            policy.bind(chapterID: frontiers, hasResponsiveAudio: true),
            .none
        )
    }

    func testNewBindingFencesAStaleAuthorizedRebindCompletion() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let first = try XCTUnwrap(policy.chooseSound())
        XCTAssertTrue(policy.completePlayback(first, didStart: true))

        guard case let .startAuthorizedPlayback(stale) = policy.bind(
            chapterID: farmers,
            hasResponsiveAudio: true
        ) else {
            return XCTFail("The first same-chapter rebind did not start.")
        }
        guard case let .startAuthorizedPlayback(current) = policy.bind(
            chapterID: farmers,
            hasResponsiveAudio: true
        ) else {
            return XCTFail("The successor same-chapter rebind did not start.")
        }

        XCTAssertFalse(policy.accepts(stale))
        XCTAssertFalse(policy.completePlayback(stale, didStart: true))
        XCTAssertTrue(policy.accepts(current))
        XCTAssertTrue(policy.completePlayback(current, didStart: true))
        XCTAssertEqual(policy.choice, .playing)
    }

    func testRebindingWhileExplicitStartIsPendingRequiresResume() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let stale = try XCTUnwrap(policy.chooseSound())

        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        XCTAssertFalse(policy.accepts(stale))
        XCTAssertFalse(policy.completePlayback(stale, didStart: true))
        XCTAssertEqual(policy.choice, .resumeRequired)
    }

    func testSuccessfulInFlightStartAuthorizesPersistenceOnlyRebind() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let inFlight = try XCTUnwrap(policy.chooseSound())

        XCTAssertTrue(policy.completePlayback(inFlight, didStart: true))
        XCTAssertEqual(policy.choice, .playing)
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: false),
            .none
        )
        guard case let .startAuthorizedPlayback(rebind) = policy.bind(
            chapterID: farmers,
            hasResponsiveAudio: true
        ) else {
            return XCTFail("The successful start did not authorize its replacement.")
        }
        XCTAssertTrue(policy.completePlayback(rebind, didStart: true))
        XCTAssertEqual(policy.choice, .playing)
    }

    func testFailedInFlightStartRequiresResumeAfterPersistenceOnlyRebind()
        throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let inFlight = try XCTUnwrap(policy.chooseSound())

        XCTAssertTrue(policy.completePlayback(inFlight, didStart: false))
        XCTAssertEqual(policy.choice, .resumeRequired)
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: false),
            .none
        )
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: true),
            .none
        )
        XCTAssertEqual(policy.choice, .resumeRequired)
    }
}
