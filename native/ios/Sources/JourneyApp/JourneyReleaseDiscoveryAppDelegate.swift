import ContentKit
import ReleaseDiscovery
import UIKit
@preconcurrency import UserNotifications

@MainActor
final class JourneyReleaseDiscoveryBridge {
    static let shared = JourneyReleaseDiscoveryBridge()

    private var model: ReleaseDiscoveryApplicationModel?
    private var queuedHints: [ReleaseRemoteNotificationHint] = []
    private var queuedReleaseIDs: [ReleaseID] = []

    private init() {}

    func install(_ model: ReleaseDiscoveryApplicationModel) {
        self.model = model
        let hints = queuedHints
        let releaseIDs = queuedReleaseIDs
        queuedHints.removeAll()
        queuedReleaseIDs.removeAll()

        for hint in hints {
            Task { await model.handleRemoteNotification(hint) }
        }
        for releaseID in releaseIDs {
            Task { await model.openRelease(releaseID) }
        }
    }

    func handleRemoteNotification(
        _ hint: ReleaseRemoteNotificationHint
    ) async -> ReleaseDiscoveryLifecyclePushResult? {
        guard let model else {
            if !queuedHints.contains(hint) { queuedHints.append(hint) }
            return nil
        }
        return await model.handleRemoteNotification(hint)
    }

    func openRelease(_ releaseID: ReleaseID) {
        guard let model else {
            if !queuedReleaseIDs.contains(releaseID) {
                queuedReleaseIDs.append(releaseID)
            }
            return
        }
        Task { await model.openRelease(releaseID) }
    }
}

@MainActor
final class JourneyAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate {
    private let pushRouter = CloudKitReleasePushRouter()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: ReleaseServiceContract.notificationCategory,
                actions: [],
                intentIdentifiers: []
            ),
        ])
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let hint = pushRouter.hint(fromRemoteNotification: userInfo) else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let result = await JourneyReleaseDiscoveryBridge.shared
                .handleRemoteNotification(hint)
            switch result {
            case .none, .some(.ignored):
                completionHandler(.noData)
            case let .some(.refreshed(update)):
                completionHandler(update.discovery.source == .remote ? .newData : .noData)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard Self.releaseID(from: notification.request.content) != nil else {
            return []
        }
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let releaseID = Self.releaseID(
            from: response.notification.request.content
        ) else {
            return
        }
        await MainActor.run {
            JourneyReleaseDiscoveryBridge.shared.openRelease(releaseID)
        }
    }

    nonisolated private static func releaseID(
        from content: UNNotificationContent
    ) -> ReleaseID? {
        guard content.categoryIdentifier == ReleaseServiceContract.notificationCategory,
              let value = content.userInfo[
                  ReleaseServiceContract.notificationReleaseIDKey
              ] as? String else {
            return nil
        }
        return ReleaseID(value)
    }
}
