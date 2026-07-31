import Foundation

/// Process-local ownership for chapter inputs that have crossed runtime
/// admission but have not yet completed their causal follow-up.
///
/// Tokens are scoped to the concrete gate as well as its monotonically
/// increasing generation. Replacing a gate therefore invalidates every token
/// issued by its predecessor, even when both gates begin at generation one.
public struct ChapterRuntimeInputReservationGate: Sendable {
    public struct Token: Hashable, Sendable {
        fileprivate let gateID: UUID
        fileprivate let generation: UInt64
    }

    private let gateID: UUID
    private var generation: UInt64
    private var activeGenerations: Set<UInt64> = []

    public init() {
        gateID = UUID()
        generation = 0
    }

    init(gateID: UUID = UUID(), generation: UInt64) {
        self.gateID = gateID
        self.generation = generation
    }

    public var activeCount: Int {
        activeGenerations.count
    }

    public var hasActiveReservations: Bool {
        !activeGenerations.isEmpty
    }

    public func activeCount(excluding token: Token?) -> Int {
        guard let token, owns(token) else { return activeGenerations.count }
        return activeGenerations.count - 1
    }

    /// Returns nil without changing state once the monotonic generation space
    /// is exhausted. Existing reservations retain their ownership.
    public mutating func reserve() -> Token? {
        guard generation < UInt64.max else { return nil }
        generation += 1
        guard activeGenerations.insert(generation).inserted else {
            return nil
        }
        return Token(gateID: gateID, generation: generation)
    }

    public func owns(_ token: Token) -> Bool {
        token.gateID == gateID
            && activeGenerations.contains(token.generation)
    }

    /// Finishing a stale, foreign or already-finished token is a no-op.
    @discardableResult
    public mutating func finish(_ token: Token) -> Bool {
        guard token.gateID == gateID else { return false }
        return activeGenerations.remove(token.generation) != nil
    }
}
