@testable import ContentKit
import ContentKitTestSupport
import CryptoKit
import Foundation
import JourneyContent
import JourneyDomain
import SceneRuntime

private final class ChapterRuntimeTestBundleProbe: NSObject {}

struct RuntimeTestFixture {
    let repository: RuntimeTestRepository
    let coordinator: ChapterCoordinator
    let state: JourneyState
    let inventory: SceneAssetInventory
    let packageRoot: URL
    let interaction: InteractionSpec
    let accessibility: AccessibilitySpec

    static let version = SchemaVersion(major: 1)
    static let packageID: PackageID = "chapter-runtime-test-package"
    static let chapterID: ChapterID = "chapter-runtime-test-chapter"
    static let arcID: ArcID = "chapter-runtime-test-arc"
    static let beatID: BeatID = "chapter-runtime-test-beat"
    static let traceAuthoredViewportPoints = [0.3, 0.4, 0.5, 0.6].map {
        SceneFramePoint(x: $0, y: 0.5)
    }
    static let traceTouchPoints = [0.31, 0.39, 0.51, 0.59].map {
        SceneFramePoint(x: $0, y: 0.5)
    }

    static func trace(seedReachedAnchors: Int = 0) throws -> Self {
        let accessibilityID: AccessibilityID = "access-runtime-trace"
        let anchors = traceAuthoredViewportPoints.map {
            NormalizedPoint(
                x: 0.15 + ($0.x * 0.7),
                y: 0.15 + ($0.y * 0.7)
            )
        }
        let interaction = InteractionSpec(
            id: "runtime-trace",
            prompt: "Carry the route through the landscape.",
            grammar: .trace(TraceInteractionSpec(anchors: anchors, tolerance: 0.025)),
            completionEffects: [completionEffect("runtime-trace-complete")],
            accessibilityID: accessibilityID
        )
        let accessibility = AccessibilitySpec(
            id: accessibilityID,
            sceneSummary: "A route crosses the inhabited landscape.",
            elements: [
                AccessibilityElementSpec(
                    id: "route-control-accessibility",
                    role: .adjustable,
                    label: "Carry the route",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .increment,
                            label: "Reach the next place",
                            token: .traceNext
                        ),
                    ]
                ),
            ]
        )
        let scene = traceScene(interaction: interaction, accessibilityID: accessibilityID)
        var fixture = try make(
            scene: scene,
            interaction: interaction,
            accessibility: accessibility
        )
        guard (0 ... anchors.count).contains(seedReachedAnchors) else {
            throw RuntimeTestFixtureError.invalidSeed
        }
        if seedReachedAnchors > 0 {
            var seeded = fixture.state
            let reducer = JourneyReducer()
            for anchor in anchors.prefix(seedReachedAnchors) {
                let effects = reducer.reduce(
                    state: &seeded,
                    action: .interact(spec: interaction, action: .trace(anchor))
                )
                guard !effects.contains(where: \.isRejection) else {
                    throw RuntimeTestFixtureError.rejectedSeed
                }
            }
            fixture = Self(
                repository: fixture.repository,
                coordinator: fixture.coordinator,
                state: seeded,
                inventory: fixture.inventory,
                packageRoot: fixture.packageRoot,
                interaction: interaction,
                accessibility: accessibility
            )
        }
        return fixture
    }

    static func harvestAllocate() throws -> Self {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "phase1/fixtures/harvest-option-1.scene.json")
            .standardizedFileURL
        let fileURL = Bundle(for: ChapterRuntimeTestBundleProbe.self).url(
            forResource: "harvest-option-1.scene",
            withExtension: "json"
        ) ?? sourceFileURL
        let envelope = try JSONDecoder().decode(
            HarvestSceneEnvelope.self,
            from: Data(contentsOf: fileURL)
        )
        let scene = envelope.scene
        let interaction = InteractionSpec(
            id: InteractionID(envelope.nativeInteractionID),
            prompt: "Divide the harvest.",
            grammar: .allocate(
                AllocateInteractionSpec(
                    resourceName: "harvest shares",
                    totalUnits: envelope.interactionContract.totalUnits,
                    destinations: [
                        AllocationDestination(id: "food", minimumUnits: 4),
                        AllocationDestination(id: "reserve", minimumUnits: 2),
                        AllocationDestination(id: "seed", minimumUnits: 3),
                    ]
                )
            ),
            completionEffects: [completionEffect("runtime-harvest-complete")],
            accessibilityID: scene.accessibilityID
        )
        let accessibility = AccessibilitySpec(
            id: scene.accessibilityID,
            sceneSummary: "The harvest lies between three obligations.",
            elements: [
                AccessibilityElementSpec(
                    id: "allocate-winter-food",
                    role: .adjustable,
                    label: "Winter food",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .increment,
                            label: "Set aside four shares",
                            token: .allocate(destinationID: "food", unitsPerStep: 4)
                        ),
                        AccessibilityActionSpec(
                            kind: .decrement,
                            label: "Return four shares",
                            token: .allocate(destinationID: "food", unitsPerStep: 4)
                        ),
                    ]
                ),
                AccessibilityElementSpec(
                    id: "allocate-protected-reserve",
                    role: .adjustable,
                    label: "Protected reserve",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .increment,
                            label: "Set aside two shares",
                            token: .allocate(destinationID: "reserve", unitsPerStep: 2)
                        ),
                        AccessibilityActionSpec(
                            kind: .decrement,
                            label: "Return two shares",
                            token: .allocate(destinationID: "reserve", unitsPerStep: 2)
                        ),
                    ]
                ),
                AccessibilityElementSpec(
                    id: "allocate-spring-seed",
                    role: .adjustable,
                    label: "Spring seed",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .increment,
                            label: "Set aside six shares",
                            token: .allocate(destinationID: "seed", unitsPerStep: 6)
                        ),
                        AccessibilityActionSpec(
                            kind: .decrement,
                            label: "Return six shares",
                            token: .allocate(destinationID: "seed", unitsPerStep: 6)
                        ),
                    ]
                ),
                AccessibilityElementSpec(
                    id: "commit-harvest-allocation",
                    role: .action,
                    label: "Commit the harvest",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .activate,
                            label: "Commit",
                            token: .commitAllocation
                        ),
                    ]
                ),
            ]
        )
        return try make(
            scene: scene,
            interaction: interaction,
            accessibility: accessibility
        )
    }

    static func completedGrammarCases() throws -> [CompletedGrammarRuntimeCase] {
        let traceFixture = try trace(seedReachedAnchors: traceTouchPoints.count)
        let allocateFixture = try complete(
            harvestAllocate(),
            actions: [
                .allocate(destinationID: "food", units: 4),
                .allocate(destinationID: "reserve", units: 2),
                .allocate(destinationID: "seed", units: 6),
                .commitAllocation,
            ]
        )
        let assembleFixture = try complete(
            assemble(),
            actions: [.place(componentID: "charter", slotID: "law")]
        )
        let pressureFixture = try complete(
            pressure(),
            actions: [
                .setPressure(forceID: "defence", magnitude: 0.4),
                .advancePressure(elapsedMillis: 1_000),
            ]
        )
        let transformFixture = try complete(
            transform(),
            actions: [.transform(controlID: "field", amount: 1)]
        )
        return [
            CompletedGrammarRuntimeCase(
                name: "trace",
                fixture: traceFixture,
                touchIntent: .trace(viewportPoint: traceTouchPoints[0])
            ),
            CompletedGrammarRuntimeCase(
                name: "allocate",
                fixture: allocateFixture,
                touchIntent: .allocateContact(
                    viewportPoint: SceneFramePoint(x: 0.5, y: 0.5),
                    progress: 0.1
                )
            ),
            CompletedGrammarRuntimeCase(
                name: "assemble",
                fixture: assembleFixture,
                touchIntent: .activateTarget(
                    viewportPoint: SceneFramePoint(x: 0.5, y: 0.5)
                )
            ),
            CompletedGrammarRuntimeCase(
                name: "pressure",
                fixture: pressureFixture,
                touchIntent: .holdPressure(elapsedMillis: 500)
            ),
            CompletedGrammarRuntimeCase(
                name: "transform",
                fixture: transformFixture,
                touchIntent: .adjustTarget(
                    viewportPoint: SceneFramePoint(x: 0.5, y: 0.5),
                    amount: 1
                )
            ),
        ]
    }

    static func assemble() throws -> Self {
        let accessibilityID: AccessibilityID = "access-runtime-assemble"
        let interaction = InteractionSpec(
            id: "runtime-assemble",
            prompt: "Set the charter into law.",
            grammar: .assemble(
                AssembleInteractionSpec(
                    components: [
                        AssemblyComponent(id: "charter", targetSlot: "law"),
                    ]
                )
            ),
            completionEffects: [completionEffect("runtime-assemble-complete")],
            accessibilityID: accessibilityID
        )
        let layerID: SceneLayerID = "runtime-charter"
        let sourceTargetID = "runtime-charter-target"
        let slotTargetID = "runtime-charter-slot"
        let accessibilityElementID = "\(sourceTargetID)-accessibility"
        let scene = statefulScene(
            id: "runtime-assemble-scene",
            accessibilityID: accessibilityID,
            layers: [
                layer(layerID, variants: ["available", "resisted", "placed"]),
            ],
            targets: [
                target(
                    sourceTargetID,
                    layerID: layerID,
                    column: 0,
                    row: 0,
                    accessibilityElementID: accessibilityElementID
                ),
                target(
                    slotTargetID,
                    layerID: layerID,
                    column: 2,
                    row: 1,
                    accessibilityElementID: accessibilityElementID
                ),
            ],
            binding: .assemble(
                SceneAssembleVisualBinding(
                    interactionID: interaction.id,
                    components: [
                        SceneAssemblyComponentVisualBinding(
                            componentID: "charter",
                            sourceInteractionTargetID: sourceTargetID,
                            slotInteractionTargetID: slotTargetID,
                            layerID: layerID,
                            availableVariantID: "available",
                            resistedVariantID: "resisted",
                            placedVariantID: "placed"
                        ),
                    ]
                )
            )
        )
        let accessibility = AccessibilitySpec(
            id: accessibilityID,
            sceneSummary: "A charter waits to become law.",
            elements: [
                AccessibilityElementSpec(
                    id: accessibilityElementID,
                    role: .action,
                    label: "Place the charter",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .activate,
                            label: "Place",
                            token: .placeComponent(componentID: "charter")
                        ),
                    ]
                ),
            ]
        )
        return try make(
            scene: scene,
            interaction: interaction,
            accessibility: accessibility
        )
    }

    /// A self-contained Assemble fixture with no payload or runtime dependency
    /// outside the current beat. Distinct source and slot targets let tests
    /// prove both direct transport and wrong-slot rejection without encoding a
    /// house-specific order in SceneRuntime.
    static func assembleDirectManipulation() throws -> Self {
        let accessibilityID: AccessibilityID = "access-runtime-assemble-direct"
        let foundation = AssemblyComponent(id: "foundation", targetSlot: "ground")
        let roof = AssemblyComponent(
            id: "roof",
            targetSlot: "cover",
            prerequisites: [foundation.id]
        )
        let interaction = InteractionSpec(
            id: "runtime-assemble-direct",
            prompt: "Raise the structure from handled material.",
            grammar: .assemble(
                AssembleInteractionSpec(components: [roof, foundation])
            ),
            completionEffects: [completionEffect("runtime-assemble-direct-complete")],
            accessibilityID: accessibilityID
        )
        let foundationLayer: SceneLayerID = "runtime-foundation"
        let roofLayer: SceneLayerID = "runtime-roof"
        let foundationTarget = "runtime-foundation-target"
        let foundationSlot = "runtime-foundation-slot"
        let roofTarget = "runtime-roof-target"
        let roofSlot = "runtime-roof-slot"
        let scene = statefulScene(
            id: "runtime-assemble-direct-scene",
            accessibilityID: accessibilityID,
            layers: [
                layer(foundationLayer, variants: ["available", "resisted", "placed"]),
                layer(roofLayer, variants: ["available", "resisted", "placed"]),
            ],
            targets: [
                target(foundationTarget, layerID: foundationLayer, column: 0, row: 0),
                target(
                    foundationSlot,
                    layerID: foundationLayer,
                    column: 0,
                    row: 1,
                    accessibilityElementID: "\(foundationTarget)-accessibility"
                ),
                target(roofTarget, layerID: roofLayer, column: 2, row: 0),
                target(
                    roofSlot,
                    layerID: roofLayer,
                    column: 2,
                    row: 1,
                    accessibilityElementID: "\(roofTarget)-accessibility"
                ),
            ],
            binding: .assemble(
                SceneAssembleVisualBinding(
                    interactionID: interaction.id,
                    components: [
                        SceneAssemblyComponentVisualBinding(
                            componentID: foundation.id,
                            sourceInteractionTargetID: foundationTarget,
                            slotInteractionTargetID: foundationSlot,
                            layerID: foundationLayer,
                            availableVariantID: "available",
                            resistedVariantID: "resisted",
                            placedVariantID: "placed"
                        ),
                        SceneAssemblyComponentVisualBinding(
                            componentID: roof.id,
                            sourceInteractionTargetID: roofTarget,
                            slotInteractionTargetID: roofSlot,
                            layerID: roofLayer,
                            availableVariantID: "available",
                            resistedVariantID: "resisted",
                            placedVariantID: "placed"
                        ),
                    ]
                )
            )
        )
        let accessibility = AccessibilitySpec(
            id: accessibilityID,
            sceneSummary: "Two handled parts wait for their structural places.",
            elements: [
                AccessibilityElementSpec(
                    id: "\(foundationTarget)-accessibility",
                    role: .action,
                    label: "Place the foundation",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .activate,
                            label: "Place",
                            token: .placeComponent(componentID: foundation.id)
                        ),
                    ]
                ),
                AccessibilityElementSpec(
                    id: "\(roofTarget)-accessibility",
                    role: .action,
                    label: "Place the roof",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .activate,
                            label: "Place",
                            token: .placeComponent(componentID: roof.id)
                        ),
                    ]
                ),
            ]
        )
        return try make(
            scene: scene,
            interaction: interaction,
            accessibility: accessibility
        )
    }

    static func pressure() throws -> Self {
        let accessibilityID: AccessibilityID = "access-runtime-pressure"
        let interaction = InteractionSpec(
            id: "runtime-pressure",
            prompt: "Hold the frontier in balance.",
            grammar: .pressure(
                PressureInteractionSpec(
                    forces: [
                        PressureForce(
                            id: "defence",
                            direction: 1,
                            initialMagnitude: 0,
                            userControllable: true
                        ),
                        PressureForce(
                            id: "attack",
                            direction: -1,
                            initialMagnitude: 0.4,
                            userControllable: false
                        ),
                    ],
                    stableRange: 0 ... 0.1,
                    requiredHoldMillis: 1_000
                )
            ),
            completionEffects: [completionEffect("runtime-pressure-complete")],
            accessibilityID: accessibilityID
        )
        let defenceLayer: SceneLayerID = "runtime-defence"
        let attackLayer: SceneLayerID = "runtime-attack"
        let systemLayer: SceneLayerID = "runtime-frontier"
        let targetID = "runtime-defence-target"
        let scene = statefulScene(
            id: "runtime-pressure-scene",
            accessibilityID: accessibilityID,
            layers: [
                layer(defenceLayer, variants: []),
                layer(attackLayer, variants: []),
                layer(
                    systemLayer,
                    variants: ["resting", "resisting", "stable", "broken"]
                ),
            ],
            targets: [target(targetID, layerID: defenceLayer, column: 1)],
            binding: .pressure(
                ScenePressureVisualBinding(
                    interactionID: interaction.id,
                    forces: [
                        ScenePressureForceVisualBinding(
                            forceID: "defence",
                            layerID: defenceLayer,
                            interactionTargetID: targetID
                        ),
                        ScenePressureForceVisualBinding(
                            forceID: "attack",
                            layerID: attackLayer
                        ),
                    ],
                    systemLayerID: systemLayer,
                    restingVariantID: "resting",
                    resistingVariantID: "resisting",
                    stableVariantID: "stable",
                    brokenVariantID: "broken"
                )
            )
        )
        let accessibility = AccessibilitySpec(
            id: accessibilityID,
            sceneSummary: "Attack and defence press against the frontier.",
            elements: [
                AccessibilityElementSpec(
                    id: "\(targetID)-accessibility",
                    role: .adjustable,
                    label: "Defence",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .increment,
                            label: "Strengthen defence",
                            token: .adjustPressure(forceID: "defence", step: 0.4)
                        ),
                    ]
                ),
                AccessibilityElementSpec(
                    id: "runtime-pressure-hold",
                    role: .action,
                    label: "Hold the line",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .activate,
                            label: "Hold",
                            token: .holdPressure
                        ),
                    ]
                ),
            ]
        )
        return try make(
            scene: scene,
            interaction: interaction,
            accessibility: accessibility
        )
    }

    static func transform() throws -> Self {
        let accessibilityID: AccessibilityID = "access-runtime-transform"
        let interaction = InteractionSpec(
            id: "runtime-transform",
            prompt: "Turn the ground into a field.",
            grammar: .transform(
                TransformInteractionSpec(
                    stages: [
                        TransformationStage(
                            id: "clear",
                            controlID: "field",
                            requiredAmount: 1
                        ),
                    ]
                )
            ),
            completionEffects: [completionEffect("runtime-transform-complete")],
            accessibilityID: accessibilityID
        )
        let layerID: SceneLayerID = "runtime-ground"
        let targetID = "runtime-clear-target"
        let scene = statefulScene(
            id: "runtime-transform-scene",
            accessibilityID: accessibilityID,
            layers: [
                layer(
                    layerID,
                    variants: ["before", "active", "completed"]
                ),
            ],
            targets: [target(targetID, layerID: layerID, column: 1)],
            binding: .transform(
                SceneTransformVisualBinding(
                    interactionID: interaction.id,
                    stages: [
                        SceneTransformationStageVisualBinding(
                            stageID: "clear",
                            interactionTargetID: targetID,
                            layerID: layerID,
                            beforeVariantID: "before",
                            activeVariantID: "active",
                            completedVariantID: "completed"
                        ),
                    ]
                )
            )
        )
        let accessibility = AccessibilitySpec(
            id: accessibilityID,
            sceneSummary: "The ground changes under sustained work.",
            elements: [
                AccessibilityElementSpec(
                    id: "\(targetID)-accessibility",
                    role: .adjustable,
                    label: "Clear the ground",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .increment,
                            label: "Work the ground",
                            token: .advanceTransform(stageID: "clear", step: 1)
                        ),
                    ]
                ),
            ]
        )
        return try make(
            scene: scene,
            interaction: interaction,
            accessibility: accessibility
        )
    }

    private static func complete(
        _ fixture: Self,
        actions: [InteractionAction]
    ) throws -> Self {
        var state = fixture.state
        let reducer = JourneyReducer()
        for action in actions {
            let effects = reducer.reduce(
                state: &state,
                action: .interact(spec: fixture.interaction, action: action)
            )
            guard !effects.contains(where: \.isRejection) else {
                throw RuntimeTestFixtureError.rejectedSeed
            }
        }
        guard state.activeChapter?.interaction?.phase == .complete else {
            throw RuntimeTestFixtureError.incompleteSeed
        }
        return Self(
            repository: fixture.repository,
            coordinator: fixture.coordinator,
            state: state,
            inventory: fixture.inventory,
            packageRoot: fixture.packageRoot,
            interaction: fixture.interaction,
            accessibility: fixture.accessibility
        )
    }

    private static func statefulScene(
        id: SceneID,
        accessibilityID: AccessibilityID,
        layers authoredLayers: [SceneLayerSpec],
        targets: [SceneInteractionTargetBinding],
        binding: SceneInteractionVisualBinding
    ) -> SceneSpec {
        let sources = [layer("runtime-world", variants: [])] + authoredLayers
        let layers = sources.enumerated().map { index, source in
            SceneLayerSpec(
                id: source.id,
                order: index,
                assetPath: source.assetPath,
                frame: source.frame,
                depth: source.depth,
                opacity: source.opacity,
                blendMode: source.blendMode,
                masks: source.masks,
                motion: source.motion,
                stateVariants: source.stateVariants
            )
        }
        let stateOverlays = layers.filter { !$0.stateVariants.isEmpty }.map {
            ReduceMotionStratum(
                id: "\($0.id.rawValue)-state",
                kind: .stateOverlay,
                layerID: $0.id
            )
        }
        return SceneSpec(
            id: id,
            sceneCanvas: SceneCanvasSpec(
                canvas: ScenePixelSize(width: 1_179, height: 2_556),
                cameraTravelBounds: NormalizedRect(
                    x: 0.2,
                    y: 0.2,
                    width: 0.6,
                    height: 0.6
                ),
                authoredOverscanFraction: 0.15,
                viewportCrops: [baselineCrop]
            ),
            layers: layers,
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
            interactionTargets: targets,
            interactionVisualBinding: binding,
            reduceMotionComposition: ReduceMotionComposition(
                canvas: ScenePixelSize(width: 1_179, height: 2_556),
                viewportCrops: [baselineCrop],
                strata: [
                    ReduceMotionStratum(
                        id: "runtime-underlay",
                        kind: .staticPlate,
                        assetPath: "assets/runtime/\(id.rawValue)/reduced-underlay.png"
                    ),
                ] + stateOverlays + [
                    ReduceMotionStratum(
                        id: "runtime-foreground",
                        kind: .staticPlate,
                        assetPath: "assets/runtime/\(id.rawValue)/reduced-foreground.png"
                    ),
                ]
            ),
            mechanismFocus: "The changed mechanism remains visible.",
            accessibilityID: accessibilityID
        )
    }

    private static func target(
        _ id: String,
        layerID: SceneLayerID,
        column: Int,
        row: Int? = nil,
        accessibilityElementID: String? = nil
    ) -> SceneInteractionTargetBinding {
        let x = [0.28, 0.45, 0.62][column]
        let y = row.map { [0.35, 0.62][$0] } ?? 0.44
        return SceneInteractionTargetBinding(
            interactionTargetID: id,
            layerID: layerID,
            hitRegion: SceneHitRegion(
                path: [
                    NormalizedPoint(x: x, y: y),
                    NormalizedPoint(x: x + 0.1, y: y),
                    NormalizedPoint(x: x + 0.1, y: y + 0.12),
                    NormalizedPoint(x: x, y: y + 0.12),
                ]
            ),
            accessibilityElementID: accessibilityElementID ?? "\(id)-accessibility"
        )
    }

    private static func make(
        scene: SceneSpec,
        interaction: InteractionSpec,
        accessibility: AccessibilitySpec
    ) throws -> Self {
        let beat = BeatSpec(
            id: beatID,
            sceneID: scene.id,
            narrative: NarrativeText(
                heading: "The mechanism takes hold",
                paragraphs: ["The user's action leaves a durable mark in the world."]
            ),
            interaction: interaction,
            checkpoint: .afterInteraction
        )
        let arc = ArcSpec(
            id: arcID,
            title: "The authored movement",
            targetDurationMinutes: 8,
            situation: "A material constraint shapes the scene.",
            mechanism: "The user acts on that constraint.",
            turn: "The action crosses its historical threshold.",
            consequence: "The changed world remains visible.",
            handoff: "The consequence opens the next movement.",
            beats: [beat]
        )
        let chapter = ChapterSpec(
            schemaVersion: version,
            id: chapterID,
            title: "Runtime test chapter",
            period: "Test period",
            arcs: [arc],
            completionEffects: [completionEffect("runtime-chapter-complete")]
        )
        let audio = makeResponsiveAudio(interaction: interaction)
        let repository = RuntimeTestRepository(
            chapter: chapter,
            scene: scene,
            accessibility: accessibility,
            program: audio.program,
            timelines: audio.timelines
        )
        let coordinator = ChapterCoordinator(repository: repository)
        var state = JourneyState(
            installedContent: [
                InstalledContentVersion(packageID: packageID, version: version),
            ]
        )
        let reducer = JourneyReducer()
        for action in try coordinator.beginActions(chapterID: chapterID, state: state) {
            let effects = reducer.reduce(state: &state, action: action)
            guard !effects.contains(where: \.isRejection) else {
                throw RuntimeTestFixtureError.rejectedOpening
            }
        }
        let inventory = try makeInventory(scene: scene)
        return Self(
            repository: repository,
            coordinator: coordinator,
            state: state,
            inventory: inventory.inventory,
            packageRoot: inventory.root,
            interaction: interaction,
            accessibility: accessibility
        )
    }

    private static func traceScene(
        interaction: InteractionSpec,
        accessibilityID: AccessibilityID
    ) -> SceneSpec {
        let crop = baselineCrop
        let background = layer("runtime-background", variants: [])
        let route = layer("runtime-route", variants: ["idle", "tracing", "completed"])
        let layers = [background, route].enumerated().map { index, source in
            SceneLayerSpec(
                id: source.id,
                order: index,
                assetPath: source.assetPath,
                frame: source.frame,
                depth: source.depth,
                opacity: source.opacity,
                blendMode: source.blendMode,
                masks: source.masks,
                motion: source.motion,
                stateVariants: source.stateVariants
            )
        }
        return SceneSpec(
            id: "runtime-trace-scene",
            sceneCanvas: SceneCanvasSpec(
                canvas: ScenePixelSize(width: 1_179, height: 2_556),
                cameraTravelBounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                authoredOverscanFraction: 0.15,
                viewportCrops: [crop]
            ),
            layers: layers,
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
            interactionTargets: [
                SceneInteractionTargetBinding(
                    interactionTargetID: "route-control",
                    layerID: route.id,
                    hitRegion: SceneHitRegion(
                        path: [
                            NormalizedPoint(x: 0.28, y: 0.43),
                            NormalizedPoint(x: 0.72, y: 0.43),
                            NormalizedPoint(x: 0.72, y: 0.57),
                            NormalizedPoint(x: 0.28, y: 0.57),
                        ]
                    ),
                    accessibilityElementID: "route-control-accessibility"
                ),
            ],
            interactionVisualBinding: .trace(
                SceneTraceVisualBinding(
                    interactionID: interaction.id,
                    interactionTargetID: "route-control",
                    layerID: route.id,
                    idleVariantID: "idle",
                    tracingVariantID: "tracing",
                    completedVariantID: "completed"
                )
            ),
            reduceMotionComposition: ReduceMotionComposition(
                canvas: ScenePixelSize(width: 1_179, height: 2_556),
                viewportCrops: [crop],
                strata: [
                    ReduceMotionStratum(
                        id: "runtime-underlay",
                        kind: .staticPlate,
                        assetPath: "assets/runtime/reduced-underlay.png"
                    ),
                    ReduceMotionStratum(
                        id: "runtime-route-state",
                        kind: .stateOverlay,
                        layerID: route.id
                    ),
                    ReduceMotionStratum(
                        id: "runtime-foreground",
                        kind: .staticPlate,
                        assetPath: "assets/runtime/reduced-foreground.png"
                    ),
                ]
            ),
            mechanismFocus: "The route itself records the historical action.",
            accessibilityID: accessibilityID
        )
    }

    private static let baselineCrop = SceneViewportCrop(
        id: "baseline-393x852",
        viewport: SceneViewportSize(widthPoints: 393, heightPoints: 852),
        sourceRect: NormalizedRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
        safeTextRegions: [
            SceneSafeTextRegion(
                id: "runtime-copy",
                rect: NormalizedRect(x: 0.15, y: 0.12, width: 0.6, height: 0.12)
            ),
        ]
    )

    private static func layer(
        _ id: SceneLayerID,
        variants: [String]
    ) -> SceneLayerSpec {
        SceneLayerSpec(
            id: id,
            order: 0,
            assetPath: "assets/runtime/\(id.rawValue)/base.png",
            frame: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            depth: variants.isEmpty ? 0.2 : 0.6,
            motion: SceneLayerMotion(
                parallaxFactor: variants.isEmpty ? 0.05 : 0.2,
                focusResponse: variants.isEmpty ? 0 : 0.2
            ),
            stateVariants: variants.map {
                SceneLayerStateVariant(
                    id: $0,
                    assetPath: "assets/runtime/\(id.rawValue)/\($0).png"
                )
            }
        )
    }

    private static func completionEffect(_ id: WorldEffectID) -> WorldEffect {
        WorldEffect(
            id: id,
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: WorldNodeID("node-\(id.rawValue)"),
                    kind: .institution,
                    form: "A durable consequence",
                    position: NormalizedPoint(x: 0.5, y: 0.5)
                )
            )
        )
    }

    private static func makeResponsiveAudio(
        interaction: InteractionSpec
    ) -> (program: ResponsiveAudioProgramSpec, timelines: [AudioTimeline]) {
        let scope = ResponsiveAudioProgramScope(
            chapterID: chapterID,
            arcID: arcID,
            beatID: beatID,
            interactionID: interaction.id
        )
        func timeline(_ name: String) -> AudioTimeline {
            let timelineID = AudioTimelineID("runtime-audio-\(name)")
            return AudioTimeline(
                id: timelineID,
                sampleRate: 48_000,
                events: [
                    AudioEvent(
                        cueID: AudioCueID("cue-\(timelineID.rawValue)"),
                        role: .soundscape,
                        startSample: 0,
                        durationSamples: 48_000,
                        assetPath: "audio/\(timelineID.rawValue).m4a",
                        gain: 1
                    ),
                ],
                haptics: []
            )
        }
        let approach = timeline("approach")
        let waiting = timeline("waiting")
        let engaged = timeline("engaged")
        let resistance = timeline("resistance")
        let consequence = timeline("consequence")
        let program = ResponsiveAudioProgramSpec(
            id: ResponsiveAudioProgramID("runtime-audio-program"),
            scope: scope,
            approachTimelineID: approach.id,
            interactionBeds: [
                ResponsiveInteractionAudioBedSpec(
                    phase: .waiting,
                    timelineID: waiting.id,
                    layerStates: ResponsiveAudioLayerStateSelection(
                        scoreStateID: nil,
                        soundscapeStateID: "runtime-waiting"
                    )
                ),
                ResponsiveInteractionAudioBedSpec(
                    phase: .engaged,
                    timelineID: engaged.id,
                    layerStates: ResponsiveAudioLayerStateSelection(
                        scoreStateID: nil,
                        soundscapeStateID: "runtime-engaged"
                    )
                ),
                ResponsiveInteractionAudioBedSpec(
                    phase: .resistance,
                    timelineID: resistance.id,
                    layerStates: ResponsiveAudioLayerStateSelection(
                        scoreStateID: nil,
                        soundscapeStateID: "runtime-resistance"
                    )
                ),
            ],
            consequenceTimelineID: consequence.id,
            exitPolicy: .boundedFade(durationSamples: 480)
        )
        return (program, [approach, waiting, engaged, resistance, consequence])
    }

    private static func makeInventory(
        scene: SceneSpec
    ) throws -> (inventory: SceneAssetInventory, root: URL) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "chapter-runtime-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var records: [PackageFileRecord] = []
        for packagePath in referencedAssetPaths(in: scene).sorted() {
            let url = root.appending(path: packagePath, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = Data([0x01])
            try data.write(to: url, options: .atomic)
            records.append(
                PackageFileRecord(
                    path: packagePath,
                    bytes: Int64(data.count),
                    sha256: SHA256.hash(data: data)
                        .map { String(format: "%02x", $0) }
                        .joined()
                )
            )
        }
        let manifest = SignedPackageManifest(
            packageID: packageID,
            packageVersion: version,
            schemaVersion: version,
            minimumRuntime: version,
            files: records,
            manifestDigest: "test-only",
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "test-only",
                value: "test-only"
            )
        )
        let payload = ContentPackagePayload(
            schemaVersion: version,
            packageID: packageID,
            worldSeed: WorldSeedSpec(nodes: [], traces: []),
            chapters: [],
            scenes: [scene],
            audioTimelines: [],
            accessibility: []
        )
        return try (
            SceneAssetInventory(
                verifiedPackage: VerifiedContentPackage(
                    manifest: manifest,
                    payload: payload
                ),
                activatedPackageRoot: root
            ),
            root
        )
    }

    private static func referencedAssetPaths(in scene: SceneSpec) -> Set<String> {
        var result: Set<String> = []
        for layer in scene.layers {
            result.insert(layer.assetPath)
            result.formUnion(layer.masks.assetPathsForRuntimeTest)
            for variant in layer.stateVariants {
                result.insert(variant.assetPath)
                result.formUnion(variant.masks.assetPathsForRuntimeTest)
            }
        }
        for stratum in scene.reduceMotionComposition.strata {
            if let assetPath = stratum.assetPath { result.insert(assetPath) }
        }
        return result
    }
}

struct CompletedGrammarRuntimeCase {
    let name: String
    let fixture: RuntimeTestFixture
    let touchIntent: SceneTouchIntent
}

struct RuntimeTestRepository: ChapterContentRepository {
    let chapterValue: ChapterSpec
    let sceneValue: SceneSpec
    let accessibilityValue: AccessibilitySpec
    let program: ResponsiveAudioProgramSpec
    let timelines: [AudioTimeline]

    init(
        chapter: ChapterSpec,
        scene: SceneSpec,
        accessibility: AccessibilitySpec,
        program: ResponsiveAudioProgramSpec,
        timelines: [AudioTimeline]
    ) {
        chapterValue = chapter
        sceneValue = scene
        accessibilityValue = accessibility
        self.program = program
        self.timelines = timelines
    }

    func chapter(_ id: ChapterID) -> ChapterSpec? {
        id == chapterValue.id ? chapterValue : nil
    }

    func arc(_ id: ArcID) -> ArcSpec? {
        chapterValue.arcs.first { $0.id == id }
    }

    func beat(_ id: BeatID) -> BeatSpec? {
        chapterValue.arcs.flatMap(\.beats).first { $0.id == id }
    }

    func scene(_ id: SceneID) -> SceneSpec? { id == sceneValue.id ? sceneValue : nil }

    func interaction(_ id: InteractionID) -> InteractionSpec? {
        beat(RuntimeTestFixture.beatID)?.interaction.flatMap { $0.id == id ? $0 : nil }
    }

    func accessibility(_ id: AccessibilityID) -> AccessibilitySpec? {
        id == accessibilityValue.id ? accessibilityValue : nil
    }

    func packageID(for chapterID: ChapterID) -> PackageID? {
        chapterID == chapterValue.id ? RuntimeTestFixture.packageID : nil
    }

    func contentVersion(for chapterID: ChapterID) -> SchemaVersion? {
        chapterID == chapterValue.id ? RuntimeTestFixture.version : nil
    }

    func location(of arcID: ArcID) -> ArcContentLocation? {
        arcID == RuntimeTestFixture.arcID
            ? ArcContentLocation(chapterID: chapterValue.id, arcIndex: 0)
            : nil
    }

    func location(of beatID: BeatID) -> BeatContentLocation? {
        beatID == RuntimeTestFixture.beatID
            ? BeatContentLocation(
                chapterID: chapterValue.id,
                arcID: RuntimeTestFixture.arcID,
                arcIndex: 0,
                beatIndex: 0
            )
            : nil
    }

    func audioTimelineIDs(for beatID: BeatID) -> [AudioTimelineID]? {
        beatID == RuntimeTestFixture.beatID ? [] : nil
    }

    func responsiveAudioProgram(
        for interactionID: InteractionID
    ) -> ResponsiveAudioProgramSpec? {
        interactionID == program.scope.interactionID ? program : nil
    }

    func responsiveAudioTimelines(
        for interactionID: InteractionID
    ) -> [AudioTimeline]? {
        interactionID == program.scope.interactionID ? timelines : nil
    }
}

enum RuntimeTestFixtureError: Error {
    case invalidSeed
    case rejectedSeed
    case incompleteSeed
    case rejectedOpening
}

private struct HarvestSceneEnvelope: Decodable {
    struct InteractionContract: Decodable {
        let totalUnits: Int
    }

    let nativeInteractionID: String
    let interactionContract: InteractionContract
    let scene: SceneSpec
}

private extension JourneyEffect {
    var isRejection: Bool {
        if case .rejected = self { return true }
        return false
    }
}

private extension SceneLayerMaskSet {
    var assetPathsForRuntimeTest: [String] {
        [
            alphaMaskAssetPath,
            occlusionMaskAssetPath,
            depthMaskAssetPath,
            lightMaskAssetPath,
        ].compactMap { $0 }
    }
}
