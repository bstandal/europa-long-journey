import ContentKit
import ExperiencePreferences

public enum AudioRoleRouting: Equatable, Sendable {
    case audible
    case muted
    case timingOnly
}

/// Pure routing derived from locally stored experience preferences. Routing
/// never removes a cue or haptic from its authored timeline; native transports
/// apply it at their output boundary so cursor and end-sample authority remain
/// unchanged.
public struct ExperienceAudioRoutingPolicy: Equatable, Sendable {
    public let narrationIsAudible: Bool
    public let scoreIsAudible: Bool
    public let soundscapeIsAudible: Bool
    public let timelineHapticsAreEnabled: Bool
    public let semanticHapticsAreEnabled: Bool

    public init(preferences: ExperiencePreferences) {
        narrationIsAudible = preferences.narrationEnabled
        scoreIsAudible = preferences.scoreEnabled
        soundscapeIsAudible = preferences.soundscapeEnabled
        timelineHapticsAreEnabled = preferences.hapticsEnabled
        semanticHapticsAreEnabled = preferences.hapticsEnabled
    }

    public static let standard = ExperienceAudioRoutingPolicy(preferences: .standard)

    public func routing(for role: AudioTrackRole) -> AudioRoleRouting {
        switch role {
        case .narration:
            narrationIsAudible ? .audible : .muted
        case .score:
            scoreIsAudible ? .audible : .muted
        case .soundscape, .spatialDetail:
            soundscapeIsAudible ? .audible : .muted
        case .silence:
            .timingOnly
        }
    }

    public func mixerOutputVolume(for role: AudioTrackRole) -> Float? {
        switch routing(for: role) {
        case .audible:
            1
        case .muted:
            0
        case .timingOnly:
            nil
        }
    }
}
