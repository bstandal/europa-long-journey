import ContentKit
import Foundation

public enum LaunchDownloadPlanError: Error, Equatable, Sendable {
    case maximumInstalledByteBudgetOverflow
}

/// The signed launch contract's authority over one active package generation.
///
/// A missing generation and an older generation both require the expected
/// package. An exact match is current. A newer generation is protected: this
/// runtime must neither classify it as current nor replace it with an older
/// package.
public enum InstalledPackageVersionAuthority: Equatable, Sendable {
    case updateRequired(installedVersion: SchemaVersion?)
    case current
    case protectedNewer(installedVersion: SchemaVersion)

    public init(
        activeGeneration: InstalledPackageGeneration?,
        expectedVersion: SchemaVersion
    ) {
        guard let activeGeneration else {
            self = .updateRequired(installedVersion: nil)
            return
        }
        if activeGeneration.packageVersion < expectedVersion {
            self = .updateRequired(installedVersion: activeGeneration.packageVersion)
        } else if activeGeneration.packageVersion == expectedVersion {
            self = .current
        } else {
            self = .protectedNewer(installedVersion: activeGeneration.packageVersion)
        }
    }
}

/// A newer integrity-checked generation that this runtime cannot interpret as
/// the signed version it was compiled to expect.
public struct ProtectedNewerPackageVersion: Equatable, Sendable {
    public let packageID: PackageID
    public let installedVersion: SchemaVersion
    public let expectedVersion: SchemaVersion

    public init(
        packageID: PackageID,
        installedVersion: SchemaVersion,
        expectedVersion: SchemaVersion
    ) {
        self.packageID = packageID
        self.installedVersion = installedVersion
        self.expectedVersion = expectedVersion
    }
}

/// An older active generation that remains pending until the signed expected
/// package has been installed.
public struct OutdatedPackageVersion: Equatable, Sendable {
    public let packageID: PackageID
    public let installedVersion: SchemaVersion
    public let expectedVersion: SchemaVersion

    public init(
        packageID: PackageID,
        installedVersion: SchemaVersion,
        expectedVersion: SchemaVersion
    ) {
        self.packageID = packageID
        self.installedVersion = installedVersion
        self.expectedVersion = expectedVersion
    }
}

/// The paid launch packages that still need a current active generation.
///
/// `remainingMaximumInstalledBytes` is a conservative storage budget from the
/// validated collection contract. It is not an observed or promised transfer size.
public struct LaunchDownloadPlan: Equatable, Sendable {
    public let packages: [ContentPackageSpec]
    public let outdatedPackages: [OutdatedPackageVersion]
    public let protectedNewerPackages: [ProtectedNewerPackageVersion]
    public let remainingMaximumInstalledBytes: Int64

    public init(
        manifest: CollectionManifest = LaunchContent.collectionManifest,
        installedIndex: InstalledPackageIndex
    ) throws {
        try manifest.validateLaunch()
        try installedIndex.validate()

        let packageByID = Dictionary(uniqueKeysWithValues: manifest.packages.map { ($0.id, $0) })
        var pendingPackages: [ContentPackageSpec] = []
        var outdatedPackages: [OutdatedPackageVersion] = []
        var protectedPackages: [ProtectedNewerPackageVersion] = []
        for packageID in LaunchContent.packageIDsInDeliveryOrder {
            guard packageID != LaunchContent.essentialPackageID,
                  let package = packageByID[packageID] else {
                continue
            }
            switch InstalledPackageVersionAuthority(
                activeGeneration: installedIndex.activeGeneration(for: packageID),
                expectedVersion: package.version
            ) {
            case let .updateRequired(installedVersion):
                pendingPackages.append(package)
                if let installedVersion {
                    outdatedPackages.append(OutdatedPackageVersion(
                        packageID: packageID,
                        installedVersion: installedVersion,
                        expectedVersion: package.version
                    ))
                }
            case .current:
                break
            case let .protectedNewer(installedVersion):
                protectedPackages.append(ProtectedNewerPackageVersion(
                    packageID: packageID,
                    installedVersion: installedVersion,
                    expectedVersion: package.version
                ))
            }
        }
        packages = pendingPackages
        self.outdatedPackages = outdatedPackages
        protectedNewerPackages = protectedPackages
        remainingMaximumInstalledBytes = try Self.maximumInstalledByteBudget(for: packages)
    }

    static func maximumInstalledByteBudget(
        for packages: [ContentPackageSpec]
    ) throws -> Int64 {
        var total: Int64 = 0
        for package in packages {
            let result = total.addingReportingOverflow(package.maximumInstalledBytes)
            guard !result.overflow else {
                throw LaunchDownloadPlanError.maximumInstalledByteBudgetOverflow
            }
            total = result.partialValue
        }
        return total
    }
}
