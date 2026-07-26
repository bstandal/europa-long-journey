import ContentDelivery
@testable import ContentKit
import Foundation
@testable import JourneyContent
import JourneyPersistence
import ProgressStore
import XCTest

final class VerifiedSaveMigrationAuthoritySetTests: XCTestCase {
    func testExactLaunchSnapshotBuildsByteBoundEssentialAndActivePaidAuthorities() throws {
        let essential = verifiedPackage(
            payload: JourneyContentFixtures.package("essential-free-v1"),
            digestByte: "a"
        )
        let paid = verifiedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            digestByte: "b"
        )
        let generation = installedGeneration(for: paid, sequence: 9)
        let snapshot = try launchSnapshot(
            verifiedPackages: [essential, paid],
            generations: [generation]
        )

        let result = try VerifiedSaveMigrationAuthoritySet(
            launchSnapshot: snapshot,
            futureReleaseSnapshot: .empty
        )

        XCTAssertEqual(result.authorities.map(\.packageID), [
            "essential-free-v1", "paid-pack-01",
        ])
        XCTAssertEqual(
            result.identities[0].generationID,
            "code-signed-essential-\(essential.manifest.manifestDigest)"
        )
        XCTAssertEqual(
            result.identities[0].source,
            .codeSignedEssential
        )
        XCTAssertEqual(result.identities[0].activationSequence, 0)
        XCTAssertEqual(result.identities[1].generationID, generation.generationID)
        XCTAssertEqual(result.identities[1].source, .launchDownload)
    }

    func testPaidAuthorityFailsClosedWhenGenerationDoesNotMatchVerifiedManifest() throws {
        let essential = verifiedPackage(
            payload: JourneyContentFixtures.package("essential-free-v1"),
            digestByte: "a"
        )
        let paid = verifiedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            digestByte: "b"
        )
        let mismatched = InstalledPackageGeneration(
            generationID: "paid-pack-mismatch",
            packageID: paid.manifest.packageID,
            packageVersion: paid.manifest.packageVersion,
            manifestDigest: String(repeating: "c", count: 64),
            relativePath: "generations/paid-pack-mismatch",
            activationSequence: 2
        )
        let snapshot = try launchSnapshot(
            verifiedPackages: [essential, paid],
            generations: [mismatched]
        )

        XCTAssertThrowsError(try VerifiedSaveMigrationAuthoritySet(
            launchSnapshot: snapshot,
            futureReleaseSnapshot: .empty
        )) { error in
            XCTAssertEqual(
                error as? VerifiedSaveMigrationAuthoritySetError,
                .activeGenerationMismatch("paid-pack-01")
            )
        }
    }

    func testFutureReleaseAuthorityComesFromItsExactVerifiedContentAndGeneration() throws {
        let essential = verifiedPackage(
            payload: JourneyContentFixtures.package("essential-free-v1"),
            digestByte: "a"
        )
        let launch = try launchSnapshot(
            verifiedPackages: [essential],
            generations: []
        )
        let futurePayload = JourneyContentFixtures.futurePackage()
        let futurePackage = verifiedPackage(
            payload: futurePayload,
            digestByte: "d"
        )
        let release = Release(
            id: "release-alpha-v1",
            contentID: "alpha-deep-dive",
            packageID: futurePayload.packageID,
            version: futurePayload.schemaVersion,
            chapterIDs: futurePayload.chapters.map(\.id),
            maximumInstalledBytes: 1_000_000,
            publishedAtUnixMillis: 1_700_000_000_000,
            minimumRuntime: futurePayload.schemaVersion
        )
        let generation = installedGeneration(
            for: futurePackage,
            sequence: 11
        )
        let future = VerifiedFutureReleaseContent(
            release: release,
            repository: try ContentRepository(
                trustedFutureRelease: release,
                verifiedPackage: futurePackage,
                expectedWorldSeed: futurePayload.worldSeed
            ),
            packageRootURL: URL(fileURLWithPath: "/tmp/future-alpha"),
            installedGeneration: generation,
            verifiedPackage: futurePackage
        )
        let snapshot = VerifiedFutureReleaseContentSnapshot(
            revision: 4,
            contentsByReleaseID: [release.id: future],
            unavailableInstalledPackageIDs: []
        )

        let result = try VerifiedSaveMigrationAuthoritySet(
            launchSnapshot: launch,
            futureReleaseSnapshot: snapshot
        )

        XCTAssertEqual(result.identities.map(\.packageID), [
            "deep-dive-alpha-v1", "essential-free-v1",
        ])
        let identity = try XCTUnwrap(result.identities.first)
        XCTAssertEqual(identity.source, .futureRelease)
        XCTAssertEqual(identity.generationID, generation.generationID)
        XCTAssertEqual(identity.manifestDigest, futurePackage.manifest.manifestDigest)
    }

    func testSnapshotCannotExposeAPathWithoutAVerifiedPackage() throws {
        let essential = verifiedPackage(
            payload: JourneyContentFixtures.package("essential-free-v1"),
            digestByte: "a"
        )
        let repository = try ContentRepository(
            packagePayloads: [essential.payload]
        )
        let snapshot = VerifiedJourneyContentSnapshot(
            revision: 1,
            repository: repository,
            reconciledInstalledIndex: .empty,
            packageRootURLs: [
                "essential-free-v1": URL(fileURLWithPath: "/tmp/essential"),
                "paid-pack-01": URL(fileURLWithPath: "/tmp/unverified"),
            ],
            verifiedPackagesByID: ["essential-free-v1": essential]
        )

        XCTAssertThrowsError(try VerifiedSaveMigrationAuthoritySet(
            launchSnapshot: snapshot,
            futureReleaseSnapshot: .empty
        )) { error in
            XCTAssertEqual(
                error as? VerifiedSaveMigrationAuthoritySetError,
                .unexpectedPackageRoot("paid-pack-01")
            )
        }
    }

    func testDuplicateFuturePackageAuthorityFailsClosedWithoutDictionaryTrap()
        throws
    {
        let essential = verifiedPackage(
            payload: JourneyContentFixtures.package("essential-free-v1"),
            digestByte: "a"
        )
        let launch = try launchSnapshot(
            verifiedPackages: [essential],
            generations: []
        )
        let payload = JourneyContentFixtures.futurePackage()
        let package = verifiedPackage(payload: payload, digestByte: "d")
        let firstRelease = futureRelease(
            id: "duplicate-alpha-v1",
            contentID: try XCTUnwrap(payload.chapters.first).id.rawValue,
            payload: payload
        )
        let secondRelease = futureRelease(
            id: "duplicate-beta-v1",
            contentID: try XCTUnwrap(payload.chapters.first).id.rawValue,
            payload: payload
        )
        let first = try futureContent(
            release: firstRelease,
            package: package,
            sequence: 12
        )
        let second = try futureContent(
            release: secondRelease,
            package: package,
            sequence: 13
        )
        let snapshot = VerifiedFutureReleaseContentSnapshot(
            revision: 5,
            contentsByReleaseID: [
                firstRelease.id: first,
                secondRelease.id: second,
            ],
            unavailableInstalledPackageIDs: []
        )

        XCTAssertThrowsError(try
            VerifiedFutureReleaseSaveMigrationGenerations(snapshot: snapshot)
        ) { error in
            XCTAssertEqual(
                error as? VerifiedSaveMigrationAuthoritySetError,
                .duplicatePackageAuthority(payload.packageID)
            )
        }
        XCTAssertThrowsError(try VerifiedSaveMigrationAuthoritySet(
            launchSnapshot: launch,
            futureReleaseSnapshot: snapshot
        )) { error in
            XCTAssertEqual(
                error as? VerifiedSaveMigrationAuthoritySetError,
                .duplicatePackageAuthority(payload.packageID)
            )
        }
    }

    private func launchSnapshot(
        verifiedPackages: [VerifiedContentPackage],
        generations: [InstalledPackageGeneration]
    ) throws -> VerifiedJourneyContentSnapshot {
        let active = Dictionary(uniqueKeysWithValues: generations.map {
            ($0.packageID, $0.generationID)
        })
        let index = InstalledPackageIndex(
            nextActivationSequence:
                (generations.map(\.activationSequence).max() ?? 0) + 1,
            generations: generations,
            activeGenerationByPackage: active
        )
        return VerifiedJourneyContentSnapshot(
            revision: 3,
            repository: try ContentRepository(
                packagePayloads: verifiedPackages.map(\.payload)
            ),
            reconciledInstalledIndex: index,
            packageRootURLs: Dictionary(uniqueKeysWithValues:
                verifiedPackages.map {
                    ($0.manifest.packageID, URL(
                        fileURLWithPath: "/tmp/\($0.manifest.packageID.rawValue)"
                    ))
                }
            ),
            verifiedPackagesByID: Dictionary(uniqueKeysWithValues:
                verifiedPackages.map { ($0.manifest.packageID, $0) }
            )
        )
    }

    private func verifiedPackage(
        payload: ContentPackagePayload,
        digestByte: Character
    ) -> VerifiedContentPackage {
        let digest = String(repeating: String(digestByte), count: 64)
        return VerifiedContentPackage(
            manifest: SignedPackageManifest(
                packageID: payload.packageID,
                packageVersion: payload.schemaVersion,
                schemaVersion: payload.schemaVersion,
                minimumRuntime: payload.schemaVersion,
                files: [],
                manifestDigest: digest,
                signature: PackageSignature(
                    algorithm: ContentPackageVerifier.signatureAlgorithm,
                    keyID: "fixture-key",
                    value: Data([0]).base64EncodedString()
                )
            ),
            payload: payload
        )
    }

    private func futureRelease(
        id: ReleaseID,
        contentID: String,
        payload: ContentPackagePayload
    ) -> Release {
        Release(
            id: id,
            contentID: contentID,
            packageID: payload.packageID,
            version: payload.schemaVersion,
            chapterIDs: payload.chapters.map(\.id),
            maximumInstalledBytes: 1_000_000,
            publishedAtUnixMillis: 1_700_000_000_000,
            minimumRuntime: payload.schemaVersion
        )
    }

    private func futureContent(
        release: Release,
        package: VerifiedContentPackage,
        sequence: UInt64
    ) throws -> VerifiedFutureReleaseContent {
        VerifiedFutureReleaseContent(
            release: release,
            repository: try ContentRepository(
                trustedFutureRelease: release,
                verifiedPackage: package,
                expectedWorldSeed: package.payload.worldSeed
            ),
            packageRootURL: URL(
                fileURLWithPath: "/tmp/\(release.id.rawValue)"
            ),
            installedGeneration: installedGeneration(
                for: package,
                sequence: sequence
            ),
            verifiedPackage: package
        )
    }

    private func installedGeneration(
        for package: VerifiedContentPackage,
        sequence: UInt64
    ) -> InstalledPackageGeneration {
        InstalledPackageGeneration(
            generationID:
                "generation-\(package.manifest.packageID.rawValue)-\(sequence)",
            packageID: package.manifest.packageID,
            packageVersion: package.manifest.packageVersion,
            manifestDigest: package.manifest.manifestDigest,
            relativePath:
                "generations/generation-\(package.manifest.packageID.rawValue)-\(sequence)",
            activationSequence: sequence
        )
    }
}
