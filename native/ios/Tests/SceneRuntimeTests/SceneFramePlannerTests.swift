import CryptoKit
import Foundation
@testable import ContentKit
@testable import SceneRuntime
import XCTest

final class SceneFramePlannerTests: XCTestCase {
    func testVerifiedPackageInventoryBindsEverySceneAssetToSignedManifest() throws {
        let root = try makeTemporaryPackageRoot()
        for path in SceneFrameFixtures.assetPaths {
            _ = try writeAsset(path, under: root)
        }
        let verified = try makeVerifiedPackage(root: root)

        let inventory = try SceneAssetInventory(
            verifiedPackage: verified,
            activatedPackageRoot: root
        )
        let plan = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(),
            assets: inventory
        )

        let background = try XCTUnwrap(plan.drawCommands.first?.asset)
        XCTAssertEqual(background.packagePath, "assets/background.heif")
        XCTAssertEqual(background.byteCount, 1)
        XCTAssertEqual(
            background.sha256,
            SHA256.hash(data: Data([0x01])).map { String(format: "%02x", $0) }.joined()
        )
        XCTAssertEqual(try SceneAssetDataLoader.load(background), Data([0x01]))
    }

    func testInventoryDoesNotReadLargeBytesAndFirstSceneUseRejectsReplacement() throws {
        let root = try makeTemporaryPackageRoot()
        for path in SceneFrameFixtures.assetPaths {
            _ = try writeAsset(path, under: root)
        }
        let verified = try makeVerifiedPackage(root: root)
        try Data([0x02]).write(
            to: root.appending(path: "assets/background.heif", directoryHint: .notDirectory),
            options: .atomic
        )

        let inventory = try SceneAssetInventory(
            verifiedPackage: verified,
            activatedPackageRoot: root
        )
        let plan = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(),
            assets: inventory
        )
        let background = try XCTUnwrap(plan.drawCommands.first?.asset)

        XCTAssertThrowsError(try SceneAssetDataLoader.load(background)) { error in
            XCTAssertEqual(
                error as? SceneAssetInventoryError,
                .manifestDigestMismatch("assets/background.heif")
            )
        }
    }

    func testAssetLoaderRejectsReplacementAfterInventoryConstruction() throws {
        let root = try makeTemporaryPackageRoot()
        for path in SceneFrameFixtures.assetPaths {
            _ = try writeAsset(path, under: root)
        }
        let inventory = try SceneAssetInventory(
            verifiedPackage: makeVerifiedPackage(root: root),
            activatedPackageRoot: root
        )
        let plan = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(),
            assets: inventory
        )
        let background = try XCTUnwrap(plan.drawCommands.first?.asset)
        try Data([0x02]).write(
            to: root.appending(path: background.packagePath, directoryHint: .notDirectory),
            options: .atomic
        )

        XCTAssertThrowsError(try SceneAssetDataLoader.load(background)) { error in
            XCTAssertEqual(
                error as? SceneAssetInventoryError,
                .manifestDigestMismatch("assets/background.heif")
            )
        }
    }

    func testAssetLoaderRejectsSymlinkReplacementAfterInventoryConstruction() throws {
        let root = try makeTemporaryPackageRoot()
        for path in SceneFrameFixtures.assetPaths {
            _ = try writeAsset(path, under: root)
        }
        let inventory = try SceneAssetInventory(
            verifiedPackage: makeVerifiedPackage(root: root),
            activatedPackageRoot: root
        )
        let plan = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(),
            assets: inventory
        )
        let background = try XCTUnwrap(plan.drawCommands.first?.asset)
        let backgroundURL = root.appending(
            path: background.packagePath,
            directoryHint: .notDirectory
        )
        let outsideRoot = try makeTemporaryPackageRoot()
        let outsideFile = try writeAsset("same-signed-bytes.heif", under: outsideRoot)
        try FileManager.default.removeItem(at: backgroundURL)
        do {
            try FileManager.default.createSymbolicLink(
                at: backgroundURL,
                withDestinationURL: outsideFile
            )
        } catch {
            throw XCTSkip("Symbolic links are unavailable in this test environment: \(error)")
        }

        XCTAssertThrowsError(try SceneAssetDataLoader.load(background)) { error in
            XCTAssertEqual(
                error as? SceneAssetInventoryError,
                .assetIsSymbolicLink("assets/background.heif")
            )
        }
    }

    func testVerifiedPackageInventoryRejectsSceneAssetMissingFromManifest() throws {
        let root = try makeTemporaryPackageRoot()
        for path in SceneFrameFixtures.assetPaths {
            _ = try writeAsset(path, under: root)
        }
        let verified = try makeVerifiedPackage(
            root: root,
            manifestPaths: SceneFrameFixtures.assetPaths.filter { $0 != "assets/background.heif" }
        )

        XCTAssertThrowsError(
            try SceneAssetInventory(
                verifiedPackage: verified,
                activatedPackageRoot: root
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneAssetInventoryError,
                .missingManifestRecord("assets/background.heif")
            )
        }
    }

    func testBaselinePortraitBuildsOrderedImmutableFramePlan() throws {
        let scene = SceneFrameFixtures.scene()
        let plan = try SceneFramePlanner.plan(
            scene: scene,
            request: SceneFrameFixtures.request(),
            assets: try makeInventory()
        )

        XCTAssertEqual(plan.sceneID, scene.id)
        XCTAssertEqual(plan.viewportCropID, "baseline-393x852")
        XCTAssertEqual(plan.viewport, SceneFrameSize(width: 393, height: 852))
        XCTAssertEqual(plan.camera.masterCenter, SceneFramePoint(x: 0.5, y: 0.5))
        XCTAssertEqual(plan.camera.viewportCenter, SceneFramePoint(x: 0.5, y: 0.5))
        XCTAssertEqual(plan.camera.scale, 1.2)
        XCTAssertTrue(plan.camera.followsAuthoredRail)
        XCTAssertEqual(
            plan.drawCommands.map(\.source),
            [
                .layer("background", variantID: nil),
                .layer("store", variantID: "divided"),
                .layer("foreground", variantID: nil),
            ]
        )
        XCTAssertEqual(plan.drawCommands.map(\.authoredOrder), [0, 1, 2])
        XCTAssertEqual(plan.drawCommands.map(\.depth), [0.1, 0.7, 0.7])
        XCTAssertEqual(plan.drawCommands[1].asset.packagePath, "assets/store-divided.heif")
        XCTAssertEqual(
            plan.drawCommands[1].masks.alpha?.packagePath,
            "assets/store-divided-alpha.png"
        )
        XCTAssertEqual(plan.safeTextRegions.map(\.id), ["opening-copy"])
        XCTAssertEqual(plan.atmosphere.count, 1)
        XCTAssertEqual(plan.atmosphere[0].authoredVelocity, SceneFrameVector(dx: -0.25, dy: 0.1))
        XCTAssertFalse(plan.atmosphere[0].samples.isEmpty)
    }

    func testLargestAuthoredCropMapsLayerFramesIntoItsViewport() throws {
        let plan = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(viewportCropID: "largest-430x932"),
            assets: try makeInventory()
        )

        XCTAssertEqual(plan.viewport, SceneFrameSize(width: 430, height: 932))
        let store = try XCTUnwrap(plan.drawCommands.first { command in
            command.source == .layer("store", variantID: "divided")
        })
        XCTAssertEqual(store.masterFrame, SceneFrameRect(x: 0.3, y: 0.35, width: 0.4, height: 0.3))
        let activeSourceSize = 0.7 / 1.2
        let activeSourceOrigin = 0.5 - activeSourceSize / 2
        XCTAssertEqual(
            store.viewportFrame.x,
            (0.3 - activeSourceOrigin) / activeSourceSize,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(
            store.viewportFrame.y,
            (0.35 - activeSourceOrigin) / activeSourceSize,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(store.viewportFrame.width, 0.4 / activeSourceSize, accuracy: 0.000_000_000_001)
        XCTAssertEqual(store.viewportFrame.height, 0.3 / activeSourceSize, accuracy: 0.000_000_000_001)
    }

    func testViewportCropSelectorProvesExactBaselineAndLargestInBothMotionModes() throws {
        let scene = SceneFrameFixtures.scene()
        for reduceMotion in [false, true] {
            XCTAssertEqual(
                try SceneViewportCropSelector.selectCropID(
                    scene: scene,
                    viewport: SceneFrameSize(width: 393, height: 852),
                    reduceMotion: reduceMotion
                ),
                "baseline-393x852"
            )
            XCTAssertEqual(
                try SceneViewportCropSelector.selectCropID(
                    scene: scene,
                    viewport: SceneFrameSize(width: 430, height: 932),
                    reduceMotion: reduceMotion
                ),
                "largest-430x932"
            )
        }
    }

    func testViewportCropSelectorUsesOnlyExplicitNearbyTolerance() throws {
        let scene = SceneFrameFixtures.scene()
        let nearbyBaselineNormal = try SceneViewportCropSelector.selectCropID(
            scene: scene,
            viewport: SceneFrameSize(width: 402, height: 874),
            reduceMotion: false
        )
        let nearbyBaselineReduced = try SceneViewportCropSelector.selectCropID(
            scene: scene,
            viewport: SceneFrameSize(width: 402, height: 874),
            reduceMotion: true
        )
        XCTAssertEqual(nearbyBaselineNormal, "baseline-393x852")
        XCTAssertEqual(nearbyBaselineReduced, nearbyBaselineNormal)

        let nearbyLargestNormal = try SceneViewportCropSelector.selectCropID(
            scene: scene,
            viewport: SceneFrameSize(width: 440, height: 956),
            reduceMotion: false
        )
        let nearbyLargestReduced = try SceneViewportCropSelector.selectCropID(
            scene: scene,
            viewport: SceneFrameSize(width: 440, height: 956),
            reduceMotion: true
        )
        XCTAssertEqual(nearbyLargestNormal, "largest-430x932")
        XCTAssertEqual(nearbyLargestReduced, nearbyLargestNormal)

        for uncovered in [
            SceneFrameSize(width: 410, height: 890),
            SceneFrameSize(width: 393, height: 828),
        ] {
            XCTAssertThrowsError(
                try SceneViewportCropSelector.selectCropID(
                    scene: scene,
                    viewport: uncovered,
                    reduceMotion: false
                )
            ) { error in
                XCTAssertEqual(
                    error as? SceneViewportCropSelectionError,
                    .insufficientAuthoredCoverage
                )
            }
        }
    }

    func testViewportCropSelectorRejectsInvalidAndLandscapeSurfaces() throws {
        let scene = SceneFrameFixtures.scene()
        for invalid in [
            SceneFrameSize(width: 0, height: 852),
            SceneFrameSize(width: .nan, height: 852),
            SceneFrameSize(width: 393, height: .infinity),
        ] {
            XCTAssertThrowsError(
                try SceneViewportCropSelector.selectCropID(
                    scene: scene,
                    viewport: invalid,
                    reduceMotion: false
                )
            ) { error in
                XCTAssertEqual(
                    error as? SceneViewportCropSelectionError,
                    .invalidViewportSize
                )
            }
        }
        for nonPortrait in [
            SceneFrameSize(width: 852, height: 393),
            SceneFrameSize(width: 430, height: 430),
        ] {
            XCTAssertThrowsError(
                try SceneViewportCropSelector.selectCropID(
                    scene: scene,
                    viewport: nonPortrait,
                    reduceMotion: true
                )
            ) { error in
                XCTAssertEqual(
                    error as? SceneViewportCropSelectionError,
                    .nonPortraitViewport
                )
            }
        }
    }

    func testViewportCropSelectorRejectsAmbiguityAndCropSetDrift() throws {
        let twin = SceneViewportCrop(
            id: "baseline-twin",
            viewport: SceneViewportSize(widthPoints: 393, heightPoints: 852),
            sourceRect: SceneFrameFixtures.baselineCrop.sourceRect,
            safeTextRegions: SceneFrameFixtures.baselineCrop.safeTextRegions
        )
        let ambiguous = SceneFrameFixtures.scene(
            sceneCrops: [SceneFrameFixtures.baselineCrop, twin],
            reducedCrops: [SceneFrameFixtures.baselineCrop, twin]
        )
        XCTAssertThrowsError(
            try SceneViewportCropSelector.selectCropID(
                scene: ambiguous,
                viewport: SceneFrameSize(width: 393, height: 852),
                reduceMotion: false
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneViewportCropSelectionError,
                .ambiguousSelection(["baseline-393x852", "baseline-twin"])
            )
        }

        let mismatched = SceneFrameFixtures.scene(
            sceneCrops: [SceneFrameFixtures.baselineCrop, SceneFrameFixtures.largestCrop],
            reducedCrops: [SceneFrameFixtures.baselineCrop]
        )
        XCTAssertThrowsError(
            try SceneViewportCropSelector.selectCropID(
                scene: mismatched,
                viewport: SceneFrameSize(width: 393, height: 852),
                reduceMotion: true
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneViewportCropSelectionError,
                .normalAndReducedCropSetsMismatch
            )
        }
    }

    func testViewportCropSelectorRejectsMalformedAuthoredSetsBeforeSelection() throws {
        let duplicate = SceneFrameFixtures.scene(
            sceneCrops: [
                SceneFrameFixtures.baselineCrop,
                SceneFrameFixtures.baselineCrop,
            ],
            reducedCrops: [SceneFrameFixtures.baselineCrop]
        )
        XCTAssertThrowsError(
            try SceneViewportCropSelector.selectCropID(
                scene: duplicate,
                viewport: SceneFrameSize(width: 393, height: 852),
                reduceMotion: false
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneViewportCropSelectionError,
                .duplicateAuthoredCropID("baseline-393x852")
            )
        }

        let empty = SceneFrameFixtures.scene(sceneCrops: [], reducedCrops: [])
        XCTAssertThrowsError(
            try SceneViewportCropSelector.selectCropID(
                scene: empty,
                viewport: SceneFrameSize(width: 393, height: 852),
                reduceMotion: false
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneViewportCropSelectionError,
                .emptyAuthoredCropSet(reduceMotion: false)
            )
        }
    }

    func testIdenticalInputProducesEquatableIdenticalPlan() throws {
        let scene = SceneFrameFixtures.scene()
        let request = SceneFrameFixtures.request(cameraProgress: 0.37, deterministicTick: 12_345)
        let inventory = try makeInventory(reversedInsertionOrder: true)
        let first = try SceneFramePlanner.plan(scene: scene, request: request, assets: inventory)

        for _ in 0 ..< 20 {
            XCTAssertEqual(
                try SceneFramePlanner.plan(scene: scene, request: request, assets: inventory),
                first
            )
        }
    }

    func testAuthoredOrderRemainsAuthoritativeWhenDepthsConflict() throws {
        let authoredDepths = [0.9, 0.1, 0.4]
        let scene = SceneFrameFixtures.scene(layerMutation: { layers in
            layers.enumerated().map { entry in
                let (index, layer) = entry
                return SceneLayerSpec(
                    id: layer.id,
                    order: layer.order,
                    assetPath: layer.assetPath,
                    frame: layer.frame,
                    depth: authoredDepths[index],
                    opacity: layer.opacity,
                    blendMode: layer.blendMode,
                    masks: layer.masks,
                    motion: layer.motion,
                    stateVariants: layer.stateVariants
                )
            }
        })

        let plan = try SceneFramePlanner.plan(
            scene: scene,
            request: SceneFrameFixtures.request(),
            assets: try makeInventory()
        )

        XCTAssertEqual(plan.drawCommands.map(\.authoredOrder), [0, 1, 2])
        XCTAssertEqual(plan.drawCommands.map(\.depth), authoredDepths)
    }

    func testCameraInterpolationIsPiecewiseLinearAndDeterministic() throws {
        let plan = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(cameraProgress: 0.25),
            assets: try makeInventory()
        )

        XCTAssertEqual(plan.camera.masterCenter.x, 0.425, accuracy: 0.000_000_000_001)
        XCTAssertEqual(plan.camera.masterCenter.y, 0.45, accuracy: 0.000_000_000_001)
        XCTAssertEqual(plan.camera.scale, 1.1, accuracy: 0.000_000_000_001)
    }

    func testActiveVariantSelectsItsCompleteAssetAndMaskSet() throws {
        let closed = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(variants: ["store": "closed"]),
            assets: try makeInventory()
        )
        let divided = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(variants: ["store": "divided"]),
            assets: try makeInventory()
        )
        let closedStore = try XCTUnwrap(closed.drawCommands.first { $0.authoredOrder == 1 })
        let dividedStore = try XCTUnwrap(divided.drawCommands.first { $0.authoredOrder == 1 })

        XCTAssertEqual(closedStore.source, .layer("store", variantID: "closed"))
        XCTAssertEqual(closedStore.asset.packagePath, "assets/store-closed.heif")
        XCTAssertEqual(closedStore.masks.alpha?.packagePath, "assets/store-closed-alpha.png")
        XCTAssertEqual(dividedStore.source, .layer("store", variantID: "divided"))
        XCTAssertEqual(dividedStore.asset.packagePath, "assets/store-divided.heif")
        XCTAssertEqual(dividedStore.masks.light?.packagePath, "assets/store-divided-light.png")
    }

    func testHitRegionMapsFromSceneCanvasIntoSelectedCrop() throws {
        let plan = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(),
            assets: try makeInventory()
        )
        let hit = try XCTUnwrap(plan.interactionHitRegions.first)

        XCTAssertEqual(hit.interactionTargetID, "grain-store")
        XCTAssertEqual(hit.layerID, "store")
        XCTAssertEqual(hit.accessibilityElementID, "divide-store")
        let activeSourceSize = 0.6 / 1.2
        let activeSourceOrigin = 0.5 - activeSourceSize / 2
        let parallaxX = (0.5 - 0.35) / activeSourceSize * 0.35
        let parallaxY = (0.5 - 0.4) / activeSourceSize * 0.35
        XCTAssertEqual(
            hit.viewportPath[0].x,
            (0.36 - activeSourceOrigin) / activeSourceSize + parallaxX,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(
            hit.viewportPath[0].y,
            (0.4 - activeSourceOrigin) / activeSourceSize + parallaxY,
            accuracy: 0.000_000_000_001
        )
    }

    func testReduceMotionUsesAuthoredStaticCompositionAndStopsTravel() throws {
        let scene = SceneFrameFixtures.scene()
        let moving = try SceneFramePlanner.plan(
            scene: scene,
            request: SceneFrameFixtures.request(deterministicTick: 180),
            assets: try makeInventory()
        )
        let reduced = try SceneFramePlanner.plan(
            scene: scene,
            request: SceneFrameFixtures.request(deterministicTick: 180, reduceMotion: true),
            assets: try makeInventory()
        )

        XCTAssertEqual(reduced.drawCommands.count, 3)
        XCTAssertEqual(reduced.drawCommands[0].source, .reduceMotionStaticStratum("world-underlay"))
        XCTAssertEqual(reduced.drawCommands[0].asset.packagePath, "assets/reduce-motion-underlay.heif")
        XCTAssertEqual(reduced.drawCommands[0].motion, .still)
        XCTAssertEqual(reduced.drawCommands[1].source, .layer("store", variantID: "divided"))
        XCTAssertEqual(reduced.drawCommands[1].asset.packagePath, "assets/store-divided.heif")
        XCTAssertEqual(reduced.drawCommands[2].source, .reduceMotionStaticStratum("foreground-occlusion"))
        XCTAssertEqual(reduced.drawCommands[2].asset.packagePath, "assets/reduce-motion-foreground.heif")
        XCTAssertTrue(reduced.drawCommands.allSatisfy { $0.motion == .still })
        XCTAssertFalse(reduced.camera.followsAuthoredRail)
        XCTAssertEqual(reduced.camera.viewportCenter, SceneFramePoint(x: 0.5, y: 0.5))
        XCTAssertEqual(reduced.atmosphere[0].travel, .zero)
        XCTAssertNotEqual(moving.atmosphere[0].travel, .zero)

        let reducedAtAnotherTick = try SceneFramePlanner.plan(
            scene: scene,
            request: SceneFrameFixtures.request(deterministicTick: 3_600, reduceMotion: true),
            assets: try makeInventory()
        )
        XCTAssertEqual(
            reduced.atmosphere.map(\.samples),
            reducedAtAnotherTick.atmosphere.map(\.samples)
        )

        let reducedClosed = try SceneFramePlanner.plan(
            scene: scene,
            request: SceneFrameFixtures.request(variants: ["store": "closed"], reduceMotion: true),
            assets: try makeInventory()
        )
        XCTAssertNotEqual(reduced.drawCommands, reducedClosed.drawCommands)
        XCTAssertEqual(reducedClosed.drawCommands[1].source, .layer("store", variantID: "closed"))
        XCTAssertTrue(reducedClosed.drawCommands.allSatisfy { $0.motion == .still })
    }

    func testRejectsUnknownAndMissingReducedViewportCrops() throws {
        XCTAssertThrowsError(
            try SceneFramePlanner.plan(
                scene: SceneFrameFixtures.scene(),
                request: SceneFrameFixtures.request(viewportCropID: "unknown-crop"),
                assets: try makeInventory()
            )
        ) { error in
            XCTAssertEqual(error as? SceneFramePlannerError, .unknownViewportCrop("unknown-crop"))
        }

        let baselineOnlyReduced = SceneFrameFixtures.scene(
            reducedCrops: [SceneFrameFixtures.baselineCrop]
        )
        XCTAssertThrowsError(
            try SceneFramePlanner.plan(
                scene: baselineOnlyReduced,
                request: SceneFrameFixtures.request(
                    viewportCropID: "largest-430x932",
                    reduceMotion: true
                ),
                assets: try makeInventory()
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneFramePlannerError,
                .missingReduceMotionViewportCrop("largest-430x932")
            )
        }
    }

    func testRejectsMissingUnknownAndUnexpectedVariants() throws {
        XCTAssertThrowsError(
            try SceneFramePlanner.plan(
                scene: SceneFrameFixtures.scene(),
                request: SceneFrameFixtures.request(variants: [:]),
                assets: try makeInventory()
            )
        ) { error in
            XCTAssertEqual(error as? SceneFramePlannerError, .missingLayerVariant("store"))
        }
        XCTAssertThrowsError(
            try SceneFramePlanner.plan(
                scene: SceneFrameFixtures.scene(),
                request: SceneFrameFixtures.request(variants: ["store": "invented"]),
                assets: try makeInventory()
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneFramePlannerError,
                .unknownLayerVariant(layerID: "store", variantID: "invented")
            )
        }
        XCTAssertThrowsError(
            try SceneFramePlanner.plan(
                scene: SceneFrameFixtures.scene(),
                request: SceneFrameFixtures.request(
                    variants: ["store": "divided", "background": "invented"]
                ),
                assets: try makeInventory()
            )
        ) { error in
            XCTAssertEqual(error as? SceneFramePlannerError, .unexpectedLayerVariant("background"))
        }

        for insertionOrder in [["zeta", "alpha"], ["alpha", "zeta"]] {
            var variants: [SceneLayerID: String] = ["store": "divided"]
            for layerID in insertionOrder {
                variants[SceneLayerID(layerID)] = "invented"
            }
            XCTAssertThrowsError(
                try SceneFramePlanner.plan(
                    scene: SceneFrameFixtures.scene(),
                    request: SceneFrameFixtures.request(variants: variants),
                    assets: try makeInventory()
                )
            ) { error in
                XCTAssertEqual(error as? SceneFramePlannerError, .unexpectedLayerVariant("alpha"))
            }
        }
    }

    func testVerifiedPackageInventoryRejectsUnsafeSceneAssetPath() throws {
        let root = try makeTemporaryPackageRoot()
        for path in SceneFrameFixtures.assetPaths {
            _ = try writeAsset(path, under: root)
        }
        let unsafeScene = SceneFrameFixtures.scene(
            backgroundAssetPath: "../outside-package.heif"
        )
        let verified = try makeVerifiedPackage(root: root, scene: unsafeScene)

        XCTAssertThrowsError(
            try SceneAssetInventory(
                verifiedPackage: verified,
                activatedPackageRoot: root
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneAssetInventoryError,
                .unsafePackagePath("../outside-package.heif")
            )
        }
    }

    func testVerifiedPackageInventoryRejectsDirectoryReplacingSignedAsset() throws {
        let root = try makeTemporaryPackageRoot()
        for path in SceneFrameFixtures.assetPaths {
            _ = try writeAsset(path, under: root)
        }
        let verified = try makeVerifiedPackage(root: root)
        let backgroundURL = root.appending(
            path: "assets/background.heif",
            directoryHint: .notDirectory
        )
        try FileManager.default.removeItem(at: backgroundURL)
        try FileManager.default.createDirectory(at: backgroundURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(
            try SceneAssetInventory(
                verifiedPackage: verified,
                activatedPackageRoot: root
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneAssetInventoryError,
                .assetIsNotRegularFile("assets/background.heif")
            )
        }
    }

    func testVerifiedPackageInventoryRejectsDuplicateSignedManifestBinding() throws {
        let root = try makeTemporaryPackageRoot()
        for path in SceneFrameFixtures.assetPaths {
            _ = try writeAsset(path, under: root)
        }
        let verified = try makeVerifiedPackage(root: root)
        let duplicateRecord = try XCTUnwrap(
            verified.manifest.files.first { $0.path == "assets/background.heif" }
        )
        let manifest = SignedPackageManifest(
            packageID: verified.manifest.packageID,
            packageVersion: verified.manifest.packageVersion,
            schemaVersion: verified.manifest.schemaVersion,
            minimumRuntime: verified.manifest.minimumRuntime,
            files: verified.manifest.files + [duplicateRecord],
            manifestDigest: verified.manifest.manifestDigest,
            signature: verified.manifest.signature
        )
        let duplicate = VerifiedContentPackage(manifest: manifest, payload: verified.payload)

        XCTAssertThrowsError(
            try SceneAssetInventory(
                verifiedPackage: duplicate,
                activatedPackageRoot: root
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneAssetInventoryError,
                .duplicateManifestRecord("assets/background.heif")
            )
        }
    }

    func testVerifiedPackageInventoryRejectsSymlinkEscapeBeforeConstruction() throws {
        let root = try makeTemporaryPackageRoot()
        for path in SceneFrameFixtures.assetPaths {
            _ = try writeAsset(path, under: root)
        }
        let verified = try makeVerifiedPackage(root: root)
        let outsideRoot = try makeTemporaryPackageRoot()
        let outsideFile = try writeAsset("same-signed-bytes.heif", under: outsideRoot)
        let link = root.appending(
            path: "assets/background.heif",
            directoryHint: .notDirectory
        )
        try FileManager.default.removeItem(at: link)
        do {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)
        } catch {
            throw XCTSkip("Symbolic links are unavailable in this test environment: \(error)")
        }

        XCTAssertThrowsError(
            try SceneAssetInventory(
                verifiedPackage: verified,
                activatedPackageRoot: root
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneAssetInventoryError,
                .assetIsSymbolicLink("assets/background.heif")
            )
        }
    }

    func testRejectsAmbiguousLayerIdentityAndAuthoredOrder() throws {
        XCTAssertThrowsError(
            try SceneFramePlanner.plan(
                scene: SceneFrameFixtures.scene(layerMutation: { $0 + [$0[0]] }),
                request: SceneFrameFixtures.request(),
                assets: try makeInventory()
            )
        ) { error in
            XCTAssertEqual(error as? SceneFramePlannerError, .ambiguousLayer("background"))
        }

        let duplicateOrder = SceneLayerSpec(
            id: "veil",
            order: 1,
            assetPath: "assets/foreground.heif",
            frame: NormalizedRect(x: 0, y: 0.72, width: 1, height: 0.28),
            depth: 0.7,
            motion: SceneLayerMotion(parallaxFactor: 0.2)
        )
        XCTAssertThrowsError(
            try SceneFramePlanner.plan(
                scene: SceneFrameFixtures.scene(layerMutation: { [$0[0], $0[1], duplicateOrder] }),
                request: SceneFrameFixtures.request(),
                assets: try makeInventory()
            )
        ) { error in
            XCTAssertEqual(error as? SceneFramePlannerError, .ambiguousLayerOrder(1))
        }
    }

    func testRejectsInvalidCameraProgressAndInvalidViewport() throws {
        XCTAssertThrowsError(
            try SceneFramePlanner.plan(
                scene: SceneFrameFixtures.scene(),
                request: SceneFrameFixtures.request(cameraProgress: .nan),
                assets: try makeInventory()
            )
        ) { error in
            XCTAssertEqual(error as? SceneFramePlannerError, .invalidCameraProgress)
        }

        let invalidCrop = SceneViewportCrop(
            id: "baseline-393x852",
            viewport: SceneViewportSize(widthPoints: 0, heightPoints: 852),
            sourceRect: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
            safeTextRegions: SceneFrameFixtures.baselineCrop.safeTextRegions
        )
        XCTAssertThrowsError(
            try SceneFramePlanner.plan(
                scene: SceneFrameFixtures.scene(sceneCrops: [invalidCrop, SceneFrameFixtures.largestCrop]),
                request: SceneFrameFixtures.request(),
                assets: try makeInventory()
            )
        ) { error in
            XCTAssertEqual(error as? SceneFramePlannerError, .invalidViewport("baseline-393x852"))
        }
    }

    func testTouchGeometryUsesTheExactDisplayedCameraAndLayerMotion() throws {
        let plan = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(cameraProgress: 0.37, deterministicTick: 77),
            assets: try makeInventory()
        )
        let store = try XCTUnwrap(plan.drawCommands.first { command in
            command.source == .layer("store", variantID: "divided")
        })
        let expected = NormalizedPoint(x: 0.5, y: 0.5)
        let viewport = SceneFramePoint(
            x: (expected.x - plan.camera.sourceRect.x) / plan.camera.sourceRect.width
                + store.motion.parallaxOffset.dx + store.motion.windOffset.dx,
            y: (expected.y - plan.camera.sourceRect.y) / plan.camera.sourceRect.height
                + store.motion.parallaxOffset.dy + store.motion.windOffset.dy
        )

        let resolved = try SceneTouchGeometryResolver.masterPoint(
            for: viewport,
            in: plan,
            boundTo: "store"
        )
        XCTAssertEqual(resolved.x, expected.x, accuracy: 0.000_000_000_001)
        XCTAssertEqual(resolved.y, expected.y, accuracy: 0.000_000_000_001)
    }

    func testTouchTargetUsesTheSameViewportPolygonAsTheFrame() throws {
        let plan = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(),
            assets: try makeInventory()
        )
        let region = try XCTUnwrap(plan.interactionHitRegions.first)
        let point = centroid(region.viewportPath)
        let hit = try XCTUnwrap(
            SceneTouchGeometryResolver.target(at: point, in: plan)
        )

        XCTAssertEqual(hit.interactionTargetID, "grain-store")
        XCTAssertEqual(hit.accessibilityElementID, "divide-store")
        XCTAssertEqual(hit.layerID, "store")
        XCTAssertTrue(hit.masterPosition.isUnitPoint)
        XCTAssertNil(
            try SceneTouchGeometryResolver.target(
                at: SceneFramePoint(x: 0.01, y: 0.01),
                in: plan
            )
        )
    }

    func testSourceContactRequiresTheSelectedVariantAlphaMask() throws {
        let base = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(),
            assets: try makeInventory()
        )
        let store = try XCTUnwrap(base.drawCommands.first { command in
            command.source == .layer("store", variantID: "divided")
        })
        let mask = try XCTUnwrap(store.masks.alpha)
        let target = try XCTUnwrap(base.interactionHitRegions.first)
        let source = SceneInteractionSourceHitRegionPlan(
            interactionID: "allocate-test",
            layerID: "store",
            hitTest: .selectedVariantAlpha,
            viewportPath: target.viewportPath,
            selectedVariantAlphaMask: mask
        )
        let plan = replacingInteractionGeometry(base, source: source)
        let point = centroid(source.viewportPath)

        let contact = try SceneTouchGeometryResolver.sourceContact(
            at: point,
            in: plan,
            alphaSampler: FixedAlphaSampler(opaque: true)
        )
        XCTAssertEqual(contact.interactionID, "allocate-test")
        XCTAssertEqual(contact.layerID, "store")
        XCTAssertTrue(contact.masterPosition.isUnitPoint)
        XCTAssertTrue(contact.alphaMaskPosition.isUnitPoint)

        XCTAssertThrowsError(
            try SceneTouchGeometryResolver.sourceContact(
                at: point,
                in: plan,
                alphaSampler: FixedAlphaSampler(opaque: false)
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneTouchGeometryError,
                .sourceAlphaRejected
            )
        }
    }

    func testTouchGeometryRejectsInvalidAndAmbiguousViewportInput() throws {
        let base = try SceneFramePlanner.plan(
            scene: SceneFrameFixtures.scene(),
            request: SceneFrameFixtures.request(),
            assets: try makeInventory()
        )
        XCTAssertThrowsError(
            try SceneTouchGeometryResolver.target(
                at: SceneFramePoint(x: .nan, y: 0.5),
                in: base
            )
        ) { error in
            XCTAssertEqual(error as? SceneTouchGeometryError, .invalidViewportPoint)
        }

        let original = try XCTUnwrap(base.interactionHitRegions.first)
        let duplicate = SceneInteractionHitRegionPlan(
            interactionTargetID: "duplicate",
            layerID: original.layerID,
            accessibilityElementID: "duplicate-action",
            viewportPath: original.viewportPath
        )
        let ambiguous = SceneFramePlan(
            sceneID: base.sceneID,
            viewportCropID: base.viewportCropID,
            viewport: base.viewport,
            deterministicTick: base.deterministicTick,
            reduceMotion: base.reduceMotion,
            camera: base.camera,
            drawCommands: base.drawCommands,
            atmosphere: base.atmosphere,
            interactionSourceHitRegion: base.interactionSourceHitRegion,
            interactionHitRegions: [original, duplicate],
            interactionResponse: base.interactionResponse,
            safeTextRegions: base.safeTextRegions
        )
        XCTAssertThrowsError(
            try SceneTouchGeometryResolver.target(
                at: centroid(original.viewportPath),
                in: ambiguous
            )
        ) { error in
            XCTAssertEqual(error as? SceneTouchGeometryError, .ambiguousTarget)
        }
    }

    private func centroid(_ points: [SceneFramePoint]) -> SceneFramePoint {
        SceneFramePoint(
            x: points.reduce(0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0) { $0 + $1.y } / Double(points.count)
        )
    }

    private func replacingInteractionGeometry(
        _ frame: SceneFramePlan,
        source: SceneInteractionSourceHitRegionPlan
    ) -> SceneFramePlan {
        SceneFramePlan(
            sceneID: frame.sceneID,
            viewportCropID: frame.viewportCropID,
            viewport: frame.viewport,
            deterministicTick: frame.deterministicTick,
            reduceMotion: frame.reduceMotion,
            camera: frame.camera,
            drawCommands: frame.drawCommands,
            atmosphere: frame.atmosphere,
            interactionSourceHitRegion: source,
            interactionHitRegions: frame.interactionHitRegions,
            interactionResponse: frame.interactionResponse,
            safeTextRegions: frame.safeTextRegions
        )
    }

    private func makeInventory(
        reversedInsertionOrder: Bool = false
    ) throws -> SceneAssetInventory {
        let root = try makeTemporaryPackageRoot()
        let paths = SceneFrameFixtures.assetPaths
        let orderedPaths = reversedInsertionOrder ? Array(paths.reversed()) : paths
        for path in orderedPaths {
            _ = try writeAsset(path, under: root)
        }
        return try SceneAssetInventory(
            verifiedPackage: makeVerifiedPackage(root: root),
            activatedPackageRoot: root
        )
    }

    private func makeVerifiedPackage(
        root: URL,
        manifestPaths: [String] = SceneFrameFixtures.assetPaths,
        scene: SceneSpec = SceneFrameFixtures.scene()
    ) throws -> VerifiedContentPackage {
        let records = try manifestPaths.sorted().map { path -> PackageFileRecord in
            let data = try Data(
                contentsOf: root.appending(path: path, directoryHint: .notDirectory)
            )
            return PackageFileRecord(
                path: path,
                bytes: Int64(data.count),
                sha256: SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }
                    .joined()
            )
        }
        let version = SchemaVersion(major: 1)
        let packageID: PackageID = "phase-one-test-package"
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
        return VerifiedContentPackage(manifest: manifest, payload: payload)
    }

    private func makeTemporaryPackageRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "scene-runtime-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func writeAsset(_ packagePath: String, under root: URL) throws -> URL {
        let fileURL = root.appending(path: packagePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x01]).write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private struct FixedAlphaSampler: SceneAlphaMaskSampling {
    let opaque: Bool

    func isOpaque(
        in alphaMask: SceneResolvedAsset,
        at unitPoint: NormalizedPoint
    ) throws -> Bool {
        _ = alphaMask
        return opaque && unitPoint.isUnitPoint
    }
}

private enum SceneFrameFixtures {
    static let baselineCrop = SceneViewportCrop(
        id: "baseline-393x852",
        viewport: SceneViewportSize(widthPoints: 393, heightPoints: 852),
        sourceRect: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
        safeTextRegions: [
            SceneSafeTextRegion(
                id: "opening-copy",
                rect: NormalizedRect(x: 0.08, y: 0.08, width: 0.5, height: 0.18)
            ),
        ]
    )

    static let largestCrop = SceneViewportCrop(
        id: "largest-430x932",
        viewport: SceneViewportSize(widthPoints: 430, heightPoints: 932),
        sourceRect: NormalizedRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
        safeTextRegions: [
            SceneSafeTextRegion(
                id: "opening-copy",
                rect: NormalizedRect(x: 0.08, y: 0.08, width: 0.5, height: 0.18)
            ),
        ]
    )

    static let assetPaths = [
        "assets/reduce-motion-underlay.heif",
        "assets/reduce-motion-foreground.heif",
        "assets/background.heif",
        "assets/background-depth.png",
        "assets/store.heif",
        "assets/store-alpha.png",
        "assets/store-closed.heif",
        "assets/store-closed-alpha.png",
        "assets/store-divided.heif",
        "assets/store-divided-alpha.png",
        "assets/store-divided-light.png",
        "assets/foreground.heif",
        "assets/foreground-occlusion.png",
    ]

    static func scene(
        sceneCrops: [SceneViewportCrop] = [baselineCrop, largestCrop],
        reducedCrops: [SceneViewportCrop] = [baselineCrop, largestCrop],
        backgroundAssetPath: String = "assets/background.heif",
        layerMutation: ([SceneLayerSpec]) -> [SceneLayerSpec] = { $0 }
    ) -> SceneSpec {
        SceneSpec(
            id: "harvest-store",
            sceneCanvas: SceneCanvasSpec(
                canvas: ScenePixelSize(width: 1_179, height: 2_556),
                cameraTravelBounds: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                authoredOverscanFraction: 0.15,
                viewportCrops: sceneCrops
            ),
            layers: layerMutation([
                SceneLayerSpec(
                    id: "background",
                    order: 0,
                    assetPath: backgroundAssetPath,
                    frame: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                    depth: 0.1,
                    masks: SceneLayerMaskSet(depthMaskAssetPath: "assets/background-depth.png"),
                    motion: SceneLayerMotion(parallaxFactor: 0.1, windResponse: 0.2)
                ),
                SceneLayerSpec(
                    id: "store",
                    order: 1,
                    assetPath: "assets/store.heif",
                    frame: NormalizedRect(x: 0.3, y: 0.35, width: 0.4, height: 0.3),
                    depth: 0.7,
                    masks: SceneLayerMaskSet(alphaMaskAssetPath: "assets/store-alpha.png"),
                    motion: SceneLayerMotion(
                        parallaxFactor: 0.35,
                        windResponse: 0,
                        focusResponse: 0.4
                    ),
                    stateVariants: [
                        SceneLayerStateVariant(
                            id: "closed",
                            assetPath: "assets/store-closed.heif",
                            masks: SceneLayerMaskSet(
                                alphaMaskAssetPath: "assets/store-closed-alpha.png"
                            )
                        ),
                        SceneLayerStateVariant(
                            id: "divided",
                            assetPath: "assets/store-divided.heif",
                            masks: SceneLayerMaskSet(
                                alphaMaskAssetPath: "assets/store-divided-alpha.png",
                                lightMaskAssetPath: "assets/store-divided-light.png"
                            )
                        ),
                    ]
                ),
                SceneLayerSpec(
                    id: "foreground",
                    order: 2,
                    assetPath: "assets/foreground.heif",
                    frame: NormalizedRect(x: 0, y: 0.72, width: 1, height: 0.28),
                    depth: 0.7,
                    masks: SceneLayerMaskSet(
                        occlusionMaskAssetPath: "assets/foreground-occlusion.png"
                    ),
                    motion: SceneLayerMotion(parallaxFactor: 0.6, windResponse: 0.3)
                ),
            ]),
            cameraRail: CameraRail(
                keyframes: [
                    CameraKeyframe(
                        progress: 0,
                        center: NormalizedPoint(x: 0.35, y: 0.4),
                        scale: 1
                    ),
                    CameraKeyframe(
                        progress: 0.5,
                        center: NormalizedPoint(x: 0.5, y: 0.5),
                        scale: 1.2
                    ),
                    CameraKeyframe(
                        progress: 1,
                        center: NormalizedPoint(x: 0.65, y: 0.6),
                        scale: 1.4
                    ),
                ]
            ),
            atmosphere: [
                AtmosphereSpec(
                    kind: .dust,
                    density: 0.5,
                    velocity: SignedUnitVector(dx: -0.25, dy: 0.1),
                    deterministicSeed: 41
                ),
            ],
            interactionTargets: [
                SceneInteractionTargetBinding(
                    interactionTargetID: "grain-store",
                    layerID: "store",
                    hitRegion: SceneHitRegion(
                        path: [
                            NormalizedPoint(x: 0.36, y: 0.4),
                            NormalizedPoint(x: 0.64, y: 0.4),
                            NormalizedPoint(x: 0.64, y: 0.6),
                            NormalizedPoint(x: 0.36, y: 0.6),
                        ]
                    ),
                    accessibilityElementID: "divide-store"
                ),
            ],
            reduceMotionComposition: ReduceMotionComposition(
                canvas: ScenePixelSize(width: 1_179, height: 2_556),
                viewportCrops: reducedCrops,
                strata: [
                    ReduceMotionStratum(
                        id: "world-underlay",
                        kind: .staticPlate,
                        assetPath: "assets/reduce-motion-underlay.heif"
                    ),
                    ReduceMotionStratum(
                        id: "store-state",
                        kind: .stateOverlay,
                        layerID: "store"
                    ),
                    ReduceMotionStratum(
                        id: "foreground-occlusion",
                        kind: .staticPlate,
                        assetPath: "assets/reduce-motion-foreground.heif"
                    ),
                ]
            ),
            mechanismFocus: LocalizedStringSpec(
                id: "scene-harvest-store-mechanism-focus",
                launchEnglish: "grain divided between present food, reserve and seed"
            ),
            accessibilityID: "access-harvest-store"
        )
    }

    static func request(
        viewportCropID: String = "baseline-393x852",
        cameraProgress: Double = 0.5,
        variants: [SceneLayerID: String] = ["store": "divided"],
        deterministicTick: UInt64 = 120,
        reduceMotion: Bool = false
    ) -> SceneFrameRequest {
        SceneFrameRequest(
            viewportCropID: viewportCropID,
            cameraProgress: cameraProgress,
            visualState: SceneInteractionVisualState(
                activeLayerVariants: variants,
                directManipulation: nil
            ),
            deterministicTick: deterministicTick,
            reduceMotion: reduceMotion
        )
    }

}
