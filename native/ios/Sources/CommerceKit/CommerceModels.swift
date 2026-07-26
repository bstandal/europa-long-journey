import ContentKit
import Foundation

public enum CommerceProductKind: String, Codable, Equatable, Sendable {
    case consumable
    case nonConsumable
    case autoRenewableSubscription
    case nonRenewingSubscription
    case unknown
}

public struct CommerceProduct: Equatable, Sendable {
    public let id: String
    public let kind: CommerceProductKind
    public let displayPrice: String?

    public init(
        id: String,
        kind: CommerceProductKind,
        displayPrice: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayPrice = displayPrice
    }
}

public enum CommerceRevocationReason: String, Codable, Equatable, Sendable {
    case developerIssue
    case other
    case unknown
}

/// StoreKit 2 can distinguish refunds from a family-sharing revocation on
/// recent systems. Older launch-floor releases still preserve the verified
/// revocation date and reason even when this more precise value is absent.
public enum CommerceRevocationType: String, Codable, Equatable, Sendable {
    case familyRevocation
    case fullRefund
    case proratedRefund
    case unknown
}

public struct CommerceTransaction: Equatable, Sendable {
    public let id: UInt64
    public let originalID: UInt64
    public let productID: String
    public let purchaseDate: Date
    public let expirationDate: Date?
    public let revocationDate: Date?
    public let revocationReason: CommerceRevocationReason?
    public let revocationType: CommerceRevocationType?

    public init(
        id: UInt64,
        originalID: UInt64,
        productID: String,
        purchaseDate: Date,
        expirationDate: Date? = nil,
        revocationDate: Date? = nil,
        revocationReason: CommerceRevocationReason? = nil,
        revocationType: CommerceRevocationType? = nil
    ) {
        self.id = id
        self.originalID = originalID
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.revocationReason = revocationReason
        self.revocationType = revocationType
    }

    public func isActive(at date: Date) -> Bool {
        guard revocationDate == nil else { return false }
        guard let expirationDate else { return true }
        return expirationDate > date
    }
}

/// Only `.verified` may ever be converted into durable ownership. The product
/// identifier attached to `.unverified` is routing information from the
/// unsafe StoreKit payload and can never grant or revoke access.
public enum StoreTransactionVerification: Equatable, Sendable {
    case verified(CommerceTransaction)
    case unverified(productID: String)
}

public enum StorePurchaseResult: Equatable, Sendable {
    case success(StoreTransactionVerification)
    case pending
    case cancelled
}

public protocol CommerceStoreProviding: Sendable {
    func product(for productID: String) async throws -> CommerceProduct?
    func purchase(productID: String) async throws -> StorePurchaseResult
    func currentEntitlements(productID: String) async throws -> [StoreTransactionVerification]
    func sync() async throws
    func transactionUpdates() async -> AsyncStream<StoreTransactionVerification>
    func finish(transactionID: UInt64) async
}

public enum CommerceFailure: Error, Equatable, Sendable {
    case productUnavailable
    case productIdentifierMismatch
    case productIsNotNonConsumable
    case unverifiedTransaction
    case inactivePurchase
}

public enum EntitlementPurchaseOutcome: Equatable, Sendable {
    case success(EntitlementSnapshot)
    case pending
    case cancelled
}

public enum EntitlementRefreshFailure: Equatable, Sendable {
    case storeUnavailable
    case unverifiedTargetTransaction
    case persistenceFailure
}

public enum EntitlementRefreshOutcome: Equatable, Sendable {
    case updated(EntitlementSnapshot)
    case retainedCached(EntitlementSnapshot, reason: EntitlementRefreshFailure)
}

public enum EntitlementState: String, Codable, Equatable, Sendable {
    case notPurchased
    case owned
    case revoked
    case expired
}

public struct EntitlementSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let productID: String
    public let state: EntitlementState
    public let transactionID: UInt64?
    public let originalTransactionID: UInt64?
    public let purchaseDate: Date?
    public let expirationDate: Date?
    public let revocationDate: Date?
    public let revocationReason: CommerceRevocationReason?
    public let revocationType: CommerceRevocationType?
    public let lastValidatedAt: Date

    public init(
        formatVersion: Int = currentFormatVersion,
        productID: String,
        state: EntitlementState,
        transactionID: UInt64? = nil,
        originalTransactionID: UInt64? = nil,
        purchaseDate: Date? = nil,
        expirationDate: Date? = nil,
        revocationDate: Date? = nil,
        revocationReason: CommerceRevocationReason? = nil,
        revocationType: CommerceRevocationType? = nil,
        lastValidatedAt: Date
    ) {
        self.formatVersion = formatVersion
        self.productID = productID
        self.state = state
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.revocationReason = revocationReason
        self.revocationType = revocationType
        self.lastValidatedAt = lastValidatedAt
    }

    public static func notPurchased(at date: Date) -> EntitlementSnapshot {
        EntitlementSnapshot(
            productID: LaunchContent.fullWorkStoreProductID,
            state: .notPurchased,
            lastValidatedAt: date
        )
    }

    public static func fromVerified(
        _ transaction: CommerceTransaction,
        evaluatedAt date: Date
    ) -> EntitlementSnapshot {
        let state: EntitlementState
        if transaction.revocationDate != nil {
            state = .revoked
        } else if let expirationDate = transaction.expirationDate, expirationDate <= date {
            state = .expired
        } else {
            state = .owned
        }
        return EntitlementSnapshot(
            productID: transaction.productID,
            state: state,
            transactionID: transaction.id,
            originalTransactionID: transaction.originalID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            revocationReason: transaction.revocationReason,
            revocationType: transaction.revocationType,
            lastValidatedAt: date
        )
    }

    public func grantsAccess(at date: Date) -> Bool {
        guard productID == LaunchContent.fullWorkStoreProductID,
              state == .owned,
              revocationDate == nil else {
            return false
        }
        guard let expirationDate else { return true }
        return expirationDate > date
    }
}
