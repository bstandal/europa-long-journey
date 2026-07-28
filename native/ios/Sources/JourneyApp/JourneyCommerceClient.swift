import CommerceKit
import ContentKit
import Foundation

/// App-shell boundary around StoreKit-backed entitlement work. Product
/// readiness is explicit so the UI cannot offer an operation that the store
/// composition has not proved fulfillable.
struct JourneyCommerceClient: Sendable {
    let currentSnapshot: @Sendable () async -> EntitlementSnapshot
    let snapshotUpdates: @Sendable () async -> AsyncStream<EntitlementSnapshot>
    let startTransactionListener: @Sendable () async -> Void
    let productDetails: @Sendable () async throws -> CommerceProduct
    let refreshCurrentEntitlements: @Sendable () async -> EntitlementRefreshOutcome
    let purchase: @Sendable () async throws -> EntitlementPurchaseOutcome
    let restorePurchases: @Sendable () async -> EntitlementRefreshOutcome

    init(controller: EntitlementController) {
        currentSnapshot = { await controller.currentSnapshot() }
        snapshotUpdates = { await controller.snapshotUpdates() }
        startTransactionListener = { await controller.startTransactionListener() }
        productDetails = { try await controller.productDetails() }
        refreshCurrentEntitlements = { await controller.refreshCurrentEntitlements() }
        purchase = { try await controller.purchase() }
        restorePurchases = { await controller.restorePurchases() }
    }
}

#if DEBUG
extension JourneyCommerceClient {
    static func developmentFixture(
        initiallyOwned: Bool,
        restoresOwnership: Bool = false
    ) -> JourneyCommerceClient {
        let fixture = DevelopmentJourneyCommerceFixture(
            initiallyOwned: initiallyOwned,
            restoresOwnership: restoresOwnership
        )
        return JourneyCommerceClient(
            currentSnapshot: { await fixture.currentSnapshot() },
            snapshotUpdates: { await fixture.snapshotUpdates() },
            startTransactionListener: {},
            productDetails: { await fixture.productDetails() },
            refreshCurrentEntitlements: { await fixture.refresh() },
            purchase: { await fixture.purchase() },
            restorePurchases: { await fixture.restore() }
        )
    }

    private init(
        currentSnapshot: @escaping @Sendable () async -> EntitlementSnapshot,
        snapshotUpdates: @escaping @Sendable () async -> AsyncStream<EntitlementSnapshot>,
        startTransactionListener: @escaping @Sendable () async -> Void,
        productDetails: @escaping @Sendable () async throws -> CommerceProduct,
        refreshCurrentEntitlements: @escaping @Sendable () async -> EntitlementRefreshOutcome,
        purchase: @escaping @Sendable () async throws -> EntitlementPurchaseOutcome,
        restorePurchases: @escaping @Sendable () async -> EntitlementRefreshOutcome
    ) {
        self.currentSnapshot = currentSnapshot
        self.snapshotUpdates = snapshotUpdates
        self.startTransactionListener = startTransactionListener
        self.productDetails = productDetails
        self.refreshCurrentEntitlements = refreshCurrentEntitlements
        self.purchase = purchase
        self.restorePurchases = restorePurchases
    }
}

private actor DevelopmentJourneyCommerceFixture {
    private var snapshot: EntitlementSnapshot
    private let restoresOwnership: Bool
    private var continuation: AsyncStream<EntitlementSnapshot>.Continuation?

    init(initiallyOwned: Bool, restoresOwnership: Bool) {
        self.restoresOwnership = restoresOwnership
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        snapshot = initiallyOwned
            ? EntitlementSnapshot(
                productID: LaunchContent.fullWorkStoreProductID,
                state: .owned,
                transactionID: 1,
                originalTransactionID: 1,
                purchaseDate: now,
                lastValidatedAt: now
            )
            : .notPurchased(at: now)
    }

    func currentSnapshot() -> EntitlementSnapshot { snapshot }

    func snapshotUpdates() -> AsyncStream<EntitlementSnapshot> {
        continuation?.finish()
        let pair = AsyncStream<EntitlementSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation = pair.continuation
        pair.continuation.yield(snapshot)
        return pair.stream
    }

    func productDetails() -> CommerceProduct {
        CommerceProduct(
            id: LaunchContent.fullWorkStoreProductID,
            kind: .nonConsumable,
            displayPrice: "$24.99"
        )
    }

    func refresh() -> EntitlementRefreshOutcome { .updated(snapshot) }

    func purchase() -> EntitlementPurchaseOutcome {
        let now = Date(timeIntervalSince1970: 1_700_000_001)
        snapshot = EntitlementSnapshot(
            productID: LaunchContent.fullWorkStoreProductID,
            state: .owned,
            transactionID: 2,
            originalTransactionID: 2,
            purchaseDate: now,
            lastValidatedAt: now
        )
        continuation?.yield(snapshot)
        return .success(snapshot)
    }

    func restore() -> EntitlementRefreshOutcome {
        if restoresOwnership {
            let now = Date(timeIntervalSince1970: 1_700_000_002)
            snapshot = EntitlementSnapshot(
                productID: LaunchContent.fullWorkStoreProductID,
                state: .owned,
                transactionID: 3,
                originalTransactionID: 3,
                purchaseDate: now,
                lastValidatedAt: now
            )
        }
        continuation?.yield(snapshot)
        return .updated(snapshot)
    }
}
#endif
