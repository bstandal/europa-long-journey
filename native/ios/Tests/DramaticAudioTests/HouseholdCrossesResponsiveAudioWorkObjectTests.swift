import ContentKit
import DramaticAudio
import Foundation
import XCTest

final class HouseholdCrossesResponsiveAudioWorkObjectTests: XCTestCase {
    func testProvisionalHouseholdCrossesWorkObjectRunsThroughTheResponsiveRuntime() throws {
        let work = try Self.loadWorkObject()

        XCTAssertEqual(work.id, "household-crosses-responsive-audio-v1")
        XCTAssertEqual(work.status, "PROVISIONAL_NON_SHIPPING")
        XCTAssertEqual(work.shippingState, "PROHIBITED")
        XCTAssertEqual(work.trustDomain, "BACKSTAGE_AUDIO_PRODUCTION")
        XCTAssertEqual(
            work.causalBinding,
            HouseholdCrossesCausalBinding(
                controlID: "household-route-progress",
                originAnchorID: "western-anatolia",
                stages: [
                    HouseholdCrossesCausalStage(id: "aegean-islands", requiredAmount: 0.333333),
                    HouseholdCrossesCausalStage(id: "thessaly", requiredAmount: 0.666667),
                    HouseholdCrossesCausalStage(id: "danube-corridor", requiredAmount: 1),
                ],
                completionEffectID: "effect-first-farmers-a-household-crosses",
                packageTraceID: "route-aegean-danube",
                persistentTraceID: "trace-european-farming-belt",
                audioStageAccumulation: "PHASE_LEVEL_ONLY_VISUAL_REDUCER_OWNS_LATCHED_ANCHORS"
            )
        )
        try work.responsiveProgram.validate(timelines: work.timelines)

        XCTAssertEqual(
            work.timelines.map(\.id),
            [
                "household-crosses-approach-v1",
                "household-crosses-waiting-bed-v1",
                "household-crosses-engaged-bed-v1",
                "household-crosses-resistance-bed-v1",
                "household-crosses-consequence-v1",
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
        XCTAssertEqual(
            work.authoredSilence.map { silence in
                HouseholdCrossesSilenceIdentity(
                    timelineID: silence.timelineID.rawValue,
                    startSample: silence.startSample,
                    durationSamples: silence.durationSamples
                )
            },
            [
                HouseholdCrossesSilenceIdentity(
                    timelineID: "household-crosses-approach-v1",
                    startSample: 2_652_000,
                    durationSamples: 132_000
                ),
                HouseholdCrossesSilenceIdentity(
                    timelineID: "household-crosses-waiting-bed-v1",
                    startSample: 710_400,
                    durationSamples: 9_600
                ),
                HouseholdCrossesSilenceIdentity(
                    timelineID: "household-crosses-engaged-bed-v1",
                    startSample: 350_400,
                    durationSamples: 7_680
                ),
                HouseholdCrossesSilenceIdentity(
                    timelineID: "household-crosses-resistance-bed-v1",
                    startSample: 554_400,
                    durationSamples: 9_600
                ),
                HouseholdCrossesSilenceIdentity(
                    timelineID: "household-crosses-consequence-v1",
                    startSample: 744_000,
                    durationSamples: 216_000
                ),
            ]
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
        XCTAssertEqual(runtime.timelineID, "household-crosses-waiting-bed-v1")
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
                scoreStateID: "four-parts-cross-together",
                soundscapeStateID: "wake-carries-household"
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
        XCTAssertEqual(runtime.timelineID, "household-crosses-resistance-bed-v1")

        let samplesToBoundary = 15 * 48_000 - runtime.cursorSample
        try runtime.advance(bySamples: samplesToBoundary + 1_234)
        XCTAssertEqual(runtime.loopIteration, 1)
        XCTAssertEqual(runtime.cursorSample, 1_234)
        try runtime.selectInteractionPhase(.engaged)
        XCTAssertEqual(runtime.loopIteration, 1)
        XCTAssertEqual(runtime.cursorSample, 1_234)
    }

    func testHouseholdCrossesHapticsAndNarrationStayFailClosed() throws {
        let work = try Self.loadWorkObject()

        XCTAssertEqual(
            work.hapticProgram.vocabulary,
            [.contact, .drag, .resistance, .transfer, .break, .seal]
        )
        XCTAssertEqual(
            work.hapticProgram.activeHouseholdCrossesSemantics,
            [.contact, .drag, .seal]
        )
        XCTAssertEqual(
            work.hapticProgram.reservedForOtherGrammars,
            [.resistance, .transfer, .break]
        )
        XCTAssertEqual(
            work.hapticProgram.runtimeBindings,
            [
                HouseholdCrossesHapticRuntimeBinding(
                    trigger: "trace-origin-contact",
                    semantic: .contact,
                    durableCommitRequired: false
                ),
                HouseholdCrossesHapticRuntimeBinding(
                    trigger: "trace-intermediate-anchor-accepted",
                    semantic: .contact,
                    durableCommitRequired: false
                ),
                HouseholdCrossesHapticRuntimeBinding(
                    trigger: "trace-viable-movement-throttled",
                    semantic: .drag,
                    durableCommitRequired: false
                ),
                HouseholdCrossesHapticRuntimeBinding(
                    trigger: "trace-destination-durable-commit",
                    semantic: .seal,
                    durableCommitRequired: true
                ),
            ]
        )
        XCTAssertEqual(work.hapticProgram.destinationPreliminaryContact, "FORBIDDEN")
        XCTAssertEqual(work.hapticProgram.resistanceSemantic, "FORBIDDEN")
        XCTAssertEqual(work.hapticProgram.loopedTimelineHaptics, "FORBIDDEN")

        XCTAssertEqual(work.narrationSlots.count, 2)
        XCTAssertEqual(
            Set(work.narrationSlots.map(\.timelineID)),
            Set(["household-crosses-approach-v1", "household-crosses-consequence-v1"])
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
            segmentIDsByTimeline["household-crosses-approach-v1"],
            ["ff-crossing-01", "ff-crossing-02"]
        )
        XCTAssertEqual(
            segmentIDsByTimeline["household-crosses-consequence-v1"],
            ["ff-system-01", "ff-system-02"]
        )
        let segmentHashesByTimeline = Dictionary(
            uniqueKeysWithValues: work.narrationSlots.map { slot in
                (
                    slot.timelineID.rawValue,
                    slot.segments.map(\.manuscriptSegmentSHA256)
                )
            }
        )
        XCTAssertEqual(
            segmentHashesByTimeline["household-crosses-approach-v1"],
            [
                "c79a713d8cd503a9162a11d454047c67a1bcf4fe666c417bcc73e226eedfc814",
                "f975c91529a3c07afaf1f87c5f492ba37417d39823976a2a6ed3b92a75da2e75",
            ]
        )
        let audiblePaths = Set(work.timelines.flatMap { timeline in
            timeline.events.compactMap(\.assetPath)
        })
        XCTAssertTrue(work.narrationSlots.allSatisfy { slot in
            !audiblePaths.contains(slot.requiredAssetPath)
        })
        XCTAssertTrue(work.editorialBlocks.isEmpty)
        XCTAssertEqual(
            work.gates.narrationF5SowingSeason,
            "PASS_EDITOR_REPAIR_BOUND_TO_FROZEN_TEXT"
        )
        XCTAssertEqual(
            work.acousticBoundaries.soundscapeProhibitedClaims,
            [
                "sail, mast, rigging or wind propulsion",
                "specific paddle, oar, rowing action or cadence",
                "plank, keel, deck, nail or metal-fitting construction",
                "storm or heroic ocean",
                "species calls, bells, tack, gallop or stampede",
                "human speech, chant or crowd",
                "procedural tones represented as documented waves or historical evidence",
            ]
        )
    }

    private static func loadWorkObject() throws -> HouseholdCrossesWorkObject {
#if os(iOS)
        let bundle = Bundle(for: HouseholdCrossesResponsiveAudioWorkObjectTests.self)
        let file = try XCTUnwrap(
            bundle.url(
                forResource: "household-crosses-responsive-work-object",
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
                "audio/score-soundscape/household-crosses-responsive-v1/household-crosses-responsive-work-object.json"
            )
#endif
        return try JSONDecoder().decode(
            HouseholdCrossesWorkObject.self,
            from: Data(contentsOf: file)
        )
    }
}

private struct HouseholdCrossesWorkObject: Decodable {
    let id: String
    let status: String
    let shippingState: String
    let trustDomain: String
    let responsiveProgram: ResponsiveAudioProgramSpec
    let causalBinding: HouseholdCrossesCausalBinding
    let timelines: [AudioTimeline]
    let audioAssetMetadata: [HouseholdCrossesAudioAssetMetadata]
    let narrationSlots: [HouseholdCrossesNarrationSlot]
    let hapticProgram: HouseholdCrossesHapticProgram
    let editorialBlocks: [HouseholdCrossesEditorialBlock]
    let acousticBoundaries: HouseholdCrossesAcousticBoundaries
    let authoredSilence: [HouseholdCrossesAuthoredSilence]
    let gates: HouseholdCrossesGates
}

private struct HouseholdCrossesCausalBinding: Decodable, Equatable {
    let controlID: String
    let originAnchorID: String
    let stages: [HouseholdCrossesCausalStage]
    let completionEffectID: String
    let packageTraceID: String
    let persistentTraceID: String
    let audioStageAccumulation: String
}

private struct HouseholdCrossesCausalStage: Decodable, Equatable {
    let id: String
    let requiredAmount: Double
}

private struct HouseholdCrossesAudioAssetMetadata: Decodable {
    let path: String
    let sampleRate: Int
    let frameCount: Int64
    let channelCount: Int
}

private struct HouseholdCrossesNarrationSlot: Decodable {
    let timelineID: AudioTimelineID
    let status: String
    let requiredAssetPath: String
    let segments: [HouseholdCrossesNarrationSegment]
    let shippingBlock: Bool
}

private struct HouseholdCrossesNarrationSegment: Decodable {
    let manuscriptSegmentID: LocalizedStringID
    let manuscriptSegmentSHA256: String
}

private struct HouseholdCrossesHapticProgram: Decodable {
    let vocabulary: [HapticSemantic]
    let activeHouseholdCrossesSemantics: [HapticSemantic]
    let reservedForOtherGrammars: [HapticSemantic]
    let runtimeBindings: [HouseholdCrossesHapticRuntimeBinding]
    let destinationPreliminaryContact: String
    let resistanceSemantic: String
    let loopedTimelineHaptics: String
}

private struct HouseholdCrossesHapticRuntimeBinding: Decodable, Equatable {
    let trigger: String
    let semantic: HapticSemantic
    let durableCommitRequired: Bool
}

private struct HouseholdCrossesAuthoredSilence: Decodable {
    let timelineID: AudioTimelineID
    let sampleRate: Int
    let startSample: Int64
    let durationSamples: Int64
    let id: String
    let reason: String
}

private struct HouseholdCrossesEditorialBlock: Decodable, Equatable {
    let code: String
    let manuscriptSegmentID: String
    let status: String
    let issue: String
    let publicProseMutation: String
    let shippingBlock: Bool
}

private struct HouseholdCrossesGates: Decodable {
    let narrationF5SowingSeason: String
}

private struct HouseholdCrossesAcousticBoundaries: Decodable {
    let scoreProhibitedClaims: [String]
    let soundscapeProhibitedClaims: [String]
}

private struct HouseholdCrossesSilenceIdentity: Equatable {
    let timelineID: String
    let startSample: Int64
    let durationSamples: Int64
}
