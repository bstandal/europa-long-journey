import ContentDelivery
import ContentKit
import Foundation
import JourneyContent
import ReleaseDiscovery

struct JourneyFutureReleaseBootstrapSnapshot: Sendable {
    let download: FutureReleaseDownloadSnapshot
    let content: VerifiedFutureReleaseContentSnapshot
    let retainedCatalogEntries: [ReleaseCatalogEntry]

    init(
        download: FutureReleaseDownloadSnapshot,
        content: VerifiedFutureReleaseContentSnapshot
    ) {
        self.download = download
        self.content = content
        retainedCatalogEntries = download.retainedCatalogEntries
    }
}

/// App-facing composition over dynamic delivery and independently verified
/// offline chapter authority. Discovery never supplies playable content
/// directly: a Release must first be retained, installed and re-admitted.
struct JourneyFutureReleaseClient: Sendable {
    let bootstrap: @Sendable () async throws
        -> JourneyFutureReleaseBootstrapSnapshot
    let request: @Sendable (
        ReleaseID,
        FutureReleaseDownloadIntent
    ) async throws -> FutureReleaseDownloadRequestResult
    let downloadSnapshot: @Sendable () async throws
        -> FutureReleaseDownloadSnapshot
    let contentSnapshot: @Sendable () async
        -> VerifiedFutureReleaseContentSnapshot
    let refreshContent: @Sendable () async throws
        -> VerifiedFutureReleaseContentSnapshot
    let resumeQueue: @Sendable () async throws -> Void
    let retryFailedPackage: @Sendable () async throws -> Void
    let reportAssetFailure: @Sendable (
        ReleaseID,
        PackageAssetFailureAuthority
    ) async -> AssetFailureReportOutcome
    let revertSaveMigrationAuthorityChange: @Sendable (
        PackageID,
        InstalledPackageGeneration,
        InstalledPackageGeneration?
    ) async throws -> VerifiedFutureReleaseContentSnapshot?
    let installationStateUpdates: @Sendable () async
        -> AsyncStream<PackageBatchInstallationState>
    let systemTransferStateUpdates: @Sendable () async
        -> AsyncStream<PackageSystemTransferState>

    static func live(
        downloadController: FutureReleaseDownloadController,
        contentAuthority: VerifiedFutureReleaseRepositoryAuthority,
        beforeBootstrap: @escaping @Sendable () async -> Void = {}
    ) -> JourneyFutureReleaseClient {
        JourneyFutureReleaseClient(
            bootstrap: {
                await beforeBootstrap()
                let download = try await downloadController.bootstrap()
                let content = try await contentAuthority.bootstrap()
                return JourneyFutureReleaseBootstrapSnapshot(
                    download: download,
                    content: content
                )
            },
            request: { releaseID, intent in
                try await downloadController.request(releaseID, intent: intent)
            },
            downloadSnapshot: {
                try await downloadController.snapshot()
            },
            contentSnapshot: {
                await contentAuthority.snapshot()
            },
            refreshContent: {
                try await contentAuthority.refresh()
            },
            resumeQueue: {
                try await downloadController.resumeQueue()
            },
            retryFailedPackage: {
                try await downloadController.retryFailedPackage()
            },
            reportAssetFailure: { releaseID, authority in
                await contentAuthority.reportAssetFailure(
                    releaseID: releaseID,
                    expectedAuthority: authority
                )
            },
            revertSaveMigrationAuthorityChange: {
                packageID,
                current,
                previous in
                try await contentAuthority.revertSaveMigrationAuthorityChange(
                    packageID: packageID,
                    expectedCurrent: current,
                    expectedPrevious: previous
                )
            },
            installationStateUpdates: {
                await downloadController.installationStateUpdates()
            },
            systemTransferStateUpdates: {
                await downloadController.systemTransferStateUpdates()
            }
        )
    }
}

#if DEBUG
private enum DevelopmentFutureReleaseFixtureError: Error {
    case bootstrapUnavailable
}

private enum DevelopmentFutureReleaseContract {
    static let releaseID = ReleaseID("release-local-fixture-v1")
    static let packageID = PackageID("local-frontier-package-v1")
    static let entry = ReleaseCatalogEntry(
        release: Release(
            id: releaseID,
            contentID: "local-frontier-route",
            packageID: packageID,
            version: SchemaVersion(major: 1),
            chapterIDs: ["local-frontier-route"],
            maximumInstalledBytes: 1_000_000,
            publishedAtUnixMillis: 1_700_000_000_000,
            minimumRuntime: SchemaVersion(major: 1)
        ),
        placement: ReleaseWorldPlacement(
            worldNodeID: "chapter-frontiers-hold",
            historicalTime: HistoricalTimeAnchor(astronomicalYear: 1453)
        ),
        announcement: ReleaseAnnouncement(
            title: "Local release fixture",
            body: "Open the local historical route."
        )
    )
}

private actor DevelopmentFutureReleaseClientFixture {
    private let releaseID = DevelopmentFutureReleaseContract.releaseID
    private let packageID = DevelopmentFutureReleaseContract.packageID
    private let entry = DevelopmentFutureReleaseContract.entry
    private var download: FutureReleaseDownloadSnapshot
    private var bootstrapFailuresRemaining: Int
    private var isBootstrapped = false

    init(
        bootstrapFailuresRemaining: Int = 0,
        initiallyInstalled: Bool = false,
        awaitingRestore: Bool = false
    ) {
        self.bootstrapFailuresRemaining = bootstrapFailuresRemaining
        download = FutureReleaseDownloadSnapshot(
            retainedCatalogEntries: initiallyInstalled || awaitingRestore
                ? [DevelopmentFutureReleaseContract.entry] : [],
            currentInstalledPackageIDs: initiallyInstalled
                ? [DevelopmentFutureReleaseContract.packageID] : [],
            installationState: awaitingRestore
                ? .awaitingExplicitRestore(
                    nextPackageID: DevelopmentFutureReleaseContract.packageID,
                    completedPackageIDs: [],
                    totalPackageCount: 1
                ) : .idle,
            systemTransferState: .idle
        )
    }

    func bootstrap() throws -> JourneyFutureReleaseBootstrapSnapshot {
        if bootstrapFailuresRemaining > 0 {
            bootstrapFailuresRemaining -= 1
            throw DevelopmentFutureReleaseFixtureError.bootstrapUnavailable
        }
        isBootstrapped = true
        return JourneyFutureReleaseBootstrapSnapshot(
            download: download,
            content: .empty
        )
    }

    func request(
        _ requestedReleaseID: ReleaseID
    ) -> FutureReleaseDownloadRequestResult {
        guard requestedReleaseID == releaseID else {
            return .noOperation(.unknownRelease)
        }
        download = FutureReleaseDownloadSnapshot(
            retainedCatalogEntries: [entry],
            currentInstalledPackageIDs: [],
            installationState: .installing(
                packageID: packageID,
                completedPackageIDs: [],
                totalPackageCount: 1
            ),
            systemTransferState: .downloading(
                packageID: packageID,
                completedUnitCount: 240_000,
                totalUnitCount: 1_000_000
            )
        )
        return .started(releaseID: releaseID, packageID: packageID)
    }

    func snapshot() throws -> FutureReleaseDownloadSnapshot {
        guard isBootstrapped else {
            throw DevelopmentFutureReleaseFixtureError.bootstrapUnavailable
        }
        return download
    }

    func retry() {
        _ = request(releaseID)
    }

    func resume() {
        download = FutureReleaseDownloadSnapshot(
            retainedCatalogEntries: [entry],
            currentInstalledPackageIDs: [],
            installationState: .installing(
                packageID: packageID,
                completedPackageIDs: [],
                totalPackageCount: 1
            ),
            systemTransferState: .idle
        )
    }

    func installationStateUpdates()
        -> AsyncStream<PackageBatchInstallationState> {
        let state = download.installationState
        return AsyncStream { continuation in
            continuation.yield(state)
        }
    }

    func systemTransferStateUpdates()
        -> AsyncStream<PackageSystemTransferState> {
        let state = download.systemTransferState
        return AsyncStream { continuation in
            continuation.yield(state)
        }
    }
}

extension JourneyFutureReleaseClient {
    /// UI-only fixture for proving the world-node download control without
    /// requiring Apple-hosted bytes or weakening production admission.
    static func developmentPresentationFixture(
        failsFirstBootstrap: Bool = false,
        initiallyInstalled: Bool = false,
        awaitingRestore: Bool = false
    ) -> JourneyFutureReleaseClient {
        let fixture = DevelopmentFutureReleaseClientFixture(
            bootstrapFailuresRemaining: failsFirstBootstrap ? 1 : 0,
            initiallyInstalled: initiallyInstalled,
            awaitingRestore: awaitingRestore
        )
        return JourneyFutureReleaseClient(
            bootstrap: { try await fixture.bootstrap() },
            request: { releaseID, _ in await fixture.request(releaseID) },
            downloadSnapshot: { try await fixture.snapshot() },
            contentSnapshot: { .empty },
            refreshContent: { .empty },
            resumeQueue: { await fixture.resume() },
            retryFailedPackage: { await fixture.retry() },
            reportAssetFailure: { _, _ in .ignoredDurableAuthority },
            revertSaveMigrationAuthorityChange: { _, _, _ in nil },
            installationStateUpdates: {
                await fixture.installationStateUpdates()
            },
            systemTransferStateUpdates: {
                await fixture.systemTransferStateUpdates()
            }
        )
    }
}
#endif
