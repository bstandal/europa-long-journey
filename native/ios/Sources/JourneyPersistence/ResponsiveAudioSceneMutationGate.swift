import ContentKit

public enum ResponsiveAudioSceneMutationGateError: Error, Equatable, Sendable {
    case authoredAudioUnavailable
    case automaticBoundaryDurabilityPending
}

/// Main-actor-owned admission state for the narrow interval in which a scene
/// input may first commit Journey history and then commit its responsive-audio
/// follow-up. Suspension and phase requests retain semantic intent here; they
/// do not materialize a snapshot from a controller that may still be one
/// durable Transform action behind.
public struct ResponsiveAudioSceneMutationGate: Sendable {
    public struct Token: Hashable, Sendable {
        fileprivate let generation: UInt64
    }

    public struct AutomaticBoundaryToken: Hashable, Sendable {
        fileprivate let generation: UInt64
    }

    public struct AutomaticBoundaryIntent: Equatable, Sendable {
        public let token: AutomaticBoundaryToken
        public let controllerIdentifier: ObjectIdentifier

        fileprivate init(
            token: AutomaticBoundaryToken,
            controllerIdentifier: ObjectIdentifier
        ) {
            self.token = token
            self.controllerIdentifier = controllerIdentifier
        }
    }

    public enum AutomaticBoundaryAdmission: Equatable, Sendable {
        /// A scene transaction owns the controller until its conditional audio
        /// follow-up returns. The signal is retained without retaining a
        /// captured Journey action.
        case deferred
        /// No scene transaction is active. The returned intent immediately
        /// blocks the next responsive scene admission until its fresh snapshot
        /// has crossed the journal boundary.
        case admitted(AutomaticBoundaryIntent)
        /// A second or mismatched boundary cannot overtake the first.
        case rejected
    }

    public struct DeferredIntents: Equatable, Sendable {
        public let phase: ResponsiveInteractionAudioPhase?
        public let suspensionEpochMillis: Int64?
        public let automaticBoundary: AutomaticBoundaryIntent?

        fileprivate init(
            phase: ResponsiveInteractionAudioPhase?,
            suspensionEpochMillis: Int64?,
            automaticBoundary: AutomaticBoundaryIntent?
        ) {
            self.phase = phase
            self.suspensionEpochMillis = suspensionEpochMillis
            self.automaticBoundary = automaticBoundary
        }
    }

    private var generation: UInt64 = 0
    private var automaticBoundaryGeneration: UInt64 = 0
    private var activeGenerations: Set<UInt64> = []
    private var deferredPhase: ResponsiveInteractionAudioPhase?
    private var deferredSuspensionEpochMillis: Int64?
    private var deferredAutomaticBoundaryControllerIdentifier:
        ObjectIdentifier?
    private var pendingAutomaticBoundary: AutomaticBoundaryIntent?

    public init() {}

    public var hasActiveResponsiveSceneMutation: Bool {
        !activeGenerations.isEmpty
    }

    public var automaticBoundaryDurabilityIsPending: Bool {
        pendingAutomaticBoundary != nil
    }

    /// Non-responsive beats receive no token and never wait on this gate.
    /// Responsive beats fail before their historical action is admitted when
    /// the exact offline controller is unavailable.
    public mutating func begin(
        requiresResponsiveAudio: Bool,
        controllerIsReady: Bool
    ) throws -> Token? {
        guard requiresResponsiveAudio else { return nil }
        guard pendingAutomaticBoundary == nil else {
            throw ResponsiveAudioSceneMutationGateError
                .automaticBoundaryDurabilityPending
        }
        guard controllerIsReady, activeGenerations.isEmpty else {
            throw ResponsiveAudioSceneMutationGateError.authoredAudioUnavailable
        }
        guard generation < UInt64.max else {
            throw ResponsiveAudioSceneMutationGateError.authoredAudioUnavailable
        }
        generation += 1
        activeGenerations.insert(generation)
        return Token(generation: generation)
    }

    /// Returns true when the caller must defer controller access until the last
    /// admitted scene transaction has finished its audio follow-up.
    public mutating func deferPhaseIfNeeded(
        _ phase: ResponsiveInteractionAudioPhase
    ) -> Bool {
        guard hasActiveResponsiveSceneMutation else { return false }
        deferredPhase = phase
        return true
    }

    /// Captures only generation-bound semantic intent and concrete controller
    /// identity. The callback's prebuilt Journey action is never stored.
    public mutating func receiveAutomaticBoundary(
        controllerIdentifier: ObjectIdentifier
    ) -> AutomaticBoundaryAdmission {
        if hasActiveResponsiveSceneMutation {
            if let deferredAutomaticBoundaryControllerIdentifier {
                return deferredAutomaticBoundaryControllerIdentifier
                    == controllerIdentifier ? .deferred : .rejected
            }
            deferredAutomaticBoundaryControllerIdentifier =
                controllerIdentifier
            return .deferred
        }
        guard pendingAutomaticBoundary == nil,
              let intent = makeAutomaticBoundaryIntent(
                  controllerIdentifier: controllerIdentifier
              ) else {
            return .rejected
        }
        pendingAutomaticBoundary = intent
        return .admitted(intent)
    }

    /// Releases responsive scene admission only for the exact boundary
    /// generation that became durable (or was explicitly abandoned by a
    /// fail-closed owner).
    @discardableResult
    public mutating func finishAutomaticBoundary(
        _ token: AutomaticBoundaryToken
    ) -> Bool {
        guard pendingAutomaticBoundary?.token == token else { return false }
        pendingAutomaticBoundary = nil
        return true
    }

    /// Lifecycle replacement and persistence failure use this only after the
    /// physical transport has already been stopped.
    @discardableResult
    public mutating func cancelAutomaticBoundary() -> Bool {
        let hadBoundary = pendingAutomaticBoundary != nil
            || deferredAutomaticBoundaryControllerIdentifier != nil
        pendingAutomaticBoundary = nil
        deferredAutomaticBoundaryControllerIdentifier = nil
        return hadBoundary
    }

    /// Coalesces repeated lifecycle callbacks to the latest valid timestamp.
    /// The caller may pause the transport immediately, but must not enqueue the
    /// returned snapshot until this intent is released.
    public mutating func deferSuspensionIfNeeded(
        atEpochMillis: Int64
    ) -> Bool {
        guard hasActiveResponsiveSceneMutation else { return false }
        deferredSuspensionEpochMillis = max(
            deferredSuspensionEpochMillis ?? 0,
            atEpochMillis
        )
        return true
    }

    /// Delivers deferred semantic intent only after the admitted responsive
    /// scene transaction has completed. JourneyModel uses this callback as the
    /// sole snapshot-materialization seam, so an invalid or duplicate token
    /// cannot flush intent early.
    @discardableResult
    public mutating func finish(
        _ token: Token,
        materialize: (DeferredIntents) -> Void
    ) -> Bool {
        guard activeGenerations.remove(token.generation) != nil else {
            return false
        }
        let automaticBoundary: AutomaticBoundaryIntent?
        if let controllerIdentifier =
            deferredAutomaticBoundaryControllerIdentifier,
           pendingAutomaticBoundary == nil {
            automaticBoundary = makeAutomaticBoundaryIntent(
                controllerIdentifier: controllerIdentifier
            )
            pendingAutomaticBoundary = automaticBoundary
        } else {
            automaticBoundary = nil
        }
        let intents = DeferredIntents(
            phase: deferredPhase,
            suspensionEpochMillis: deferredSuspensionEpochMillis,
            automaticBoundary: automaticBoundary
        )
        deferredPhase = nil
        deferredSuspensionEpochMillis = nil
        deferredAutomaticBoundaryControllerIdentifier = nil
        guard intents.phase != nil
                || intents.suspensionEpochMillis != nil
                || intents.automaticBoundary != nil else {
            return false
        }
        materialize(intents)
        return true
    }


    private mutating func makeAutomaticBoundaryIntent(
        controllerIdentifier: ObjectIdentifier
    ) -> AutomaticBoundaryIntent? {
        guard automaticBoundaryGeneration < UInt64.max else { return nil }
        automaticBoundaryGeneration += 1
        return AutomaticBoundaryIntent(
            token: AutomaticBoundaryToken(
                generation: automaticBoundaryGeneration
            ),
            controllerIdentifier: controllerIdentifier
        )
    }
}
