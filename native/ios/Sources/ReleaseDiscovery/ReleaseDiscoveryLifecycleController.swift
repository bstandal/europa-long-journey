import ContentKit
import Foundation

public enum ReleaseNotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    public var permitsDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        }
    }
}

public protocol ReleaseNotificationAuthorizationProviding: Sendable {
    func authorizationStatus() async -> ReleaseNotificationAuthorizationStatus
    func requestAuthorization() async throws -> ReleaseNotificationAuthorizationStatus
}

public protocol ReleaseNotificationScheduling: Sendable {
    func schedule(_ intent: ReleaseNotificationIntent) async throws
}

public protocol ReleaseRemoteNotificationRegistering: Sendable {
    func registerForRemoteNotifications() async
}

public enum HistoricalExperienceMilestone: Equatable, Sendable {
    case prologueCompleted
    case historicalBeatCompleted
}

public struct ReleaseDiscoveryLifecycleUpdate: Equatable, Sendable {
    public let discovery: ReleaseDiscoveryResult
    public let scheduledReleaseIDs: [ReleaseID]
    public let failedNotificationReleaseIDs: [ReleaseID]

    public init(
        discovery: ReleaseDiscoveryResult,
        scheduledReleaseIDs: [ReleaseID] = [],
        failedNotificationReleaseIDs: [ReleaseID] = []
    ) {
        self.discovery = discovery
        self.scheduledReleaseIDs = scheduledReleaseIDs
        self.failedNotificationReleaseIDs = failedNotificationReleaseIDs
    }
}

public enum ReleaseDiscoveryLifecyclePushResult: Equatable, Sendable {
    case ignored
    case refreshed(ReleaseDiscoveryLifecycleUpdate)
}

public enum ReleaseNotificationEnrollmentResult: Equatable, Sendable {
    case blockedUntilHistoricalExperience
    case denied
    case unavailable
    case ready(
        subscription: ReleaseSubscriptionResult,
        update: ReleaseDiscoveryLifecycleUpdate
    )
}

/// Coordinates the only network edge used to discover later releases. App
/// activation and silent pushes may refresh the catalog, but neither path is
/// allowed to trigger the system permission sheet. That sheet is reachable
/// only after an explicit historical-experience milestone has been recorded.
public actor ReleaseDiscoveryLifecycleController {
    private let discovery: ReleaseDiscoveryController
    private let authorization: any ReleaseNotificationAuthorizationProviding
    private let scheduler: any ReleaseNotificationScheduling
    private let registrar: any ReleaseRemoteNotificationRegistering

    private var hasExperiencedHistory = false

    public init(
        discovery: ReleaseDiscoveryController,
        authorization: any ReleaseNotificationAuthorizationProviding,
        scheduler: any ReleaseNotificationScheduling,
        registrar: any ReleaseRemoteNotificationRegistering
    ) {
        self.discovery = discovery
        self.authorization = authorization
        self.scheduler = scheduler
        self.registrar = registrar
    }

    public func recordHistoricalExperience(
        _ milestone: HistoricalExperienceMilestone
    ) {
        switch milestone {
        case .prologueCompleted, .historicalBeatCompleted:
            hasExperiencedHistory = true
        }
    }

    public func applicationDidBecomeActive() async -> ReleaseDiscoveryLifecycleUpdate {
        let status = await authorization.authorizationStatus()
        if status.permitsDelivery {
            await registrar.registerForRemoteNotifications()
            _ = await discovery.prepareRemoteNotifications()
        }
        return await refreshAndSchedule(whenAuthorizedBy: status)
    }

    public func handleRemoteNotification(
        _ hint: ReleaseRemoteNotificationHint
    ) async -> ReleaseDiscoveryLifecyclePushResult {
        let result = await discovery.handleRemoteNotification(hint)
        switch result {
        case .ignored:
            return .ignored
        case let .refreshed(discoveryResult):
            let status = await authorization.authorizationStatus()
            return .refreshed(
                await deliver(
                    discoveryResult,
                    whenAuthorizedBy: status
                )
            )
        }
    }

    /// The caller must first record a real Journey milestone. No launch,
    /// foreground refresh or push callback calls this method on the user's
    /// behalf.
    public func requestNotificationAuthorization()
        async -> ReleaseNotificationEnrollmentResult {
        guard hasExperiencedHistory else {
            return .blockedUntilHistoricalExperience
        }

        var status = await authorization.authorizationStatus()
        if status == .notDetermined {
            do {
                status = try await authorization.requestAuthorization()
            } catch {
                return .unavailable
            }
        }
        guard status.permitsDelivery else { return .denied }

        await registrar.registerForRemoteNotifications()
        let subscription = await discovery.prepareRemoteNotifications()
        let update = await refreshAndSchedule(whenAuthorizedBy: status)
        return .ready(subscription: subscription, update: update)
    }

    public func resolveDeepLink(
        for releaseID: ReleaseID
    ) async -> ReleaseDeepLinkResolution {
        await discovery.beginDeepLink(for: releaseID)
    }

    public func pendingDeepLink() async -> ReleaseDeepLinkIntent? {
        await discovery.pendingDeepLink()
    }

    @discardableResult
    public func completePendingDeepLink(for releaseID: ReleaseID) async -> Bool {
        await discovery.completePendingDeepLink(for: releaseID)
    }

    public func notificationAuthorizationStatus()
        async -> ReleaseNotificationAuthorizationStatus {
        await authorization.authorizationStatus()
    }

    private func refreshAndSchedule(
        whenAuthorizedBy status: ReleaseNotificationAuthorizationStatus
    ) async -> ReleaseDiscoveryLifecycleUpdate {
        await deliver(
            await discovery.refresh(),
            whenAuthorizedBy: status
        )
    }

    private func deliver(
        _ result: ReleaseDiscoveryResult,
        whenAuthorizedBy status: ReleaseNotificationAuthorizationStatus
    ) async -> ReleaseDiscoveryLifecycleUpdate {
        guard status.permitsDelivery else {
            return ReleaseDiscoveryLifecycleUpdate(discovery: result)
        }

        var scheduled: [ReleaseID] = []
        var failed: [ReleaseID] = []
        for intent in result.notificationIntents {
            do {
                try await scheduler.schedule(intent)
                scheduled.append(intent.deepLink.releaseID)
            } catch {
                failed.append(intent.deepLink.releaseID)
            }
        }
        return ReleaseDiscoveryLifecycleUpdate(
            discovery: result,
            scheduledReleaseIDs: scheduled,
            failedNotificationReleaseIDs: failed
        )
    }
}
