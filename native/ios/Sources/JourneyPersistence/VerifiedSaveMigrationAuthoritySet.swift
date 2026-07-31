import ContentDelivery
import ContentKit
import Foundation
import JourneyContent
import ProgressStore

public enum VerifiedSaveMigrationAuthoritySetError: Error, Equatable, Sendable {
    case missingEssentialPackage(PackageID)
    case unexpectedDownloadedEssentialGeneration(PackageID)
    case missingPackageRoot(PackageID)
    case unexpectedPackageRoot(PackageID)
    case missingActiveGeneration(PackageID)
    case activeGenerationMismatch(PackageID)
    case futureReleaseIdentityMismatch(ReleaseID)
    case duplicatePackageAuthority(PackageID)
}

/// Stable identity of the exact verified package bytes and durable activation
/// pointer used by one `ProgressStore` restoration.
public struct SaveMigrationPackageAuthorityIdentity: Equatable, Sendable {
    public enum Source: String, Codable, Equatable, Sendable {
        case codeSignedEssential
        case launchDownload
        case futureRelease
    }

    public let source: Source
    public let packageID: PackageID
    public let targetContentVersion: SchemaVersion
    public let manifestDigest: String
    public let generationID: String
    public let activationSequence: UInt64

    public init(
        source: Source,
        packageID: PackageID,
        targetContentVersion: SchemaVersion,
        manifestDigest: String,
        generationID: String,
        activationSequence: UInt64
    ) {
        self.source = source
        self.packageID = packageID
        self.targetContentVersion = targetContentVersion
        self.manifestDigest = manifestDigest
        self.generationID = generationID
        self.activationSequence = activationSequence
    }
}

/// Exact active generations carried by a verified future-release snapshot.
/// Multiple releases cannot silently claim the same package identity: such a
/// snapshot is malformed and must fail before rollback selection.
public struct VerifiedFutureReleaseSaveMigrationGenerations: Sendable {
    public let byPackageID: [PackageID: InstalledPackageGeneration]

    public init(snapshot: VerifiedFutureReleaseContentSnapshot) throws {
        var generations: [PackageID: InstalledPackageGeneration] = [:]
        for releaseID in snapshot.contentsByReleaseID.keys.sorted() {
            guard let content = snapshot.content(for: releaseID),
                  content.release.id == releaseID,
                  content.installedGeneration.packageID
                    == content.release.packageID else {
                throw VerifiedSaveMigrationAuthoritySetError
                    .futureReleaseIdentityMismatch(releaseID)
            }
            let packageID = content.release.packageID
            guard generations.updateValue(
                content.installedGeneration,
                forKey: packageID
            ) == nil else {
                throw VerifiedSaveMigrationAuthoritySetError
                    .duplicatePackageAuthority(packageID)
            }
        }
        byPackageID = generations
    }
}

/// The complete migration authority for one restoration. Callers cannot add a
/// raw manifest or generation: construction begins at immutable snapshots
/// published by the verified launch and future-release repositories.
public struct VerifiedSaveMigrationAuthoritySet: Sendable {
    public let authorities: [VerifiedPackageSaveMigrationAuthority]
    public let identities: [SaveMigrationPackageAuthorityIdentity]

    public init(
        launchSnapshot: VerifiedJourneyContentSnapshot,
        futureReleaseSnapshot: VerifiedFutureReleaseContentSnapshot
    ) throws {
        var records = try Self.launchRecords(from: launchSnapshot)
        records.append(contentsOf: try Self.futureReleaseRecords(
            from: futureReleaseSnapshot
        ))
        records.sort { $0.identity.packageID < $1.identity.packageID }

        for pair in zip(records, records.dropFirst())
            where pair.0.identity.packageID == pair.1.identity.packageID {
            throw VerifiedSaveMigrationAuthoritySetError
                .duplicatePackageAuthority(pair.0.identity.packageID)
        }
        authorities = records.map(\.authority)
        identities = records.map(\.identity)
    }

    private struct Record {
        let authority: VerifiedPackageSaveMigrationAuthority
        let identity: SaveMigrationPackageAuthorityIdentity
    }

    private static func launchRecords(
        from snapshot: VerifiedJourneyContentSnapshot
    ) throws -> [Record] {
        let essentialID = LaunchContent.essentialPackageID
        guard let essential = snapshot.verifiedPackage(for: essentialID) else {
            throw VerifiedSaveMigrationAuthoritySetError
                .missingEssentialPackage(essentialID)
        }
        guard snapshot.packageRootURL(for: essentialID) != nil else {
            throw VerifiedSaveMigrationAuthoritySetError
                .missingPackageRoot(essentialID)
        }
        guard snapshot.reconciledInstalledIndex.activeGeneration(
            for: essentialID
        ) == nil else {
            throw VerifiedSaveMigrationAuthoritySetError
                .unexpectedDownloadedEssentialGeneration(essentialID)
        }

        var records = [try codeSignedEssentialRecord(essential)]
        for packageID in snapshot.verifiedPackagesByID.keys.sorted()
            where packageID != essentialID {
            guard let verified = snapshot.verifiedPackage(for: packageID) else {
                continue
            }
            guard snapshot.packageRootURL(for: packageID) != nil else {
                throw VerifiedSaveMigrationAuthoritySetError
                    .missingPackageRoot(packageID)
            }
            guard let generation = snapshot.reconciledInstalledIndex
                .activeGeneration(for: packageID) else {
                throw VerifiedSaveMigrationAuthoritySetError
                    .missingActiveGeneration(packageID)
            }
            records.append(try downloadedRecord(
                verified: verified,
                generation: generation,
                source: .launchDownload
            ))
        }

        for packageID in snapshot.packageRootURLs.keys
            where snapshot.verifiedPackage(for: packageID) == nil {
            throw VerifiedSaveMigrationAuthoritySetError
                .unexpectedPackageRoot(packageID)
        }
        return records
    }

    private static func futureReleaseRecords(
        from snapshot: VerifiedFutureReleaseContentSnapshot
    ) throws -> [Record] {
        try snapshot.contentsByReleaseID.keys.sorted().map { releaseID in
            guard let content = snapshot.content(for: releaseID),
                  content.release.id == releaseID,
                  content.release.packageID == content.verifiedPackage.manifest.packageID,
                  content.repository.availablePackageIDs == [content.release.packageID],
                  content.packageRootURL.isFileURL else {
                throw VerifiedSaveMigrationAuthoritySetError
                    .futureReleaseIdentityMismatch(releaseID)
            }
            return try downloadedRecord(
                verified: content.verifiedPackage,
                generation: content.installedGeneration,
                source: .futureRelease
            )
        }
    }

    private static func codeSignedEssentialRecord(
        _ verified: VerifiedContentPackage
    ) throws -> Record {
        let manifest = verified.manifest
        guard manifest.packageID == LaunchContent.essentialPackageID else {
            throw VerifiedSaveMigrationAuthoritySetError
                .missingEssentialPackage(LaunchContent.essentialPackageID)
        }

        // The signed manifest digest covers the canonical package contract and
        // every declared file hash. It therefore supplies a reproducible,
        // byte-bound identity for immutable code-signed content without
        // pretending that the bundle came through PackageActivator.
        let generation = ActiveSaveMigrationPackageGeneration(
            generationID: "code-signed-essential-\(manifest.manifestDigest)",
            packageID: manifest.packageID,
            packageVersion: manifest.packageVersion,
            manifestDigest: manifest.manifestDigest,
            activationSequence: 0
        )
        return Record(
            authority: try VerifiedPackageSaveMigrationAuthority(
                verifiedPackage: verified,
                activeGeneration: generation
            ),
            identity: SaveMigrationPackageAuthorityIdentity(
                source: .codeSignedEssential,
                packageID: manifest.packageID,
                targetContentVersion: manifest.packageVersion,
                manifestDigest: manifest.manifestDigest,
                generationID: generation.generationID,
                activationSequence: generation.activationSequence
            )
        )
    }

    private static func downloadedRecord(
        verified: VerifiedContentPackage,
        generation: InstalledPackageGeneration,
        source: SaveMigrationPackageAuthorityIdentity.Source
    ) throws -> Record {
        let manifest = verified.manifest
        guard generation.packageID == manifest.packageID,
              generation.packageVersion == manifest.packageVersion,
              generation.manifestDigest == manifest.manifestDigest else {
            throw VerifiedSaveMigrationAuthoritySetError
                .activeGenerationMismatch(manifest.packageID)
        }
        let active = ActiveSaveMigrationPackageGeneration(
            generationID: generation.generationID,
            packageID: generation.packageID,
            packageVersion: generation.packageVersion,
            manifestDigest: generation.manifestDigest,
            activationSequence: generation.activationSequence
        )
        return Record(
            authority: try VerifiedPackageSaveMigrationAuthority(
                verifiedPackage: verified,
                activeGeneration: active
            ),
            identity: SaveMigrationPackageAuthorityIdentity(
                source: source,
                packageID: manifest.packageID,
                targetContentVersion: manifest.packageVersion,
                manifestDigest: manifest.manifestDigest,
                generationID: generation.generationID,
                activationSequence: generation.activationSequence
            )
        )
    }
}

/// One reviewed registry for every production restoration. It deliberately
/// remains empty until a real signed migration declaration and matching
/// compiled transform are added together.
public enum JourneySaveMigrationRuntime {
    public static let compiledRegistry = SaveMigrationRegistry.empty
}
