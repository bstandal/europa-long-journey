import CommerceKit
import ContentKit
import Foundation
import XCTest

final class CommerceKitTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 2_000_000_000)

    func testAccessResolverKeepsFreeTriadOpenAndGatesEveryOtherLaunchChapter() {
        let resolver = ChapterAccessResolver()
        XCTAssertEqual(EntitlementController.productID, LaunchContent.fullWorkStoreProductID)

        for chapterID in LaunchContent.chapterOrder {
            let access = resolver.access(to: chapterID, snapshot: nil, at: instant)
            if LaunchContent.freeChapterIDs.contains(chapterID) {
                XCTAssertEqual(access, .included)
            } else {
                XCTAssertEqual(
                    access,
                    .locked(entitlementID: LaunchContent.fullWorkEntitlementID)
                )
            }
        }

        let owned = EntitlementSnapshot.fromVerified(activeTransaction(), evaluatedAt: instant)
        for chapterID in LaunchContent.chapterOrder where !LaunchContent.freeChapterIDs.contains(chapterID) {
            XCTAssertEqual(resolver.access(to: chapterID, snapshot: owned, at: instant), .purchased)
        }
        XCTAssertEqual(
            resolver.access(to: "future-deep-dive", snapshot: owned, at: instant),
            .locked(entitlementID: LaunchContent.fullWorkEntitlementID)
        )
    }

    func testAuthenticatedSnapshotRoundTripsAndNewestCorruptSlotFallsBack() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try snapshotStore(at: directory)
        let notPurchased = EntitlementSnapshot.notPurchased(at: instant.addingTimeInterval(-1))
        let owned = EntitlementSnapshot.fromVerified(activeTransaction(id: 41), evaluatedAt: instant)

        XCTAssertEqual(try store.save(notPurchased), 1)
        XCTAssertEqual(try store.save(owned), 2)
        XCTAssertEqual(try store.load(), owned)

        try Data("interrupted".utf8).write(
            to: directory.appendingPathComponent("entitlement-snapshot-b.json"),
            options: .atomic
        )
        XCTAssertEqual(try store.load(), notPurchased)
    }

    func testCompletedRevocationSealsBothFallbackSlotsAgainstOwnershipRollback() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try snapshotStore(at: directory)
        let owned = EntitlementSnapshot.fromVerified(activeTransaction(id: 51), evaluatedAt: instant)
        let revoked = EntitlementSnapshot.fromVerified(
            revokedTransaction(id: 51, type: .fullRefund),
            evaluatedAt: instant.addingTimeInterval(60)
        )

        XCTAssertEqual(try store.save(owned), 1)
        XCTAssertEqual(try store.save(revoked), 3)
        XCTAssertEqual(try store.load(), revoked)

        try Data("interrupted".utf8).write(
            to: directory.appendingPathComponent("entitlement-snapshot-a.json"),
            options: .atomic
        )
        XCTAssertEqual(try store.load(), revoked)
    }

    func testSnapshotTamperingOrWrongIntegrityKeyFailsClosed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try snapshotStore(at: directory)
        try store.save(EntitlementSnapshot.fromVerified(activeTransaction(), evaluatedAt: instant))

        let wrongKeyStore = try EntitlementSnapshotStore(
            directoryURL: directory,
            keyProvider: FixedIntegrityKeyProvider(byte: 0x99)
        )
        XCTAssertThrowsError(try wrongKeyStore.load()) { error in
            XCTAssertEqual(error as? EntitlementSnapshotStoreError, .corruptStorage)
        }

        let slot = directory.appendingPathComponent("entitlement-snapshot-a.json")
        var data = try Data(contentsOf: slot)
        data[data.startIndex] ^= 0x01
        try data.write(to: slot, options: .atomic)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? EntitlementSnapshotStoreError, .corruptStorage)
        }
    }

    func testVerifiedPurchasePersistsBeforeFinishAndRestoresOffline() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeCommerceProvider()
        let transaction = activeTransaction(id: 77)
        await provider.setPurchaseResult(.success(.verified(transaction)))
        let store = try snapshotStore(at: directory)
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: store,
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )

        let outcome = try await controller.purchase()
        guard case let .success(snapshot) = outcome else {
            return XCTFail("Expected verified purchase success")
        }
        XCTAssertTrue(snapshot.grantsAccess(at: instant))
        let finishedAfterPurchase = await provider.finishedTransactionIDs()
        XCTAssertEqual(finishedAfterPurchase, [77])

        await provider.setCurrentEntitlementsError(true)
        let coldController = try EntitlementController(
            provider: provider,
            snapshotStore: store,
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )
        let coldOwnership = await coldController.ownsFullWork()
        XCTAssertTrue(coldOwnership)
        let refresh = await coldController.refreshCurrentEntitlements()
        XCTAssertEqual(refresh, .retainedCached(snapshot, reason: .storeUnavailable))
        let retainedOwnership = await coldController.ownsFullWork()
        XCTAssertTrue(retainedOwnership)
    }

    func testPendingAndCancelledPurchaseNeverMutateEntitlement() async throws {
        for result in [StorePurchaseResult.pending, .cancelled] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let provider = FakeCommerceProvider()
            await provider.setPurchaseResult(result)
            let controller = try EntitlementController(
                provider: provider,
                snapshotStore: snapshotStore(at: directory),
                now: { Date(timeIntervalSince1970: 2_000_000_000) }
            )

            let outcome = try await controller.purchase()
            if result == .pending {
                XCTAssertEqual(outcome, .pending)
            } else {
                XCTAssertEqual(outcome, .cancelled)
            }
            let ownsFullWork = await controller.ownsFullWork()
            let finished = await provider.finishedTransactionIDs()
            XCTAssertFalse(ownsFullWork)
            XCTAssertEqual(finished, [])
        }
    }

    func testUnverifiedPurchaseCannotUnlockOrFinish() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeCommerceProvider()
        await provider.setPurchaseResult(
            .success(.unverified(productID: LaunchContent.fullWorkStoreProductID))
        )
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: snapshotStore(at: directory),
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )

        do {
            _ = try await controller.purchase()
            XCTFail("Unverified purchase must fail")
        } catch {
            XCTAssertEqual(error as? CommerceFailure, .unverifiedTransaction)
        }
        let ownsFullWork = await controller.ownsFullWork()
        let finished = await provider.finishedTransactionIDs()
        XCTAssertFalse(ownsFullWork)
        XCTAssertEqual(finished, [])
    }

    func testProductMustExistAndBeTheLaunchNonConsumable() async throws {
        let cases: [(CommerceProduct?, CommerceFailure)] = [
            (nil, .productUnavailable),
            (
                CommerceProduct(
                    id: LaunchContent.fullWorkStoreProductID,
                    kind: .autoRenewableSubscription
                ),
                .productIsNotNonConsumable
            ),
            (CommerceProduct(id: "wrong-product", kind: .nonConsumable), .productIdentifierMismatch),
        ]

        for (product, expectedError) in cases {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let provider = FakeCommerceProvider()
            await provider.setProduct(product)
            let controller = try EntitlementController(
                provider: provider,
                snapshotStore: snapshotStore(at: directory),
                now: { Date(timeIntervalSince1970: 2_000_000_000) }
            )
            do {
                _ = try await controller.purchase()
                XCTFail("Invalid product configuration must fail")
            } catch {
                XCTAssertEqual(error as? CommerceFailure, expectedError)
            }
        }
    }

    func testValidatedProductDetailsPreserveStoreDisplayPrice() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeCommerceProvider()
        let expected = CommerceProduct(
            id: LaunchContent.fullWorkStoreProductID,
            kind: .nonConsumable,
            displayPrice: "£14.99"
        )
        await provider.setProduct(expected)
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: snapshotStore(at: directory),
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )

        let product = try await controller.productDetails()
        XCTAssertEqual(product, expected)
    }

    func testSuccessfulEmptyCurrentEntitlementsRemovesCachedOwnership() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try snapshotStore(at: directory)
        try store.save(EntitlementSnapshot.fromVerified(activeTransaction(), evaluatedAt: instant))
        let provider = FakeCommerceProvider()
        await provider.setCurrentEntitlements([])
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: store,
            now: { Date(timeIntervalSince1970: 2_000_000_001) }
        )

        let outcome = await controller.refreshCurrentEntitlements()
        guard case let .updated(snapshot) = outcome else {
            return XCTFail("Expected authoritative empty refresh")
        }
        XCTAssertEqual(snapshot.state, .notPurchased)
        let ownsAfterEmptyRefresh = await controller.ownsFullWork()
        XCTAssertFalse(ownsAfterEmptyRefresh)
        XCTAssertEqual(try store.load()?.state, .notPurchased)
    }

    func testUnverifiedRefreshRetainsValidCachedOwnership() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try snapshotStore(at: directory)
        let cached = EntitlementSnapshot.fromVerified(activeTransaction(), evaluatedAt: instant)
        try store.save(cached)
        let provider = FakeCommerceProvider()
        await provider.setCurrentEntitlements([
            .unverified(productID: LaunchContent.fullWorkStoreProductID),
        ])
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: store,
            now: { Date(timeIntervalSince1970: 2_000_000_001) }
        )

        let refresh = await controller.refreshCurrentEntitlements()
        XCTAssertEqual(
            refresh,
            .retainedCached(cached, reason: .unverifiedTargetTransaction)
        )
        let retainedOwnership = await controller.ownsFullWork()
        XCTAssertTrue(retainedOwnership)
    }

    func testRestoreSyncsThenRefreshesAndSyncFailureKeepsCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeCommerceProvider()
        let transaction = activeTransaction(id: 90)
        await provider.setCurrentEntitlements([.verified(transaction)])
        let store = try snapshotStore(at: directory)
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: store,
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )

        guard case let .updated(snapshot) = await controller.restorePurchases() else {
            return XCTFail("Restore should refresh after sync")
        }
        XCTAssertEqual(snapshot.transactionID, 90)
        let syncCount = await provider.syncInvocationCount()
        XCTAssertEqual(syncCount, 1)

        await provider.setSyncError(true)
        await provider.setCurrentEntitlements([])
        let failedRestore = await controller.restorePurchases()
        XCTAssertEqual(failedRestore, .retainedCached(snapshot, reason: .storeUnavailable))
        let retainedOwnership = await controller.ownsFullWork()
        XCTAssertTrue(retainedOwnership)
    }

    func testListenerPersistsVerifiedRefundAndFinishesTransaction() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try snapshotStore(at: directory)
        try store.save(EntitlementSnapshot.fromVerified(activeTransaction(id: 101), evaluatedAt: instant))
        let provider = FakeCommerceProvider()
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: store,
            now: { Date(timeIntervalSince1970: 2_000_000_120) }
        )
        await controller.startTransactionListener()

        await provider.emit(.verified(revokedTransaction(id: 101, type: .fullRefund)))
        await waitUntil { await provider.finishedTransactionIDs().contains(101) }

        let snapshot = await controller.currentSnapshot()
        XCTAssertEqual(snapshot.state, .revoked)
        XCTAssertEqual(snapshot.revocationType, .fullRefund)
        let ownsAfterRefund = await controller.ownsFullWork()
        XCTAssertFalse(ownsAfterRefund)
        XCTAssertEqual(try store.load(), snapshot)
        await controller.stopTransactionListener()
        await provider.finishUpdates()
    }

    func testListenerIgnoresUnverifiedUpdateAndDoesNotFinishIt() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try snapshotStore(at: directory)
        let cached = EntitlementSnapshot.fromVerified(activeTransaction(id: 111), evaluatedAt: instant)
        try store.save(cached)
        let provider = FakeCommerceProvider()
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: store,
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )
        await controller.startTransactionListener()

        await provider.emit(.unverified(productID: LaunchContent.fullWorkStoreProductID))
        await waitUntil { await controller.lastListenerFailure() != nil }

        let snapshotAfterUnverified = await controller.currentSnapshot()
        let ownsAfterUnverified = await controller.ownsFullWork()
        let finished = await provider.finishedTransactionIDs()
        let listenerFailure = await controller.lastListenerFailure()
        XCTAssertEqual(snapshotAfterUnverified, cached)
        XCTAssertTrue(ownsAfterUnverified)
        XCTAssertEqual(finished, [])
        XCTAssertEqual(listenerFailure, .unverifiedTargetTransaction)
        await controller.stopTransactionListener()
        await provider.finishUpdates()
    }

    func testListenerDoesNotFinishWhenDurableRevocationWriteFails() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try snapshotStore(at: directory)
        let cached = EntitlementSnapshot.fromVerified(activeTransaction(id: 115), evaluatedAt: instant)
        try store.save(cached)
        let provider = FakeCommerceProvider()
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: store,
            now: { Date(timeIntervalSince1970: 2_000_000_120) }
        )

        try Data("damaged".utf8).write(
            to: directory.appendingPathComponent("entitlement-snapshot-a.json"),
            options: .atomic
        )
        await controller.startTransactionListener()
        await provider.emit(.verified(revokedTransaction(id: 115, type: .fullRefund)))
        await waitUntil { await controller.lastListenerFailure() == .persistenceFailure }

        let inMemorySnapshot = await controller.currentSnapshot()
        let finished = await provider.finishedTransactionIDs()
        XCTAssertEqual(inMemorySnapshot.state, .revoked)
        XCTAssertFalse(inMemorySnapshot.grantsAccess(at: instant.addingTimeInterval(120)))
        XCTAssertEqual(finished, [])
        await controller.stopTransactionListener()
        await provider.finishUpdates()
    }

    func testPartialDenialSealRevokesInMemoryAndRemainsUnfinishedForRedelivery() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = FailOnWriteNumberWriter(failingWriteNumber: 3)
        let store = try EntitlementSnapshotStore(
            directoryURL: directory,
            keyProvider: FixedIntegrityKeyProvider(byte: 0x42),
            writer: writer
        )
        let owned = EntitlementSnapshot.fromVerified(activeTransaction(id: 117), evaluatedAt: instant)
        try store.save(owned)
        let provider = FakeCommerceProvider()
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: store,
            now: { Date(timeIntervalSince1970: 2_000_000_120) }
        )
        await controller.startTransactionListener()

        await provider.emit(.verified(revokedTransaction(id: 117, type: .fullRefund)))
        await waitUntil { await controller.lastListenerFailure() == .persistenceFailure }

        let inMemorySnapshot = await controller.currentSnapshot()
        let finished = await provider.finishedTransactionIDs()
        XCTAssertEqual(inMemorySnapshot.state, .revoked)
        XCTAssertFalse(inMemorySnapshot.grantsAccess(at: instant.addingTimeInterval(120)))
        XCTAssertEqual(finished, [])

        let normalStore = try snapshotStore(at: directory)
        XCTAssertEqual(try normalStore.load()?.state, .revoked)
        await controller.stopTransactionListener()
        await provider.finishUpdates()
    }

    func testExpirationFailsClosedOfflineAndIsRecordedOnRefresh() async throws {
        let expiration = instant.addingTimeInterval(30)
        let transaction = CommerceTransaction(
            id: 120,
            originalID: 120,
            productID: LaunchContent.fullWorkStoreProductID,
            purchaseDate: instant.addingTimeInterval(-60),
            expirationDate: expiration
        )
        let owned = EntitlementSnapshot.fromVerified(transaction, evaluatedAt: instant)
        let paidID = try XCTUnwrap(
            LaunchContent.chapterOrder.first { !LaunchContent.freeChapterIDs.contains($0) }
        )
        XCTAssertEqual(
            ChapterAccessResolver().access(
                to: paidID,
                snapshot: owned,
                at: expiration.addingTimeInterval(1)
            ),
            .locked(entitlementID: LaunchContent.fullWorkEntitlementID)
        )

        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeCommerceProvider()
        await provider.setCurrentEntitlements([.verified(transaction)])
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: snapshotStore(at: directory),
            now: { expiration.addingTimeInterval(1) }
        )
        guard case let .updated(snapshot) = await controller.refreshCurrentEntitlements() else {
            return XCTFail("Expected expired transaction to be recorded")
        }
        XCTAssertEqual(snapshot.state, .expired)
        let ownsAfterExpiration = await controller.ownsFullWork()
        XCTAssertFalse(ownsAfterExpiration)
    }

    func testStaleActiveUpdateCannotUndoDurableRevocation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try snapshotStore(at: directory)
        let revoked = EntitlementSnapshot.fromVerified(
            revokedTransaction(id: 131, type: .familyRevocation),
            evaluatedAt: instant
        )
        try store.save(revoked)
        let provider = FakeCommerceProvider()
        await provider.setCurrentEntitlements([.verified(activeTransaction(id: 131))])
        let controller = try EntitlementController(
            provider: provider,
            snapshotStore: store,
            now: { Date(timeIntervalSince1970: 2_000_000_100) }
        )

        let refresh = await controller.refreshCurrentEntitlements()
        let ownsAfterStaleUpdate = await controller.ownsFullWork()
        XCTAssertEqual(refresh, .updated(revoked))
        XCTAssertFalse(ownsAfterStaleUpdate)
        XCTAssertEqual(try store.load(), revoked)
    }

    private func activeTransaction(id: UInt64 = 42) -> CommerceTransaction {
        CommerceTransaction(
            id: id,
            originalID: id,
            productID: LaunchContent.fullWorkStoreProductID,
            purchaseDate: instant.addingTimeInterval(-60)
        )
    }

    private func revokedTransaction(
        id: UInt64,
        type: CommerceRevocationType
    ) -> CommerceTransaction {
        CommerceTransaction(
            id: id,
            originalID: id,
            productID: LaunchContent.fullWorkStoreProductID,
            purchaseDate: instant.addingTimeInterval(-60),
            revocationDate: instant.addingTimeInterval(30),
            revocationReason: .other,
            revocationType: type
        )
    }

    private func snapshotStore(at directory: URL) throws -> EntitlementSnapshotStore {
        try EntitlementSnapshotStore(
            directoryURL: directory,
            keyProvider: FixedIntegrityKeyProvider(byte: 0x42)
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("commerce-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0 ..< 200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for asynchronous transaction update")
    }
}

private struct FixedIntegrityKeyProvider: EntitlementIntegrityKeyProviding {
    let byte: UInt8

    func loadOrCreateKey() throws -> Data {
        Data(repeating: byte, count: 32)
    }
}

private enum FakeStoreError: Error {
    case unavailable
}

private final class FailOnWriteNumberWriter: EntitlementSnapshotAtomicWriting, @unchecked Sendable {
    private let lock = NSLock()
    private let failingWriteNumber: Int
    private var writeCount = 0

    init(failingWriteNumber: Int) {
        self.failingWriteNumber = failingWriteNumber
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        let shouldFail = lock.withLock { () -> Bool in
            writeCount += 1
            return writeCount == failingWriteNumber
        }
        if shouldFail { throw FakeStoreError.unavailable }
        try data.write(to: url, options: .atomic)
    }
}

private actor FakeCommerceProvider: CommerceStoreProviding {
    private var configuredProduct: CommerceProduct? = CommerceProduct(
        id: LaunchContent.fullWorkStoreProductID,
        kind: .nonConsumable
    )
    private var configuredPurchaseResult: StorePurchaseResult = .pending
    private var configuredCurrentEntitlements: [StoreTransactionVerification] = []
    private var currentEntitlementsShouldThrow = false
    private var syncShouldThrow = false
    private var syncCount = 0
    private var finishedIDs: [UInt64] = []
    private let updates: AsyncStream<StoreTransactionVerification>
    private let updatesContinuation: AsyncStream<StoreTransactionVerification>.Continuation

    init() {
        let pair = AsyncStream<StoreTransactionVerification>.makeStream()
        updates = pair.stream
        updatesContinuation = pair.continuation
    }

    func product(for productID: String) async throws -> CommerceProduct? {
        configuredProduct
    }

    func purchase(productID: String) async throws -> StorePurchaseResult {
        configuredPurchaseResult
    }

    func currentEntitlements(
        productID: String
    ) async throws -> [StoreTransactionVerification] {
        if currentEntitlementsShouldThrow { throw FakeStoreError.unavailable }
        return configuredCurrentEntitlements
    }

    func sync() async throws {
        syncCount += 1
        if syncShouldThrow { throw FakeStoreError.unavailable }
    }

    func transactionUpdates() async -> AsyncStream<StoreTransactionVerification> {
        updates
    }

    func finish(transactionID: UInt64) async {
        finishedIDs.append(transactionID)
    }

    func setProduct(_ product: CommerceProduct?) {
        configuredProduct = product
    }

    func setPurchaseResult(_ result: StorePurchaseResult) {
        configuredPurchaseResult = result
    }

    func setCurrentEntitlements(_ results: [StoreTransactionVerification]) {
        configuredCurrentEntitlements = results
    }

    func setCurrentEntitlementsError(_ value: Bool) {
        currentEntitlementsShouldThrow = value
    }

    func setSyncError(_ value: Bool) {
        syncShouldThrow = value
    }

    func emit(_ verification: StoreTransactionVerification) {
        updatesContinuation.yield(verification)
    }

    func finishUpdates() {
        updatesContinuation.finish()
    }

    func finishedTransactionIDs() -> [UInt64] {
        finishedIDs
    }

    func syncInvocationCount() -> Int {
        syncCount
    }
}
