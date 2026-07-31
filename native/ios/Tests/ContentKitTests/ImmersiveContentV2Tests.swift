@testable import ContentKit
import Foundation
import XCTest

final class ImmersiveContentV2Tests: XCTestCase {
    func testApprovedChapter01FixtureValidatesAndRoundTripsThroughFailClosedDecoder() throws {
        let payload = makePayload()

        XCTAssertNoThrow(try payload.validate())
        XCTAssertEqual(payload.worldCells.count, 5)
        XCTAssertEqual(payload.sequences.count, 6)
        XCTAssertEqual(payload.sequences.flatMap(\.beats).count, 34)

        let encoded = try ImmersiveContentDocumentV2.encode(payload)
        let decoded = try ImmersiveContentDocumentV2.decode(encoded)
        XCTAssertEqual(decoded, payload)
    }

    func testChapterAuthorityRejectsChangedGrammarAndBeatCount() throws {
        let payload = makePayload()
        var sequences = payload.sequences
        let opening = sequences[0]
        sequences[0] = ExperienceSequenceSpec(
            id: opening.id,
            locationCue: opening.locationCue,
            worldCellIDs: opening.worldCellIDs,
            authoredDurationSeconds: opening.authoredDurationSeconds,
            principalInteraction: PrincipalInteraction3DBindingSpec(
                interactionID: opening.principalInteraction.interactionID,
                grammar: .pressure
            ),
            beats: opening.beats,
            narrationCueIDs: opening.narrationCueIDs
        )
        XCTAssertThrowsError(try replacing(payload, sequences: sequences).validate()) { error in
            XCTAssertTrue(String(describing: error).contains("stable interaction ID and grammar"))
        }

        sequences = payload.sequences
        let ending = sequences[5]
        sequences[5] = ExperienceSequenceSpec(
            id: ending.id,
            locationCue: ending.locationCue,
            worldCellIDs: ending.worldCellIDs,
            authoredDurationSeconds: ending.authoredDurationSeconds,
            principalInteraction: ending.principalInteraction,
            beats: Array(ending.beats.dropLast()),
            narrationCueIDs: ending.narrationCueIDs
        )
        XCTAssertThrowsError(try replacing(payload, sequences: sequences).validate()) { error in
            XCTAssertTrue(String(describing: error).contains("expected 34"))
        }
    }

    func testSemanticActionRequiresDirectTouchVoiceOverReduceMotionParityAndReach() throws {
        let payload = makePayload()
        var cells = payload.worldCells
        let cell = cells[0]
        let action = cell.semanticActions[0]
        let inaccessible = AccessibleSemanticAction3DSpec(
            id: action.id,
            interactionID: action.interactionID,
            targetEntityID: action.targetEntityID,
            domainActionKey: action.domainActionKey,
            accessibilityLabel: action.accessibilityLabel,
            visibleFallbackCue: action.visibleFallbackCue,
            directGesture: action.directGesture,
            inputModalities: [.directTouch],
            minimumTouchTargetPoints: 43,
            reduceMotionUsesSameDomainAction: false
        )
        cells[0] = replacing(cell, semanticActions: [inaccessible])

        XCTAssertThrowsError(try replacing(payload, worldCells: cells).validate()) { error in
            XCTAssertTrue(String(describing: error).contains("VoiceOver"))
        }
    }

    func testTransitionRequiresPhysicalIdentityAndCrossCellPrefetch() throws {
        let payload = makePayload()
        var transitions = payload.transitions
        let carrier = transitions[0]
        transitions[0] = TransitionCarrierSpec(
            id: carrier.id,
            sourceSequenceID: carrier.sourceSequenceID,
            destinationSequenceID: carrier.destinationSequenceID,
            sourceCellID: carrier.sourceCellID,
            destinationCellID: carrier.destinationCellID,
            kind: carrier.kind,
            sourceEntityID: carrier.sourceEntityID,
            destinationEntityID: carrier.destinationEntityID,
            identityRule: carrier.identityRule,
            cameraTrackID: carrier.cameraTrackID,
            audioBindingID: carrier.audioBindingID,
            prefetchesDestinationCell: false,
            visibleCue: carrier.visibleCue
        )

        XCTAssertThrowsError(try replacing(payload, transitions: transitions).validate()) { error in
            XCTAssertTrue(String(describing: error).contains("prefetch"))
        }
    }

    func testNarrationRequiresWordExactTimedTwoLineCaptions() throws {
        let payload = makePayload()
        var captions = payload.captions
        let caption = captions[0]
        captions[0] = CaptionBinding3DSpec(
            id: caption.id,
            narrationCueID: caption.narrationCueID,
            text: LocalizedStringSpec(
                id: caption.text.id,
                launchEnglish: "Different public words."
            ),
            startSampleFrame: caption.startSampleFrame,
            endSampleFrame: caption.endSampleFrame,
            maximumLineCount: caption.maximumLineCount
        )

        XCTAssertThrowsError(try replacing(payload, captions: captions).validate()) { error in
            XCTAssertTrue(String(describing: error).contains("word-exact"))
        }
    }

    func testDocumentDecoderRejectsUnknownAndBackstageFieldsAtAnyDepth() throws {
        let payload = makePayload()
        let encoded = try ImmersiveContentDocumentV2.encode(payload)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["reviewLabel"] = "must not be ignored"
        XCTAssertThrowsError(
            try ImmersiveContentDocumentV2.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("exact public immersive v2 wire fields"))
        }

        object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var cells = try XCTUnwrap(object["worldCells"] as? [[String: Any]])
        cells[0]["researchNotes"] = ["private source discussion"]
        object["worldCells"] = cells
        XCTAssertThrowsError(
            try ImmersiveContentDocumentV2.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("backstage research fields"))
        }
    }

    func testAssetsRequirePackageRelativePathsHashesAndLiveReferences() throws {
        let payload = makePayload()
        var assets = payload.assets
        let asset = assets[0]
        assets[0] = AssetReference3DSpec(
            id: asset.id,
            kind: asset.kind,
            path: "../private/scene.usdz",
            sha256: String(repeating: "G", count: 64),
            byteCount: asset.byteCount
        )
        XCTAssertThrowsError(try replacing(payload, assets: assets).validate())

        assets = payload.assets
        assets.append(
            AssetReference3DSpec(
                id: "asset-first-farmers-unused",
                kind: .mesh,
                path: "immersive/first-farmers/unused.usdz",
                sha256: String(repeating: "a", count: 64),
                byteCount: 1
            )
        )
        XCTAssertThrowsError(try replacing(payload, assets: assets).validate()) { error in
            XCTAssertTrue(String(describing: error).contains("every packaged asset"))
        }
    }
}

private extension ImmersiveContentV2Tests {
    func makePayload() -> ContentPackagePayloadV2 {
        let cellIDs = Chapter01ImmersiveV2Authority.worldCellIDs
        let sequenceIDs = Chapter01ImmersiveV2Authority.sequenceIDs
        let interactionIDs = Chapter01ImmersiveV2Authority.interactionIDs
        let entityIDs: [WorldEntity3DID] = [
            "entity-first-farmers-seed-vessel",
            "entity-first-farmers-seed-vessel",
            "entity-first-farmers-landing-load",
            "entity-first-farmers-house-load",
            "entity-first-farmers-settlement-load",
        ]
        let sequenceActions: [SemanticAction3DID] = (1 ... 6).map {
            SemanticAction3DID("semantic-action-first-farmers-\(String(format: "%02d", $0))")
        }
        let cameraTrackIDs: [CameraTrack3DID] = (1 ... 5).map {
            CameraTrack3DID("camera-track-first-farmers-cell-\(String(format: "%02d", $0))")
        }

        var assets: [AssetReference3DSpec] = []
        var cells: [WorldCell3DSpec] = []
        let actionIndicesByCell = [[0], [1], [2], [3], [4, 5]]
        let fallbackCues = [
            "Hold the line", "Divide the harvest", "Take the landing line",
            "Hold the load", "Lead them to water", "Close the gate",
        ]

        for cellIndex in cellIDs.indices {
            let suffix = String(format: "%02d", cellIndex + 1)
            let sceneAssetID = AssetReference3DID("asset-first-farmers-scene-\(suffix)")
            let materialAssetID = AssetReference3DID("asset-first-farmers-material-\(suffix)")
            let animationAssetID = AssetReference3DID("asset-first-farmers-animation-\(suffix)")
            assets.append(contentsOf: [
                asset(id: sceneAssetID, kind: .sceneGraph, suffix: "cells/cell-\(suffix).usdz"),
                asset(id: materialAssetID, kind: .material, suffix: "materials/material-\(suffix).reality"),
                asset(id: animationAssetID, kind: .animation, suffix: "animations/action-\(suffix).usdz"),
            ])

            let materialBindingID = MaterialBinding3DID("material-binding-first-farmers-\(suffix)")
            let animationBindingID = AnimationBinding3DID("animation-binding-first-farmers-\(suffix)")
            let actionIndices = actionIndicesByCell[cellIndex]
            let actions = actionIndices.map { actionIndex in
                AccessibleSemanticAction3DSpec(
                    id: sequenceActions[actionIndex],
                    interactionID: interactionIDs[actionIndex],
                    targetEntityID: entityIDs[cellIndex],
                    domainActionKey: "commit-first-farmers-action-\(String(format: "%02d", actionIndex + 1))",
                    accessibilityLabel: LocalizedStringSpec(
                        id: LocalizedStringID("copy-first-farmers-action-label-\(String(format: "%02d", actionIndex + 1))"),
                        launchEnglish: fallbackCues[actionIndex]
                    ),
                    visibleFallbackCue: LocalizedStringSpec(
                        id: LocalizedStringID("copy-first-farmers-action-cue-\(String(format: "%02d", actionIndex + 1))"),
                        launchEnglish: fallbackCues[actionIndex]
                    ),
                    directGesture: .drag,
                    inputModalities: [.directTouch, .voiceOver],
                    minimumTouchTargetPoints: 52,
                    reduceMotionUsesSameDomainAction: true
                )
            }
            let entity = WorldEntity3DBindingSpec(
                id: entityIDs[cellIndex],
                scenePath: "Root/ActionObject",
                role: .actionObject,
                reducerStateKey: "first-farmers-cell-\(suffix)-state",
                persistsAfterSequence: true,
                materialBindingIDs: [materialBindingID],
                animationBindingIDs: [animationBindingID],
                semanticActionIDs: actions.map(\.id)
            )
            let material = MaterialBinding3DSpec(
                id: materialBindingID,
                entityID: entity.id,
                reducerStateKey: "first-farmers-cell-\(suffix)-material",
                initialStateID: MaterialState3DID("material-state-first-farmers-\(suffix)-ready"),
                states: [
                    MaterialState3DSpec(
                        id: MaterialState3DID("material-state-first-farmers-\(suffix)-ready"),
                        assetID: materialAssetID
                    ),
                ]
            )
            let animation = AnimationBinding3DSpec(
                id: animationBindingID,
                entityID: entity.id,
                reducerStateKey: "first-farmers-cell-\(suffix)-animation",
                initialStateID: AnimationState3DID("animation-state-first-farmers-\(suffix)-ready"),
                states: [
                    AnimationState3DSpec(
                        id: AnimationState3DID("animation-state-first-farmers-\(suffix)-ready"),
                        assetID: animationAssetID,
                        loops: false
                    ),
                ]
            )
            let anchor = cameraAnchor(
                id: CameraAnchor3DID("camera-anchor-first-farmers-\(suffix)-default"),
                entityID: entity.id
            )
            let reducedAnchor = cameraAnchor(
                id: CameraAnchor3DID("camera-anchor-first-farmers-\(suffix)-reduced"),
                entityID: entity.id
            )
            let camera = CameraTrackSpec(
                id: cameraTrackIDs[cellIndex],
                anchors: [anchor],
                authoredDurationSeconds: 5,
                maximumUnbrokenTravelSeconds: 5,
                reduceMotion: ReduceMotionCameraTrackSpec(
                    anchors: [reducedAnchor],
                    transition: .shortEase,
                    maximumTransitionSeconds: 0.25
                )
            )
            cells.append(
                WorldCell3DSpec(
                    id: cellIDs[cellIndex],
                    sceneGraphAssetID: sceneAssetID,
                    entities: [entity],
                    materialBindings: [material],
                    animationBindings: [animation],
                    cameraTracks: [camera],
                    semanticActions: actions,
                    lodGroups: [
                        LODGroup3DSpec(
                            id: LODGroup3DID("lod-group-first-farmers-\(suffix)"),
                            entityID: entity.id,
                            levels: [
                                LODLevel3DSpec(maximumDistanceMeters: 100, assetID: sceneAssetID),
                            ]
                        ),
                    ]
                )
            )
        }

        var audioBindings: [ImmersiveAudioBindingSpec] = []
        for index in cellIDs.indices {
            let suffix = String(format: "%02d", index + 1)
            audioBindings.append(
                makeAudio(
                    idSuffix: "environment-\(suffix)",
                    role: .environment,
                    cellID: cellIDs[index],
                    durationSeconds: 8,
                    loops: true,
                    assets: &assets
                )
            )
        }
        for index in sequenceIDs.indices {
            let suffix = String(format: "%02d", index + 1)
            audioBindings.append(
                makeAudio(
                    idSuffix: "mechanism-\(suffix)",
                    role: .mechanism,
                    sequenceID: sequenceIDs[index],
                    interactionID: interactionIDs[index],
                    durationSeconds: 4,
                    loops: false,
                    assets: &assets
                )
            )
            audioBindings.append(
                makeAudio(
                    idSuffix: "transition-\(suffix)",
                    role: .transition,
                    sequenceID: sequenceIDs[index],
                    durationSeconds: 3,
                    loops: false,
                    assets: &assets
                )
            )
        }

        let narrationSequenceIndices = [0, 0, 1, 1, 1, 2, 3, 4, 5, 5]
        let narrationWords = [
            "Households carried seed west.",
            "The vessel reached dry ground.",
            "One harvest faced three claims.",
            "Autumn governed the winter margin.",
            "Protected seed returned to soil.",
            "River knowledge made landing possible.",
            "Inherited ground outlived the timber.",
            "Growing households required more land.",
            "Settled systems remade European ground.",
            "The eastern horizon remained exposed.",
        ]
        var narrations: [NarrationBinding3DSpec] = []
        var captions: [CaptionBinding3DSpec] = []
        for cueIndex in narrationSequenceIndices.indices {
            let suffix = String(format: "%02d", cueIndex + 1)
            let sequenceIndex = narrationSequenceIndices[cueIndex]
            let audio = makeAudio(
                idSuffix: "narration-\(suffix)",
                role: .narration,
                sequenceID: sequenceIDs[sequenceIndex],
                durationSeconds: 2,
                loops: false,
                assets: &assets
            )
            audioBindings.append(audio)
            let cueID = AudioCueID("narration-first-farmers-\(suffix)")
            let captionID = CaptionBinding3DID("caption-first-farmers-\(suffix)")
            let text = LocalizedStringSpec(
                id: LocalizedStringID("copy-first-farmers-narration-\(suffix)"),
                launchEnglish: narrationWords[cueIndex]
            )
            narrations.append(
                NarrationBinding3DSpec(
                    id: cueID,
                    sequenceID: sequenceIDs[sequenceIndex],
                    audioBindingID: audio.id,
                    text: text,
                    captionIDs: [captionID],
                    beginsAfterPreciseInputRelease: true
                )
            )
            captions.append(
                CaptionBinding3DSpec(
                    id: captionID,
                    narrationCueID: cueID,
                    text: text,
                    startSampleFrame: 0,
                    endSampleFrame: 96_000,
                    maximumLineCount: 2
                )
            )
        }

        let sequenceDurations: [Double] = [150, 190, 100, 150, 130, 95]
        let beatCounts = [6, 7, 4, 5, 6, 6]
        let sequenceCells: [[WorldCell3DID]] = [
            [cellIDs[0], cellIDs[1]], [cellIDs[1]], [cellIDs[2]],
            [cellIDs[3]], [cellIDs[4]], [cellIDs[4]],
        ]
        let grammars: [ImmersiveInteractionGrammar] = [
            .trace, .allocate, .transform, .assemble, .transform, .transform,
        ]
        var sequences: [ExperienceSequenceSpec] = []
        for sequenceIndex in sequenceIDs.indices {
            let cueIDs = narrations
                .filter { $0.sequenceID == sequenceIDs[sequenceIndex] }
                .map(\.id)
            let duration = sequenceDurations[sequenceIndex] / Double(beatCounts[sequenceIndex])
            var beats: [ExperienceBeat3DSpec] = []
            for beatIndex in 0 ..< beatCounts[sequenceIndex] {
                let cellID: WorldCell3DID
                if sequenceIndex == 0 {
                    cellID = beatIndex < 3 ? cellIDs[0] : cellIDs[1]
                } else {
                    cellID = sequenceCells[sequenceIndex][0]
                }
                let cellIndex = cellIDs.firstIndex(of: cellID)!
                beats.append(
                    ExperienceBeat3DSpec(
                        id: ExperienceBeatID(
                            "beat-first-farmers-\(String(format: "%02d", sequenceIndex + 1))-\(String(format: "%02d", beatIndex + 1))"
                        ),
                        cellID: cellID,
                        authoredDurationSeconds: duration,
                        maximumPassiveSeconds: beatIndex == 0 ? 2 : 6,
                        cameraTrackID: cameraTrackIDs[cellIndex],
                        semanticActionIDs: beatIndex == 0 ? [sequenceActions[sequenceIndex]] : [],
                        narrationCueIDs: beatIndex < cueIDs.count ? [cueIDs[beatIndex]] : [],
                        endsAtStableRestorationState: beatIndex == beatCounts[sequenceIndex] - 1
                    )
                )
            }
            sequences.append(
                ExperienceSequenceSpec(
                    id: sequenceIDs[sequenceIndex],
                    locationCue: nil,
                    worldCellIDs: sequenceCells[sequenceIndex],
                    authoredDurationSeconds: sequenceDurations[sequenceIndex],
                    principalInteraction: PrincipalInteraction3DBindingSpec(
                        interactionID: interactionIDs[sequenceIndex],
                        grammar: grammars[sequenceIndex]
                    ),
                    beats: beats,
                    narrationCueIDs: cueIDs
                )
            )
        }

        let transitionMap = [
            (0, 0, 0, 1), (0, 1, 1, 1), (1, 2, 1, 2),
            (2, 3, 2, 3), (3, 4, 3, 4), (4, 5, 4, 4),
        ]
        let transitionKinds: [TransitionCarrierKind3D] = [
            .load, .surface, .load, .route, .route, .load,
        ]
        let transitions = Chapter01ImmersiveV2Authority.transitionIDs.indices.map { index in
            let map = transitionMap[index]
            let sameEntity = entityIDs[map.2] == entityIDs[map.3]
            return TransitionCarrierSpec(
                id: Chapter01ImmersiveV2Authority.transitionIDs[index],
                sourceSequenceID: sequenceIDs[map.0],
                destinationSequenceID: sequenceIDs[map.1],
                sourceCellID: cellIDs[map.2],
                destinationCellID: cellIDs[map.3],
                kind: transitionKinds[index],
                sourceEntityID: entityIDs[map.2],
                destinationEntityID: entityIDs[map.3],
                identityRule: sameEntity ? .preserveIdentity : .visibleHandoff,
                cameraTrackID: cameraTrackIDs[map.2],
                audioBindingID: AudioBinding3DID(
                    "audio-binding-first-farmers-transition-\(String(format: "%02d", map.1 + 1))"
                ),
                prefetchesDestinationCell: map.2 != map.3,
                visibleCue: nil
            )
        }

        return ContentPackagePayloadV2(
            schemaVersion: SchemaVersion(major: 2),
            packageID: "first-farmers-3d-review-v1",
            chapterID: "first-farmers",
            pacing: Chapter01PacingSpec(
                authoredCoreSeconds: 815,
                expectedFirstPlayMinimumSeconds: 960,
                expectedFirstPlayMaximumSeconds: 1_050,
                firstMeaningfulContactSeconds: 2,
                maximumPassiveCameraSeconds: 8,
                maximumNarrationWords: 280,
                maximumVisibleInterfaceWords: 70
            ),
            streamingPolicy: ImmersiveStreamingPolicySpec(
                maximumResidentCellCount: 2,
                prefetchLeadSeconds: 5,
                unloadRule: .afterTransitionCommit,
                permitsPlaceholderUI: false
            ),
            assets: assets,
            worldCells: cells,
            sequences: sequences,
            transitions: transitions,
            audioBindings: audioBindings,
            narrationBindings: narrations,
            captions: captions
        )
    }

    func asset(
        id: AssetReference3DID,
        kind: ImmersiveAssetKind,
        suffix: String
    ) -> AssetReference3DSpec {
        AssetReference3DSpec(
            id: id,
            kind: kind,
            path: "immersive/first-farmers/\(suffix)",
            sha256: String(repeating: "a", count: 64),
            byteCount: 128
        )
    }

    func makeAudio(
        idSuffix: String,
        role: ImmersiveAudioRole,
        cellID: WorldCell3DID? = nil,
        sequenceID: ExperienceSequenceID? = nil,
        interactionID: InteractionID? = nil,
        durationSeconds: UInt64,
        loops: Bool,
        assets: inout [AssetReference3DSpec]
    ) -> ImmersiveAudioBindingSpec {
        let assetID = AssetReference3DID("asset-first-farmers-audio-\(idSuffix)")
        assets.append(
            asset(id: assetID, kind: .audio, suffix: "audio/\(idSuffix).m4a")
        )
        return ImmersiveAudioBindingSpec(
            id: AudioBinding3DID("audio-binding-first-farmers-\(idSuffix)"),
            assetID: assetID,
            role: role,
            cellID: cellID,
            sequenceID: sequenceID,
            interactionID: interactionID,
            startSampleFrame: 0,
            durationSampleFrames: durationSeconds * 48_000,
            sampleRate: 48_000,
            loops: loops
        )
    }

    func cameraAnchor(
        id: CameraAnchor3DID,
        entityID: WorldEntity3DID
    ) -> CameraAnchor3DSpec {
        CameraAnchor3DSpec(
            id: id,
            pose: CameraPose3DSpec(
                position: Vector3DSpec(x: 0, y: 1.4, z: 2.8),
                pitchDegrees: -8,
                yawDegrees: 0,
                rollDegrees: 0,
                verticalFieldOfViewDegrees: 48
            ),
            portraitSafeRegion: PortraitSafeRegion3DSpec(
                minimumX: 0.08,
                minimumY: 0.1,
                maximumX: 0.92,
                maximumY: 0.9
            ),
            focusEntityID: entityID
        )
    }

    func replacing(
        _ payload: ContentPackagePayloadV2,
        assets: [AssetReference3DSpec]? = nil,
        worldCells: [WorldCell3DSpec]? = nil,
        sequences: [ExperienceSequenceSpec]? = nil,
        transitions: [TransitionCarrierSpec]? = nil,
        captions: [CaptionBinding3DSpec]? = nil
    ) -> ContentPackagePayloadV2 {
        ContentPackagePayloadV2(
            schemaVersion: payload.schemaVersion,
            packageID: payload.packageID,
            chapterID: payload.chapterID,
            pacing: payload.pacing,
            streamingPolicy: payload.streamingPolicy,
            assets: assets ?? payload.assets,
            worldCells: worldCells ?? payload.worldCells,
            sequences: sequences ?? payload.sequences,
            transitions: transitions ?? payload.transitions,
            audioBindings: payload.audioBindings,
            narrationBindings: payload.narrationBindings,
            captions: captions ?? payload.captions
        )
    }

    func replacing(
        _ cell: WorldCell3DSpec,
        semanticActions: [AccessibleSemanticAction3DSpec]
    ) -> WorldCell3DSpec {
        WorldCell3DSpec(
            id: cell.id,
            sceneGraphAssetID: cell.sceneGraphAssetID,
            entities: cell.entities,
            materialBindings: cell.materialBindings,
            animationBindings: cell.animationBindings,
            cameraTracks: cell.cameraTracks,
            semanticActions: semanticActions,
            lodGroups: cell.lodGroups
        )
    }
}
