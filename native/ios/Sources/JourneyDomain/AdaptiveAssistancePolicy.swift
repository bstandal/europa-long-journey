import Foundation

/// Durable assistance phases for direct interaction with the authored world.
///
/// The phases describe presentation and input tolerance only. They do not
/// carry an `InteractionAction` and therefore cannot complete historical work.
public enum AdaptiveAssistanceTier: String, Codable, CaseIterable, Hashable, Sendable {
    case diegetic
    case strengthenedDiegetic
    case actionCue
    case stabilizedInput
    case semanticStep
}

public enum AdaptiveAssistanceError: Error, Equatable, Sendable {
    case negativeElapsedMillis
    case invalidCueWordCount(Int)
    case invalidDurableState
}

/// A fallback action phrase that is short enough to remain beside the acted
/// object instead of becoming an instruction panel.
public struct AdaptiveAssistanceCue: Codable, Hashable, Sendable {
    public let text: String

    public init(_ text: String) throws {
        let normalized = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let wordCount = normalized.split(separator: " ").count
        guard (1 ... 4).contains(wordCount) else {
            throw AdaptiveAssistanceError.invalidCueWordCount(wordCount)
        }
        self.text = normalized
    }

    private enum CodingKeys: String, CodingKey {
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedText = try container.decode(String.self, forKey: .text)
        do {
            try self.init(decodedText)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription: "An adaptive assistance cue must contain one to four words"
            )
        }
    }
}

/// The minimum durable information required to resume invisible assistance at
/// the same point after process termination.
public struct AdaptiveAssistanceState: Codable, Hashable, Sendable {
    public private(set) var tier: AdaptiveAssistanceTier
    public private(set) var hesitationMillis: Int64
    public private(set) var missCount: Int

    public init() {
        tier = .diegetic
        hesitationMillis = 0
        missCount = 0
    }

    private init(
        tier: AdaptiveAssistanceTier,
        hesitationMillis: Int64,
        missCount: Int
    ) throws {
        guard hesitationMillis >= 0,
              missCount >= 0,
              tier == AdaptiveAssistancePolicy.tier(
                  hesitationMillis: hesitationMillis,
                  missCount: missCount
              ) else {
            throw AdaptiveAssistanceError.invalidDurableState
        }
        self.tier = tier
        self.hesitationMillis = hesitationMillis
        self.missCount = missCount
    }

    public var isStructurallyValid: Bool {
        hesitationMillis >= 0
            && missCount >= 0
            && tier == AdaptiveAssistancePolicy.tier(
                hesitationMillis: hesitationMillis,
                missCount: missCount
            )
    }

    private enum CodingKeys: String, CodingKey {
        case tier
        case hesitationMillis
        case missCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTier = try container.decode(
            AdaptiveAssistanceTier.self,
            forKey: .tier
        )
        let decodedHesitation = try container.decode(
            Int64.self,
            forKey: .hesitationMillis
        )
        let decodedMissCount = try container.decode(Int.self, forKey: .missCount)
        do {
            try self.init(
                tier: decodedTier,
                hesitationMillis: decodedHesitation,
                missCount: decodedMissCount
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .tier,
                in: container,
                debugDescription: "Adaptive assistance state was not canonical"
            )
        }
    }

    fileprivate mutating func advance(by elapsedMillis: Int64) throws {
        guard elapsedMillis >= 0 else {
            throw AdaptiveAssistanceError.negativeElapsedMillis
        }
        let (sum, overflow) = hesitationMillis.addingReportingOverflow(elapsedMillis)
        hesitationMillis = overflow ? Int64.max : sum
        resolveTier()
    }

    fileprivate mutating func registerMiss() {
        if missCount < Int.max {
            missCount += 1
        }
        resolveTier()
    }

    fileprivate mutating func registerPurposefulContact() {
        hesitationMillis = 0
        missCount = 0
        tier = .diegetic
    }

    private mutating func resolveTier() {
        tier = AdaptiveAssistancePolicy.tier(
            hesitationMillis: hesitationMillis,
            missCount: missCount
        )
    }
}

public enum AdaptiveAssistanceEvent: Codable, Hashable, Sendable {
    case hesitationElapsed(Int64)
    case missedAttempt
    case purposefulContact
}

/// Presentation-only output. `automaticallyCompletesInteraction` is a fixed
/// false invariant: the semantic step is an offered user action, never replay
/// or auto-advance authority.
public struct AdaptiveAssistanceDirective: Hashable, Sendable {
    public let tier: AdaptiveAssistanceTier
    public let strengthensDiegeticSignals: Bool
    public let actionCue: AdaptiveAssistanceCue?
    public let hitTargetScale: Double
    public let stabilizesInput: Bool
    public let offersSemanticStep: Bool
    public let automaticallyCompletesInteraction: Bool

    fileprivate init(
        tier: AdaptiveAssistanceTier,
        strengthensDiegeticSignals: Bool,
        actionCue: AdaptiveAssistanceCue?,
        hitTargetScale: Double,
        stabilizesInput: Bool,
        offersSemanticStep: Bool
    ) {
        self.tier = tier
        self.strengthensDiegeticSignals = strengthensDiegeticSignals
        self.actionCue = actionCue
        self.hitTargetScale = hitTargetScale
        self.stabilizesInput = stabilizesInput
        self.offersSemanticStep = offersSemanticStep
        automaticallyCompletesInteraction = false
    }
}

public enum AdaptiveAssistancePolicy {
    public static let strengthenedDiegeticThresholdMillis: Int64 = 3_000
    public static let actionCueThresholdMillis: Int64 = 6_000
    public static let actionCueMinimumMissCount = 2
    public static let stabilizedInputThresholdMillis: Int64 = 10_000
    public static let stabilizedInputMinimumMissCount = 3
    public static let semanticStepThresholdMillis: Int64 = 15_000
    public static let expandedHitTargetScale = 1.3

    @discardableResult
    public static func reduce(
        state: inout AdaptiveAssistanceState,
        event: AdaptiveAssistanceEvent,
        cue: AdaptiveAssistanceCue? = nil
    ) throws -> AdaptiveAssistanceDirective {
        switch event {
        case let .hesitationElapsed(elapsedMillis):
            try state.advance(by: elapsedMillis)
        case .missedAttempt:
            state.registerMiss()
        case .purposefulContact:
            state.registerPurposefulContact()
        }
        return directive(for: state, cue: cue)
    }

    public static func directive(
        for state: AdaptiveAssistanceState,
        cue: AdaptiveAssistanceCue? = nil
    ) -> AdaptiveAssistanceDirective {
        let semanticStepIsEligible =
            state.hesitationMillis >= semanticStepThresholdMillis
        let actionCueIsEligible =
            (
                state.hesitationMillis >= actionCueThresholdMillis
                    && state.missCount >= actionCueMinimumMissCount
            )
            || semanticStepIsEligible
        let stabilizedInputIsEligible =
            state.hesitationMillis >= stabilizedInputThresholdMillis
            || state.missCount >= stabilizedInputMinimumMissCount

        return AdaptiveAssistanceDirective(
            tier: state.tier,
            strengthensDiegeticSignals:
                state.hesitationMillis >= strengthenedDiegeticThresholdMillis,
            actionCue: actionCueIsEligible ? cue : nil,
            hitTargetScale: stabilizedInputIsEligible ? expandedHitTargetScale : 1,
            stabilizesInput: stabilizedInputIsEligible,
            offersSemanticStep: semanticStepIsEligible
        )
    }

    fileprivate static func tier(
        hesitationMillis: Int64,
        missCount: Int
    ) -> AdaptiveAssistanceTier {
        if hesitationMillis >= semanticStepThresholdMillis {
            return .semanticStep
        }
        if hesitationMillis >= stabilizedInputThresholdMillis
            || missCount >= stabilizedInputMinimumMissCount {
            return .stabilizedInput
        }
        if hesitationMillis >= actionCueThresholdMillis
            && missCount >= actionCueMinimumMissCount {
            return .actionCue
        }
        if hesitationMillis >= strengthenedDiegeticThresholdMillis {
            return .strengthenedDiegetic
        }
        return .diegetic
    }
}
