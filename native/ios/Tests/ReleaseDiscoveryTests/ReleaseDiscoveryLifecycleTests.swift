@testable import ReleaseDiscovery
import ContentKit
import Foundation
import XCTest

final class ReleaseDiscoveryLifecycleTests: XCTestCase {
    private let runtimeVersion = SchemaVersion(major: 1)
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testActivationRefreshesCatalogWithoutRequestingNotificationPermission() async throws {
        let harness = try makeHarness(records: [record(id: "release-alpha-v1")])
        defer { harness.removeStorage() }

        let update = await harness.lifecycle.applicationDidBecomeActive()
        let requestCount = await harness.authorization.requestCount
        let registrationCount = await harness.registrar.registrationCount
        let subscriptionCount = await harness.remote.subscriptionCount
        let intents = await harness.scheduler.intents

        XCTAssertEqual(update.discovery.availableEntries.map(\.id), ["release-alpha-v1"])
        XCTAssertTrue(update.scheduledReleaseIDs.isEmpty)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(registrationCount, 0)
        XCTAssertEqual(subscriptionCount, 0)
        XCTAssertTrue(intents.isEmpty)
    }

    func testPushNeverRequestsPermissionAndDuplicateReleaseSchedulesOnceWhenAuthorized()
        async throws {
        let alpha = record(id: "release-alpha-v1")
        let beta = record(
            id: "release-beta-v1",
            packageID: "deep-dive-beta-v1",
            contentID: "beta-deep-dive",
            worldNodeID: "world-rhine-crossing",
            historicalYear: 406,
            chronologyOrdinal: 3,
            title: "The Rhine Frontier Breaks",
            body: "Enter the winter crossing of 406."
        )
        let harness = try makeHarness(records: [alpha])
        defer { harness.removeStorage() }
        _ = await harness.lifecycle.applicationDidBecomeActive()

        await harness.authorization.setStatus(.authorized)
        await harness.remote.setRecords([alpha, beta])
        let hint = ReleaseRemoteNotificationHint(
            subscriptionID: ReleaseServiceContract.cloudSubscriptionID
        )

        guard case let .refreshed(first) = await harness.lifecycle
            .handleRemoteNotification(hint) else {
            return XCTFail("Expected the release push to refresh")
        }
        guard case let .refreshed(duplicate) = await harness.lifecycle
            .handleRemoteNotification(hint) else {
            return XCTFail("Expected the duplicate push to refresh")
        }
        let requestCount = await harness.authorization.requestCount

        XCTAssertEqual(first.scheduledReleaseIDs, ["release-beta-v1"])
        XCTAssertTrue(duplicate.scheduledReleaseIDs.isEmpty)
        XCTAssertEqual(requestCount, 0)
        let intents = await harness.scheduler.intents
        XCTAssertEqual(intents.count, 1)
        XCTAssertEqual(intents.first?.announcement.title, "The Rhine Frontier Breaks")
        XCTAssertEqual(intents.first?.deepLink.worldNodeID, "world-rhine-crossing")
        XCTAssertEqual(
            intents.first?.deepLink.historicalTime,
            HistoricalTimeAnchor(astronomicalYear: 406, ordinal: 3)
        )
    }

    func testPermissionRequestIsBlockedUntilHistoricalExperience() async throws {
        let harness = try makeHarness(records: [record(id: "release-alpha-v1")])
        defer { harness.removeStorage() }

        let blocked = await harness.lifecycle.requestNotificationAuthorization()
        let blockedRequestCount = await harness.authorization.requestCount
        let blockedRegistrationCount = await harness.registrar.registrationCount
        XCTAssertEqual(blocked, .blockedUntilHistoricalExperience)
        XCTAssertEqual(blockedRequestCount, 0)
        XCTAssertEqual(blockedRegistrationCount, 0)

        await harness.lifecycle.recordHistoricalExperience(.prologueCompleted)
        let ready = await harness.lifecycle.requestNotificationAuthorization()
        guard case let .ready(subscription, update) = ready else {
            return XCTFail("Expected notification enrollment after the prologue")
        }
        let requestCount = await harness.authorization.requestCount
        let registrationCount = await harness.registrar.registrationCount
        let subscriptionCount = await harness.remote.subscriptionCount
        XCTAssertEqual(subscription, .ready)
        XCTAssertEqual(update.discovery.availableEntries.map(\.id), ["release-alpha-v1"])
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(registrationCount, 1)
        XCTAssertEqual(subscriptionCount, 1)
    }

    func testDeniedPermissionNeverRegistersOrSubscribes() async throws {
        let harness = try makeHarness(
            records: [record(id: "release-alpha-v1")],
            requestResult: .denied
        )
        defer { harness.removeStorage() }
        await harness.lifecycle.recordHistoricalExperience(.historicalBeatCompleted)

        let result = await harness.lifecycle.requestNotificationAuthorization()
        let requestCount = await harness.authorization.requestCount
        let registrationCount = await harness.registrar.registrationCount
        let subscriptionCount = await harness.remote.subscriptionCount

        XCTAssertEqual(result, .denied)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(registrationCount, 0)
        XCTAssertEqual(subscriptionCount, 0)
    }

    @MainActor
    func testNotificationTapKeepsExactAuthenticatedHistoricalPlacementOffline()
        async throws {
        let entry = record(
            id: "release-beta-v1",
            packageID: "deep-dive-beta-v1",
            contentID: "beta-deep-dive",
            worldNodeID: "world-rhine-crossing",
            historicalYear: 406,
            chronologyOrdinal: 3,
            title: "The Rhine Frontier Breaks",
            body: "Enter the winter crossing of 406."
        )
        let harness = try makeHarness(records: [entry])
        defer { harness.removeStorage() }
        let model = ReleaseDiscoveryApplicationModel(lifecycle: harness.lifecycle)
        _ = await model.applicationDidBecomeActive()
        await harness.remote.setFetchFailure(true)

        let resolution = await model.openRelease("release-beta-v1")

        guard case let .ready(intent) = resolution else {
            return XCTFail("Expected an authenticated cached deep link")
        }
        XCTAssertEqual(intent.packageID, "deep-dive-beta-v1")
        XCTAssertEqual(intent.contentID, "beta-deep-dive")
        XCTAssertEqual(intent.worldNodeID, "world-rhine-crossing")
        XCTAssertEqual(
            intent.historicalTime,
            HistoricalTimeAnchor(astronomicalYear: 406, ordinal: 3)
        )
        XCTAssertEqual(model.pendingDeepLink, intent)
        let consumed = await model.consumePendingDeepLink(
            releaseID: "release-beta-v1"
        )
        XCTAssertEqual(consumed, intent)
        XCTAssertNil(model.pendingDeepLink)
    }

    @MainActor
    func testNotificationTapSurvivesTerminationBeforeJourneyAdoption() async throws {
        let entry = record(
            id: "release-beta-v1",
            packageID: "deep-dive-beta-v1",
            contentID: "beta-deep-dive",
            worldNodeID: "world-rhine-crossing",
            historicalYear: 406,
            chronologyOrdinal: 3
        )
        let harness = try makeHarness(records: [entry])
        defer { harness.removeStorage() }
        let firstModel = ReleaseDiscoveryApplicationModel(lifecycle: harness.lifecycle)
        _ = await firstModel.applicationDidBecomeActive()
        guard case let .ready(opened) = await firstModel.openRelease(
            "release-beta-v1"
        ) else {
            return XCTFail("Expected the tapped release to be accepted")
        }

        // Rebuild every controller as a terminated process would. The remote
        // is unavailable, so only the authenticated two-slot cache can recover
        // the bounded release-ID marker and re-resolve its authored route.
        let coldRemote = LifecycleRemote(records: [])
        await coldRemote.setFetchFailure(true)
        let coldAuthorization = LifecycleAuthorization(requestResult: .authorized)
        let coldScheduler = LifecycleScheduler()
        let coldRegistrar = LifecycleRegistrar()
        let fixedNow = now
        let coldDiscovery = ReleaseDiscoveryController(
            remote: coldRemote,
            cacheStore: try ReleaseCatalogCacheStore(
                directoryURL: harness.directory,
                keyProvider: LifecycleCacheKeyProvider()
            ),
            runtimeVersion: runtimeVersion,
            now: { fixedNow }
        )
        let coldLifecycle = ReleaseDiscoveryLifecycleController(
            discovery: coldDiscovery,
            authorization: coldAuthorization,
            scheduler: coldScheduler,
            registrar: coldRegistrar
        )
        let coldModel = ReleaseDiscoveryApplicationModel(lifecycle: coldLifecycle)

        _ = await coldModel.applicationDidBecomeActive()
        XCTAssertEqual(coldModel.pendingDeepLink, opened)

        let consumed = await coldModel.consumePendingDeepLink(
            releaseID: opened.releaseID
        )
        XCTAssertEqual(consumed, opened)

        let finalDiscovery = ReleaseDiscoveryController(
            remote: coldRemote,
            cacheStore: try ReleaseCatalogCacheStore(
                directoryURL: harness.directory,
                keyProvider: LifecycleCacheKeyProvider()
            ),
            runtimeVersion: runtimeVersion,
            now: { fixedNow }
        )
        let finalModel = ReleaseDiscoveryApplicationModel(
            lifecycle: ReleaseDiscoveryLifecycleController(
                discovery: finalDiscovery,
                authorization: coldAuthorization,
                scheduler: coldScheduler,
                registrar: coldRegistrar
            )
        )
        _ = await finalModel.applicationDidBecomeActive()
        XCTAssertNil(finalModel.pendingDeepLink)
    }

    func testInvalidAnnouncementCannotEnterAuthenticatedCatalog() async throws {
        let invalid = record(
            id: "release-alpha-v1",
            title: " Internal title",
            body: "Open the route."
        )
        let harness = try makeHarness(records: [invalid])
        defer { harness.removeStorage() }

        let update = await harness.lifecycle.applicationDidBecomeActive()
        let intents = await harness.scheduler.intents

        XCTAssertEqual(update.discovery.issue, .invalidRemoteCatalog)
        XCTAssertTrue(update.discovery.availableEntries.isEmpty)
        XCTAssertTrue(intents.isEmpty)
    }

    private func makeHarness(
        records: [ReleaseRemoteRecord],
        requestResult: ReleaseNotificationAuthorizationStatus = .authorized
    ) throws -> LifecycleHarness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "release-lifecycle-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let remote = LifecycleRemote(records: records)
        let authorization = LifecycleAuthorization(requestResult: requestResult)
        let scheduler = LifecycleScheduler()
        let registrar = LifecycleRegistrar()
        let store = try ReleaseCatalogCacheStore(
            directoryURL: directory,
            keyProvider: LifecycleCacheKeyProvider()
        )
        let fixedNow = now
        let discovery = ReleaseDiscoveryController(
            remote: remote,
            cacheStore: store,
            runtimeVersion: runtimeVersion,
            now: { fixedNow }
        )
        return LifecycleHarness(
            directory: directory,
            remote: remote,
            authorization: authorization,
            scheduler: scheduler,
            registrar: registrar,
            lifecycle: ReleaseDiscoveryLifecycleController(
                discovery: discovery,
                authorization: authorization,
                scheduler: scheduler,
                registrar: registrar
            )
        )
    }

    private func record(
        id: String,
        packageID: String = "deep-dive-alpha-v1",
        contentID: String = "alpha-deep-dive",
        worldNodeID: String = "world-alpha",
        historicalYear: Int64 = 1096,
        chronologyOrdinal: Int64 = 0,
        title: String = "The First Route",
        body: String = "Enter the new historical route."
    ) -> ReleaseRemoteRecord {
        let release = Release(
            id: ReleaseID(id),
            contentID: contentID,
            packageID: PackageID(packageID),
            version: SchemaVersion(major: 1),
            chapterIDs: [ChapterID(contentID)],
            maximumInstalledBytes: 420_000_000,
            publishedAtUnixMillis: 1_900_000_000_000,
            minimumRuntime: SchemaVersion(major: 1)
        )
        return ReleaseRemoteRecord(
            recordName: id,
            releasePayload: try! JSONEncoder().encode(release),
            worldNodeID: worldNodeID,
            historicalYear: historicalYear,
            chronologyOrdinal: chronologyOrdinal,
            notificationTitle: title,
            notificationBody: body
        )
    }
}

private struct LifecycleHarness {
    let directory: URL
    let remote: LifecycleRemote
    let authorization: LifecycleAuthorization
    let scheduler: LifecycleScheduler
    let registrar: LifecycleRegistrar
    let lifecycle: ReleaseDiscoveryLifecycleController

    func removeStorage() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct LifecycleCacheKeyProvider: ReleaseCacheIntegrityKeyProviding {
    func loadOrCreateKey() throws -> Data { Data(repeating: 0x5B, count: 32) }
}

private actor LifecycleRemote: ReleaseCatalogRemoteProviding {
    private var records: [ReleaseRemoteRecord]
    private var shouldFailFetch = false
    private(set) var subscriptionCount = 0

    init(records: [ReleaseRemoteRecord]) {
        self.records = records
    }

    func ensureReleaseSubscription() async throws { subscriptionCount += 1 }

    func fetchAvailableReleaseRecords() async throws -> [ReleaseRemoteRecord] {
        if shouldFailFetch { throw LifecycleTestError.unavailable }
        return records
    }

    func setRecords(_ records: [ReleaseRemoteRecord]) { self.records = records }
    func setFetchFailure(_ value: Bool) { shouldFailFetch = value }
}

private actor LifecycleAuthorization: ReleaseNotificationAuthorizationProviding {
    private var status = ReleaseNotificationAuthorizationStatus.notDetermined
    private let requestResult: ReleaseNotificationAuthorizationStatus
    private(set) var requestCount = 0

    init(requestResult: ReleaseNotificationAuthorizationStatus) {
        self.requestResult = requestResult
    }

    func authorizationStatus() async -> ReleaseNotificationAuthorizationStatus { status }

    func requestAuthorization() async throws -> ReleaseNotificationAuthorizationStatus {
        requestCount += 1
        status = requestResult
        return status
    }

    func setStatus(_ status: ReleaseNotificationAuthorizationStatus) {
        self.status = status
    }
}

private actor LifecycleScheduler: ReleaseNotificationScheduling {
    private(set) var intents: [ReleaseNotificationIntent] = []
    func schedule(_ intent: ReleaseNotificationIntent) async throws { intents.append(intent) }
}

private actor LifecycleRegistrar: ReleaseRemoteNotificationRegistering {
    private(set) var registrationCount = 0
    func registerForRemoteNotifications() async { registrationCount += 1 }
}

private enum LifecycleTestError: Error {
    case unavailable
}
