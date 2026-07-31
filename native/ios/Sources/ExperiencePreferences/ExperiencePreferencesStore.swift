import CryptoKit
import Foundation

public protocol ExperiencePreferencesAtomicWriting: Sendable {
    func writeAtomically(_ data: Data, to url: URL) throws
}

public struct FoundationExperiencePreferencesWriter: ExperiencePreferencesAtomicWriting {
    public init() {}

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

public enum ExperiencePreferencesLoadOrigin: Equatable, Sendable {
    case defaultsBecauseFileIsMissing
    case stored
    case migrated(fromSchemaVersion: Int)
    case recoveredFromCorruptFile(preservedAt: URL)
    case defaultsProtectedFromFutureSchema(version: Int, preservedAt: URL)
}

public struct ExperiencePreferencesLoadResult: Equatable, Sendable {
    public let preferences: ExperiencePreferences
    public let origin: ExperiencePreferencesLoadOrigin

    public init(
        preferences: ExperiencePreferences,
        origin: ExperiencePreferencesLoadOrigin
    ) {
        self.preferences = preferences
        self.origin = origin
    }
}

public enum ExperiencePreferencesStoreError: Error, Equatable, Sendable {
    case futureSchemaWriteBlocked(Int)
    case preservationCollision(URL)
}

/// Atomic, local-only storage for experience preferences.
///
/// A corrupt document is copied byte-for-byte to the preservation directory
/// before stable defaults replace it. A document written by a newer schema is
/// preserved and left untouched; writes remain blocked until a subsequent
/// `load()` proves that the canonical file is supported again.
public actor ExperiencePreferencesStore {
    public nonisolated let directoryURL: URL
    public nonisolated let preferencesFileURL: URL
    public nonisolated let preservedFilesDirectoryURL: URL

    private let writer: any ExperiencePreferencesAtomicWriting
    private var blockedFutureSchemaVersion: Int?

    public init(
        directoryURL: URL,
        writer: any ExperiencePreferencesAtomicWriting = FoundationExperiencePreferencesWriter()
    ) throws {
        self.directoryURL = directoryURL
        preferencesFileURL = directoryURL.appendingPathComponent(
            "experience-preferences.json",
            isDirectory: false
        )
        preservedFilesDirectoryURL = directoryURL.appendingPathComponent(
            "PreservedExperiencePreferences",
            isDirectory: true
        )
        self.writer = writer
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    public func load() throws -> ExperiencePreferencesLoadResult {
        blockedFutureSchemaVersion = nil
        guard FileManager.default.fileExists(atPath: preferencesFileURL.path) else {
            return ExperiencePreferencesLoadResult(
                preferences: .standard,
                origin: .defaultsBecauseFileIsMissing
            )
        }

        let bytes = try Data(contentsOf: preferencesFileURL)
        switch Self.classify(bytes) {
        case let .current(preferences):
            return ExperiencePreferencesLoadResult(
                preferences: preferences,
                origin: .stored
            )

        case let .legacyV0(legacy):
            let migrated = legacy.migrated()
            try writeCurrent(migrated)
            return ExperiencePreferencesLoadResult(
                preferences: migrated,
                origin: .migrated(fromSchemaVersion: 0)
            )

        case let .legacyV1(legacy):
            let migrated = legacy.migrated()
            try writeCurrent(migrated)
            return ExperiencePreferencesLoadResult(
                preferences: migrated,
                origin: .migrated(fromSchemaVersion: 1)
            )

        case let .future(version):
            let preservedURL = try preserve(
                bytes,
                classification: "future-v\(version)"
            )
            blockedFutureSchemaVersion = version
            return ExperiencePreferencesLoadResult(
                preferences: .standard,
                origin: .defaultsProtectedFromFutureSchema(
                    version: version,
                    preservedAt: preservedURL
                )
            )

        case .corrupt:
            let preservedURL = try preserve(bytes, classification: "corrupt")
            try writeCurrent(.standard)
            return ExperiencePreferencesLoadResult(
                preferences: .standard,
                origin: .recoveredFromCorruptFile(preservedAt: preservedURL)
            )
        }
    }

    public func save(_ preferences: ExperiencePreferences) throws {
        try preferences.validate()
        if let blockedFutureSchemaVersion {
            throw ExperiencePreferencesStoreError.futureSchemaWriteBlocked(
                blockedFutureSchemaVersion
            )
        }
        try protectExistingDocumentBeforeWrite()
        try writeCurrent(preferences)
    }

    private func protectExistingDocumentBeforeWrite() throws {
        guard FileManager.default.fileExists(atPath: preferencesFileURL.path) else { return }
        let bytes = try Data(contentsOf: preferencesFileURL)
        switch Self.classify(bytes) {
        case .current, .legacyV0, .legacyV1:
            return
        case let .future(version):
            _ = try preserve(bytes, classification: "future-v\(version)")
            blockedFutureSchemaVersion = version
            throw ExperiencePreferencesStoreError.futureSchemaWriteBlocked(version)
        case .corrupt:
            _ = try preserve(bytes, classification: "corrupt")
        }
    }

    private func writeCurrent(_ preferences: ExperiencePreferences) throws {
        try preferences.validate()
        try writer.writeAtomically(Self.encode(preferences), to: preferencesFileURL)
    }

    private func preserve(_ bytes: Data, classification: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: preservedFilesDirectoryURL,
            withIntermediateDirectories: true
        )
        let digest = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
        let target = preservedFilesDirectoryURL.appendingPathComponent(
            "experience-preferences.\(classification).\(digest).json",
            isDirectory: false
        )

        if FileManager.default.fileExists(atPath: target.path) {
            guard try Data(contentsOf: target) == bytes else {
                throw ExperiencePreferencesStoreError.preservationCollision(target)
            }
            return target
        }

        try writer.writeAtomically(bytes, to: target)
        return target
    }

    private static func classify(_ bytes: Data) -> StoredDocument {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(SchemaHeader.self, from: bytes) else {
            return .corrupt
        }
        guard header.schemaVersion >= 0 else { return .corrupt }

        if header.schemaVersion > ExperiencePreferences.currentSchemaVersion {
            return .future(header.schemaVersion)
        }
        switch header.schemaVersion {
        case 0:
            guard let legacy = try? decoder.decode(LegacyExperiencePreferencesV0.self, from: bytes)
            else { return .corrupt }
            return .legacyV0(legacy)
        case 1:
            guard let legacy = try? decoder.decode(LegacyExperiencePreferencesV1.self, from: bytes)
            else { return .corrupt }
            return .legacyV1(legacy)
        case ExperiencePreferences.currentSchemaVersion:
            guard let preferences = try? decoder.decode(ExperiencePreferences.self, from: bytes),
                  (try? preferences.validate()) != nil else {
                return .corrupt
            }
            return .current(preferences)
        default:
            return .corrupt
        }
    }

    private static func encode(_ preferences: ExperiencePreferences) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(preferences)
    }
}

private enum StoredDocument {
    case current(ExperiencePreferences)
    case legacyV0(LegacyExperiencePreferencesV0)
    case legacyV1(LegacyExperiencePreferencesV1)
    case future(Int)
    case corrupt
}

private struct SchemaHeader: Decodable {
    let schemaVersion: Int
}

private struct LegacyExperiencePreferencesV0: Codable {
    let schemaVersion: Int
    let narrationEnabled: Bool
    let scoreEnabled: Bool
    let soundscapeEnabled: Bool
    let hapticsEnabled: Bool
    let cellularDownloadsEnabled: Bool

    func migrated() -> ExperiencePreferences {
        ExperiencePreferences(
            soundEnabled: narrationEnabled || scoreEnabled || soundscapeEnabled,
            narrationEnabled: narrationEnabled,
            hapticsEnabled: hapticsEnabled,
            cellularDownloadsEnabled: cellularDownloadsEnabled,
            automaticDeepDiveDownloadsEnabled: false
        )
    }
}

private enum LegacyNarrationPlaybackPolicyV1: String, Codable {
    case explicitUserActionOnly
}

private struct LegacyExperiencePreferencesV1: Codable {
    let schemaVersion: Int
    let narrationEnabled: Bool
    let narrationPlaybackPolicy: LegacyNarrationPlaybackPolicyV1
    let scoreEnabled: Bool
    let soundscapeEnabled: Bool
    let hapticsEnabled: Bool
    let cellularDownloadsEnabled: Bool
    let automaticDeepDiveDownloadsEnabled: Bool

    func migrated() -> ExperiencePreferences {
        ExperiencePreferences(
            soundEnabled: narrationEnabled || scoreEnabled || soundscapeEnabled,
            narrationEnabled: narrationEnabled,
            hapticsEnabled: hapticsEnabled,
            cellularDownloadsEnabled: cellularDownloadsEnabled,
            automaticDeepDiveDownloadsEnabled: automaticDeepDiveDownloadsEnabled
        )
    }
}
