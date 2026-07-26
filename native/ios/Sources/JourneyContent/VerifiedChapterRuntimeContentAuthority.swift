import ContentDelivery
import ContentKit
import Foundation

/// The smallest immutable production authority required to open one chapter:
/// repository indices, verifier-created package values and actor-resolved
/// roots all captured at one revision. Launch chapters and later deep dives
/// use this exact shape at the ChapterRuntime boundary.
public struct VerifiedChapterRuntimeContentAuthority: Sendable {
    public let revision: UInt64
    public let repository: ContentRepository
    public let packageRootURLs: [PackageID: URL]
    public let verifiedPackagesByID: [PackageID: VerifiedContentPackage]
    public let installedGenerationsByPackageID: [
        PackageID: InstalledPackageGeneration
    ]

    public init(
        revision: UInt64,
        repository: ContentRepository,
        packageRootURLs: [PackageID: URL],
        verifiedPackagesByID: [PackageID: VerifiedContentPackage],
        installedGenerationsByPackageID: [
            PackageID: InstalledPackageGeneration
        ]
    ) {
        self.revision = revision
        self.repository = repository
        self.packageRootURLs = packageRootURLs
        self.verifiedPackagesByID = verifiedPackagesByID
        self.installedGenerationsByPackageID = installedGenerationsByPackageID
    }

    public func packageRootURL(for packageID: PackageID) -> URL? {
        packageRootURLs[packageID]
    }

    public func verifiedPackage(
        for packageID: PackageID
    ) -> VerifiedContentPackage? {
        verifiedPackagesByID[packageID]
    }

    public func assetFailureAuthority(
        for packageID: PackageID
    ) -> PackageAssetFailureAuthority? {
        guard let verified = verifiedPackagesByID[packageID] else { return nil }
        let installedGeneration = installedGenerationsByPackageID[packageID]
        if packageID != LaunchContent.essentialPackageID {
            guard let installedGeneration,
                  installedGeneration.manifestDigest
                    == verified.manifest.manifestDigest else {
                return nil
            }
        }
        return PackageAssetFailureAuthority(
            snapshotRevision: revision,
            packageID: packageID,
            installedGeneration: installedGeneration,
            manifestDigest: verified.manifest.manifestDigest
        )
    }
}

public extension VerifiedJourneyContentSnapshot {
    var chapterRuntimeAuthority: VerifiedChapterRuntimeContentAuthority {
        VerifiedChapterRuntimeContentAuthority(
            revision: revision,
            repository: repository,
            packageRootURLs: packageRootURLs,
            verifiedPackagesByID: verifiedPackagesByID,
            installedGenerationsByPackageID: Dictionary(
                uniqueKeysWithValues: reconciledInstalledIndex
                    .activeGenerationByPackage.keys.compactMap { packageID in
                        reconciledInstalledIndex.activeGeneration(for: packageID)
                            .map { (packageID, $0) }
                    }
            )
        )
    }
}

public extension VerifiedFutureReleaseContentSnapshot {
    func chapterRuntimeAuthority(
        for releaseID: ReleaseID
    ) -> VerifiedChapterRuntimeContentAuthority? {
        guard let content = content(for: releaseID) else { return nil }
        let packageID = content.release.packageID
        return VerifiedChapterRuntimeContentAuthority(
            revision: revision,
            repository: content.repository,
            packageRootURLs: [packageID: content.packageRootURL],
            verifiedPackagesByID: [packageID: content.verifiedPackage],
            installedGenerationsByPackageID: [
                packageID: content.installedGeneration,
            ]
        )
    }
}
