import ContentKit
import Foundation

/// UI-neutral state for one launch package in canonical delivery order.
public enum DownloadPackagePresentationState: Equatable, Sendable {
    /// The package ships in the app and is never part of a paid download queue.
    case includedInApp
    /// The active installed index has not been loaded yet.
    case awaitingBootstrap
    /// The active integrity-checked generation satisfies the launch contract.
    case installedCurrent
    /// The launch contract still requires this paid package.
    case pending
    /// An older active generation is present and the signed expected package
    /// remains in the download plan.
    case updatePending(
        installedVersion: SchemaVersion,
        expectedVersion: SchemaVersion
    )
    /// A newer integrity-checked generation is present. This runtime cannot
    /// open or replace it; a newer app is required.
    case requiresNewerApp(
        installedVersion: SchemaVersion,
        expectedVersion: SchemaVersion
    )

    /// Presentation admission only. A `true` value means an installed
    /// generation may be offered to the Journey's exact verified-runtime
    /// authority check; it never supplies content authority by itself.
    ///
    /// In particular, an outdated retained generation remains playable while
    /// its separately requestable update is pending. An uninstalled,
    /// unbootstrapped or protected-newer package cannot proceed to opening.
    public var allowsVerifiedInstalledGenerationOpen: Bool {
        switch self {
        case .includedInApp, .installedCurrent, .updatePending:
            true
        case .awaitingBootstrap, .pending, .requiresNewerApp:
            false
        }
    }
}

/// Localisation-ready chapter metadata for a package row. No rendered or
/// locale-selected string is manufactured by the delivery layer.
public struct DownloadPackageChapterPresentation: Equatable, Sendable {
    public let id: ChapterID
    public let sequence: Int
    public let title: LocalizedStringSpec
    public let period: LocalizedStringSpec
}

public struct DownloadPackagePresentationRow: Equatable, Identifiable, Sendable {
    public let id: PackageID
    public let canonicalOrder: Int
    public let maximumInstalledBytes: Int64
    public let chapters: [DownloadPackageChapterPresentation]
    public let state: DownloadPackagePresentationState
}

/// Commands exposed by the presentation projection. Queue pause is named for
/// its exact boundary: the current package finishes verification and atomic
/// activation before the application queue pauses. There is intentionally no
/// byte-pause, transfer-resume, cancellation or deletion command here.
public enum DownloadPresentationCommand: Equatable, Hashable, Sendable {
    case requestSinglePackage(PackageID)
    case requestDownloadAll
    case requestQueuePauseAfterCurrentPackage
    case resumeApplicationQueue
    case retryFailedPackage
    case removeFailedPackage
    case refreshInstalledChapters
    case discardStaleQueue
}

public enum DownloadPresentationProjectionError: Error, Equatable, Sendable {
    case invalidLaunchContract
    case invalidAwaitingBootstrapSnapshot
    case nonCanonicalInstalledPackageIDs([PackageID])
    case nonCanonicalPendingPackageIDs([PackageID])
    case nonCanonicalOutdatedPackageIDs([PackageID])
    case invalidOutdatedPackageVersion(OutdatedPackageVersion)
    case outdatedPackagesAreNotPending
    case nonCanonicalProtectedNewerPackageIDs([PackageID])
    case invalidProtectedNewerPackageVersion(ProtectedNewerPackageVersion)
    case installedPendingAndProtectedPackagesDoNotPartitionPaidLaunchPackages
    case remainingMaximumInstalledBytesMismatch(expected: Int64, actual: Int64)
    case invalidInstallationState
    case inconsistentSystemTransferState
}

/// A complete, UI-neutral download surface derived from exactly one
/// `DownloadControllerSnapshot` and the compiled launch contract.
///
/// The application queue and Apple's observed system-transfer state remain
/// separate public values. The latter never grants a command: Background
/// Assets can report a paused transfer without giving this layer a byte-exact
/// pause or resume control.
public struct DownloadPresentationProjection: Equatable, Sendable {
    public let bootstrapState: DownloadControllerBootstrapState
    public let packageRows: [DownloadPackagePresentationRow]
    public let installedPackageIDs: [PackageID]
    public let pendingPaidPackageIDs: [PackageID]
    public let outdatedPackages: [OutdatedPackageVersion]
    public let protectedNewerPackages: [ProtectedNewerPackageVersion]
    /// Conservative sum of the pending packages' installed-size ceilings. It
    /// is neither observed free-space use nor a promised transfer byte count.
    public let remainingMaximumInstalledBytes: Int64
    public let applicationQueueState: PackageBatchInstallationState
    public let appleSystemTransferState: PackageSystemTransferState
    public let refreshFailure: PackageBatchFailure?
    public let allowedCommands: [DownloadPresentationCommand]

    public init(snapshot: DownloadControllerSnapshot) throws {
        let contract = try Self.canonicalContract()

        if snapshot.bootstrapState == .awaitingBootstrap {
            guard snapshot == .awaitingBootstrap else {
                throw DownloadPresentationProjectionError.invalidAwaitingBootstrapSnapshot
            }
            bootstrapState = .awaitingBootstrap
            packageRows = contract.rows.map {
                Self.row(from: $0, state: $0.id == LaunchContent.essentialPackageID
                    ? .includedInApp
                    : .awaitingBootstrap)
            }
            installedPackageIDs = []
            pendingPaidPackageIDs = []
            outdatedPackages = []
            protectedNewerPackages = []
            remainingMaximumInstalledBytes = 0
            applicationQueueState = .idle
            appleSystemTransferState = .idle
            refreshFailure = nil
            allowedCommands = []
            return
        }

        let installedIDs = snapshot.currentInstalledPackageIDs
        guard Self.isCanonicalSubsequence(installedIDs, of: contract.allPackageIDs),
              Set(installedIDs).count == installedIDs.count else {
            throw DownloadPresentationProjectionError
                .nonCanonicalInstalledPackageIDs(installedIDs)
        }

        let pendingIDs = snapshot.pendingPaidPackageIDs
        guard Self.isCanonicalSubsequence(pendingIDs, of: contract.paidPackageIDs),
              Set(pendingIDs).count == pendingIDs.count else {
            throw DownloadPresentationProjectionError.nonCanonicalPendingPackageIDs(pendingIDs)
        }

        let outdatedPackages = snapshot.outdatedPackages
        let outdatedIDs = outdatedPackages.map(\.packageID)
        guard Self.isCanonicalSubsequence(outdatedIDs, of: contract.paidPackageIDs),
              Set(outdatedIDs).count == outdatedIDs.count else {
            throw DownloadPresentationProjectionError
                .nonCanonicalOutdatedPackageIDs(outdatedIDs)
        }
        for outdatedPackage in outdatedPackages {
            guard let expectedVersion = contract.versionByID[outdatedPackage.packageID],
                  outdatedPackage.expectedVersion == expectedVersion,
                  outdatedPackage.installedVersion < expectedVersion else {
                throw DownloadPresentationProjectionError
                    .invalidOutdatedPackageVersion(outdatedPackage)
            }
        }
        guard Set(outdatedIDs).isSubset(of: Set(pendingIDs)) else {
            throw DownloadPresentationProjectionError.outdatedPackagesAreNotPending
        }

        let protectedPackages = snapshot.protectedNewerPackages
        let protectedIDs = protectedPackages.map(\.packageID)
        guard Self.isCanonicalSubsequence(protectedIDs, of: contract.paidPackageIDs),
              Set(protectedIDs).count == protectedIDs.count else {
            throw DownloadPresentationProjectionError
                .nonCanonicalProtectedNewerPackageIDs(protectedIDs)
        }
        for protectedPackage in protectedPackages {
            guard let expectedVersion = contract.versionByID[protectedPackage.packageID],
                  protectedPackage.expectedVersion == expectedVersion,
                  protectedPackage.installedVersion > expectedVersion else {
                throw DownloadPresentationProjectionError
                    .invalidProtectedNewerPackageVersion(protectedPackage)
            }
        }

        let installedPaidIDs = installedIDs.filter { $0 != LaunchContent.essentialPackageID }
        let installedPaidSet = Set(installedPaidIDs)
        let pendingSet = Set(pendingIDs)
        let protectedSet = Set(protectedIDs)
        guard installedPaidSet.isDisjoint(with: pendingSet),
              installedPaidSet.isDisjoint(with: protectedSet),
              pendingSet.isDisjoint(with: protectedSet),
              installedPaidSet.union(pendingSet).union(protectedSet)
                == Set(contract.paidPackageIDs) else {
            throw DownloadPresentationProjectionError
                .installedPendingAndProtectedPackagesDoNotPartitionPaidLaunchPackages
        }

        var expectedRemainingBytes: Int64 = 0
        for packageID in pendingIDs {
            guard let maximumBytes = contract.maximumInstalledBytesByID[packageID] else {
                throw DownloadPresentationProjectionError.invalidLaunchContract
            }
            let sum = expectedRemainingBytes.addingReportingOverflow(maximumBytes)
            guard !sum.overflow else {
                throw DownloadPresentationProjectionError.invalidLaunchContract
            }
            expectedRemainingBytes = sum.partialValue
        }
        guard snapshot.remainingMaximumInstalledBytes == expectedRemainingBytes else {
            throw DownloadPresentationProjectionError.remainingMaximumInstalledBytesMismatch(
                expected: expectedRemainingBytes,
                actual: snapshot.remainingMaximumInstalledBytes
            )
        }

        try Self.validate(
            installationState: snapshot.installationState,
            paidPackageIDs: contract.paidPackageIDs,
            protectedNewerPackageIDs: protectedSet
        )
        try Self.validate(
            systemTransferState: snapshot.systemTransferState,
            installationState: snapshot.installationState
        )

        let protectedByID = Dictionary(
            uniqueKeysWithValues: protectedPackages.map { ($0.packageID, $0) }
        )
        let outdatedByID = Dictionary(
            uniqueKeysWithValues: outdatedPackages.map { ($0.packageID, $0) }
        )
        bootstrapState = .ready
        packageRows = contract.rows.map { package in
            let state: DownloadPackagePresentationState
            if package.id == LaunchContent.essentialPackageID {
                state = .includedInApp
            } else if installedPaidSet.contains(package.id) {
                state = .installedCurrent
            } else if let outdatedPackage = outdatedByID[package.id] {
                state = .updatePending(
                    installedVersion: outdatedPackage.installedVersion,
                    expectedVersion: outdatedPackage.expectedVersion
                )
            } else if let protectedPackage = protectedByID[package.id] {
                state = .requiresNewerApp(
                    installedVersion: protectedPackage.installedVersion,
                    expectedVersion: protectedPackage.expectedVersion
                )
            } else {
                state = .pending
            }
            return Self.row(from: package, state: state)
        }
        installedPackageIDs = installedIDs
        pendingPaidPackageIDs = pendingIDs
        self.outdatedPackages = outdatedPackages
        protectedNewerPackages = protectedPackages
        remainingMaximumInstalledBytes = expectedRemainingBytes
        applicationQueueState = snapshot.installationState
        appleSystemTransferState = snapshot.systemTransferState
        refreshFailure = snapshot.refreshFailure
        allowedCommands = Self.allowedCommands(
            installationState: snapshot.installationState,
            pendingPackageIDs: pendingIDs,
            hasRefreshFailure: snapshot.refreshFailure != nil
        )
    }
}

private extension DownloadPresentationProjection {
    struct CanonicalPackage: Sendable {
        let id: PackageID
        let canonicalOrder: Int
        let maximumInstalledBytes: Int64
        let chapters: [DownloadPackageChapterPresentation]
        let version: SchemaVersion
    }

    struct CanonicalContract: Sendable {
        let rows: [CanonicalPackage]
        let allPackageIDs: [PackageID]
        let paidPackageIDs: [PackageID]
        let maximumInstalledBytesByID: [PackageID: Int64]
        let versionByID: [PackageID: SchemaVersion]
    }

    static func canonicalContract() throws -> CanonicalContract {
        let manifest = LaunchContent.collectionManifest
        do {
            try manifest.validateLaunch()
        } catch {
            throw DownloadPresentationProjectionError.invalidLaunchContract
        }
        let allPackageIDs = LaunchContent.packageIDsInDeliveryOrder
        guard !allPackageIDs.isEmpty,
              allPackageIDs.first == LaunchContent.essentialPackageID,
              Set(allPackageIDs).count == allPackageIDs.count,
              Set(manifest.packages.map(\.id)) == Set(allPackageIDs),
              Set(manifest.chapters.map(\.id)) == Set(LaunchContent.chapterOrder) else {
            throw DownloadPresentationProjectionError.invalidLaunchContract
        }

        let packageByID = Dictionary(uniqueKeysWithValues: manifest.packages.map { ($0.id, $0) })
        let chapterByID = Dictionary(uniqueKeysWithValues: manifest.chapters.map { ($0.id, $0) })
        var rows: [CanonicalPackage] = []
        for (offset, packageID) in allPackageIDs.enumerated() {
            guard let package = packageByID[packageID],
                  package.maximumInstalledBytes >= 0,
                  package.isEssentialInstall == (packageID == LaunchContent.essentialPackageID),
                  Set(package.chapterIDs).count == package.chapterIDs.count else {
                throw DownloadPresentationProjectionError.invalidLaunchContract
            }
            let chapterIDs = LaunchContent.chapterOrder.filter { package.chapterIDs.contains($0) }
            guard Set(chapterIDs) == Set(package.chapterIDs) else {
                throw DownloadPresentationProjectionError.invalidLaunchContract
            }
            let chapters = try chapterIDs.map { chapterID in
                guard let chapter = chapterByID[chapterID], chapter.packageID == packageID else {
                    throw DownloadPresentationProjectionError.invalidLaunchContract
                }
                return DownloadPackageChapterPresentation(
                    id: chapter.id,
                    sequence: chapter.sequence,
                    title: chapter.title,
                    period: chapter.period
                )
            }
            rows.append(CanonicalPackage(
                id: packageID,
                canonicalOrder: offset,
                maximumInstalledBytes: package.maximumInstalledBytes,
                chapters: chapters,
                version: package.version
            ))
        }

        let paidPackageIDs = allPackageIDs.filter { $0 != LaunchContent.essentialPackageID }
        return CanonicalContract(
            rows: rows,
            allPackageIDs: allPackageIDs,
            paidPackageIDs: paidPackageIDs,
            maximumInstalledBytesByID: Dictionary(
                uniqueKeysWithValues: rows.map { ($0.id, $0.maximumInstalledBytes) }
            ),
            versionByID: Dictionary(
                uniqueKeysWithValues: rows.map { ($0.id, $0.version) }
            )
        )
    }

    static func row(
        from package: CanonicalPackage,
        state: DownloadPackagePresentationState
    ) -> DownloadPackagePresentationRow {
        DownloadPackagePresentationRow(
            id: package.id,
            canonicalOrder: package.canonicalOrder,
            maximumInstalledBytes: package.maximumInstalledBytes,
            chapters: package.chapters,
            state: state
        )
    }

    static func isCanonicalSubsequence(_ ids: [PackageID], of canonical: [PackageID]) -> Bool {
        let positionByID = Dictionary(
            uniqueKeysWithValues: canonical.enumerated().map { ($0.element, $0.offset) }
        )
        let positions = ids.compactMap { positionByID[$0] }
        guard positions.count == ids.count else { return false }
        return zip(positions, positions.dropFirst()).allSatisfy(<)
    }

    static func validate(
        installationState: PackageBatchInstallationState,
        paidPackageIDs: [PackageID],
        protectedNewerPackageIDs: Set<PackageID>
    ) throws {
        func validateQueuePrefix(
            completed: [PackageID],
            activeOrNext: PackageID?,
            total: Int?
        ) throws {
            let represented = completed + [activeOrNext].compactMap { $0 }
            guard Set(represented).count == represented.count,
                  isCanonicalSubsequence(represented, of: paidPackageIDs),
                  represented.allSatisfy({ !protectedNewerPackageIDs.contains($0) }) else {
                throw DownloadPresentationProjectionError.invalidInstallationState
            }
            if let total {
                guard total > 0,
                      total <= paidPackageIDs.count,
                      represented.count <= total else {
                    throw DownloadPresentationProjectionError.invalidInstallationState
                }
                if activeOrNext == nil, completed.count != total {
                    throw DownloadPresentationProjectionError.invalidInstallationState
                }
                if activeOrNext != nil, completed.count >= total {
                    throw DownloadPresentationProjectionError.invalidInstallationState
                }
            }
        }

        switch installationState {
        case .idle:
            return

        case let .starting(packageID, completed, total),
             let .installing(packageID, completed, total),
             let .pausingAfterCurrent(packageID, completed, total):
            try validateQueuePrefix(
                completed: completed,
                activeOrNext: packageID,
                total: total
            )

        case let .paused(nextPackageID, completed, total):
            // PackageBatchInstaller only publishes `.paused` while a next
            // package exists. A nil ID would invent a queue state it cannot
            // restore or resume.
            guard let nextPackageID else {
                throw DownloadPresentationProjectionError.invalidInstallationState
            }
            try validateQueuePrefix(
                completed: completed,
                activeOrNext: nextPackageID,
                total: total
            )

        case let .awaitingExplicitRestore(nextPackageID, completed, total):
            try validateQueuePrefix(
                completed: completed,
                activeOrNext: nextPackageID,
                total: total
            )

        case let .staleJournal(reason):
            switch reason {
            case .corruptJournal:
                // The journal store has already proved that neither durable
                // slot can be decoded and authenticated. There are no package
                // identifiers to validate until the preserved queue is
                // explicitly retired.
                break
            case let .unknownOrRemovedPackageIDs(ids):
                guard !ids.isEmpty,
                      ids.allSatisfy({ !paidPackageIDs.contains($0) }) else {
                    throw DownloadPresentationProjectionError.invalidInstallationState
                }
            case let .nonCanonicalPackageOrder(ids):
                guard !ids.isEmpty,
                      ids.allSatisfy(paidPackageIDs.contains),
                      !isCanonicalSubsequence(ids, of: paidPackageIDs) else {
                    throw DownloadPresentationProjectionError.invalidInstallationState
                }
            case let .protectedNewerPackageVersions(ids):
                guard !ids.isEmpty,
                      Set(ids).count == ids.count,
                      isCanonicalSubsequence(ids, of: paidPackageIDs),
                      Set(ids).isSubset(of: protectedNewerPackageIDs) else {
                    throw DownloadPresentationProjectionError.invalidInstallationState
                }
            case let .requiresNewerApp(formatVersion):
                guard formatVersion > PackageBatchQueueJournal.currentFormatVersion else {
                    throw DownloadPresentationProjectionError.invalidInstallationState
                }
            }

        case let .completed(installedPackageIDs):
            guard Set(installedPackageIDs).count == installedPackageIDs.count,
                  isCanonicalSubsequence(installedPackageIDs, of: paidPackageIDs),
                  installedPackageIDs.allSatisfy({
                      !protectedNewerPackageIDs.contains($0)
                  }) else {
                throw DownloadPresentationProjectionError.invalidInstallationState
            }

        case let .failed(packageID, completed, _):
            try validateQueuePrefix(
                completed: completed,
                activeOrNext: packageID,
                total: nil
            )
        }
    }

    static func validate(
        systemTransferState: PackageSystemTransferState,
        installationState: PackageBatchInstallationState
    ) throws {
        let activePackageID: PackageID?
        switch installationState {
        case let .installing(packageID, _, _),
             let .pausingAfterCurrent(packageID, _, _):
            activePackageID = packageID
        case .idle, .starting, .paused, .awaitingExplicitRestore,
             .staleJournal, .completed, .failed:
            activePackageID = nil
        }

        switch systemTransferState {
        case .idle:
            return
        case let .began(packageID, _),
             let .paused(packageID),
             let .finished(packageID),
             let .failed(packageID, _):
            guard packageID == activePackageID else {
                throw DownloadPresentationProjectionError.inconsistentSystemTransferState
            }
        case let .downloading(packageID, _, _):
            // Counts remain opaque Apple telemetry. In particular, this layer
            // does not reinterpret them as byte-exact transfer control.
            guard packageID == activePackageID else {
                throw DownloadPresentationProjectionError.inconsistentSystemTransferState
            }
        }
    }

    static func allowedCommands(
        installationState: PackageBatchInstallationState,
        pendingPackageIDs: [PackageID],
        hasRefreshFailure: Bool
    ) -> [DownloadPresentationCommand] {
        switch installationState {
        case .idle, .completed:
            // A refresh failure means the package plan is deliberately kept as
            // the last verified snapshot. Do not offer a new request from it;
            // the controller may be refreshed and projected again first.
            if hasRefreshFailure { return [.refreshInstalledChapters] }
            guard !pendingPackageIDs.isEmpty else { return [] }
            return pendingPackageIDs.map(DownloadPresentationCommand.requestSinglePackage)
                + [.requestDownloadAll]

        case .starting:
            return []

        case let .staleJournal(reason):
            if case .protectedNewerPackageVersions = reason {
                return []
            }
            if case .requiresNewerApp = reason {
                return []
            }
            return [.discardStaleQueue]

        case .installing:
            return [.requestQueuePauseAfterCurrentPackage]

        case .pausingAfterCurrent, .paused, .awaitingExplicitRestore:
            return [.resumeApplicationQueue]

        case .failed:
            return [.retryFailedPackage, .removeFailedPackage]
        }
    }
}
