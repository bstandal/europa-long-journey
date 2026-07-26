public struct JourneyPersistenceMutationToken: Hashable, Sendable {
    fileprivate let generation: UInt64
}

/// Main-actor-owned admission state shared by every path which can append or
/// checkpoint Journey progress. Package-authority restoration may start only
/// when no token remains active; locking admission first prevents a new writer
/// from entering after that decision.
public struct JourneyPersistenceMutationBarrier: Sendable {
    public private(set) var generation: UInt64 = 0
    private var activeGenerations: Set<UInt64> = []

    public init() {}

    public var hasActiveMutations: Bool {
        !activeGenerations.isEmpty
    }

    public var activeMutationCount: Int {
        activeGenerations.count
    }

    public mutating func begin() -> JourneyPersistenceMutationToken? {
        guard generation < UInt64.max else { return nil }
        generation += 1
        activeGenerations.insert(generation)
        return JourneyPersistenceMutationToken(generation: generation)
    }

    /// Admits a write owned by restoration itself after a prepared authority
    /// has been accepted. Ordinary app writes remain excluded by the
    /// persistence lock; this narrower path is valid only while that lock and
    /// the authority-restore operation are both active.
    public mutating func beginRestoreInternal(
        authorityRestoreIsInFlight: Bool,
        persistenceIsLocked: Bool
    ) -> JourneyPersistenceMutationToken? {
        guard authorityRestoreIsInFlight,
              persistenceIsLocked,
              activeGenerations.isEmpty else {
            return nil
        }
        return begin()
    }

    @discardableResult
    public mutating func finish(
        _ token: JourneyPersistenceMutationToken
    ) -> Bool {
        activeGenerations.remove(token.generation) != nil
    }
}

/// Starting a package-authority restoration is legal only after transition
/// preparation has locked ordinary persistence and entered restoration. The
/// same gate is used by the direct transition path and by the last writer
/// leaving a transition that was already waiting on the mutation barrier.
public enum JourneyAuthorityTransitionStartAdmissionPolicy {
    public static func admits(
        persistenceIsLocked: Bool,
        restorationIsInFlight: Bool,
        authorityPreparationIsInFlight: Bool,
        authorityTransitionIsInFlight: Bool,
        authorityRestoreIsInFlight: Bool,
        persistenceMutationIsInFlight: Bool
    ) -> Bool {
        persistenceIsLocked
            && restorationIsInFlight
            && !authorityPreparationIsInFlight
            && !authorityTransitionIsInFlight
            && !authorityRestoreIsInFlight
            && !persistenceMutationIsInFlight
    }
}

public enum VerifiedSnapshotRevisionPolicy {
    public static func admits(
        candidate: UInt64,
        after current: UInt64?
    ) -> Bool {
        guard let current else { return true }
        return candidate > current
    }
}
