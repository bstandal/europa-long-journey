import ContentKit
import ExperiencePreferences
import Foundation

public enum SemanticHapticPulseKind: String, Equatable, Sendable {
    case transient
    case continuous
}

public struct SemanticHapticPulse: Equatable, Sendable {
    public let kind: SemanticHapticPulseKind
    public let relativeTimeSeconds: Double
    public let durationSeconds: Double
    public let intensity: Double
    public let sharpness: Double

    public init(
        kind: SemanticHapticPulseKind,
        relativeTimeSeconds: Double,
        durationSeconds: Double = 0,
        intensity: Double,
        sharpness: Double
    ) {
        self.kind = kind
        self.relativeTimeSeconds = relativeTimeSeconds
        self.durationSeconds = durationSeconds
        self.intensity = intensity
        self.sharpness = sharpness
    }
}

public enum SemanticHapticPatternError: Error, Equatable, Sendable {
    case emptyPattern(HapticSemantic)
    case invalidPulse(HapticSemantic, index: Int)
}

/// A closed baseline vocabulary for causal, gesture-driven haptics. Authored
/// timeline haptics can still set their own intensity and sharpness; this
/// profile is used when a durable Journey action emits only its semantic.
public enum FranchiseSemanticHapticProfile {
    public static func pulses(for semantic: HapticSemantic) -> [SemanticHapticPulse] {
        switch semantic {
        case .contact:
            [
                .init(
                    kind: .transient,
                    relativeTimeSeconds: 0,
                    intensity: 0.34,
                    sharpness: 0.58
                ),
            ]
        case .drag:
            [
                .init(
                    kind: .continuous,
                    relativeTimeSeconds: 0,
                    durationSeconds: 0.045,
                    intensity: 0.18,
                    sharpness: 0.24
                ),
            ]
        case .resistance:
            [
                .init(
                    kind: .continuous,
                    relativeTimeSeconds: 0,
                    durationSeconds: 0.07,
                    intensity: 0.58,
                    sharpness: 0.16
                ),
            ]
        case .transfer:
            [
                .init(
                    kind: .transient,
                    relativeTimeSeconds: 0,
                    intensity: 0.31,
                    sharpness: 0.42
                ),
                .init(
                    kind: .transient,
                    relativeTimeSeconds: 0.042,
                    intensity: 0.44,
                    sharpness: 0.5
                ),
            ]
        case .break:
            [
                .init(
                    kind: .transient,
                    relativeTimeSeconds: 0,
                    intensity: 0.72,
                    sharpness: 0.2
                ),
                .init(
                    kind: .transient,
                    relativeTimeSeconds: 0.052,
                    intensity: 0.82,
                    sharpness: 0.78
                ),
            ]
        case .seal:
            [
                .init(
                    kind: .transient,
                    relativeTimeSeconds: 0,
                    intensity: 0.68,
                    sharpness: 0.28
                ),
                .init(
                    kind: .transient,
                    relativeTimeSeconds: 0.075,
                    intensity: 0.38,
                    sharpness: 0.18
                ),
            ]
        }
    }

    public static func validate() throws {
        for semantic in HapticSemantic.allCasesForValidation {
            let pulses = pulses(for: semantic)
            guard !pulses.isEmpty else {
                throw SemanticHapticPatternError.emptyPattern(semantic)
            }
            for (index, pulse) in pulses.enumerated() {
                let durationIsValid = switch pulse.kind {
                case .transient:
                    pulse.durationSeconds == 0
                case .continuous:
                    pulse.durationSeconds > 0 && pulse.durationSeconds <= 0.25
                }
                guard pulse.relativeTimeSeconds.isFinite,
                      pulse.relativeTimeSeconds >= 0,
                      pulse.relativeTimeSeconds <= 0.25,
                      pulse.durationSeconds.isFinite,
                      durationIsValid,
                      pulse.intensity.isFinite,
                      (0 ... 1).contains(pulse.intensity),
                      pulse.sharpness.isFinite,
                      (0 ... 1).contains(pulse.sharpness) else {
                    throw SemanticHapticPatternError.invalidPulse(semantic, index: index)
                }
            }
        }
    }
}

extension HapticSemantic {
    fileprivate static let allCasesForValidation: [HapticSemantic] = [
        .contact,
        .drag,
        .resistance,
        .transfer,
        .break,
        .seal,
    ]
}

/// Prevents gesture updates from creating an unbounded haptic event stream.
/// Suppression is per semantic, so a consequence seal is never swallowed by
/// a drag or transfer that happened immediately before it.
public struct SemanticHapticRateLimiter: Equatable, Sendable {
    private var lastEmissionBySemantic: [HapticSemantic: UInt64] = [:]

    public init() {}

    public mutating func shouldEmit(
        _ semantic: HapticSemantic,
        atUptimeNanoseconds now: UInt64
    ) -> Bool {
        let minimumInterval = Self.minimumIntervalNanoseconds(for: semantic)
        if let last = lastEmissionBySemantic[semantic],
           now >= last,
           now - last < minimumInterval {
            return false
        }
        lastEmissionBySemantic[semantic] = now
        return true
    }

    public mutating func reset() {
        lastEmissionBySemantic.removeAll(keepingCapacity: true)
    }

    public static func minimumIntervalNanoseconds(for semantic: HapticSemantic) -> UInt64 {
        switch semantic {
        case .drag:
            50_000_000
        case .contact, .transfer:
            75_000_000
        case .resistance:
            120_000_000
        case .break, .seal:
            180_000_000
        }
    }
}

/// Generation gate shared by lifecycle callbacks and engine reset handlers.
/// A late callback from an engine owned before suspension cannot invalidate a
/// replacement engine created after the scene becomes active again.
public struct SemanticHapticLifecycleGate: Equatable, Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var isSuspended = false

    public init() {}

    @discardableResult
    public mutating func suspend() -> Bool {
        guard !isSuspended else { return false }
        isSuspended = true
        advanceGeneration()
        return true
    }

    @discardableResult
    public mutating func resume() -> Bool {
        guard isSuspended else { return false }
        isSuspended = false
        advanceGeneration()
        return true
    }

    public mutating func registerEngine() -> UInt64? {
        guard !isSuspended else { return nil }
        advanceGeneration()
        return generation
    }

    public func ownsEngine(generation candidate: UInt64) -> Bool {
        !isSuspended && generation == candidate
    }

    private mutating func advanceGeneration() {
        generation = generation == UInt64.max ? 0 : generation + 1
    }
}

#if os(iOS)
import CoreHaptics
import Dispatch

@MainActor
public final class NativeSemanticHapticTransport {
    public private(set) var hapticsAreAvailable = false
    public private(set) var routingPolicy: ExperienceAudioRoutingPolicy

    private var engine: CHHapticEngine?
    private var limiter = SemanticHapticRateLimiter()
    private var lifecycleGate = SemanticHapticLifecycleGate()

    public init(preferences: ExperiencePreferences = .standard) {
        routingPolicy = ExperienceAudioRoutingPolicy(preferences: preferences)
        hapticsAreAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    public func applyPreferences(_ preferences: ExperiencePreferences) {
        let wasEnabled = routingPolicy.semanticHapticsAreEnabled
        routingPolicy = ExperienceAudioRoutingPolicy(preferences: preferences)
        if wasEnabled, !routingPolicy.semanticHapticsAreEnabled {
            stop()
        } else if !wasEnabled, routingPolicy.semanticHapticsAreEnabled {
            limiter.reset()
        }
    }

    /// Plays a causal haptic after its corresponding Journey action has been
    /// durably committed. A hardware or engine failure never changes the
    /// historical action, its visual consequence or its accessible form.
    public func play(_ semantic: HapticSemantic) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard routingPolicy.semanticHapticsAreEnabled,
              !lifecycleGate.isSuspended,
              hapticsAreAvailable,
              limiter.shouldEmit(semantic, atUptimeNanoseconds: now) else {
            return
        }

        do {
            try FranchiseSemanticHapticProfile.validate()
            let activeEngine: CHHapticEngine
            if let engine {
                activeEngine = engine
            } else {
                let created = try CHHapticEngine()
                created.playsHapticsOnly = true
                guard let generation = lifecycleGate.registerEngine() else {
                    return
                }
                created.stoppedHandler = { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.invalidateEngineIfOwned(generation: generation)
                    }
                }
                created.resetHandler = { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.invalidateEngineIfOwned(generation: generation)
                    }
                }
                engine = created
                activeEngine = created
            }
            try activeEngine.start()
            let events = FranchiseSemanticHapticProfile.pulses(for: semantic).map { pulse in
                CHHapticEvent(
                    eventType: pulse.kind == .transient
                        ? .hapticTransient
                        : .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: Float(pulse.intensity)
                        ),
                        CHHapticEventParameter(
                            parameterID: .hapticSharpness,
                            value: Float(pulse.sharpness)
                        ),
                    ],
                    relativeTime: pulse.relativeTimeSeconds,
                    duration: pulse.durationSeconds
                )
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try activeEngine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            engine?.stop()
            engine = nil
            limiter.reset()
            hapticsAreAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        }
    }

    public func stop() {
        engine?.stop()
        engine = nil
        limiter.reset()
    }

    /// Joins the same idempotent suspension episode as responsive audio.
    public func quiesceForSuspension() {
        guard lifecycleGate.suspend() else { return }
        stop()
    }

    /// Engines are rebuilt lazily by the first post-resume causal pulse.
    public func resumeAfterSuspension() {
        guard lifecycleGate.resume() else { return }
        hapticsAreAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        limiter.reset()
    }

    private func invalidateEngineIfOwned(generation: UInt64) {
        guard lifecycleGate.ownsEngine(generation: generation) else { return }
        engine?.stop()
        engine = nil
        limiter.reset()
        hapticsAreAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }
}
#endif
