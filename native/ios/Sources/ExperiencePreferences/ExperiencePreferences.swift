import Foundation

/// Narration is an authored, user-paced track. Enabling it makes the track
/// available; it never grants the runtime permission to start playback.
public enum NarrationPlaybackPolicy: String, Codable, Equatable, Sendable {
    case explicitUserActionOnly
}

public enum ExperiencePreferencesValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case narrationPlaybackMustRequireExplicitUserAction
}

/// Offline-owned choices for experience systems that the app controls.
///
/// Dynamic Type, Reduce Motion and Increased Contrast are intentionally not
/// stored here. Their current system values are read at the point of rendering
/// so the app cannot drift from the user's iOS accessibility configuration.
public struct ExperiencePreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var narrationEnabled: Bool
    public let narrationPlaybackPolicy: NarrationPlaybackPolicy
    public var scoreEnabled: Bool
    public var soundscapeEnabled: Bool
    public var hapticsEnabled: Bool
    public var cellularDownloadsEnabled: Bool
    public var automaticDeepDiveDownloadsEnabled: Bool

    public init(
        narrationEnabled: Bool = true,
        scoreEnabled: Bool = true,
        soundscapeEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        cellularDownloadsEnabled: Bool = false,
        automaticDeepDiveDownloadsEnabled: Bool = false
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.narrationEnabled = narrationEnabled
        narrationPlaybackPolicy = .explicitUserActionOnly
        self.scoreEnabled = scoreEnabled
        self.soundscapeEnabled = soundscapeEnabled
        self.hapticsEnabled = hapticsEnabled
        self.cellularDownloadsEnabled = cellularDownloadsEnabled
        self.automaticDeepDiveDownloadsEnabled = automaticDeepDiveDownloadsEnabled
    }

    public static let standard = ExperiencePreferences()

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ExperiencePreferencesValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard narrationPlaybackPolicy == .explicitUserActionOnly else {
            throw ExperiencePreferencesValidationError
                .narrationPlaybackMustRequireExplicitUserAction
        }
    }
}
