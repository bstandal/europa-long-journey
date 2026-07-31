import ContentKit
import Foundation

public actor EntitlementController {
    public nonisolated static let productID = LaunchContent.fullWorkStoreProductID

    private let provider: any CommerceStoreProviding
    private let snapshotStore: EntitlementSnapshotStore
    private let now: @Sendable () -> Date
    private var snapshot: EntitlementSnapshot
    private var listenerTask: Task<Void, Never>?
    private var listenerFailure: EntitlementRefreshFailure?
    private var snapshotUpdateContinuation: AsyncStream<EntitlementSnapshot>.Continuation?

    public init(
        provider: any CommerceStoreProviding,
        snapshotStore: EntitlementSnapshotStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        self.provider = provider
        self.snapshotStore = snapshotStore
        self.now = now
        snapshot = try snapshotStore.load() ?? .notPurchased(at: now())
    }

    public func currentSnapshot() -> EntitlementSnapshot {
        snapshot
    }

    /// A single app-shell observer receives the current durable value first
    /// and every later verified transition. Replacing the observer terminates
    /// the older stream so stale shells cannot keep presenting access state.
    public func snapshotUpdates() -> AsyncStream<EntitlementSnapshot> {
        snapshotUpdateContinuation?.finish()
        let pair = AsyncStream<EntitlementSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        snapshotUpdateContinuation = pair.continuation
        pair.continuation.yield(snapshot)
        return pair.stream
    }

    public func ownsFullWork() -> Bool {
        snapshot.grantsAccess(at: now())
    }

    public func lastListenerFailure() -> EntitlementRefreshFailure? {
        listenerFailure
    }

    public func productDetails() async throws -> CommerceProduct {
        guard let product = try await provider.product(for: Self.productID) else {
            throw CommerceFailure.productUnavailable
        }
        guard product.id == Self.productID else {
            throw CommerceFailure.productIdentifierMismatch
        }
        guard product.kind == .nonConsumable else {
            throw CommerceFailure.productIsNotNonConsumable
        }
        return product
    }

    public func purchase() async throws -> EntitlementPurchaseOutcome {
        _ = try await productDetails()

        switch try await provider.purchase(productID: Self.productID) {
        case .pending:
            return .pending
        case .cancelled:
            return .cancelled
        case let .success(verification):
            switch verification {
            case .unverified:
                throw CommerceFailure.unverifiedTransaction
            case let .verified(transaction):
                guard transaction.productID == Self.productID else {
                    throw CommerceFailure.productIdentifierMismatch
                }
                let effective = try applyVerifiedTransaction(transaction, evaluatedAt: now())
                await provider.finish(transactionID: transaction.id)
                guard effective.grantsAccess(at: now()) else {
                    throw CommerceFailure.inactivePurchase
                }
                return .success(effective)
            }
        }
    }

    /// Refreshes from StoreKit's complete current-entitlement view. A provider
    /// failure or an unverified target result is indeterminate and therefore
    /// retains a previously authenticated ownership snapshot. A successful,
    /// verified empty result is authoritative and records no current purchase.
    public func refreshCurrentEntitlements() async -> EntitlementRefreshOutcome {
        let verifications: [StoreTransactionVerification]
        do {
            verifications = try await provider.currentEntitlements(productID: Self.productID)
        } catch {
            return .retainedCached(snapshot, reason: .storeUnavailable)
        }

        let targetResults = verifications.filter { verification in
            switch verification {
            case let .verified(transaction):
                transaction.productID == Self.productID
            case let .unverified(productID):
                productID == Self.productID
            }
        }
        let verified = targetResults.compactMap { verification -> CommerceTransaction? in
            guard case let .verified(transaction) = verification else { return nil }
            return transaction
        }

        if let transaction = verified.max(by: Self.transactionHasLowerPrecedence) {
            do {
                let effective = try applyVerifiedTransaction(transaction, evaluatedAt: now())
                return .updated(effective)
            } catch {
                return .retainedCached(snapshot, reason: .persistenceFailure)
            }
        }

        if targetResults.contains(where: {
            if case .unverified = $0 { return true }
            return false
        }) {
            return .retainedCached(snapshot, reason: .unverifiedTargetTransaction)
        }

        let candidate = EntitlementSnapshot.notPurchased(at: now())
        do {
            try persist(candidate)
            return .updated(candidate)
        } catch {
            return .retainedCached(snapshot, reason: .persistenceFailure)
        }
    }

    /// AppStore.sync() is the explicit user-initiated restore edge. Failure to
    /// reach the store leaves authenticated offline ownership untouched.
    public func restorePurchases() async -> EntitlementRefreshOutcome {
        do {
            try await provider.sync()
        } catch {
            return .retainedCached(snapshot, reason: .storeUnavailable)
        }
        return await refreshCurrentEntitlements()
    }

    public func startTransactionListener() {
        guard listenerTask == nil else { return }
        let provider = provider
        listenerTask = Task { [weak self] in
            let updates = await provider.transactionUpdates()
            for await verification in updates {
                guard !Task.isCancelled else { break }
                await self?.consumeListenerUpdate(verification)
            }
        }
    }

    public func stopTransactionListener() {
        listenerTask?.cancel()
        listenerTask = nil
    }

    private func consumeListenerUpdate(_ verification: StoreTransactionVerification) async {
        switch verification {
        case let .unverified(productID):
            if productID == Self.productID {
                listenerFailure = .unverifiedTargetTransaction
            }
        case let .verified(transaction):
            guard transaction.productID == Self.productID else { return }
            do {
                _ = try applyVerifiedTransaction(transaction, evaluatedAt: now())
                listenerFailure = nil
                await provider.finish(transactionID: transaction.id)
            } catch {
                // Do not finish a transaction whose durable state failed. It
                // remains available for StoreKit to redeliver after recovery.
                listenerFailure = .persistenceFailure
            }
        }
    }

    @discardableResult
    private func applyVerifiedTransaction(
        _ transaction: CommerceTransaction,
        evaluatedAt date: Date
    ) throws -> EntitlementSnapshot {
        guard transaction.productID == Self.productID else {
            throw CommerceFailure.productIdentifierMismatch
        }
        let candidate = EntitlementSnapshot.fromVerified(transaction, evaluatedAt: date)
        guard Self.shouldApply(candidate, over: snapshot) else { return snapshot }
        try persist(candidate)
        return candidate
    }

    private func persist(_ candidate: EntitlementSnapshot) throws {
        // Ownership becomes visible only after the authenticated atomic write.
        // A verified denial is asymmetric: even an I/O failure must deny in
        // this process, while the unfinished StoreKit transaction remains
        // available to repair durable storage through redelivery.
        do {
            try snapshotStore.save(candidate)
            snapshot = candidate
            snapshotUpdateContinuation?.yield(candidate)
        } catch {
            if candidate.state != .owned {
                snapshot = candidate
                snapshotUpdateContinuation?.yield(candidate)
            }
            throw error
        }
    }

    private static func shouldApply(
        _ candidate: EntitlementSnapshot,
        over current: EntitlementSnapshot
    ) -> Bool {
        guard let candidateID = candidate.transactionID else { return true }
        guard let currentID = current.transactionID else { return true }
        if candidateID != currentID { return candidateID > currentID }

        // A stale active representation of the same transaction must never
        // undo a verified refund, revocation or expiry already made durable.
        if current.state == .revoked || current.state == .expired {
            return candidate.state != .owned
        }
        if candidate.state == .revoked || candidate.state == .expired {
            return true
        }
        return candidate.lastValidatedAt >= current.lastValidatedAt
    }

    private static func transactionHasLowerPrecedence(
        _ lhs: CommerceTransaction,
        _ rhs: CommerceTransaction
    ) -> Bool {
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        if (lhs.revocationDate != nil) != (rhs.revocationDate != nil) {
            return lhs.revocationDate == nil
        }
        return (lhs.revocationDate ?? lhs.expirationDate ?? lhs.purchaseDate)
            < (rhs.revocationDate ?? rhs.expirationDate ?? rhs.purchaseDate)
    }
}
