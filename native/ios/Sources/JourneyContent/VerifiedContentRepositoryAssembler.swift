import ContentKit
import Foundation

public enum VerifiedContentRepositoryAssemblyError: Error, Equatable, Sendable,
    CustomStringConvertible
{
    case essentialPackageCannotBeDownloaded(PackageID)
    case essentialPackageIdentityMismatch(PackageID)
    case packageNotDeclared(PackageID)

    public var description: String {
        switch self {
        case let .essentialPackageCannotBeDownloaded(packageID):
            return "Downloaded package \(packageID) cannot shadow bundled essential content"
        case let .essentialPackageIdentityMismatch(packageID):
            return "Bundled essential package has the wrong identity: \(packageID)"
        case let .packageNotDeclared(packageID):
            return "Downloaded package \(packageID) is absent from the launch catalog"
        }
    }
}

/// Reconstructs the immutable runtime repository at cold launch. Every active
/// generation must pass signed-manifest, exact-tree, declared-size and payload
/// admission again. Large scene and audio bytes retain their signed digest
/// boundary and are verified when the renderer or audio transport first uses
/// them; activation remains the full-package byte-verification boundary.
public struct VerifiedContentRepositoryAssembler: Sendable {
    public let manifest: CollectionManifest
    public let supportedSchema: SchemaVersion
    public let runtimeVersion: SchemaVersion

    public init(
        manifest: CollectionManifest = LaunchContent.collectionManifest,
        supportedSchema: SchemaVersion = SchemaVersion(major: 1),
        runtimeVersion: SchemaVersion = SchemaVersion(major: 1)
    ) {
        self.manifest = manifest
        self.supportedSchema = supportedSchema
        self.runtimeVersion = runtimeVersion
    }

    public func assemble(
        bundledEssentialData: Data,
        activeDownloadedPackageRoots: [PackageID: URL],
        trustedPublicKeys: [String: Data]
    ) throws -> ContentRepository {
        if activeDownloadedPackageRoots[LaunchContent.essentialPackageID] != nil {
            throw VerifiedContentRepositoryAssemblyError
                .essentialPackageCannotBeDownloaded(LaunchContent.essentialPackageID)
        }

        let packageByID = Dictionary(
            uniqueKeysWithValues: manifest.packages.map { ($0.id, $0) }
        )
        for packageID in activeDownloadedPackageRoots.keys
            where packageByID[packageID] == nil {
            throw VerifiedContentRepositoryAssemblyError.packageNotDeclared(packageID)
        }

        let bundledPayload = try BundledEssentialContentLoader()
            .decodePayload(data: bundledEssentialData)
        var verifiedPackages: [VerifiedContentPackage] = []
        for package in manifest.packages where package.id != LaunchContent.essentialPackageID {
            guard let root = activeDownloadedPackageRoots[package.id] else { continue }
            verifiedPackages.append(
                try verifyDownloadedPackage(
                    at: root,
                    expectedPackage: package,
                    trustedPublicKeys: trustedPublicKeys
                )
            )
        }

        return try assemble(
            bundledEssentialPayload: bundledPayload,
            verifiedPackages: verifiedPackages
        )
    }

    /// Admits one actor-resolved immutable generation against the exact launch
    /// package contract without hashing every large asset during cold start.
    /// Callers may use this narrow operation to keep an unrelated damaged
    /// package out of an otherwise valid repository.
    public func verifyDownloadedPackage(
        at root: URL,
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys: [String: Data]
    ) throws -> VerifiedContentPackage {
        try ContentPackageVerifier.admitPackageAtRuntime(
            at: root,
            expectedPackage: expectedPackage,
            trustedPublicKeys: trustedPublicKeys,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion
        )
    }

    /// Runtime-admits the code-signed essential package with the same signed
    /// manifest, exact inventory and package contract used for downloaded
    /// generations. App code signing protects the bundled directory; every
    /// scene/audio asset remains bound to the approved launch manifest and is
    /// digest-verified at its first decode/open boundary.
    public func verifyBundledEssentialPackage(
        at root: URL,
        trustedPublicKeys: [String: Data]
    ) throws -> VerifiedContentPackage {
        guard let expected = manifest.packages.first(where: {
            $0.id == LaunchContent.essentialPackageID
        }) else {
            throw VerifiedContentRepositoryAssemblyError.packageNotDeclared(
                LaunchContent.essentialPackageID
            )
        }
        return try ContentPackageVerifier.admitPackageAtRuntime(
            at: root,
            expectedPackage: expected,
            trustedPublicKeys: trustedPublicKeys,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion
        )
    }

    /// Joins a code-signed essential payload to generations which have
    /// already crossed a verifier-created package boundary in this process.
    public func assemble(
        bundledEssentialPayload: ContentPackagePayload,
        verifiedPackages: [VerifiedContentPackage]
    ) throws -> ContentRepository {
        try ContentRepository(
            manifest: manifest,
            bundledEssentialPayload: bundledEssentialPayload,
            verifiedPackages: verifiedPackages
        )
    }

    /// Joins only a verifier-created essential package. Keeping this value
    /// intact lets the app construct the Metal asset inventory from the same
    /// trust decision that admitted the chapter prose and scene contracts.
    public func assemble(
        verifiedBundledEssentialPackage: VerifiedContentPackage,
        verifiedPackages: [VerifiedContentPackage]
    ) throws -> ContentRepository {
        guard verifiedBundledEssentialPackage.manifest.packageID
                == LaunchContent.essentialPackageID,
              verifiedBundledEssentialPackage.payload.packageID
                == LaunchContent.essentialPackageID else {
            throw VerifiedContentRepositoryAssemblyError
                .essentialPackageIdentityMismatch(
                    verifiedBundledEssentialPackage.payload.packageID
                )
        }
        return try assemble(
            bundledEssentialPayload: verifiedBundledEssentialPackage.payload,
            verifiedPackages: verifiedPackages
        )
    }
}
