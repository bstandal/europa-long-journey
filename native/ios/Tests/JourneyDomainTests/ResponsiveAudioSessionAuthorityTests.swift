import ContentKit
import Foundation
@testable import JourneyDomain
import XCTest

final class ResponsiveAudioSessionAuthorityTests: XCTestCase {
    func testSessionAuthorityIsDurableMonotonicAndReplayDeterministic() throws {
        let reducer = JourneyReducer()
        let nonce = UUID(uuidString: "00000000-0000-0000-0000-00000000a001")!
        let snapshot = ResponsiveAudioProgramSnapshot(
            programID: "program",
            stage: .interaction,
            interactionPhase: .waiting,
            timelineID: "waiting",
            cursorSample: 400,
            loopIteration: 0,
            durableCompletionSequence: nil
        )
        var state = JourneyState(
            route: .chapter("chapter"),
            activeChapter: ChapterSession(
                chapterID: "chapter",
                packageID: "package",
                contentVersion: SchemaVersion(major: 1),
                arcID: "arc",
                beatID: "beat",
                interaction: InteractionRuntimeState(spec: Fixtures.trace)
            )
        )

        XCTAssertEqual(
            reducer.reduce(
                state: &state,
                action: .beginResponsiveAudioSession(
                    chapterOpenNonce: nonce,
                    generation: 1,
                    snapshot: snapshot
                )
            ),
            [.checkpoint(.responsiveAudioChanged)]
        )
        XCTAssertEqual(state.activeChapter?.responsiveAudioChapterOpenNonce, nonce)
        XCTAssertEqual(state.activeChapter?.responsiveAudioSessionGeneration, 1)
        XCTAssertEqual(state.activeChapter?.responsiveAudioSessionIsActive, true)

        let beforeDuplicate = state
        XCTAssertEqual(
            reducer.reduce(
                state: &state,
                action: .beginResponsiveAudioSession(
                    chapterOpenNonce: nonce,
                    generation: 1,
                    snapshot: snapshot
                )
            ),
            [.rejected("Responsive audio playback authority was stale")]
        )
        XCTAssertEqual(state, beforeDuplicate)

        XCTAssertEqual(
            reducer.reduce(
                state: &state,
                action: .endResponsiveAudioSession(snapshot)
            ),
            [.checkpoint(.responsiveAudioChanged)]
        )
        XCTAssertNil(state.activeChapter?.responsiveAudioChapterOpenNonce)
        XCTAssertEqual(state.activeChapter?.responsiveAudioSessionGeneration, 1)
        XCTAssertEqual(state.activeChapter?.responsiveAudioSessionIsActive, false)

        let reopenedNonce = UUID(
            uuidString: "00000000-0000-0000-0000-00000000a002"
        )!
        XCTAssertEqual(
            reducer.reduce(
                state: &state,
                action: .beginResponsiveAudioSession(
                    chapterOpenNonce: reopenedNonce,
                    generation: 2,
                    snapshot: snapshot
                )
            ),
            [.checkpoint(.responsiveAudioChanged)]
        )

        let roundTrip = try JSONDecoder().decode(
            JourneyState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(roundTrip, state)
        XCTAssertEqual(roundTrip.activeChapter?.responsiveAudioSessionGeneration, 2)
    }

    func testBeatChangeTombstonesPriorCursorAuthority() {
        var state = JourneyState(
            route: .chapter("chapter"),
            activeChapter: ChapterSession(
                chapterID: "chapter",
                packageID: "package",
                contentVersion: SchemaVersion(major: 1),
                arcID: "arc",
                beatID: "old-beat",
                responsiveAudioSnapshot: ResponsiveAudioProgramSnapshot(
                    programID: "program",
                    stage: .interaction,
                    interactionPhase: .waiting,
                    timelineID: "waiting",
                    cursorSample: 4_000,
                    loopIteration: 0,
                    durableCompletionSequence: nil
                ),
                responsiveAudioChapterOpenNonce: UUID(),
                responsiveAudioSessionGeneration: 9,
                responsiveAudioSessionIsActive: true
            )
        )
        let effects = JourneyReducer().reduce(
            state: &state,
            action: .enterBeat(arcID: "arc", beatID: "new-beat")
        )
        XCTAssertEqual(effects, [.checkpoint(.beatChanged)])
        XCTAssertNil(state.activeChapter?.responsiveAudioSnapshot)
        XCTAssertNil(state.activeChapter?.responsiveAudioChapterOpenNonce)
        XCTAssertEqual(state.activeChapter?.responsiveAudioSessionGeneration, 0)
        XCTAssertEqual(state.activeChapter?.responsiveAudioSessionIsActive, false)
    }
}
