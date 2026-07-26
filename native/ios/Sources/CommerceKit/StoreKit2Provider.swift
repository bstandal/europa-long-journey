#if os(iOS) && canImport(StoreKit)
import Foundation
import StoreKit

/// Production StoreKit 2 boundary. StoreKit verification results remain
/// explicit across the protocol so no unsafe payload can be mistaken for an
/// entitlement by the domain controller.
@available(iOS 26.0, *)
public actor StoreKit2Provider: CommerceStoreProviding {
    private var productsByID: [String: Product] = [:]
    private var transactionsAwaitingFinish: [UInt64: Transaction] = [:]

    public init() {}

    public func product(for productID: String) async throws -> CommerceProduct? {
        let products = try await Product.products(for: [productID])
        guard let product = products.first(where: { $0.id == productID }) else { return nil }
        productsByID[productID] = product
        return CommerceProduct(
            id: product.id,
            kind: Self.map(product.type),
            displayPrice: product.displayPrice
        )
    }

    public func purchase(productID: String) async throws -> StorePurchaseResult {
        let product: Product
        if let cached = productsByID[productID] {
            product = cached
        } else {
            guard let loaded = try await Product.products(for: [productID])
                .first(where: { $0.id == productID }) else {
                throw CommerceFailure.productUnavailable
            }
            productsByID[productID] = loaded
            product = loaded
        }
        guard product.type == .nonConsumable else {
            throw CommerceFailure.productIsNotNonConsumable
        }

        switch try await product.purchase() {
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        case let .success(result):
            return .success(map(result, retainForFinish: true))
        @unknown default:
            return .cancelled
        }
    }

    public func currentEntitlements(
        productID: String
    ) async throws -> [StoreTransactionVerification] {
        var results: [StoreTransactionVerification] = []
        for await result in Transaction.currentEntitlements(for: productID) {
            results.append(map(result, retainForFinish: false))
        }
        return results
    }

    public func sync() async throws {
        try await AppStore.sync()
    }

    public func transactionUpdates() async -> AsyncStream<StoreTransactionVerification> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { break }
                    guard let self else { break }
                    continuation.yield(await self.map(result, retainForFinish: true))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func finish(transactionID: UInt64) async {
        guard let transaction = transactionsAwaitingFinish.removeValue(forKey: transactionID) else {
            return
        }
        await transaction.finish()
    }

    private func map(
        _ result: VerificationResult<Transaction>,
        retainForFinish: Bool
    ) -> StoreTransactionVerification {
        switch result {
        case let .unverified(transaction, _):
            return .unverified(productID: transaction.productID)
        case let .verified(transaction):
            if retainForFinish {
                transactionsAwaitingFinish[transaction.id] = transaction
            }
            return .verified(Self.map(transaction))
        }
    }

    private static func map(_ type: Product.ProductType) -> CommerceProductKind {
        switch type {
        case .consumable:
            .consumable
        case .nonConsumable:
            .nonConsumable
        case .autoRenewable:
            .autoRenewableSubscription
        case .nonRenewable:
            .nonRenewingSubscription
        default:
            .unknown
        }
    }

    private static func map(_ transaction: Transaction) -> CommerceTransaction {
        CommerceTransaction(
            id: transaction.id,
            originalID: transaction.originalID,
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            revocationReason: map(transaction.revocationReason),
            revocationType: mapRevocationType(transaction)
        )
    }

    private static func map(
        _ reason: Transaction.RevocationReason?
    ) -> CommerceRevocationReason? {
        guard let reason else { return nil }
        if reason == .developerIssue { return .developerIssue }
        if reason == .other { return .other }
        return .unknown
    }

    private static func mapRevocationType(
        _ transaction: Transaction
    ) -> CommerceRevocationType? {
        guard transaction.revocationDate != nil else { return nil }
        if #available(iOS 26.4, *) {
            guard let type = transaction.revocationType else { return nil }
            if type == .familyRevocation { return .familyRevocation }
            if type == .fullRefund { return .fullRefund }
            if type == .proratedRefund { return .proratedRefund }
            return .unknown
        }
        return nil
    }
}
#endif
