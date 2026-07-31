import ContentKit
import DramaticAudio
import Foundation
import XCTest

final class ThreeRecordsResponsiveAudioWorkObjectTests: XCTestCase {
    func testWorkObjectDecodesTheExactSharedAssetAndCausalMixContract() throws {
        let work = try Self.loadWorkObject()

        XCTAssertEqual(work.id, "three-records-responsive-audio-v1")
        XCTAssertEqual(work.status, "PROVISIONAL_NON_SHIPPING")
        XCTAssertEqual(work.shippingState, "PROHIBITED")
        XCTAssertEqual(work.trustDomain, "BACKSTAGE_AUDIO_PRODUCTION")
        XCTAssertEqual(
            work.causalBinding,
            ThreeRecordsCausalBinding(
                controlID: "time-layer",
                stages: [
                    ThreeRecordsCausalStage(id: "river-communities", requiredAmount: 0.33),
                    ThreeRecordsCausalStage(id: "contact-households", requiredAmount: 0.66),
                    ThreeRecordsCausalStage(id: "later-settlements", requiredAmount: 1),
                ],
                completionEffectID: "effect-first-farmers-at-the-iron-gates",
                persistentTraceID: "trace-european-farming-belt",
                audioStageAccumulation: "RUNTIME_PERSISTS_CAUSAL_STAGE_AND_APPLIES_MONOTONIC_GAIN_TRANSPORT"
            )
        )
        try work.responsiveProgram.validate(timelines: work.timelines)

        let mix = try XCTUnwrap(work.responsiveProgram.causalMix)
        XCTAssertEqual(mix.rampDurationSamples, 9_600)
        XCTAssertEqual(
            mix.layers.map(\.id.rawValue),
            [
                "gorge-current", "river-gear", "landing-work",
                "settlement-hearths", "carried-grain", "domestic-herd",
                "household-voices",
            ]
        )
        XCTAssertEqual(mix.states.map(\.completedStageCount), [0, 1, 2, 3])
        XCTAssertEqual(
            mix.states.map { $0.layerGains.map(\.gain) },
            [
                [0.82, 0, 0, 0, 0, 0, 0],
                [0.82, 0.32, 0.28, 0.18, 0, 0, 0.14],
                [0.82, 0.42, 0.38, 0.28, 0.3, 0.24, 0.34],
                [0.82, 0.48, 0.44, 0.34, 0.4, 0.32, 0.42],
            ]
        )

        let timelines = Dictionary(uniqueKeysWithValues: work.timelines.map { ($0.id, $0) })
        XCTAssertEqual(work.audioAssetMetadata.count, 16)
        XCTAssertTrue(work.audioAssetMetadata.allSatisfy {
            $0.sampleRate == 48_000 && $0.channelCount == 2
        })
        let sharedMetadata = work.audioAssetMetadata.filter {
            $0.path.contains("/interaction/shared/")
        }
        XCTAssertEqual(sharedMetadata.count, 7)
        XCTAssertTrue(sharedMetadata.allSatisfy { $0.frameCount == 720_000 })

        for layer in mix.layers {
            let expectedPath = "audio/first-farmers/three-records-responsive-v1/interaction/shared/\(layer.id.rawValue).wav"
            XCTAssertEqual(layer.assetPath, expectedPath)
            for phase in ResponsiveInteractionAudioPhase.allCases {
                let bed = try XCTUnwrap(work.responsiveProgram.interactionBed(for: phase))
                let timeline = try XCTUnwrap(timelines[bed.timelineID])
                let cueID = layer.cueIDs.cueID(for: phase)
                let event = try XCTUnwrap(timeline.events.first { $0.cueID == cueID })
                XCTAssertEqual(event.assetPath, expectedPath)
                XCTAssertEqual(event.startSample, 0)
                XCTAssertEqual(event.durationSamples, 720_000)
                XCTAssertTrue(event.role == .soundscape || event.role == .spatialDetail)
            }
        }

        XCTAssertTrue(work.timelines.allSatisfy { timeline in
            timeline.sampleRate == 48_000
                && timeline.haptics.isEmpty
                && !timeline.events.contains { [.silence, .narration].contains($0.role) }
        })
        XCTAssertEqual(work.authoredQuiet.count, 5)
        XCTAssertEqual(
            work.authoredQuiet.map {
                ThreeRecordsQuietIdentity(
                    timelineID: $0.timelineID.rawValue,
                    startSample: $0.startSample,
                    durationSamples: $0.durationSamples
                )
            },
            [
                .init(timelineID: "three-records-approach-v1", startSample: 0, durationSamples: 96_000),
                .init(timelineID: "three-records-waiting-bed-v1", startSample: 710_400, durationSamples: 9_600),
                .init(timelineID: "three-records-engaged-bed-v1", startSample: 710_400, durationSamples: 9_600),
                .init(timelineID: "three-records-resistance-bed-v1", startSample: 710_400, durationSamples: 9_600),
                .init(timelineID: "three-records-consequence-v1", startSample: 0, durationSamples: 144_000),
            ]
        )
        XCTAssertTrue(work.authoredQuiet.allSatisfy {
            $0.scope == "SOURCE_BOUND_QUIET_NOT_GLOBAL_TIMELINE_SILENCE"
                && $0.preservedCueIDs.count == 1
                && !$0.zeroedCueIDs.isEmpty
        })
    }

    func testCausalStagePersistsAndSelectsMonotonicGainsWithoutMovingTheClock() throws {
        let work = try Self.loadWorkObject()
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
        var runtime = try ResponsiveAudioProgramRuntime(
            program: work.responsiveProgram,
            timelines: work.timelines
        )
        try runtime.resume()
        try runtime.advance(bySamples: 45 * 48_000)
        XCTAssertEqual(runtime.stage, .interaction)
        XCTAssertEqual(runtime.interactionPhase, .waiting)

        let zeroPlan = try XCTUnwrap(runtime.makePlaybackPlan(assetMetadata: metadata))
        XCTAssertEqual(zeroPlan.causalMix?.completedStageCount, 0)
        XCTAssertEqual(zeroPlan.causalMix?.layers.map(\.targetGain), [0.82, 0, 0, 0, 0, 0, 0])

        _ = try runtime.selectCausalStage(.init(completedStageCount: 1))
        let clockBeforePhaseChange = runtime.snapshot()
        let firstPlan = try XCTUnwrap(runtime.makePlaybackPlan(assetMetadata: metadata))
        XCTAssertEqual(firstPlan.causalMix?.rampDurationSamples, 9_600)
        XCTAssertEqual(firstPlan.causalMix?.layers.map(\.targetGain), [0.82, 0.32, 0.28, 0.18, 0, 0, 0.14])

        try runtime.selectInteractionPhase(.engaged)
        XCTAssertEqual(runtime.cursorSample, clockBeforePhaseChange.cursorSample)
        XCTAssertEqual(runtime.loopIteration, clockBeforePhaseChange.loopIteration)
        XCTAssertEqual(runtime.causalStage?.completedStageCount, 1)
        let engagedPlan = try XCTUnwrap(runtime.makePlaybackPlan(assetMetadata: metadata))
        XCTAssertEqual(engagedPlan.causalMix?.layers.first?.cueID, "engaged-gorge-current")
        XCTAssertEqual(
            engagedPlan.causalMix?.layers.first?.assetPath,
            zeroPlan.causalMix?.layers.first?.assetPath
        )

        let restored = try ResponsiveAudioProgramRuntime(
            program: work.responsiveProgram,
            timelines: work.timelines,
            restoring: runtime.snapshot()
        )
        XCTAssertEqual(restored.causalStage?.completedStageCount, 1)
        XCTAssertEqual(restored.cursorSample, runtime.cursorSample)
        XCTAssertEqual(restored.timelineID, runtime.timelineID)

        _ = try runtime.selectCausalStage(.init(completedStageCount: 2))
        let secondPlan = try XCTUnwrap(runtime.makePlaybackPlan(assetMetadata: metadata))
        let firstGains = try XCTUnwrap(firstPlan.causalMix?.layers.map(\.targetGain))
        let secondGains = try XCTUnwrap(secondPlan.causalMix?.layers.map(\.targetGain))
        XCTAssertTrue(zip(firstGains, secondGains).allSatisfy { pair in
            pair.1 >= pair.0
        })
        XCTAssertThrowsError(
            try runtime.selectCausalStage(.init(completedStageCount: 1))
        ) { error in
            XCTAssertEqual(
                error as? ResponsiveAudioRuntimeError,
                .causalStageRegression(current: 2, proposed: 1)
            )
        }
    }

    func testNarrationAndSemanticHapticsRemainFailClosed() throws {
        let work = try Self.loadWorkObject()
        XCTAssertEqual(work.hapticProgram.vocabulary, [.contact, .drag, .resistance, .transfer, .break, .seal])
        XCTAssertEqual(work.hapticProgram.activeThreeRecordsSemantics, [.drag, .break, .seal])
        XCTAssertEqual(work.hapticProgram.reservedForOtherGrammars, [.contact, .resistance, .transfer])
        XCTAssertEqual(
            work.hapticProgram.runtimeBindings,
            [
                .init(trigger: "transform-drag", completedStageCounts: nil, semantic: .drag, durableCommitRequired: false),
                .init(trigger: "causal-threshold-crossed", completedStageCounts: [1, 2, 3], semantic: .break, durableCommitRequired: false),
                .init(trigger: "durable-completion", completedStageCounts: nil, semantic: .seal, durableCommitRequired: true),
            ]
        )
        XCTAssertEqual(work.hapticProgram.loopedTimelineHaptics, "FORBIDDEN")

        XCTAssertEqual(work.narrationSlots.count, 2)
        XCTAssertEqual(
            work.narrationSlots.map { $0.segments.map(\.manuscriptSegmentID.rawValue) },
            [
                ["ff-records-01", "ff-records-02"],
                ["ff-frontier-consequence-01", "ff-frontier-consequence-02"],
            ]
        )
        XCTAssertEqual(
            work.narrationSlots.map { $0.segments.map(\.manuscriptSegmentSHA256) },
            [
                [
                    "2e0bb347d1c361da279ad76505fa9741e0e0026b82b06d81677a13bf9e258ac5",
                    "84f1d3f284fff9f26af1e53fa49f7ccf608a2ab827ce4168949e949c813569a8",
                ],
                [
                    "b00525cb8d6e7d560a7adfe0b1894976ae43ca38638fb22f51af0a5f7495781d",
                    "61a833e2bcfd178acf647e72b68a7be0b3d9849026242e5795107b90d76c5159",
                ],
            ]
        )
        let audiblePaths = Set(work.timelines.flatMap { $0.events.compactMap(\.assetPath) })
        XCTAssertTrue(work.narrationSlots.allSatisfy {
            $0.status == "MISSING_EDITOR_SELECTED_NARRATION_MASTER"
                && $0.shippingBlock
                && !audiblePaths.contains($0.requiredAssetPath)
        })
        XCTAssertEqual(work.gates.artisticApproval, "OPEN")
        XCTAssertEqual(work.gates.shippingApproval, "PROHIBITED")
    }

    private static func loadWorkObject() throws -> ThreeRecordsWorkObject {
#if os(iOS)
        let bundle = Bundle(for: ThreeRecordsResponsiveAudioWorkObjectTests.self)
        let file = try XCTUnwrap(
            bundle.url(
                forResource: "three-records-responsive-work-object",
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
                "audio/score-soundscape/three-records-responsive-v1/three-records-responsive-work-object.json"
            )
#endif
        return try JSONDecoder().decode(
            ThreeRecordsWorkObject.self,
            from: Data(contentsOf: file)
        )
    }
}

private struct ThreeRecordsWorkObject: Decodable {
    let id: String
    let status: String
    let shippingState: String
    let trustDomain: String
    let responsiveProgram: ResponsiveAudioProgramSpec
    let causalBinding: ThreeRecordsCausalBinding
    let timelines: [AudioTimeline]
    let audioAssetMetadata: [ThreeRecordsAudioAssetMetadata]
    let narrationSlots: [ThreeRecordsNarrationSlot]
    let hapticProgram: ThreeRecordsHapticProgram
    let authoredQuiet: [ThreeRecordsAuthoredQuiet]
    let gates: ThreeRecordsGates
}

private struct ThreeRecordsCausalBinding: Decodable, Equatable {
    let controlID: String
    let stages: [ThreeRecordsCausalStage]
    let completionEffectID: String
    let persistentTraceID: String
    let audioStageAccumulation: String
}

private struct ThreeRecordsCausalStage: Decodable, Equatable {
    let id: String
    let requiredAmount: Double
}

private struct ThreeRecordsAudioAssetMetadata: Decodable {
    let path: String
    let sampleRate: Int
    let frameCount: Int64
    let channelCount: Int
}

private struct ThreeRecordsNarrationSlot: Decodable {
    let timelineID: AudioTimelineID
    let status: String
    let requiredAssetPath: String
    let segments: [ThreeRecordsNarrationSegment]
    let shippingBlock: Bool
}

private struct ThreeRecordsNarrationSegment: Decodable {
    let manuscriptSegmentID: LocalizedStringID
    let manuscriptSegmentSHA256: String
}

private struct ThreeRecordsHapticProgram: Decodable {
    let vocabulary: [HapticSemantic]
    let activeThreeRecordsSemantics: [HapticSemantic]
    let reservedForOtherGrammars: [HapticSemantic]
    let runtimeBindings: [ThreeRecordsHapticRuntimeBinding]
    let loopedTimelineHaptics: String
}

private struct ThreeRecordsHapticRuntimeBinding: Decodable, Equatable {
    let trigger: String
    let completedStageCounts: [Int]?
    let semantic: HapticSemantic
    let durableCommitRequired: Bool
}

private struct ThreeRecordsAuthoredQuiet: Decodable {
    let timelineID: AudioTimelineID
    let sampleRate: Int
    let startSample: Int64
    let durationSamples: Int64
    let id: String
    let reason: String
    let scope: String
    let preservedCueIDs: [AudioCueID]
    let zeroedCueIDs: [AudioCueID]
}

private struct ThreeRecordsGates: Decodable {
    let artisticApproval: String
    let shippingApproval: String
}

private struct ThreeRecordsQuietIdentity: Equatable {
    let timelineID: String
    let startSample: Int64
    let durationSamples: Int64
}
