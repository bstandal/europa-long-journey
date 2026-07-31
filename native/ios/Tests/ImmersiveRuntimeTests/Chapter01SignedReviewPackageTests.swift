import ContentKit
import Foundation
import XCTest

#if canImport(AVFAudio)
import AVFAudio
#endif

final class Chapter01SignedReviewPackageTests: XCTestCase {
    func testSignedReviewPackageLoadsCompletelyOfflineAndAdmitsAssetsAtOpenEdge() throws {
        let fixture = try loadFixture()

        let complete = try ContentPackageVerifier.verifyImmersiveV2Package(
            at: fixture.packageRoot,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: fixture.trustedKeys,
            supportedSchema: SchemaVersion(major: 2),
            runtimeVersion: SchemaVersion(major: 2)
        )
        XCTAssertEqual(complete.verificationScope, .completePackage)
        XCTAssertEqual(complete.payload.packageID.rawValue, "first-farmers-3d-review-v1")
        XCTAssertEqual(complete.payload.worldCells.count, 5)
        XCTAssertEqual(complete.payload.sequences.count, 6)
        XCTAssertEqual(complete.payload.sequences.flatMap(\.beats).count, 34)

        let admitted = try ContentPackageVerifier.admitImmersiveV2PackageAtRuntime(
            at: fixture.packageRoot,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: fixture.trustedKeys,
            supportedSchema: SchemaVersion(major: 2),
            runtimeVersion: SchemaVersion(major: 2)
        )
        XCTAssertEqual(admitted.verificationScope, .runtimeAdmission)
        let scenePath = try XCTUnwrap(
            admitted.payload.assets.first(where: { $0.kind == .sceneGraph })?.path
        )
        let sceneURL = try ContentPackageVerifier.verifyImmersiveV2Asset(
            path: scenePath,
            in: admitted,
            packageRoot: fixture.packageRoot
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sceneURL.path))
    }

    func testSignedReviewPackageRejectsMissingCorruptAndTamperedFiles() throws {
        let fixture = try loadFixture()
        let assetPath = "immersive/first-farmers/cells/cell-01.usdz"
        let payloadPath = "chapters/first-farmers-3d-review-v1.json"

        try withPackageCopy(fixture.packageRoot) { candidate in
            try FileManager.default.removeItem(at: candidate.appending(path: assetPath))
            XCTAssertThrowsError(try verify(candidate, fixture: fixture))
        }

        try withPackageCopy(fixture.packageRoot) { candidate in
            let url = candidate.appending(path: assetPath)
            var data = try Data(contentsOf: url)
            data[data.count / 2] ^= 0xff
            try data.write(to: url)
            let admitted = try ContentPackageVerifier.admitImmersiveV2PackageAtRuntime(
                at: candidate,
                expectedPackage: fixture.expectedPackage,
                trustedPublicKeys: fixture.trustedKeys,
                supportedSchema: SchemaVersion(major: 2),
                runtimeVersion: SchemaVersion(major: 2)
            )
            XCTAssertThrowsError(
                try ContentPackageVerifier.verifyImmersiveV2Asset(
                    path: assetPath,
                    in: admitted,
                    packageRoot: candidate
                )
            ) { error in
                XCTAssertEqual(
                    error as? PackageVerificationError,
                    .fileDigestMismatch(assetPath)
                )
            }
            XCTAssertThrowsError(try verify(candidate, fixture: fixture)) { error in
                XCTAssertEqual(
                    error as? PackageVerificationError,
                    .fileDigestMismatch(assetPath)
                )
            }
        }

        try withPackageCopy(fixture.packageRoot) { candidate in
            let url = candidate.appending(path: payloadPath)
            var data = try Data(contentsOf: url)
            let marker = try XCTUnwrap(data.range(of: Data("first-farmers".utf8)))
            data[marker.lowerBound] = Character("x").asciiValue!
            try data.write(to: url)
            XCTAssertThrowsError(try verify(candidate, fixture: fixture)) { error in
                XCTAssertEqual(
                    error as? PackageVerificationError,
                    .fileDigestMismatch(payloadPath)
                )
            }
        }
    }

#if canImport(AVFAudio)
    func testEverySignedPackageAudioProgramIsOfflineDecodableAt48k() throws {
        let fixture = try loadFixture()
        let admitted = try ContentPackageVerifier.admitImmersiveV2PackageAtRuntime(
            at: fixture.packageRoot,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: fixture.trustedKeys,
            supportedSchema: SchemaVersion(major: 2),
            runtimeVersion: SchemaVersion(major: 2)
        )
        XCTAssertEqual(
            Dictionary(grouping: admitted.payload.audioBindings, by: \.role)
                .mapValues(\.count),
            [
                .environment: 5,
                .mechanism: 6,
                .transition: 6,
                .narration: 10,
            ]
        )
        let assetsByID = Dictionary(
            uniqueKeysWithValues: admitted.payload.assets.map { ($0.id, $0) }
        )
        for binding in admitted.payload.audioBindings {
            let asset = try XCTUnwrap(assetsByID[binding.assetID])
            let url = try ContentPackageVerifier.verifyImmersiveV2Asset(
                path: asset.path,
                in: admitted,
                packageRoot: fixture.packageRoot
            )
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.processingFormat.sampleRate, 48_000)
            XCTAssertGreaterThan(file.length, 0)
        }
    }
#endif
}

private extension Chapter01SignedReviewPackageTests {
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
        let packageRoot = reviewRoot.appending(
            path: "compiled/first-farmers-3d-review-v1.runtimefixture",
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
        let key = try XCTUnwrap(Data(base64Encoded: receipt.trustedPublicKeyX963Base64))
        return Fixture(
            packageRoot: packageRoot,
            expectedPackage: ContentPackageSpec(
                id: "first-farmers-3d-review-v1",
                version: SchemaVersion(major: 1),
                chapterIDs: ["first-farmers"],
                maximumInstalledBytes: 200_000_000,
                minimumRuntime: SchemaVersion(major: 2),
                isEssentialInstall: false
            ),
            trustedKeys: [receipt.keyID: key]
        )
    }

    func verify(_ packageRoot: URL, fixture: Fixture) throws -> VerifiedImmersiveContentPackageV2 {
        try ContentPackageVerifier.verifyImmersiveV2Package(
            at: packageRoot,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: fixture.trustedKeys,
            supportedSchema: SchemaVersion(major: 2),
            runtimeVersion: SchemaVersion(major: 2)
        )
    }

    func withPackageCopy(
        _ source: URL,
        operation: (URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "chapter01-v2-package-tests-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let candidate = root.appending(path: "package", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: candidate)
        try operation(candidate)
    }
}
