import ContentKit
import DramaticAudio
import XCTest

final class TimelinePlaybackPlannerTests: XCTestCase {
    func testColdRestoreSlicesEveryActiveTrackAtExactAuthoredSample() throws {
        let timeline = Self.timeline()
        let plan = try TimelinePlaybackPlanner.makePlan(
            timeline: timeline,
            cursorSample: 72_000,
            assetMetadata: Self.metadata
        )

        XCTAssertEqual(plan.cursorSample, 72_000)
        XCTAssertEqual(plan.endSample, 240_000)
        XCTAssertEqual(plan.audioSlices, [
            ScheduledAudioSlice(
                cueID: "narration",
                role: .narration,
                assetPath: "audio/narration.wav",
                assetStartFrame: 72_000,
                frameCount: 72_000,
                timelineStartOffset: 0,
                gain: 1
            ),
            ScheduledAudioSlice(
                cueID: "score",
                role: .score,
                assetPath: "audio/score.wav",
                assetStartFrame: 72_000,
                frameCount: 168_000,
                timelineStartOffset: 0,
                gain: 0.5
            ),
            ScheduledAudioSlice(
                cueID: "field-detail",
                role: .spatialDetail,
                assetPath: "audio/field.wav",
                assetStartFrame: 0,
                frameCount: 24_000,
                timelineStartOffset: 24_000,
                gain: 0.75
            ),
        ])
        XCTAssertEqual(plan.haptics, [
            ScheduledHaptic(
                timelineStartOffset: 24_000,
                semantic: .transfer,
                intensity: 0.7,
                sharpness: 0.4
            ),
        ])
    }

    func testPlanAtEndSchedulesNoAudioOrPastHaptics() throws {
        let plan = try TimelinePlaybackPlanner.makePlan(
            timeline: Self.timeline(),
            cursorSample: 240_000,
            assetMetadata: Self.metadata
        )
        XCTAssertEqual(plan.remainingSamples, 0)
        XCTAssertTrue(plan.audioSlices.isEmpty)
        XCTAssertTrue(plan.haptics.isEmpty)
    }

    func testMissingOrWrongFormatAssetFailsBeforePlayback() throws {
        XCTAssertThrowsError(
            try TimelinePlaybackPlanner.makePlan(
                timeline: Self.timeline(),
                cursorSample: 0,
                assetMetadata: [:]
            )
        ) { error in
            XCTAssertEqual(
                error as? TimelinePlaybackPlanningError,
                .missingAsset("audio/narration.wav")
            )
        }

        var wrongRate = Self.metadata
        wrongRate["audio/narration.wav"] = AudioAssetMetadata(
            path: "audio/narration.wav",
            sampleRate: 44_100,
            frameCount: 144_000,
            channelCount: 1
        )
        XCTAssertThrowsError(
            try TimelinePlaybackPlanner.makePlan(
                timeline: Self.timeline(),
                cursorSample: 0,
                assetMetadata: wrongRate
            )
        ) { error in
            XCTAssertEqual(
                error as? TimelinePlaybackPlanningError,
                .unsupportedSampleRate(
                    path: "audio/narration.wav",
                    expected: 48_000,
                    actual: 44_100
                )
            )
        }
    }

    func testNarrationMustBeMonoAndScoreAndSoundscapeStereo() throws {
        var invalid = Self.metadata
        invalid["audio/narration.wav"] = AudioAssetMetadata(
            path: "audio/narration.wav",
            sampleRate: 48_000,
            frameCount: 144_000,
            channelCount: 2
        )
        XCTAssertThrowsError(
            try TimelinePlaybackPlanner.makePlan(
                timeline: Self.timeline(),
                cursorSample: 0,
                assetMetadata: invalid
            )
        ) { error in
            XCTAssertEqual(
                error as? TimelinePlaybackPlanningError,
                .invalidChannelCount(
                    path: "audio/narration.wav",
                    role: .narration,
                    actual: 2
                )
            )
        }
    }

    func testCursorBeforeLaterCuePreservesAuthoredOffset() throws {
        let plan = try TimelinePlaybackPlanner.makePlan(
            timeline: Self.timeline(),
            cursorSample: 48_000,
            assetMetadata: Self.metadata
        )
        let detail = try XCTUnwrap(plan.audioSlices.first(where: { $0.cueID == "field-detail" }))
        XCTAssertEqual(detail.assetStartFrame, 0)
        XCTAssertEqual(detail.timelineStartOffset, 48_000)
    }

    private static func timeline() -> AudioTimeline {
        AudioTimeline(
            id: "harvest-audio",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "narration",
                    role: .narration,
                    startSample: 0,
                    durationSamples: 144_000,
                    assetPath: "audio/narration.wav",
                    gain: 1,
                    narrationBinding: NarrationCueBinding(
                        manuscriptSegmentID: "harvest-segment",
                        manuscriptSegmentSHA256: String(repeating: "a", count: 64),
                        scope: NarrationCueScope(
                            chapterID: "first-farmers",
                            arcID: "fields-that-must-endure",
                            beatID: "harvest-allocation"
                        )
                    )
                ),
                AudioEvent(
                    cueID: "score",
                    role: .score,
                    startSample: 0,
                    durationSamples: 240_000,
                    assetPath: "audio/score.wav",
                    gain: 0.5
                ),
                AudioEvent(
                    cueID: "field-detail",
                    role: .spatialDetail,
                    startSample: 96_000,
                    durationSamples: 24_000,
                    assetPath: "audio/field.wav",
                    gain: 0.75
                ),
                AudioEvent(
                    cueID: "held-silence",
                    role: .silence,
                    startSample: 144_000,
                    durationSamples: 48_000,
                    assetPath: nil,
                    gain: 0
                ),
            ],
            haptics: [
                HapticEvent(
                    sample: 96_000,
                    kind: .transfer,
                    intensity: 0.7,
                    sharpness: 0.4
                ),
            ]
        )
    }

    private static let metadata: [String: AudioAssetMetadata] = [
        "audio/narration.wav": AudioAssetMetadata(
            path: "audio/narration.wav",
            sampleRate: 48_000,
            frameCount: 144_000,
            channelCount: 1
        ),
        "audio/score.wav": AudioAssetMetadata(
            path: "audio/score.wav",
            sampleRate: 48_000,
            frameCount: 240_000,
            channelCount: 2
        ),
        "audio/field.wav": AudioAssetMetadata(
            path: "audio/field.wav",
            sampleRate: 48_000,
            frameCount: 24_000,
            channelCount: 1
        ),
    ]
}
