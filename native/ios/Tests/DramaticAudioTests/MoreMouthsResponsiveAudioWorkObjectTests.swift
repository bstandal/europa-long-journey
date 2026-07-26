import ContentKit
import DramaticAudio
import Foundation
import XCTest

final class MoreMouthsResponsiveAudioWorkObjectTests: XCTestCase {
    func testProvisionalMoreMouthsWorkObjectRunsThroughTheResponsiveRuntime() throws {
        let work = try Self.loadWorkObject()

        XCTAssertEqual(work.id, "more-mouths-responsive-audio-v1")
        XCTAssertEqual(work.status, "PROVISIONAL_NON_SHIPPING")
        XCTAssertEqual(work.shippingState, "PROHIBITED")
        XCTAssertEqual(work.trustDomain, "BACKSTAGE_AUDIO_PRODUCTION")
        XCTAssertEqual(
            work.causalBinding,
            MoreMouthsCausalBinding(
                controlID: "settlement-pressure",
                stages: [
                    MoreMouthsCausalStage(id: "new-hearths", requiredAmount: 0.32),
                    MoreMouthsCausalStage(id: "field-edges", requiredAmount: 0.66),
                    MoreMouthsCausalStage(id: "herd-lanes-and-daughters", requiredAmount: 1),
                ],
                completionEffectID: "effect-first-farmers-more-mouths-more-land",
                persistentTraceID: "trace-european-farming-belt",
                audioStageAccumulation: "PHASE_LEVEL_ONLY_UNTIL_RUNTIME_SUPPORTS_LATCHED_THRESHOLD_MIXES"
            )
        )
        try work.responsiveProgram.validate(timelines: work.timelines)

        XCTAssertEqual(
            work.timelines.map(\.id),
            [
                "more-mouths-approach-v1",
                "more-mouths-waiting-bed-v1",
                "more-mouths-engaged-bed-v1",
                "more-mouths-resistance-bed-v1",
                "more-mouths-consequence-v1",
            ]
        )
        XCTAssertTrue(work.timelines.allSatisfy { timeline in
            timeline.sampleRate == 48_000
                && timeline.haptics.isEmpty
                && !timeline.events.contains(where: { $0.role == .narration })
                && Set(timeline.events.map(\.role))
                    == Set([.score, .soundscape, .spatialDetail, .silence])
        })

        let timelineByID = Dictionary(
            uniqueKeysWithValues: work.timelines.map { ($0.id, $0) }
        )
        XCTAssertEqual(work.authoredSilence.count, 5)
        XCTAssertEqual(
            Set(work.authoredSilence.map(\.timelineID)),
            Set(work.timelines.map(\.id))
        )
        for silence in work.authoredSilence {
            XCTAssertEqual(silence.sampleRate, 48_000)
            XCTAssertGreaterThan(silence.durationSamples, 0)
            let timeline = try XCTUnwrap(timelineByID[silence.timelineID])
            let event = try XCTUnwrap(timeline.events.first { event in
                event.role == .silence
                    && event.startSample == silence.startSample
                    && event.durationSamples == silence.durationSamples
            })
            XCTAssertTrue(event.cueID.rawValue.hasSuffix("-\(silence.id)"))
            XCTAssertNil(event.assetPath)
        }

        let metadata = Dictionary(
            uniqueKeysWithValues: work.audioAssetMetadata.map { item in
                (
                    item.path,
                    AudioAssetMetadata(
                        path: item.path,
                        sampleRate: item.sampleRate,
                        frameCount: item.frameCount,
                        channelCount: item.channelCount
                    )
                )
            }
        )
        XCTAssertEqual(metadata.count, 15)
        XCTAssertTrue(work.audioAssetMetadata.allSatisfy {
            $0.sampleRate == 48_000 && $0.channelCount == 2
        })

        for bed in work.responsiveProgram.interactionBeds {
            let timeline = try XCTUnwrap(timelineByID[bed.timelineID])
            XCTAssertEqual(timeline.authoredDurationSamples, 15 * 48_000)
            let regionPath = "/\(bed.phase.rawValue)/"
            let bedMetadata = work.audioAssetMetadata.filter {
                $0.path.contains(regionPath)
            }
            XCTAssertEqual(bedMetadata.count, 3)
            XCTAssertTrue(bedMetadata.allSatisfy { $0.frameCount == 15 * 48_000 })
        }

        var runtime = try ResponsiveAudioProgramRuntime(
            program: work.responsiveProgram,
            timelines: work.timelines
        )
        let approach = try XCTUnwrap(timelineByID[work.responsiveProgram.approachTimelineID])
        try runtime.resume()
        try runtime.advance(bySamples: approach.authoredDurationSamples)
        XCTAssertEqual(runtime.stage, .interaction)
        XCTAssertEqual(runtime.interactionPhase, .waiting)
        XCTAssertEqual(runtime.timelineID, "more-mouths-waiting-bed-v1")
        XCTAssertEqual(runtime.cursorSample, 0)

        let engagedBed = try XCTUnwrap(
            work.responsiveProgram.interactionBed(for: .engaged)
        )
        try runtime.selectInteractionPhase(.engaged)
        let engagedSilence = try XCTUnwrap(
            work.authoredSilence.first { $0.timelineID == engagedBed.timelineID }
        )
        try runtime.advance(bySamples: engagedSilence.startSample)
        let engagedPlan = try XCTUnwrap(
            runtime.makePlaybackPlan(assetMetadata: metadata)
        )
        XCTAssertEqual(
            engagedPlan.repetition,
            .loop(iteration: 0, durationSamples: 15 * 48_000)
        )
        XCTAssertEqual(
            engagedPlan.layerStates,
            ResponsiveAudioLayerStateSelection(
                scoreStateID: "households-open-ground",
                soundscapeStateID: "work-and-herds-move-outward"
            )
        )
        XCTAssertTrue(engagedPlan.isInsideAuthoredSilence)
        XCTAssertEqual(
            engagedPlan.authoredSilenceCueIDs,
            [
                try XCTUnwrap(
                    timelineByID[engagedBed.timelineID]?.events.first {
                        $0.role == .silence
                    }
                ).cueID,
            ]
        )

        let beforePhaseChange = runtime.snapshot()
        try runtime.selectInteractionPhase(.resistance)
        XCTAssertEqual(runtime.cursorSample, beforePhaseChange.cursorSample)
        XCTAssertEqual(runtime.loopIteration, beforePhaseChange.loopIteration)
        XCTAssertEqual(runtime.timelineID, "more-mouths-resistance-bed-v1")

        let samplesToBoundary = 15 * 48_000 - runtime.cursorSample
        try runtime.advance(bySamples: samplesToBoundary + 1_234)
        XCTAssertEqual(runtime.loopIteration, 1)
        XCTAssertEqual(runtime.cursorSample, 1_234)
        try runtime.selectInteractionPhase(.engaged)
        XCTAssertEqual(runtime.loopIteration, 1)
        XCTAssertEqual(runtime.cursorSample, 1_234)
    }

    func testMoreMouthsHapticsAndNarrationStayFailClosed() throws {
        let work = try Self.loadWorkObject()

        XCTAssertEqual(
            work.hapticProgram.vocabulary,
            [.contact, .drag, .resistance, .transfer, .break, .seal]
        )
        XCTAssertEqual(
            work.hapticProgram.activeMoreMouthsSemantics,
            [.drag, .break, .seal]
        )
        XCTAssertEqual(
            work.hapticProgram.reservedForOtherGrammars,
            [.contact, .resistance, .transfer]
        )
        XCTAssertEqual(
            work.hapticProgram.runtimeBindings,
            [
                MoreMouthsHapticRuntimeBinding(
                    trigger: "transform-drag",
                    semantic: .drag,
                    durableCommitRequired: false
                ),
                MoreMouthsHapticRuntimeBinding(
                    trigger: "causal-threshold-crossed",
                    semantic: .break,
                    durableCommitRequired: false
                ),
                MoreMouthsHapticRuntimeBinding(
                    trigger: "durable-completion",
                    semantic: .seal,
                    durableCommitRequired: true
                ),
            ]
        )
        XCTAssertEqual(work.hapticProgram.loopedTimelineHaptics, "FORBIDDEN")

        XCTAssertEqual(work.narrationSlots.count, 2)
        XCTAssertEqual(
            Set(work.narrationSlots.map(\.timelineID)),
            Set(["more-mouths-approach-v1", "more-mouths-consequence-v1"])
        )
        XCTAssertTrue(work.narrationSlots.allSatisfy { slot in
            slot.status == "MISSING_EDITOR_SELECTED_NARRATION_MASTER"
                && slot.shippingBlock
                && !slot.segments.isEmpty
        })
        let segmentIDsByTimeline = Dictionary(
            uniqueKeysWithValues: work.narrationSlots.map { slot in
                (
                    slot.timelineID.rawValue,
                    slot.segments.map(\.manuscriptSegmentID.rawValue)
                )
            }
        )
        XCTAssertEqual(
            segmentIDsByTimeline["more-mouths-approach-v1"],
            ["ff-growth-01", "ff-growth-02"]
        )
        XCTAssertEqual(
            segmentIDsByTimeline["more-mouths-consequence-v1"],
            ["ff-contraction-01", "ff-contraction-02"]
        )
        let audiblePaths = Set(work.timelines.flatMap { timeline in
            timeline.events.compactMap(\.assetPath)
        })
        XCTAssertTrue(work.narrationSlots.allSatisfy { slot in
            !audiblePaths.contains(slot.requiredAssetPath)
        })
    }

    private static func loadWorkObject() throws -> MoreMouthsWorkObject {
#if os(iOS)
        let bundle = Bundle(for: MoreMouthsResponsiveAudioWorkObjectTests.self)
        let file = try XCTUnwrap(
            bundle.url(
                forResource: "more-mouths-responsive-work-object",
                withExtension: "json"
            )
        )
#else
        let iosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = iosRoot
            .deletingLastPathComponent()
            .appendingPathComponent(
                "audio/score-soundscape/more-mouths-responsive-v1/more-mouths-responsive-work-object.json"
            )
#endif
        return try JSONDecoder().decode(
            MoreMouthsWorkObject.self,
            from: Data(contentsOf: file)
        )
    }
}

private struct MoreMouthsWorkObject: Decodable {
    let id: String
    let status: String
    let shippingState: String
    let trustDomain: String
    let responsiveProgram: ResponsiveAudioProgramSpec
    let causalBinding: MoreMouthsCausalBinding
    let timelines: [AudioTimeline]
    let audioAssetMetadata: [MoreMouthsAudioAssetMetadata]
    let narrationSlots: [MoreMouthsNarrationSlot]
    let hapticProgram: MoreMouthsHapticProgram
    let authoredSilence: [MoreMouthsAuthoredSilence]
}

private struct MoreMouthsCausalBinding: Decodable, Equatable {
    let controlID: String
    let stages: [MoreMouthsCausalStage]
    let completionEffectID: String
    let persistentTraceID: String
    let audioStageAccumulation: String
}

private struct MoreMouthsCausalStage: Decodable, Equatable {
    let id: String
    let requiredAmount: Double
}

private struct MoreMouthsAudioAssetMetadata: Decodable {
    let path: String
    let sampleRate: Int
    let frameCount: Int64
    let channelCount: Int
}

private struct MoreMouthsNarrationSlot: Decodable {
    let timelineID: AudioTimelineID
    let status: String
    let requiredAssetPath: String
    let segments: [MoreMouthsNarrationSegment]
    let shippingBlock: Bool
}

private struct MoreMouthsNarrationSegment: Decodable {
    let manuscriptSegmentID: LocalizedStringID
    let manuscriptSegmentSHA256: String
}

private struct MoreMouthsHapticProgram: Decodable {
    let vocabulary: [HapticSemantic]
    let activeMoreMouthsSemantics: [HapticSemantic]
    let reservedForOtherGrammars: [HapticSemantic]
    let runtimeBindings: [MoreMouthsHapticRuntimeBinding]
    let loopedTimelineHaptics: String
}

private struct MoreMouthsHapticRuntimeBinding: Decodable, Equatable {
    let trigger: String
    let semantic: HapticSemantic
    let durableCommitRequired: Bool
}

private struct MoreMouthsAuthoredSilence: Decodable {
    let timelineID: AudioTimelineID
    let sampleRate: Int
    let startSample: Int64
    let durationSamples: Int64
    let id: String
    let reason: String
}
