import ContentKit
import CryptoKit
import Foundation
@testable import JourneyContent
import XCTest

final class VerifiedContentRepositoryAssemblerTests: XCTestCase {
    func testBundledEssentialContentCrossesRuntimeAdmissionBoundary() throws {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let signed = try makeSignedPackage(payload: essential)
        defer { try? FileManager.default.removeItem(at: signed.root) }
        let assembler = VerifiedContentRepositoryAssembler()

        let verified = try assembler.verifyBundledEssentialPackage(
            at: signed.root,
            trustedPublicKeys: ["test-launch-key": signed.publicKey]
        )
        let repository = try assembler.assemble(
            verifiedBundledEssentialPackage: verified,
            verifiedPackages: []
        )

        XCTAssertEqual(repository.availablePackageIDs, ["essential-free-v1"])
        XCTAssertEqual(verified.verificationScope, .runtimeAdmission)
        XCTAssertEqual(verified.manifest.packageID, LaunchContent.essentialPackageID)
        XCTAssertEqual(verified.payload.chapters.map(\.id), [
            "first-farmers", "europe-holds-the-line", "european-world",
        ])
    }

    func testBundledEssentialTamperingFailsBeforeARepositoryExists() throws {
        let signed = try makeSignedPackage(
            payload: JourneyContentFixtures.package("essential-free-v1")
        )
        defer { try? FileManager.default.removeItem(at: signed.root) }
        try Data("tampered-essential".utf8).write(
            to: signed.payloadURL,
            options: .atomic
        )

        XCTAssertThrowsError(
            try VerifiedContentRepositoryAssembler().verifyBundledEssentialPackage(
                at: signed.root,
                trustedPublicKeys: ["test-launch-key": signed.publicKey]
            )
        ) { error in
            XCTAssertEqual(
                error as? PackageVerificationError,
                .fileSizeMismatch("content/payload.json")
            )
        }
    }

    func testColdLaunchRuntimeAdmitsDownloadedPackageBeforeIndexingIt() throws {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let paid = JourneyContentFixtures.package("paid-pack-01")
        let bundledData = try ContentDocumentDecoder.encodePackage(essential)
        let signed = try makeSignedPackage(payload: paid)
        defer { try? FileManager.default.removeItem(at: signed.root) }

        let repository = try VerifiedContentRepositoryAssembler().assemble(
            bundledEssentialData: bundledData,
            activeDownloadedPackageRoots: ["paid-pack-01": signed.root],
            trustedPublicKeys: ["test-launch-key": signed.publicKey]
        )

        XCTAssertEqual(
            repository.availablePackageIDs,
            ["essential-free-v1", "paid-pack-01"]
        )
        XCTAssertNotNil(repository.chapter("steppe-comes-west"))

        let admitted = try VerifiedContentRepositoryAssembler().verifyDownloadedPackage(
            at: signed.root,
            expectedPackage: try XCTUnwrap(
                LaunchContent.collectionManifest.packages.first {
                    $0.id == "paid-pack-01"
                }
            ),
            trustedPublicKeys: ["test-launch-key": signed.publicKey]
        )
        XCTAssertEqual(admitted.verificationScope, .runtimeAdmission)
    }

    func testColdLaunchRejectsBytesChangedAfterActivation() throws {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let paid = JourneyContentFixtures.package("paid-pack-01")
        let signed = try makeSignedPackage(payload: paid)
        defer { try? FileManager.default.removeItem(at: signed.root) }
        try Data("tampered".utf8).write(to: signed.payloadURL, options: .atomic)

        XCTAssertThrowsError(
            try VerifiedContentRepositoryAssembler().assemble(
                bundledEssentialData: ContentDocumentDecoder.encodePackage(essential),
                activeDownloadedPackageRoots: ["paid-pack-01": signed.root],
                trustedPublicKeys: ["test-launch-key": signed.publicKey]
            )
        ) { error in
            XCTAssertEqual(
                error as? PackageVerificationError,
                .fileSizeMismatch("content/payload.json")
            )
        }
    }

    func testDownloadedRootsCannotShadowEssentialOrInventAPackage() throws {
        let essentialData = try ContentDocumentDecoder.encodePackage(
            JourneyContentFixtures.package("essential-free-v1")
        )
        let absent = URL(fileURLWithPath: "/package-does-not-need-to-exist")
        let assembler = VerifiedContentRepositoryAssembler()

        XCTAssertThrowsError(
            try assembler.assemble(
                bundledEssentialData: essentialData,
                activeDownloadedPackageRoots: ["essential-free-v1": absent],
                trustedPublicKeys: [:]
            )
        ) { error in
            XCTAssertEqual(
                error as? VerifiedContentRepositoryAssemblyError,
                .essentialPackageCannotBeDownloaded("essential-free-v1")
            )
        }

        XCTAssertThrowsError(
            try assembler.assemble(
                bundledEssentialData: essentialData,
                activeDownloadedPackageRoots: ["invented-package": absent],
                trustedPublicKeys: [:]
            )
        ) { error in
            XCTAssertEqual(
                error as? VerifiedContentRepositoryAssemblyError,
                .packageNotDeclared("invented-package")
            )
        }
    }

    private func makeSignedPackage(
        payload: ContentPackagePayload
    ) throws -> (root: URL, payloadURL: URL, publicKey: Data) {
        let package = try XCTUnwrap(
            LaunchContent.collectionManifest.packages.first { $0.id == payload.packageID }
        )
        let root = FileManager.default.temporaryDirectory.appending(
            path: "verified-repository-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let payloadPath = "content/payload.json"
        let payloadURL = root.appending(path: payloadPath)
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payloadData = try ContentDocumentDecoder.encodePackage(payload)
        try payloadData.write(to: payloadURL)

        let privateKey = P256.Signing.PrivateKey()
        let unsigned = SignedPackageManifest(
            packageID: payload.packageID,
            packageVersion: package.version,
            schemaVersion: payload.schemaVersion,
            minimumRuntime: package.minimumRuntime,
            files: [
                PackageFileRecord(
                    path: payloadPath,
                    bytes: Int64(payloadData.count),
                    sha256: Self.sha256(payloadData)
                ),
            ],
            manifestDigest: String(repeating: "0", count: 64),
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "test-launch-key",
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
                keyID: "test-launch-key",
                value: signature.derRepresentation.base64EncodedString()
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(
            to: root.appending(path: ContentPackageVerifier.manifestFileName),
            options: .atomic
        )
        return (root, payloadURL, privateKey.publicKey.x963Representation)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
