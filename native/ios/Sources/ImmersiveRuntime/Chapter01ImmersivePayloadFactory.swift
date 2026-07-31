import ContentKit
import Foundation

/// Integrity metadata supplied by the package compiler after it has produced
/// the referenced asset. The factory never invents a digest for an absent
/// file, so its output can pass directly into the signed-package boundary.
public struct Chapter01ImmersiveAssetIntegrity: Hashable, Sendable {
    public let sha256: String
    public let byteCount: Int64

    public init(sha256: String, byteCount: Int64) {
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public enum Chapter01ImmersivePayloadFactoryError: Error, Equatable, Sendable {
    case missingAssetIntegrity(path: String)
    case invalidApprovedProjection(reason: String)
}

/// Builds the one public V2 payload authorised for the Chapter 01 3D review.
///
/// Interaction IDs and causal beat order come from the approved Chapter 01
/// projection already compiled into this module. The ten narration texts stay
/// byte-faithful to the manuscript's explicitly provisional review copy; this
/// factory does not promote them to approved launch wording. Filesystem
/// integrity remains an input because only the package compiler can truthfully
/// bind generated assets to their hashes and byte counts.
public enum Chapter01ImmersivePayloadFactory {
    private static let assetRoot = "immersive/first-farmers"
    private static let materialLibraryPath =
        "\(assetRoot)/materials/chapter01-material-carrier-v1.usdz"
    private static let directedAnimationLibraryPath =
        "\(assetRoot)/animations/chapter01-directed-animation-library-v1.usdz"

    /// Runtime-only index for the ten provisional review recordings. Public
    /// wording remains private to the payload compiler; playback needs only
    /// the locked beat, cue, verified package path and authored 48 kHz span.
    struct RuntimeNarrationBinding: Equatable, Sendable {
        let cueID: String
        let beatID: String
        let packageRelativePath: String
        let durationSampleFrames: Int64
    }

    static let runtimeNarrationBindings: [RuntimeNarrationBinding] =
        NarrationDraft.all.enumerated().map { index, draft in
            let wordCount = draft.text.split(whereSeparator: \.isWhitespace).count
            let durationSeconds = max(
                3,
                min(14, Int(ceil(Double(wordCount) / 2.35)) + 1)
            )
            return RuntimeNarrationBinding(
                cueID: draft.cueID.rawValue,
                beatID: draft.beatID,
                packageRelativePath:
                    "\(assetRoot)/audio/narration-\(twoDigits(index + 1)).m4a",
                durationSampleFrames: Int64(durationSeconds * 48_000)
            )
        }

    public static let requiredAssetPaths: [String] = {
        let cellAssets = (1 ... 5).map { index in
            "\(assetRoot)/cells/cell-\(twoDigits(index)).usdz"
        }
        let environments = (1 ... 5).map {
            "\(assetRoot)/audio/environment-\(twoDigits($0)).m4a"
        }
        let mechanisms = (1 ... 6).map {
            "\(assetRoot)/audio/mechanism-\(twoDigits($0)).m4a"
        }
        let transitions = (1 ... 6).map {
            "\(assetRoot)/audio/transition-\(twoDigits($0)).m4a"
        }
        let narrations = (1 ... 10).map {
            "\(assetRoot)/audio/narration-\(twoDigits($0)).m4a"
        }
        return cellAssets
            + [materialLibraryPath, directedAnimationLibraryPath]
            + environments + mechanisms + transitions + narrations
    }()

    public static func make(
        assetIntegrityByPath: [String: Chapter01ImmersiveAssetIntegrity]
    ) throws -> ContentPackagePayloadV2 {
        let cellIDs = Chapter01ImmersiveV2Authority.worldCellIDs
        let sequenceIDs = Chapter01ImmersiveV2Authority.sequenceIDs
        let interactionIDs = Chapter01ImmersiveV2Authority.interactionIDs

        guard Chapter01ExperienceScript.packageID
                == Chapter01ImmersiveV2Authority.packageID.rawValue,
              Chapter01ExperienceScript.beats.count == 34,
              Chapter01Sequence.allCases.map(\.interactionID)
                == interactionIDs.map(\.rawValue) else {
            throw Chapter01ImmersivePayloadFactoryError.invalidApprovedProjection(
                reason: "runtime script and V2 Chapter 01 authority diverged"
            )
        }

        let entityIDs: [WorldEntity3DID] = [
            "entity-first-farmers-seed-vessel",
            "entity-first-farmers-seed-vessel",
            "entity-first-farmers-landing-load",
            "entity-first-farmers-house-load",
            "entity-first-farmers-settlement-load",
        ]
        let semanticActionIDs: [SemanticAction3DID] = (1 ... 6).map {
            SemanticAction3DID("semantic-action-first-farmers-\(twoDigits($0))")
        }
        let cameraTrackIDs: [CameraTrack3DID] = (1 ... 5).map {
            CameraTrack3DID("camera-track-first-farmers-cell-\(twoDigits($0))")
        }

        var assets: [AssetReference3DSpec] = []
        let worldCells = try makeWorldCells(
            entityIDs: entityIDs,
            semanticActionIDs: semanticActionIDs,
            cameraTrackIDs: cameraTrackIDs,
            interactionIDs: interactionIDs,
            integrity: assetIntegrityByPath,
            assets: &assets
        )

        var audioBindings = try makeBaseAudioBindings(
            cellIDs: cellIDs,
            sequenceIDs: sequenceIDs,
            interactionIDs: interactionIDs,
            integrity: assetIntegrityByPath,
            assets: &assets
        )
        let narration = try makeNarration(
            sequenceIDs: sequenceIDs,
            integrity: assetIntegrityByPath,
            assets: &assets
        )
        audioBindings.append(contentsOf: narration.audioBindings)

        let sequences = try makeSequences(
            cellIDs: cellIDs,
            sequenceIDs: sequenceIDs,
            interactionIDs: interactionIDs,
            semanticActionIDs: semanticActionIDs,
            cameraTrackIDs: cameraTrackIDs,
            narrationDrafts: narration.drafts
        )
        let transitions = makeTransitions(
            cellIDs: cellIDs,
            sequenceIDs: sequenceIDs,
            entityIDs: entityIDs,
            cameraTrackIDs: cameraTrackIDs
        )

        let payload = ContentPackagePayloadV2(
            schemaVersion: Chapter01ImmersiveV2Authority.schemaVersion,
            packageID: Chapter01ImmersiveV2Authority.packageID,
            chapterID: Chapter01ImmersiveV2Authority.chapterID,
            pacing: Chapter01PacingSpec(
                authoredCoreSeconds: Chapter01ExperienceScript.authoredDurationSeconds,
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
            worldCells: worldCells,
            sequences: sequences,
            transitions: transitions,
            audioBindings: audioBindings,
            narrationBindings: narration.bindings,
            captions: narration.captions
        )
        try payload.validate()
        return payload
    }
}

private extension Chapter01ImmersivePayloadFactory {
    struct NarrationDraft {
        let sequenceIndex: Int
        let beatID: String
        let phrases: [String]

        var text: String { phrases.joined(separator: " ") }
        var cueID: AudioCueID {
            AudioCueID("narration-first-farmers-\(twoDigits(number))")
        }
        var number: Int { Self.all.firstIndex(where: { $0.beatID == beatID })! + 1 }

        static let all: [NarrationDraft] = [
            .init(
                sequenceIndex: 0,
                beatID: "load-under-tension",
                phrases: [
                    "Farming moved west with Anatolian households.",
                    "They carried seed, livestock, tools, containers and the learned routines that made the parts work together.",
                ]
            ),
            .init(
                sequenceIndex: 0,
                beatID: "dry-bank-transfer",
                phrases: [
                    "Repeated crossings carried the complete system onto Aegean shores and into Thessaly.",
                ]
            ),
            .init(
                sequenceIndex: 1,
                beatID: "three-claims",
                phrases: [
                    "Nothing more will ripen before winter.",
                    "This harvest must feed the household, cover loss and preserve seed for spring.",
                ]
            ),
            .init(
                sequenceIndex: 1,
                beatID: "winter-breach",
                phrases: [
                    "Grain eaten in winter cannot cover later loss or return to the soil.",
                    "The household's autumn decision now governs spring.",
                ]
            ),
            .init(
                sequenceIndex: 1,
                beatID: "spring-return",
                phrases: [
                    "The protected seed returns to worked soil instead of the hearth.",
                ]
            ),
            .init(
                sequenceIndex: 2,
                beatID: "route-inland",
                phrases: [
                    "At the Iron Gates, incoming farmers met established river communities.",
                    "People and practices crossed through older routes,",
                    "while river foods and local ancestry persisted unevenly.",
                ]
            ),
            .init(
                sequenceIndex: 3,
                beatID: "plot-crowds",
                phrases: [
                    "Timber failed; the threshold, worked ground, graves and postholes remained.",
                    "In some communities, fathers and sons held strongly to these inherited places,",
                    "while women often arrived from neighbouring groups.",
                ]
            ),
            .init(
                sequenceIndex: 4,
                beatID: "clearing-regrows",
                phrases: [
                    "More households required more fields and herd lanes.",
                    "Some clearings emptied and returned to grass and young trees; the carried system continued.",
                ]
            ),
            .init(
                sequenceIndex: 5,
                beatID: "continent-condition",
                phrases: [
                    "By 3300 BC, Europe had become a continent of fields, herds and long-lived settlements.",
                ]
            ),
            .init(
                sequenceIndex: 5,
                beatID: "eastern-grass",
                phrases: [
                    "The steppe would meet fields to seize, stores to command, houses to inherit and paternal lines to reorder.",
                ]
            ),
        ]
    }

    struct NarrationBuild {
        let drafts: [NarrationDraft]
        let audioBindings: [ImmersiveAudioBindingSpec]
        let bindings: [NarrationBinding3DSpec]
        let captions: [CaptionBinding3DSpec]
    }

    static let actionBeatIDs = [
        "cross-current",
        "three-claims",
        "forces-align",
        "frame-rises",
        "herd-finds-water",
        "coupled-load",
    ]

    static let sequenceDurations: [Double] = [150, 190, 100, 150, 130, 95]

    /// Timings retain the approved pressure-map boundaries while keeping each
    /// of the 34 durable states positive in the V2 wire model.
    static let beatDurations: [String: Double] = [
        "cross-current": 5,
        "load-under-tension": 50,
        "dry-bank-transfer": 25,
        "seed-leaves-water": 12,
        "first-furrow": 28,
        "worked-season": 18,
        "finite-harvest": 12,

        "three-claims": 12,
        "food-committed": 16,
        "reserve-raised": 16,
        "seed-sealed": 16,
        "winter-breach": 95,
        "spring-return": 35,

        "later-hands": 15,
        "inhabited-bank": 13,
        "forces-align": 17,
        "two-way-load": 30,
        "route-inland": 25,

        "prepared-ground": 18,
        "frame-rises": 42,
        "shelter-holds": 35,
        "timber-replaced": 40,
        "plot-crowds": 15,

        "enclosure-opens": 20,
        "herd-finds-water": 35,
        "field-edge": 25,
        "daughter-clearing": 12,
        "settlement-grows": 8,
        "hearth-cools": 10,
        "clearing-regrows": 20,

        "basket-relay": 12,
        "coupled-load": 30,
        "continent-condition": 36,
        "eastern-grass": 17,
    ]

    static func makeWorldCells(
        entityIDs: [WorldEntity3DID],
        semanticActionIDs: [SemanticAction3DID],
        cameraTrackIDs: [CameraTrack3DID],
        interactionIDs: [InteractionID],
        integrity: [String: Chapter01ImmersiveAssetIntegrity],
        assets: inout [AssetReference3DSpec]
    ) throws -> [WorldCell3DSpec] {
        let actionIndicesByCell = [[0], [1], [2], [3], [4, 5]]
        let gestures: [DirectManipulationGesture3D] = [
            .hold, .transfer, .drag, .hold, .drag, .seal,
        ]
        let materialAssetID = AssetReference3DID(
            "asset-first-farmers-material-library"
        )
        let animationAssetID = AssetReference3DID(
            "asset-first-farmers-directed-animation-library"
        )
        assets.append(contentsOf: try [
            asset(materialAssetID, .material, materialLibraryPath, integrity),
            asset(
                animationAssetID,
                .animation,
                directedAnimationLibraryPath,
                integrity
            ),
        ])

        return try Chapter01ImmersiveV2Authority.worldCellIDs.indices.map { cellIndex in
            let number = cellIndex + 1
            let suffix = twoDigits(number)
            let scenePath = "\(assetRoot)/cells/cell-\(suffix).usdz"
            let sceneAssetID = AssetReference3DID("asset-first-farmers-scene-\(suffix)")
            assets.append(try asset(sceneAssetID, .sceneGraph, scenePath, integrity))

            let actionIndices = actionIndicesByCell[cellIndex]
            let actions = actionIndices.map { actionIndex in
                let sequence = Chapter01Sequence(rawValue: actionIndex)!
                return AccessibleSemanticAction3DSpec(
                    id: semanticActionIDs[actionIndex],
                    interactionID: interactionIDs[actionIndex],
                    targetEntityID: entityIDs[cellIndex],
                    domainActionKey: "commit-first-farmers-action-\(twoDigits(actionIndex + 1))",
                    accessibilityLabel: LocalizedStringSpec(
                        id: LocalizedStringID("copy-first-farmers-action-label-\(twoDigits(actionIndex + 1))"),
                        launchEnglish: sequence.accessibilityLabel
                    ),
                    visibleFallbackCue: LocalizedStringSpec(
                        id: LocalizedStringID("copy-first-farmers-action-cue-\(twoDigits(actionIndex + 1))"),
                        launchEnglish: sequence.shortAction
                    ),
                    directGesture: gestures[actionIndex],
                    inputModalities: [.directTouch, .voiceOver],
                    minimumTouchTargetPoints: 52,
                    reduceMotionUsesSameDomainAction: true
                )
            }

            let materialBindingID = MaterialBinding3DID("material-binding-first-farmers-\(suffix)")
            let animationBindingID = AnimationBinding3DID("animation-binding-first-farmers-\(suffix)")
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
            let materialStateID = MaterialState3DID("material-state-first-farmers-\(suffix)-ready")
            let animationStateID = AnimationState3DID("animation-state-first-farmers-\(suffix)-ready")
            let defaultAnchor = cameraAnchor(
                id: CameraAnchor3DID("camera-anchor-first-farmers-\(suffix)-default"),
                entityID: entity.id,
                reduced: false
            )
            let reducedAnchor = cameraAnchor(
                id: CameraAnchor3DID("camera-anchor-first-farmers-\(suffix)-reduced"),
                entityID: entity.id,
                reduced: true
            )

            return WorldCell3DSpec(
                id: Chapter01ImmersiveV2Authority.worldCellIDs[cellIndex],
                sceneGraphAssetID: sceneAssetID,
                entities: [entity],
                materialBindings: [
                    MaterialBinding3DSpec(
                        id: materialBindingID,
                        entityID: entity.id,
                        reducerStateKey: "first-farmers-cell-\(suffix)-material",
                        initialStateID: materialStateID,
                        states: [MaterialState3DSpec(id: materialStateID, assetID: materialAssetID)]
                    ),
                ],
                animationBindings: [
                    AnimationBinding3DSpec(
                        id: animationBindingID,
                        entityID: entity.id,
                        reducerStateKey: "first-farmers-cell-\(suffix)-animation",
                        initialStateID: animationStateID,
                        states: [
                            AnimationState3DSpec(
                                id: animationStateID,
                                assetID: animationAssetID,
                                loops: false
                            ),
                        ]
                    ),
                ],
                cameraTracks: [
                    CameraTrackSpec(
                        id: cameraTrackIDs[cellIndex],
                        anchors: [defaultAnchor],
                        authoredDurationSeconds: 8,
                        maximumUnbrokenTravelSeconds: 8,
                        reduceMotion: ReduceMotionCameraTrackSpec(
                            anchors: [reducedAnchor],
                            transition: .shortEase,
                            maximumTransitionSeconds: 0.25
                        )
                    ),
                ],
                semanticActions: actions,
                lodGroups: [
                    LODGroup3DSpec(
                        id: LODGroup3DID("lod-group-first-farmers-\(suffix)"),
                        entityID: entity.id,
                        levels: [LODLevel3DSpec(maximumDistanceMeters: 100, assetID: sceneAssetID)]
                    ),
                ]
            )
        }
    }

    static func makeBaseAudioBindings(
        cellIDs: [WorldCell3DID],
        sequenceIDs: [ExperienceSequenceID],
        interactionIDs: [InteractionID],
        integrity: [String: Chapter01ImmersiveAssetIntegrity],
        assets: inout [AssetReference3DSpec]
    ) throws -> [ImmersiveAudioBindingSpec] {
        var bindings: [ImmersiveAudioBindingSpec] = []
        for index in cellIDs.indices {
            bindings.append(
                try makeAudio(
                    suffix: "environment-\(twoDigits(index + 1))",
                    role: .environment,
                    cellID: cellIDs[index],
                    durationSeconds: 8,
                    loops: true,
                    integrity: integrity,
                    assets: &assets
                )
            )
        }
        for index in sequenceIDs.indices {
            bindings.append(
                try makeAudio(
                    suffix: "mechanism-\(twoDigits(index + 1))",
                    role: .mechanism,
                    sequenceID: sequenceIDs[index],
                    interactionID: interactionIDs[index],
                    durationSeconds: 4,
                    loops: false,
                    integrity: integrity,
                    assets: &assets
                )
            )
            bindings.append(
                try makeAudio(
                    suffix: "transition-\(twoDigits(index + 1))",
                    role: .transition,
                    sequenceID: sequenceIDs[index],
                    durationSeconds: 3,
                    loops: false,
                    integrity: integrity,
                    assets: &assets
                )
            )
        }
        return bindings
    }

    static func makeNarration(
        sequenceIDs: [ExperienceSequenceID],
        integrity: [String: Chapter01ImmersiveAssetIntegrity],
        assets: inout [AssetReference3DSpec]
    ) throws -> NarrationBuild {
        var audioBindings: [ImmersiveAudioBindingSpec] = []
        var bindings: [NarrationBinding3DSpec] = []
        var captions: [CaptionBinding3DSpec] = []

        for (index, draft) in NarrationDraft.all.enumerated() {
            let number = index + 1
            let suffix = twoDigits(number)
            let wordCount = draft.text.split(whereSeparator: \.isWhitespace).count
            let durationSeconds = UInt64(max(3, min(14, Int(ceil(Double(wordCount) / 2.35)) + 1)))
            let audio = try makeAudio(
                suffix: "narration-\(suffix)",
                role: .narration,
                sequenceID: sequenceIDs[draft.sequenceIndex],
                durationSeconds: durationSeconds,
                loops: false,
                integrity: integrity,
                assets: &assets
            )
            audioBindings.append(audio)

            let cueID = AudioCueID("narration-first-farmers-\(suffix)")
            let captionIDs: [CaptionBinding3DID] = draft.phrases.indices.map {
                CaptionBinding3DID("caption-first-farmers-\(suffix)-\(twoDigits($0 + 1))")
            }
            let text = LocalizedStringSpec(
                id: LocalizedStringID("copy-first-farmers-narration-\(suffix)"),
                launchEnglish: draft.text
            )
            bindings.append(
                NarrationBinding3DSpec(
                    id: cueID,
                    sequenceID: sequenceIDs[draft.sequenceIndex],
                    audioBindingID: audio.id,
                    text: text,
                    captionIDs: captionIDs,
                    beginsAfterPreciseInputRelease: true
                )
            )

            let totalFrames = durationSeconds * 48_000
            let phraseWordCounts = draft.phrases.map {
                max(1, $0.split(whereSeparator: \.isWhitespace).count)
            }
            let totalWords = phraseWordCounts.reduce(0, +)
            var startFrame: UInt64 = 0
            for phraseIndex in draft.phrases.indices {
                let isLast = phraseIndex == draft.phrases.index(before: draft.phrases.endIndex)
                let usedWords = phraseWordCounts.prefix(phraseIndex + 1).reduce(0, +)
                let proportionalEnd = UInt64(
                    Double(totalFrames) * Double(usedWords) / Double(totalWords)
                )
                let endFrame = isLast ? totalFrames : max(startFrame + 1, proportionalEnd)
                captions.append(
                    CaptionBinding3DSpec(
                        id: captionIDs[phraseIndex],
                        narrationCueID: cueID,
                        text: LocalizedStringSpec(
                            id: LocalizedStringID(
                                "copy-first-farmers-narration-\(suffix)-caption-\(twoDigits(phraseIndex + 1))"
                            ),
                            launchEnglish: draft.phrases[phraseIndex]
                        ),
                        startSampleFrame: startFrame,
                        endSampleFrame: endFrame,
                        maximumLineCount: 2
                    )
                )
                startFrame = endFrame
            }
        }

        return NarrationBuild(
            drafts: NarrationDraft.all,
            audioBindings: audioBindings,
            bindings: bindings,
            captions: captions
        )
    }

    static func makeSequences(
        cellIDs: [WorldCell3DID],
        sequenceIDs: [ExperienceSequenceID],
        interactionIDs: [InteractionID],
        semanticActionIDs: [SemanticAction3DID],
        cameraTrackIDs: [CameraTrack3DID],
        narrationDrafts: [NarrationDraft]
    ) throws -> [ExperienceSequenceSpec] {
        let sequenceCells: [[WorldCell3DID]] = [
            [cellIDs[0], cellIDs[1]], [cellIDs[1]], [cellIDs[2]],
            [cellIDs[3]], [cellIDs[4]], [cellIDs[4]],
        ]
        let grammars: [ImmersiveInteractionGrammar] = [
            .trace, .allocate, .transform, .assemble, .transform, .transform,
        ]

        return try Chapter01Sequence.allCases.enumerated().map { sequenceIndex, sequence in
            let scriptBeats = Chapter01ExperienceScript.beats.filter { $0.sequence == sequence }
            guard !scriptBeats.isEmpty else {
                throw Chapter01ImmersivePayloadFactoryError.invalidApprovedProjection(
                    reason: "sequence \(sequenceIndex + 1) has no durable beats"
                )
            }
            let narrationForSequence = narrationDrafts.filter { $0.sequenceIndex == sequenceIndex }
            let narrationByBeat = Dictionary(
                uniqueKeysWithValues: narrationForSequence.map { ($0.beatID, $0.cueID) }
            )

            let beats: [ExperienceBeat3DSpec] = try scriptBeats.enumerated().map { beatIndex, scriptBeat in
                guard let duration = beatDurations[scriptBeat.id],
                      let cellIndex = cellIndex(for: scriptBeat.cell) else {
                    throw Chapter01ImmersivePayloadFactoryError.invalidApprovedProjection(
                        reason: "beat \(scriptBeat.id) is not bound to V2 timing and cell authority"
                    )
                }
                let actionIDs = scriptBeat.id == actionBeatIDs[sequenceIndex]
                    ? [semanticActionIDs[sequenceIndex]]
                    : []
                let narrationIDs = narrationByBeat[scriptBeat.id].map { [$0] } ?? []
                return ExperienceBeat3DSpec(
                    id: ExperienceBeatID("beat-first-farmers-\(scriptBeat.id)"),
                    cellID: cellIDs[cellIndex],
                    authoredDurationSeconds: duration,
                    maximumPassiveSeconds: sequenceIndex == 0 && beatIndex == 0 ? 2 : 6,
                    cameraTrackID: cameraTrackIDs[cellIndex],
                    semanticActionIDs: actionIDs,
                    narrationCueIDs: narrationIDs,
                    endsAtStableRestorationState: beatIndex == scriptBeats.count - 1
                )
            }
            let duration = beats.reduce(0) { $0 + $1.authoredDurationSeconds }
            guard abs(duration - sequenceDurations[sequenceIndex]) < 0.001 else {
                throw Chapter01ImmersivePayloadFactoryError.invalidApprovedProjection(
                    reason: "sequence \(sequenceIndex + 1) duration does not preserve the approved pressure map"
                )
            }
            let narrationCueIDs = narrationForSequence.map(\.cueID)
            return ExperienceSequenceSpec(
                id: sequenceIDs[sequenceIndex],
                locationCue: nil,
                worldCellIDs: sequenceCells[sequenceIndex],
                authoredDurationSeconds: sequenceDurations[sequenceIndex],
                principalInteraction: PrincipalInteraction3DBindingSpec(
                    interactionID: interactionIDs[sequenceIndex],
                    grammar: grammars[sequenceIndex]
                ),
                beats: beats,
                narrationCueIDs: narrationCueIDs
            )
        }
    }

    static func makeTransitions(
        cellIDs: [WorldCell3DID],
        sequenceIDs: [ExperienceSequenceID],
        entityIDs: [WorldEntity3DID],
        cameraTrackIDs: [CameraTrack3DID]
    ) -> [TransitionCarrierSpec] {
        let map = [
            (0, 0, 0, 1), (0, 1, 1, 1), (1, 2, 1, 2),
            (2, 3, 2, 3), (3, 4, 3, 4), (4, 5, 4, 4),
        ]
        let kinds: [TransitionCarrierKind3D] = [
            .load, .surface, .load, .route, .route, .load,
        ]

        return Chapter01ImmersiveV2Authority.transitionIDs.indices.map { index in
            let boundary = map[index]
            let sourceEntityID = entityIDs[boundary.2]
            let destinationEntityID = entityIDs[boundary.3]
            return TransitionCarrierSpec(
                id: Chapter01ImmersiveV2Authority.transitionIDs[index],
                sourceSequenceID: sequenceIDs[boundary.0],
                destinationSequenceID: sequenceIDs[boundary.1],
                sourceCellID: cellIDs[boundary.2],
                destinationCellID: cellIDs[boundary.3],
                kind: kinds[index],
                sourceEntityID: sourceEntityID,
                destinationEntityID: destinationEntityID,
                identityRule: sourceEntityID == destinationEntityID
                    ? .preserveIdentity
                    : .visibleHandoff,
                cameraTrackID: cameraTrackIDs[boundary.2],
                audioBindingID: AudioBinding3DID(
                    "audio-binding-first-farmers-transition-\(twoDigits(boundary.1 + 1))"
                ),
                prefetchesDestinationCell: boundary.2 != boundary.3,
                visibleCue: nil
            )
        }
    }

    static func makeAudio(
        suffix: String,
        role: ImmersiveAudioRole,
        cellID: WorldCell3DID? = nil,
        sequenceID: ExperienceSequenceID? = nil,
        interactionID: InteractionID? = nil,
        durationSeconds: UInt64,
        loops: Bool,
        integrity: [String: Chapter01ImmersiveAssetIntegrity],
        assets: inout [AssetReference3DSpec]
    ) throws -> ImmersiveAudioBindingSpec {
        let path = "\(assetRoot)/audio/\(suffix).m4a"
        let assetID = AssetReference3DID("asset-first-farmers-audio-\(suffix)")
        assets.append(try asset(assetID, .audio, path, integrity))
        return ImmersiveAudioBindingSpec(
            id: AudioBinding3DID("audio-binding-first-farmers-\(suffix)"),
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

    static func asset(
        _ id: AssetReference3DID,
        _ kind: ImmersiveAssetKind,
        _ path: String,
        _ integrityByPath: [String: Chapter01ImmersiveAssetIntegrity]
    ) throws -> AssetReference3DSpec {
        guard let integrity = integrityByPath[path] else {
            throw Chapter01ImmersivePayloadFactoryError.missingAssetIntegrity(path: path)
        }
        return AssetReference3DSpec(
            id: id,
            kind: kind,
            path: path,
            sha256: integrity.sha256,
            byteCount: integrity.byteCount
        )
    }

    static func cameraAnchor(
        id: CameraAnchor3DID,
        entityID: WorldEntity3DID,
        reduced: Bool
    ) -> CameraAnchor3DSpec {
        CameraAnchor3DSpec(
            id: id,
            pose: CameraPose3DSpec(
                position: Vector3DSpec(x: 0, y: reduced ? 1.35 : 1.4, z: 2.8),
                pitchDegrees: reduced ? -6 : -8,
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

    static func cellIndex(for cell: Chapter01WorldCell) -> Int? {
        switch cell {
        case .aegeanPassage: 0
        case .thessalianHousehold: 1
        case .ironGates: 2
        case .longhouseGround: 3
        case .settlementLandscape: 4
        }
    }

    static func twoDigits(_ number: Int) -> String {
        String(format: "%02d", number)
    }
}
