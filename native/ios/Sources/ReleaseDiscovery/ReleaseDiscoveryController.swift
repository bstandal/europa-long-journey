import ContentKit
import Foundation

public protocol ReleaseCatalogRemoteProviding: Sendable {
    func ensureReleaseSubscription() async throws
    func fetchAvailableReleaseRecords() async throws -> [ReleaseRemoteRecord]
}

public struct ReleaseRemoteNotificationHint: Equatable, Sendable {
    public let subscriptionID: String
    public let recordName: String?

    public init(subscriptionID: String, recordName: String? = nil) {
        self.subscriptionID = subscriptionID
        self.recordName = recordName
    }
}

public enum ReleaseDiscoverySource: Equatable, Sendable {
    case empty
    case cache
    case remote
    case cacheAfterRemoteFailure
}

public enum ReleaseDiscoveryIssue: Equatable, Sendable {
    case remoteUnavailable
    case invalidRemoteCatalog
    case cacheCorrupt
    case cachePersistenceFailed
    case cacheAndRemoteUnavailable
    case cacheRecovered
}

public struct ReleaseDiscoveryResult: Equatable, Sendable {
    public let availableEntries: [ReleaseCatalogEntry]
    public let unsupportedRuntimeEntries: [ReleaseCatalogEntry]
    public let notificationIntents: [ReleaseNotificationIntent]
    public let source: ReleaseDiscoverySource
    public let issue: ReleaseDiscoveryIssue?

    public init(
        availableEntries: [ReleaseCatalogEntry],
        unsupportedRuntimeEntries: [ReleaseCatalogEntry],
        notificationIntents: [ReleaseNotificationIntent] = [],
        source: ReleaseDiscoverySource,
        issue: ReleaseDiscoveryIssue? = nil
    ) {
        self.availableEntries = availableEntries
        self.unsupportedRuntimeEntries = unsupportedRuntimeEntries
        self.notificationIntents = notificationIntents
        self.source = source
        self.issue = issue
    }
}

public enum ReleaseSubscriptionResult: Equatable, Sendable {
    case ready
    case unavailable
}

public enum ReleasePushHandlingResult: Equatable, Sendable {
    case ignored
    case refreshed(ReleaseDiscoveryResult)
}

public actor ReleaseDiscoveryController {
    private let remote: any ReleaseCatalogRemoteProviding
    private let cacheStore: ReleaseCatalogCacheStore
    private let installationContractStore: ReleaseInstallationContractStore?
    private let runtimeVersion: SchemaVersion
    private let now: @Sendable () -> Date

    private var didLoadCache = false
    private var cacheWasCorrupt = false
    private var snapshot = ReleaseCatalogCacheSnapshot.empty

    public init(
        remote: any ReleaseCatalogRemoteProviding,
        cacheStore: ReleaseCatalogCacheStore,
        installationContractStore: ReleaseInstallationContractStore? = nil,
        runtimeVersion: SchemaVersion,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.remote = remote
        self.cacheStore = cacheStore
        self.installationContractStore = installationContractStore
        self.runtimeVersion = runtimeVersion
        self.now = now
    }

    public func prepareRemoteNotifications() async -> ReleaseSubscriptionResult {
        do {
            try await remote.ensureReleaseSubscription()
            return .ready
        } catch {
            // Subscription failure never invalidates the cached catalog.
            // Foreground refresh remains the fallback when CloudKit push is
            // unavailable or coalesced.
            return .unavailable
        }
    }

    public func cachedCatalog() -> ReleaseDiscoveryResult {
        loadCacheIfNeeded()
        let issue: ReleaseDiscoveryIssue? = cacheWasCorrupt ? .cacheCorrupt : nil
        return makeResult(
            from: snapshot,
            notifications: [],
            source: snapshot.entries.isEmpty ? .empty : .cache,
            issue: issue
        )
    }

    public func refresh() async -> ReleaseDiscoveryResult {
        loadCacheIfNeeded()
        let prior = snapshot
        let hadCorruptCache = cacheWasCorrupt

        let records: [ReleaseRemoteRecord]
        do {
            records = try await remote.fetchAvailableReleaseRecords()
        } catch {
            return makeResult(
                from: prior,
                notifications: [],
                source: prior.entries.isEmpty ? .empty : .cacheAfterRemoteFailure,
                issue: hadCorruptCache ? .cacheAndRemoteUnavailable : .remoteUnavailable
            )
        }

        let remoteEntries: [ReleaseCatalogEntry]
        do {
            remoteEntries = try records.map { try $0.decode() }
                .validatedCanonicalReleaseCatalog()
        } catch {
            return makeResult(
                from: prior,
                notifications: [],
                source: prior.entries.isEmpty ? .empty : .cacheAfterRemoteFailure,
                issue: hadCorruptCache ? .cacheAndRemoteUnavailable : .invalidRemoteCatalog
            )
        }

        var merged: [ReleaseCatalogEntry]
        do {
            merged = try Self.merge(prior.entries, with: remoteEntries)
            if let pendingID = prior.pendingDeepLinkReleaseID,
               !merged.contains(where: { $0.id == pendingID }),
               let pendingEntry = prior.entries.first(where: { $0.id == pendingID }) {
                merged.append(pendingEntry)
                merged = try merged.validatedCanonicalReleaseCatalog()
            }
        } catch {
            return makeResult(
                from: prior,
                notifications: [],
                source: prior.entries.isEmpty ? .empty : .cacheAfterRemoteFailure,
                issue: .invalidRemoteCatalog
            )
        }

        let refreshMillis = max(Int64(0), Int64(now().timeIntervalSince1970 * 1_000))
        var claimed = Set(prior.notificationClaimedReleaseIDs)
        var intents: [ReleaseNotificationIntent] = []
        let establishesBaseline = !prior.baselineEstablished || hadCorruptCache

        for entry in merged where isPublished(entry) && isRuntimeCompatible(entry) {
            if establishesBaseline {
                claimed.insert(entry.id)
            } else if claimed.insert(entry.id).inserted {
                intents.append(
                    ReleaseNotificationIntent(
                        deepLink: entry.deepLinkIntent,
                        announcement: entry.announcement
                    )
                )
            }
        }

        let candidate = ReleaseCatalogCacheSnapshot(
            entries: merged,
            notificationClaimedReleaseIDs: Array(claimed),
            pendingDeepLinkReleaseID: prior.pendingDeepLinkReleaseID,
            baselineEstablished: true,
            lastSuccessfulRefreshUnixMillis: refreshMillis
        )

        do {
            if hadCorruptCache {
                try cacheStore.rebuildAfterCorruption(candidate)
            } else {
                try cacheStore.save(candidate)
            }
            snapshot = candidate
            cacheWasCorrupt = false
            return makeResult(
                from: candidate,
                notifications: intents,
                source: .remote,
                issue: hadCorruptCache ? .cacheRecovered : nil
            )
        } catch {
            // Never emit an at-most-once notification claim that was not made
            // durable. Retain the last authenticated catalog instead.
            return makeResult(
                from: prior,
                notifications: [],
                source: prior.entries.isEmpty ? .empty : .cache,
                issue: .cachePersistenceFailed
            )
        }
    }

    public func handleRemoteNotification(
        _ hint: ReleaseRemoteNotificationHint
    ) async -> ReleasePushHandlingResult {
        guard hint.subscriptionID == ReleaseServiceContract.cloudSubscriptionID else {
            return .ignored
        }
        // The payload is only a change hint. Even when it contains a record
        // name, the trusted release and deep link always come from a fresh
        // catalog fetch or the authenticated cache.
        return .refreshed(await refresh())
    }

    public func deepLink(for releaseID: ReleaseID) -> ReleaseDeepLinkResolution {
        loadCacheIfNeeded()
        return resolveDeepLink(for: releaseID)
    }

    /// Returns the complete release contract only after resolving it from the
    /// authenticated catalog cache and reapplying publication/runtime gates.
    /// Package delivery must use this method rather than trusting the bounded
    /// notification/deep-link fields.
    public func packageContract(
        for releaseID: ReleaseID
    ) -> ReleasePackageContractResolution {
        loadCacheIfNeeded()
        return resolvePackageContract(for: releaseID)
    }

    /// Seals the exact authenticated catalog entry into an installation
    /// ledger before any Apple-hosted request may begin. The retained contract
    /// survives later catalog withdrawal and remains the only trusted source
    /// for cold-launch package verification.
    @discardableResult
    public func retainPackageContractForInstallation(
        _ releaseID: ReleaseID
    ) throws -> ReleasePackageContractResolution {
        loadCacheIfNeeded()
        let resolution = resolvePackageContract(for: releaseID)
        guard case let .ready(entry) = resolution else { return resolution }
        guard let installationContractStore else {
            throw ReleaseInstallationContractStoreError.unavailable
        }
        try installationContractStore.pin(entry)
        return resolution
    }

    /// Reads only the separately authenticated installation ledger. It never
    /// falls back to the live catalog because a withdrawn discovery record
    /// must not make already installed offline content unverifiable.
    public func retainedInstallationContract(
        for releaseID: ReleaseID
    ) throws -> ReleaseCatalogEntry? {
        guard let installationContractStore else {
            throw ReleaseInstallationContractStoreError.unavailable
        }
        return try installationContractStore.entry(for: releaseID)
    }

    public func retainedInstallationContracts() throws -> [ReleaseCatalogEntry] {
        guard let installationContractStore else {
            throw ReleaseInstallationContractStoreError.unavailable
        }
        return try installationContractStore.load().entries
    }

    /// Durably records only the authenticated release ID before exposing a
    /// notification tap to the app. A kill during Journey restoration can
    /// therefore recover the intent without storing an unverified route.
    public func beginDeepLink(
        for releaseID: ReleaseID
    ) -> ReleaseDeepLinkResolution {
        loadCacheIfNeeded()
        let resolution = resolveDeepLink(for: releaseID)
        guard case .ready = resolution else { return resolution }
        guard snapshot.pendingDeepLinkReleaseID != releaseID else {
            return resolution
        }
        let candidate = ReleaseCatalogCacheSnapshot(
            entries: snapshot.entries,
            notificationClaimedReleaseIDs: snapshot.notificationClaimedReleaseIDs,
            pendingDeepLinkReleaseID: releaseID,
            baselineEstablished: snapshot.baselineEstablished,
            lastSuccessfulRefreshUnixMillis: snapshot.lastSuccessfulRefreshUnixMillis
        )
        do {
            try cacheStore.save(candidate)
            snapshot = candidate
            return resolution
        } catch {
            return .persistenceUnavailable
        }
    }

    public func pendingDeepLink() -> ReleaseDeepLinkIntent? {
        loadCacheIfNeeded()
        guard let releaseID = snapshot.pendingDeepLinkReleaseID,
              case let .ready(intent) = resolveDeepLink(for: releaseID) else {
            return nil
        }
        return intent
    }

    @discardableResult
    public func completePendingDeepLink(for releaseID: ReleaseID) -> Bool {
        loadCacheIfNeeded()
        guard snapshot.pendingDeepLinkReleaseID == releaseID else { return false }
        let candidate = ReleaseCatalogCacheSnapshot(
            entries: snapshot.entries,
            notificationClaimedReleaseIDs: snapshot.notificationClaimedReleaseIDs,
            pendingDeepLinkReleaseID: nil,
            baselineEstablished: snapshot.baselineEstablished,
            lastSuccessfulRefreshUnixMillis: snapshot.lastSuccessfulRefreshUnixMillis
        )
        do {
            try cacheStore.save(candidate)
            snapshot = candidate
            return true
        } catch {
            return false
        }
    }

    private func resolveDeepLink(
        for releaseID: ReleaseID
    ) -> ReleaseDeepLinkResolution {
        switch resolvePackageContract(for: releaseID) {
        case let .ready(entry):
            return .ready(entry.deepLinkIntent)
        case let .requiresRuntime(minimum):
            return .requiresRuntime(minimum: minimum)
        case .notPublished:
            return .notPublished
        case .unknownRelease:
            return .unknownRelease
        }
    }

    private func resolvePackageContract(
        for releaseID: ReleaseID
    ) -> ReleasePackageContractResolution {
        guard let entry = snapshot.entries.first(where: { $0.id == releaseID }) else {
            return .unknownRelease
        }
        guard isPublished(entry) else { return .notPublished }
        guard isRuntimeCompatible(entry) else {
            return .requiresRuntime(minimum: entry.release.minimumRuntime)
        }
        return .ready(entry)
    }

    private func loadCacheIfNeeded() {
        guard !didLoadCache else { return }
        didLoadCache = true
        do {
            snapshot = try cacheStore.load() ?? .empty
        } catch {
            snapshot = .empty
            cacheWasCorrupt = true
        }
    }

    private func makeResult(
        from snapshot: ReleaseCatalogCacheSnapshot,
        notifications: [ReleaseNotificationIntent],
        source: ReleaseDiscoverySource,
        issue: ReleaseDiscoveryIssue?
    ) -> ReleaseDiscoveryResult {
        let published = snapshot.entries.filter(isPublished)
        return ReleaseDiscoveryResult(
            availableEntries: published.filter(isRuntimeCompatible),
            unsupportedRuntimeEntries: published.filter { !isRuntimeCompatible($0) },
            notificationIntents: notifications,
            source: source,
            issue: issue
        )
    }

    private func isPublished(_ entry: ReleaseCatalogEntry) -> Bool {
        entry.release.publishedAtUnixMillis <= Int64(now().timeIntervalSince1970 * 1_000)
    }

    private func isRuntimeCompatible(_ entry: ReleaseCatalogEntry) -> Bool {
        entry.release.minimumRuntime <= runtimeVersion
    }

    private static func merge(
        _ cached: [ReleaseCatalogEntry],
        with remote: [ReleaseCatalogEntry]
    ) throws -> [ReleaseCatalogEntry] {
        let cachedByID = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        let cachedBindings = Dictionary(uniqueKeysWithValues: cached.map {
            ("\($0.release.packageID.rawValue)@\($0.release.version)", $0.id)
        })
        for entry in remote {
            if let prior = cachedByID[entry.id], prior != entry {
                throw ReleaseCatalogError.immutableReleaseChanged(entry.id)
            }
            let binding = "\(entry.release.packageID.rawValue)@\(entry.release.version)"
            if let priorReleaseID = cachedBindings[binding], priorReleaseID != entry.id {
                throw ReleaseCatalogError.duplicatePackageBinding(
                    packageID: entry.release.packageID,
                    version: entry.release.version
                )
            }
        }

        // CKQuery notifications are only hints. The fully paginated query is
        // authoritative, so records that no longer match are removed from the
        // live catalog. Durable release-level notification claims remain in
        // the cache and prevent a later reappearance from notifying twice.
        return remote
    }
}
