import Foundation

/// Decides whether an audio-route notification can invalidate the output or
/// render clock used by the current journey. The app's own category setup is
/// the sole reason that is proven not to change output authority; every other
/// delivered route event is conservatively checkpointed and explicitly resumed.
public enum JourneyAudioRouteChangeSuspensionPolicy {
    private enum Reason: UInt {
        case unknown = 0
        case newDeviceAvailable = 1
        case oldDeviceUnavailable = 2
        case categoryChange = 3
        case override = 4
        case wakeFromSleep = 6
        case noSuitableRouteForCategory = 7
        case routeConfigurationChange = 8
    }

    /// Raw values mirror the stable route-change reason values delivered by
    /// the platform adapter. Keeping the decision here makes it deterministic
    /// and testable without importing an audio framework.
    public static func shouldSuspend(reasonRawValue: UInt?) -> Bool {
        guard let reasonRawValue, let reason = Reason(rawValue: reasonRawValue)
        else { return true }
        return switch reason {
        case .categoryChange:
            // NativeTimelineTransport configures the playback category while
            // acquiring its lease. That setup notification cannot pause the
            // very playback it is preparing.
            false
        case .unknown,
             .newDeviceAvailable,
             .oldDeviceUnavailable,
             .override,
             .wakeFromSleep,
             .noSuitableRouteForCategory,
             .routeConfigurationChange:
            true
        }
    }

    /// A route change matters only while this Journey owns, is starting, or
    /// is deliberately fading an authored render. Reading in silence must not
    /// rebuild and gate an otherwise untouched scene when headphones change.
    public static func journeyAudioRequiresSuspension(
        controllerIsPlaying: Bool,
        playbackStartIsInFlight: Bool,
        crashCursorIsArmed: Bool,
        outgoingTailIsActive: Bool
    ) -> Bool {
        controllerIsPlaying
            || playbackStartIsInFlight
            || crashCursorIsArmed
            || outgoingTailIsActive
    }
}
