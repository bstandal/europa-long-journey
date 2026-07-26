@testable import ReleaseDiscovery
import ContentKit
import Foundation
import XCTest

final class ReleaseDiscoveryTests: XCTestCase {
    private let currentRuntime = SchemaVersion(major: 1, minor: 2, patch: 0)
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testOfflineRefreshFallsBackToAuthenticatedCachedCatalog() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = FakeReleaseRemote(records: [try record(id: "release-alpha-v1")])
        let store = try cacheStore(at: directory)
        let online = controller(remote: remote, store: store)

        let first = await online.refresh()
        XCTAssertEqual(first.source, .remote)
        XCTAssertEqual(first.availableEntries.map(\.id), ["release-alpha-v1"])
        XCTAssertTrue(first.notificationIntents.isEmpty)

        await remote.setFetchFailure(true)
        let coldOffline = controller(remote: remote, store: store)
        let fallback = await coldOffline.refresh()
        XCTAssertEqual(fallback.source, .cacheAfterRemoteFailure)
        XCTAssertEqual(fallback.issue, .remoteUnavailable)
        XCTAssertEqual(fallback.availableEntries.map(\.id), ["release-alpha-v1"])
        XCTAssertTrue(fallback.notificationIntents.isEmpty)
    }

    func testDuplicatePushProducesExactlyOneDurableNotificationClaim() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = FakeReleaseRemote(records: [try record(id: "release-alpha-v1")])
        let store = try cacheStore(at: directory)
        let discovery = controller(remote: remote, store: store)
        _ = await discovery.refresh() // Establishes a no-spam install baseline.

        await remote.setRecords([
            try record(id: "release-alpha-v1"),
            try record(
                id: "release-beta-v1",
                packageID: "deep-dive-beta-v1",
                contentID: "beta-deep-dive",
                worldNodeID: "world-vienna",
                historicalYear: 1683,
                chronologyOrdinal: 2
            ),
        ])
        let hint = ReleaseRemoteNotificationHint(
            subscriptionID: ReleaseServiceContract.cloudSubscriptionID,
            recordName: "release-beta-v1"
        )

        let firstPush = await discovery.handleRemoteNotification(hint)
        guard case let .refreshed(firstResult) = firstPush else {
            return XCTFail("Expected release subscription push to refresh")
        }
        XCTAssertEqual(firstResult.notificationIntents.count, 1)
        let intent = try XCTUnwrap(firstResult.notificationIntents.first)
        XCTAssertEqual(intent.notificationIdentifier, "release-available-release-beta-v1")
        XCTAssertEqual(intent.deepLink.releaseID, "release-beta-v1")
        XCTAssertEqual(intent.deepLink.packageID, "deep-dive-beta-v1")
        XCTAssertEqual(intent.deepLink.packageVersion, SchemaVersion(major: 1))
        XCTAssertEqual(intent.deepLink.worldNodeID, "world-vienna")
        XCTAssertEqual(
            intent.deepLink.historicalTime,
            HistoricalTimeAnchor(astronomicalYear: 1683, ordinal: 2)
        )

        let duplicatePush = await discovery.handleRemoteNotification(hint)
        guard case let .refreshed(duplicateResult) = duplicatePush else {
            return XCTFail("Expected duplicate hint to refresh safely")
        }
        XCTAssertTrue(duplicateResult.notificationIntents.isEmpty)

        // Dedupe survives termination rather than living only in actor memory.
        let coldDiscovery = controller(remote: remote, store: store)
        let afterRestart = await coldDiscovery.handleRemoteNotification(hint)
        guard case let .refreshed(restartedResult) = afterRestart else {
            return XCTFail("Expected refresh after restart")
        }
        XCTAssertTrue(restartedResult.notificationIntents.isEmpty)
    }

    func testOutOfOrderRemoteRecordsHaveOneCanonicalChronologicalOrder() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = FakeReleaseRemote(records: [
            try record(
                id: "release-charlie-v1",
                packageID: "deep-dive-charlie-v1",
                contentID: "charlie-deep-dive",
                publishedAt: 1_950_000_000_000
            ),
            try record(
                id: "release-beta-v1",
                packageID: "deep-dive-beta-v1",
                contentID: "beta-deep-dive",
                publishedAt: 1_900_000_000_000
            ),
            try record(
                id: "release-alpha-v1",
                publishedAt: 1_900_000_000_000
            ),
        ])
        let result = await controller(
            remote: remote,
            store: try cacheStore(at: directory)
        ).refresh()

        XCTAssertEqual(
            result.availableEntries.map(\.id),
            ["release-alpha-v1", "release-beta-v1", "release-charlie-v1"]
        )
    }

    func testAuthoritativeQueryRemovalDoesNotPermitNotificationOnReappearance() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let alpha = try record(id: "release-alpha-v1")
        let beta = try record(
            id: "release-beta-v1",
            packageID: "deep-dive-beta-v1",
            contentID: "beta-deep-dive"
        )
        let remote = FakeReleaseRemote(records: [alpha])
        let store = try cacheStore(at: directory)
        let discovery = controller(remote: remote, store: store)
        _ = await discovery.refresh()

        await remote.setRecords([alpha, beta])
        let introduced = await discovery.refresh()
        XCTAssertEqual(
            introduced.notificationIntents.map(\.deepLink.releaseID),
            ["release-beta-v1"]
        )

        await remote.setRecords([alpha])
        let removed = await discovery.refresh()
        XCTAssertEqual(removed.availableEntries.map(\.id), ["release-alpha-v1"])

        await remote.setRecords([alpha, beta])
        let reappeared = await discovery.refresh()
        XCTAssertEqual(
            reappeared.availableEntries.map(\.id),
            ["release-alpha-v1", "release-beta-v1"]
        )
        XCTAssertTrue(reappeared.notificationIntents.isEmpty)
    }

    func testNewestCorruptCacheSlotFallsBackToOlderAuthenticatedGeneration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try cacheStore(at: directory)
        let first = try snapshot(entries: [entry(id: "release-alpha-v1")])
        let secondEntries = try [
            entry(id: "release-alpha-v1"),
            entry(
                id: "release-beta-v1",
                packageID: "deep-dive-beta-v1",
                contentID: "beta-deep-dive"
            ),
        ].validatedCanonicalReleaseCatalog()
        let second = ReleaseCatalogCacheSnapshot(
            entries: secondEntries,
            notificationClaimedReleaseIDs: ["release-alpha-v1"],
            baselineEstablished: true,
            lastSuccessfulRefreshUnixMillis: 2_000_000_000_000
        )

        XCTAssertEqual(try store.save(first), 2)
        XCTAssertEqual(try store.save(second), 3)
        try Data("interrupted".utf8).write(to: store.slotAURL, options: .atomic)
        XCTAssertEqual(try store.load(), first)
    }

    func testNotificationClaimIsSealedAgainstNewestSlotCorruption() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = FakeReleaseRemote(records: [try record(id: "release-alpha-v1")])
        let store = try cacheStore(at: directory)
        let discovery = controller(remote: remote, store: store)
        _ = await discovery.refresh()

        await remote.setRecords([
            try record(id: "release-alpha-v1"),
            try record(
                id: "release-beta-v1",
                packageID: "deep-dive-beta-v1",
                contentID: "beta-deep-dive"
            ),
        ])
        let hint = ReleaseRemoteNotificationHint(
            subscriptionID: ReleaseServiceContract.cloudSubscriptionID
        )
        guard case let .refreshed(first) = await discovery.handleRemoteNotification(hint) else {
            return XCTFail("Expected release refresh")
        }
        XCTAssertEqual(first.notificationIntents.map(\.deepLink.releaseID), ["release-beta-v1"])

        // The changed claim set is sealed into both slots. Losing the newest
        // one therefore cannot cause a second notification after termination.
        try Data("interrupted".utf8).write(to: store.slotBURL, options: .atomic)
        let cold = controller(remote: remote, store: store)
        guard case let .refreshed(afterCorruption) = await cold.handleRemoteNotification(hint) else {
            return XCTFail("Expected release refresh after cache fallback")
        }
        XCTAssertTrue(afterCorruption.notificationIntents.isEmpty)
    }

    func testPendingDeepLinkMarkerAndItsClearAreSealedAcrossFallback() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = FakeReleaseRemote(records: [try record(id: "release-alpha-v1")])
        let store = try cacheStore(at: directory)
        let discovery = controller(remote: remote, store: store)
        _ = await discovery.refresh()

        guard case let .ready(opened) = await discovery.beginDeepLink(
            for: "release-alpha-v1"
        ) else {
            return XCTFail("Expected a durable pending deep link")
        }

        // Beginning the tap writes generations 3 and 4. Corrupting the newest
        // slot must still recover the marker from the sealed fallback.
        try Data("interrupted".utf8).write(to: store.slotBURL, options: .atomic)
        let cold = controller(remote: remote, store: store)
        let recovered = await cold.pendingDeepLink()
        let completed = await cold.completePendingDeepLink(for: opened.releaseID)
        XCTAssertEqual(recovered, opened)
        XCTAssertTrue(completed)

        // Clearing from fallback writes generations 4 and 5. Losing the newest
        // one must not resurrect a notification tap that Journey adopted.
        try Data("interrupted-again".utf8).write(to: store.slotAURL, options: .atomic)
        let afterClear = controller(remote: remote, store: store)
        let resurrected = await afterClear.pendingDeepLink()
        XCTAssertNil(resurrected)
    }

    func testFullyCorruptCacheFailsClosedOfflineAndRebuildsFromValidRemote() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try cacheStore(at: directory)
        try store.save(try snapshot(entries: [entry(id: "release-alpha-v1")]))
        try store.save(try snapshot(entries: [
            entry(id: "release-alpha-v1"),
            entry(
                id: "release-beta-v1",
                packageID: "deep-dive-beta-v1",
                contentID: "beta-deep-dive"
            ),
        ]))
        try Data("bad-a".utf8).write(to: store.slotAURL, options: .atomic)
        try Data("bad-b".utf8).write(to: store.slotBURL, options: .atomic)

        let offline = FakeReleaseRemote(records: [], fetchFailure: true)
        let unavailable = await controller(remote: offline, store: store).refresh()
        XCTAssertEqual(unavailable.source, .empty)
        XCTAssertEqual(unavailable.issue, .cacheAndRemoteUnavailable)
        XCTAssertTrue(unavailable.availableEntries.isEmpty)

        let online = FakeReleaseRemote(records: [try record(id: "release-alpha-v1")])
        let repaired = await controller(remote: online, store: store).refresh()
        XCTAssertEqual(repaired.source, .remote)
        XCTAssertEqual(repaired.issue, .cacheRecovered)
        XCTAssertEqual(repaired.availableEntries.map(\.id), ["release-alpha-v1"])
        XCTAssertNotNil(try store.load())
    }

    func testUnsupportedRuntimeIsCachedButCannotNotifyOrDeepLink() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = FakeReleaseRemote(records: [
            try record(
                id: "release-future-runtime-v1",
                packageID: "deep-dive-future-runtime-v1",
                contentID: "future-runtime-deep-dive",
                minimumRuntime: SchemaVersion(major: 2)
            ),
        ])
        let discovery = controller(remote: remote, store: try cacheStore(at: directory))

        let result = await discovery.refresh()
        XCTAssertTrue(result.availableEntries.isEmpty)
        XCTAssertEqual(
            result.unsupportedRuntimeEntries.map(\.id),
            ["release-future-runtime-v1"]
        )
        XCTAssertTrue(result.notificationIntents.isEmpty)
        let resolution = await discovery.deepLink(for: "release-future-runtime-v1")
        XCTAssertEqual(resolution, .requiresRuntime(minimum: SchemaVersion(major: 2)))
        let contract = await discovery.packageContract(for: "release-future-runtime-v1")
        XCTAssertEqual(contract, .requiresRuntime(minimum: SchemaVersion(major: 2)))
    }

    func testPackageContractComesFromAuthenticatedCatalogWithExactInstallFields() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = FakeReleaseRemote(records: [
            try record(
                id: "release-alpha-v1",
                version: SchemaVersion(major: 1, minor: 4, patch: 2),
                worldNodeID: "world-anatolia",
                historicalYear: 1096,
                chronologyOrdinal: 3
            ),
        ])
        let store = try cacheStore(at: directory)
        let online = controller(remote: remote, store: store)
        _ = await online.refresh()

        guard case let .ready(entry) = await online.packageContract(
            for: "release-alpha-v1"
        ) else {
            return XCTFail("Expected authenticated package contract")
        }
        XCTAssertEqual(entry.release.packageID, "deep-dive-alpha-v1")
        XCTAssertEqual(entry.release.chapterIDs, ["alpha-deep-dive"])
        XCTAssertEqual(entry.release.maximumInstalledBytes, 420_000_000)
        XCTAssertEqual(entry.release.version, SchemaVersion(major: 1, minor: 4, patch: 2))
        XCTAssertEqual(entry.placement.worldNodeID, "world-anatolia")

        await remote.setFetchFailure(true)
        let coldOffline = controller(remote: remote, store: store)
        let offlineContract = await coldOffline.packageContract(
            for: "release-alpha-v1"
        )
        let missingContract = await coldOffline.packageContract(
            for: "release-unknown-v1"
        )
        XCTAssertEqual(offlineContract, .ready(entry))
        XCTAssertEqual(missingContract, .unknownRelease)
    }

    func testRetainedInstallContractSurvivesAuthoritativeCatalogWithdrawal() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let releaseRecord = try record(id: "release-alpha-v1")
        let remote = FakeReleaseRemote(records: [releaseRecord])
        let cache = try cacheStore(at: directory.appendingPathComponent("cache"))
        let contracts = try ReleaseInstallationContractStore(
            directoryURL: directory.appendingPathComponent("contracts"),
            keyProvider: FixedReleaseCacheKeyProvider()
        )
        let fixedNow = now
        let discovery = ReleaseDiscoveryController(
            remote: remote,
            cacheStore: cache,
            installationContractStore: contracts,
            runtimeVersion: currentRuntime,
            now: { fixedNow }
        )
        _ = await discovery.refresh()

        guard case let .ready(retained) = try await discovery
            .retainPackageContractForInstallation("release-alpha-v1") else {
            return XCTFail("Expected retained installation contract")
        }
        await remote.setRecords([])
        let withdrawn = await discovery.refresh()
        let coldContract = try await discovery.retainedInstallationContract(
            for: "release-alpha-v1"
        )
        XCTAssertTrue(withdrawn.availableEntries.isEmpty)
        XCTAssertEqual(coldContract, retained)
    }

    func testFuturePublicationTimeCannotBecomeAvailableEarly() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = FakeReleaseRemote(records: [
            try record(id: "release-future-v1", publishedAt: 2_100_000_000_000),
        ])
        let discovery = controller(remote: remote, store: try cacheStore(at: directory))

        let result = await discovery.refresh()
        XCTAssertTrue(result.availableEntries.isEmpty)
        XCTAssertTrue(result.notificationIntents.isEmpty)
        let resolution = await discovery.deepLink(for: "release-future-v1")
        XCTAssertEqual(resolution, .notPublished)
        let contract = await discovery.packageContract(for: "release-future-v1")
        XCTAssertEqual(contract, .notPublished)
    }

    func testRemoteRecordIdentityAndPackageBindingFailClosed() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mismatched = try record(id: "release-alpha-v1", recordName: "release-impostor-v1")
        let identityRemote = FakeReleaseRemote(records: [mismatched])
        let identityResult = await controller(
            remote: identityRemote,
            store: try cacheStore(at: directory.appendingPathComponent("identity"))
        ).refresh()
        XCTAssertEqual(identityResult.issue, .invalidRemoteCatalog)
        XCTAssertTrue(identityResult.availableEntries.isEmpty)

        let duplicateBindingRemote = FakeReleaseRemote(records: [
            try record(id: "release-alpha-v1"),
            try record(
                id: "release-beta-v1",
                packageID: "deep-dive-alpha-v1",
                contentID: "beta-deep-dive"
            ),
        ])
        let bindingResult = await controller(
            remote: duplicateBindingRemote,
            store: try cacheStore(at: directory.appendingPathComponent("binding"))
        ).refresh()
        XCTAssertEqual(bindingResult.issue, .invalidRemoteCatalog)
        XCTAssertTrue(bindingResult.availableEntries.isEmpty)
    }

    func testUnrelatedPushIsIgnoredWithoutFetching() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = FakeReleaseRemote(records: [try record(id: "release-alpha-v1")])
        let discovery = controller(remote: remote, store: try cacheStore(at: directory))
        let result = await discovery.handleRemoteNotification(
            ReleaseRemoteNotificationHint(subscriptionID: "another-subscription")
        )

        XCTAssertEqual(result, .ignored)
        let fetchCount = await remote.fetchCount()
        XCTAssertEqual(fetchCount, 0)
    }

    func testSubscriptionFailureLeavesCatalogUsable() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = FakeReleaseRemote(
            records: [try record(id: "release-alpha-v1")],
            subscriptionFailure: true
        )
        let discovery = controller(remote: remote, store: try cacheStore(at: directory))

        let subscription = await discovery.prepareRemoteNotifications()
        let refresh = await discovery.refresh()
        XCTAssertEqual(subscription, .unavailable)
        XCTAssertEqual(refresh.availableEntries.map(\.id), ["release-alpha-v1"])
    }

    private func controller(
        remote: FakeReleaseRemote,
        store: ReleaseCatalogCacheStore
    ) -> ReleaseDiscoveryController {
        let fixedNow = now
        return ReleaseDiscoveryController(
            remote: remote,
            cacheStore: store,
            runtimeVersion: currentRuntime,
            now: { fixedNow }
        )
    }

    private func record(
        id: String,
        recordName: String? = nil,
        packageID: String = "deep-dive-alpha-v1",
        contentID: String = "alpha-deep-dive",
        version: SchemaVersion = SchemaVersion(major: 1),
        publishedAt: Int64 = 1_900_000_000_000,
        minimumRuntime: SchemaVersion = SchemaVersion(major: 1),
        worldNodeID: String = "world-alpha",
        historicalYear: Int64 = 1096,
        chronologyOrdinal: Int64 = 0
    ) throws -> ReleaseRemoteRecord {
        let release = Release(
            id: ReleaseID(id),
            contentID: contentID,
            packageID: PackageID(packageID),
            version: version,
            chapterIDs: [ChapterID(contentID)],
            maximumInstalledBytes: 420_000_000,
            publishedAtUnixMillis: publishedAt,
            minimumRuntime: minimumRuntime
        )
        return ReleaseRemoteRecord(
            recordName: recordName ?? id,
            releasePayload: try JSONEncoder().encode(release),
            worldNodeID: worldNodeID,
            historicalYear: historicalYear,
            chronologyOrdinal: chronologyOrdinal,
            notificationTitle: "Test release \(id)",
            notificationBody: "Open the authored test route."
        )
    }

    private func entry(
        id: String,
        packageID: String = "deep-dive-alpha-v1",
        contentID: String = "alpha-deep-dive"
    ) throws -> ReleaseCatalogEntry {
        try record(id: id, packageID: packageID, contentID: contentID).decode()
    }

    private func snapshot(
        entries: [ReleaseCatalogEntry]
    ) throws -> ReleaseCatalogCacheSnapshot {
        let canonical = try entries.validatedCanonicalReleaseCatalog()
        return ReleaseCatalogCacheSnapshot(
            entries: canonical,
            notificationClaimedReleaseIDs: canonical.map(\.id),
            baselineEstablished: true,
            lastSuccessfulRefreshUnixMillis: 2_000_000_000_000
        )
    }

    private func cacheStore(at directory: URL) throws -> ReleaseCatalogCacheStore {
        try ReleaseCatalogCacheStore(
            directoryURL: directory,
            keyProvider: FixedReleaseCacheKeyProvider()
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "release-discovery-tests-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

private struct FixedReleaseCacheKeyProvider: ReleaseCacheIntegrityKeyProviding {
    func loadOrCreateKey() throws -> Data {
        Data(repeating: 0x5A, count: 32)
    }
}

private actor FakeReleaseRemote: ReleaseCatalogRemoteProviding {
    private var records: [ReleaseRemoteRecord]
    private var shouldFailFetch: Bool
    private var shouldFailSubscription: Bool
    private var fetchInvocations = 0

    init(
        records: [ReleaseRemoteRecord],
        fetchFailure: Bool = false,
        subscriptionFailure: Bool = false
    ) {
        self.records = records
        shouldFailFetch = fetchFailure
        shouldFailSubscription = subscriptionFailure
    }

    func ensureReleaseSubscription() async throws {
        if shouldFailSubscription { throw FakeReleaseError.unavailable }
    }

    func fetchAvailableReleaseRecords() async throws -> [ReleaseRemoteRecord] {
        fetchInvocations += 1
        if shouldFailFetch { throw FakeReleaseError.unavailable }
        return records
    }

    func setRecords(_ records: [ReleaseRemoteRecord]) {
        self.records = records
    }

    func setFetchFailure(_ value: Bool) {
        shouldFailFetch = value
    }

    func fetchCount() -> Int { fetchInvocations }
}

private enum FakeReleaseError: Error {
    case unavailable
}
