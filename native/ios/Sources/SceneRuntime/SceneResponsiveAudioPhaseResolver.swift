import ContentKit
import JourneyDomain

/// Projects the shared reducer response into the three transient authored
/// audio beds. This boundary is deliberately grammar-neutral: scene gestures
/// and semantic accessibility actions have already converged on the same
/// `InteractionAction` before feedback reaches it.
public enum SceneResponsiveAudioPhaseResolver {
    public static func phase(
        interactionPhase: InteractionPhase?,
        feedback: InteractionFeedback?,
        directManipulation: SceneDirectManipulationState?
    ) -> ResponsiveInteractionAudioPhase? {
        guard interactionPhase != .complete,
              feedback != .completed else {
            // Completion is owned by the durable consequence transition.
            // It must never select another transient interaction bed.
            return nil
        }

        if let directManipulation {
            if directManipulation.outcome == .cancelled {
                // Letting go outside a valid bearing point is a neutral return
                // to the authored source. Only a reducer rejection earns the
                // short resistance bed.
                return .waiting
            }
            switch directManipulation.phase {
            case .contact, .lift, .carrying, .targetContact, .slotApproach, .accepted:
                return .engaged
            case .resistance:
                return .resistance
            case .snapBack:
                return directManipulation.outcome == .rejectedByReducer
                    ? .resistance : .waiting
            }
        }

        switch feedback {
        case nil, .some(.none):
            return .waiting
        case .some(.contact), .some(.progress), .some(.threshold):
            return .engaged
        case .some(.resistance):
            return .resistance
        case .some(.completed):
            return nil
        }
    }
}
