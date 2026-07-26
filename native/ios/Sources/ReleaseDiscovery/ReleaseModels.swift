import ContentKit
import Foundation

/// Stable service identifiers. They contain no public franchise or work title,
/// so a future title change cannot invalidate subscriptions or cached releases.
public enum ReleaseServiceContract {
    public static let cloudContainerIdentifier = "iCloud.com.thelongwest.journey"
    public static let cloudRecordType = "JourneyRelease"
    public static let cloudSubscriptionID = "journey-release-catalog-v1"
    public static let notificationCategory = "journey-release-available-v1"
    public static let notificationReleaseIDKey = "releaseID"

    public static let releasePayloadField = "releasePayload"
    public static let worldNodeIDField = "worldNodeID"
    public static let historicalYearField = "historicalYear"
    public static let chronologyOrdinalField = "chronologyOrdinal"
    public static let availableField = "isAvailable"
    public static let notificationTitleField = "notificationTitle"
    public static let notificationBodyField = "notificationBody"

    public static let cloudRecordFields: Set<String> = [
        releasePayloadField,
        worldNodeIDField,
        historicalYearField,
        chronologyOrdinalField,
        availableField,
        notificationTitleField,
        notificationBodyField,
    ]
}

/// English launch copy authored with the release itself. Release discovery
/// must never fabricate a title from a content identifier or expose an
/// internal slug in a notification.
public struct ReleaseAnnouncement: Codable, Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    public func validate() throws {
        guard Self.isValidLine(title, maximumCharacters: 80),
              Self.isValidLine(body, maximumCharacters: 180) else {
            throw ReleaseCatalogError.invalidAnnouncement
        }
    }

    private static func isValidLine(
        _ value: String,
        maximumCharacters: Int
    ) -> Bool {
        guard !value.isEmpty,
              value.count <= maximumCharacters,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { scalar in
                  CharacterSet.newlines.contains(scalar)
                      || CharacterSet.controlCharacters.contains(scalar)
              }) else {
            return false
        }
        return true
    }
}

/// Astronomical year numbering keeps ancient and modern anchors deterministic:
/// year 0 is 1 BC, -1 is 2 BC. `ordinal` orders multiple authored placements
/// inside the same year without pretending that an uncertain month is known.
public struct HistoricalTimeAnchor: Codable, Equatable, Comparable, Sendable {
    public let astronomicalYear: Int
    public let ordinal: Int

    public init(astronomicalYear: Int, ordinal: Int = 0) {
        self.astronomicalYear = astronomicalYear
        self.ordinal = ordinal
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.astronomicalYear, lhs.ordinal) < (rhs.astronomicalYear, rhs.ordinal)
    }

    public func validate() throws {
        guard ordinal >= 0 else {
            throw ReleaseCatalogError.invalidHistoricalTime
        }
    }
}

public struct ReleaseWorldPlacement: Codable, Equatable, Sendable {
    public let worldNodeID: WorldNodeID
    public let historicalTime: HistoricalTimeAnchor

    public init(worldNodeID: WorldNodeID, historicalTime: HistoricalTimeAnchor) {
        self.worldNodeID = worldNodeID
        self.historicalTime = historicalTime
    }

    public func validate() throws {
        guard Self.isStableIdentifier(worldNodeID.rawValue) else {
            throw ReleaseCatalogError.invalidWorldNodeID(worldNodeID.rawValue)
        }
        try historicalTime.validate()
    }

    private static func isStableIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("-"), !value.hasSuffix("-") else {
            return false
        }
        return value.utf8.allSatisfy {
            ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45
        }
    }
}

/// The trusted public catalog unit. `Release` owns the exact package contract;
/// placement only tells the living world where and when to open it.
public struct ReleaseCatalogEntry: Codable, Equatable, Identifiable, Sendable {
    public let release: Release
    public let placement: ReleaseWorldPlacement
    public let announcement: ReleaseAnnouncement

    public var id: ReleaseID { release.id }

    public init(
        release: Release,
        placement: ReleaseWorldPlacement,
        announcement: ReleaseAnnouncement
    ) {
        self.release = release
        self.placement = placement
        self.announcement = announcement
    }

    public func validate() throws {
        try release.validate()
        try placement.validate()
        try announcement.validate()
    }

    public var deepLinkIntent: ReleaseDeepLinkIntent {
        ReleaseDeepLinkIntent(
            releaseID: release.id,
            contentID: release.contentID,
            packageID: release.packageID,
            packageVersion: release.version,
            worldNodeID: placement.worldNodeID,
            historicalTime: placement.historicalTime
        )
    }
}

/// Framework-neutral representation of one CloudKit record. The iOS adapter
/// supplies it; tests can inject it without pretending to contact Apple.
public struct ReleaseRemoteRecord: Equatable, Sendable {
    public let recordName: String
    public let releasePayload: Data
    public let worldNodeID: String
    public let historicalYear: Int64
    public let chronologyOrdinal: Int64
    public let notificationTitle: String
    public let notificationBody: String

    public init(
        recordName: String,
        releasePayload: Data,
        worldNodeID: String,
        historicalYear: Int64,
        chronologyOrdinal: Int64,
        notificationTitle: String,
        notificationBody: String
    ) {
        self.recordName = recordName
        self.releasePayload = releasePayload
        self.worldNodeID = worldNodeID
        self.historicalYear = historicalYear
        self.chronologyOrdinal = chronologyOrdinal
        self.notificationTitle = notificationTitle
        self.notificationBody = notificationBody
    }

    public func decode() throws -> ReleaseCatalogEntry {
        guard releasePayload.count <= 64 * 1_024,
              let year = Int(exactly: historicalYear),
              let ordinal = Int(exactly: chronologyOrdinal) else {
            throw ReleaseCatalogError.invalidRemoteRecord(recordName)
        }
        let release = try ReleaseCatalogDecoder.decode(releasePayload)
        guard recordName == release.id.rawValue else {
            throw ReleaseCatalogError.recordIdentityMismatch(
                recordName: recordName,
                releaseID: release.id.rawValue
            )
        }
        let entry = ReleaseCatalogEntry(
            release: release,
            placement: ReleaseWorldPlacement(
                worldNodeID: WorldNodeID(worldNodeID),
                historicalTime: HistoricalTimeAnchor(
                    astronomicalYear: year,
                    ordinal: ordinal
                )
            ),
            announcement: ReleaseAnnouncement(
                title: notificationTitle,
                body: notificationBody
            )
        )
        try entry.validate()
        return entry
    }
}

public struct ReleaseDeepLinkIntent: Codable, Equatable, Sendable {
    public let releaseID: ReleaseID
    public let contentID: String
    public let packageID: PackageID
    public let packageVersion: SchemaVersion
    public let worldNodeID: WorldNodeID
    public let historicalTime: HistoricalTimeAnchor

    public init(
        releaseID: ReleaseID,
        contentID: String,
        packageID: PackageID,
        packageVersion: SchemaVersion,
        worldNodeID: WorldNodeID,
        historicalTime: HistoricalTimeAnchor
    ) {
        self.releaseID = releaseID
        self.contentID = contentID
        self.packageID = packageID
        self.packageVersion = packageVersion
        self.worldNodeID = worldNodeID
        self.historicalTime = historicalTime
    }
}

public struct ReleaseNotificationIntent: Equatable, Sendable {
    public let notificationIdentifier: String
    public let deepLink: ReleaseDeepLinkIntent
    public let announcement: ReleaseAnnouncement

    public init(
        deepLink: ReleaseDeepLinkIntent,
        announcement: ReleaseAnnouncement
    ) {
        notificationIdentifier = "release-available-\(deepLink.releaseID.rawValue)"
        self.deepLink = deepLink
        self.announcement = announcement
    }
}

public enum ReleaseDeepLinkResolution: Equatable, Sendable {
    case ready(ReleaseDeepLinkIntent)
    case requiresRuntime(minimum: SchemaVersion)
    case notPublished
    case unknownRelease
    case persistenceUnavailable
}

/// Resolves the complete authenticated catalog contract needed to verify and
/// install a post-launch package. A deep link deliberately carries only route
/// identity; delivery must obtain this value so the byte ceiling, chapter
/// ownership and minimum runtime cannot be reconstructed from an untrusted
/// package or notification payload.
public enum ReleasePackageContractResolution: Equatable, Sendable {
    case ready(ReleaseCatalogEntry)
    case requiresRuntime(minimum: SchemaVersion)
    case notPublished
    case unknownRelease
}

public enum ReleaseCatalogError: Error, Equatable, Sendable {
    case invalidRemoteRecord(String)
    case recordIdentityMismatch(recordName: String, releaseID: String)
    case invalidWorldNodeID(String)
    case invalidHistoricalTime
    case invalidAnnouncement
    case duplicateReleaseID(ReleaseID)
    case duplicatePackageBinding(packageID: PackageID, version: SchemaVersion)
    case immutableReleaseChanged(ReleaseID)
}

extension Array where Element == ReleaseCatalogEntry {
    public func validatedCanonicalReleaseCatalog() throws
        -> [ReleaseCatalogEntry] {
        var releaseIDs = Set<ReleaseID>()
        var packageBindings = Set<String>()
        for entry in self {
            try entry.validate()
            guard releaseIDs.insert(entry.id).inserted else {
                throw ReleaseCatalogError.duplicateReleaseID(entry.id)
            }
            let binding = "\(entry.release.packageID.rawValue)@\(entry.release.version)"
            guard packageBindings.insert(binding).inserted else {
                throw ReleaseCatalogError.duplicatePackageBinding(
                    packageID: entry.release.packageID,
                    version: entry.release.version
                )
            }
        }
        return sorted {
            if $0.release.publishedAtUnixMillis != $1.release.publishedAtUnixMillis {
                return $0.release.publishedAtUnixMillis < $1.release.publishedAtUnixMillis
            }
            return $0.id < $1.id
        }
    }
}
