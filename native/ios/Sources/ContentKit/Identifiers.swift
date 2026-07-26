import Foundation

/// A stable, title-independent identifier used by authored content and persisted progress.
public struct StableID<Domain>: RawRepresentable, Codable, Hashable, Comparable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
where Domain: Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum CollectionIDDomain: Sendable {}
public enum PackageIDDomain: Sendable {}
public enum ChapterIDDomain: Sendable {}
public enum ArcIDDomain: Sendable {}
public enum BeatIDDomain: Sendable {}
public enum SceneIDDomain: Sendable {}
public enum SceneLayerIDDomain: Sendable {}
public enum InteractionIDDomain: Sendable {}
public enum AudioCueIDDomain: Sendable {}
public enum AudioTimelineIDDomain: Sendable {}
public enum AccessibilityIDDomain: Sendable {}
public enum WorldNodeIDDomain: Sendable {}
public enum WorldTraceIDDomain: Sendable {}
public enum WorldEffectIDDomain: Sendable {}
public enum EntitlementIDDomain: Sendable {}
public enum ReleaseIDDomain: Sendable {}
public enum LocalizedStringIDDomain: Sendable {}
public enum AppShellIDDomain: Sendable {}
public enum PrologueIDDomain: Sendable {}
public enum LivingWorldPresentationIDDomain: Sendable {}

public typealias CollectionID = StableID<CollectionIDDomain>
public typealias PackageID = StableID<PackageIDDomain>
public typealias ChapterID = StableID<ChapterIDDomain>
public typealias ArcID = StableID<ArcIDDomain>
public typealias BeatID = StableID<BeatIDDomain>
public typealias SceneID = StableID<SceneIDDomain>
public typealias SceneLayerID = StableID<SceneLayerIDDomain>
public typealias InteractionID = StableID<InteractionIDDomain>
public typealias AudioCueID = StableID<AudioCueIDDomain>
public typealias AudioTimelineID = StableID<AudioTimelineIDDomain>
public typealias AccessibilityID = StableID<AccessibilityIDDomain>
public typealias WorldNodeID = StableID<WorldNodeIDDomain>
public typealias WorldTraceID = StableID<WorldTraceIDDomain>
public typealias WorldEffectID = StableID<WorldEffectIDDomain>
public typealias EntitlementID = StableID<EntitlementIDDomain>
public typealias ReleaseID = StableID<ReleaseIDDomain>
public typealias LocalizedStringID = StableID<LocalizedStringIDDomain>
public typealias AppShellID = StableID<AppShellIDDomain>
public typealias PrologueID = StableID<PrologueIDDomain>
public typealias LivingWorldPresentationID = StableID<LivingWorldPresentationIDDomain>

public struct SchemaVersion: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public var isValid: Bool {
        major >= 0 && minor >= 0 && patch >= 0
    }
}

public enum ContentValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyIdentifier(String)
    case duplicateIdentifier(String)
    case invalidCount(field: String, expected: String, actual: Int)
    case invalidValue(field: String, reason: String)
    case missingReference(field: String, identifier: String)
    case unsafeAssetPath(String)

    public var description: String {
        switch self {
        case let .emptyIdentifier(field):
            "Empty stable identifier in \(field)"
        case let .duplicateIdentifier(identifier):
            "Duplicate stable identifier: \(identifier)"
        case let .invalidCount(field, expected, actual):
            "Invalid count for \(field): expected \(expected), found \(actual)"
        case let .invalidValue(field, reason):
            "Invalid value for \(field): \(reason)"
        case let .missingReference(field, identifier):
            "Missing reference in \(field): \(identifier)"
        case let .unsafeAssetPath(path):
            "Content asset path must be package-relative: \(path)"
        }
    }
}

@inline(__always)
func requireNonempty<Domain>(_ id: StableID<Domain>, field: String) throws where Domain: Sendable {
    guard !id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ContentValidationError.emptyIdentifier(field)
    }
    guard isStableStringIdentifier(id.rawValue) else {
        throw ContentValidationError.invalidValue(
            field: field,
            reason: "must be a stable kebab-case identifier"
        )
    }
}

func requireUnique<Domain>(_ ids: [StableID<Domain>]) throws where Domain: Sendable {
    var seen: Set<String> = []
    for id in ids {
        guard seen.insert(id.rawValue).inserted else {
            throw ContentValidationError.duplicateIdentifier(id.rawValue)
        }
    }
}

func requireSafePackageAssetPath(_ path: String) throws {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    let containsControlCharacter = path.unicodeScalars.contains { scalar in
        scalar.value <= 0x1F || scalar.value == 0x7F
    }
    guard !path.isEmpty,
          !path.hasPrefix("/"),
          !path.contains("\\"),
          !path.contains("://"),
          !containsControlCharacter,
          components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
        throw ContentValidationError.unsafeAssetPath(path)
    }
}

func isStableStringIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, !value.hasPrefix("-"), !value.hasSuffix("-"), !value.contains("--") else {
        return false
    }
    return value.utf8.allSatisfy { byte in
        (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 45
    }
}
