import Foundation

public enum PersistenceAuthorityFenceError: Error, Equatable, Sendable {
    case generationExhausted
}

/// Process-local authority for objects that may represent the same durable
/// content, route and beat while owning different persistence generations.
/// The receipt is intentionally opaque: consumers can retain and compare it,
/// but only this fence can prove that the same object still owns it.
@MainActor
public struct PersistenceAuthorityFence {
    public struct Receipt: Hashable, Sendable {
        fileprivate let modelID: UUID
        fileprivate let generation: UInt64
        fileprivate let authorityIdentifier: ObjectIdentifier
    }

    private let modelID: UUID
    private var generation: UInt64 = 0
    private var currentAuthorityIdentifier: ObjectIdentifier?

    public init(modelID: UUID = UUID()) {
        self.modelID = modelID
    }

    public private(set) var currentReceipt: Receipt?

    /// Rotates on every accepted persistence object, even when content and
    /// Journey state are byte-for-byte identical to the previous authority.
    @discardableResult
    public mutating func accept(
        _ authority: AnyObject
    ) throws -> Receipt {
        guard generation < UInt64.max else {
            throw PersistenceAuthorityFenceError.generationExhausted
        }
        generation += 1
        let identifier = ObjectIdentifier(authority)
        let receipt = Receipt(
            modelID: modelID,
            generation: generation,
            authorityIdentifier: identifier
        )
        currentAuthorityIdentifier = identifier
        currentReceipt = receipt
        return receipt
    }

    /// Requires the receipt, current generation and concrete object identity
    /// to agree. A restored replacement can never inherit authority merely by
    /// recreating the same local generation number.
    public func matches(
        _ receipt: Receipt,
        authority: AnyObject
    ) -> Bool {
        receipt == currentReceipt
            && receipt.modelID == modelID
            && receipt.generation == generation
            && receipt.authorityIdentifier == ObjectIdentifier(authority)
            && currentAuthorityIdentifier == ObjectIdentifier(authority)
    }
}
