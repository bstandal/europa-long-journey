import ProgressStore

/// A restoration whose migration write has not yet been accepted by the
/// package-snapshot coordinator. If the exact authority changes while the
/// restore is suspended, the same authority-bound store can put the prior
/// save pair back before its package generation is withdrawn.
public struct PreparedSaveMigrationRestoration: Sendable {
    public let store: ProgressStore
    public let restoration: JourneyRestoration
    public let committedSaveMigration: Bool

    public func rollbackCommittedSaveMigrationIfNeeded() async throws {
        guard committedSaveMigration else { return }
        try await store.rollbackToLastKnownGoodSave()
    }
}

public enum SaveMigrationRestorationPreparer {
    public static func prepare(
        store: ProgressStore,
        restore: @Sendable () async throws -> JourneyRestoration
    ) async throws -> PreparedSaveMigrationRestoration {
        let restoration = try await restore()
        return PreparedSaveMigrationRestoration(
            store: store,
            restoration: restoration,
            committedSaveMigration: restoration.didCommitSaveMigration
        )
    }
}
