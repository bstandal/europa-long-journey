import ContentKit
import Foundation
import RealityKit

public enum Chapter01RuntimePackageContextFailure:
    Error,
    Equatable,
    LocalizedError
{
    case missingAsset(id: AssetReference3DID)
    case missingWorldCell(id: WorldCell3DID)
    case unexpectedAssetKind(
        id: AssetReference3DID,
        expected: ImmersiveAssetKind,
        actual: ImmersiveAssetKind
    )
    case sharedLibraryCardinality(kind: ImmersiveAssetKind, count: Int)

    public var errorDescription: String? {
        switch self {
        case let .missingAsset(id):
            "The verified Chapter 01 payload does not declare asset \(id.rawValue)."
        case let .missingWorldCell(id):
            "The verified Chapter 01 payload does not declare world cell \(id.rawValue)."
        case let .unexpectedAssetKind(id, expected, actual):
            "Asset \(id.rawValue) is \(actual.rawValue), not \(expected.rawValue)."
        case let .sharedLibraryCardinality(kind, count):
            "Chapter 01 requires one shared \(kind.rawValue) library; the payload declares \(count)."
        }
    }
}

/// The verified, signed-package boundary retained for one Chapter 01 runtime.
///
/// Every URL is obtained through the caller's open-edge verifier after an
/// `AssetReference3DID` has been resolved through the authoritative V2
/// payload. The context owns no historical state and exposes no animation
/// completion callback. Material and animation libraries are decoded only as
/// package witnesses until authored bindings are ready to consume them.
@MainActor
public final class Chapter01RuntimePackageContext {
    public typealias OpenEdgeResolver = @MainActor (String) throws -> URL
    public typealias WitnessEntityLoader = @MainActor (URL) async throws -> Entity

    private final class DecodedEntityBox: @unchecked Sendable {
        let entity: Entity

        init(_ entity: Entity) {
            self.entity = entity
        }
    }

    public let payload: ContentPackagePayloadV2
    public let manifestDigest: String
    public let verificationScope: ContentPackageVerificationScope

    private let assetsByID: [AssetReference3DID: AssetReference3DSpec]
    private let worldCellsByID: [WorldCell3DID: WorldCell3DSpec]
    private let openEdgeResolver: OpenEdgeResolver
    private let witnessEntityLoader: WitnessEntityLoader
    private let materialLibraryAssetID: AssetReference3DID
    private let animationLibraryAssetID: AssetReference3DID
    private var decodedWitnesses: [AssetReference3DID: Entity] = [:]
    private var witnessDecodeTasks: [
        AssetReference3DID: Task<DecodedEntityBox, Error>
    ] = [:]

    public init(
        verifiedPackage: VerifiedImmersiveContentPackageV2,
        openEdgeResolver: @escaping OpenEdgeResolver,
        witnessEntityLoader: @escaping WitnessEntityLoader = {
            try await Entity(contentsOf: $0)
        }
    ) throws {
        try verifiedPackage.payload.validate()

        payload = verifiedPackage.payload
        manifestDigest = verifiedPackage.manifest.manifestDigest
        verificationScope = verifiedPackage.verificationScope
        assetsByID = Dictionary(
            uniqueKeysWithValues: verifiedPackage.payload.assets.map {
                ($0.id, $0)
            }
        )
        worldCellsByID = Dictionary(
            uniqueKeysWithValues: verifiedPackage.payload.worldCells.map {
                ($0.id, $0)
            }
        )
        self.openEdgeResolver = openEdgeResolver
        self.witnessEntityLoader = witnessEntityLoader

        let materialIDs = Set(
            verifiedPackage.payload.worldCells
                .flatMap(\.materialBindings)
                .flatMap(\.states)
                .map(\.assetID)
        )
        guard materialIDs.count == 1, let materialID = materialIDs.first else {
            throw Chapter01RuntimePackageContextFailure
                .sharedLibraryCardinality(
                    kind: .material,
                    count: materialIDs.count
                )
        }
        materialLibraryAssetID = materialID

        let animationIDs = Set(
            verifiedPackage.payload.worldCells
                .flatMap(\.animationBindings)
                .flatMap(\.states)
                .map(\.assetID)
        )
        guard animationIDs.count == 1,
              let animationID = animationIDs.first else {
            throw Chapter01RuntimePackageContextFailure
                .sharedLibraryCardinality(
                    kind: .animation,
                    count: animationIDs.count
                )
        }
        animationLibraryAssetID = animationID
    }

    /// Resolves any payload asset by stable ID, preserving the payload path as
    /// the only authority passed into signed open-edge verification.
    public func resolveAsset(_ id: AssetReference3DID) throws -> URL {
        let asset = try assetReference(id)
        return try openEdgeResolver(asset.path)
    }

    public func assetReference(
        _ id: AssetReference3DID
    ) throws -> AssetReference3DSpec {
        guard let asset = assetsByID[id] else {
            throw Chapter01RuntimePackageContextFailure.missingAsset(id: id)
        }
        return asset
    }

    public func sceneGraphAssetID(
        for cell: Chapter01WorldCell
    ) throws -> AssetReference3DID {
        let payloadCellID = Chapter01ImmersiveV2Authority.worldCellIDs[
            Chapter01WorldCell.allCases.firstIndex(of: cell)!
        ]
        guard let payloadCell = worldCellsByID[payloadCellID] else {
            throw Chapter01RuntimePackageContextFailure.missingWorldCell(
                id: payloadCellID
            )
        }
        return payloadCell.sceneGraphAssetID
    }

    public func resolveSceneGraph(
        for cell: Chapter01WorldCell
    ) throws -> URL {
        let assetID = try sceneGraphAssetID(for: cell)
        return try resolveAsset(assetID, expectedKind: .sceneGraph)
    }

    /// Verifies and RealityKit-decodes the two shared libraries once for this
    /// runtime context. The decoded witnesses remain detached from the world.
    public func prepareSharedLibraryWitnesses() async throws {
        try await decodeWitnessOnce(
            materialLibraryAssetID,
            expectedKind: .material
        )
        try await decodeWitnessOnce(
            animationLibraryAssetID,
            expectedKind: .animation
        )
    }

    private func resolveAsset(
        _ id: AssetReference3DID,
        expectedKind: ImmersiveAssetKind
    ) throws -> URL {
        let asset = try assetReference(id)
        guard asset.kind == expectedKind else {
            throw Chapter01RuntimePackageContextFailure.unexpectedAssetKind(
                id: id,
                expected: expectedKind,
                actual: asset.kind
            )
        }
        return try openEdgeResolver(asset.path)
    }

    private func decodeWitnessOnce(
        _ id: AssetReference3DID,
        expectedKind: ImmersiveAssetKind
    ) async throws {
        if decodedWitnesses[id] != nil {
            return
        }
        if let task = witnessDecodeTasks[id] {
            let box = try await task.value
            decodedWitnesses[id] = box.entity
            return
        }

        let url = try resolveAsset(id, expectedKind: expectedKind)
        let loader = witnessEntityLoader
        let task = Task { @MainActor in
            DecodedEntityBox(try await loader(url))
        }
        witnessDecodeTasks[id] = task
        do {
            let box = try await task.value
            decodedWitnesses[id] = box.entity
            witnessDecodeTasks[id] = nil
        } catch {
            witnessDecodeTasks[id] = nil
            throw error
        }
    }
}
