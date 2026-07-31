import ContentKit

public enum ResponsiveAudioPhaseDurabilityDecision: Equatable, Sendable {
    case ignore
    case deferUntilInteraction
    case commit
}

/// Decides whether one semantic interaction phase needs a new durability
/// action. Repeated touch and accessibility inputs that resolve to the phase
/// already playing are coalesced before transport or disk I/O.
public enum ResponsiveAudioPhaseDurabilityPolicy {
    public static func decision(
        desiredPhase: ResponsiveInteractionAudioPhase,
        currentStage: ResponsiveAudioProgramStage,
        currentPhase: ResponsiveInteractionAudioPhase?,
        isUserAuthorized: Bool,
        suspensionIsActive: Bool
    ) -> ResponsiveAudioPhaseDurabilityDecision {
        guard isUserAuthorized, !suspensionIsActive else { return .ignore }
        switch currentStage {
        case .approach:
            return .deferUntilInteraction
        case .interaction:
            return currentPhase == desiredPhase ? .ignore : .commit
        case .consequence, .completed:
            return .ignore
        }
    }
}
