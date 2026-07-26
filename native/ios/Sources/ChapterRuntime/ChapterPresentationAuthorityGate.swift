public enum ChapterPresentationAuthorityGate {
    public static func admitsPresentation<Identity: Equatable>(
        expectedIdentity: Identity,
        sessionIdentity: Identity?,
        runtimeIsReady: Bool
    ) -> Bool {
        runtimeIsReady && sessionIdentity == expectedIdentity
    }

    public static func admitsInput<Identity: Equatable>(
        expectedIdentity: Identity,
        sessionIdentity: Identity?,
        runtimeIsReady: Bool,
        presentationIsReady: Bool
    ) -> Bool {
        presentationIsReady
            && admitsPresentation(
                expectedIdentity: expectedIdentity,
                sessionIdentity: sessionIdentity,
                runtimeIsReady: runtimeIsReady
            )
    }
}

/// The transition state that must remain inactive before a chapter runtime
/// may accept a new user action. Ordinary journal writes are deliberately not
/// represented: an already admitted scene transaction owns that durability
/// boundary until it finishes.
public enum ChapterRuntimeInputAdmissionPolicy {
    public struct State: Equatable, Sendable {
        public let restorationIsInFlight: Bool
        public let persistenceIsLocked: Bool
        public let authorityPreparationIsInFlight: Bool
        public let authorityTransitionIsInFlight: Bool
        public let authorityRestoreIsInFlight: Bool
        public let orderedTransitionIsInFlight: Bool
        public let chapterTransitionIsPending: Bool

        public init(
            restorationIsInFlight: Bool,
            persistenceIsLocked: Bool,
            authorityPreparationIsInFlight: Bool,
            authorityTransitionIsInFlight: Bool,
            authorityRestoreIsInFlight: Bool,
            orderedTransitionIsInFlight: Bool,
            chapterTransitionIsPending: Bool
        ) {
            self.restorationIsInFlight = restorationIsInFlight
            self.persistenceIsLocked = persistenceIsLocked
            self.authorityPreparationIsInFlight =
                authorityPreparationIsInFlight
            self.authorityTransitionIsInFlight =
                authorityTransitionIsInFlight
            self.authorityRestoreIsInFlight = authorityRestoreIsInFlight
            self.orderedTransitionIsInFlight = orderedTransitionIsInFlight
            self.chapterTransitionIsPending = chapterTransitionIsPending
        }
    }

    public static func runtimeTransitionIsInactive(_ state: State) -> Bool {
        !state.restorationIsInFlight
            && !state.persistenceIsLocked
            && !state.authorityPreparationIsInFlight
            && !state.authorityTransitionIsInFlight
            && !state.authorityRestoreIsInFlight
            && !state.orderedTransitionIsInFlight
            && !state.chapterTransitionIsPending
    }

    public static func admits<Identity: Equatable>(
        expectedIdentity: Identity,
        currentIdentity: Identity?,
        state: State
    ) -> Bool {
        currentIdentity == expectedIdentity
            && runtimeTransitionIsInactive(state)
    }
}

/// Invalidates activation work that suspended before it could claim the route
/// generation. Tickets are process-local and never enter saved state.
public struct ChapterRouteActivationRequestFence: Equatable, Sendable {
    public struct Ticket: Equatable, Sendable {
        fileprivate let generation: UInt64
    }

    private var generation: UInt64 = 0

    public init() {}

    public mutating func begin() -> Ticket {
        generation &+= 1
        return Ticket(generation: generation)
    }

    public func isCurrent(_ ticket: Ticket) -> Bool {
        ticket.generation == generation
    }

    public mutating func invalidate() {
        generation &+= 1
    }
}
