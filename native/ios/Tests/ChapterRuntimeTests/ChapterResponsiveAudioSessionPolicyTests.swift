import ChapterRuntime
import ContentKit
import XCTest

final class ChapterResponsiveAudioSessionPolicyTests: XCTestCase {
    private let farmers = ChapterID("first-farmers")
    private let frontiers = ChapterID("europe-holds-the-line")

    func testUnboundPolicyIsInactiveAndCannotRequestPlayback() {
        var policy = ChapterResponsiveAudioSessionPolicy()

        XCTAssertEqual(policy.playbackState, .inactive)
        XCTAssertNil(policy.requestPlayback())
        XCTAssertFalse(policy.playbackState.authorizesPlayback)
    }

    func testPlayingStateContinuesAcrossBeatAndProgramBindings() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: true),
            .none
        )
        XCTAssertEqual(policy.playbackState, .ready)
        let first = try XCTUnwrap(policy.requestPlayback())
        XCTAssertTrue(policy.completePlayback(first, didStart: true))

        let nextBeat = policy.bind(
            chapterID: farmers,
            hasResponsiveAudio: true
        )
        guard case let .startAuthorizedPlayback(rebind) = nextBeat else {
            return XCTFail("The next authored program did not inherit chapter consent.")
        }
        XCTAssertEqual(policy.playbackState, .playing)
        XCTAssertTrue(policy.completePlayback(rebind, didStart: true))
        XCTAssertEqual(policy.playbackState, .playing)
    }

    func testPlayingStateContinuesAcrossCropAndReduceMotionRebinds() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let first = try XCTUnwrap(policy.requestPlayback())
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
        XCTAssertEqual(policy.playbackState, .playing)
    }

    func testProgramlessBindingIsInactiveAndRetainsPlayingChapterAuthority() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let first = try XCTUnwrap(policy.requestPlayback())
        XCTAssertTrue(policy.completePlayback(first, didStart: true))

        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: false),
            .none
        )
        XCTAssertEqual(policy.playbackState, .inactive)

        guard case let .startAuthorizedPlayback(rebind) = policy.bind(
            chapterID: farmers,
            hasResponsiveAudio: true
        ) else {
            return XCTFail("The next authored program did not retain playback authority.")
        }
        XCTAssertEqual(policy.playbackState, .playing)
        XCTAssertTrue(policy.completePlayback(rebind, didStart: true))
    }

    func testColdRestoredActiveSessionRequiresExplicitResume() {
        var policy = ChapterResponsiveAudioSessionPolicy()

        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: false),
            .none
        )
        XCTAssertEqual(policy.playbackState, .inactive)
        XCTAssertEqual(
            policy.bind(
                chapterID: farmers,
                hasResponsiveAudio: true,
                restoredSessionIsActive: true
            ),
            .none
        )
        XCTAssertEqual(policy.playbackState, .resumeRequired)
    }

    func testColdChapterWithoutActiveSessionIsReadyForAuthorizedEntry() {
        var policy = ChapterResponsiveAudioSessionPolicy()

        XCTAssertEqual(
            policy.bind(
                chapterID: farmers,
                hasResponsiveAudio: true,
                restoredSessionIsActive: false
            ),
            .none
        )
        XCTAssertEqual(policy.playbackState, .ready)
    }

    func testRestoredSessionChangesReadyStateToResumeRequired() {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        XCTAssertEqual(policy.playbackState, .ready)

        XCTAssertEqual(
            policy.bind(
                chapterID: farmers,
                hasResponsiveAudio: true,
                restoredSessionIsActive: true
            ),
            .none
        )
        XCTAssertEqual(policy.playbackState, .resumeRequired)
    }

    func testDuplicatePlaybackRequestCannotReplaceAudiblePlayback() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let attempt = try XCTUnwrap(policy.requestPlayback())
        XCTAssertTrue(policy.completePlayback(attempt, didStart: true))

        XCTAssertNil(policy.requestPlayback())
        XCTAssertEqual(policy.playbackState, .playing)
    }

    func testFiniteCompletionRequiresExplicitReplayAndCannotAutoplayOnRebind()
        throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let attempt = try XCTUnwrap(policy.requestPlayback())
        XCTAssertTrue(policy.completePlayback(attempt, didStart: true))

        policy.completeFinitePlayback()

        XCTAssertEqual(policy.playbackState, .resumeRequired)
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: true),
            .none
        )
        XCTAssertEqual(policy.playbackState, .resumeRequired)
        XCTAssertNotNil(policy.requestPlayback())
    }

    func testNewChapterBackgroundAndRouteExitNeverAutoplay() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let first = try XCTUnwrap(policy.requestPlayback())
        XCTAssertTrue(policy.completePlayback(first, didStart: true))

        policy.requireExplicitResume()
        XCTAssertEqual(policy.playbackState, .resumeRequired)
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: true),
            .none
        )
        XCTAssertEqual(policy.playbackState, .resumeRequired)

        XCTAssertEqual(
            policy.bind(chapterID: frontiers, hasResponsiveAudio: true),
            .none
        )
        XCTAssertEqual(policy.playbackState, .ready)

        policy.deactivate()
        XCTAssertEqual(policy.playbackState, .inactive)
        XCTAssertEqual(
            policy.bind(chapterID: frontiers, hasResponsiveAudio: true),
            .none
        )
    }

    func testNewBindingFencesAStaleAuthorizedRebindCompletion() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let first = try XCTUnwrap(policy.requestPlayback())
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
        XCTAssertEqual(policy.playbackState, .playing)
    }

    func testRebindingWhileExplicitStartIsPendingRequiresResume() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let stale = try XCTUnwrap(policy.requestPlayback())

        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        XCTAssertFalse(policy.accepts(stale))
        XCTAssertFalse(policy.completePlayback(stale, didStart: true))
        XCTAssertEqual(policy.playbackState, .resumeRequired)
    }

    func testSuccessfulInFlightStartAuthorizesPersistenceOnlyRebind() throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let inFlight = try XCTUnwrap(policy.requestPlayback())

        XCTAssertTrue(policy.completePlayback(inFlight, didStart: true))
        XCTAssertEqual(policy.playbackState, .playing)
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
        XCTAssertEqual(policy.playbackState, .playing)
    }

    func testFailedInFlightStartRequiresResumeAfterPersistenceOnlyRebind()
        throws {
        var policy = ChapterResponsiveAudioSessionPolicy()
        _ = policy.bind(chapterID: farmers, hasResponsiveAudio: true)
        let inFlight = try XCTUnwrap(policy.requestPlayback())

        XCTAssertTrue(policy.completePlayback(inFlight, didStart: false))
        XCTAssertEqual(policy.playbackState, .resumeRequired)
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: false),
            .none
        )
        XCTAssertEqual(
            policy.bind(chapterID: farmers, hasResponsiveAudio: true),
            .none
        )
        XCTAssertEqual(policy.playbackState, .resumeRequired)
    }
}
