import ContentDelivery
import ContentKit
import ExperiencePreferences
import Foundation
import JourneyContent
import ReleaseDiscovery
import UIKit

struct JourneyReleaseDiscoveryServices {
    let applicationModel: ReleaseDiscoveryApplicationModel
    let futureReleaseClient: JourneyFutureReleaseClient?
}

@MainActor
enum JourneyReleaseDiscoveryComposition {
    static func make(
        applicationSupportURL: URL,
        bundle: Bundle = .main
    ) -> JourneyReleaseDiscoveryServices {
#if NON_SHIPPING_LIVE_TEST
        JourneyReleaseDiscoveryServices(
            applicationModel: ReleaseDiscoveryApplicationModel(),
            futureReleaseClient: nil
        )
#else
        do {
#if DEBUG
            if !ProcessInfo.processInfo.arguments.contains(
                "--release-discovery-live"
            ) {
                return try makeLocal(
                    applicationSupportURL: applicationSupportURL,
                    bundle: bundle
                )
            }
#endif
            return try makeApple(
                applicationSupportURL: applicationSupportURL,
                bundle: bundle
            )
        } catch {
            // Release discovery is additive. Failure to create its cache must
            // never block the installed Journey or its saved offline state.
            return JourneyReleaseDiscoveryServices(
                applicationModel: ReleaseDiscoveryApplicationModel(),
                futureReleaseClient: nil
            )
        }
#endif
    }

    private static func makeApple(
        applicationSupportURL: URL,
        bundle: Bundle
    ) throws -> JourneyReleaseDiscoveryServices {
        let keyProvider = KeychainReleaseIntegrityKeyProvider()
        let cache = try ReleaseCatalogCacheStore(
            directoryURL: applicationSupportURL.appendingPathComponent(
                "release-discovery-v1",
                isDirectory: true
            ),
            keyProvider: keyProvider
        )
        let installationContracts = try ReleaseInstallationContractStore(
            directoryURL: applicationSupportURL.appendingPathComponent(
                "release-install-contracts-v1",
                isDirectory: true
            ),
            keyProvider: keyProvider
        )
        return makeServices(
            remote: CloudKitReleaseCatalogProvider(),
            cache: cache,
            installationContracts: installationContracts,
            authorization: AppleReleaseNotificationAuthorizationProvider(),
            scheduler: AppleReleaseNotificationScheduler(),
            registrar: UIApplicationReleaseRemoteNotificationRegistrar(),
            applicationSupportURL: applicationSupportURL,
            bundle: bundle
        )
    }

#if DEBUG
    private static func makeLocal(
        applicationSupportURL: URL,
        bundle: Bundle
    ) throws -> JourneyReleaseDiscoveryServices {
        let keyProvider = LocalReleaseCacheKeyProvider()
        let cache = try ReleaseCatalogCacheStore(
            directoryURL: applicationSupportURL.appendingPathComponent(
                "release-discovery-local-v1",
                isDirectory: true
            ),
            keyProvider: keyProvider
        )
        let installationContracts = try ReleaseInstallationContractStore(
            directoryURL: applicationSupportURL.appendingPathComponent(
                "release-install-contracts-local-v1",
                isDirectory: true
            ),
            keyProvider: keyProvider
        )
        return makeServices(
            remote: LocalReleaseCatalogProvider(
                catalogIsWithdrawn: ProcessInfo.processInfo.arguments.contains(
                    "--ui-testing-release-catalog-withdrawn"
                )
            ),
            cache: cache,
            installationContracts: installationContracts,
            authorization: LocalReleaseNotificationAuthorizationProvider(),
            scheduler: LocalReleaseNotificationScheduler(),
            registrar: LocalReleaseRemoteNotificationRegistrar(),
            applicationSupportURL: applicationSupportURL,
            bundle: bundle
        )
    }
#endif

    private static func makeServices(
        remote: any ReleaseCatalogRemoteProviding,
        cache: ReleaseCatalogCacheStore,
        installationContracts: ReleaseInstallationContractStore,
        authorization: any ReleaseNotificationAuthorizationProviding,
        scheduler: any ReleaseNotificationScheduling,
        registrar: any ReleaseRemoteNotificationRegistering,
        applicationSupportURL: URL,
        bundle: Bundle
    ) -> JourneyReleaseDiscoveryServices {
        let discovery = ReleaseDiscoveryController(
            remote: remote,
            cacheStore: cache,
            installationContractStore: installationContracts,
            runtimeVersion: FoundationCatalog.manifest.schemaVersion
        )
        let lifecycle = ReleaseDiscoveryLifecycleController(
            discovery: discovery,
            authorization: authorization,
            scheduler: scheduler,
            registrar: registrar
        )
        let applicationModel = ReleaseDiscoveryApplicationModel(lifecycle: lifecycle)
        let futureReleaseClient = try? makeFutureReleaseClient(
            discovery: discovery,
            applicationSupportURL: applicationSupportURL,
            bundle: bundle
        )
        return JourneyReleaseDiscoveryServices(
            applicationModel: applicationModel,
            futureReleaseClient: futureReleaseClient
        )
    }

    private static func makeFutureReleaseClient(
        discovery: ReleaseDiscoveryController,
        applicationSupportURL: URL,
        bundle: Bundle
    ) throws -> JourneyFutureReleaseClient {
        guard let trustURL = bundle.url(
            forResource: JourneyDownloadComposition.trustResourceName,
            withExtension: "json"
        ), let essentialManifestURL = bundle.url(
            forResource: "package-manifest",
            withExtension: "json",
            subdirectory: JourneyDownloadComposition
                .essentialPackageResourceDirectory
        ) else {
            throw ReleaseInstallationContractStoreError.unavailable
        }
        let trust = try LaunchPackageTrustConfiguration(
            data: Data(contentsOf: trustURL)
        )
        let essentialPackageRoot = essentialManifestURL.deletingLastPathComponent()
        let essential = try VerifiedContentRepositoryAssembler()
            .verifyBundledEssentialPackage(
                at: essentialPackageRoot,
                trustedPublicKeys: trust.trustedPublicKeys
            )
        let preferencesStore = try ExperiencePreferencesStore(
            directoryURL: applicationSupportURL.appendingPathComponent(
                "experience-preferences-v1",
                isDirectory: true
            )
        )
        let deliveryRoot = applicationSupportURL.appending(
            path: "future-content-delivery-v1",
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
        let materializer = ManagedPackageMaterializer(
            provider: AppleHostedAssetPackProvider(),
            activator: activator
        )
        let installer = PackageBatchInstaller(
            materializer: materializer,
            context: trust.installationContext(),
            journalStore: try PackageBatchQueueJournalStore(
                directoryURL: deliveryRoot.appending(
                    path: "queue",
                    directoryHint: .isDirectory
                )
            )
        )
        let downloadController = FutureReleaseDownloadController(
            discovery: discovery,
            installer: installer,
            networkBasisProvider: NWPathDownloadNetworkBasisProvider(),
            installedIndexProvider: {
                try await activator.retainedPackageAuthority().index
            },
            preferencesProvider: {
                try await preferencesStore.load().preferences
            }
        )
        let contentAuthority = VerifiedFutureReleaseRepositoryAuthority(
            expectedWorldSeed: essential.payload.worldSeed,
            trustedPublicKeys: trust.trustedPublicKeys,
            supportedSchema: FoundationCatalog.manifest.schemaVersion,
            runtimeVersion: FoundationCatalog.manifest.schemaVersion,
            releaseContractProvider: {
                try await discovery.retainedInstallationContracts().map(\.release)
            },
            packageAuthorityProvider: {
                try await activator.retainedPackageAuthority()
            },
            deactivate: { packageID, generation in
                try await activator.deactivate(
                    packageID: packageID,
                    expectedActiveGeneration: generation
                )
            },
            exactRollback: { packageID, current, previous in
                try await activator.rollback(
                    packageID: packageID,
                    expectedActiveGeneration: current,
                    expectedPreviousGeneration: previous
                )
            }
        )
        return .live(
            downloadController: downloadController,
            contentAuthority: contentAuthority,
            beforeBootstrap: {
                try? await materializer.retryPendingCleanup()
            }
        )
    }
}

@MainActor
private final class UIApplicationReleaseRemoteNotificationRegistrar:
    ReleaseRemoteNotificationRegistering {
    func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

#if DEBUG
private struct LocalReleaseCacheKeyProvider: ReleaseCacheIntegrityKeyProviding {
    func loadOrCreateKey() throws -> Data {
        Data(repeating: 0x4C, count: 32)
    }
}

private actor LocalReleaseCatalogProvider: ReleaseCatalogRemoteProviding {
    private let catalogIsWithdrawn: Bool

    init(catalogIsWithdrawn: Bool = false) {
        self.catalogIsWithdrawn = catalogIsWithdrawn
    }

    func ensureReleaseSubscription() async throws {}
    func fetchAvailableReleaseRecords() async throws -> [ReleaseRemoteRecord] {
        if catalogIsWithdrawn { return [] }
        let release = Release(
            id: "release-local-fixture-v1",
            contentID: "local-frontier-route",
            packageID: "local-frontier-package-v1",
            version: SchemaVersion(major: 1),
            chapterIDs: ["local-frontier-route"],
            maximumInstalledBytes: 1_000_000,
            publishedAtUnixMillis: 1_700_000_000_000,
            minimumRuntime: SchemaVersion(major: 1)
        )
        return [
            ReleaseRemoteRecord(
                recordName: release.id.rawValue,
                releasePayload: try JSONEncoder().encode(release),
                worldNodeID: "chapter-frontiers-hold",
                historicalYear: 1453,
                chronologyOrdinal: 0,
                notificationTitle: "Local release fixture",
                notificationBody: "Open the local historical route."
            ),
        ]
    }
}

private actor LocalReleaseNotificationAuthorizationProvider:
    ReleaseNotificationAuthorizationProviding {
    private var status = ReleaseNotificationAuthorizationStatus.notDetermined

    func authorizationStatus() async -> ReleaseNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> ReleaseNotificationAuthorizationStatus {
        status = .authorized
        return status
    }
}

private actor LocalReleaseNotificationScheduler: ReleaseNotificationScheduling {
    func schedule(_ intent: ReleaseNotificationIntent) async throws {}
}

private actor LocalReleaseRemoteNotificationRegistrar:
    ReleaseRemoteNotificationRegistering {
    func registerForRemoteNotifications() async {}
}
#endif
