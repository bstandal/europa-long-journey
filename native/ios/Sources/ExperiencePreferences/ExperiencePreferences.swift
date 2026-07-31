import Foundation

public enum ExperiencePreferencesValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

/// Offline-owned choices for experience systems that the app controls.
///
/// Dynamic Type, Reduce Motion and Increased Contrast are intentionally not
/// stored here. Their current system values are read at the point of rendering
/// so the app cannot drift from the user's iOS accessibility configuration.
public struct ExperiencePreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    /// The single user-facing switch for every authored audio layer.
    public var soundEnabled: Bool
    /// Keeps narration optional while score, soundscape and spatial detail
    /// remain one authored mix behind `soundEnabled`.
    public var narrationEnabled: Bool
    public var hapticsEnabled: Bool
    public var cellularDownloadsEnabled: Bool
    public var automaticDeepDiveDownloadsEnabled: Bool

    public init(
        soundEnabled: Bool = true,
        narrationEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        cellularDownloadsEnabled: Bool = false,
        automaticDeepDiveDownloadsEnabled: Bool = false
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.soundEnabled = soundEnabled
        self.narrationEnabled = narrationEnabled
        self.hapticsEnabled = hapticsEnabled
        self.cellularDownloadsEnabled = cellularDownloadsEnabled
        self.automaticDeepDiveDownloadsEnabled = automaticDeepDiveDownloadsEnabled
    }

    public static let standard = ExperiencePreferences()

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ExperiencePreferencesValidationError.unsupportedSchemaVersion(schemaVersion)
        }
    }
}
