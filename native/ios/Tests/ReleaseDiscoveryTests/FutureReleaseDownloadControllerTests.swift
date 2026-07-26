@testable import ReleaseDiscovery
import ContentDelivery
import ContentKit
import ExperiencePreferences
import Foundation
import XCTest

final class FutureReleaseDownloadControllerTests: XCTestCase {
    func testExplicitRequestPinsExactContractBeforeStartingInstaller() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        _ = try await fixture.controller.bootstrap()

        let result = try await fixture.controller.request(
            fixture.entry.id,
            intent: .explicit
        )
        XCTAssertEqual(
            result,
            .started(
                releaseID: fixture.entry.id,
                packageID: fixture.entry.release.packageID
            )
        )
        XCTAssertEqual(
            try fixture.contractStore.entry(for: fixture.entry.id),
            fixture.entry
        )
        let snapshot = try await fixture.controller.snapshot()
        XCTAssertEqual(snapshot.retainedReleaseIDs, [fixture.entry.id])
        XCTAssertEqual(snapshot.retainedCatalogEntries, [fixture.entry])
        let installed = await fixture.recorder.waitForFirst()
        XCTAssertEqual(
            installed,
            try fixture.entry.release.packageSpecForVerification()
        )
    }

    func testAutomaticRequestUsesPreferenceAndLowDataModeGates() async throws {
        let disabled = try await Fixture.make(
            preferences: ExperiencePreferences(
                automaticDeepDiveDownloadsEnabled: false
            )
        )
        defer { disabled.remove() }
        _ = try await disabled.controller.bootstrap()
        let preferenceResult = try await disabled.controller.request(
            disabled.entry.id,
            intent: .automatic
        )
        XCTAssertEqual(
            preferenceResult,
            .blocked(.automaticDeepDiveDownloadsDisabled)
        )
        let preferenceRecorderIsEmpty = await disabled.recorder.isEmpty()
        XCTAssertTrue(preferenceRecorderIsEmpty)

        let constrained = try await Fixture.make(
            preferences: ExperiencePreferences(
                automaticDeepDiveDownloadsEnabled: true
            ),
            networkContext: DownloadNetworkContext(
                basis: .wifi,
                isConstrained: true
            )
        )
        defer { constrained.remove() }
        _ = try await constrained.controller.bootstrap()
        let lowDataResult = try await constrained.controller.request(
            constrained.entry.id,
            intent: .automatic
        )
        XCTAssertEqual(lowDataResult, .blocked(.lowDataMode))
        let constrainedRecorderIsEmpty = await constrained.recorder.isEmpty()
        XCTAssertTrue(constrainedRecorderIsEmpty)
    }

    func testColdBootstrapRestoresQueueFromRetainedContractWithoutCatalog() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        _ = try await fixture.discovery.retainPackageContractForInstallation(
            fixture.entry.id
        )
        let package = try fixture.entry.release.packageSpecForVerification()
        try fixture.journalStore.save(
            PackageBatchQueueJournal(
                intent: .running,
                packages: [package],
                completedPackageIDs: []
            )
        )
        await fixture.remote.setRecords([])
        _ = await fixture.discovery.refresh()

        let snapshot = try await fixture.controller.bootstrap()
        XCTAssertEqual(snapshot.retainedReleaseIDs, [fixture.entry.id])
        XCTAssertEqual(snapshot.retainedCatalogEntries, [fixture.entry])
        XCTAssertEqual(
            snapshot.installationState,
            .awaitingExplicitRestore(
                nextPackageID: package.id,
                completedPackageIDs: [],
                totalPackageCount: 1
            )
        )
        let recorderIsEmpty = await fixture.recorder.isEmpty()
        XCTAssertTrue(recorderIsEmpty)
        try await fixture.controller.resumeQueue()
        let resumedPackage = await fixture.recorder.waitForFirst()
        XCTAssertEqual(resumedPackage, package)
    }

    func testColdBootstrapKeepsInstalledWorldEntryAfterCatalogWithdrawal()
        async throws {
        let packageID = PackageID("deep-dive-alpha-v1")
        let generation = InstalledPackageGeneration(
            generationID: "installed-deep-dive-alpha-v1",
            packageID: packageID,
            packageVersion: SchemaVersion(major: 1, minor: 2),
            manifestDigest: String(repeating: "a", count: 64),
            relativePath: "generations/installed-deep-dive-alpha-v1",
            activationSequence: 1
        )
        let fixture = try await Fixture.make(
            installedIndex: InstalledPackageIndex(
                nextActivationSequence: 2,
                generations: [generation],
                activeGenerationByPackage: [
                    packageID: generation.generationID,
                ]
            )
        )
        defer { fixture.remove() }
        _ = try await fixture.discovery.retainPackageContractForInstallation(
            fixture.entry.id
        )
        await fixture.remote.setRecords([])
        let discovery = await fixture.discovery.refresh()
        XCTAssertTrue(discovery.availableEntries.isEmpty)

        let snapshot = try await fixture.controller.bootstrap()
        XCTAssertEqual(snapshot.retainedReleaseIDs, [fixture.entry.id])
        XCTAssertEqual(snapshot.retainedCatalogEntries, [fixture.entry])
        XCTAssertEqual(
            snapshot.currentInstalledPackageIDs,
            [fixture.entry.release.packageID]
        )
        XCTAssertEqual(
            snapshot.retainedCatalogEntries.first?.placement,
            fixture.entry.placement
        )
        XCTAssertEqual(
            snapshot.retainedCatalogEntries.first?.announcement,
            fixture.entry.announcement
        )
    }

    func testBootstrapRejectsInstalledBytesWithoutRetainedContract() async throws {
        let unknownPackageID = PackageID("unknown-deep-dive-v1")
        let index = InstalledPackageIndex(
            nextActivationSequence: 2,
            generations: [
                InstalledPackageGeneration(
                    generationID: "unknown-generation-v1",
                    packageID: unknownPackageID,
                    packageVersion: SchemaVersion(major: 1),
                    manifestDigest: String(repeating: "a", count: 64),
                    relativePath: "generations/unknown-generation-v1",
                    activationSequence: 1
                ),
            ],
            activeGenerationByPackage: [
                unknownPackageID: "unknown-generation-v1",
            ]
        )
        let fixture = try await Fixture.make(installedIndex: index)
        defer { fixture.remove() }

        do {
            _ = try await fixture.controller.bootstrap()
            XCTFail("Expected unknown installed bytes to fail closed")
        } catch {
            XCTAssertEqual(
                error as? FutureReleaseDownloadControllerError,
                .installedPackageWithoutContract(unknownPackageID)
            )
        }
    }
}

private struct Fixture: @unchecked Sendable {
    let root: URL
    let entry: ReleaseCatalogEntry
    let remote: FutureReleaseRemote
    let discovery: ReleaseDiscoveryController
    let contractStore: ReleaseInstallationContractStore
    let journalStore: PackageBatchQueueJournalStore
    let recorder: FuturePackageRecorder
    let controller: FutureReleaseDownloadController

    static func make(
        preferences: ExperiencePreferences = ExperiencePreferences(),
        networkContext: DownloadNetworkContext = DownloadNetworkContext(basis: .wifi),
        installedIndex: InstalledPackageIndex = .empty
    ) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "future-release-download-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let entry = try makeEntry()
        let remote = FutureReleaseRemote(records: [try makeRecord(from: entry)])
        let key = FutureContractKeyProvider()
        let cache = try ReleaseCatalogCacheStore(
            directoryURL: root.appendingPathComponent("catalog"),
            keyProvider: key
        )
        let contracts = try ReleaseInstallationContractStore(
            directoryURL: root.appendingPathComponent("contracts"),
            keyProvider: key
        )
        let discovery = ReleaseDiscoveryController(
            remote: remote,
            cacheStore: cache,
            installationContractStore: contracts,
            runtimeVersion: SchemaVersion(major: 1),
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )
        _ = await discovery.refresh()

        let recorder = FuturePackageRecorder()
        let installer = PackageBatchInstaller(installOperation: { package in
            await recorder.record(package)
            return ActivatedPackage(
                generation: InstalledPackageGeneration(
                    generationID: "installed-\(package.id.rawValue)",
                    packageID: package.id,
                    packageVersion: package.version,
                    manifestDigest: String(repeating: "b", count: 64),
                    relativePath: "generations/installed-\(package.id.rawValue)",
                    activationSequence: 1
                ),
                packageURL: root.appendingPathComponent("installed")
            )
        }, journalStore: try PackageBatchQueueJournalStore(
            directoryURL: root.appendingPathComponent("queue")
        ))
        let journalStore = try PackageBatchQueueJournalStore(
            directoryURL: root.appendingPathComponent("queue")
        )
        let controller = FutureReleaseDownloadController(
            discovery: discovery,
            installer: installer,
            networkBasisProvider: FixedFutureNetworkProvider(context: networkContext),
            installedIndexProvider: { installedIndex },
            preferencesProvider: { preferences }
        )
        return Fixture(
            root: root,
            entry: entry,
            remote: remote,
            discovery: discovery,
            contractStore: contracts,
            journalStore: journalStore,
            recorder: recorder,
            controller: controller
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func makeEntry() throws -> ReleaseCatalogEntry {
        let release = Release(
            id: "release-alpha-v1",
            contentID: "alpha-deep-dive",
            packageID: "deep-dive-alpha-v1",
            version: SchemaVersion(major: 1, minor: 2),
            chapterIDs: ["alpha-deep-dive"],
            maximumInstalledBytes: 420_000_000,
            publishedAtUnixMillis: 1_900_000_000_000,
            minimumRuntime: SchemaVersion(major: 1)
        )
        let entry = ReleaseCatalogEntry(
            release: release,
            placement: ReleaseWorldPlacement(
                worldNodeID: "world-alpha",
                historicalTime: HistoricalTimeAnchor(astronomicalYear: 1096)
            ),
            announcement: ReleaseAnnouncement(
                title: "A road opens",
                body: "The new route is ready."
            )
        )
        try entry.validate()
        return entry
    }

    private static func makeRecord(
        from entry: ReleaseCatalogEntry
    ) throws -> ReleaseRemoteRecord {
        ReleaseRemoteRecord(
            recordName: entry.id.rawValue,
            releasePayload: try JSONEncoder().encode(entry.release),
            worldNodeID: entry.placement.worldNodeID.rawValue,
            historicalYear: Int64(
                entry.placement.historicalTime.astronomicalYear
            ),
            chronologyOrdinal: Int64(entry.placement.historicalTime.ordinal),
            notificationTitle: entry.announcement.title,
            notificationBody: entry.announcement.body
        )
    }
}

private actor FutureReleaseRemote: ReleaseCatalogRemoteProviding {
    private var records: [ReleaseRemoteRecord]

    init(records: [ReleaseRemoteRecord]) {
        self.records = records
    }

    func ensureReleaseSubscription() async throws {}

    func fetchAvailableReleaseRecords() async throws -> [ReleaseRemoteRecord] {
        records
    }

    func setRecords(_ records: [ReleaseRemoteRecord]) {
        self.records = records
    }
}

private actor FuturePackageRecorder {
    private var packages: [ContentPackageSpec] = []

    func record(_ package: ContentPackageSpec) {
        packages.append(package)
    }

    func isEmpty() -> Bool { packages.isEmpty }

    func waitForFirst() async -> ContentPackageSpec? {
        for _ in 0 ..< 1_000 {
            if let first = packages.first { return first }
            await Task.yield()
        }
        return packages.first
    }
}

private struct FixedFutureNetworkProvider: DownloadNetworkBasisProviding {
    let context: DownloadNetworkContext

    func currentNetworkBasis() -> DownloadNetworkBasis { context.basis }
    func currentNetworkContext() -> DownloadNetworkContext { context }
}

private struct FutureContractKeyProvider: ReleaseCacheIntegrityKeyProviding {
    func loadOrCreateKey() throws -> Data {
        Data(repeating: 0x6D, count: 32)
    }
}
