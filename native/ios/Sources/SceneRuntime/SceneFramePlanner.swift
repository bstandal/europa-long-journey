import ContentKit
import CryptoKit
import Foundation

/// A package-relative asset resolved from a signed manifest inside a
/// runtime-admitted package root. The frame planner performs no file-system or
/// GPU work; the bytes cross their digest boundary immediately before decode.
public struct SceneResolvedAsset: Equatable, Sendable {
    public let packagePath: String
    public let byteCount: Int64
    public let sha256: String
    private let activatedPackageRoot: URL

    init(
        packagePath: String,
        activatedPackageRoot: URL,
        byteCount: Int64,
        sha256: String
    ) {
        self.packagePath = packagePath
        self.activatedPackageRoot = activatedPackageRoot
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    fileprivate func loadVerifiedData() throws -> Data {
        try SceneAssetFileBoundary.load(
            packagePath: packagePath,
            activatedPackageRoot: activatedPackageRoot,
            expectedByteCount: byteCount,
            expectedSHA256: sha256
        )
    }
}

public enum SceneAssetInventoryError: Error, Equatable, Sendable {
    case invalidVerifiedPackageRoot
    case unsafePackagePath(String)
    case pathMappingMismatch(String)
    case assetOutsideVerifiedPackageRoot(String)
    case duplicateManifestRecord(String)
    case missingManifestRecord(String)
    case manifestSizeMismatch(String)
    case manifestDigestMismatch(String)
    case missingAsset(String)
    case assetIsNotRegularFile(String)
    case assetIsSymbolicLink(String)
}

public struct SceneAssetInventory: Equatable, Sendable {
    private let assetsByPackagePath: [String: SceneResolvedAsset]

    /// Creates the production inventory from verifier-created package
    /// authority. Construction binds paths to signed size/digest records but
    /// deliberately does not read asset bytes. `SceneAssetDataLoader` performs
    /// that check at first decode, keeping cold launch independent of total
    /// scene-asset size.
    public init(
        verifiedPackage: VerifiedContentPackage,
        activatedPackageRoot: URL
    ) throws {
        let canonicalRoot = try SceneAssetFileBoundary.canonicalPackageRoot(
            activatedPackageRoot
        )
        let requiredPaths = Self.sceneAssetPaths(in: verifiedPackage.payload)
        var recordsByPath: [String: PackageFileRecord] = [:]
        for record in verifiedPackage.manifest.files {
            guard recordsByPath.updateValue(record, forKey: record.path) == nil else {
                throw SceneAssetInventoryError.duplicateManifestRecord(record.path)
            }
        }

        var validatedAssets: [String: SceneResolvedAsset] = [:]
        for packagePath in requiredPaths.sorted() {
            guard Self.isSafePackagePath(packagePath) else {
                throw SceneAssetInventoryError.unsafePackagePath(packagePath)
            }
            guard let record = recordsByPath[packagePath] else {
                throw SceneAssetInventoryError.missingManifestRecord(packagePath)
            }
            try SceneAssetFileBoundary.validateMetadata(
                packagePath: packagePath,
                activatedPackageRoot: canonicalRoot,
                expectedByteCount: record.bytes
            )
            let asset = SceneResolvedAsset(
                packagePath: packagePath,
                activatedPackageRoot: canonicalRoot,
                byteCount: record.bytes,
                sha256: record.sha256
            )
            validatedAssets[packagePath] = asset
        }
        assetsByPackagePath = validatedAssets
    }

    fileprivate func resolvedAsset(for packagePath: String) -> SceneResolvedAsset? {
        assetsByPackagePath[packagePath]
    }

    private static func sceneAssetPaths(in payload: ContentPackagePayload) -> Set<String> {
        var paths: Set<String> = []
        for scene in payload.scenes {
            for stratum in scene.reduceMotionComposition.strata {
                if let assetPath = stratum.assetPath {
                    paths.insert(assetPath)
                }
            }
            for layer in scene.layers {
                paths.insert(layer.assetPath)
                insertMaskPaths(layer.masks, into: &paths)
                for variant in layer.stateVariants {
                    paths.insert(variant.assetPath)
                    insertMaskPaths(variant.masks, into: &paths)
                }
            }
        }
        return paths
    }

    private static func insertMaskPaths(
        _ masks: SceneLayerMaskSet,
        into paths: inout Set<String>
    ) {
        for path in [
            masks.alphaMaskAssetPath,
            masks.occlusionMaskAssetPath,
            masks.depthMaskAssetPath,
            masks.lightMaskAssetPath,
        ].compactMap({ $0 }) {
            paths.insert(path)
        }
    }

    fileprivate static func isSafePackagePath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let containsControlCharacter = path.unicodeScalars.contains { scalar in
            scalar.value <= 0x1F || scalar.value == 0x7F
        }
        return !path.isEmpty
            && !path.hasPrefix("/")
            && !path.contains("\\")
            && !path.contains("://")
            && !containsControlCharacter
            && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

/// The renderer crosses this boundary when it first decodes an asset. It
/// rechecks the signed size and digest so replacing a file after package
/// activation or inventory construction cannot silently reach Metal.
public enum SceneAssetDataLoader {
    public static func load(_ asset: SceneResolvedAsset) throws -> Data {
        try asset.loadVerifiedData()
    }
}

private enum SceneAssetFileBoundary {
    static func canonicalPackageRoot(_ root: URL) throws -> URL {
        guard root.isFileURL else {
            throw SceneAssetInventoryError.invalidVerifiedPackageRoot
        }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let values: URLResourceValues
        do {
            values = try canonicalRoot.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            throw SceneAssetInventoryError.invalidVerifiedPackageRoot
        }
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw SceneAssetInventoryError.invalidVerifiedPackageRoot
        }
        return canonicalRoot
    }

    static func load(
        packagePath: String,
        activatedPackageRoot: URL,
        expectedByteCount: Int64,
        expectedSHA256: String
    ) throws -> Data {
        guard SceneAssetInventory.isSafePackagePath(packagePath) else {
            throw SceneAssetInventoryError.unsafePackagePath(packagePath)
        }
        let canonicalRoot = try canonicalPackageRoot(activatedPackageRoot)
        let expectedURL = canonicalRoot
            .appending(path: packagePath, directoryHint: .notDirectory)
            .standardizedFileURL
        let values: URLResourceValues
        do {
            values = try expectedURL.resourceValues(
                forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            throw SceneAssetInventoryError.missingAsset(packagePath)
        }
        guard values.isSymbolicLink != true else {
            throw SceneAssetInventoryError.assetIsSymbolicLink(packagePath)
        }
        guard values.isRegularFile == true, values.isDirectory != true else {
            throw SceneAssetInventoryError.assetIsNotRegularFile(packagePath)
        }

        let canonicalURL = expectedURL.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(canonicalURL, of: canonicalRoot) else {
            throw SceneAssetInventoryError.assetOutsideVerifiedPackageRoot(packagePath)
        }
        guard packageRelativePath(for: canonicalURL, root: canonicalRoot) == packagePath else {
            throw SceneAssetInventoryError.pathMappingMismatch(packagePath)
        }

        let data: Data
        do {
            data = try Data(contentsOf: expectedURL, options: [.mappedIfSafe])
        } catch {
            throw SceneAssetInventoryError.missingAsset(packagePath)
        }

        // Check the path again after reading. The digest below protects the
        // returned bytes; the second path check rejects a replacement that
        // changes the file into a symlink during the read boundary.
        let postReadValues: URLResourceValues
        do {
            postReadValues = try expectedURL.resourceValues(
                forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            throw SceneAssetInventoryError.missingAsset(packagePath)
        }
        guard postReadValues.isSymbolicLink != true else {
            throw SceneAssetInventoryError.assetIsSymbolicLink(packagePath)
        }
        guard postReadValues.isRegularFile == true, postReadValues.isDirectory != true else {
            throw SceneAssetInventoryError.assetIsNotRegularFile(packagePath)
        }
        let postReadCanonicalURL = expectedURL.resolvingSymlinksInPath().standardizedFileURL
        guard postReadCanonicalURL == canonicalURL else {
            throw SceneAssetInventoryError.pathMappingMismatch(packagePath)
        }

        guard Int64(data.count) == expectedByteCount else {
            throw SceneAssetInventoryError.manifestSizeMismatch(packagePath)
        }
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == expectedSHA256 else {
            throw SceneAssetInventoryError.manifestDigestMismatch(packagePath)
        }
        return data
    }

    /// Rejects path, type and declared-size drift without opening the file.
    /// This keeps inventory construction proportional to file count rather
    /// than total scene bytes while preserving a fail-closed path boundary.
    static func validateMetadata(
        packagePath: String,
        activatedPackageRoot: URL,
        expectedByteCount: Int64
    ) throws {
        guard SceneAssetInventory.isSafePackagePath(packagePath) else {
            throw SceneAssetInventoryError.unsafePackagePath(packagePath)
        }
        let canonicalRoot = try canonicalPackageRoot(activatedPackageRoot)
        let expectedURL = canonicalRoot
            .appending(path: packagePath, directoryHint: .notDirectory)
            .standardizedFileURL
        let values: URLResourceValues
        do {
            values = try expectedURL.resourceValues(
                forKeys: [
                    .fileSizeKey,
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ]
            )
        } catch {
            throw SceneAssetInventoryError.missingAsset(packagePath)
        }
        guard values.isSymbolicLink != true else {
            throw SceneAssetInventoryError.assetIsSymbolicLink(packagePath)
        }
        guard values.isRegularFile == true, values.isDirectory != true else {
            throw SceneAssetInventoryError.assetIsNotRegularFile(packagePath)
        }
        let canonicalURL = expectedURL.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(canonicalURL, of: canonicalRoot) else {
            throw SceneAssetInventoryError.assetOutsideVerifiedPackageRoot(packagePath)
        }
        guard packageRelativePath(for: canonicalURL, root: canonicalRoot) == packagePath else {
            throw SceneAssetInventoryError.pathMappingMismatch(packagePath)
        }
        guard let fileSize = values.fileSize, Int64(fileSize) == expectedByteCount else {
            throw SceneAssetInventoryError.manifestSizeMismatch(packagePath)
        }
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path.hasPrefix(prefix)
    }

    private static func packageRelativePath(for file: URL, root: URL) -> String? {
        guard isDescendant(file, of: root) else { return nil }
        let prefixLength = root.path.hasSuffix("/") ? root.path.count : root.path.count + 1
        return String(file.path.dropFirst(prefixLength))
    }
}

public struct SceneFrameRequest: Equatable, Sendable {
    public let viewportCropID: String
    public let cameraProgress: Double
    public let visualState: SceneInteractionVisualState
    public let deterministicTick: UInt64
    public let reduceMotion: Bool

    public init(
        viewportCropID: String,
        cameraProgress: Double,
        visualState: SceneInteractionVisualState,
        deterministicTick: UInt64,
        reduceMotion: Bool
    ) {
        self.viewportCropID = viewportCropID
        self.cameraProgress = cameraProgress
        self.visualState = visualState
        self.deterministicTick = deterministicTick
        self.reduceMotion = reduceMotion
    }
}

public struct SceneFrameSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct SceneFramePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct SceneFrameVector: Equatable, Sendable {
    public let dx: Double
    public let dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = SceneFrameVector(dx: 0, dy: 0)
}

public struct SceneFrameRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct SceneCameraTransform: Equatable, Sendable {
    /// Camera centre in the scene canvas's normalised coordinate space.
    public let masterCenter: SceneFramePoint
    /// The same centre mapped into the selected crop's coordinate space.
    public let viewportCenter: SceneFramePoint
    public let scale: Double
    public let sourceRect: SceneFrameRect
    public let followsAuthoredRail: Bool

    public init(
        masterCenter: SceneFramePoint,
        viewportCenter: SceneFramePoint,
        scale: Double,
        sourceRect: SceneFrameRect,
        followsAuthoredRail: Bool
    ) {
        self.masterCenter = masterCenter
        self.viewportCenter = viewportCenter
        self.scale = scale
        self.sourceRect = sourceRect
        self.followsAuthoredRail = followsAuthoredRail
    }
}

public struct SceneDrawMaskPlan: Equatable, Sendable {
    public let alpha: SceneResolvedAsset?
    public let occlusion: SceneResolvedAsset?
    public let depth: SceneResolvedAsset?
    public let light: SceneResolvedAsset?

    public init(
        alpha: SceneResolvedAsset?,
        occlusion: SceneResolvedAsset?,
        depth: SceneResolvedAsset?,
        light: SceneResolvedAsset?
    ) {
        self.alpha = alpha
        self.occlusion = occlusion
        self.depth = depth
        self.light = light
    }

    public static let none = SceneDrawMaskPlan(
        alpha: nil,
        occlusion: nil,
        depth: nil,
        light: nil
    )
}

public enum SceneDrawSource: Equatable, Sendable {
    case layer(SceneLayerID, variantID: String?)
    case reduceMotionStaticStratum(String)
}

public struct SceneLayerMotionState: Equatable, Sendable {
    /// Normalised viewport displacement caused by the authored camera rail.
    public let parallaxOffset: SceneFrameVector
    /// A bounded, deterministic response to the scene's authored atmosphere.
    public let windOffset: SceneFrameVector
    /// The authored focus response evaluated at the current camera progress.
    public let focusAmount: Double

    public init(
        parallaxOffset: SceneFrameVector,
        windOffset: SceneFrameVector,
        focusAmount: Double
    ) {
        self.parallaxOffset = parallaxOffset
        self.windOffset = windOffset
        self.focusAmount = focusAmount
    }

    public static let still = SceneLayerMotionState(
        parallaxOffset: .zero,
        windOffset: .zero,
        focusAmount: 0
    )
}

public struct SceneDrawCommand: Equatable, Sendable {
    public let source: SceneDrawSource
    public let authoredOrder: Int
    public let depth: Double
    public let asset: SceneResolvedAsset
    public let masks: SceneDrawMaskPlan
    public let masterFrame: SceneFrameRect
    public let viewportFrame: SceneFrameRect
    public let opacity: Double
    public let blendMode: SceneBlendMode
    public let motion: SceneLayerMotionState

    public init(
        source: SceneDrawSource,
        authoredOrder: Int,
        depth: Double,
        asset: SceneResolvedAsset,
        masks: SceneDrawMaskPlan,
        masterFrame: SceneFrameRect,
        viewportFrame: SceneFrameRect,
        opacity: Double,
        blendMode: SceneBlendMode,
        motion: SceneLayerMotionState
    ) {
        self.source = source
        self.authoredOrder = authoredOrder
        self.depth = depth
        self.asset = asset
        self.masks = masks
        self.masterFrame = masterFrame
        self.viewportFrame = viewportFrame
        self.opacity = opacity
        self.blendMode = blendMode
        self.motion = motion
    }
}

public struct SceneAtmosphereSample: Equatable, Sendable {
    public let index: Int
    public let position: SceneFramePoint
    public let phase: Double

    public init(index: Int, position: SceneFramePoint, phase: Double) {
        self.index = index
        self.position = position
        self.phase = phase
    }
}

public struct SceneAtmosphereState: Equatable, Sendable {
    public let authoredIndex: Int
    public let kind: AtmosphereSpec.Kind
    public let density: Double
    public let deterministicSeed: UInt64
    public let authoredVelocity: SceneFrameVector
    public let travel: SceneFrameVector
    public let samples: [SceneAtmosphereSample]

    public init(
        authoredIndex: Int,
        kind: AtmosphereSpec.Kind,
        density: Double,
        deterministicSeed: UInt64,
        authoredVelocity: SceneFrameVector,
        travel: SceneFrameVector,
        samples: [SceneAtmosphereSample]
    ) {
        self.authoredIndex = authoredIndex
        self.kind = kind
        self.density = density
        self.deterministicSeed = deterministicSeed
        self.authoredVelocity = authoredVelocity
        self.travel = travel
        self.samples = samples
    }
}

public struct SceneInteractionHitRegionPlan: Equatable, Sendable {
    public let interactionTargetID: String
    public let layerID: SceneLayerID
    public let accessibilityElementID: String
    /// Polygon points mapped from scene-canvas space into the selected viewport crop.
    public let viewportPath: [SceneFramePoint]

    public init(
        interactionTargetID: String,
        layerID: SceneLayerID,
        accessibilityElementID: String,
        viewportPath: [SceneFramePoint]
    ) {
        self.interactionTargetID = interactionTargetID
        self.layerID = layerID
        self.accessibilityElementID = accessibilityElementID
        self.viewportPath = viewportPath
    }
}

public struct SceneInteractionSourceHitRegionPlan: Equatable, Sendable {
    public let interactionID: InteractionID
    public let layerID: SceneLayerID
    public let hitTest: SceneResourceHitTest
    /// Polygon mapped with the exact transform used by the selected resource layer.
    public let viewportPath: [SceneFramePoint]
    /// Digest-bound selected-variant alpha mask used for the final pixel hit.
    public let selectedVariantAlphaMask: SceneResolvedAsset

    public init(
        interactionID: InteractionID,
        layerID: SceneLayerID,
        hitTest: SceneResourceHitTest,
        viewportPath: [SceneFramePoint],
        selectedVariantAlphaMask: SceneResolvedAsset
    ) {
        self.interactionID = interactionID
        self.layerID = layerID
        self.hitTest = hitTest
        self.viewportPath = viewportPath
        self.selectedVariantAlphaMask = selectedVariantAlphaMask
    }
}

public struct SceneInteractionResponsePlan: Equatable, Sendable {
    public let phase: SceneDirectManipulationPhase
    public let targetID: String?
    public let transferLayerID: SceneLayerID
    /// Displayed anchor of the material inside `transferLayerID` before the
    /// manipulation offset. Nil preserves the legacy centered transfer-layer
    /// contract used by Allocate; Assemble supplies its component target.
    public let viewportTransferLayerAnchor: SceneFramePoint?
    public let viewportMaterialPosition: SceneFramePoint?
    public let viewportTransferPath: [SceneFramePoint]
    public let progress: Double
    public let contactAmount: Double
    public let resistanceAmount: Double

    public init(
        phase: SceneDirectManipulationPhase,
        targetID: String?,
        transferLayerID: SceneLayerID,
        viewportTransferLayerAnchor: SceneFramePoint? = nil,
        viewportMaterialPosition: SceneFramePoint?,
        viewportTransferPath: [SceneFramePoint],
        progress: Double,
        contactAmount: Double,
        resistanceAmount: Double
    ) {
        self.phase = phase
        self.targetID = targetID
        self.transferLayerID = transferLayerID
        self.viewportTransferLayerAnchor = viewportTransferLayerAnchor
        self.viewportMaterialPosition = viewportMaterialPosition
        self.viewportTransferPath = viewportTransferPath
        self.progress = progress
        self.contactAmount = contactAmount
        self.resistanceAmount = resistanceAmount
    }
}

public struct SceneSafeTextRegionPlan: Equatable, Sendable {
    public let id: String
    /// Safe text regions are authored directly in final viewport unit space.
    public let viewportRect: SceneFrameRect

    public init(id: String, viewportRect: SceneFrameRect) {
        self.id = id
        self.viewportRect = viewportRect
    }
}

public struct SceneFramePlan: Equatable, Sendable {
    public let sceneID: SceneID
    public let viewportCropID: String
    public let viewport: SceneFrameSize
    public let deterministicTick: UInt64
    public let reduceMotion: Bool
    public let camera: SceneCameraTransform
    public let drawCommands: [SceneDrawCommand]
    public let atmosphere: [SceneAtmosphereState]
    public let interactionSourceHitRegion: SceneInteractionSourceHitRegionPlan?
    public let interactionHitRegions: [SceneInteractionHitRegionPlan]
    public let interactionResponse: SceneInteractionResponsePlan?
    public let safeTextRegions: [SceneSafeTextRegionPlan]

    public init(
        sceneID: SceneID,
        viewportCropID: String,
        viewport: SceneFrameSize,
        deterministicTick: UInt64,
        reduceMotion: Bool,
        camera: SceneCameraTransform,
        drawCommands: [SceneDrawCommand],
        atmosphere: [SceneAtmosphereState],
        interactionSourceHitRegion: SceneInteractionSourceHitRegionPlan?,
        interactionHitRegions: [SceneInteractionHitRegionPlan],
        interactionResponse: SceneInteractionResponsePlan?,
        safeTextRegions: [SceneSafeTextRegionPlan]
    ) {
        self.sceneID = sceneID
        self.viewportCropID = viewportCropID
        self.viewport = viewport
        self.deterministicTick = deterministicTick
        self.reduceMotion = reduceMotion
        self.camera = camera
        self.drawCommands = drawCommands
        self.atmosphere = atmosphere
        self.interactionSourceHitRegion = interactionSourceHitRegion
        self.interactionHitRegions = interactionHitRegions
        self.interactionResponse = interactionResponse
        self.safeTextRegions = safeTextRegions
    }
}

public enum SceneFramePlannerError: Error, Equatable, Sendable {
    case invalidScene(String)
    case unknownViewportCrop(String)
    case ambiguousViewportCrop(String)
    case invalidViewport(String)
    case invalidCameraProgress
    case invalidCameraRail
    case ambiguousLayer(SceneLayerID)
    case ambiguousLayerOrder(Int)
    case unexpectedLayerVariant(SceneLayerID)
    case missingLayerVariant(SceneLayerID)
    case unknownLayerVariant(layerID: SceneLayerID, variantID: String)
    case ambiguousLayerVariant(layerID: SceneLayerID, variantID: String)
    case missingAssetResolution(String)
    case missingReduceMotionViewportCrop(String)
    case ambiguousInteractionTarget(String)
    case missingInteractionLayer(SceneLayerID)
    case invalidInteractionHitRegion(String)
    case overlappingInteractionTargets(String, String)
    case invalidDirectManipulation
    case invalidAtmosphere(Int)
}

/// Produces a complete immutable rendering plan without touching Metal, the
/// file system or wall-clock time. Given the same authored scene, request and
/// resolved asset inventory, the result is Equatable-identical.
public enum SceneFramePlanner {
    private static let atmosphereSampleCapacity = 32
    private static let ticksPerSecond = 60.0

    public static func plan(
        scene: SceneSpec,
        request: SceneFrameRequest,
        assets: SceneAssetInventory
    ) throws -> SceneFramePlan {
        guard request.cameraProgress.isFinite,
              (0 ... 1).contains(request.cameraProgress) else {
            throw SceneFramePlannerError.invalidCameraProgress
        }

        try validateUnambiguousLayers(scene.layers)
        try validateVariantSelection(
            scene.layers,
            selection: request.visualState.activeLayerVariants
        )

        let crop: SceneViewportCrop
        if request.reduceMotion {
            let composition = scene.reduceMotionComposition
            let matches = composition.viewportCrops.filter { $0.id == request.viewportCropID }
            guard !matches.isEmpty else {
                throw SceneFramePlannerError.missingReduceMotionViewportCrop(request.viewportCropID)
            }
            guard matches.count == 1, let selected = matches.first else {
                throw SceneFramePlannerError.ambiguousViewportCrop(request.viewportCropID)
            }
            crop = selected
        } else {
            let matches = scene.sceneCanvas.viewportCrops.filter { $0.id == request.viewportCropID }
            guard !matches.isEmpty else {
                throw SceneFramePlannerError.unknownViewportCrop(request.viewportCropID)
            }
            guard matches.count == 1, let selected = matches.first else {
                throw SceneFramePlannerError.ambiguousViewportCrop(request.viewportCropID)
            }
            crop = selected
        }

        let viewport = try validatedViewport(crop)
        do {
            try scene.validate()
        } catch {
            throw SceneFramePlannerError.invalidScene(String(describing: error))
        }
        try preflightAllAssets(in: scene, inventory: assets)
        let camera = try cameraTransform(
            rail: scene.cameraRail,
            progress: request.cameraProgress,
            crop: crop,
            reduceMotion: request.reduceMotion
        )
        let atmosphere = try atmosphereStates(
            scene.atmosphere,
            tick: request.deterministicTick,
            reduceMotion: request.reduceMotion
        )
        let drawCommands: [SceneDrawCommand]
        if request.reduceMotion {
            drawCommands = try reducedMotionDrawCommands(
                scene: scene,
                crop: crop,
                variants: request.visualState.activeLayerVariants,
                assets: assets
            )
        } else {
            drawCommands = try layeredDrawCommands(
                scene: scene,
                crop: crop,
                camera: camera,
                cameraProgress: request.cameraProgress,
                variants: request.visualState.activeLayerVariants,
                tick: request.deterministicTick,
                assets: assets
            )
        }

        return SceneFramePlan(
            sceneID: scene.id,
            viewportCropID: crop.id,
            viewport: viewport,
            deterministicTick: request.deterministicTick,
            reduceMotion: request.reduceMotion,
            camera: camera,
            drawCommands: drawCommands,
            atmosphere: atmosphere,
            interactionSourceHitRegion: try sourceHitRegion(
                scene: scene,
                crop: crop,
                camera: camera,
                drawCommands: drawCommands,
                reduceMotion: request.reduceMotion
            ),
            interactionHitRegions: try hitRegions(
                scene: scene,
                crop: crop,
                camera: camera,
                drawCommands: drawCommands,
                reduceMotion: request.reduceMotion
            ),
            interactionResponse: try interactionResponse(
                scene: scene,
                visualState: request.visualState,
                camera: camera,
                drawCommands: drawCommands,
                reduceMotion: request.reduceMotion
            ),
            safeTextRegions: crop.safeTextRegions.map {
                SceneSafeTextRegionPlan(id: $0.id, viewportRect: frameRect($0.rect))
            }
        )
    }

    private static func validateUnambiguousLayers(_ layers: [SceneLayerSpec]) throws {
        var layerIDs: Set<SceneLayerID> = []
        var orders: Set<Int> = []
        for (index, layer) in layers.enumerated() {
            guard layerIDs.insert(layer.id).inserted else {
                throw SceneFramePlannerError.ambiguousLayer(layer.id)
            }
            guard orders.insert(layer.order).inserted, layer.order == index else {
                throw SceneFramePlannerError.ambiguousLayerOrder(layer.order)
            }
            var variantIDs: Set<String> = []
            for variant in layer.stateVariants where !variantIDs.insert(variant.id).inserted {
                throw SceneFramePlannerError.ambiguousLayerVariant(
                    layerID: layer.id,
                    variantID: variant.id
                )
            }
        }
    }

    private static func validateVariantSelection(
        _ layers: [SceneLayerSpec],
        selection: [SceneLayerID: String]
    ) throws {
        let layersByID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        for layerID in selection.keys.sorted() where layersByID[layerID] == nil {
            throw SceneFramePlannerError.unexpectedLayerVariant(layerID)
        }
        for layer in layers {
            guard !layer.stateVariants.isEmpty else {
                if selection[layer.id] != nil {
                    throw SceneFramePlannerError.unexpectedLayerVariant(layer.id)
                }
                continue
            }
            guard let selectedID = selection[layer.id] else {
                throw SceneFramePlannerError.missingLayerVariant(layer.id)
            }
            guard layer.stateVariants.contains(where: { $0.id == selectedID }) else {
                throw SceneFramePlannerError.unknownLayerVariant(
                    layerID: layer.id,
                    variantID: selectedID
                )
            }
        }
    }

    private static func validatedViewport(_ crop: SceneViewportCrop) throws -> SceneFrameSize {
        let width = Double(crop.viewport.widthPoints)
        let height = Double(crop.viewport.heightPoints)
        let rect = frameRect(crop.sourceRect)
        guard width.isFinite, height.isFinite, width > 0, height > 0, width < height,
              validUnitRect(rect) else {
            throw SceneFramePlannerError.invalidViewport(crop.id)
        }
        return SceneFrameSize(width: width, height: height)
    }

    private static func cameraTransform(
        rail: CameraRail,
        progress: Double,
        crop: SceneViewportCrop,
        reduceMotion: Bool
    ) throws -> SceneCameraTransform {
        let authoredSourceRect = frameRect(crop.sourceRect)
        if reduceMotion {
            let center = SceneFramePoint(
                x: authoredSourceRect.x + authoredSourceRect.width / 2,
                y: authoredSourceRect.y + authoredSourceRect.height / 2
            )
            return SceneCameraTransform(
                masterCenter: center,
                viewportCenter: SceneFramePoint(x: 0.5, y: 0.5),
                scale: 1,
                sourceRect: authoredSourceRect,
                followsAuthoredRail: false
            )
        }

        let keyframes = rail.keyframes
        guard keyframes.count >= 2,
              keyframes.first?.progress == 0,
              keyframes.last?.progress == 1 else {
            throw SceneFramePlannerError.invalidCameraRail
        }
        for index in keyframes.indices {
            let frame = keyframes[index]
            guard frame.progress.isFinite, frame.center.x.isFinite, frame.center.y.isFinite,
                  frame.scale.isFinite, frame.scale > 0 else {
                throw SceneFramePlannerError.invalidCameraRail
            }
            if index > keyframes.startIndex,
               keyframes[index - 1].progress >= frame.progress {
                throw SceneFramePlannerError.invalidCameraRail
            }
        }

        let upperIndex = keyframes.firstIndex(where: { $0.progress >= progress })
            ?? keyframes.index(before: keyframes.endIndex)
        let lowerIndex = max(keyframes.startIndex, upperIndex - 1)
        let lower = keyframes[lowerIndex]
        let upper = keyframes[upperIndex]
        let span = upper.progress - lower.progress
        let amount = span > 0 ? (progress - lower.progress) / span : 0
        let center = SceneFramePoint(
            x: interpolate(lower.center.x, upper.center.x, amount: amount),
            y: interpolate(lower.center.y, upper.center.y, amount: amount)
        )
        let scale = interpolate(lower.scale, upper.scale, amount: amount)
        let activeSourceRect = SceneFrameRect(
            x: center.x - authoredSourceRect.width / scale / 2,
            y: center.y - authoredSourceRect.height / scale / 2,
            width: authoredSourceRect.width / scale,
            height: authoredSourceRect.height / scale
        )
        guard validUnitRect(activeSourceRect) else {
            throw SceneFramePlannerError.invalidCameraRail
        }
        return SceneCameraTransform(
            masterCenter: center,
            viewportCenter: SceneFramePoint(x: 0.5, y: 0.5),
            scale: scale,
            sourceRect: activeSourceRect,
            followsAuthoredRail: true
        )
    }

    private static func reducedMotionDrawCommands(
        scene: SceneSpec,
        crop: SceneViewportCrop,
        variants: [SceneLayerID: String],
        assets: SceneAssetInventory
    ) throws -> [SceneDrawCommand] {
        let sourceRect = frameRect(crop.sourceRect)
        let layersByID = Dictionary(uniqueKeysWithValues: scene.layers.map { ($0.id, $0) })
        return try scene.reduceMotionComposition.strata.enumerated().map { index, stratum in
            switch stratum.kind {
            case .staticPlate:
                guard let assetPath = stratum.assetPath else {
                    throw SceneFramePlannerError.invalidScene(
                        "Reduce Motion static stratum '\(stratum.id)' has no asset"
                    )
                }
                return SceneDrawCommand(
                    source: .reduceMotionStaticStratum(stratum.id),
                    authoredOrder: index,
                    depth: Double(index) / Double(max(1, scene.reduceMotionComposition.strata.count)),
                    asset: try resolve(assetPath, from: assets),
                    masks: .none,
                    masterFrame: sourceRect,
                    viewportFrame: SceneFrameRect(x: 0, y: 0, width: 1, height: 1),
                    opacity: 1,
                    blendMode: .normal,
                    motion: .still
                )
            case .stateOverlay:
                guard let layerID = stratum.layerID,
                      let layer = layersByID[layerID],
                      let selectedID = variants[layerID],
                      let selectedVariant = layer.stateVariants.first(where: {
                          $0.id == selectedID
                      }) else {
                    throw SceneFramePlannerError.missingLayerVariant(
                        stratum.layerID ?? "missing-reduce-motion-layer"
                    )
                }
                let masterFrame = frameRect(layer.frame)
                return SceneDrawCommand(
                    source: .layer(layer.id, variantID: selectedID),
                    authoredOrder: index,
                    depth: layer.depth,
                    asset: try resolve(selectedVariant.assetPath, from: assets),
                    masks: try resolvedMasks(selectedVariant.masks, from: assets),
                    masterFrame: masterFrame,
                    viewportFrame: map(rect: masterFrame, through: sourceRect),
                    opacity: layer.opacity,
                    blendMode: layer.blendMode,
                    motion: .still
                )
            }
        }
    }

    private static func layeredDrawCommands(
        scene: SceneSpec,
        crop: SceneViewportCrop,
        camera: SceneCameraTransform,
        cameraProgress: Double,
        variants: [SceneLayerID: String],
        tick: UInt64,
        assets: SceneAssetInventory
    ) throws -> [SceneDrawCommand] {
        let sourceRect = camera.sourceRect
        guard let railOrigin = scene.cameraRail.keyframes.first?.center else {
            throw SceneFramePlannerError.invalidCameraRail
        }
        let wind = aggregateWind(scene.atmosphere, tick: tick)
        let commands = try scene.layers.map { layer -> SceneDrawCommand in
            let selectedVariantID = variants[layer.id]
            let selectedVariant = selectedVariantID.flatMap { selectedID in
                layer.stateVariants.first { $0.id == selectedID }
            }
            let assetPath = selectedVariant?.assetPath ?? layer.assetPath
            let masks = selectedVariant?.masks ?? layer.masks
            let masterFrame = frameRect(layer.frame)
            let parallax = SceneFrameVector(
                dx: ((camera.masterCenter.x - railOrigin.x) / sourceRect.width)
                    * layer.motion.parallaxFactor,
                dy: ((camera.masterCenter.y - railOrigin.y) / sourceRect.height)
                    * layer.motion.parallaxFactor
            )
            let windOffset = SceneFrameVector(
                dx: wind.dx * layer.motion.windResponse,
                dy: wind.dy * layer.motion.windResponse
            )
            return SceneDrawCommand(
                source: .layer(layer.id, variantID: selectedVariantID),
                authoredOrder: layer.order,
                depth: layer.depth,
                asset: try resolve(assetPath, from: assets),
                masks: try resolvedMasks(masks, from: assets),
                masterFrame: masterFrame,
                viewportFrame: map(rect: masterFrame, through: sourceRect),
                opacity: layer.opacity,
                blendMode: layer.blendMode,
                motion: SceneLayerMotionState(
                    parallaxOffset: parallax,
                    windOffset: windOffset,
                    focusAmount: cameraProgress * layer.motion.focusResponse
                )
            )
        }
        return commands.sorted { $0.authoredOrder < $1.authoredOrder }
    }

    private static func hitRegions(
        scene: SceneSpec,
        crop: SceneViewportCrop,
        camera: SceneCameraTransform,
        drawCommands: [SceneDrawCommand],
        reduceMotion: Bool
    ) throws -> [SceneInteractionHitRegionPlan] {
        let layerIDs = Set(scene.layers.map(\.id))
        let sourceRect = camera.sourceRect
        var targetIDs: Set<String> = []
        var result: [SceneInteractionHitRegionPlan] = []
        for target in scene.interactionTargets {
            guard targetIDs.insert(target.interactionTargetID).inserted else {
                throw SceneFramePlannerError.ambiguousInteractionTarget(target.interactionTargetID)
            }
            guard layerIDs.contains(target.layerID) else {
                throw SceneFramePlannerError.missingInteractionLayer(target.layerID)
            }
            guard target.hitRegion.path.count >= 3 else {
                throw SceneFramePlannerError.invalidInteractionHitRegion(target.interactionTargetID)
            }
            let boundMotion = reduceMotion
                ? SceneLayerMotionState.still
                : drawCommands.first(where: { command in
                    if case let .layer(layerID, _) = command.source { return layerID == target.layerID }
                    return false
                })?.motion ?? .still
            let path = target.hitRegion.path.map {
                let projected = map(
                    point: SceneFramePoint(x: $0.x, y: $0.y),
                    through: sourceRect
                )
                return SceneFramePoint(
                    x: projected.x + boundMotion.parallaxOffset.dx + boundMotion.windOffset.dx,
                    y: projected.y + boundMotion.parallaxOffset.dy + boundMotion.windOffset.dy
                )
            }
            let xs = path.map(\.x)
            let ys = path.map(\.y)
            guard path.allSatisfy({
                $0.x.isFinite && $0.y.isFinite
                    && (0 ... 1).contains($0.x) && (0 ... 1).contains($0.y)
            }), let minimumX = xs.min(), let maximumX = xs.max(),
                  let minimumY = ys.min(), let maximumY = ys.max(),
                  (maximumX - minimumX) * Double(crop.viewport.widthPoints) >= 44,
                  (maximumY - minimumY) * Double(crop.viewport.heightPoints) >= 44 else {
                throw SceneFramePlannerError.invalidInteractionHitRegion(target.interactionTargetID)
            }
            result.append(
                SceneInteractionHitRegionPlan(
                    interactionTargetID: target.interactionTargetID,
                    layerID: target.layerID,
                    accessibilityElementID: target.accessibilityElementID,
                    viewportPath: path
                )
            )
        }
        for leftIndex in result.indices {
            for rightIndex in result.indices where rightIndex > leftIndex {
                let leftX = result[leftIndex].viewportPath.map(\.x)
                let leftY = result[leftIndex].viewportPath.map(\.y)
                let rightX = result[rightIndex].viewportPath.map(\.x)
                let rightY = result[rightIndex].viewportPath.map(\.y)
                guard let leftMinX = leftX.min(), let leftMaxX = leftX.max(),
                      let leftMinY = leftY.min(), let leftMaxY = leftY.max(),
                      let rightMinX = rightX.min(), let rightMaxX = rightX.max(),
                      let rightMinY = rightY.min(), let rightMaxY = rightY.max() else {
                    throw SceneFramePlannerError.invalidInteractionHitRegion(
                        result[leftIndex].interactionTargetID
                    )
                }
                let overlaps = leftMinX < rightMaxX && rightMinX < leftMaxX
                    && leftMinY < rightMaxY && rightMinY < leftMaxY
                guard !overlaps else {
                    throw SceneFramePlannerError.overlappingInteractionTargets(
                        result[leftIndex].interactionTargetID,
                        result[rightIndex].interactionTargetID
                    )
                }
            }
        }
        return result
    }

    private static func sourceHitRegion(
        scene: SceneSpec,
        crop: SceneViewportCrop,
        camera: SceneCameraTransform,
        drawCommands: [SceneDrawCommand],
        reduceMotion: Bool
    ) throws -> SceneInteractionSourceHitRegionPlan? {
        guard case let .allocate(binding)? = scene.interactionVisualBinding else {
            return nil
        }
        guard let resourceCommand = drawCommands.first(where: { command in
            if case let .layer(layerID, _) = command.source {
                return layerID == binding.resource.layerID
            }
            return false
        }), let selectedAlphaMask = resourceCommand.masks.alpha else {
            throw SceneFramePlannerError.invalidInteractionHitRegion("allocation-resource")
        }
        let boundMotion = reduceMotion ? .still : resourceCommand.motion
        let path = binding.resource.hitRegion.path.map {
            project(point: $0, through: camera.sourceRect, motion: boundMotion)
        }
        let xs = path.map(\.x)
        let ys = path.map(\.y)
        guard path.count >= 3,
              path.allSatisfy(isFiniteViewportPoint),
              let minimumX = xs.min(), let maximumX = xs.max(),
              let minimumY = ys.min(), let maximumY = ys.max(),
              (maximumX - minimumX) * Double(crop.viewport.widthPoints) >= 44,
              (maximumY - minimumY) * Double(crop.viewport.heightPoints) >= 44 else {
            throw SceneFramePlannerError.invalidInteractionHitRegion("allocation-resource")
        }
        return SceneInteractionSourceHitRegionPlan(
            interactionID: binding.interactionID,
            layerID: binding.resource.layerID,
            hitTest: binding.resource.hitTest,
            viewportPath: path,
            selectedVariantAlphaMask: selectedAlphaMask
        )
    }

    private static func interactionResponse(
        scene: SceneSpec,
        visualState: SceneInteractionVisualState,
        camera: SceneCameraTransform,
        drawCommands: [SceneDrawCommand],
        reduceMotion: Bool
    ) throws -> SceneInteractionResponsePlan? {
        guard let direct = visualState.directManipulation else { return nil }
        switch scene.interactionVisualBinding {
        case let .allocate(binding)?:
            return try allocationInteractionResponse(
                direct: direct,
                binding: binding,
                camera: camera,
                drawCommands: drawCommands,
                reduceMotion: reduceMotion
            )
        case let .assemble(binding)?:
            return try assemblyInteractionResponse(
                direct: direct,
                binding: binding,
                scene: scene,
                camera: camera,
                drawCommands: drawCommands,
                reduceMotion: reduceMotion
            )
        default:
            throw SceneFramePlannerError.invalidDirectManipulation
        }
    }

    private static func allocationInteractionResponse(
        direct: SceneDirectManipulationState,
        binding: SceneAllocateVisualBinding,
        camera: SceneCameraTransform,
        drawCommands: [SceneDrawCommand],
        reduceMotion: Bool
    ) throws -> SceneInteractionResponsePlan {
        let destination = direct.targetID.flatMap { targetID in
            binding.destinations.first { $0.interactionTargetID == targetID }
        }
        if direct.targetID != nil, destination == nil {
            throw SceneFramePlannerError.invalidDirectManipulation
        }

        let authoredPath = destination?.transferPath ?? []
        let materialMasterPosition = direct.masterPosition ?? authoredPath.last
        let sourceMotion = motion(
            for: binding.resource.layerID,
            in: drawCommands,
            reduceMotion: reduceMotion
        )
        let destinationMotion = destination.map {
            motion(for: $0.layerID, in: drawCommands, reduceMotion: reduceMotion)
        } ?? .still
        let transferMotion = motion(
            for: binding.transferLayerID,
            in: drawCommands,
            reduceMotion: reduceMotion
        )
        let viewportPath: [SceneFramePoint]
        let viewportMaterialPosition: SceneFramePoint?
        if reduceMotion {
            viewportPath = []
            viewportMaterialPosition = nil
        } else {
            viewportPath = authoredPath.enumerated().map { index, point in
                let attachedMotion: SceneLayerMotionState = if index == 0 {
                    sourceMotion
                } else if index == authoredPath.count - 1 {
                    destinationMotion
                } else {
                    transferMotion
                }
                return project(
                    point: point,
                    through: camera.sourceRect,
                    motion: attachedMotion
                )
            }
            viewportMaterialPosition = materialMasterPosition.map {
                let responseMotion: SceneLayerMotionState = switch direct.phase {
                case .contact, .lift:
                    sourceMotion
                case .carrying:
                    transferMotion
                case .targetContact, .slotApproach, .resistance, .snapBack, .accepted:
                    destinationMotion
                }
                return project(
                    point: $0,
                    through: camera.sourceRect,
                    motion: responseMotion
                )
            }
            guard viewportPath.allSatisfy(isFiniteViewportPoint),
                  viewportMaterialPosition.map(isFiniteViewportPoint) ?? true else {
                throw SceneFramePlannerError.invalidDirectManipulation
            }
        }

        let amounts = responseAmounts(for: direct.phase)
        return SceneInteractionResponsePlan(
            phase: direct.phase,
            targetID: direct.targetID,
            transferLayerID: binding.transferLayerID,
            viewportMaterialPosition: viewportMaterialPosition,
            viewportTransferPath: viewportPath,
            progress: direct.progress,
            contactAmount: amounts.contact,
            resistanceAmount: amounts.resistance
        )
    }

    private static func assemblyInteractionResponse(
        direct: SceneDirectManipulationState,
        binding: SceneAssembleVisualBinding,
        scene: SceneSpec,
        camera: SceneCameraTransform,
        drawCommands: [SceneDrawCommand],
        reduceMotion: Bool
    ) throws -> SceneInteractionResponsePlan {
        guard let componentID = direct.subjectID,
              let sourceTargetID = direct.sourceTargetID,
              let source = binding.components.first(where: {
                  $0.componentID == componentID
                      && $0.sourceInteractionTargetID == sourceTargetID
              }), let sourceCenter = targetCenter(
                  sourceTargetID,
                  in: scene
              ) else {
            throw SceneFramePlannerError.invalidDirectManipulation
        }
        let destination = direct.targetID.flatMap { targetID in
            binding.components.first { $0.slotInteractionTargetID == targetID }
        }
        if direct.targetID != nil, destination == nil {
            throw SceneFramePlannerError.invalidDirectManipulation
        }
        let destinationCenter = try destination.map { component -> NormalizedPoint in
            guard let slotTargetID = component.slotInteractionTargetID,
                  let center = targetCenter(slotTargetID, in: scene) else {
                throw SceneFramePlannerError.invalidDirectManipulation
            }
            return center
        }
        let sourceMotion = motion(
            for: source.layerID,
            in: drawCommands,
            reduceMotion: reduceMotion
        )
        let destinationMotion = destination.map {
            motion(for: $0.layerID, in: drawCommands, reduceMotion: reduceMotion)
        } ?? sourceMotion

        func grabbedAnchor(for fingerPosition: NormalizedPoint) throws -> NormalizedPoint {
            guard let grabOffset = direct.grabOffset else {
                throw SceneFramePlannerError.invalidDirectManipulation
            }
            let anchor = NormalizedPoint(
                x: fingerPosition.x - grabOffset.dx,
                y: fingerPosition.y - grabOffset.dy
            )
            guard anchor.x.isFinite, anchor.y.isFinite else {
                throw SceneFramePlannerError.invalidDirectManipulation
            }
            return anchor
        }

        let masterPath: [(NormalizedPoint, SceneLayerMotionState)]
        let material: (NormalizedPoint, SceneLayerMotionState)?
        switch direct.phase {
        case .contact, .lift:
            guard let position = direct.masterPosition else {
                throw SceneFramePlannerError.invalidDirectManipulation
            }
            masterPath = []
            material = (try grabbedAnchor(for: position), sourceMotion)
        case .carrying:
            guard let position = direct.masterPosition else {
                throw SceneFramePlannerError.invalidDirectManipulation
            }
            let anchor = try grabbedAnchor(for: position)
            masterPath = [(sourceCenter, sourceMotion), (anchor, sourceMotion)]
            material = (anchor, sourceMotion)
        case .slotApproach:
            guard let destinationCenter,
                  let position = direct.masterPosition else {
                throw SceneFramePlannerError.invalidDirectManipulation
            }
            masterPath = [(sourceCenter, sourceMotion), (destinationCenter, destinationMotion)]
            material = (try grabbedAnchor(for: position), destinationMotion)
        case .snapBack:
            guard let position = direct.masterPosition else {
                throw SceneFramePlannerError.invalidDirectManipulation
            }
            let anchor = try grabbedAnchor(for: position)
            let startMotion = destination == nil ? sourceMotion : destinationMotion
            masterPath = [(anchor, startMotion), (sourceCenter, sourceMotion)]
            material = (sourceCenter, sourceMotion)
        case .accepted:
            guard destinationCenter != nil else {
                throw SceneFramePlannerError.invalidDirectManipulation
            }
            // Reducer acceptance has already selected the durable placed
            // variant. Moving that same layer again would double-offset placed
            // art and make the accepted frame diverge from cold restoration.
            masterPath = []
            material = nil
        case .targetContact, .resistance:
            throw SceneFramePlannerError.invalidDirectManipulation
        }

        let viewportPath: [SceneFramePoint]
        let viewportMaterialPosition: SceneFramePoint?
        if reduceMotion {
            viewportPath = []
            viewportMaterialPosition = nil
        } else {
            viewportPath = masterPath.map { point, attachedMotion in
                project(
                    point: point,
                    through: camera.sourceRect,
                    motion: attachedMotion
                )
            }
            viewportMaterialPosition = material.map { point, attachedMotion in
                project(
                    point: point,
                    through: camera.sourceRect,
                    motion: attachedMotion
                )
            }
            guard viewportPath.allSatisfy(isFiniteViewportPoint),
                  viewportMaterialPosition.map(isFiniteViewportPoint) ?? true else {
                throw SceneFramePlannerError.invalidDirectManipulation
            }
        }

        let amounts = responseAmounts(for: direct.phase)
        return SceneInteractionResponsePlan(
            phase: direct.phase,
            targetID: direct.targetID,
            transferLayerID: source.layerID,
            viewportTransferLayerAnchor: reduceMotion
                ? nil
                : project(
                    point: sourceCenter,
                    through: camera.sourceRect,
                    motion: sourceMotion
                ),
            viewportMaterialPosition: viewportMaterialPosition,
            viewportTransferPath: viewportPath,
            progress: direct.progress,
            contactAmount: amounts.contact,
            resistanceAmount: amounts.resistance
        )
    }

    private static func responseAmounts(
        for phase: SceneDirectManipulationPhase
    ) -> (contact: Double, resistance: Double) {
        switch phase {
        case .contact:
            (0.35, 0)
        case .lift:
            (0.55, 0)
        case .carrying:
            (0.15, 0)
        case .targetContact, .slotApproach:
            (1, 0)
        case .resistance, .snapBack:
            (0.8, 1)
        case .accepted:
            (1, 0)
        }
    }

    private static func targetCenter(
        _ targetID: String,
        in scene: SceneSpec
    ) -> NormalizedPoint? {
        guard let path = scene.interactionTargets.first(where: {
            $0.interactionTargetID == targetID
        })?.hitRegion.path, !path.isEmpty else {
            return nil
        }
        let center = NormalizedPoint(
            x: path.reduce(0) { $0 + $1.x } / Double(path.count),
            y: path.reduce(0) { $0 + $1.y } / Double(path.count)
        )
        return center.isUnitPoint ? center : nil
    }

    private static func motion(
        for layerID: SceneLayerID,
        in drawCommands: [SceneDrawCommand],
        reduceMotion: Bool
    ) -> SceneLayerMotionState {
        guard !reduceMotion else { return .still }
        return drawCommands.first(where: { command in
            if case let .layer(id, _) = command.source { return id == layerID }
            return false
        })?.motion ?? .still
    }

    private static func project(
        point: NormalizedPoint,
        through sourceRect: SceneFrameRect,
        motion: SceneLayerMotionState
    ) -> SceneFramePoint {
        let projected = map(
            point: SceneFramePoint(x: point.x, y: point.y),
            through: sourceRect
        )
        return SceneFramePoint(
            x: projected.x + motion.parallaxOffset.dx + motion.windOffset.dx,
            y: projected.y + motion.parallaxOffset.dy + motion.windOffset.dy
        )
    }

    private static func isFiniteViewportPoint(_ point: SceneFramePoint) -> Bool {
        point.x.isFinite && point.y.isFinite
            && (0 ... 1).contains(point.x) && (0 ... 1).contains(point.y)
    }

    private static func atmosphereStates(
        _ specifications: [AtmosphereSpec],
        tick: UInt64,
        reduceMotion: Bool
    ) throws -> [SceneAtmosphereState] {
        try specifications.enumerated().map { index, specification in
            let dx = specification.velocity.dx
            let dy = specification.velocity.dy
            guard specification.density.isFinite,
                  (0 ... 1).contains(specification.density),
                  dx.isFinite, dy.isFinite,
                  (-1 ... 1).contains(dx), (-1 ... 1).contains(dy) else {
                throw SceneFramePlannerError.invalidAtmosphere(index)
            }
            let seconds = Double(tick % 3_600_000) / ticksPerSecond
            let travel = reduceMotion
                ? SceneFrameVector.zero
                : SceneFrameVector(dx: dx * seconds, dy: dy * seconds)
            let count = specification.density == 0
                ? 0
                : max(1, Int((specification.density * Double(atmosphereSampleCapacity)).rounded()))
            let samples = (0 ..< count).map { sampleIndex in
                let offset = UInt64(sampleIndex) &* 0x9E37_79B9_7F4A_7C15
                let x = unitDouble(splitMix64(specification.deterministicSeed &+ offset))
                let y = unitDouble(splitMix64(specification.deterministicSeed &+ offset &+ 1))
                let phase = unitDouble(splitMix64(specification.deterministicSeed &+ offset &+ 2))
                return SceneAtmosphereSample(
                    index: sampleIndex,
                    position: SceneFramePoint(
                        x: wrapUnit(x + travel.dx),
                        y: wrapUnit(y + travel.dy)
                    ),
                    phase: phase
                )
            }
            return SceneAtmosphereState(
                authoredIndex: index,
                kind: specification.kind,
                density: specification.density,
                deterministicSeed: specification.deterministicSeed,
                authoredVelocity: SceneFrameVector(dx: dx, dy: dy),
                travel: travel,
                samples: samples
            )
        }
    }

    private static func aggregateWind(
        _ specifications: [AtmosphereSpec],
        tick: UInt64
    ) -> SceneFrameVector {
        guard !specifications.isEmpty else { return .zero }
        let phase = Double(tick % 3_600_000) / ticksPerSecond
        let pulse = sin(phase * 0.4) * 0.01
        let total = specifications.reduce(SceneFrameVector.zero) { partial, specification in
            SceneFrameVector(
                dx: partial.dx + specification.velocity.dx,
                dy: partial.dy + specification.velocity.dy
            )
        }
        let divisor = Double(specifications.count)
        return SceneFrameVector(
            dx: total.dx / divisor * pulse,
            dy: total.dy / divisor * pulse
        )
    }

    private static func preflightAllAssets(
        in scene: SceneSpec,
        inventory: SceneAssetInventory
    ) throws {
        for layer in scene.layers {
            _ = try resolve(layer.assetPath, from: inventory)
            _ = try resolvedMasks(layer.masks, from: inventory)
            for variant in layer.stateVariants {
                _ = try resolve(variant.assetPath, from: inventory)
                _ = try resolvedMasks(variant.masks, from: inventory)
            }
        }
        for stratum in scene.reduceMotionComposition.strata {
            if let assetPath = stratum.assetPath {
                _ = try resolve(assetPath, from: inventory)
            }
        }
    }

    private static func resolvedMasks(
        _ masks: SceneLayerMaskSet,
        from inventory: SceneAssetInventory
    ) throws -> SceneDrawMaskPlan {
        SceneDrawMaskPlan(
            alpha: try masks.alphaMaskAssetPath.map { try resolve($0, from: inventory) },
            occlusion: try masks.occlusionMaskAssetPath.map { try resolve($0, from: inventory) },
            depth: try masks.depthMaskAssetPath.map { try resolve($0, from: inventory) },
            light: try masks.lightMaskAssetPath.map { try resolve($0, from: inventory) }
        )
    }

    private static func resolve(
        _ packagePath: String,
        from inventory: SceneAssetInventory
    ) throws -> SceneResolvedAsset {
        guard let asset = inventory.resolvedAsset(for: packagePath) else {
            throw SceneFramePlannerError.missingAssetResolution(packagePath)
        }
        return asset
    }

    private static func frameRect(_ rect: NormalizedRect) -> SceneFrameRect {
        SceneFrameRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    private static func validUnitRect(_ rect: SceneFrameRect) -> Bool {
        rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.x >= 0 && rect.y >= 0 && rect.width > 0 && rect.height > 0
            && rect.x + rect.width <= 1 && rect.y + rect.height <= 1
    }

    private static func map(
        point: SceneFramePoint,
        through crop: SceneFrameRect
    ) -> SceneFramePoint {
        SceneFramePoint(
            x: (point.x - crop.x) / crop.width,
            y: (point.y - crop.y) / crop.height
        )
    }

    private static func map(
        rect: SceneFrameRect,
        through crop: SceneFrameRect
    ) -> SceneFrameRect {
        SceneFrameRect(
            x: (rect.x - crop.x) / crop.width,
            y: (rect.y - crop.y) / crop.height,
            width: rect.width / crop.width,
            height: rect.height / crop.height
        )
    }

    private static func interpolate(_ lower: Double, _ upper: Double, amount: Double) -> Double {
        lower + (upper - lower) * amount
    }

    private static func splitMix64(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    private static func unitDouble(_ value: UInt64) -> Double {
        Double(value >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    private static func wrapUnit(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }
}
