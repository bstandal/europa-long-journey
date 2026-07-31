import Foundation
import RealityKit
@testable import ContentKit
@testable import ImmersiveRuntime
import XCTest

final class Chapter01RuntimePackageContextTests: XCTestCase {
    @MainActor
    func testSignedContextOpenEdgeVerifiesAndRealityKitDecodesSharedLibrariesOnce()
        async throws
    {
        let fixture = try loadFixture()
        let admitted = try admit(fixture.packageRoot, fixture: fixture)
        var resolvedPaths: [String] = []
        let context = try Chapter01RuntimePackageContext(
            verifiedPackage: admitted,
            openEdgeResolver: { path in
                resolvedPaths.append(path)
                return try ContentPackageVerifier.verifyImmersiveV2Asset(
                    path: path,
                    in: admitted,
                    packageRoot: fixture.packageRoot
                )
            }
        )

        try await context.prepareSharedLibraryWitnesses()
        try await context.prepareSharedLibraryWitnesses()

        let materialPath = try XCTUnwrap(
            admitted.payload.assets.first(where: { $0.kind == .material })?.path
        )
        let animationPath = try XCTUnwrap(
            admitted.payload.assets.first(where: { $0.kind == .animation })?.path
        )
        XCTAssertEqual(resolvedPaths.filter { $0 == materialPath }.count, 1)
        XCTAssertEqual(resolvedPaths.filter { $0 == animationPath }.count, 1)
        XCTAssertEqual(context.payload, admitted.payload)
        XCTAssertEqual(
            context.manifestDigest,
            admitted.manifest.manifestDigest
        )
        XCTAssertEqual(context.verificationScope, .runtimeAdmission)

        let audio = try XCTUnwrap(
            admitted.payload.assets.first(where: { $0.kind == .audio })
        )
        let audioURL = try context.resolveAsset(audio.id)
        XCTAssertEqual(audioURL.lastPathComponent, URL(fileURLWithPath: audio.path).lastPathComponent)
        XCTAssertEqual(resolvedPaths.last, audio.path)

        let absentID = AssetReference3DID("asset-first-farmers-absent")
        XCTAssertThrowsError(try context.resolveAsset(absentID)) { error in
            XCTAssertEqual(
                error as? Chapter01RuntimePackageContextFailure,
                .missingAsset(id: absentID)
            )
        }
    }

    @MainActor
    func testRepositoryUsesPayloadWorldCellSceneReferencesInsteadOfCatalogPaths()
        async throws
    {
        let fixture = try loadFixture()
        let admitted = try admit(fixture.packageRoot, fixture: fixture)
        let swappedPayload = payloadBySwappingFirstTwoSceneGraphs(
            admitted.payload
        )
        try swappedPayload.validate()
        let testPackage = VerifiedImmersiveContentPackageV2(
            manifest: admitted.manifest,
            payload: swappedPayload,
            verificationScope: .runtimeAdmission
        )
        var witnessLoads: [String] = []
        let context = try Chapter01RuntimePackageContext(
            verifiedPackage: testPackage,
            openEdgeResolver: { path in
                URL(fileURLWithPath: "/payload-authority")
                    .appending(path: path)
            },
            witnessEntityLoader: { url in
                witnessLoads.append(url.path)
                return Entity()
            }
        )
        let expectedCells: [Chapter01WorldCell] = [
            .aegeanPassage,
            .thessalianHousehold,
        ]
        var sceneLoadURLs: [URL] = []
        var sceneLoadIndex = 0
        let repository = Chapter01RealityAssetRepository(
            runtimePackageContext: context,
            entityLoader: { url in
                sceneLoadURLs.append(url)
                let cell = expectedCells[sceneLoadIndex]
                sceneLoadIndex += 1
                return Self.makeValidEntity(
                    for: Chapter01RealityAssetCatalog.descriptor(for: cell)
                )
            }
        )

        _ = try await repository.reconcileResidency(current: .aegeanPassage)

        let assetsByID = Dictionary(
            uniqueKeysWithValues: swappedPayload.assets.map { ($0.id, $0) }
        )
        let expectedScenePaths = try swappedPayload.worldCells.prefix(2).map {
            try XCTUnwrap(assetsByID[$0.sceneGraphAssetID]).path
        }
        XCTAssertEqual(sceneLoadURLs.map(\.path), expectedScenePaths.map {
            URL(fileURLWithPath: "/payload-authority")
                .appending(path: $0).path
        })
        XCTAssertNotEqual(
            expectedScenePaths[0],
            Chapter01RealityAssetCatalog.descriptor(for: .aegeanPassage)
                .packageRelativePath
        )
        XCTAssertEqual(witnessLoads.count, 2)
        XCTAssertEqual(sceneLoadURLs.count, 2)
    }

    @MainActor
    func testTamperedSharedLibraryFailurePropagatesBeforeRealityKitDecode()
        async throws
    {
        let fixture = try loadFixture()
        try await withPackageCopy(fixture.packageRoot) { candidate in
            let admitted = try admit(candidate, fixture: fixture)
            let materialPath = try XCTUnwrap(
                admitted.payload.assets.first(where: { $0.kind == .material })?.path
            )
            let materialURL = candidate.appending(path: materialPath)
            var bytes = try Data(contentsOf: materialURL)
            bytes[bytes.count / 2] ^= 0xff
            try bytes.write(to: materialURL)

            let context = try Chapter01RuntimePackageContext(
                verifiedPackage: admitted,
                openEdgeResolver: { path in
                    try ContentPackageVerifier.verifyImmersiveV2Asset(
                        path: path,
                        in: admitted,
                        packageRoot: candidate
                    )
                },
                witnessEntityLoader: { _ in
                    XCTFail("Tampered bytes must fail before RealityKit decode")
                    return Entity()
                }
            )
            let repository = Chapter01RealityAssetRepository(
                runtimePackageContext: context,
                entityLoader: { _ in
                    XCTFail("A failed shared witness must block scene decode")
                    return Entity()
                }
            )

            do {
                _ = try await repository.reconcileResidency(
                    current: .aegeanPassage
                )
                XCTFail("Expected open-edge integrity failure")
            } catch {
                XCTAssertEqual(
                    error as? PackageVerificationError,
                    .fileDigestMismatch(materialPath)
                )
            }
        }
    }
}

private extension Chapter01RuntimePackageContextTests {
    struct TrustReceipt: Decodable {
        let packageID: String
        let keyID: String
        let trustedPublicKeyX963Base64: String
        let shippingState: String
    }

    struct Fixture {
        let packageRoot: URL
        let expectedPackage: ContentPackageSpec
        let trustedKeys: [String: Data]
    }

    func loadFixture() throws -> Fixture {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let reviewRoot = nativeRoot.appending(
            path: "production/3d/chapter01/review-package",
            directoryHint: .isDirectory
        )
        let receipt = try JSONDecoder().decode(
            TrustReceipt.self,
            from: Data(
                contentsOf: reviewRoot.appending(
                    path: "backstage/review-trust-receipt.json",
                    directoryHint: .notDirectory
                )
            )
        )
        XCTAssertEqual(receipt.packageID, "first-farmers-3d-review-v1")
        XCTAssertEqual(receipt.shippingState, "PROHIBITED")
        return Fixture(
            packageRoot: reviewRoot.appending(
                path: "compiled/first-farmers-3d-review-v1.runtimefixture",
                directoryHint: .isDirectory
            ),
            expectedPackage: ContentPackageSpec(
                id: "first-farmers-3d-review-v1",
                version: SchemaVersion(major: 1),
                chapterIDs: ["first-farmers"],
                maximumInstalledBytes: 200_000_000,
                minimumRuntime: SchemaVersion(major: 2),
                isEssentialInstall: false
            ),
            trustedKeys: [
                receipt.keyID: try XCTUnwrap(
                    Data(base64Encoded: receipt.trustedPublicKeyX963Base64)
                ),
            ]
        )
    }

    func admit(
        _ packageRoot: URL,
        fixture: Fixture
    ) throws -> VerifiedImmersiveContentPackageV2 {
        try ContentPackageVerifier.admitImmersiveV2PackageAtRuntime(
            at: packageRoot,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: fixture.trustedKeys,
            supportedSchema: SchemaVersion(major: 2),
            runtimeVersion: SchemaVersion(major: 2)
        )
    }

    func payloadBySwappingFirstTwoSceneGraphs(
        _ payload: ContentPackagePayloadV2
    ) -> ContentPackagePayloadV2 {
        var cells = payload.worldCells
        let first = cells[0]
        let second = cells[1]
        cells[0] = replacing(
            first,
            sceneGraphAssetID: second.sceneGraphAssetID
        )
        cells[1] = replacing(
            second,
            sceneGraphAssetID: first.sceneGraphAssetID
        )
        return ContentPackagePayloadV2(
            schemaVersion: payload.schemaVersion,
            packageID: payload.packageID,
            chapterID: payload.chapterID,
            pacing: payload.pacing,
            streamingPolicy: payload.streamingPolicy,
            assets: payload.assets,
            worldCells: cells,
            sequences: payload.sequences,
            transitions: payload.transitions,
            audioBindings: payload.audioBindings,
            narrationBindings: payload.narrationBindings,
            captions: payload.captions
        )
    }

    func replacing(
        _ cell: WorldCell3DSpec,
        sceneGraphAssetID: AssetReference3DID
    ) -> WorldCell3DSpec {
        WorldCell3DSpec(
            id: cell.id,
            sceneGraphAssetID: sceneGraphAssetID,
            entities: cell.entities,
            materialBindings: cell.materialBindings,
            animationBindings: cell.animationBindings,
            cameraTracks: cell.cameraTracks,
            semanticActions: cell.semanticActions,
            lodGroups: cell.lodGroups
        )
    }

    @MainActor
    func withPackageCopy(
        _ source: URL,
        operation: @MainActor (URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "chapter01-runtime-context-tests-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let candidate = root.appending(
            path: "package",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: candidate)
        try await operation(candidate)
    }
}

@MainActor
private extension Chapter01RuntimePackageContextTests {
    static func makeValidEntity(
        for descriptor: Chapter01RealityAssetDescriptor
    ) -> Entity {
        let root = Entity()
        root.name = "fixture-\(descriptor.cell.rawValue)"
        let actionNames = Set(descriptor.actionBindingNames)
        for binding in descriptor.requiredBindingNames {
            let entity: Entity
            if actionNames.contains(binding) {
                entity = ModelEntity(
                    mesh: .generateBox(size: 0.25),
                    materials: [
                        SimpleMaterial(color: .white, isMetallic: false),
                    ]
                )
            } else {
                entity = Entity()
            }
            entity.name = binding
            root.addChild(entity)
        }
        return root
    }
}
