import CryptoKit
import Foundation
import Metal
@testable import ContentKit
@testable import SceneRuntime
import XCTest

final class SceneMetalCompositorTests: XCTestCase {
    func testPreparationPreservesAuthoredOrderTransformsAndEveryMaskHook() throws {
        let fixture = try makeFixture()
        let frame = try fixture.frame(reduceMotion: false)
        let preparation = try SceneMetalPreparationPlanner.make(from: frame)

        XCTAssertEqual(preparation.sceneID, frame.sceneID)
        XCTAssertEqual(preparation.viewport, SceneFrameSize(width: 393, height: 852))
        XCTAssertEqual(preparation.deterministicTick, 240)
        XCTAssertFalse(preparation.reduceMotion)
        XCTAssertEqual(preparation.drawCommands.map(\.authoredOrder), [0, 1])
        XCTAssertEqual(preparation.drawCommands.map(\.source), frame.drawCommands.map(\.source))
        XCTAssertEqual(
            preparation.drawCommands.map(\.viewportFrame),
            frame.drawCommands.map(\.viewportFrame)
        )
        XCTAssertEqual(preparation.drawCommands.map(\.motion), frame.drawCommands.map(\.motion))
        XCTAssertEqual(
            preparation.textureRequests.map(\.key.packagePath),
            [
                "assets/background.png",
                "assets/mechanism.png",
                "assets/mechanism-alpha.png",
                "assets/mechanism-occlusion.png",
                "assets/mechanism-depth.png",
                "assets/mechanism-light.png",
            ]
        )
        XCTAssertEqual(
            preparation.textureRequests.map(\.key.sampling),
            [.colorSRGB, .colorSRGB, .linearMask, .linearMask, .linearMask, .linearMask]
        )

        let mechanism = try XCTUnwrap(preparation.drawCommands.last)
        XCTAssertEqual(mechanism.blendMode, .screen)
        XCTAssertEqual(mechanism.masks.alpha?.packagePath, "assets/mechanism-alpha.png")
        XCTAssertEqual(
            mechanism.masks.occlusion?.packagePath,
            "assets/mechanism-occlusion.png"
        )
        XCTAssertEqual(mechanism.masks.depth?.packagePath, "assets/mechanism-depth.png")
        XCTAssertEqual(mechanism.masks.light?.packagePath, "assets/mechanism-light.png")
        XCTAssertTrue(mechanism.masks.all.allSatisfy { $0.sampling == .linearMask })
    }

    func testPreparationIsEquatableDeterministic() throws {
        let fixture = try makeFixture()
        let frame = try fixture.frame(reduceMotion: false)
        let first = try SceneMetalPreparationPlanner.make(from: frame)

        for _ in 0 ..< 20 {
            XCTAssertEqual(try SceneMetalPreparationPlanner.make(from: frame), first)
        }
    }

    func testDirectManipulationMovesOnlyTheAuthoredTransferLayer() throws {
        let fixture = try makeFixture()
        let frame = try fixture.frame(reduceMotion: false)
        let response = SceneInteractionResponsePlan(
            phase: .carrying,
            targetID: nil,
            transferLayerID: "mechanism",
            viewportMaterialPosition: SceneFramePoint(x: 0.78, y: 0.62),
            viewportTransferPath: [],
            progress: 0.4,
            contactAmount: 0.15,
            resistanceAmount: 0
        )
        let interactive = SceneFramePlan(
            sceneID: frame.sceneID,
            viewportCropID: frame.viewportCropID,
            viewport: frame.viewport,
            deterministicTick: frame.deterministicTick,
            reduceMotion: frame.reduceMotion,
            camera: frame.camera,
            drawCommands: frame.drawCommands,
            atmosphere: frame.atmosphere,
            interactionSourceHitRegion: frame.interactionSourceHitRegion,
            interactionHitRegions: frame.interactionHitRegions,
            interactionResponse: response,
            safeTextRegions: frame.safeTextRegions
        )
        let preparation = try SceneMetalPreparationPlanner.make(from: interactive)
        let background = try XCTUnwrap(preparation.drawCommands.first)
        let mechanism = try XCTUnwrap(preparation.drawCommands.last)

        XCTAssertEqual(background.interactionOffset, .zero)
        XCTAssertEqual(background.interactionContactAmount, 0)
        XCTAssertEqual(background.interactionResistanceAmount, 0)
        XCTAssertEqual(
            mechanism.interactionOffset.dx,
            0.78 - (mechanism.viewportFrame.x + mechanism.viewportFrame.width * 0.5),
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(
            mechanism.interactionOffset.dy,
            0.62 - (mechanism.viewportFrame.y + mechanism.viewportFrame.height * 0.5),
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(mechanism.interactionContactAmount, 0.15)
        XCTAssertEqual(mechanism.interactionResistanceAmount, 0)
    }

    func testReduceMotionKeepsStaticContactAndResistanceWithoutTransport() throws {
        let fixture = try makeFixture()
        let normal = try fixture.frame(reduceMotion: false)
        let reduced = try fixture.frame(reduceMotion: true)
        let staticPlate = try XCTUnwrap(reduced.drawCommands.first)
        let source = try XCTUnwrap(normal.drawCommands.last)
        let stateOverlay = SceneDrawCommand(
            source: source.source,
            authoredOrder: 1,
            depth: source.depth,
            asset: source.asset,
            masks: source.masks,
            masterFrame: source.masterFrame,
            viewportFrame: source.viewportFrame,
            opacity: source.opacity,
            blendMode: source.blendMode,
            motion: .still
        )
        let response = SceneInteractionResponsePlan(
            phase: .snapBack,
            targetID: "mechanism-slot",
            transferLayerID: "mechanism",
            viewportMaterialPosition: SceneFramePoint(x: 0.8, y: 0.8),
            viewportTransferPath: [
                SceneFramePoint(x: 0.8, y: 0.8),
                SceneFramePoint(x: 0.5, y: 0.5),
            ],
            progress: 1,
            contactAmount: 0.8,
            resistanceAmount: 1
        )
        let frame = SceneFramePlan(
            sceneID: reduced.sceneID,
            viewportCropID: reduced.viewportCropID,
            viewport: reduced.viewport,
            deterministicTick: reduced.deterministicTick,
            reduceMotion: true,
            camera: reduced.camera,
            drawCommands: [staticPlate, stateOverlay],
            atmosphere: reduced.atmosphere,
            interactionSourceHitRegion: nil,
            interactionHitRegions: [],
            interactionResponse: response,
            safeTextRegions: reduced.safeTextRegions
        )

        let preparation = try SceneMetalPreparationPlanner.make(from: frame)
        let preparedStatic = try XCTUnwrap(preparation.drawCommands.first)
        let preparedOverlay = try XCTUnwrap(preparation.drawCommands.last)
        XCTAssertEqual(preparedStatic.interactionOffset, .zero)
        XCTAssertEqual(preparedStatic.interactionContactAmount, 0)
        XCTAssertEqual(preparedStatic.interactionResistanceAmount, 0)
        XCTAssertEqual(preparedOverlay.interactionOffset, .zero)
        XCTAssertEqual(preparedOverlay.interactionContactAmount, 0.8)
        XCTAssertEqual(preparedOverlay.interactionResistanceAmount, 1)
    }

    func testAcceptedDurableVariantIsNeverOffsetAgain() throws {
        let fixture = try makeFixture()
        let base = try fixture.frame(reduceMotion: false)
        let response = SceneInteractionResponsePlan(
            phase: .accepted,
            targetID: "mechanism-slot",
            transferLayerID: "mechanism",
            viewportTransferLayerAnchor: SceneFramePoint(x: 0.25, y: 0.25),
            viewportMaterialPosition: nil,
            viewportTransferPath: [],
            progress: 1,
            contactAmount: 1,
            resistanceAmount: 0
        )
        let frame = SceneFramePlan(
            sceneID: base.sceneID,
            viewportCropID: base.viewportCropID,
            viewport: base.viewport,
            deterministicTick: base.deterministicTick,
            reduceMotion: false,
            camera: base.camera,
            drawCommands: base.drawCommands,
            atmosphere: base.atmosphere,
            interactionSourceHitRegion: base.interactionSourceHitRegion,
            interactionHitRegions: base.interactionHitRegions,
            interactionResponse: response,
            safeTextRegions: base.safeTextRegions
        )

        let preparation = try SceneMetalPreparationPlanner.make(from: frame)
        let mechanism = try XCTUnwrap(preparation.drawCommands.last)
        XCTAssertEqual(mechanism.interactionOffset, .zero)
        XCTAssertEqual(mechanism.interactionContactAmount, 1)
    }

    func testReduceMotionUsesTheAuthoredStaticCompositionWithoutMotion() throws {
        let fixture = try makeFixture()
        let frame = try fixture.frame(reduceMotion: true)
        let preparation = try SceneMetalPreparationPlanner.make(from: frame)

        XCTAssertTrue(preparation.reduceMotion)
        XCTAssertEqual(preparation.drawCommands.count, 1)
        XCTAssertEqual(
            preparation.drawCommands[0].source,
            .reduceMotionStaticStratum("reduced-static")
        )
        XCTAssertEqual(preparation.drawCommands[0].motion, .still)
        XCTAssertEqual(preparation.drawCommands[0].interactionOffset, .zero)
        XCTAssertEqual(
            preparation.textureRequests.map(\.key.packagePath),
            ["assets/reduced.png"]
        )
        XCTAssertTrue(preparation.atmosphere.allSatisfy { $0.travel == .zero })
    }

    func testMalformedReduceMotionPlanFailsClosed() throws {
        let fixture = try makeFixture()
        let reduced = try fixture.frame(reduceMotion: true)
        let original = try XCTUnwrap(reduced.drawCommands.first)
        let moving = SceneDrawCommand(
            source: original.source,
            authoredOrder: original.authoredOrder,
            depth: original.depth,
            asset: original.asset,
            masks: original.masks,
            masterFrame: original.masterFrame,
            viewportFrame: original.viewportFrame,
            opacity: original.opacity,
            blendMode: original.blendMode,
            motion: SceneLayerMotionState(
                parallaxOffset: SceneFrameVector(dx: 0.01, dy: 0),
                windOffset: .zero,
                focusAmount: 0
            )
        )
        let malformed = copy(reduced, drawCommands: [moving])

        XCTAssertThrowsError(try SceneMetalPreparationPlanner.make(from: malformed)) { error in
            XCTAssertEqual(
                error as? SceneMetalPreparationError,
                .reduceMotionContainsMotion(0)
            )
        }
    }

    func testAuthoredOrderCannotBeResortedOrAmbiguous() throws {
        let fixture = try makeFixture()
        let frame = try fixture.frame(reduceMotion: false)
        let first = frame.drawCommands[0]
        let second = frame.drawCommands[1]
        let duplicate = SceneDrawCommand(
            source: second.source,
            authoredOrder: first.authoredOrder,
            depth: second.depth,
            asset: second.asset,
            masks: second.masks,
            masterFrame: second.masterFrame,
            viewportFrame: second.viewportFrame,
            opacity: second.opacity,
            blendMode: second.blendMode,
            motion: second.motion
        )

        XCTAssertThrowsError(
            try SceneMetalPreparationPlanner.make(
                from: copy(frame, drawCommands: [first, duplicate])
            )
        ) { error in
            XCTAssertEqual(error as? SceneMetalPreparationError, .ambiguousAuthoredOrder(0))
        }
        XCTAssertThrowsError(
            try SceneMetalPreparationPlanner.make(
                from: copy(frame, drawCommands: [second, first])
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneMetalPreparationError,
                .unorderedAuthoredOrder(previous: 1, next: 0)
            )
        }
    }

    func testTextureResolutionRequiresTheExactCompleteSet() throws {
        let fixture = try makeFixture()
        let preparation = try SceneMetalPreparationPlanner.make(
            from: fixture.frame(reduceMotion: false)
        )
        let required = preparation.textureRequests.map(\.key)

        XCTAssertNoThrow(
            try SceneMetalTextureResolutionGate.validate(
                required: required,
                resolved: Array(required.reversed())
            )
        )
        XCTAssertThrowsError(
            try SceneMetalTextureResolutionGate.validate(
                required: required,
                resolved: Array(required.dropLast())
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneMetalTextureResolutionError,
                .missingTexture(try! XCTUnwrap(required.last))
            )
        }
        XCTAssertThrowsError(
            try SceneMetalTextureResolutionGate.validate(
                required: Array(required.dropLast()),
                resolved: required
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneMetalTextureResolutionError,
                .unexpectedTexture(try! XCTUnwrap(required.last))
            )
        }
        XCTAssertThrowsError(
            try SceneMetalTextureResolutionGate.validate(
                required: required,
                resolved: required + [required[0]]
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneMetalTextureResolutionError,
                .duplicateResolvedTexture(required[0])
            )
        }
    }

    func testConfigurationValidatorNamesEveryUnavailableResource() {
        XCTAssertEqual(SceneMetalConfigurationValidator.validate(.ready), .readyForScene)
        var availability = SceneMetalResourceAvailability.ready
        availability.screenPipeline = false
        XCTAssertEqual(
            SceneMetalConfigurationValidator.validate(availability),
            .failed(.blendPipelineCreationFailed(.screen))
        )
        availability = .ready
        availability.neutralMask = false
        XCTAssertEqual(
            SceneMetalConfigurationValidator.validate(availability),
            .failed(.neutralMaskCreationFailed)
        )
    }

    func testFailurePresentationIsVisibleAndCarriesStableDiagnostics() {
        let presentation = SceneMetalFallbackPresentation(
            failure: .assetVerificationFailed("assets/mechanism.png")
        )

        XCTAssertFalse(presentation.title.isEmpty)
        XCTAssertFalse(presentation.action.isEmpty)
        XCTAssertEqual(presentation.diagnosticCode, "SCENE_SIGNED_ASSET_REJECTED")
        XCTAssertEqual(presentation.backgroundRGBA.w, 1)
        XCTAssertGreaterThan(presentation.foregroundRGBA.x, presentation.backgroundRGBA.x)
    }

    @MainActor
    func testRealMetalConfigurationAndSignedTexturePreparationWhenAvailable() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("The current test host exposes no Metal device.")
        }
        let fixture = try makeFixture()
        let frame = try fixture.frame(reduceMotion: false)
        let compositor = SceneMetalCompositor()

        XCTAssertEqual(compositor.configure(device: device), .readyForScene)
        let preparedState = await compositor.prepare(frame)
        XCTAssertEqual(
            preparedState,
            .sceneReady(sceneID: frame.sceneID, deterministicTick: 240, reduceMotion: false)
        )
    }

    @MainActor
    func testAssetReplacementAfterInventoryConstructionCannotReachMetal() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("The current test host exposes no Metal device.")
        }
        let fixture = try makeFixture()
        let frame = try fixture.frame(reduceMotion: false)
        try Data([0x00]).write(
            to: fixture.root.appending(path: "assets/mechanism.png"),
            options: .atomic
        )
        let compositor = SceneMetalCompositor()
        XCTAssertEqual(compositor.configure(device: device), .readyForScene)

        let preparedState = await compositor.prepare(frame)
        XCTAssertEqual(
            preparedState,
            .failed(.assetVerificationFailed("assets/mechanism.png"))
        )
    }

    @MainActor
    func testPerFrameUpdateUsesPreparedTexturesWithoutReadingPackageFiles() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("The current test host exposes no Metal device.")
        }
        let fixture = try makeFixture()
        let initialFrame = try fixture.frame(reduceMotion: false)
        let compositor = SceneMetalCompositor()
        XCTAssertEqual(compositor.configure(device: device), .readyForScene)
        let initialState = await compositor.prepare(initialFrame)
        XCTAssertEqual(
            initialState,
            .sceneReady(
                sceneID: initialFrame.sceneID,
                deterministicTick: 240,
                reduceMotion: false
            )
        )

        for path in SceneMetalFixture.assetPaths {
            try Data([0x00]).write(
                to: fixture.root.appending(path: path),
                options: .atomic
            )
        }
        let nextFrame = try fixture.frame(
            reduceMotion: false,
            deterministicTick: 241,
            cameraProgress: 0.6
        )

        XCTAssertEqual(
            compositor.update(nextFrame),
            .sceneReady(
                sceneID: nextFrame.sceneID,
                deterministicTick: 241,
                reduceMotion: false
            )
        )
    }

    @MainActor
    func testPerFrameUpdateBeforePreparationFailsClosed() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("The current test host exposes no Metal device.")
        }
        let fixture = try makeFixture()
        let frame = try fixture.frame(reduceMotion: false)
        let preparation = try SceneMetalPreparationPlanner.make(from: frame)
        let firstTexture = try XCTUnwrap(preparation.textureRequests.first?.key)
        let compositor = SceneMetalCompositor()
        XCTAssertEqual(compositor.configure(device: device), .readyForScene)

        XCTAssertEqual(
            compositor.update(frame),
            .failed(.textureResolutionFailed(.missingTexture(firstTexture)))
        )
    }

    private func copy(
        _ plan: SceneFramePlan,
        drawCommands: [SceneDrawCommand]
    ) -> SceneFramePlan {
        SceneFramePlan(
            sceneID: plan.sceneID,
            viewportCropID: plan.viewportCropID,
            viewport: plan.viewport,
            deterministicTick: plan.deterministicTick,
            reduceMotion: plan.reduceMotion,
            camera: plan.camera,
            drawCommands: drawCommands,
            atmosphere: plan.atmosphere,
            interactionSourceHitRegion: plan.interactionSourceHitRegion,
            interactionHitRegions: plan.interactionHitRegions,
            interactionResponse: plan.interactionResponse,
            safeTextRegions: plan.safeTextRegions
        )
    }

    private func makeFixture() throws -> SceneMetalFixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "scene-metal-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        for path in SceneMetalFixture.assetPaths {
            let url = root.appending(path: path, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try SceneMetalFixture.pngData.write(to: url, options: .atomic)
        }
        let scene = SceneMetalFixture.scene
        let records = try SceneMetalFixture.assetPaths.sorted().map { path in
            let data = try Data(contentsOf: root.appending(path: path))
            return PackageFileRecord(
                path: path,
                bytes: Int64(data.count),
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            )
        }
        let schema = SchemaVersion(major: 1)
        let packageID: PackageID = "scene-metal-test"
        let verified = VerifiedContentPackage(
            manifest: SignedPackageManifest(
                packageID: packageID,
                packageVersion: schema,
                schemaVersion: schema,
                minimumRuntime: schema,
                files: records,
                manifestDigest: "test-only",
                signature: PackageSignature(
                    algorithm: ContentPackageVerifier.signatureAlgorithm,
                    keyID: "test-only",
                    value: "test-only"
                )
            ),
            payload: ContentPackagePayload(
                schemaVersion: schema,
                packageID: packageID,
                worldSeed: WorldSeedSpec(nodes: [], traces: []),
                chapters: [],
                scenes: [scene],
                audioTimelines: [],
                accessibility: []
            )
        )
        return SceneMetalFixture(
            root: root,
            scene: scene,
            inventory: try SceneAssetInventory(
                verifiedPackage: verified,
                activatedPackageRoot: root
            )
        )
    }
}

private struct SceneMetalFixture {
    let root: URL
    let scene: SceneSpec
    let inventory: SceneAssetInventory

    static let assetPaths = [
        "assets/background.png",
        "assets/mechanism.png",
        "assets/mechanism-alpha.png",
        "assets/mechanism-occlusion.png",
        "assets/mechanism-depth.png",
        "assets/mechanism-light.png",
        "assets/reduced.png",
    ]

    static let pngData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAAECAIAAAArjXluAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAqADAAQAAAABAAAABAAAAABiWEkKAAAAJ0lEQVQIHQEcAOP/ATQ3Nvf4+QT79PD++/kE/PbxAgD/AwQFBvz8/eqxEE/b0NhIAAAAAElFTkSuQmCC"
    )!

    static let crop = SceneViewportCrop(
        id: "baseline-393x852",
        viewport: SceneViewportSize(widthPoints: 393, heightPoints: 852),
        sourceRect: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
        safeTextRegions: [
            SceneSafeTextRegion(
                id: "scene-copy",
                rect: NormalizedRect(x: 0.08, y: 0.08, width: 0.5, height: 0.16)
            ),
        ]
    )

    static let scene = SceneSpec(
        id: "metal-composition",
        sceneCanvas: SceneCanvasSpec(
            canvas: ScenePixelSize(width: 1_179, height: 2_556),
            cameraTravelBounds: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            authoredOverscanFraction: 0.15,
            viewportCrops: [crop]
        ),
        layers: [
            SceneLayerSpec(
                id: "background",
                order: 0,
                assetPath: "assets/background.png",
                frame: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                depth: 0.1,
                motion: SceneLayerMotion(parallaxFactor: 0.1, windResponse: 0.1)
            ),
            SceneLayerSpec(
                id: "mechanism",
                order: 1,
                assetPath: "assets/mechanism.png",
                frame: NormalizedRect(x: 0.25, y: 0.3, width: 0.5, height: 0.4),
                depth: 0.7,
                opacity: 0.85,
                blendMode: .screen,
                masks: SceneLayerMaskSet(
                    alphaMaskAssetPath: "assets/mechanism-alpha.png",
                    occlusionMaskAssetPath: "assets/mechanism-occlusion.png",
                    depthMaskAssetPath: "assets/mechanism-depth.png",
                    lightMaskAssetPath: "assets/mechanism-light.png"
                ),
                motion: SceneLayerMotion(
                    parallaxFactor: 0.35,
                    windResponse: 0.2,
                    focusResponse: 0.4
                )
            ),
        ],
        cameraRail: CameraRail(
            keyframes: [
                CameraKeyframe(
                    progress: 0,
                    center: NormalizedPoint(x: 0.5, y: 0.5),
                    scale: 1.2
                ),
                CameraKeyframe(
                    progress: 1,
                    center: NormalizedPoint(x: 0.5, y: 0.5),
                    scale: 1.2
                ),
            ]
        ),
        atmosphere: [
            AtmosphereSpec(
                kind: .dust,
                density: 0.25,
                velocity: SignedUnitVector(dx: 0.1, dy: 0),
                deterministicSeed: 7
            ),
        ],
        interactionTargets: [],
        reduceMotionComposition: ReduceMotionComposition(
            canvas: ScenePixelSize(width: 1_179, height: 2_556),
            viewportCrops: [crop],
            strata: [
                ReduceMotionStratum(
                    id: "reduced-static",
                    kind: .staticPlate,
                    assetPath: "assets/reduced.png"
                ),
            ]
        ),
        mechanismFocus: LocalizedStringSpec(
            id: "metal-composition-focus",
            launchEnglish: "the mechanism remains visible through the authored crop"
        ),
        accessibilityID: "metal-composition-accessibility"
    )

    func frame(
        reduceMotion: Bool,
        deterministicTick: UInt64 = 240,
        cameraProgress: Double = 0.5
    ) throws -> SceneFramePlan {
        try SceneFramePlanner.plan(
            scene: scene,
            request: SceneFrameRequest(
                viewportCropID: "baseline-393x852",
                cameraProgress: cameraProgress,
                visualState: SceneInteractionVisualState(
                    activeLayerVariants: [:],
                    directManipulation: nil
                ),
                deterministicTick: deterministicTick,
                reduceMotion: reduceMotion
            ),
            assets: inventory
        )
    }
}
