import ContentKit
import ContentKitTestSupport
import Foundation
import JourneyDomain

struct JourneyContentIdentifierOverrides {
    var arcID: ArcID?
    var beatID: BeatID?
    var sceneID: SceneID?
    var interactionID: InteractionID?
    var timelineID: AudioTimelineID?
    var cueID: AudioCueID?
    var accessibilityID: AccessibilityID?
    var effectID: WorldEffectID?
}

enum JourneyContentFixtures {
    static let version = SchemaVersion(major: 1)
    static let worldSeed = WorldSeedSpec(nodes: [], traces: [])

    static func package(
        _ packageID: PackageID,
        schemaVersion: SchemaVersion = version,
        worldSeed: WorldSeedSpec = worldSeed,
        firstChapterOverrides: JourneyContentIdentifierOverrides = .init(),
        alteredTitleFor chapterWithAlteredTitle: ChapterID? = nil,
        reverseChapterOrder: Bool = false
    ) -> ContentPackagePayload {
        let manifest = LaunchContent.collectionManifest
        let packageSpec = manifest.packages.first { $0.id == packageID }!
        let catalog = Dictionary(uniqueKeysWithValues: manifest.chapters.map { ($0.id, $0) })
        var chapterIDs = packageSpec.chapterIDs
        if reverseChapterOrder { chapterIDs.reverse() }

        let chapters = chapterIDs.enumerated().map { offset, chapterID in
            let entry = catalog[chapterID]!
            let overrides = offset == 0 ? firstChapterOverrides : .init()
            let title = chapterWithAlteredTitle == chapterID
                ? LocalizedStringSpec(
                    id: LocalizedStringID("altered-\(chapterID.rawValue)-title"),
                    launchEnglish: "Altered title"
                )
                : entry.title
            return chapter(
                entry: entry,
                schemaVersion: schemaVersion,
                title: title,
                isCoordinatorChapter: chapterID == "first-farmers",
                overrides: overrides
            )
        }
        let scenes = chapters.flatMap { chapter in
            chapter.arcs.flatMap { arc in
                arc.beats.map { beat in
                    scene(
                        id: beat.sceneID,
                        accessibilityID: beat.interaction?.accessibilityID
                            ?? AccessibilityID("accessibility-\(beat.id.rawValue)"),
                        interaction: beat.interaction
                    )
                }
            }
        }
        let accessibility = chapters.flatMap { chapter in
            chapter.arcs.flatMap { arc in
                arc.beats.map { beat in
                    accessibilitySpec(
                        id: beat.interaction?.accessibilityID
                            ?? AccessibilityID("accessibility-\(beat.id.rawValue)"),
                        interaction: beat.interaction
                    )
                }
            }
        }
        let timelineID = firstChapterOverrides.timelineID
            ?? AudioTimelineID("timeline-\(packageID.rawValue)")
        let cueID = firstChapterOverrides.cueID
            ?? AudioCueID("sound-\(packageID.rawValue)")
        let responsiveAudio = responsiveAudioProjection(chapters: chapters)
        return ContentPackagePayload(
            schemaVersion: schemaVersion,
            packageID: packageID,
            worldSeed: worldSeed,
            chapters: chapters,
            scenes: scenes,
            audioTimelines: [
                AudioTimeline(
                    id: timelineID,
                    sampleRate: 48_000,
                    events: [
                        AudioEvent(
                            cueID: cueID,
                            role: .soundscape,
                            startSample: 0,
                            durationSamples: 48_000,
                            assetPath: "audio/\(packageID.rawValue).m4a",
                            gain: 1
                        ),
                    ],
                    haptics: []
                ),
            ] + responsiveAudio.timelines,
            responsiveAudioPrograms: responsiveAudio.programs,
            accessibility: accessibility
        )
    }

    static func futurePackage(
        packageID: PackageID = "deep-dive-alpha-v1",
        chapterID: ChapterID = "alpha-deep-dive",
        schemaVersion: SchemaVersion = version,
        worldSeed: WorldSeedSpec = worldSeed
    ) -> ContentPackagePayload {
        let title = LocalizedStringSpec(
            id: LocalizedStringID("chapter-\(chapterID.rawValue)-title"),
            launchEnglish: "A Future Deep Dive"
        )
        let period = LocalizedStringSpec(
            id: LocalizedStringID("chapter-\(chapterID.rawValue)-period"),
            launchEnglish: "A later historical release"
        )
        let entry = ChapterIndexEntry(
            id: chapterID,
            sequence: 1,
            title: title,
            period: period,
            packageID: packageID,
            access: .included
        )
        let chapter = chapter(
            entry: entry,
            schemaVersion: schemaVersion,
            title: title,
            isCoordinatorChapter: false,
            overrides: JourneyContentIdentifierOverrides(
                effectID: WorldEffectID("effect-\(chapterID.rawValue)-complete")
            )
        )
        let scenes = chapter.arcs.flatMap { arc in
            arc.beats.map { beat in
                scene(
                    id: beat.sceneID,
                    accessibilityID: beat.interaction?.accessibilityID
                        ?? AccessibilityID("accessibility-\(beat.id.rawValue)"),
                    interaction: beat.interaction
                )
            }
        }
        let accessibility = chapter.arcs.flatMap { arc in
            arc.beats.map { beat in
                accessibilitySpec(
                    id: beat.interaction?.accessibilityID
                        ?? AccessibilityID("accessibility-\(beat.id.rawValue)"),
                    interaction: beat.interaction
                )
            }
        }
        let responsiveAudio = responsiveAudioProjection(chapters: [chapter])
        return ContentPackagePayload(
            schemaVersion: schemaVersion,
            packageID: packageID,
            worldSeed: worldSeed,
            chapters: [chapter],
            scenes: scenes,
            audioTimelines: [
                AudioTimeline(
                    id: AudioTimelineID("timeline-\(packageID.rawValue)"),
                    sampleRate: 48_000,
                    events: [
                        AudioEvent(
                            cueID: AudioCueID("sound-\(packageID.rawValue)"),
                            role: .soundscape,
                            startSample: 0,
                            durationSamples: 48_000,
                            assetPath: "audio/\(packageID.rawValue).m4a",
                            gain: 1
                        ),
                    ],
                    haptics: []
                ),
            ] + responsiveAudio.timelines,
            responsiveAudioPrograms: responsiveAudio.programs,
            accessibility: accessibility
        )
    }

    static func replacing(
        _ payload: ContentPackagePayload,
        packageID: PackageID? = nil,
        worldSeed: WorldSeedSpec? = nil,
        chapters: [ChapterSpec]? = nil
    ) -> ContentPackagePayload {
        ContentPackagePayload(
            schemaVersion: payload.schemaVersion,
            packageID: packageID ?? payload.packageID,
            worldSeed: worldSeed ?? payload.worldSeed,
            chapters: chapters ?? payload.chapters,
            scenes: payload.scenes,
            audioTimelines: payload.audioTimelines,
            responsiveAudioPrograms: payload.responsiveAudioPrograms,
            accessibility: payload.accessibility
        )
    }

    private static func responsiveAudioProjection(
        chapters: [ChapterSpec]
    ) -> (programs: [ResponsiveAudioProgramSpec], timelines: [AudioTimeline]) {
        let scopes = chapters.flatMap { chapter in
            chapter.arcs.flatMap { arc in
                arc.beats.compactMap { beat in
                    beat.interaction.map { interaction in
                        ResponsiveAudioProgramScope(
                            chapterID: chapter.id,
                            arcID: arc.id,
                            beatID: beat.id,
                            interactionID: interaction.id
                        )
                    }
                }
            }
        }
        var programs: [ResponsiveAudioProgramSpec] = []
        var timelines: [AudioTimeline] = []
        for scope in scopes {
            func timeline(_ region: String, duration: Int64) -> AudioTimeline {
                let id = AudioTimelineID("responsive-\(scope.beatID.rawValue)-\(region)")
                return AudioTimeline(
                    id: id,
                    sampleRate: 48_000,
                    events: [
                        AudioEvent(
                            cueID: AudioCueID("cue-\(id.rawValue)"),
                            role: .soundscape,
                            startSample: 0,
                            durationSamples: duration,
                            assetPath: "audio/\(id.rawValue).m4a",
                            gain: 1
                        ),
                    ],
                    haptics: []
                )
            }
            let approach = timeline("approach", duration: 96_000)
            let waiting = timeline("waiting", duration: 48_000)
            let engaged = timeline("engaged", duration: 48_000)
            let resistance = timeline("resistance", duration: 48_000)
            let consequence = timeline("consequence", duration: 96_000)
            timelines += [approach, waiting, engaged, resistance, consequence]
            programs.append(
                ResponsiveAudioProgramSpec(
                    id: ResponsiveAudioProgramID("program-\(scope.interactionID.rawValue)"),
                    scope: scope,
                    approachTimelineID: approach.id,
                    interactionBeds: [
                        ResponsiveInteractionAudioBedSpec(
                            phase: .waiting,
                            timelineID: waiting.id,
                            layerStates: ResponsiveAudioLayerStateSelection(
                                scoreStateID: nil,
                                soundscapeStateID: "waiting-world"
                            )
                        ),
                        ResponsiveInteractionAudioBedSpec(
                            phase: .engaged,
                            timelineID: engaged.id,
                            layerStates: ResponsiveAudioLayerStateSelection(
                                scoreStateID: nil,
                                soundscapeStateID: "engaged-world"
                            )
                        ),
                        ResponsiveInteractionAudioBedSpec(
                            phase: .resistance,
                            timelineID: resistance.id,
                            layerStates: ResponsiveAudioLayerStateSelection(
                                scoreStateID: nil,
                                soundscapeStateID: "resistance-world"
                            )
                        ),
                    ],
                    consequenceTimelineID: consequence.id,
                    exitPolicy: .boundedFade(durationSamples: 480)
                )
            )
        }
        return (programs, timelines)
    }

    static func signedManifest(
        for payload: ContentPackagePayload,
        packageVersion: SchemaVersion = version,
        schemaVersion: SchemaVersion? = nil,
        minimumRuntime: SchemaVersion = version
    ) -> SignedPackageManifest {
        SignedPackageManifest(
            packageID: payload.packageID,
            packageVersion: packageVersion,
            schemaVersion: schemaVersion ?? payload.schemaVersion,
            minimumRuntime: minimumRuntime,
            files: [
                PackageFileRecord(
                    path: "content.json",
                    bytes: 1,
                    sha256: String(repeating: "0", count: 64)
                ),
            ],
            manifestDigest: "test-only",
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "test-only",
                value: "dGVzdA=="
            )
        )
    }

    static func applying(
        _ actions: [JourneyAction],
        to initial: JourneyState = .initial
    ) -> JourneyState {
        var state = initial
        let reducer = JourneyReducer()
        for action in actions {
            let effects = reducer.reduce(state: &state, action: action)
            precondition(!effects.contains { effect in
                if case .rejected = effect { return true }
                return false
            })
        }
        return state
    }

    private static func chapter(
        entry: ChapterIndexEntry,
        schemaVersion: SchemaVersion,
        title: LocalizedStringSpec,
        isCoordinatorChapter: Bool,
        overrides: JourneyContentIdentifierOverrides
    ) -> ChapterSpec {
        let base = entry.id.rawValue
        let firstArcID = overrides.arcID ?? ArcID("\(base)-arc-one")
        let firstBeatID = overrides.beatID ?? BeatID("\(base)-beat-one")
        let firstSceneID = overrides.sceneID ?? SceneID("\(base)-scene-one")
        let interactionID = overrides.interactionID
            ?? InteractionID("\(base)-interaction")
        let accessibilityID = overrides.accessibilityID
            ?? AccessibilityID("accessibility-\(isCoordinatorChapter ? "\(base)-beat-two" : firstBeatID.rawValue)")
        let interaction = traceInteraction(
            id: interactionID,
            accessibilityID: accessibilityID,
            effectID: WorldEffectID("effect-\(interactionID.rawValue)")
        )

        let arcs: [ArcSpec]
        if isCoordinatorChapter {
            let secondBeatID: BeatID = "first-farmers-beat-two"
            let secondSceneID: SceneID = "first-farmers-scene-two"
            let secondAccessibilityID = overrides.accessibilityID
                ?? AccessibilityID("accessibility-\(secondBeatID.rawValue)")
            let coordinatorInteraction = traceInteraction(
                id: interactionID,
                accessibilityID: secondAccessibilityID,
                effectID: WorldEffectID("effect-\(interactionID.rawValue)")
            )
            arcs = [
                arc(
                    id: firstArcID,
                    beats: [
                        beat(id: firstBeatID, sceneID: firstSceneID),
                        beat(
                            id: secondBeatID,
                            sceneID: secondSceneID,
                            interaction: coordinatorInteraction
                        ),
                    ]
                ),
                arc(
                    id: "first-farmers-arc-two",
                    beats: [
                        beat(
                            id: "first-farmers-beat-three",
                            sceneID: "first-farmers-scene-three"
                        ),
                    ]
                ),
            ]
        } else {
            arcs = [
                arc(
                    id: firstArcID,
                    beats: [
                        beat(
                            id: firstBeatID,
                            sceneID: firstSceneID,
                            interaction: interaction
                        ),
                    ]
                ),
            ]
        }
        return ChapterSpec(
            schemaVersion: schemaVersion,
            id: entry.id,
            title: title,
            period: entry.period,
            arcs: arcs,
            completionEffects: [
                revealEffect(
                    id: overrides.effectID
                        ?? WorldEffectID("effect-complete-\(base)"),
                    nodeID: WorldNodeID("node-complete-\(base)")
                ),
            ]
        )
    }

    private static func arc(id: ArcID, beats: [BeatSpec]) -> ArcSpec {
        ArcSpec(
            id: id,
            title: "An authored arc",
            targetDurationMinutes: 8,
            situation: "A concrete historical situation begins.",
            mechanism: "A visible mechanism carries the action.",
            turn: "The mechanism crosses its threshold.",
            consequence: "The historical order changes.",
            handoff: "The changed order opens the next movement.",
            beats: beats
        )
    }

    private static func beat(
        id: BeatID,
        sceneID: SceneID,
        interaction: InteractionSpec? = nil
    ) -> BeatSpec {
        BeatSpec(
            id: id,
            sceneID: sceneID,
            narrative: NarrativeText(
                heading: "A historical mechanism",
                paragraphs: ["The action leaves a concrete consequence in the world."]
            ),
            interaction: interaction,
            completionEffects: interaction == nil ? [
                revealEffect(
                    id: WorldEffectID("effect-documentary-\(id.rawValue)"),
                    nodeID: WorldNodeID("node-documentary-\(id.rawValue)")
                ),
            ] : [],
            checkpoint: interaction == nil ? .onExit : .afterInteraction
        )
    }

    private static func traceInteraction(
        id: InteractionID,
        accessibilityID: AccessibilityID,
        effectID: WorldEffectID
    ) -> InteractionSpec {
        InteractionSpec(
            id: id,
            prompt: "Carry the route through the landscape",
            grammar: .trace(
                TraceInteractionSpec(
                    anchors: [
                        NormalizedPoint(x: 0.4, y: 0.5),
                        NormalizedPoint(x: 0.6, y: 0.5),
                    ],
                    tolerance: 0.08
                )
            ),
            completionEffects: [
                revealEffect(
                    id: effectID,
                    nodeID: WorldNodeID("node-\(id.rawValue)")
                ),
            ],
            accessibilityID: accessibilityID
        )
    }

    private static func scene(
        id: SceneID,
        accessibilityID: AccessibilityID,
        interaction: InteractionSpec?
    ) -> SceneSpec {
        let crop = SceneViewportCrop(
            id: "baseline-393x852",
            viewport: SceneViewportSize(widthPoints: 393, heightPoints: 852),
            sourceRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            safeTextRegions: [
                SceneSafeTextRegion(
                    id: "opening-copy",
                    rect: NormalizedRect(x: 0.08, y: 0.08, width: 0.84, height: 0.2)
                ),
            ]
        )
        let layerID = SceneLayerID("layer-\(id.rawValue)")
        let variants: [SceneLayerStateVariant] = if interaction == nil {
            []
        } else {
            [
                SceneLayerStateVariant(id: "idle", assetPath: "assets/\(id.rawValue)-idle.heif"),
                SceneLayerStateVariant(id: "tracing", assetPath: "assets/\(id.rawValue)-tracing.heif"),
                SceneLayerStateVariant(id: "completed", assetPath: "assets/\(id.rawValue)-completed.heif"),
            ]
        }
        let strata: [ReduceMotionStratum] = if interaction == nil {
            [
                ReduceMotionStratum(
                    id: "static-world",
                    kind: .staticPlate,
                    assetPath: "assets/\(id.rawValue)-reduced.heif"
                ),
            ]
        } else {
            [
                ReduceMotionStratum(
                    id: "static-underlay",
                    kind: .staticPlate,
                    assetPath: "assets/\(id.rawValue)-reduced-underlay.heif"
                ),
                ReduceMotionStratum(
                    id: "route-state",
                    kind: .stateOverlay,
                    layerID: layerID
                ),
                ReduceMotionStratum(
                    id: "static-foreground",
                    kind: .staticPlate,
                    assetPath: "assets/\(id.rawValue)-reduced-foreground.heif"
                ),
            ]
        }
        let targetID = "route-\(id.rawValue)"
        return SceneSpec(
            id: id,
            sceneCanvas: SceneCanvasSpec(
                canvas: ScenePixelSize(width: 1_200, height: 2_600),
                cameraTravelBounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                authoredOverscanFraction: 0.15,
                viewportCrops: [crop]
            ),
            layers: [
                SceneLayerSpec(
                    id: layerID,
                    order: 0,
                    assetPath: "assets/\(id.rawValue).heif",
                    frame: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                    depth: 0.5,
                    motion: SceneLayerMotion(parallaxFactor: 0),
                    stateVariants: variants
                ),
            ],
            cameraRail: CameraRail(
                keyframes: [
                    CameraKeyframe(
                        progress: 0,
                        center: NormalizedPoint(x: 0.5, y: 0.5),
                        scale: 1
                    ),
                    CameraKeyframe(
                        progress: 1,
                        center: NormalizedPoint(x: 0.5, y: 0.5),
                        scale: 1
                    ),
                ]
            ),
            atmosphere: [],
            interactionTargets: interaction == nil ? [] : [
                SceneInteractionTargetBinding(
                    interactionTargetID: targetID,
                    layerID: layerID,
                    hitRegion: SceneHitRegion(
                        path: [
                            NormalizedPoint(x: 0.3, y: 0.4),
                            NormalizedPoint(x: 0.7, y: 0.4),
                            NormalizedPoint(x: 0.7, y: 0.6),
                            NormalizedPoint(x: 0.3, y: 0.6),
                        ]
                    ),
                    accessibilityElementID: "route-control"
                ),
            ],
            interactionVisualBinding: interaction.map {
                .trace(
                    SceneTraceVisualBinding(
                        interactionID: $0.id,
                        interactionTargetID: targetID,
                        layerID: layerID,
                        idleVariantID: "idle",
                        tracingVariantID: "tracing",
                        completedVariantID: "completed"
                    )
                )
            },
            reduceMotionComposition: ReduceMotionComposition(
                canvas: ScenePixelSize(width: 1_200, height: 2_600),
                viewportCrops: [crop],
                strata: strata
            ),
            mechanismFocus: "The route carries the historical mechanism.",
            accessibilityID: accessibilityID
        )
    }

    private static func accessibilitySpec(
        id: AccessibilityID,
        interaction: InteractionSpec?
    ) -> AccessibilitySpec {
        if interaction == nil {
            return AccessibilitySpec(
                id: id,
                sceneSummary: "A material historical scene.",
                elements: [
                    AccessibilityElementSpec(
                        id: "scene-image",
                        role: .image,
                        label: "The historical scene"
                    ),
                ]
            )
        }
        return AccessibilitySpec(
            id: id,
            sceneSummary: "A route crosses the landscape.",
            elements: [
                AccessibilityElementSpec(
                    id: "route-control",
                    role: .adjustable,
                    label: "Historical route",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .increment,
                            label: "Advance along the route",
                            token: .traceNext
                        ),
                    ]
                ),
            ]
        )
    }

    private static func revealEffect(
        id: WorldEffectID,
        nodeID: WorldNodeID
    ) -> WorldEffect {
        WorldEffect(
            id: id,
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: nodeID,
                    kind: .landscape,
                    form: "authored-test-form",
                    position: NormalizedPoint(x: 0.5, y: 0.5)
                )
            )
        )
    }
}
