import ContentDelivery
import ContentKit
import Foundation
import XCTest

final class ImmersiveV2PackageActivationTests: XCTestCase {
    func testSignedImmersiveFixtureUsesExistingAtomicActivationAuthority() async throws {
        let fixture = try loadFixture()
        let managedRoot = FileManager.default.temporaryDirectory.appending(
            path: "chapter01-v2-activation-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: managedRoot) }
        let activator = try PackageActivator(
            rootURL: managedRoot,
            verifier: ImmersiveContentPackageV2ActivationVerifier(),
            generationID: { "chapter01-review-generation" }
        )
        let staging = try await activator.makeStagingDirectory()
        for child in try FileManager.default.contentsOfDirectory(
            at: fixture.packageRoot,
            includingPropertiesForKeys: nil
        ) {
            try FileManager.default.copyItem(
                at: child,
                to: staging.appending(path: child.lastPathComponent)
            )
        }

        let activated = try await activator.activate(
            stagedPackageURL: staging,
            expectedPackage: fixture.expectedPackage,
            trustedPublicKeys: fixture.trustedKeys,
            supportedSchema: SchemaVersion(major: 2),
            runtimeVersion: SchemaVersion(major: 2)
        )
        XCTAssertEqual(activated.generation.packageID.rawValue, "first-farmers-3d-review-v1")
        let activePackage = try await activator.activePackage(
            for: "first-farmers-3d-review-v1"
        )
        XCTAssertEqual(activePackage, activated)
        let retained = try await activator.retainedPackageLocations(
            for: "first-farmers-3d-review-v1"
        )
        XCTAssertEqual(retained.activePackage, activated)
        XCTAssertNil(retained.previousPackage)
    }
}

private extension ImmersiveV2PackageActivationTests {
    struct TrustReceipt: Decodable {
        let keyID: String
        let trustedPublicKeyX963Base64: String
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
            from: Data(contentsOf: reviewRoot.appending(path: "backstage/review-trust-receipt.json"))
        )
        let key = try XCTUnwrap(Data(base64Encoded: receipt.trustedPublicKeyX963Base64))
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
            trustedKeys: [receipt.keyID: key]
        )
    }
}
