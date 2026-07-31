import ContentKit
import CryptoKit
import Foundation
import XCTest

final class SaveMigrationManifestTests: XCTestCase {
    func testIntegrityMaterialBindsCanonicalMigrationDeclaration() throws {
        let declaration = PackageSaveMigrationDeclaration(
            id: "save-one-to-two",
            fromContentVersion: SchemaVersion(major: 1),
            toContentVersion: SchemaVersion(major: 2),
            requiredSaveFormatVersion: 1,
            requiredStateSchemaVersion: 3,
            fields: PackageSaveMigrationField.allCases.sorted {
                $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8)
            },
            worldOwnershipDelta: Self.worldOwnershipDelta,
            implementationSHA256: String(repeating: "c", count: 64)
        )
        let base = manifest(declaration: declaration)
        let material = String(
            decoding: try ContentPackageVerifier.integrityMaterial(for: base),
            as: UTF8.self
        )
        XCTAssertTrue(material.contains(
            "saveMigration=save-one-to-two\t1.0.0\t2.0.0\tsave=1\tstate=3"
        ))

        let changed = PackageSaveMigrationDeclaration(
            id: declaration.id,
            fromContentVersion: declaration.fromContentVersion,
            toContentVersion: declaration.toContentVersion,
            requiredSaveFormatVersion: declaration.requiredSaveFormatVersion,
            requiredStateSchemaVersion: declaration.requiredStateSchemaVersion,
            fields: declaration.fields,
            worldOwnershipDelta: declaration.worldOwnershipDelta,
            implementationSHA256: String(repeating: "d", count: 64)
        )
        XCTAssertNotEqual(
            try ContentPackageVerifier.manifestDigest(for: base),
            try ContentPackageVerifier.manifestDigest(for: manifest(declaration: changed))
        )
    }

    func testVerifiedManifestAuthenticatesMigrationDeclarationAndRejectsTamper() throws {
        let declaration = canonicalDeclaration(
            implementationSHA256: String(repeating: "c", count: 64)
        )
        let privateKey = P256.Signing.PrivateKey()
        let draft = manifest(declaration: declaration)
        let digest = try ContentPackageVerifier.manifestDigest(for: draft)
        let signature = try privateKey.signature(for: Data(digest.utf8))
        let signed = signedManifest(
            declaration: declaration,
            digest: digest,
            signature: signature.derRepresentation.base64EncodedString()
        )
        let expected = ContentPackageSpec(
            id: "migration-test-pack",
            version: SchemaVersion(major: 2),
            chapterIDs: ["migration-test-chapter"],
            maximumInstalledBytes: 100_000,
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: false
        )
        let encoded = try canonicalEncoder.encode(signed)
        let verified = try ContentPackageVerifier.verifyManifest(
            encoded,
            expectedPackage: expected,
            trustedPublicKeys: [
                "migration-test-key": privateKey.publicKey.x963Representation,
            ],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1)
        )
        XCTAssertEqual(verified.saveMigrations, [declaration])

        let tampered = signedManifest(
            declaration: canonicalDeclaration(
                implementationSHA256: String(repeating: "d", count: 64)
            ),
            digest: digest,
            signature: signature.derRepresentation.base64EncodedString()
        )
        XCTAssertThrowsError(
            try ContentPackageVerifier.verifyManifest(
                canonicalEncoder.encode(tampered),
                expectedPackage: expected,
                trustedPublicKeys: [
                    "migration-test-key": privateKey.publicKey.x963Representation,
                ],
                supportedSchema: SchemaVersion(major: 1),
                runtimeVersion: SchemaVersion(major: 1)
            )
        ) { error in
            XCTAssertEqual(error as? PackageVerificationError, .invalidManifestDigest)
        }
    }

    func testVerifierRejectsIncompleteAndAmbiguousGraphsBeforeActivation() throws {
        let v1 = SchemaVersion(major: 1)
        let v2 = SchemaVersion(major: 2)
        let v3 = SchemaVersion(major: 3)
        let incomplete = graphDeclaration(id: "one-to-two", from: v1, to: v2)
        XCTAssertThrowsError(try ContentPackageVerifier.integrityMaterial(for: graphManifest(
            packageVersion: v3,
            supportedSources: [v1],
            declarations: [incomplete]
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("no complete path"))
        }

        let ambiguous = [
            graphDeclaration(id: "direct-one-to-three", from: v1, to: v3),
            graphDeclaration(id: "one-to-two", from: v1, to: v2),
            graphDeclaration(id: "two-to-three", from: v2, to: v3),
        ]
        XCTAssertThrowsError(try ContentPackageVerifier.integrityMaterial(for: graphManifest(
            packageVersion: v3,
            supportedSources: [v1, v2],
            declarations: ambiguous
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("ambiguous paths"))
        }
    }

    func testVerifierRejectsMissingOrUnknownWorldOwnership() throws {
        let v1 = SchemaVersion(major: 1)
        let v2 = SchemaVersion(major: 2)
        let missing = PackageSaveMigrationDeclaration(
            id: "world-one-to-two",
            fromContentVersion: v1,
            toContentVersion: v2,
            requiredSaveFormatVersion: 1,
            requiredStateSchemaVersion: 3,
            fields: [.cumulativeWorldState],
            implementationSHA256: String(repeating: "c", count: 64)
        )
        XCTAssertThrowsError(try ContentPackageVerifier.integrityMaterial(for: graphManifest(
            packageVersion: v2,
            supportedSources: [v1],
            declarations: [missing]
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("world ownership"))
        }

        let unknown = PackageSaveMigrationDeclaration(
            id: "world-one-to-two",
            fromContentVersion: v1,
            toContentVersion: v2,
            requiredSaveFormatVersion: 1,
            requiredStateSchemaVersion: 3,
            fields: [.cumulativeWorldState],
            worldOwnershipDelta: PackageSaveMigrationWorldOwnershipDelta(
                newEffectIDs: [WorldEffectID("not a stable id")]
            ),
            implementationSHA256: String(repeating: "c", count: 64)
        )
        XCTAssertThrowsError(try ContentPackageVerifier.integrityMaterial(for: graphManifest(
            packageVersion: v2,
            supportedSources: [v1],
            declarations: [unknown]
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("stable, unique and canonical"))
        }

        let owned = PackageSaveMigrationDeclaration(
            id: "world-one-to-two",
            fromContentVersion: v1,
            toContentVersion: v2,
            requiredSaveFormatVersion: 1,
            requiredStateSchemaVersion: 3,
            fields: [.cumulativeWorldState],
            worldOwnershipDelta: PackageSaveMigrationWorldOwnershipDelta(
                newEffectIDs: ["effect-owned-world"]
            ),
            implementationSHA256: String(repeating: "c", count: 64)
        )
        let encoded = try canonicalEncoder.encode(graphManifest(
            packageVersion: v2,
            supportedSources: [v1],
            declarations: [owned]
        ))
        let unknownCategoryJSON = String(decoding: encoded, as: UTF8.self).replacingOccurrences(
            of: "\"newTraceIDs\":[]",
            with: "\"newTraceIDs\":[],\"oldSettlementIDs\":[]"
        )
        let publicKey = P256.Signing.PrivateKey().publicKey.x963Representation
        XCTAssertThrowsError(try ContentPackageVerifier.verifyManifest(
            Data(unknownCategoryJSON.utf8),
            expectedPackage: ContentPackageSpec(
                id: "migration-test-pack",
                version: v2,
                chapterIDs: ["migration-test-chapter"],
                maximumInstalledBytes: 100_000,
                minimumRuntime: v1,
                isEssentialInstall: false
            ),
            trustedPublicKeys: ["migration-test-key": publicKey],
            supportedSchema: v1,
            runtimeVersion: v1
        )) { error in
            XCTAssertTrue(String(describing: error).contains("fields are not canonical"))
        }
    }

    private func manifest(
        declaration: PackageSaveMigrationDeclaration
    ) -> SignedPackageManifest {
        SignedPackageManifest(
            packageID: "migration-test-pack",
            packageVersion: SchemaVersion(major: 2),
            schemaVersion: SchemaVersion(major: 1),
            minimumRuntime: SchemaVersion(major: 1),
            saveMigrationSupportedSourceVersions: [SchemaVersion(major: 1)],
            saveMigrationDescriptorInventorySHA256: String(repeating: "e", count: 64),
            saveMigrations: [declaration],
            files: [
                PackageFileRecord(
                    path: "payload.json",
                    bytes: 1,
                    sha256: String(repeating: "a", count: 64)
                ),
            ],
            manifestDigest: String(repeating: "0", count: 64),
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "migration-test-key",
                value: "AA=="
            )
        )
    }

    private func signedManifest(
        declaration: PackageSaveMigrationDeclaration,
        digest: String,
        signature: String
    ) -> SignedPackageManifest {
        SignedPackageManifest(
            packageID: "migration-test-pack",
            packageVersion: SchemaVersion(major: 2),
            schemaVersion: SchemaVersion(major: 1),
            minimumRuntime: SchemaVersion(major: 1),
            saveMigrationSupportedSourceVersions: [SchemaVersion(major: 1)],
            saveMigrationDescriptorInventorySHA256: String(repeating: "e", count: 64),
            saveMigrations: [declaration],
            files: [
                PackageFileRecord(
                    path: "payload.json",
                    bytes: 1,
                    sha256: String(repeating: "a", count: 64)
                ),
            ],
            manifestDigest: digest,
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "migration-test-key",
                value: signature
            )
        )
    }

    private func canonicalDeclaration(
        implementationSHA256: String
    ) -> PackageSaveMigrationDeclaration {
        PackageSaveMigrationDeclaration(
            id: "save-one-to-two",
            fromContentVersion: SchemaVersion(major: 1),
            toContentVersion: SchemaVersion(major: 2),
            requiredSaveFormatVersion: 1,
            requiredStateSchemaVersion: 3,
            fields: PackageSaveMigrationField.allCases.sorted {
                $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8)
            },
            worldOwnershipDelta: Self.worldOwnershipDelta,
            implementationSHA256: implementationSHA256
        )
    }

    private func graphDeclaration(
        id: String,
        from: SchemaVersion,
        to: SchemaVersion
    ) -> PackageSaveMigrationDeclaration {
        PackageSaveMigrationDeclaration(
            id: id,
            fromContentVersion: from,
            toContentVersion: to,
            requiredSaveFormatVersion: 1,
            requiredStateSchemaVersion: 3,
            fields: [.beatIdentity],
            implementationSHA256: String(repeating: "c", count: 64)
        )
    }

    private func graphManifest(
        packageVersion: SchemaVersion,
        supportedSources: [SchemaVersion],
        declarations: [PackageSaveMigrationDeclaration]
    ) -> SignedPackageManifest {
        SignedPackageManifest(
            packageID: "migration-test-pack",
            packageVersion: packageVersion,
            schemaVersion: SchemaVersion(major: 1),
            minimumRuntime: SchemaVersion(major: 1),
            saveMigrationSupportedSourceVersions: supportedSources,
            saveMigrationDescriptorInventorySHA256: String(repeating: "e", count: 64),
            saveMigrations: declarations,
            files: [
                PackageFileRecord(
                    path: "payload.json",
                    bytes: 1,
                    sha256: String(repeating: "a", count: 64)
                ),
            ],
            manifestDigest: String(repeating: "0", count: 64),
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "migration-test-key",
                value: "AA=="
            )
        )
    }

    private static let worldOwnershipDelta = PackageSaveMigrationWorldOwnershipDelta(
        oldEffectIDs: ["effect-old-world"],
        newEffectIDs: ["effect-new-world"],
        oldNodeIDs: ["old-world-node"],
        newNodeIDs: ["new-world-node"],
        oldTraceIDs: ["old-world-trace"],
        newTraceIDs: ["new-world-trace"]
    )

    private var canonicalEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
