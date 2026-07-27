import ContentKit
import ContentKitTestSupport
import CryptoKit
import XCTest

final class ContentKitTests: XCTestCase {
    func testManifestUsesStableFreeIDsAndValidates() throws {
        let chapters = [
            ChapterIndexEntry(
                id: "first-farmers",
                sequence: 1,
                title: "The First Farmers",
                period: "7000–3300 BC",
                packageID: "essential",
                access: .included
            ),
            ChapterIndexEntry(
                id: "europe-holds-the-line",
                sequence: 13,
                title: "The Frontiers Hold",
                period: "AD 711–1699",
                packageID: "essential",
                access: .included
            ),
            ChapterIndexEntry(
                id: "european-world",
                sequence: 21,
                title: "The European World",
                period: "AD 1802–1914",
                packageID: "essential",
                access: .included
            ),
        ]
        let manifest = CollectionManifest(
            schemaVersion: SchemaVersion(major: 1),
            collectionID: "journey-v1",
            locale: .launchEnglish,
            product: .current,
            chapters: chapters,
            packages: [
                ContentPackageSpec(
                    id: "essential",
                    version: SchemaVersion(major: 1),
                    chapterIDs: chapters.map(\.id),
                    maximumInstalledBytes: 750_000_000,
                    minimumRuntime: SchemaVersion(major: 1),
                    isEssentialInstall: true
                ),
            ],
            entitlements: []
        )

        XCTAssertNoThrow(try manifest.validate())
        XCTAssertThrowsError(try manifest.validateLaunch())
        XCTAssertEqual(Set(chapters.map(\.id)), LaunchContent.freeChapterIDs)
    }

    func testCompleteLaunchManifestMatchesGeneratedCatalogAndDeliveryPlan() throws {
        let manifest = LaunchContent.collectionManifest

        XCTAssertNoThrow(try manifest.validateLaunch())
        XCTAssertEqual(manifest.collectionID, LaunchContent.collectionID)
        XCTAssertEqual(manifest.chapters.count, 24)
        XCTAssertEqual(manifest.chapters.map(\.id), LaunchContent.chapterOrder)
        XCTAssertEqual(
            Set(manifest.chapters.filter { $0.access == .included }.map(\.id)),
            LaunchContent.freeChapterIDs
        )
        XCTAssertEqual(manifest.packages.map(\.id), LaunchContent.packageIDsInDeliveryOrder)
        XCTAssertEqual(
            manifest.packages.reduce(Int64(0)) { $0 + $1.maximumInstalledBytes },
            LaunchContent.maximumInstalledContentBytes
        )
        XCTAssertEqual(manifest.chapters.first?.title.launchEnglish, "The First Farmers")
        XCTAssertEqual(manifest.chapters.last?.title.launchEnglish, "Europe Returns")
        XCTAssertEqual(manifest.chapters.last?.period.launchEnglish, "AD 1989–20 July 2026")
        XCTAssertEqual(
            manifest.entitlements,
            [
                EntitlementSpec(
                    id: LaunchContent.fullWorkEntitlementID,
                    storeProductID: LaunchContent.fullWorkStoreProductID,
                    kind: .nonConsumable
                ),
            ]
        )

        let packagesWithoutShellReservation = try LaunchContent.packageIDsInDeliveryOrder.map { packageID in
            ContentPackageSpec(
                id: packageID,
                version: SchemaVersion(major: 1),
                chapterIDs: Array(try XCTUnwrap(LaunchContent.packageChapterIDs[packageID])),
                maximumInstalledBytes: try XCTUnwrap(
                    LaunchContent.packageMaximumInstalledBytes[packageID]
                ),
                minimumRuntime: SchemaVersion(major: 1),
                isEssentialInstall: packageID == LaunchContent.essentialPackageID
            )
        }
        let oversizedManifest = CollectionManifest(
            schemaVersion: manifest.schemaVersion,
            collectionID: manifest.collectionID,
            locale: manifest.locale,
            product: manifest.product,
            chapters: manifest.chapters,
            packages: packagesWithoutShellReservation,
            entitlements: manifest.entitlements
        )
        XCTAssertThrowsError(try oversizedManifest.validateLaunch())
    }

    func testShippingChapterSchemaContainsNoResearchApparatus() throws {
        let interactionEffect = worldEffect(id: "interaction-effect", nodeID: "interaction-node")
        let interaction = InteractionSpec(
            id: "route",
            prompt: "Follow the route",
            grammar: .trace(
                TraceInteractionSpec(
                    anchors: [
                        NormalizedPoint(x: 0, y: 0),
                        NormalizedPoint(x: 1, y: 1),
                    ],
                    tolerance: 0.1
                )
            ),
            completionEffects: [interactionEffect],
            accessibilityID: "route-accessibility"
        )
        let chapter = ChapterSpec(
            schemaVersion: SchemaVersion(major: 1),
            id: "chapter",
            title: "Chapter",
            period: "Period",
            arcs: [
                ArcSpec(
                    id: "arc",
                    title: "Arc",
                    targetDurationMinutes: 9,
                    situation: "A household reaches the river.",
                    mechanism: "Stored seed carries the farming system forward.",
                    turn: "The reserve cannot be consumed twice.",
                    consequence: "The household binds survival to the next season.",
                    handoff: "The settlement begins to outlive its builders.",
                    beats: [
                        BeatSpec(
                            id: "beat",
                            sceneID: "scene",
                            narrative: NarrativeText(
                                heading: "Heading",
                                paragraphs: ["A concrete causal sentence."]
                            ),
                            interaction: interaction,
                            checkpoint: .afterInteraction
                        ),
                    ]
                ),
            ],
            completionEffects: [worldEffect(id: "chapter-effect", nodeID: "chapter-node")]
        )

        try chapter.validate()
        let beatCompletedChapter = ChapterSpec(
            schemaVersion: chapter.schemaVersion,
            id: chapter.id,
            title: chapter.title,
            period: chapter.period,
            arcs: chapter.arcs,
            completionEffects: []
        )
        XCTAssertNoThrow(try beatCompletedChapter.validate())

        let effectlessChapter = ChapterSpec(
            schemaVersion: SchemaVersion(major: 1),
            id: "effectless-chapter",
            title: "Effectless Chapter",
            period: "Period",
            arcs: [
                ArcSpec(
                    id: "effectless-arc",
                    title: "Arc",
                    targetDurationMinutes: 9,
                    situation: "A household reaches the river.",
                    mechanism: "The river carries the household.",
                    turn: "The crossing ends.",
                    consequence: "Nothing durable is authored.",
                    handoff: "The journey pauses.",
                    beats: [
                        BeatSpec(
                            id: "effectless-beat",
                            sceneID: "effectless-scene",
                            narrative: NarrativeText(
                                heading: "Heading",
                                paragraphs: ["A concrete sentence."]
                            ),
                            checkpoint: .onExit
                        ),
                    ]
                ),
            ],
            completionEffects: []
        )
        XCTAssertThrowsError(try effectlessChapter.validate())
        let json = String(data: try JSONEncoder().encode(chapter), encoding: .utf8)!.lowercased()
        for forbidden in ["historiography", "counterargument", "confidence", "methodology", "evidencepanel"] {
            XCTAssertFalse(json.contains(forbidden))
        }
    }

    func testSceneRejectsRemoteAssets() {
        let scene = canonicalScene(layerAssetPath: "https://example.com/image.jpg")
        XCTAssertThrowsError(try scene.validate())
    }

    func testProductionSceneContractValidates() {
        XCTAssertNoThrow(try canonicalScene().validate())
    }

    func testSceneRequiresPortraitCanvasBaselineCropAndAuthoredOverscan() {
        XCTAssertThrowsError(
            try canonicalScene(
                canvas: ScenePixelSize(width: 2600, height: 1200)
            ).validate()
        )
        XCTAssertThrowsError(try canonicalScene(authoredOverscanFraction: 0.149).validate())
        XCTAssertThrowsError(
            try canonicalScene(
                cameraTravelBounds: NormalizedRect(x: 0.01, y: 0.2, width: 0.6, height: 0.6)
            ).validate()
        )
        XCTAssertThrowsError(
            try canonicalScene(viewportCrops: [baselineCrop(id: "compact-393x852")]).validate()
        )
    }

    func testSceneRejectsInvalidRectsCropAspectAndLayerValues() {
        XCTAssertThrowsError(
            try canonicalScene(
                layerFrame: NormalizedRect(x: 0.8, y: 0, width: 0.3, height: 1)
            ).validate()
        )
        XCTAssertThrowsError(try canonicalScene(layerOrder: 1).validate())
        XCTAssertThrowsError(
            try canonicalScene(
                layerMotion: SceneLayerMotion(
                    parallaxFactor: .infinity,
                    windResponse: 0.2,
                    focusResponse: 0.1
                )
            ).validate()
        )

        let wrongAspect = SceneViewportCrop(
            id: "baseline-393x852",
            viewport: SceneViewportSize(widthPoints: 393, heightPoints: 852),
            sourceRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
            safeTextRegions: [
                SceneSafeTextRegion(
                    id: "opening-copy",
                    rect: NormalizedRect(x: 0.08, y: 0.06, width: 0.84, height: 0.22)
                ),
            ]
        )
        XCTAssertThrowsError(try canonicalScene(viewportCrops: [wrongAspect]).validate())

        let escapedSafeText = SceneViewportCrop(
            id: "baseline-393x852",
            viewport: SceneViewportSize(widthPoints: 393, heightPoints: 852),
            sourceRect: NormalizedRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9),
            safeTextRegions: [
                SceneSafeTextRegion(
                    id: "opening-copy",
                    rect: NormalizedRect(x: 0.9, y: 0.1, width: 0.2, height: 0.2)
                ),
            ]
        )
        XCTAssertThrowsError(try canonicalScene(viewportCrops: [escapedSafeText]).validate())
    }

    func testSceneRejectsDuplicateCameraProgressAndInvalidAtmosphere() {
        let duplicateProgress = [
            CameraKeyframe(progress: 0, center: NormalizedPoint(x: 0.5, y: 0.5), scale: 1),
            CameraKeyframe(progress: 0.5, center: NormalizedPoint(x: 0.52, y: 0.48), scale: 1),
            CameraKeyframe(progress: 0.5, center: NormalizedPoint(x: 0.54, y: 0.46), scale: 1.05),
            CameraKeyframe(progress: 1, center: NormalizedPoint(x: 0.6, y: 0.4), scale: 1.1),
        ]
        XCTAssertThrowsError(try canonicalScene(keyframes: duplicateProgress).validate())

        XCTAssertThrowsError(
            try canonicalScene(atmosphere: [
                AtmosphereSpec(
                    kind: .mist,
                    density: .nan,
                    velocity: SignedUnitVector(dx: -0.1, dy: 0),
                    deterministicSeed: 42
                ),
            ]).validate()
        )
        XCTAssertThrowsError(
            try canonicalScene(atmosphere: [
                AtmosphereSpec(
                    kind: .mist,
                    density: 0.2,
                    velocity: SignedUnitVector(dx: 0.9, dy: 0.9),
                    deterministicSeed: 42
                ),
            ]).validate()
        )
        XCTAssertThrowsError(
            try canonicalScene(atmosphere: [
                AtmosphereSpec(
                    kind: .mist,
                    density: 0.2,
                    velocity: SignedUnitVector(dx: -0.1, dy: 0),
                    deterministicSeed: 4_294_967_296
                ),
            ]).validate()
        )
    }

    func testSceneHitTargetsRemainVisibleAndFortyFourPointsInEveryCrop() {
        let tinyTarget = SceneInteractionTargetBinding(
            interactionTargetID: "route-control",
            layerID: "water",
            hitRegion: SceneHitRegion(
                path: [
                    NormalizedPoint(x: 0.25, y: 0.65),
                    NormalizedPoint(x: 0.27, y: 0.65),
                    NormalizedPoint(x: 0.26, y: 0.67),
                ]
            ),
            accessibilityElementID: "route-control"
        )
        XCTAssertThrowsError(try canonicalScene(interactionTargets: [tinyTarget]).validate())

        let clippedCrop = SceneViewportCrop(
            id: "baseline-393x852",
            viewport: SceneViewportSize(widthPoints: 393, heightPoints: 852),
            sourceRect: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
            safeTextRegions: [
                SceneSafeTextRegion(
                    id: "opening-copy",
                    rect: NormalizedRect(x: 0.08, y: 0.06, width: 0.84, height: 0.22)
                ),
            ]
        )
        XCTAssertThrowsError(
            try canonicalScene(
                viewportCrops: [clippedCrop],
                reduceViewportCrops: [clippedCrop]
            ).validate()
        )

        let compactCrop = SceneViewportCrop(
            id: "compact-390x845",
            viewport: SceneViewportSize(widthPoints: 390, heightPoints: 845),
            sourceRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            safeTextRegions: [
                SceneSafeTextRegion(
                    id: "opening-copy",
                    rect: NormalizedRect(x: 0.08, y: 0.06, width: 0.84, height: 0.22)
                ),
            ]
        )
        XCTAssertThrowsError(
            try canonicalScene(viewportCrops: [baselineCrop(), compactCrop]).validate()
        )
    }

    func testSceneRejectsUnsafeNestedAssetsAndReusedReduceMotionLayer() {
        XCTAssertThrowsError(
            try canonicalScene(
                layerMasks: SceneLayerMaskSet(depthMaskAssetPath: "../depth.png")
            ).validate()
        )
        XCTAssertThrowsError(
            try canonicalScene(stateVariants: [
                SceneLayerStateVariant(
                    id: "arrival",
                    assetPath: "https://example.com/arrival.heif"
                ),
            ]).validate()
        )
        XCTAssertThrowsError(
            try canonicalScene(
                layerAssetPath: "assets/shared.heif",
                reduceAssetPath: "assets/shared.heif"
            ).validate()
        )
    }

    func testAllocateVisualBindingValidatesAgainstTheExactInteraction() throws {
        let scene = canonicalAllocateScene()
        let interaction = canonicalAllocateInteraction()

        XCTAssertNoThrow(try scene.validate())
        XCTAssertNoThrow(try interaction.validate())
        XCTAssertNoThrow(try scene.validateInteractionVisualBinding(to: interaction))
    }

    func testAllocateVisualBindingRejectsWrongInteractionAndDestinationSet() {
        let interaction = canonicalAllocateInteraction()
        let wrongInteraction = canonicalAllocateScene(interactionID: "allocate-another-store")
        XCTAssertNoThrow(try wrongInteraction.validate())
        XCTAssertThrowsError(
            try wrongInteraction.validateInteractionVisualBinding(to: interaction)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("must bind the exact interaction"))
        }

        let destinations = canonicalAllocateDestinations()
        let missingDestination = canonicalAllocateScene(
            bindingDestinations: [destinations[0]]
        )
        XCTAssertNoThrow(try missingDestination.validate())
        XCTAssertThrowsError(
            try missingDestination.validateInteractionVisualBinding(to: interaction)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("must bind the exact interaction"))
        }

        let interactionWithDifferentDestination = canonicalAllocateInteraction(
            destinations: [
                AllocationDestination(id: "seed", minimumUnits: 1),
                AllocationDestination(id: "reserve", minimumUnits: 1),
            ]
        )
        let extraDestination = canonicalAllocateScene()
        XCTAssertNoThrow(try extraDestination.validate())
        XCTAssertThrowsError(
            try extraDestination.validateInteractionVisualBinding(to: interactionWithDifferentDestination)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("must bind the exact interaction"))
        }
    }

    func testAllocateVisualBindingRejectsResourceThresholdThatDoesNotEndAtTotal() {
        let scene = canonicalAllocateScene(
            resourceThresholds: [
                SceneRemainingUnitsVariant(maximumRemainingUnits: 0, variantID: "exhausted"),
                SceneRemainingUnitsVariant(maximumRemainingUnits: 3, variantID: "full"),
            ]
        )

        XCTAssertNoThrow(try scene.validate())
        XCTAssertThrowsError(
            try scene.validateInteractionVisualBinding(to: canonicalAllocateInteraction())
        ) { error in
            XCTAssertTrue(String(describing: error).contains("finite resource total"))
        }
    }

    func testAllocateVisualBindingRejectsUnknownDestinationVariantAndTarget() {
        let destinations = canonicalAllocateDestinations()
        let seed = destinations[0]
        let unknownVariant = SceneAllocationDestinationVisualBinding(
            destinationID: seed.destinationID,
            interactionTargetID: seed.interactionTargetID,
            layerID: seed.layerID,
            emptyVariantID: seed.emptyVariantID,
            receivingVariantID: seed.receivingVariantID,
            completedVariantID: "unknown-state",
            transferPath: seed.transferPath
        )
        XCTAssertThrowsError(
            try canonicalAllocateScene(
                bindingDestinations: [unknownVariant, destinations[1]]
            ).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("three distinct variants"))
        }

        let unknownTarget = SceneAllocationDestinationVisualBinding(
            destinationID: seed.destinationID,
            interactionTargetID: "unknown-target",
            layerID: seed.layerID,
            emptyVariantID: seed.emptyVariantID,
            receivingVariantID: seed.receivingVariantID,
            completedVariantID: seed.completedVariantID,
            transferPath: seed.transferPath
        )
        XCTAssertThrowsError(
            try canonicalAllocateScene(
                bindingDestinations: [unknownTarget, destinations[1]]
            ).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("requires a real target"))
        }
    }

    func testReduceMotionStrataCannotOmitAStatefulLayer() {
        XCTAssertThrowsError(
            try canonicalAllocateScene(
                stateOverlayLayerIDs: ["harvest", "seed-store"]
            ).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("every and only stateful layer"))
        }
    }

    func testSceneRejectsTargetOverlapAndCameraSourceEscape() {
        let targets = canonicalAllocateTargets()
        let overlappingWinter = SceneInteractionTargetBinding(
            interactionTargetID: targets[1].interactionTargetID,
            layerID: targets[1].layerID,
            hitRegion: targets[0].hitRegion,
            accessibilityElementID: targets[1].accessibilityElementID
        )
        XCTAssertThrowsError(
            try canonicalAllocateScene(
                interactionTargets: [targets[0], overlappingWinter]
            ).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("overlap"))
        }

        let escapingRail = [
            CameraKeyframe(
                progress: 0,
                center: NormalizedPoint(x: 0.2, y: 0.2),
                scale: 1
            ),
            CameraKeyframe(
                progress: 1,
                center: NormalizedPoint(x: 0.5, y: 0.5),
                scale: 1
            ),
        ]
        XCTAssertThrowsError(try canonicalScene(keyframes: escapingRail).validate()) { error in
            XCTAssertTrue(String(describing: error).contains("active camera source"))
        }
    }

    func testSceneRejectsTargetThatClipsBetweenCameraAnchors() {
        let midpointClippedTarget = SceneInteractionTargetBinding(
            interactionTargetID: "midpoint-target",
            layerID: "water",
            hitRegion: SceneHitRegion(
                path: [
                    NormalizedPoint(x: 0.55, y: 0.47),
                    NormalizedPoint(x: 2.0 / 3.0, y: 0.47),
                    NormalizedPoint(x: 2.0 / 3.0, y: 0.53),
                    NormalizedPoint(x: 0.55, y: 0.53),
                ]
            ),
            accessibilityElementID: "midpoint-target"
        )
        let rail = [
            CameraKeyframe(
                progress: 0,
                center: NormalizedPoint(x: 0.4, y: 0.5),
                scale: 1.5
            ),
            CameraKeyframe(
                progress: 1,
                center: NormalizedPoint(x: 17.0 / 30.0, y: 0.5),
                scale: 4
            ),
        ]

        XCTAssertThrowsError(
            try canonicalScene(
                keyframes: rail,
                interactionTargets: [midpointClippedTarget]
            ).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("complete camera rail"))
        }
    }

    func testSceneRejectsTargetsThatCrossBetweenCameraAnchors() {
        let leftLayer = canonicalLayer(
            id: "left-target-layer",
            order: 0,
            parallaxFactor: 1
        )
        let rightLayer = canonicalLayer(
            id: "right-target-layer",
            order: 1,
            parallaxFactor: -1
        )
        let targets = [
            rectangularTarget(
                id: "left-target",
                layerID: leftLayer.id,
                minimumX: 0.33,
                maximumX: 0.45
            ),
            rectangularTarget(
                id: "right-target",
                layerID: rightLayer.id,
                minimumX: 0.49,
                maximumX: 0.61
            ),
        ]
        let rail = [
            CameraKeyframe(
                progress: 0,
                center: NormalizedPoint(x: 0.425, y: 0.5),
                scale: 1.2
            ),
            CameraKeyframe(
                progress: 1,
                center: NormalizedPoint(x: 0.575, y: 0.5),
                scale: 1.2
            ),
        ]

        XCTAssertThrowsError(
            try canonicalScene(
                keyframes: rail,
                interactionTargets: targets,
                sceneLayers: [leftLayer, rightLayer]
            ).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("overlap"))
        }
    }

    func testSceneRejectsTargetOutsideItsBoundLayer() {
        let boundedLayer = canonicalLayer(
            id: "bounded-layer",
            order: 0,
            frame: NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.6)
        )
        let escapedTarget = rectangularTarget(
            id: "escaped-target",
            layerID: boundedLayer.id,
            minimumX: 0.45,
            maximumX: 0.57
        )

        XCTAssertThrowsError(
            try canonicalScene(
                interactionTargets: [escapedTarget],
                sceneLayers: [boundedLayer]
            ).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("inside its fixed bound layer"))
        }
    }

    func testAllocateRejectsResourceDestinationOverlapAlongRail() {
        let seedTarget = canonicalAllocateTarget(
            id: "seed-target",
            layerID: "seed-store",
            accessibilityElementID: "allocate-seed",
            minimumX: 0.39,
            maximumX: 0.51
        )
        let winterTarget = canonicalAllocateTargets()[1]
        let destinations = canonicalAllocateDestinations()
        let seed = destinations[0]
        let overlappingSeed = SceneAllocationDestinationVisualBinding(
            destinationID: seed.destinationID,
            interactionTargetID: seed.interactionTargetID,
            layerID: seed.layerID,
            emptyVariantID: seed.emptyVariantID,
            receivingVariantID: seed.receivingVariantID,
            completedVariantID: seed.completedVariantID,
            transferPath: [
                NormalizedPoint(x: 0.5, y: 0.78),
                NormalizedPoint(x: 0.45, y: 0.7),
            ]
        )

        XCTAssertThrowsError(
            try canonicalAllocateScene(
                bindingDestinations: [overlappingSeed, destinations[1]],
                interactionTargets: [seedTarget, winterTarget]
            ).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("overlap"))
        }
    }

    func testAllocateRejectsDegenerateAndInvisibleTransferControlPoints() {
        let destinations = canonicalAllocateDestinations()
        let seed = destinations[0]
        let duplicateControlPoint = SceneAllocationDestinationVisualBinding(
            destinationID: seed.destinationID,
            interactionTargetID: seed.interactionTargetID,
            layerID: seed.layerID,
            emptyVariantID: seed.emptyVariantID,
            receivingVariantID: seed.receivingVariantID,
            completedVariantID: seed.completedVariantID,
            transferPath: [
                NormalizedPoint(x: 0.5, y: 0.78),
                NormalizedPoint(x: 0.5, y: 0.78),
                NormalizedPoint(x: 0.32, y: 0.62),
            ]
        )
        XCTAssertThrowsError(
            try canonicalAllocateScene(
                bindingDestinations: [duplicateControlPoint, destinations[1]]
            ).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("non-degenerate path"))
        }

        let clippedControlPoint = SceneAllocationDestinationVisualBinding(
            destinationID: seed.destinationID,
            interactionTargetID: seed.interactionTargetID,
            layerID: seed.layerID,
            emptyVariantID: seed.emptyVariantID,
            receivingVariantID: seed.receivingVariantID,
            completedVariantID: seed.completedVariantID,
            transferPath: [
                NormalizedPoint(x: 0.5, y: 0.78),
                NormalizedPoint(x: 0.05, y: 0.7),
                NormalizedPoint(x: 0.32, y: 0.62),
            ]
        )
        XCTAssertThrowsError(
            try canonicalAllocateScene(
                bindingDestinations: [clippedControlPoint, destinations[1]]
            ).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("transfer control point"))
        }
    }

    func testAllocateRejectsWindDrivenTransferGeometry() {
        let layers = [
            canonicalLayer(id: "harvest", order: 0, variants: ["exhausted", "full"]),
            canonicalLayer(id: "grain-transfer", order: 1, windResponse: 0.1),
            canonicalLayer(
                id: "seed-store",
                order: 2,
                variants: ["empty", "receiving", "committed"]
            ),
            canonicalLayer(
                id: "winter-store",
                order: 3,
                variants: ["empty", "receiving", "provisioned"]
            ),
        ]

        XCTAssertThrowsError(
            try canonicalAllocateScene(sceneLayers: layers).validate()
        ) { error in
            XCTAssertTrue(String(describing: error).contains("fixed alpha-bound source"))
        }
    }

    func testPackageRequiresInteractiveSceneTargetAndMatchingAccessibilityPath() {
        let noTargetPackage = replacingCanonicalPackage(
            scenes: [canonicalScene(interactionTargets: [])]
        )
        XCTAssertThrowsError(try noTargetPackage.validate())

        let base = canonicalPackage()
        let alternateSpec = AccessibilitySpec(
            id: "alternate-accessibility",
            sceneSummary: base.accessibility[0].sceneSummary,
            elements: base.accessibility[0].elements
        )
        let mismatchedPackage = replacingCanonicalPackage(
            scenes: [canonicalScene(accessibilityID: alternateSpec.id)],
            accessibility: base.accessibility + [alternateSpec]
        )
        XCTAssertThrowsError(try mismatchedPackage.validate())

        let descriptiveElement = AccessibilityElementSpec(
            id: "route-description",
            role: .mechanism,
            label: "The crossing route"
        )
        let specWithDescription = AccessibilitySpec(
            id: base.accessibility[0].id,
            sceneSummary: base.accessibility[0].sceneSummary,
            elements: base.accessibility[0].elements + [descriptiveElement]
        )
        let descriptiveTarget = SceneInteractionTargetBinding(
            interactionTargetID: "route-control",
            layerID: "water",
            hitRegion: SceneHitRegion(
                path: [
                    NormalizedPoint(x: 0.25, y: 0.65),
                    NormalizedPoint(x: 0.75, y: 0.55),
                    NormalizedPoint(x: 0.65, y: 0.82),
                ]
            ),
            accessibilityElementID: descriptiveElement.id
        )
        let descriptiveTargetPackage = replacingCanonicalPackage(
            scenes: [canonicalScene(interactionTargets: [descriptiveTarget])],
            accessibility: [specWithDescription]
        )
        XCTAssertThrowsError(try descriptiveTargetPackage.validate())
    }

    func testShippingAllocateRequiresAnExactRuntimeVisualBinding() throws {
        let boundPackage = canonicalPackage()
        XCTAssertNoThrow(try boundPackage.validate())

        let boundScene = try XCTUnwrap(boundPackage.scenes.first)
        let unboundScene = SceneSpec(
            id: boundScene.id,
            sceneCanvas: boundScene.sceneCanvas,
            layers: boundScene.layers,
            cameraRail: boundScene.cameraRail,
            atmosphere: boundScene.atmosphere,
            interactionTargets: boundScene.interactionTargets,
            reduceMotionComposition: boundScene.reduceMotionComposition,
            mechanismFocus: boundScene.mechanismFocus,
            accessibilityID: boundScene.accessibilityID
        )
        let unboundPackage = replacingCanonicalPackage(scenes: [unboundScene])
        XCTAssertThrowsError(try unboundPackage.validate()) { error in
            XCTAssertTrue(
                String(describing: error).contains(
                    "interactive shipping beat requires an authored visual binding"
                )
            )
        }

        // The laboratory may prepare a SceneSpec before it enters a shipping payload.
        XCTAssertNoThrow(try unboundScene.validate())
    }

    func testShippingEveryGrammarRequiresItsExactRuntimeVisualBinding() {
        let grammars: [InteractionSpec.Grammar] = [
            .trace(
                TraceInteractionSpec(
                    anchors: [
                        NormalizedPoint(x: 0.1, y: 0.8),
                        NormalizedPoint(x: 0.8, y: 0.2),
                    ],
                    tolerance: 0.1
                )
            ),
            .assemble(
                AssembleInteractionSpec(
                    components: [AssemblyComponent(id: "post", targetSlot: "frame")]
                )
            ),
            .pressure(
                PressureInteractionSpec(
                    forces: [
                        PressureForce(
                            id: "defence",
                            direction: 1,
                            initialMagnitude: 0,
                            userControllable: true
                        ),
                    ],
                    stableRange: 0.25 ... 0.75,
                    requiredHoldMillis: 500
                )
            ),
            .transform(
                TransformInteractionSpec(
                    stages: [
                        TransformationStage(
                            id: "clear-ground",
                            controlID: "field-edge",
                            requiredAmount: 0.5
                        ),
                    ]
                )
            ),
        ]

        for grammar in grammars {
            XCTAssertThrowsError(
                try replacingCanonicalPackage(interactionGrammar: grammar).validate()
            ) { error in
                XCTAssertTrue(
                    String(describing: error).contains(
                        "grammar must match the bound interaction"
                    )
                )
            }
        }
    }

    func testDocumentaryBeatCanOwnAWorldEffectWithoutTurningItIntoPlay() throws {
        let effect = worldEffect(id: "documentary-effect", nodeID: "documentary-node")
        let documentaryBeat = BeatSpec(
            id: "documentary-beat",
            sceneID: "documentary-scene",
            narrative: NarrativeText(
                heading: "The record remains",
                paragraphs: ["The consequence enters the world without player control."]
            ),
            completionEffects: [effect],
            checkpoint: .onExit
        )
        XCTAssertNoThrow(try documentaryBeat.validate())

        let interactiveBeat = BeatSpec(
            id: "interactive-beat",
            sceneID: "interactive-scene",
            narrative: documentaryBeat.narrative,
            interaction: try XCTUnwrap(canonicalPackage().chapters[0].arcs[0].beats[0].interaction),
            completionEffects: [effect],
            checkpoint: .afterInteraction
        )
        XCTAssertThrowsError(try interactiveBeat.validate())
    }

    func testInteractionRequiresPermanentConsequences() {
        let interaction = InteractionSpec(
            id: "route",
            prompt: "Follow the route",
            grammar: .trace(
                TraceInteractionSpec(
                    anchors: [NormalizedPoint(x: 0, y: 0), NormalizedPoint(x: 1, y: 1)],
                    tolerance: 0.1
                )
            ),
            completionEffects: [],
            accessibilityID: "route-accessibility"
        )
        XCTAssertThrowsError(try interaction.validate())
    }

    func testTraceAnchorLimitBoundsDeferredTransportMemory() throws {
        func interaction(anchorCount: Int) -> InteractionSpec {
            InteractionSpec(
                id: InteractionID(rawValue: "bounded-trace-\(anchorCount)"),
                prompt: "Carry the route",
                grammar: .trace(
                    TraceInteractionSpec(
                        anchors: (0 ..< anchorCount).map { index in
                            NormalizedPoint(
                                x: Double(index % 8) / 7,
                                y: Double(index / 8) / 8
                            )
                        },
                        tolerance: 0.05
                    )
                ),
                completionEffects: [
                    worldEffect(
                        id: WorldEffectID(
                            rawValue: "bounded-trace-effect-\(anchorCount)"
                        ),
                        nodeID: WorldNodeID(
                            rawValue: "bounded-trace-node-\(anchorCount)"
                        )
                    ),
                ],
                accessibilityID: AccessibilityID(
                    rawValue: "bounded-trace-accessibility-\(anchorCount)"
                )
            )
        }

        XCTAssertEqual(TraceInteractionSpec.maximumAnchorCount, 64)
        XCTAssertNoThrow(
            try interaction(
                anchorCount: TraceInteractionSpec.maximumAnchorCount
            ).validate()
        )
        XCTAssertThrowsError(
            try interaction(
                anchorCount: TraceInteractionSpec.maximumAnchorCount + 1
            ).validate()
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains(
                    "requires 2–64 unit-space anchors"
                )
            )
        }
    }

    func testAssemblyRejectsCyclicPrerequisites() {
        let interaction = InteractionSpec(
            id: "cyclic-order",
            prompt: "Build the order",
            grammar: .assemble(
                AssembleInteractionSpec(
                    components: [
                        AssemblyComponent(id: "charter", targetSlot: "law", prerequisites: ["council"]),
                        AssemblyComponent(id: "council", targetSlot: "office", prerequisites: ["charter"]),
                    ]
                )
            ),
            completionEffects: [worldEffect(id: "order-effect", nodeID: "order-node")],
            accessibilityID: "order-accessibility"
        )
        XCTAssertThrowsError(try interaction.validate())
    }

    func testPressureRejectsAnUnreachableStableRange() {
        let interaction = InteractionSpec(
            id: "unreachable-front",
            prompt: "Hold the front",
            grammar: .pressure(
                PressureInteractionSpec(
                    forces: [
                        PressureForce(
                            id: "assault",
                            direction: -2,
                            initialMagnitude: 1,
                            userControllable: false
                        ),
                        PressureForce(
                            id: "defence",
                            direction: 1,
                            initialMagnitude: 0,
                            userControllable: true
                        ),
                    ],
                    stableRange: 0 ... 0.1,
                    requiredHoldMillis: 500
                )
            ),
            completionEffects: [worldEffect(id: "front-effect", nodeID: "front-node")],
            accessibilityID: "front-accessibility"
        )
        XCTAssertThrowsError(try interaction.validate())
    }

    func testCanonicalPackageRoundTripsThroughTheRuntimeDecoder() throws {
        let payload = canonicalPackage()
        let encoded = try ContentDocumentDecoder.encodePackage(payload)
        let decoded = try ContentDocumentDecoder.decodePackage(encoded)
        XCTAssertEqual(decoded, payload)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(json.contains("\"grammar\":\"allocate\""))
        XCTAssertTrue(json.contains("\"mutation\":\"reveal-node\""))
    }

    func testSignedPackageVerifiesAgainstCompilerWireContract() throws {
        let packageRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        let payload = canonicalPackage()
        let payloadData = try ContentDocumentDecoder.encodePackage(payload)
        let expectedPackage = ContentPackageSpec(
            id: payload.packageID,
            version: SchemaVersion(major: 1),
            chapterIDs: payload.chapters.map(\.id),
            maximumInstalledBytes: 10_000_000,
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: true
        )
        let payloadPath = "content/payload.json"
        let payloadURL = packageRoot.appending(path: payloadPath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payloadData.write(to: payloadURL)

        let privateKey = P256.Signing.PrivateKey()
        let unsigned = SignedPackageManifest(
            packageID: payload.packageID,
            packageVersion: SchemaVersion(major: 1),
            schemaVersion: payload.schemaVersion,
            minimumRuntime: SchemaVersion(major: 1),
            files: [
                PackageFileRecord(
                    path: payloadPath,
                    bytes: Int64(payloadData.count),
                    sha256: sha256(payloadData)
                ),
            ],
            manifestDigest: String(repeating: "0", count: 64),
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "launch-signing-key",
                value: "AA=="
            )
        )
        let digest = try ContentPackageVerifier.manifestDigest(for: unsigned)
        let signature = try privateKey.signature(for: Data(digest.utf8))
        let manifest = SignedPackageManifest(
            packageID: unsigned.packageID,
            packageVersion: unsigned.packageVersion,
            schemaVersion: unsigned.schemaVersion,
            minimumRuntime: unsigned.minimumRuntime,
            files: unsigned.files,
            manifestDigest: digest,
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "launch-signing-key",
                value: signature.derRepresentation.base64EncodedString()
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(
            to: packageRoot.appending(path: ContentPackageVerifier.manifestFileName)
        )

        let verified = try ContentPackageVerifier.verifyPackage(
            at: packageRoot,
            expectedPackage: expectedPackage,
            trustedPublicKeys: [
                "launch-signing-key": privateKey.publicKey.x963Representation,
            ],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1)
        )
        XCTAssertEqual(verified.payload, payload)
        XCTAssertEqual(verified.manifest.packageID, payload.packageID)
        XCTAssertEqual(verified.verificationScope, .completePackage)

        let driftedVersion = ContentPackageSpec(
            id: expectedPackage.id,
            version: SchemaVersion(major: 2),
            chapterIDs: expectedPackage.chapterIDs,
            maximumInstalledBytes: expectedPackage.maximumInstalledBytes,
            minimumRuntime: expectedPackage.minimumRuntime,
            isEssentialInstall: expectedPackage.isEssentialInstall
        )
        XCTAssertThrowsError(
            try ContentPackageVerifier.verifyPackage(
                at: packageRoot,
                expectedPackage: driftedVersion,
                trustedPublicKeys: [
                    "launch-signing-key": privateKey.publicKey.x963Representation,
                ],
                supportedSchema: SchemaVersion(major: 1),
                runtimeVersion: SchemaVersion(major: 1)
            )
        ) { error in
            guard case PackageVerificationError.packageSpecMismatch = error else {
                return XCTFail("Expected trusted-spec mismatch, found \(error)")
            }
        }

        let undersizedBudget = ContentPackageSpec(
            id: expectedPackage.id,
            version: expectedPackage.version,
            chapterIDs: expectedPackage.chapterIDs,
            maximumInstalledBytes: 1,
            minimumRuntime: expectedPackage.minimumRuntime,
            isEssentialInstall: expectedPackage.isEssentialInstall
        )
        XCTAssertThrowsError(
            try ContentPackageVerifier.verifyPackage(
                at: packageRoot,
                expectedPackage: undersizedBudget,
                trustedPublicKeys: [
                    "launch-signing-key": privateKey.publicKey.x963Representation,
                ],
                supportedSchema: SchemaVersion(major: 1),
                runtimeVersion: SchemaVersion(major: 1)
            )
        ) { error in
            guard case PackageVerificationError.installedByteBudgetExceeded = error else {
                return XCTFail("Expected installed-byte budget failure, found \(error)")
            }
        }

        var tamperedPayload = payloadData
        tamperedPayload.append(Data("tampered".utf8))
        try tamperedPayload.write(to: payloadURL)
        XCTAssertThrowsError(
            try ContentPackageVerifier.verifyPackage(
                at: packageRoot,
                expectedPackage: expectedPackage,
                trustedPublicKeys: [
                    "launch-signing-key": privateKey.publicKey.x963Representation,
                ],
                supportedSchema: SchemaVersion(major: 1),
                runtimeVersion: SchemaVersion(major: 1)
            )
        ) { error in
            guard case PackageVerificationError.fileSizeMismatch(payloadPath) = error else {
                return XCTFail("Expected file-size failure, found \(error)")
            }
        }
    }

    func testRuntimeAdmissionDefersLargeAssetDigestButFullActivationDoesNot() throws {
        let fixture = try makeRuntimeAdmissionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var tampered = try Data(contentsOf: fixture.largeAssetURL)
        tampered[tampered.startIndex] ^= 0xFF
        try tampered.write(to: fixture.largeAssetURL, options: .atomic)

        let admitted = try ContentPackageVerifier.admitPackageAtRuntime(
            at: fixture.root,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: [fixture.keyID: fixture.publicKey],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1)
        )
        XCTAssertEqual(admitted.verificationScope, .runtimeAdmission)
        XCTAssertEqual(admitted.payload.packageID, fixture.expectedPackage.id)

        XCTAssertThrowsError(
            try ContentPackageVerifier.verifyPackage(
                at: fixture.root,
                expectedPackage: fixture.expectedPackage,
                trustedPublicKeys: [fixture.keyID: fixture.publicKey],
                supportedSchema: SchemaVersion(major: 1),
                runtimeVersion: SchemaVersion(major: 1)
            )
        ) { error in
            XCTAssertEqual(
                error as? PackageVerificationError,
                .fileDigestMismatch(fixture.largeAssetPath)
            )
        }
    }

    func testRuntimeAdmissionRejectsSignedManifestAndPayloadDrift() throws {
        do {
            let fixture = try makeRuntimeAdmissionFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let changed = SignedPackageManifest(
                packageID: fixture.manifest.packageID,
                packageVersion: SchemaVersion(major: 1, minor: 1),
                schemaVersion: fixture.manifest.schemaVersion,
                minimumRuntime: fixture.manifest.minimumRuntime,
                files: fixture.manifest.files,
                manifestDigest: fixture.manifest.manifestDigest,
                signature: fixture.manifest.signature
            )
            try canonicalJSONEncoder().encode(changed).write(
                to: fixture.manifestURL,
                options: .atomic
            )

            XCTAssertThrowsError(
                try runtimeAdmit(fixture)
            ) { error in
                XCTAssertEqual(error as? PackageVerificationError, .invalidManifestDigest)
            }
        }

        do {
            let fixture = try makeRuntimeAdmissionFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            var payload = try Data(contentsOf: fixture.payloadURL)
            let title = try XCTUnwrap(payload.range(of: Data("The First Farmers".utf8)))
            payload[title.lowerBound] = 0x41
            try payload.write(to: fixture.payloadURL, options: .atomic)

            XCTAssertThrowsError(
                try runtimeAdmit(fixture)
            ) { error in
                XCTAssertEqual(
                    error as? PackageVerificationError,
                    .fileDigestMismatch(fixture.payloadPath)
                )
            }
        }
    }

    func testRuntimeAdmissionRejectsExactTreeAndDeclaredSizeDrift() throws {
        do {
            let fixture = try makeRuntimeAdmissionFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            try FileManager.default.createDirectory(
                at: fixture.root.appending(path: "foreign-empty-directory"),
                withIntermediateDirectories: false
            )

            XCTAssertThrowsError(try runtimeAdmit(fixture)) { error in
                XCTAssertEqual(
                    error as? PackageVerificationError,
                    .installedTreeMismatch
                )
            }
        }

        do {
            let fixture = try makeRuntimeAdmissionFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let handle = try FileHandle(forWritingTo: fixture.largeAssetURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data([0x01]))
            try handle.close()

            XCTAssertThrowsError(try runtimeAdmit(fixture)) { error in
                XCTAssertEqual(
                    error as? PackageVerificationError,
                    .fileSizeMismatch(fixture.largeAssetPath)
                )
            }
        }
    }

    func testSignedPackageRejectsTamperedContentAndMetadata() throws {
        let payload = canonicalPackage()
        let data = try ContentDocumentDecoder.encodePackage(payload)
        let record = PackageFileRecord(
            path: "payload.json",
            bytes: Int64(data.count),
            sha256: sha256(data)
        )
        let first = SignedPackageManifest(
            packageID: payload.packageID,
            packageVersion: SchemaVersion(major: 1),
            schemaVersion: SchemaVersion(major: 1),
            minimumRuntime: SchemaVersion(major: 1),
            files: [record],
            manifestDigest: String(repeating: "0", count: 64),
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "launch-signing-key",
                value: "AA=="
            )
        )
        let firstDigest = try ContentPackageVerifier.manifestDigest(for: first)
        let changedMetadata = SignedPackageManifest(
            packageID: payload.packageID,
            packageVersion: SchemaVersion(major: 2),
            schemaVersion: first.schemaVersion,
            minimumRuntime: first.minimumRuntime,
            files: first.files,
            manifestDigest: first.manifestDigest,
            signature: first.signature
        )
        XCTAssertNotEqual(firstDigest, try ContentPackageVerifier.manifestDigest(for: changedMetadata))
    }

    func testManifestDigestMatchesTheCrossRuntimeGoldenVector() throws {
        let manifest = SignedPackageManifest(
            packageID: "essential-free-v1",
            packageVersion: SchemaVersion(major: 2, minor: 1, patch: 3),
            schemaVersion: SchemaVersion(major: 1, minor: 4),
            minimumRuntime: SchemaVersion(major: 1, minor: 2),
            files: [
                PackageFileRecord(path: "a.bin", bytes: 1, sha256: String(repeating: "a", count: 64)),
                PackageFileRecord(path: "z.bin", bytes: 2, sha256: String(repeating: "b", count: 64)),
            ],
            manifestDigest: String(repeating: "0", count: 64),
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "test-signing-key",
                value: "AA=="
            )
        )
        XCTAssertEqual(
            try ContentPackageVerifier.manifestDigest(for: manifest),
            "3667b8afd9e0bf04e89e1a6bf89469b5a2ddde1f4ed7ed0301467cc0af8e3de2"
        )
    }

    func testAppShellIsLocalizationReadyWhileLaunchRemainsEnglish() throws {
        let launchShell = canonicalAppShell()
        XCTAssertNoThrow(try launchShell.validateLaunch())
        let roundTrip = try JSONDecoder().decode(
            AppShellSpec.self,
            from: JSONEncoder().encode(launchShell)
        )
        XCTAssertEqual(roundTrip, launchShell)

        let norwegianShell = canonicalAppShell(
            locale: LocaleDescriptor(identifier: "nb-NO", fallbackIdentifier: "en")
        )
        XCTAssertNoThrow(try norwegianShell.validate())
        XCTAssertThrowsError(try norwegianShell.validateLaunch())
        XCTAssertThrowsError(
            try LocaleDescriptor(identifier: "nb_no", fallbackIdentifier: "en").validate()
        )
    }

    func testAppShellRejectsConflictingCopyForOneStableLocalizedID() {
        let base = canonicalAppShell()
        var chapters = base.livingWorld.chapters
        let first = chapters[0]
        chapters[0] = LivingWorldChapterPresentationSpec(
            chapterID: first.chapterID,
            worldNodeID: first.worldNodeID,
            position: first.position,
            historicalInvitation: LocalizedStringSpec(
                id: base.prologue.narrative.heading.id,
                launchEnglish: "A conflicting public value"
            )
        )
        let livingWorld = LivingWorldPresentationSpec(
            id: base.livingWorld.id,
            sceneID: base.livingWorld.sceneID,
            accessibilityID: base.livingWorld.accessibilityID,
            currentPlaceLayerID: base.livingWorld.currentPlaceLayerID,
            nextPressureLayerID: base.livingWorld.nextPressureLayerID,
            chapters: chapters,
            traces: base.livingWorld.traces
        )
        let conflicting = AppShellSpec(
            schemaVersion: base.schemaVersion,
            id: base.id,
            locale: base.locale,
            prologue: base.prologue,
            livingWorld: livingWorld
        )

        XCTAssertThrowsError(try conflicting.validate())
    }

    func testNarrationCueRejectsHashScopeAndOrphanDrift() throws {
        let base = canonicalPackage()
        XCTAssertNoThrow(try base.validate())
        let event = try XCTUnwrap(base.audioTimelines[0].events.first)
        let binding = try XCTUnwrap(event.narrationBinding)

        let wrongHash = NarrationCueBinding(
            manuscriptSegmentID: binding.manuscriptSegmentID,
            manuscriptSegmentSHA256: String(repeating: "0", count: 64),
            scope: binding.scope
        )
        XCTAssertThrowsError(try replacingNarrationBinding(in: base, with: wrongHash).validate())

        let wrongScope = NarrationCueBinding(
            manuscriptSegmentID: binding.manuscriptSegmentID,
            manuscriptSegmentSHA256: binding.manuscriptSegmentSHA256,
            scope: NarrationCueScope(
                chapterID: binding.scope.chapterID,
                arcID: binding.scope.arcID,
                beatID: "another-beat"
            )
        )
        XCTAssertThrowsError(try replacingNarrationBinding(in: base, with: wrongScope).validate())
        XCTAssertThrowsError(try replacingNarrationBinding(in: base, with: nil).validate())
    }

    func testPublicAudioGainAndInteractionLoopFrameBoundsFailClosed() throws {
        func audibleTimeline(gain: Double) -> AudioTimeline {
            AudioTimeline(
                id: "bounded-audio",
                sampleRate: 48_000,
                events: [
                    AudioEvent(
                        cueID: "bounded-cue",
                        role: .soundscape,
                        startSample: 0,
                        durationSamples: 1,
                        assetPath: "audio/bounded.wav",
                        gain: gain
                    ),
                ],
                haptics: []
            )
        }
        XCTAssertNoThrow(try audibleTimeline(gain: 0).validate())
        XCTAssertNoThrow(try audibleTimeline(gain: 4).validate())
        for invalidGain in [-0.001, 4.001, .infinity, .nan] {
            XCTAssertThrowsError(try audibleTimeline(gain: invalidGain).validate())
        }

        let base = canonicalPackage()
        let program = try XCTUnwrap(base.responsiveAudioPrograms.first)
        let interactionIDs = Set(program.interactionBeds.map(\.timelineID))
        func replacingInteractionDurations(_ duration: Int64) -> [AudioTimeline] {
            base.audioTimelines.map { timeline in
                guard interactionIDs.contains(timeline.id) else { return timeline }
                return AudioTimeline(
                    id: timeline.id,
                    sampleRate: timeline.sampleRate,
                    events: timeline.events.map { event in
                        AudioEvent(
                            cueID: event.cueID,
                            role: event.role,
                            startSample: 0,
                            durationSamples: duration,
                            assetPath: event.assetPath,
                            gain: event.gain,
                            narrationBinding: event.narrationBinding
                        )
                    } + (duration == 0 ? [
                        AudioEvent(
                            cueID: AudioCueID("\(timeline.id.rawValue)-timing"),
                            role: .silence,
                            startSample: 0,
                            durationSamples: 1,
                            assetPath: nil,
                            gain: 0
                        ),
                    ] : []),
                    haptics: timeline.haptics
                )
            }
        }

        XCTAssertThrowsError(
            try program.validate(timelines: replacingInteractionDurations(0))
        ) { error in
            XCTAssertTrue(String(describing: error).contains("positive duration"))
        }
        XCTAssertThrowsError(
            try program.validate(
                timelines: replacingInteractionDurations(
                    Int64(UInt32.max) + 1
                )
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("UInt32"))
        }
    }

    func testResponsiveAudioExitPolicyUsesTheConsequenceSampleDomain() throws {
        let base = canonicalPackage()
        let program = try XCTUnwrap(base.responsiveAudioPrograms.first)
        let consequence = try XCTUnwrap(
            base.audioTimelines.first { $0.id == program.consequenceTimelineID }
        )
        let duration = consequence.authoredDurationSamples
        func replacingExitPolicy(
            _ exitPolicy: ResponsiveAudioExitPolicy
        ) -> ResponsiveAudioProgramSpec {
            ResponsiveAudioProgramSpec(
                id: program.id,
                scope: program.scope,
                approachTimelineID: program.approachTimelineID,
                interactionBeds: program.interactionBeds,
                consequenceTimelineID: program.consequenceTimelineID,
                exitPolicy: exitPolicy,
                causalMix: program.causalMix
            )
        }

        XCTAssertThrowsError(
            try replacingExitPolicy(
                .boundedFade(durationSamples: 0)
            ).validate(timelines: base.audioTimelines)
        )
        XCTAssertThrowsError(
            try replacingExitPolicy(
                .boundedFade(durationSamples: Int64(UInt32.max) + 1)
            ).validate(timelines: base.audioTimelines)
        )
        XCTAssertThrowsError(
            try replacingExitPolicy(
                .boundedFade(durationSamples: duration + 1)
            ).validate(timelines: base.audioTimelines)
        )
        XCTAssertNoThrow(
            try replacingExitPolicy(
                .boundedFade(durationSamples: duration)
            ).validate(timelines: base.audioTimelines)
        )
    }

    func testHapticWireVocabularyIsSemanticAndClosed() throws {
        let semantics: [HapticSemantic] = [
            .contact, .drag, .resistance, .transfer, .break, .seal,
        ]
        let events = semantics.enumerated().map { index, semantic in
            HapticEvent(
                sample: Int64(index * 100),
                kind: semantic,
                intensity: 0.5,
                sharpness: 0.5
            )
        }
        let data = try JSONEncoder().encode(events)
        XCTAssertEqual(try JSONDecoder().decode([HapticEvent].self, from: data), events)
        let wire = try XCTUnwrap(String(data: data, encoding: .utf8))
        for semantic in ["contact", "drag", "resistance", "transfer", "break", "seal"] {
            XCTAssertTrue(wire.contains("\"kind\":\"\(semantic)\""))
        }
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                HapticEvent.self,
                from: Data(
                    #"{"sample":0,"kind":"impact","intensity":0.5,"sharpness":0.5}"#.utf8
                )
            )
        )
    }

    func testEveryInteractionVisualBindingHasAStableWireCase() throws {
        let bindings: [SceneInteractionVisualBinding] = [
            .trace(
                SceneTraceVisualBinding(
                    interactionID: "trace-road",
                    interactionTargetID: "road-target",
                    layerID: "road",
                    idleVariantID: "idle",
                    tracingVariantID: "tracing",
                    completedVariantID: "completed"
                )
            ),
            .allocate(
                SceneAllocateVisualBinding(
                    interactionID: "allocate-store",
                    resource: SceneAllocationResourceVisualBinding(
                        layerID: "grain",
                        hitRegion: SceneHitRegion(
                            path: [
                                NormalizedPoint(x: 0.4, y: 0.6),
                                NormalizedPoint(x: 0.6, y: 0.6),
                                NormalizedPoint(x: 0.5, y: 0.8),
                            ]
                        ),
                        hitTest: .selectedVariantAlpha,
                        variantsByRemainingUnits: [
                            SceneRemainingUnitsVariant(
                                maximumRemainingUnits: 0,
                                variantID: "empty"
                            ),
                            SceneRemainingUnitsVariant(
                                maximumRemainingUnits: 4,
                                variantID: "full"
                            ),
                        ]
                    ),
                    transferLayerID: "grain-transfer",
                    destinations: [
                        SceneAllocationDestinationVisualBinding(
                            destinationID: "seed",
                            interactionTargetID: "seed-target",
                            layerID: "seed-store",
                            emptyVariantID: "empty",
                            receivingVariantID: "receiving",
                            completedVariantID: "sealed",
                            transferPath: [
                                NormalizedPoint(x: 0.5, y: 0.7),
                                NormalizedPoint(x: 0.3, y: 0.5),
                            ]
                        ),
                    ]
                )
            ),
            .assemble(
                SceneAssembleVisualBinding(
                    interactionID: "assemble-frame",
                    components: [
                        SceneAssemblyComponentVisualBinding(
                            componentID: "post",
                            sourceInteractionTargetID: "post-source-target",
                            slotInteractionTargetID: "post-slot-target",
                            layerID: "post",
                            availableVariantID: "available",
                            resistedVariantID: "resisted",
                            placedVariantID: "placed"
                        ),
                    ]
                )
            ),
            .pressure(
                ScenePressureVisualBinding(
                    interactionID: "pressure-frontier",
                    forces: [
                        ScenePressureForceVisualBinding(
                            forceID: "frontier-force",
                            layerID: "frontier-force",
                            interactionTargetID: "frontier-target"
                        ),
                    ],
                    systemLayerID: "frontier",
                    restingVariantID: "resting",
                    resistingVariantID: "resisting",
                    stableVariantID: "stable",
                    brokenVariantID: "broken"
                )
            ),
            .transform(
                SceneTransformVisualBinding(
                    interactionID: "transform-ground",
                    stages: [
                        SceneTransformationStageVisualBinding(
                            stageID: "clear-ground",
                            interactionTargetID: "field-edge",
                            layerID: "field",
                            beforeVariantID: "before",
                            activeVariantID: "active",
                            completedVariantID: "completed"
                        ),
                    ]
                )
            ),
        ]

        let data = try JSONEncoder().encode(bindings)
        XCTAssertEqual(
            try JSONDecoder().decode([SceneInteractionVisualBinding].self, from: data),
            bindings
        )
        let wire = try XCTUnwrap(String(data: data, encoding: .utf8))
        for grammar in ["trace", "allocate", "assemble", "pressure", "transform"] {
            XCTAssertTrue(wire.contains("\"grammar\":\"\(grammar)\""))
        }
        let assembleWire = try XCTUnwrap(
            String(data: JSONEncoder().encode(bindings[2]), encoding: .utf8)
        )
        XCTAssertTrue(
            assembleWire.contains(
                "\"sourceInteractionTargetID\":\"post-source-target\""
            )
        )
        XCTAssertTrue(
            assembleWire.contains(
                "\"slotInteractionTargetID\":\"post-slot-target\""
            )
        )
        XCTAssertFalse(
            assembleWire.contains("\"interactionTargetID\":\"post-source-target\"")
        )
    }

    func testLegacySingleTargetAssembleBindingDecodesButCannotBeReencoded() throws {
        let legacy = Data(
            """
            {
              "componentID": "post",
              "interactionTargetID": "post-target",
              "layerID": "post",
              "availableVariantID": "available",
              "resistedVariantID": "resisted",
              "placedVariantID": "placed"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(
            SceneAssemblyComponentVisualBinding.self,
            from: legacy
        )
        XCTAssertEqual(decoded.sourceInteractionTargetID, "post-target")
        XCTAssertNil(decoded.slotInteractionTargetID)
        XCTAssertThrowsError(try JSONEncoder().encode(decoded))

        let mixedWire = Data(
            """
            {
              "componentID": "post",
              "sourceInteractionTargetID": "post-source-target",
              "slotInteractionTargetID": "post-slot-target",
              "interactionTargetID": "post-target",
              "layerID": "post",
              "availableVariantID": "available",
              "resistedVariantID": "resisted",
              "placedVariantID": "placed"
            }
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                SceneAssemblyComponentVisualBinding.self,
                from: mixedWire
            )
        )

        let aliased = SceneAssemblyComponentVisualBinding(
            componentID: "post",
            sourceInteractionTargetID: "post-target",
            slotInteractionTargetID: "post-target",
            layerID: "post",
            availableVariantID: "available",
            resistedVariantID: "resisted",
            placedVariantID: "placed"
        )
        XCTAssertThrowsError(try JSONEncoder().encode(aliased))
    }

    private func canonicalPackage() -> ContentPackagePayload {
        let accessibility = AccessibilitySpec(
            id: "allocate-accessibility",
            sceneSummary: "The household divides its finite grain store.",
            elements: [
                AccessibilityElementSpec(
                    id: "allocate-seed",
                    role: .adjustable,
                    label: "Grain kept for seed",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .increment,
                            label: "Keep one more unit for seed",
                            token: .allocate(destinationID: "seed", unitsPerStep: 1)
                        ),
                        AccessibilityActionSpec(
                            kind: .decrement,
                            label: "Return one seed unit to the store",
                            token: .allocate(destinationID: "seed", unitsPerStep: 1)
                        ),
                    ]
                ),
                AccessibilityElementSpec(
                    id: "allocate-winter",
                    role: .adjustable,
                    label: "Grain kept for winter",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .increment,
                            label: "Keep one more unit for winter",
                            token: .allocate(destinationID: "winter", unitsPerStep: 1)
                        ),
                        AccessibilityActionSpec(
                            kind: .decrement,
                            label: "Return one winter unit to the store",
                            token: .allocate(destinationID: "winter", unitsPerStep: 1)
                        ),
                    ]
                ),
                AccessibilityElementSpec(
                    id: "commit-allocation",
                    role: .action,
                    label: "Set the stores",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .activate,
                            label: "Commit the allocation",
                            token: .commitAllocation
                        ),
                    ]
                ),
            ]
        )
        let interaction = canonicalAllocateInteraction()
        let chapter = ChapterSpec(
            schemaVersion: SchemaVersion(major: 1),
            id: "first-farmers",
            title: "The First Farmers",
            period: "7000–3300 BC",
            arcs: [
                ArcSpec(
                    id: "river-before-fields",
                    title: "The River Before the Fields",
                    targetDurationMinutes: 9,
                    situation: "A household reaches an inhabited European river world.",
                    mechanism: "Seed, animals and learned routines move together.",
                    turn: "The field arrives as a complete living system.",
                    consequence: "The river becomes a frontier between durable ways of life.",
                    handoff: "The harvest must now last through winter.",
                    beats: [
                        BeatSpec(
                            id: "household-crossing",
                            sceneID: "aegean-crossing",
                            narrative: NarrativeText(
                                heading: "The Harvest Had to Last",
                                paragraphs: ["The household divides one finite store between winter and seed."]
                            ),
                            narrationCueIDs: ["narration-crossing"],
                            interaction: interaction,
                            checkpoint: .afterInteraction
                        ),
                    ]
                ),
            ],
            completionEffects: [worldEffect(id: "chapter-landscape-effect", nodeID: "farming-belt")]
        )
        let scene = canonicalAllocateScene()
        let timeline = AudioTimeline(
            id: "first-farmers-audio",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "narration-crossing",
                    role: .narration,
                    startSample: 0,
                    durationSamples: 48_000,
                    assetPath: "audio/crossing.m4a",
                    gain: 1,
                    narrationBinding: NarrationCueBinding(
                        manuscriptSegmentID: chapter.arcs[0].beats[0].narrative.heading.id,
                        manuscriptSegmentSHA256: sha256(
                            Data(
                                chapter.arcs[0].beats[0].narrative.heading.launchEnglish.utf8
                            )
                        ),
                        scope: NarrationCueScope(
                            chapterID: chapter.id,
                            arcID: chapter.arcs[0].id,
                            beatID: chapter.arcs[0].beats[0].id
                        )
                    )
                ),
            ],
            haptics: []
        )
        let responsiveAudio = canonicalResponsiveAudio(
            chapterID: chapter.id,
            arcID: chapter.arcs[0].id,
            beatID: chapter.arcs[0].beats[0].id,
            interactionID: interaction.id
        )
        return ContentPackagePayload(
            schemaVersion: SchemaVersion(major: 1),
            packageID: "essential-free-v1",
            worldSeed: WorldSeedSpec(nodes: [], traces: []),
            chapters: [chapter],
            scenes: [scene],
            audioTimelines: [timeline] + responsiveAudio.timelines,
            responsiveAudioPrograms: [responsiveAudio.program],
            accessibility: [accessibility]
        )
    }

    private func canonicalResponsiveAudio(
        chapterID: ChapterID,
        arcID: ArcID,
        beatID: BeatID,
        interactionID: InteractionID
    ) -> (program: ResponsiveAudioProgramSpec, timelines: [AudioTimeline]) {
        func timeline(_ region: String, duration: Int64) -> AudioTimeline {
            let id = AudioTimelineID("responsive-\(beatID.rawValue)-\(region)")
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
        let scope = ResponsiveAudioProgramScope(
            chapterID: chapterID,
            arcID: arcID,
            beatID: beatID,
            interactionID: interactionID
        )
        return (
            ResponsiveAudioProgramSpec(
                id: ResponsiveAudioProgramID("program-\(interactionID.rawValue)"),
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
            ),
            [approach, waiting, engaged, resistance, consequence]
        )
    }

    private func baselineCrop(id: String = "baseline-393x852") -> SceneViewportCrop {
        SceneViewportCrop(
            id: id,
            viewport: SceneViewportSize(widthPoints: 393, heightPoints: 852),
            sourceRect: NormalizedRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9),
            safeTextRegions: [
                SceneSafeTextRegion(
                    id: "opening-copy",
                    rect: NormalizedRect(x: 0.08, y: 0.06, width: 0.84, height: 0.22)
                ),
            ]
        )
    }

    private func canonicalScene(
        accessibilityID: AccessibilityID = "route-accessibility",
        canvas: ScenePixelSize = ScenePixelSize(width: 1200, height: 2600),
        cameraTravelBounds: NormalizedRect = NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
        layerAssetPath: String = "assets/water.heif",
        reduceAssetPath: String = "assets/reduce-motion.heif",
        reduceForegroundAssetPath: String = "assets/reduce-motion-foreground.heif",
        authoredOverscanFraction: Double = 0.15,
        viewportCrops: [SceneViewportCrop]? = nil,
        reduceViewportCrops: [SceneViewportCrop]? = nil,
        layerOrder: Int = 0,
        layerFrame: NormalizedRect = NormalizedRect(x: 0, y: 0, width: 1, height: 1),
        layerDepth: Double = 0.2,
        layerOpacity: Double = 1,
        layerMasks: SceneLayerMaskSet? = nil,
        layerMotion: SceneLayerMotion = SceneLayerMotion(
            parallaxFactor: 0.1,
            windResponse: 0,
            focusResponse: 0.1
        ),
        stateVariants: [SceneLayerStateVariant]? = nil,
        keyframes: [CameraKeyframe]? = nil,
        atmosphere: [AtmosphereSpec]? = nil,
        interactionTargets: [SceneInteractionTargetBinding]? = nil,
        sceneLayers: [SceneLayerSpec]? = nil,
        interactionVisualBinding: SceneInteractionVisualBinding? = nil,
        stateOverlayLayerIDs: [SceneLayerID]? = nil
    ) -> SceneSpec {
        let crop = baselineCrop()
        let layerID: SceneLayerID = "water"
        let defaultLayer = SceneLayerSpec(
            id: layerID,
            order: layerOrder,
            assetPath: layerAssetPath,
            frame: layerFrame,
            depth: layerDepth,
            opacity: layerOpacity,
            masks: layerMasks ?? SceneLayerMaskSet(
                alphaMaskAssetPath: "assets/water-alpha.png",
                occlusionMaskAssetPath: "assets/water-occlusion.png",
                depthMaskAssetPath: "assets/water-depth.png",
                lightMaskAssetPath: "assets/water-light.png"
            ),
            motion: layerMotion,
            stateVariants: stateVariants ?? [
                SceneLayerStateVariant(
                    id: "arrival",
                    assetPath: "assets/water-arrival.heif",
                    masks: SceneLayerMaskSet(alphaMaskAssetPath: "assets/water-arrival-alpha.png")
                ),
            ]
        )
        let authoredLayers = sceneLayers ?? [defaultLayer]
        let overlayLayerIDs = stateOverlayLayerIDs
            ?? authoredLayers.filter { !$0.stateVariants.isEmpty }.map(\.id)
        let reducedStrata: [ReduceMotionStratum] = if overlayLayerIDs.isEmpty {
            [
                ReduceMotionStratum(
                    id: "static-world",
                    kind: .staticPlate,
                    assetPath: reduceAssetPath
                ),
            ]
        } else {
            [
                ReduceMotionStratum(
                    id: "static-underlay",
                    kind: .staticPlate,
                    assetPath: reduceAssetPath
                ),
            ] + overlayLayerIDs.map {
                ReduceMotionStratum(
                    id: "\($0.rawValue)-state",
                    kind: .stateOverlay,
                    layerID: $0
                )
            } + [
                ReduceMotionStratum(
                    id: "static-foreground",
                    kind: .staticPlate,
                    assetPath: reduceForegroundAssetPath
                ),
            ]
        }
        return SceneSpec(
            id: "aegean-crossing",
            sceneCanvas: SceneCanvasSpec(
                canvas: canvas,
                cameraTravelBounds: cameraTravelBounds,
                authoredOverscanFraction: authoredOverscanFraction,
                viewportCrops: viewportCrops ?? [crop]
            ),
            layers: authoredLayers,
            cameraRail: CameraRail(
                keyframes: keyframes ?? [
                    CameraKeyframe(progress: 0, center: NormalizedPoint(x: 0.5, y: 0.5), scale: 1),
                    CameraKeyframe(progress: 1, center: NormalizedPoint(x: 0.58, y: 0.42), scale: 1.1),
                ]
            ),
            atmosphere: atmosphere ?? [
                AtmosphereSpec(
                    kind: .mist,
                    density: 0.2,
                    velocity: SignedUnitVector(dx: -0.1, dy: 0),
                    deterministicSeed: 42
                ),
            ],
            interactionTargets: interactionTargets ?? [
                SceneInteractionTargetBinding(
                    interactionTargetID: "route-control",
                    layerID: layerID,
                    hitRegion: SceneHitRegion(
                        path: [
                            NormalizedPoint(x: 0.25, y: 0.65),
                            NormalizedPoint(x: 0.75, y: 0.55),
                            NormalizedPoint(x: 0.65, y: 0.82),
                        ]
                    ),
                    accessibilityElementID: "route-control"
                ),
            ],
            interactionVisualBinding: interactionVisualBinding,
            reduceMotionComposition: ReduceMotionComposition(
                canvas: ScenePixelSize(width: 1200, height: 2600),
                viewportCrops: reduceViewportCrops ?? [crop],
                strata: reducedStrata
            ),
            mechanismFocus: "crossing-route",
            accessibilityID: accessibilityID
        )
    }

    private func canonicalAllocateInteraction(
        destinations: [AllocationDestination]? = nil
    ) -> InteractionSpec {
        InteractionSpec(
            id: "allocate-store",
            prompt: "Divide the store",
            grammar: .allocate(
                AllocateInteractionSpec(
                    resourceName: "Stored grain",
                    totalUnits: 4,
                    destinations: destinations ?? [
                        AllocationDestination(id: "seed", minimumUnits: 1),
                        AllocationDestination(id: "winter", minimumUnits: 1),
                    ]
                )
            ),
            completionEffects: [worldEffect(id: "store-effect", nodeID: "stored-harvest")],
            accessibilityID: "allocate-accessibility"
        )
    }

    private func canonicalAllocateScene(
        interactionID: InteractionID = "allocate-store",
        resourceThresholds: [SceneRemainingUnitsVariant]? = nil,
        bindingDestinations: [SceneAllocationDestinationVisualBinding]? = nil,
        interactionTargets: [SceneInteractionTargetBinding]? = nil,
        stateOverlayLayerIDs: [SceneLayerID]? = nil,
        sceneLayers: [SceneLayerSpec]? = nil
    ) -> SceneSpec {
        let layers = sceneLayers ?? canonicalAllocateLayers()
        return canonicalScene(
            accessibilityID: "allocate-accessibility",
            interactionTargets: interactionTargets ?? canonicalAllocateTargets(),
            sceneLayers: layers,
            interactionVisualBinding: .allocate(
                SceneAllocateVisualBinding(
                    interactionID: interactionID,
                    resource: SceneAllocationResourceVisualBinding(
                        layerID: "harvest",
                        hitRegion: SceneHitRegion(
                            path: [
                                NormalizedPoint(x: 0.43, y: 0.68),
                                NormalizedPoint(x: 0.57, y: 0.68),
                                NormalizedPoint(x: 0.57, y: 0.8),
                                NormalizedPoint(x: 0.43, y: 0.8),
                            ]
                        ),
                        hitTest: .selectedVariantAlpha,
                        variantsByRemainingUnits: resourceThresholds ?? [
                            SceneRemainingUnitsVariant(
                                maximumRemainingUnits: 0,
                                variantID: "exhausted"
                            ),
                            SceneRemainingUnitsVariant(
                                maximumRemainingUnits: 4,
                                variantID: "full"
                            ),
                        ]
                    ),
                    transferLayerID: "grain-transfer",
                    destinations: bindingDestinations ?? canonicalAllocateDestinations()
                )
            ),
            stateOverlayLayerIDs: stateOverlayLayerIDs
                ?? layers.filter { !$0.stateVariants.isEmpty }.map(\.id)
        )
    }

    private func canonicalAllocateLayers() -> [SceneLayerSpec] {
        [
            canonicalLayer(id: "harvest", order: 0, variants: ["exhausted", "full"]),
            canonicalLayer(id: "grain-transfer", order: 1),
            canonicalLayer(
                id: "seed-store",
                order: 2,
                variants: ["empty", "receiving", "committed"]
            ),
            canonicalLayer(
                id: "winter-store",
                order: 3,
                variants: ["empty", "receiving", "provisioned"]
            ),
        ]
    }

    private func canonicalLayer(
        id: SceneLayerID,
        order: Int,
        variants: [String] = [],
        frame: NormalizedRect = NormalizedRect(x: 0, y: 0, width: 1, height: 1),
        parallaxFactor: Double = 0,
        windResponse: Double = 0
    ) -> SceneLayerSpec {
        SceneLayerSpec(
            id: id,
            order: order,
            assetPath: "assets/\(id.rawValue).heif",
            frame: frame,
            depth: Double(order + 1) / 10,
            masks: SceneLayerMaskSet(
                alphaMaskAssetPath: "assets/\(id.rawValue)-alpha.png"
            ),
            motion: SceneLayerMotion(
                parallaxFactor: parallaxFactor,
                windResponse: windResponse
            ),
            stateVariants: variants.map { variantID in
                SceneLayerStateVariant(
                    id: variantID,
                    assetPath: "assets/\(id.rawValue)-\(variantID).heif",
                    masks: SceneLayerMaskSet(
                        alphaMaskAssetPath: "assets/\(id.rawValue)-\(variantID)-alpha.png"
                    )
                )
            }
        )
    }

    private func canonicalAllocateTargets() -> [SceneInteractionTargetBinding] {
        [
            canonicalAllocateTarget(
                id: "seed-target",
                layerID: "seed-store",
                accessibilityElementID: "allocate-seed",
                minimumX: 0.22,
                maximumX: 0.42
            ),
            canonicalAllocateTarget(
                id: "winter-target",
                layerID: "winter-store",
                accessibilityElementID: "allocate-winter",
                minimumX: 0.58,
                maximumX: 0.78
            ),
        ]
    }

    private func canonicalAllocateTarget(
        id: String,
        layerID: SceneLayerID,
        accessibilityElementID: String,
        minimumX: Double,
        maximumX: Double
    ) -> SceneInteractionTargetBinding {
        SceneInteractionTargetBinding(
            interactionTargetID: id,
            layerID: layerID,
            hitRegion: SceneHitRegion(
                path: [
                    NormalizedPoint(x: minimumX, y: 0.52),
                    NormalizedPoint(x: maximumX, y: 0.52),
                    NormalizedPoint(x: maximumX, y: 0.72),
                    NormalizedPoint(x: minimumX, y: 0.72),
                ]
            ),
            accessibilityElementID: accessibilityElementID
        )
    }

    private func rectangularTarget(
        id: String,
        layerID: SceneLayerID,
        minimumX: Double,
        maximumX: Double,
        minimumY: Double = 0.45,
        maximumY: Double = 0.55
    ) -> SceneInteractionTargetBinding {
        SceneInteractionTargetBinding(
            interactionTargetID: id,
            layerID: layerID,
            hitRegion: SceneHitRegion(
                path: [
                    NormalizedPoint(x: minimumX, y: minimumY),
                    NormalizedPoint(x: maximumX, y: minimumY),
                    NormalizedPoint(x: maximumX, y: maximumY),
                    NormalizedPoint(x: minimumX, y: maximumY),
                ]
            ),
            accessibilityElementID: id
        )
    }

    private func canonicalAllocateDestinations() -> [SceneAllocationDestinationVisualBinding] {
        [
            SceneAllocationDestinationVisualBinding(
                destinationID: "seed",
                interactionTargetID: "seed-target",
                layerID: "seed-store",
                emptyVariantID: "empty",
                receivingVariantID: "receiving",
                completedVariantID: "committed",
                transferPath: [
                    NormalizedPoint(x: 0.5, y: 0.78),
                    NormalizedPoint(x: 0.32, y: 0.62),
                ]
            ),
            SceneAllocationDestinationVisualBinding(
                destinationID: "winter",
                interactionTargetID: "winter-target",
                layerID: "winter-store",
                emptyVariantID: "empty",
                receivingVariantID: "receiving",
                completedVariantID: "provisioned",
                transferPath: [
                    NormalizedPoint(x: 0.5, y: 0.78),
                    NormalizedPoint(x: 0.68, y: 0.62),
                ]
            ),
        ]
    }

    private func replacingCanonicalPackage(
        scenes: [SceneSpec],
        accessibility: [AccessibilitySpec]? = nil
    ) -> ContentPackagePayload {
        let base = canonicalPackage()
        return ContentPackagePayload(
            schemaVersion: base.schemaVersion,
            packageID: base.packageID,
            worldSeed: base.worldSeed,
            chapters: base.chapters,
            scenes: scenes,
            audioTimelines: base.audioTimelines,
            responsiveAudioPrograms: base.responsiveAudioPrograms,
            accessibility: accessibility ?? base.accessibility
        )
    }

    private func replacingCanonicalPackage(
        interactionGrammar: InteractionSpec.Grammar
    ) -> ContentPackagePayload {
        let base = canonicalPackage()
        let chapter = base.chapters[0]
        let arc = chapter.arcs[0]
        let beat = arc.beats[0]
        let interaction = beat.interaction!
        let replacementInteraction = InteractionSpec(
            id: interaction.id,
            prompt: interaction.prompt,
            grammar: interactionGrammar,
            completionEffects: interaction.completionEffects,
            accessibilityID: interaction.accessibilityID
        )
        let replacementBeat = BeatSpec(
            id: beat.id,
            sceneID: beat.sceneID,
            narrative: beat.narrative,
            narrationCueIDs: beat.narrationCueIDs,
            interaction: replacementInteraction,
            completionEffects: beat.completionEffects,
            checkpoint: beat.checkpoint
        )
        let replacementArc = ArcSpec(
            id: arc.id,
            title: arc.title,
            targetDurationMinutes: arc.targetDurationMinutes,
            situation: arc.situation,
            mechanism: arc.mechanism,
            turn: arc.turn,
            consequence: arc.consequence,
            handoff: arc.handoff,
            beats: [replacementBeat]
        )
        let replacementChapter = ChapterSpec(
            schemaVersion: chapter.schemaVersion,
            id: chapter.id,
            title: chapter.title,
            period: chapter.period,
            arcs: [replacementArc],
            completionEffects: chapter.completionEffects
        )
        return ContentPackagePayload(
            schemaVersion: base.schemaVersion,
            packageID: base.packageID,
            worldSeed: base.worldSeed,
            chapters: [replacementChapter],
            scenes: base.scenes,
            audioTimelines: base.audioTimelines,
            responsiveAudioPrograms: base.responsiveAudioPrograms,
            accessibility: base.accessibility
        )
    }

    private func canonicalAppShell(
        locale: LocaleDescriptor = .launchEnglish
    ) -> AppShellSpec {
        let prologue = PrologueSpec(
            id: "wake-long-road",
            sceneID: "long-road-prologue",
            narrative: NarrativeText(
                heading: "The road is waiting",
                paragraphs: ["Draw the first movement west across the dark water."],
                actionPrompt: "Wake the road."
            ),
            interaction: InteractionSpec(
                id: "wake-long-road",
                prompt: "Trace the first crossing",
                grammar: .trace(
                    TraceInteractionSpec(
                        anchors: [
                            NormalizedPoint(x: 0.72, y: 0.52),
                            NormalizedPoint(x: 0.58, y: 0.5),
                        ],
                        tolerance: 0.1
                    )
                ),
                completionEffects: [
                    worldEffect(id: "wake-long-road-effect", nodeID: "long-road-origin"),
                ],
                accessibilityID: "wake-long-road-accessibility"
            ),
            checkpoint: .afterInteraction
        )
        let chapters = LaunchContent.chapterOrder.enumerated().map { index, chapterID in
            LivingWorldChapterPresentationSpec(
                chapterID: chapterID,
                worldNodeID: WorldNodeID("living-world-node-\(index + 1)"),
                position: NormalizedPoint(
                    x: 0.15 + Double(index % 6) * 0.13,
                    y: 0.12 + Double(index / 6) * 0.24
                ),
                historicalInvitation: LocalizedStringSpec(
                    id: LocalizedStringID(
                        "living-world-\(chapterID.rawValue)-invitation"
                    ),
                    launchEnglish: "Enter chapter \(index + 1)"
                )
            )
        }
        return AppShellSpec(
            schemaVersion: SchemaVersion(major: 1),
            id: "launch-app-shell",
            locale: locale,
            prologue: prologue,
            livingWorld: LivingWorldPresentationSpec(
                id: "cumulative-europe",
                sceneID: "living-world",
                accessibilityID: "living-world-accessibility",
                currentPlaceLayerID: "current-place",
                nextPressureLayerID: "next-pressure",
                chapters: chapters,
                traces: [
                    LivingWorldTracePresentationSpec(
                        worldTraceID: "long-road",
                        layerID: "long-road-layer"
                    ),
                ]
            )
        )
    }

    private func replacingNarrationBinding(
        in payload: ContentPackagePayload,
        with binding: NarrationCueBinding?
    ) -> ContentPackagePayload {
        let timeline = payload.audioTimelines[0]
        let event = timeline.events[0]
        let replacementEvent = AudioEvent(
            cueID: event.cueID,
            role: event.role,
            startSample: event.startSample,
            durationSamples: event.durationSamples,
            assetPath: event.assetPath,
            gain: event.gain,
            narrationBinding: binding
        )
        let replacementTimeline = AudioTimeline(
            id: timeline.id,
            sampleRate: timeline.sampleRate,
            events: [replacementEvent] + timeline.events.dropFirst(),
            haptics: timeline.haptics
        )
        return ContentPackagePayload(
            schemaVersion: payload.schemaVersion,
            packageID: payload.packageID,
            worldSeed: payload.worldSeed,
            chapters: payload.chapters,
            scenes: payload.scenes,
            audioTimelines: [replacementTimeline] + payload.audioTimelines.dropFirst(),
            responsiveAudioPrograms: payload.responsiveAudioPrograms,
            accessibility: payload.accessibility
        )
    }

    private struct RuntimeAdmissionFixture {
        let root: URL
        let manifestURL: URL
        let payloadURL: URL
        let largeAssetURL: URL
        let payloadPath: String
        let largeAssetPath: String
        let keyID: String
        let publicKey: Data
        let expectedPackage: ContentPackageSpec
        let manifest: SignedPackageManifest
    }

    private func makeRuntimeAdmissionFixture() throws -> RuntimeAdmissionFixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "runtime-admission-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let payload = canonicalPackage()
        let payloadData = try ContentDocumentDecoder.encodePackage(payload)
        let payloadPath = "content/payload.json"
        let payloadURL = root.appending(path: payloadPath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payloadData.write(to: payloadURL)

        let largeAssetPath = "assets/large-scene.bin"
        let largeAssetURL = root.appending(
            path: largeAssetPath,
            directoryHint: .notDirectory
        )
        try FileManager.default.createDirectory(
            at: largeAssetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let largeAssetData = Data(repeating: 0x5A, count: 2 * 1_048_576)
        try largeAssetData.write(to: largeAssetURL)

        let version = SchemaVersion(major: 1)
        let expectedPackage = ContentPackageSpec(
            id: payload.packageID,
            version: version,
            chapterIDs: payload.chapters.map(\.id),
            maximumInstalledBytes: 10_000_000,
            minimumRuntime: version,
            isEssentialInstall: true
        )
        let keyID = "runtime-test-key"
        let privateKey = P256.Signing.PrivateKey()
        let unsigned = SignedPackageManifest(
            packageID: payload.packageID,
            packageVersion: version,
            schemaVersion: payload.schemaVersion,
            minimumRuntime: version,
            files: [
                PackageFileRecord(
                    path: largeAssetPath,
                    bytes: Int64(largeAssetData.count),
                    sha256: sha256(largeAssetData)
                ),
                PackageFileRecord(
                    path: payloadPath,
                    bytes: Int64(payloadData.count),
                    sha256: sha256(payloadData)
                ),
            ],
            manifestDigest: String(repeating: "0", count: 64),
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: keyID,
                value: "AA=="
            )
        )
        let digest = try ContentPackageVerifier.manifestDigest(for: unsigned)
        let signature = try privateKey.signature(for: Data(digest.utf8))
        let manifest = SignedPackageManifest(
            packageID: unsigned.packageID,
            packageVersion: unsigned.packageVersion,
            schemaVersion: unsigned.schemaVersion,
            minimumRuntime: unsigned.minimumRuntime,
            files: unsigned.files,
            manifestDigest: digest,
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: keyID,
                value: signature.derRepresentation.base64EncodedString()
            )
        )
        let manifestURL = root.appending(path: ContentPackageVerifier.manifestFileName)
        try canonicalJSONEncoder().encode(manifest).write(to: manifestURL)
        return RuntimeAdmissionFixture(
            root: root,
            manifestURL: manifestURL,
            payloadURL: payloadURL,
            largeAssetURL: largeAssetURL,
            payloadPath: payloadPath,
            largeAssetPath: largeAssetPath,
            keyID: keyID,
            publicKey: privateKey.publicKey.x963Representation,
            expectedPackage: expectedPackage,
            manifest: manifest
        )
    }

    private func runtimeAdmit(
        _ fixture: RuntimeAdmissionFixture
    ) throws -> VerifiedContentPackage {
        try ContentPackageVerifier.admitPackageAtRuntime(
            at: fixture.root,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: [fixture.keyID: fixture.publicKey],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1)
        )
    }

    private func canonicalJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func worldEffect(id: WorldEffectID, nodeID: WorldNodeID) -> WorldEffect {
        WorldEffect(
            id: id,
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: nodeID,
                    kind: .landscape,
                    form: "revealed",
                    position: NormalizedPoint(x: 0.5, y: 0.5)
                )
            )
        )
    }
}
