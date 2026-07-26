#if os(iOS) && canImport(CloudKit) && canImport(UserNotifications)
@preconcurrency import CloudKit
import ContentKit
import Foundation
@preconcurrency import UserNotifications

public enum CloudKitReleaseAdapterError: Error, Equatable, Sendable {
    case subscriptionConflict
    case unexpectedRecordType(String)
    case unexpectedRecordFields
    case unavailableRecord
    case invalidRecordField(String)
    case recordFetchFailed(String)
}

/// Production edge for the public CloudKit database. The adapter deliberately
/// treats subscription notifications as coalescible change hints and always
/// refetches the complete available catalog with cursor pagination.
public actor CloudKitReleaseCatalogProvider: ReleaseCatalogRemoteProviding {
    private let database: CKDatabase

    public init(
        containerIdentifier: String = ReleaseServiceContract.cloudContainerIdentifier
    ) {
        database = CKContainer(identifier: containerIdentifier).publicCloudDatabase
    }

    public func ensureReleaseSubscription() async throws {
        do {
            let existing = try await database.subscription(
                for: ReleaseServiceContract.cloudSubscriptionID
            )
            guard let query = existing as? CKQuerySubscription,
                  query.recordType == ReleaseServiceContract.cloudRecordType,
                  query.querySubscriptionOptions == [.firesOnRecordCreation],
                  query.notificationInfo?.shouldSendContentAvailable == true,
                  query.notificationInfo?.alertBody == nil,
                  query.notificationInfo?.alertLocalizationKey == nil,
                  query.notificationInfo?.soundName == nil,
                  query.notificationInfo?.shouldBadge == false else {
                throw CloudKitReleaseAdapterError.subscriptionConflict
            }
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Expected first-install path.
        }

        let subscription = CKQuerySubscription(
            recordType: ReleaseServiceContract.cloudRecordType,
            predicate: availablePredicate,
            subscriptionID: ReleaseServiceContract.cloudSubscriptionID,
            options: [.firesOnRecordCreation]
        )
        let notification = CKSubscription.NotificationInfo()
        // Apple specifies that a background CKQuery notification should set
        // only content-available. No record fields or alert copy are trusted
        // from the push payload.
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        _ = try await database.save(subscription)
    }

    public func fetchAvailableReleaseRecords() async throws -> [ReleaseRemoteRecord] {
        let query = CKQuery(
            recordType: ReleaseServiceContract.cloudRecordType,
            predicate: availablePredicate
        )
        let desiredKeys = Array(ReleaseServiceContract.cloudRecordFields).sorted()

        var records: [CKRecord] = []
        var first = true
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let batch: (
                matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)],
                queryCursor: CKQueryOperation.Cursor?
            )
            if first {
                batch = try await database.records(
                    matching: query,
                    desiredKeys: desiredKeys,
                    resultsLimit: CKQueryOperation.maximumResults
                )
                first = false
            } else if let cursor {
                batch = try await database.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: desiredKeys,
                    resultsLimit: CKQueryOperation.maximumResults
                )
            } else {
                break
            }

            for (recordID, result) in batch.matchResults {
                do {
                    records.append(try result.get())
                } catch {
                    throw CloudKitReleaseAdapterError.recordFetchFailed(recordID.recordName)
                }
            }
            cursor = batch.queryCursor
        } while cursor != nil

        return try records.map(Self.remoteRecord)
    }

    private var availablePredicate: NSPredicate {
        NSPredicate(
            format: "%K == %@",
            ReleaseServiceContract.availableField,
            NSNumber(value: true)
        )
    }

    private static func remoteRecord(_ record: CKRecord) throws -> ReleaseRemoteRecord {
        guard record.recordType == ReleaseServiceContract.cloudRecordType else {
            throw CloudKitReleaseAdapterError.unexpectedRecordType(record.recordType)
        }
        guard Set(record.allKeys()) == ReleaseServiceContract.cloudRecordFields else {
            throw CloudKitReleaseAdapterError.unexpectedRecordFields
        }
        guard let available = record[ReleaseServiceContract.availableField] as? NSNumber,
              available.boolValue else {
            throw CloudKitReleaseAdapterError.unavailableRecord
        }
        guard let payload = record[ReleaseServiceContract.releasePayloadField] as? Data else {
            throw CloudKitReleaseAdapterError.invalidRecordField(
                ReleaseServiceContract.releasePayloadField
            )
        }
        guard let worldNodeID = record[ReleaseServiceContract.worldNodeIDField] as? String else {
            throw CloudKitReleaseAdapterError.invalidRecordField(
                ReleaseServiceContract.worldNodeIDField
            )
        }
        guard let year = record[ReleaseServiceContract.historicalYearField] as? NSNumber else {
            throw CloudKitReleaseAdapterError.invalidRecordField(
                ReleaseServiceContract.historicalYearField
            )
        }
        guard let ordinal = record[ReleaseServiceContract.chronologyOrdinalField] as? NSNumber else {
            throw CloudKitReleaseAdapterError.invalidRecordField(
                ReleaseServiceContract.chronologyOrdinalField
            )
        }
        guard let notificationTitle = record[
            ReleaseServiceContract.notificationTitleField
        ] as? String else {
            throw CloudKitReleaseAdapterError.invalidRecordField(
                ReleaseServiceContract.notificationTitleField
            )
        }
        guard let notificationBody = record[
            ReleaseServiceContract.notificationBodyField
        ] as? String else {
            throw CloudKitReleaseAdapterError.invalidRecordField(
                ReleaseServiceContract.notificationBodyField
            )
        }
        return ReleaseRemoteRecord(
            recordName: record.recordID.recordName,
            releasePayload: payload,
            worldNodeID: worldNodeID,
            historicalYear: year.int64Value,
            chronologyOrdinal: ordinal.int64Value,
            notificationTitle: notificationTitle,
            notificationBody: notificationBody
        )
    }
}

public struct CloudKitReleasePushRouter: Sendable {
    public init() {}

    public func hint(
        fromRemoteNotification userInfo: [AnyHashable: Any]
    ) -> ReleaseRemoteNotificationHint? {
        guard let notification = CKNotification(
            fromRemoteNotificationDictionary: userInfo
        ) as? CKQueryNotification,
              notification.databaseScope == .public,
              let subscriptionID = notification.subscriptionID else {
            return nil
        }
        return ReleaseRemoteNotificationHint(
            subscriptionID: subscriptionID,
            recordName: notification.recordID?.recordName
        )
    }
}

/// Schedules a caller-authored local notification after the controller has
/// durably claimed the release. It never requests permission and never authors
/// public copy. The deterministic request identifier also replaces a still-
/// pending duplicate for the same release at the UserNotifications boundary.
@MainActor
public final class AppleReleaseNotificationScheduler: ReleaseNotificationScheduling {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func schedule(
        _ intent: ReleaseNotificationIntent,
        content: UNMutableNotificationContent
    ) async throws {
        var userInfo = content.userInfo
        userInfo[ReleaseServiceContract.notificationReleaseIDKey] =
            intent.deepLink.releaseID.rawValue
        content.userInfo = userInfo
        content.categoryIdentifier = ReleaseServiceContract.notificationCategory
        let request = UNNotificationRequest(
            identifier: intent.notificationIdentifier,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    public func schedule(_ intent: ReleaseNotificationIntent) async throws {
        let content = UNMutableNotificationContent()
        content.title = intent.announcement.title
        content.body = intent.announcement.body
        content.sound = .default
        try await schedule(intent, content: content)
    }

    public static func releaseID(from content: UNNotificationContent) -> ReleaseID? {
        guard content.categoryIdentifier == ReleaseServiceContract.notificationCategory,
              let value = content.userInfo[
            ReleaseServiceContract.notificationReleaseIDKey
        ] as? String else {
            return nil
        }
        return ReleaseID(value)
    }
}

@MainActor
public final class AppleReleaseNotificationAuthorizationProvider:
    ReleaseNotificationAuthorizationProviding {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func authorizationStatus() async -> ReleaseNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        return Self.status(settings.authorizationStatus)
    }

    public func requestAuthorization() async throws -> ReleaseNotificationAuthorizationStatus {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        let settings = await center.notificationSettings()
        return Self.status(settings.authorizationStatus)
    }

    private static func status(
        _ status: UNAuthorizationStatus
    ) -> ReleaseNotificationAuthorizationStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .provisional:
            .provisional
        case .ephemeral:
            .ephemeral
        @unknown default:
            .denied
        }
    }
}
#endif
