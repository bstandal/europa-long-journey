import ContentDelivery
import ContentKit
import ExperiencePreferences
import Foundation
import JourneyContent

enum JourneyDownloadCommandOutcome: Equatable, Sendable {
    case request(DownloadControllerRequestResult)
    case performed
}

struct JourneyDownloadClient: Sendable {
    let bootstrap: @Sendable () async throws -> DownloadControllerSnapshot
    let snapshot: @Sendable () async -> DownloadControllerSnapshot
    let snapshotUpdates: @Sendable () async -> AsyncStream<DownloadControllerSnapshot>
    let execute: @Sendable (DownloadPresentationCommand) async throws
        -> JourneyDownloadCommandOutcome

    static func live(
        controller: DownloadController,
        beforeBootstrap: @escaping @Sendable () async -> Void = {}
    ) -> JourneyDownloadClient {
        JourneyDownloadClient(
            bootstrap: {
                await beforeBootstrap()
                return try await controller.bootstrap()
            },
            snapshot: { await controller.snapshot() },
            snapshotUpdates: { await controller.snapshotUpdates() },
            execute: { command in
                switch command {
                case let .requestSinglePackage(packageID):
                    return .request(try await controller.requestSinglePackage(packageID))
                case .requestDownloadAll:
                    return .request(try await controller.requestDownloadAll())
                case .requestQueuePauseAfterCurrentPackage:
                    try await controller.requestPauseAfterCurrentPackage()
                case .resumeApplicationQueue:
                    try await controller.resumeQueue()
                case .retryFailedPackage:
                    try await controller.retryFailedPackage()
                case .removeFailedPackage:
                    try await controller.removeFailedPackage()
                case .refreshInstalledChapters:
                    try await controller.refresh()
                case .discardStaleQueue:
                    try await controller.discardStaleQueue()
                }
                return .performed
            }
        )
    }
}

struct JourneyContentClient: Sendable {
    let initialSnapshot: VerifiedJourneyContentSnapshot
    let snapshot: @Sendable () async -> VerifiedJourneyContentSnapshot
    let snapshotUpdates: @Sendable () async
        -> AsyncStream<VerifiedJourneyContentSnapshot>
    let reportAssetFailure: @Sendable (
        PackageID,
        PackageAssetFailureAuthority
    ) async -> AssetFailureReportOutcome
    let revertSaveMigrationAuthorityChange: @Sendable (
        PackageID,
        InstalledPackageGeneration,
        InstalledPackageGeneration?
    ) async throws -> VerifiedJourneyContentSnapshot?

    static func live(
        authority: VerifiedJourneyRepositoryAuthority
    ) -> JourneyContentClient {
        JourneyContentClient(
            initialSnapshot: authority.initialSnapshot,
            snapshot: { await authority.snapshot() },
            snapshotUpdates: { await authority.snapshotUpdates() },
            reportAssetFailure: { packageID, expectedAuthority in
                await authority.reportAssetFailure(
                    packageID: packageID,
                    expectedAuthority: expectedAuthority
                )
            },
            revertSaveMigrationAuthorityChange: {
                packageID,
                current,
                previous in
                try await authority.revertSaveMigrationAuthorityChange(
                    packageID: packageID,
                    expectedCurrent: current,
                    expectedPrevious: previous
                )
            }
        )
    }
}

struct JourneyDownloadCompositionResult: Sendable {
    let downloadClient: JourneyDownloadClient
    let contentClient: JourneyContentClient
}

enum JourneyDownloadComposition {
    static let trustResourceName = "launch-package-trust"
    static let essentialPackageResourceDirectory =
        "JourneyContent/essential-free-v1"

    static func makeIfConfigured(
        applicationSupportURL: URL,
        preferencesStore: ExperiencePreferencesStore,
        bundle: Bundle = .main
    ) throws -> JourneyDownloadCompositionResult? {
        guard let trustURL = bundle.url(
            forResource: trustResourceName,
            withExtension: "json"
        ) else {
            return nil
        }
        let trust = try LaunchPackageTrustConfiguration(
            data: Data(contentsOf: trustURL)
        )
        guard let essentialManifestURL = bundle.url(
            forResource: "package-manifest",
            withExtension: "json",
            subdirectory: essentialPackageResourceDirectory
        ) else {
            throw BundledEssentialContentLoaderError.resourceMissing(
                name: "package-manifest",
                extension: "json",
                subdirectory: essentialPackageResourceDirectory
            )
        }
        let essentialPackageRoot = essentialManifestURL.deletingLastPathComponent()
        let contentAssembler = VerifiedContentRepositoryAssembler()
        let verifiedEssentialPackage = try contentAssembler
            .verifyBundledEssentialPackage(
                at: essentialPackageRoot,
                trustedPublicKeys: trust.trustedPublicKeys
            )
        let deliveryRoot = applicationSupportURL.appending(
            path: "content-delivery-v1",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: deliveryRoot,
            withIntermediateDirectories: true
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDeliveryRoot = deliveryRoot
        try mutableDeliveryRoot.setResourceValues(resourceValues)

        let activator = try PackageActivator(
            rootURL: deliveryRoot.appending(
                path: "installed",
                directoryHint: .isDirectory
            )
        )
        let contentAuthority = try VerifiedJourneyRepositoryAuthority(
            bundledEssentialPackage: verifiedEssentialPackage,
            bundledEssentialRootURL: essentialPackageRoot,
            trustedPublicKeys: trust.trustedPublicKeys,
            authorityProvider: {
                try await activator.retainedPackageAuthority()
            },
            exactRollback: { packageID, current, previous in
                try await activator.rollback(
                    packageID: packageID,
                    expectedActiveGeneration: current,
                    expectedPreviousGeneration: previous
                )
            },
            deactivate: { packageID, current in
                try await activator.deactivate(
                    packageID: packageID,
                    expectedActiveGeneration: current
                )
            }
        )
        let materializer = ManagedPackageMaterializer(
            provider: AppleHostedAssetPackProvider(),
            activator: activator
        )
        let journalStore = try PackageBatchQueueJournalStore(
            directoryURL: deliveryRoot.appending(
                path: "queue",
                directoryHint: .isDirectory
            )
        )
        let installer = PackageBatchInstaller(
            materializer: materializer,
            context: trust.installationContext(),
            journalStore: journalStore
        )
        let networkProvider = NWPathDownloadNetworkBasisProvider()
        let controller = DownloadController(
            installer: installer,
            networkBasisProvider: networkProvider,
            installedIndexProvider: {
                try await contentAuthority.reconciledInstalledIndex()
            },
            preferencesProvider: {
                try await preferencesStore.load().preferences
            }
        )
        return JourneyDownloadCompositionResult(
            downloadClient: .live(
                controller: controller,
                beforeBootstrap: {
                    // Apple-managed packs are only a transport cache. A
                    // failed cleanup cannot block the private, verified copy
                    // or chapter restoration, so bootstrap maintenance is
                    // deliberately best-effort.
                    try? await materializer.retryPendingCleanup()
                }
            ),
            contentClient: .live(authority: contentAuthority)
        )
    }
}

#if DEBUG
extension JourneyDownloadClient {
    static func developmentFixture(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> JourneyDownloadClient {
        let fixture = DevelopmentJourneyDownloadFixture(arguments: arguments)
        return JourneyDownloadClient(
            bootstrap: { try await fixture.bootstrap() },
            snapshot: { await fixture.snapshot() },
            snapshotUpdates: { await fixture.snapshotUpdates() },
            execute: { try await fixture.execute($0) }
        )
    }
}

private enum DevelopmentJourneyDownloadFixtureError: Error {
    case bootstrapFailed
}

private actor DevelopmentJourneyDownloadFixture {
    private static let paidPackageIDs = Array(LaunchContent.packageIDsInDeliveryOrder.dropFirst())
    private static let packageByID = Dictionary(
        uniqueKeysWithValues: LaunchContent.collectionManifest.packages.map {
            ($0.id, $0)
        }
    )
    private static let maximumBytesByPackageID = Dictionary(
        uniqueKeysWithValues: packageByID.values.map {
            ($0.id, $0.maximumInstalledBytes)
        }
    )

    private var current: DownloadControllerSnapshot
    private let readyAfterBootstrap: DownloadControllerSnapshot?
    private let requiresNewerAppAtBootstrap: Bool
    private var bootstrapFailuresRemaining: Int
    private var observers: [UUID: AsyncStream<DownloadControllerSnapshot>.Continuation] = [:]

    init(arguments: [String]) {
        let paid = Self.paidPackageIDs
        let maximum = Self.maximumBytes(for: paid)
        let ready: DownloadControllerSnapshot
        if arguments.contains("--ui-testing-download-active") {
            ready = DownloadControllerSnapshot(
                bootstrapState: .ready,
                currentInstalledPackageIDs: [],
                pendingPaidPackageIDs: paid,
                outdatedPackages: [],
                protectedNewerPackages: [],
                remainingMaximumInstalledBytes: maximum,
                installationState: .installing(
                    packageID: paid[0],
                    completedPackageIDs: [],
                    totalPackageCount: paid.count
                ),
                systemTransferState: .downloading(
                    packageID: paid[0],
                    completedUnitCount: 43,
                    totalUnitCount: 100
                )
            )
        } else if arguments.contains("--ui-testing-download-insufficient-storage") {
            ready = DownloadControllerSnapshot(
                bootstrapState: .ready,
                currentInstalledPackageIDs: [],
                pendingPaidPackageIDs: paid,
                outdatedPackages: [],
                protectedNewerPackages: [],
                remainingMaximumInstalledBytes: maximum,
                installationState: .failed(
                    packageID: paid[0],
                    completedPackageIDs: [],
                    failure: PackageBatchFailure(
                        domain: ManagedPackageMaterializationError.errorDomain,
                        code: ManagedPackageMaterializationError
                            .insufficientStorageErrorCode
                    )
                ),
                systemTransferState: .idle
            )
        } else if arguments.contains("--ui-testing-download-stale") {
            ready = DownloadControllerSnapshot(
                bootstrapState: .ready,
                currentInstalledPackageIDs: [],
                pendingPaidPackageIDs: paid,
                outdatedPackages: [],
                protectedNewerPackages: [],
                remainingMaximumInstalledBytes: maximum,
                installationState: .staleJournal(
                    reason: .unknownOrRemovedPackageIDs(["retired-paid-pack"])
                ),
                systemTransferState: .idle
            )
        } else if arguments.contains("--ui-testing-download-outdated-content") {
            let outdatedID = paid[0]
            let expectedVersion = Self.packageByID[outdatedID]?.version
                ?? SchemaVersion(major: 1)
            ready = DownloadControllerSnapshot(
                bootstrapState: .ready,
                currentInstalledPackageIDs: [],
                pendingPaidPackageIDs: paid,
                outdatedPackages: [
                    OutdatedPackageVersion(
                        packageID: outdatedID,
                        installedVersion: SchemaVersion(major: 0),
                        expectedVersion: expectedVersion
                    ),
                ],
                protectedNewerPackages: [],
                remainingMaximumInstalledBytes: maximum,
                installationState: .idle,
                systemTransferState: .idle
            )
        } else if arguments.contains("--ui-testing-download-newer-content") {
            let protectedID = paid[0]
            let expectedVersion = Self.packageByID[protectedID]?.version
                ?? SchemaVersion(major: 1)
            let pending = Array(paid.dropFirst())
            ready = DownloadControllerSnapshot(
                bootstrapState: .ready,
                currentInstalledPackageIDs: [],
                pendingPaidPackageIDs: pending,
                outdatedPackages: [],
                protectedNewerPackages: [
                    ProtectedNewerPackageVersion(
                        packageID: protectedID,
                        installedVersion: SchemaVersion(
                            major: expectedVersion.major + 1,
                            minor: expectedVersion.minor,
                            patch: expectedVersion.patch
                        ),
                        expectedVersion: expectedVersion
                    ),
                ],
                remainingMaximumInstalledBytes: Self.maximumBytes(for: pending),
                installationState: .idle,
                systemTransferState: .idle
            )
        } else if arguments.contains("--ui-testing-download-all-installed") {
            ready = DownloadControllerSnapshot(
                bootstrapState: .ready,
                currentInstalledPackageIDs: paid,
                pendingPaidPackageIDs: [],
                outdatedPackages: [],
                protectedNewerPackages: [],
                remainingMaximumInstalledBytes: 0,
                installationState: .idle,
                systemTransferState: .idle
            )
        } else {
            ready = DownloadControllerSnapshot(
                bootstrapState: .ready,
                currentInstalledPackageIDs: [],
                pendingPaidPackageIDs: paid,
                outdatedPackages: [],
                protectedNewerPackages: [],
                remainingMaximumInstalledBytes: maximum,
                installationState: .idle,
                systemTransferState: .idle
            )
        }
        requiresNewerAppAtBootstrap = arguments.contains(
            "--ui-testing-download-future-index"
        )
        if requiresNewerAppAtBootstrap {
            current = .awaitingBootstrap
            readyAfterBootstrap = nil
            bootstrapFailuresRemaining = 0
        } else if arguments.contains("--ui-testing-download-bootstrap-failure") {
            current = .awaitingBootstrap
            readyAfterBootstrap = ready
            bootstrapFailuresRemaining = 1
        } else {
            current = ready
            readyAfterBootstrap = nil
            bootstrapFailuresRemaining = 0
        }
    }

    func bootstrap() throws -> DownloadControllerSnapshot {
        if requiresNewerAppAtBootstrap {
            throw InstalledPackageIndexError.requiresNewerApp(
                InstalledPackageIndex.currentFormatVersion + 1
            )
        }
        if bootstrapFailuresRemaining > 0 {
            bootstrapFailuresRemaining -= 1
            throw DevelopmentJourneyDownloadFixtureError.bootstrapFailed
        }
        if current.bootstrapState == .awaitingBootstrap, let readyAfterBootstrap {
            publish(readyAfterBootstrap)
        }
        return current
    }

    func snapshot() -> DownloadControllerSnapshot { current }

    func snapshotUpdates() -> AsyncStream<DownloadControllerSnapshot> {
        let observerID = UUID()
        let pair = AsyncStream<DownloadControllerSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        observers[observerID] = pair.continuation
        pair.continuation.yield(current)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(observerID) }
        }
        return pair.stream
    }

    private func removeObserver(_ observerID: UUID) {
        observers.removeValue(forKey: observerID)
    }

    func execute(
        _ command: DownloadPresentationCommand
    ) throws -> JourneyDownloadCommandOutcome {
        switch command {
        case let .requestSinglePackage(packageID):
            publish(activeSnapshot(packageID: packageID, totalPackageCount: 1))
            return .request(.started(packageIDs: [packageID]))
        case .requestDownloadAll:
            let pending = current.pendingPaidPackageIDs
            guard let first = pending.first else {
                return .request(.noOperation(reason: .nothingPending))
            }
            publish(activeSnapshot(packageID: first, totalPackageCount: pending.count))
            return .request(.started(packageIDs: pending))
        case .requestQueuePauseAfterCurrentPackage:
            guard case let .installing(packageID, completed, total) = current.installationState else {
                return .performed
            }
            publish(replacingState(
                .pausingAfterCurrent(
                    packageID: packageID,
                    completedPackageIDs: completed,
                    totalPackageCount: total
                ),
                transfer: current.systemTransferState
            ))
        case .resumeApplicationQueue:
            let active: PackageID
            let completed: [PackageID]
            let total: Int
            switch current.installationState {
            case let .pausingAfterCurrent(packageID, ids, count):
                (active, completed, total) = (packageID, ids, count)
            case let .paused(nextPackageID, ids, count):
                guard let nextPackageID else { return .performed }
                (active, completed, total) = (nextPackageID, ids, count)
            case let .awaitingExplicitRestore(nextPackageID, ids, count):
                (active, completed, total) = (nextPackageID, ids, count)
            default:
                return .performed
            }
            publish(activeSnapshot(
                packageID: active,
                completedPackageIDs: completed,
                totalPackageCount: total
            ))
        case .retryFailedPackage:
            guard case let .failed(packageID, completed, _) = current.installationState else {
                return .performed
            }
            publish(activeSnapshot(
                packageID: packageID,
                completedPackageIDs: completed,
                totalPackageCount: max(completed.count + 1, 1)
            ))
        case .removeFailedPackage:
            publish(replacingState(.completed(installedPackageIDs: [])))
        case .refreshInstalledChapters:
            publish(DownloadControllerSnapshot(
                bootstrapState: .ready,
                currentInstalledPackageIDs: current.currentInstalledPackageIDs,
                pendingPaidPackageIDs: current.pendingPaidPackageIDs,
                outdatedPackages: current.outdatedPackages,
                protectedNewerPackages: current.protectedNewerPackages,
                remainingMaximumInstalledBytes: current.remainingMaximumInstalledBytes,
                installationState: current.installationState,
                systemTransferState: current.systemTransferState
            ))
        case .discardStaleQueue:
            publish(replacingState(.idle))
        }
        return .performed
    }

    private func activeSnapshot(
        packageID: PackageID,
        completedPackageIDs: [PackageID] = [],
        totalPackageCount: Int
    ) -> DownloadControllerSnapshot {
        replacingState(
            .installing(
                packageID: packageID,
                completedPackageIDs: completedPackageIDs,
                totalPackageCount: totalPackageCount
            ),
            transfer: .downloading(
                packageID: packageID,
                completedUnitCount: 43,
                totalUnitCount: 100
            )
        )
    }

    private func replacingState(
        _ state: PackageBatchInstallationState,
        transfer: PackageSystemTransferState = .idle
    ) -> DownloadControllerSnapshot {
        DownloadControllerSnapshot(
            bootstrapState: .ready,
            currentInstalledPackageIDs: current.currentInstalledPackageIDs,
            pendingPaidPackageIDs: current.pendingPaidPackageIDs,
            outdatedPackages: current.outdatedPackages,
            protectedNewerPackages: current.protectedNewerPackages,
            remainingMaximumInstalledBytes: current.remainingMaximumInstalledBytes,
            installationState: state,
            systemTransferState: transfer,
            refreshFailure: current.refreshFailure
        )
    }

    private func publish(_ snapshot: DownloadControllerSnapshot) {
        current = snapshot
        for observer in observers.values {
            observer.yield(snapshot)
        }
    }

    private static func maximumBytes(for packageIDs: [PackageID]) -> Int64 {
        packageIDs.reduce(into: 0) { total, packageID in
            total += maximumBytesByPackageID[packageID] ?? 0
        }
    }
}
#endif
