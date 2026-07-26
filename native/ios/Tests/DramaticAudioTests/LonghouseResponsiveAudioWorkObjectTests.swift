import ContentKit
import DramaticAudio
import Foundation
import XCTest

final class LonghouseResponsiveAudioWorkObjectTests: XCTestCase {
    func testProvisionalLonghouseWorkObjectRunsThroughTheResponsiveRuntime() throws {
        let work = try Self.loadWorkObject()

        XCTAssertEqual(work.id, "longhouse-responsive-audio-v1")
        XCTAssertEqual(work.status, "PROVISIONAL_NON_SHIPPING")
        XCTAssertEqual(work.shippingState, "PROHIBITED")
        XCTAssertEqual(work.trustDomain, "BACKSTAGE_AUDIO_PRODUCTION")
        try work.responsiveProgram.validate(timelines: work.timelines)

        XCTAssertEqual(work.timelines.count, 5)
        XCTAssertTrue(work.timelines.allSatisfy { timeline in
            timeline.sampleRate == 48_000
                && timeline.haptics.isEmpty
                && !timeline.events.contains(where: { $0.role == .narration })
        })
        XCTAssertEqual(
            Set(work.timelines.flatMap { $0.events.map(\.role) }),
            Set([.score, .soundscape, .spatialDetail, .silence])
        )

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

        var runtime = try ResponsiveAudioProgramRuntime(
            program: work.responsiveProgram,
            timelines: work.timelines
        )
        try runtime.resume()
        try runtime.advance(bySamples: 48 * 48_000)
        XCTAssertEqual(runtime.stage, .interaction)
        XCTAssertEqual(runtime.interactionPhase, .waiting)
        XCTAssertEqual(runtime.timelineID, "longhouse-waiting-bed-v1")

        try runtime.selectInteractionPhase(.engaged)
        try runtime.advance(bySamples: 7 * 48_000 + 15_600)
        let engagedPlan = try XCTUnwrap(runtime.makePlaybackPlan(assetMetadata: metadata))
        XCTAssertEqual(engagedPlan.repetition, .loop(iteration: 0, durationSamples: 720_000))
        XCTAssertEqual(
            engagedPlan.layerStates,
            ResponsiveAudioLayerStateSelection(
                scoreStateID: "accepted-parts-take-weight",
                soundscapeStateID: "accepted-parts-take-weight"
            )
        )
        XCTAssertTrue(engagedPlan.isInsideAuthoredSilence)
        XCTAssertEqual(engagedPlan.authoredSilenceCueIDs, ["engaged-accepted-load"])

        let beforePhaseChange = runtime.snapshot()
        try runtime.selectInteractionPhase(.resistance)
        XCTAssertEqual(runtime.cursorSample, beforePhaseChange.cursorSample)
        XCTAssertEqual(runtime.loopIteration, beforePhaseChange.loopIteration)
        XCTAssertEqual(runtime.timelineID, "longhouse-resistance-bed-v1")
    }

    func testLonghouseHapticsAndNarrationStayFailClosed() throws {
        let work = try Self.loadWorkObject()

        XCTAssertEqual(
            work.hapticProgram.vocabulary,
            [.contact, .drag, .resistance, .transfer, .break, .seal]
        )
        XCTAssertEqual(work.hapticProgram.activeLonghouseSemantics, [.contact, .resistance, .seal])
        XCTAssertEqual(work.hapticProgram.reservedForOtherGrammars, [.drag, .transfer, .break])
        XCTAssertEqual(work.hapticProgram.loopedTimelineHaptics, "FORBIDDEN")
        XCTAssertEqual(
            work.hapticProgram.runtimeBindings.first(where: { $0.semantic == .seal }),
            LonghouseHapticRuntimeBinding(
                trigger: "durable-completion",
                semantic: .seal,
                durableCommitRequired: true
            )
        )

        XCTAssertEqual(work.narrationSlots.count, 2)
        XCTAssertTrue(work.narrationSlots.allSatisfy { slot in
            slot.status == "MISSING_EDITOR_SELECTED_NARRATION_MASTER"
                && slot.shippingBlock
                && !slot.segments.isEmpty
        })
        let audiblePaths = Set(work.timelines.flatMap { timeline in
            timeline.events.compactMap(\.assetPath)
        })
        XCTAssertTrue(work.narrationSlots.allSatisfy { slot in
            !audiblePaths.contains(slot.requiredAssetPath)
        })
    }

    private static func loadWorkObject() throws -> LonghouseWorkObject {
#if os(iOS)
        let bundle = Bundle(for: LonghouseResponsiveAudioWorkObjectTests.self)
        let file = try XCTUnwrap(
            bundle.url(forResource: "longhouse-responsive-work-object", withExtension: "json")
        )
#else
        let iosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = iosRoot
            .deletingLastPathComponent()
            .appendingPathComponent(
                "audio/score-soundscape/longhouse-responsive-v1/longhouse-responsive-work-object.json"
            )
#endif
        return try JSONDecoder().decode(
            LonghouseWorkObject.self,
            from: Data(contentsOf: file)
        )
    }
}

private struct LonghouseWorkObject: Decodable {
    let id: String
    let status: String
    let shippingState: String
    let trustDomain: String
    let responsiveProgram: ResponsiveAudioProgramSpec
    let timelines: [AudioTimeline]
    let audioAssetMetadata: [LonghouseAudioAssetMetadata]
    let narrationSlots: [LonghouseNarrationSlot]
    let hapticProgram: LonghouseHapticProgram
}

private struct LonghouseAudioAssetMetadata: Decodable {
    let path: String
    let sampleRate: Int
    let frameCount: Int64
    let channelCount: Int
}

private struct LonghouseNarrationSlot: Decodable {
    let timelineID: AudioTimelineID
    let status: String
    let requiredAssetPath: String
    let segments: [LonghouseNarrationSegment]
    let shippingBlock: Bool
}

private struct LonghouseNarrationSegment: Decodable {
    let manuscriptSegmentID: LocalizedStringID
    let manuscriptSegmentSHA256: String
}

private struct LonghouseHapticProgram: Decodable {
    let vocabulary: [HapticSemantic]
    let activeLonghouseSemantics: [HapticSemantic]
    let reservedForOtherGrammars: [HapticSemantic]
    let runtimeBindings: [LonghouseHapticRuntimeBinding]
    let loopedTimelineHaptics: String
}

private struct LonghouseHapticRuntimeBinding: Decodable, Equatable {
    let trigger: String
    let semantic: HapticSemantic
    let durableCommitRequired: Bool
}
