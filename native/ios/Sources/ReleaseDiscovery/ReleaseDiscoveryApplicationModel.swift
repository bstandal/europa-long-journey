import Combine
import ContentKit
import Foundation

/// Main-actor handoff between application callbacks and the living-world
/// route consumer. A notification tap resolves only through the authenticated
/// catalog and retains the complete historical placement until the Journey
/// has adopted it.
@MainActor
public final class ReleaseDiscoveryApplicationModel: ObservableObject {
    @Published public private(set) var latestUpdate: ReleaseDiscoveryLifecycleUpdate?
    @Published public private(set) var pendingDeepLink: ReleaseDeepLinkIntent?
    @Published public private(set) var lastDeepLinkResolution: ReleaseDeepLinkResolution?
    @Published public private(set) var notificationEnrollment:
        ReleaseNotificationEnrollmentResult?
    @Published public private(set) var notificationAuthorizationStatus:
        ReleaseNotificationAuthorizationStatus?

    private let lifecycle: ReleaseDiscoveryLifecycleController?

    public init(lifecycle: ReleaseDiscoveryLifecycleController) {
        self.lifecycle = lifecycle
    }

    /// Release discovery is nonessential to the installed Journey. If its
    /// local composition cannot be created, the app remains fully usable
    /// offline and can retry after the next app build or installation repair.
    public init(unavailable: Void = ()) {
        lifecycle = nil
    }

    @discardableResult
    public func applicationDidBecomeActive()
        async -> ReleaseDiscoveryLifecycleUpdate? {
        guard let lifecycle else { return nil }
        if let restored = await lifecycle.pendingDeepLink() {
            pendingDeepLink = restored
        }
        let update = await lifecycle.applicationDidBecomeActive()
        latestUpdate = update
        notificationAuthorizationStatus = await lifecycle
            .notificationAuthorizationStatus()
        return update
    }

    @discardableResult
    public func handleRemoteNotification(
        _ hint: ReleaseRemoteNotificationHint
    ) async -> ReleaseDiscoveryLifecyclePushResult {
        guard let lifecycle else { return .ignored }
        let result = await lifecycle.handleRemoteNotification(hint)
        if case let .refreshed(update) = result {
            latestUpdate = update
        }
        return result
    }

    public func recordHistoricalExperience(
        _ milestone: HistoricalExperienceMilestone
    ) async {
        await lifecycle?.recordHistoricalExperience(milestone)
    }

    @discardableResult
    public func requestNotificationAuthorization()
        async -> ReleaseNotificationEnrollmentResult {
        guard let lifecycle else {
            notificationEnrollment = .unavailable
            return .unavailable
        }
        let result = await lifecycle.requestNotificationAuthorization()
        notificationEnrollment = result
        notificationAuthorizationStatus = await lifecycle
            .notificationAuthorizationStatus()
        if case let .ready(_, update) = result {
            latestUpdate = update
        }
        return result
    }

    @discardableResult
    public func openRelease(
        _ releaseID: ReleaseID
    ) async -> ReleaseDeepLinkResolution {
        guard let lifecycle else {
            lastDeepLinkResolution = .unknownRelease
            return .unknownRelease
        }
        let resolution = await lifecycle.resolveDeepLink(for: releaseID)
        lastDeepLinkResolution = resolution
        if case let .ready(intent) = resolution {
            pendingDeepLink = intent
        }
        return resolution
    }

    public func consumePendingDeepLink(
        releaseID: ReleaseID
    ) async -> ReleaseDeepLinkIntent? {
        guard let lifecycle,
              let intent = pendingDeepLink,
              intent.releaseID == releaseID,
              await lifecycle.completePendingDeepLink(for: releaseID) else {
            return nil
        }
        pendingDeepLink = nil
        return intent
    }
}
