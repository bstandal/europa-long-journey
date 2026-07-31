import ContentKit
import Foundation
@testable import JourneyDomain
import XCTest

final class ExperienceRuntimeStateTests: XCTestCase {
    func testCompleteExperienceStateRoundTripsWithoutRendererObjects() throws {
        var assistance = AdaptiveAssistanceState()
        _ = try AdaptiveAssistancePolicy.reduce(
            state: &assistance,
            event: .hesitationElapsed(10_000)
        )
        for _ in 0 ..< 3 {
            _ = try AdaptiveAssistancePolicy.reduce(
                state: &assistance,
                event: .missedAttempt
            )
        }

        let state = try ExperienceRuntimeState(
            worldCellID: "cell-thessaly",
            sequenceID: "sequence-harvest",
            beatID: "beat-winter-repair",
            materialChannels: [
                StableMaterialChannelState(channelID: "timber-wetness", value: 0.78),
                StableMaterialChannelState(channelID: "grain-loss", value: 0.24),
            ],
            deterministicTick: UInt64.max,
            deterministicSeed: UInt64.max - 1,
            camera: ExperienceCameraState(
                trackID: "camera-winter-breach",
                progress: 0.625
            ),
            transition: ExperienceTransitionState(
                transitionID: "transition-winter-spring",
                carrierID: "carrier-seed-vessel",
                progress: 0.375
            ),
            assistance: assistance,
            interactionStateReference: ExperienceInteractionStateReference(
                interactionID: "interaction-first-farmers-the-harvest-had-to-last"
            ),
            sampleCursor: 2_646_000
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(state)
        let restored = try JSONDecoder().decode(
            ExperienceRuntimeState.self,
            from: encoded
        )

        XCTAssertEqual(restored, state)
        XCTAssertEqual(Set([restored]).count, 1, "State must remain Hashable")
        XCTAssertEqual(restored.deterministicTick, UInt64.max)
        XCTAssertEqual(restored.deterministicSeed, UInt64.max - 1)
        XCTAssertEqual(restored.sampleCursor, 2_646_000)
        XCTAssertEqual(restored.assistance, assistance)
        XCTAssertTrue(restored.isStructurallyValid)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNil(object["entityTransforms"])
        XCTAssertNil(object["physicsState"])
        XCTAssertNil(object["realityKitEntities"])
        let reference = try XCTUnwrap(
            object["interactionStateReference"] as? [String: Any]
        )
        XCTAssertEqual(
            reference["interactionID"] as? String,
            "interaction-first-farmers-the-harvest-had-to-last"
        )
        XCTAssertNil(reference["phase"])
        XCTAssertNil(reference["progress"])
    }

    func testMaterialChannelsHaveCanonicalOrderAndStableLookup() throws {
        let state = try makeState(materialChannels: [
            StableMaterialChannelState(channelID: "water", value: 0.4),
            StableMaterialChannelState(channelID: "grain", value: 0.8),
            StableMaterialChannelState(channelID: "soil", value: 0.6),
        ])

        XCTAssertEqual(
            state.materialChannels.map(\.channelID),
            ["grain", "soil", "water"]
        )
        XCTAssertEqual(state.materialValue(for: "soil"), 0.6)
        XCTAssertNil(state.materialValue(for: "missing"))
    }

    func testDuplicateOrInvalidMaterialChannelsFailClosed() {
        XCTAssertThrowsError(
            try makeState(materialChannels: [
                StableMaterialChannelState(channelID: "grain", value: 0.2),
                StableMaterialChannelState(channelID: "grain", value: 0.8),
            ])
        ) { error in
            XCTAssertEqual(
                error as? ExperienceRuntimeStateError,
                .duplicateMaterialChannel("grain")
            )
        }

        for value in [-0.01, 1.01, .infinity, .nan] {
            XCTAssertThrowsError(
                try makeState(materialChannels: [
                    StableMaterialChannelState(channelID: "grain", value: value),
                ])
            )
        }
    }

    func testInvalidIdentifiersAndNormalizedProgressFailClosed() {
        XCTAssertThrowsError(try makeState(worldCellID: "  "))
        XCTAssertThrowsError(try makeState(sequenceID: ""))
        XCTAssertThrowsError(try makeState(beatID: "\n"))
        XCTAssertThrowsError(
            try makeState(camera: ExperienceCameraState(trackID: "camera", progress: 1.01))
        )
        XCTAssertThrowsError(
            try makeState(camera: ExperienceCameraState(trackID: " ", progress: 0.5))
        )
        XCTAssertThrowsError(
            try makeState(
                transition: ExperienceTransitionState(
                    transitionID: "transition",
                    carrierID: "carrier",
                    progress: -0.01
                )
            )
        )
        XCTAssertThrowsError(
            try makeState(
                interactionStateReference: ExperienceInteractionStateReference(
                    interactionID: " "
                )
            )
        )
        XCTAssertThrowsError(try makeState(sampleCursor: -1))
    }

    func testMutationCanBeValidatedBeforeAStateIsJournaled() throws {
        var state = try makeState()
        state.camera.progress = .infinity

        XCTAssertFalse(state.isStructurallyValid)
        XCTAssertThrowsError(try state.validate()) { error in
            XCTAssertEqual(
                error as? ExperienceRuntimeStateError,
                .invalidCameraProgress
            )
        }
    }

    func testDecodeRejectsUnsupportedVersionNegativeCursorAndDuplicateChannels()
        throws {
        let valid = try makeState(materialChannels: [
            StableMaterialChannelState(channelID: "grain", value: 0.5),
        ])
        let encoded = try JSONEncoder().encode(valid)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        object["formatVersion"] = 2
        XCTAssertThrowsError(try decode(object))

        object["formatVersion"] = 1
        object["sampleCursor"] = -1
        XCTAssertThrowsError(try decode(object))

        object["sampleCursor"] = 0
        object["materialChannels"] = [
            ["channelID": "grain", "value": 0.3],
            ["channelID": "grain", "value": 0.7],
        ]
        XCTAssertThrowsError(try decode(object))
    }

    func testAssistanceAndInteractionReferenceRemainUnchangedByRestore() throws {
        var assistance = AdaptiveAssistanceState()
        _ = try AdaptiveAssistancePolicy.reduce(
            state: &assistance,
            event: .hesitationElapsed(6_000)
        )
        _ = try AdaptiveAssistancePolicy.reduce(
            state: &assistance,
            event: .missedAttempt
        )
        _ = try AdaptiveAssistancePolicy.reduce(
            state: &assistance,
            event: .missedAttempt
        )
        let reference = ExperienceInteractionStateReference(
            interactionID: "interaction-first-farmers-a-household-crosses"
        )
        let state = try makeState(
            assistance: assistance,
            interactionStateReference: reference
        )

        let restored = try JSONDecoder().decode(
            ExperienceRuntimeState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(restored.assistance, assistance)
        XCTAssertEqual(restored.interactionStateReference, reference)
        XCTAssertEqual(
            AdaptiveAssistancePolicy.directive(for: restored.assistance).tier,
            .actionCue
        )
    }

    private func makeState(
        worldCellID: String = "cell-aegean",
        sequenceID: String = "sequence-crossing",
        beatID: BeatID = "beat-hold-line",
        materialChannels: [StableMaterialChannelState] = [],
        camera: ExperienceCameraState = ExperienceCameraState(
            trackID: "camera-crossing",
            progress: 0
        ),
        transition: ExperienceTransitionState? = nil,
        assistance: AdaptiveAssistanceState = AdaptiveAssistanceState(),
        interactionStateReference: ExperienceInteractionStateReference? = nil,
        sampleCursor: Int64 = 0
    ) throws -> ExperienceRuntimeState {
        try ExperienceRuntimeState(
            worldCellID: worldCellID,
            sequenceID: sequenceID,
            beatID: beatID,
            materialChannels: materialChannels,
            deterministicTick: 42,
            deterministicSeed: 7,
            camera: camera,
            transition: transition,
            assistance: assistance,
            interactionStateReference: interactionStateReference,
            sampleCursor: sampleCursor
        )
    }

    private func decode(_ object: [String: Any]) throws -> ExperienceRuntimeState {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(ExperienceRuntimeState.self, from: data)
    }
}
