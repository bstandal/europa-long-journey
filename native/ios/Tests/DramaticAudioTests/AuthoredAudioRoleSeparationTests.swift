import ContentKit
@testable import DramaticAudio
import Foundation
import XCTest
#if os(iOS)
import AVFAudio
#endif

final class AuthoredAudioRoleSeparationTests: XCTestCase {
    func testProjectionPartitionsEveryCueOnceAndGivesHapticsOneAuthority()
        throws {
        let timeline = makeTimeline(includingNonSpeaking: true)

        let separation = try AuthoredAudioRoleSeparation(
            validating: timeline
        )
        let nonSpeaking = try XCTUnwrap(separation.nonSpeaking)

        XCTAssertEqual(
            separation.narration.events.map(\.cueID),
            [AudioCueID("narration")]
        )
        XCTAssertTrue(separation.narration.haptics.isEmpty)
        XCTAssertEqual(
            nonSpeaking.events.map(\.cueID),
            [AudioCueID("score"), AudioCueID("authored-silence")]
        )
        XCTAssertEqual(nonSpeaking.haptics, timeline.haptics)
        XCTAssertEqual(
            Set(
                separation.narration.events.map(\.cueID)
                    + nonSpeaking.events.map(\.cueID)
            ),
            Set(timeline.events.map(\.cueID))
        )
        XCTAssertEqual(separation.narration.id, timeline.id)
        XCTAssertEqual(nonSpeaking.id, timeline.id)
        XCTAssertEqual(
            separation.narration.events.compactMap(\.assetPath),
            ["narration.caf"]
        )
        XCTAssertEqual(
            nonSpeaking.events.compactMap(\.assetPath),
            ["score.caf"]
        )

        let review = separation.reviewComponentTimelines
        XCTAssertTrue(review.values.allSatisfy { $0.haptics.isEmpty })
        XCTAssertEqual(
            review[.nonSpeaking]?.events,
            nonSpeaking.events
        )
        XCTAssertEqual(
            review[.narration]?.events,
            separation.narration.events
        )
    }

    func testActiveAndReviewUseSameVoiceOverBoundaryPolicy() {
        let separated: Set<AuthoredAudioComponent> = [
            .narration, .nonSpeaking,
        ]
        XCTAssertEqual(
            AuthoredAudioPlaybackBoundaryPolicy.componentsToPlay(
                available: separated,
                usesVerifiedRoleSeparation: true,
                suppressesNarration: false,
                narrationIsEnabled: true
            ),
            separated
        )
        XCTAssertEqual(
            AuthoredAudioPlaybackBoundaryPolicy.componentsToPlay(
                available: separated,
                usesVerifiedRoleSeparation: true,
                suppressesNarration: true,
                narrationIsEnabled: true
            ),
            [.nonSpeaking]
        )
        XCTAssertEqual(
            AuthoredAudioPlaybackBoundaryPolicy.componentsToPlay(
                available: separated,
                usesVerifiedRoleSeparation: true,
                suppressesNarration: false,
                narrationIsEnabled: false
            ),
            [.nonSpeaking],
            "A narration-disabled run must retain only the independently authored bed"
        )
        XCTAssertEqual(
            AuthoredAudioPlaybackBoundaryPolicy
                .componentToPauseForVoiceOver(
                    available: separated,
                    usesVerifiedRoleSeparation: true
                ),
            .narration
        )

        let fallback: Set<AuthoredAudioComponent> = [.wholeMix]
        XCTAssertTrue(
            AuthoredAudioPlaybackBoundaryPolicy.componentsToPlay(
                available: fallback,
                usesVerifiedRoleSeparation: false,
                suppressesNarration: true,
                narrationIsEnabled: true
            ).isEmpty
        )
        XCTAssertEqual(
            AuthoredAudioPlaybackBoundaryPolicy
                .componentToPauseForVoiceOver(
                    available: fallback,
                    usesVerifiedRoleSeparation: false
                ),
            .wholeMix
        )
    }

    func testProjectionFailsClosedInsteadOfInventingHapticTimingEvent()
        throws {
        let timeline = makeTimeline(includingNonSpeaking: false)

        XCTAssertThrowsError(
            try AuthoredAudioRoleSeparation(validating: timeline)
        ) { error in
            XCTAssertEqual(
                error as? AuthoredAudioRoleSeparationError,
                .nonSpeakingHapticsHaveNoTimingEvent
            )
        }
    }

    func testProjectionFailsClosedForDuplicateManifestCue() throws {
        let valid = makeTimeline(includingNonSpeaking: true)
        let duplicated = AudioTimeline(
            id: valid.id,
            sampleRate: valid.sampleRate,
            events: [valid.events[0], valid.events[0]],
            haptics: []
        )

        XCTAssertThrowsError(
            try AuthoredAudioRoleSeparation(validating: duplicated)
        ) { error in
            XCTAssertEqual(
                error as? AuthoredAudioRoleSeparationError,
                .invalidTimeline
            )
        }
    }

    func testSchemaTwoCheckpointRejectsWrongAuthorityRoleAndVersion()
        throws {
        let authority = TestAuthority(revision: 7, digest: "signed-a")
        let data = try AuthoredAudioCursorCheckpointCodec.encode(
            authority: authority,
            component: .narration,
            cursorSample: 8_000,
            maximumCursorSample: 24_000
        )

        XCTAssertEqual(
            AuthoredAudioCursorCheckpointCodec.recover(
                from: data,
                expectedAuthority: authority,
                component: .narration,
                maximumCursorSample: 24_000
            ),
            .current(8_000)
        )
        XCTAssertNil(AuthoredAudioCursorCheckpointCodec.recover(
            from: data,
            expectedAuthority: TestAuthority(
                revision: 8,
                digest: "signed-a"
            ),
            component: .narration,
            maximumCursorSample: 24_000
        ))
        XCTAssertNil(AuthoredAudioCursorCheckpointCodec.recover(
            from: data,
            expectedAuthority: authority,
            component: .nonSpeaking,
            maximumCursorSample: 24_000
        ))

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = 3
        let future = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(AuthoredAudioCursorCheckpointCodec.recover(
            from: future,
            expectedAuthority: authority,
            component: .narration,
            maximumCursorSample: 24_000
        ))
    }

    func testLegacyWholeMixCursorMigratesInAbsoluteDomainAndClampsEnd()
        throws {
        let authority = TestAuthority(revision: 3, digest: "signed-b")
        let legacy = try JSONEncoder().encode(LegacyFixture(
            authority: authority,
            cursorSample: 40_000
        ))

        XCTAssertEqual(
            AuthoredAudioCursorCheckpointCodec.recover(
                from: legacy,
                expectedAuthority: authority,
                component: .narration,
                maximumCursorSample: 24_000
            ),
            .migratedLegacy(24_000)
        )
        XCTAssertEqual(
            AuthoredAudioCursorCheckpointCodec.recover(
                from: legacy,
                expectedAuthority: authority,
                component: .nonSpeaking,
                maximumCursorSample: 48_100
            ),
            .migratedLegacy(40_000)
        )
    }

#if os(iOS)
    @MainActor
    func testNarrationPauseLeavesNonSpeakingClockAndHapticAuthorityRunning()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("narration.caf"),
            channelCount: 1,
            frameCount: 24_000
        )
        try writeAudioFile(
            to: directory.appendingPathComponent("score.caf"),
            channelCount: 2,
            frameCount: 48_000
        )
        let separation = try AuthoredAudioRoleSeparation(
            validating: makeTimeline(includingNonSpeaking: true)
        )
        let nonSpeakingTimeline = try XCTUnwrap(
            separation.nonSpeaking
        )
        let narrationHaptics = RecordingHapticScheduler()
        let nonSpeakingHaptics = RecordingHapticScheduler()
        let narration = NativeTimelineTransport(
            hapticScheduler: narrationHaptics
        )
        let nonSpeaking = NativeTimelineTransport(
            hapticScheduler: nonSpeakingHaptics
        )
        try narration.enableManualRenderingForTesting()
        try nonSpeaking.enableManualRenderingForTesting()
        let resolver = PackageRootAudioAssetResolver(
            packageRootURL: directory
        )
        try narration.prepare(
            timeline: separation.narration,
            cursorSample: 0,
            resolver: resolver
        )
        try nonSpeaking.prepare(
            timeline: nonSpeakingTimeline,
            cursorSample: 0,
            resolver: resolver
        )
        try narration.play()
        try nonSpeaking.play()
        _ = try narration.renderOfflineSamplesForTesting(512)
        _ = try nonSpeaking.renderOfflineSamplesForTesting(512)

        let narrationPause = try narration.pause()
        XCTAssertEqual(narrationPause.cursorSample, 512)
        XCTAssertFalse(narrationPause.isPlaying)
        _ = try nonSpeaking.renderOfflineSamplesForTesting(1_024)
        XCTAssertEqual(narration.snapshot().cursorSample, 512)
        XCTAssertEqual(nonSpeaking.snapshot().cursorSample, 1_536)
        XCTAssertEqual(narrationHaptics.prepareCount, 0)
        XCTAssertEqual(nonSpeakingHaptics.prepareCount, 1)

        try narration.resume()
        _ = try narration.renderOfflineSamplesForTesting(256)
        XCTAssertEqual(narration.snapshot().cursorSample, 768)
        XCTAssertEqual(nonSpeaking.snapshot().cursorSample, 1_536)

        let mutedNarration = try narration.pause()
        let mutedNonSpeaking = try nonSpeaking.pause()
        XCTAssertFalse(mutedNarration.isPlaying)
        XCTAssertFalse(mutedNonSpeaking.isPlaying)
        XCTAssertEqual(mutedNarration.cursorSample, 768)
        XCTAssertEqual(mutedNonSpeaking.cursorSample, 1_536)
        narration.stop()
        nonSpeaking.stop()

        let reviewScheduler = RecordingHapticScheduler()
        let reviewTransport = NativeTimelineTransport(
            hapticScheduler: reviewScheduler
        )
        try reviewTransport.enableManualRenderingForTesting()
        let reviewNonSpeaking = try XCTUnwrap(
            separation.reviewComponentTimelines[.nonSpeaking]
        )
        try reviewTransport.prepare(
            timeline: reviewNonSpeaking,
            cursorSample: 0,
            resolver: resolver
        )
        XCTAssertTrue(reviewNonSpeaking.haptics.isEmpty)
        XCTAssertEqual(reviewScheduler.prepareCount, 0)
        reviewTransport.stop()
    }
#endif

    private struct TestAuthority: Codable, Equatable, Sendable {
        let revision: UInt64
        let digest: String
    }

    private struct LegacyFixture: Codable {
        let authority: TestAuthority
        let cursorSample: Int64
    }

    private func makeTimeline(
        includingNonSpeaking: Bool
    ) -> AudioTimeline {
        let narration = AudioEvent(
            cueID: AudioCueID("narration"),
            role: .narration,
            startSample: 0,
            durationSamples: 24_000,
            assetPath: "narration.caf",
            gain: 1,
            narrationBinding: NarrationCueBinding(
                manuscriptSegmentID: LocalizedStringID("segment"),
                manuscriptSegmentSHA256: String(repeating: "a", count: 64),
                scope: NarrationCueScope(
                    chapterID: ChapterID("chapter"),
                    arcID: ArcID("arc"),
                    beatID: BeatID("beat")
                )
            )
        )
        var events = [narration]
        if includingNonSpeaking {
            events.append(AudioEvent(
                cueID: AudioCueID("score"),
                role: .score,
                startSample: 0,
                durationSamples: 48_000,
                assetPath: "score.caf",
                gain: 0.5
            ))
            events.append(AudioEvent(
                cueID: AudioCueID("authored-silence"),
                role: .silence,
                startSample: 48_000,
                durationSamples: 100,
                assetPath: nil,
                gain: 1
            ))
        }
        return AudioTimeline(
            id: AudioTimelineID("scene-audio"),
            sampleRate: 48_000,
            events: events,
            haptics: [
                HapticEvent(
                    sample: 600,
                    kind: .contact,
                    intensity: 0.5,
                    sharpness: 0.4
                ),
            ]
        )
    }

#if os(iOS)
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "authored-audio-role-separation-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func writeAudioFile(
        to url: URL,
        channelCount: AVAudioChannelCount,
        frameCount: AVAudioFrameCount
    ) throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: channelCount,
            interleaved: false
        ))
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount
        if let channels = buffer.floatChannelData {
            for channel in 0 ..< Int(channelCount) {
                channels[channel].initialize(
                    repeating: 0.05,
                    count: Int(frameCount)
                )
            }
        }
        try file.write(from: buffer)
    }
#endif
}

#if os(iOS)
@MainActor
private final class RecordingHapticScheduler:
    NativeTimelineHapticScheduling {
    private final class Playback: NativeTimelineHapticPlayback {}

    private(set) var prepareCount = 0

    func prepare(
        haptics: [ScheduledHaptic],
        sampleRate _: Int
    ) throws -> (any NativeTimelineHapticPlayback)? {
        guard !haptics.isEmpty else { return nil }
        prepareCount += 1
        return Playback()
    }

    func start(
        _: any NativeTimelineHapticPlayback,
        context _: NativeTimelineHapticRuntimeContext,
        enabled _: Bool
    ) throws {}

    func scheduleStop(
        _: any NativeTimelineHapticPlayback,
        at _: NativeTimelineHapticBoundary
    ) throws {}

    func stopImmediately(_: any NativeTimelineHapticPlayback) {}

    func setEnabled(
        _: Bool,
        for _: any NativeTimelineHapticPlayback
    ) throws {}
}
#endif
