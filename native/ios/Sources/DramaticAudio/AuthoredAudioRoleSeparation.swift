import ContentKit
import Foundation

/// The private transport components derived from one signed authored
/// timeline. These names are persistence identities, not user-facing audio
/// controls.
public enum AuthoredAudioComponent: String, Codable, CaseIterable, Hashable,
    Sendable {
    case narration
    case nonSpeaking = "non-speaking"
    case wholeMix = "whole-mix"
}

public enum AuthoredAudioRoleSeparationError: Error, Equatable, Sendable {
    case invalidTimeline
    case missingNarration
    case nonSpeakingHapticsHaveNoTimingEvent
    case cuePartitionMismatch
    case hapticAuthorityMismatch
}

/// A lossless role partition of one already-verified manifest timeline.
///
/// Every authored event keeps its original cue ID, sample range, role, asset
/// path and timeline ID. Narration owns no haptics. The non-speaking component
/// owns every remaining event (including authored silence) and the one original
/// haptic sequence. A caller must retain the original whole timeline as the
/// fail-closed fallback when this proof cannot be constructed.
public struct AuthoredAudioRoleSeparation: Equatable, Sendable {
    public let narration: AudioTimeline
    public let nonSpeaking: AudioTimeline?

    public init(validating timeline: AudioTimeline) throws {
        do {
            try timeline.validate()
        } catch {
            throw AuthoredAudioRoleSeparationError.invalidTimeline
        }

        let narrationEvents = timeline.events.filter {
            $0.role == .narration
        }
        guard !narrationEvents.isEmpty else {
            throw AuthoredAudioRoleSeparationError.missingNarration
        }
        let remainingEvents = timeline.events.filter {
            $0.role != .narration
        }

        let narration = AudioTimeline(
            id: timeline.id,
            sampleRate: timeline.sampleRate,
            events: narrationEvents,
            haptics: []
        )
        do {
            try narration.validate()
        } catch {
            throw AuthoredAudioRoleSeparationError.invalidTimeline
        }

        let nonSpeaking: AudioTimeline?
        if remainingEvents.isEmpty {
            guard timeline.haptics.isEmpty else {
                // AudioTimeline intentionally forbids an eventless timeline.
                // Inventing a silence event here would create production
                // authority that is absent from the signed manifest.
                throw AuthoredAudioRoleSeparationError
                    .nonSpeakingHapticsHaveNoTimingEvent
            }
            nonSpeaking = nil
        } else {
            let candidate = AudioTimeline(
                id: timeline.id,
                sampleRate: timeline.sampleRate,
                events: remainingEvents,
                haptics: timeline.haptics
            )
            do {
                try candidate.validate()
            } catch {
                throw AuthoredAudioRoleSeparationError.invalidTimeline
            }
            nonSpeaking = candidate
        }

        let projectedCueIDs = narration.events.map(\.cueID)
            + (nonSpeaking?.events.map(\.cueID) ?? [])
        guard projectedCueIDs.count == timeline.events.count,
              Set(projectedCueIDs).count == projectedCueIDs.count,
              Set(projectedCueIDs) == Set(timeline.events.map(\.cueID)) else {
            throw AuthoredAudioRoleSeparationError.cuePartitionMismatch
        }
        guard narration.haptics.isEmpty,
              (nonSpeaking?.haptics ?? []).count == timeline.haptics.count,
              nonSpeaking?.haptics == timeline.haptics || timeline.haptics.isEmpty else {
            throw AuthoredAudioRoleSeparationError.hapticAuthorityMismatch
        }

        self.narration = narration
        self.nonSpeaking = nonSpeaking
    }

    public var componentTimelines: [AuthoredAudioComponent: AudioTimeline] {
        var result: [AuthoredAudioComponent: AudioTimeline] = [
            .narration: narration,
        ]
        if let nonSpeaking {
            result[.nonSpeaking] = nonSpeaking
        }
        return result
    }

    /// Read-only review reuses the verified cue partition but strips the one
    /// active-scene haptic authority. It does not add, move or duplicate an
    /// event and therefore cannot replay interaction feedback.
    public var reviewComponentTimelines: [
        AuthoredAudioComponent: AudioTimeline
    ] {
        var result: [AuthoredAudioComponent: AudioTimeline] = [
            .narration: narration,
        ]
        if let nonSpeaking {
            result[.nonSpeaking] = AudioTimeline(
                id: nonSpeaking.id,
                sampleRate: nonSpeaking.sampleRate,
                events: nonSpeaking.events,
                haptics: []
            )
        }
        return result
    }
}

/// One boundary policy shared by active scenes and read-only review. It keeps
/// accessibility suppression out of mixer preferences: a suppressed speaking
/// component is physically held, while the independently verified
/// non-speaking component may continue.
public enum AuthoredAudioPlaybackBoundaryPolicy {
    public static func componentsToPlay(
        available: Set<AuthoredAudioComponent>,
        usesVerifiedRoleSeparation: Bool,
        suppressesNarration: Bool,
        narrationIsEnabled: Bool
    ) -> Set<AuthoredAudioComponent> {
        if usesVerifiedRoleSeparation {
            var result: Set<AuthoredAudioComponent> = []
            if available.contains(.nonSpeaking) {
                result.insert(.nonSpeaking)
            }
            if !suppressesNarration,
               narrationIsEnabled,
               available.contains(.narration) {
                result.insert(.narration)
            }
            return result
        }
        guard !suppressesNarration,
              available.contains(.wholeMix) else { return [] }
        return [.wholeMix]
    }

    public static func componentToPauseForVoiceOver(
        available: Set<AuthoredAudioComponent>,
        usesVerifiedRoleSeparation: Bool
    ) -> AuthoredAudioComponent? {
        let component: AuthoredAudioComponent =
            usesVerifiedRoleSeparation ? .narration : .wholeMix
        return available.contains(component) ? component : nil
    }
}

public enum AuthoredAudioCursorRecovery: Equatable, Sendable {
    case current(Int64)
    case migratedLegacy(Int64)

    public var cursorSample: Int64 {
        switch self {
        case let .current(cursorSample), let .migratedLegacy(cursorSample):
            cursorSample
        }
    }
}

/// Schema-2 crash checkpoint for one independently clocked authored component.
/// The generic authority remains the app's exact signed route authority; the
/// codec never weakens or interprets it.
public struct AuthoredAudioCursorCheckpoint<Authority>: Codable, Equatable,
    Sendable where Authority: Codable & Equatable & Sendable {
    public static var currentSchemaVersion: Int { 2 }

    public let schemaVersion: Int
    public let authority: Authority
    public let component: AuthoredAudioComponent
    public let cursorSample: Int64

    public init(
        authority: Authority,
        component: AuthoredAudioComponent,
        cursorSample: Int64
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.authority = authority
        self.component = component
        self.cursorSample = cursorSample
    }
}

private struct LegacyAuthoredAudioCursorCheckpoint<Authority>: Codable
    where Authority: Codable {
    let authority: Authority
    let cursorSample: Int64
}

public enum AuthoredAudioCursorCheckpointCodec {
    public static func encode<Authority>(
        authority: Authority,
        component: AuthoredAudioComponent,
        cursorSample: Int64,
        maximumCursorSample: Int64
    ) throws -> Data where Authority: Codable & Equatable & Sendable {
        guard cursorSample >= 0,
              maximumCursorSample >= 0,
              cursorSample <= maximumCursorSample else {
            throw AuthoredAudioCursorCheckpointCodecError.invalidCursor
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(AuthoredAudioCursorCheckpoint(
            authority: authority,
            component: component,
            cursorSample: cursorSample
        ))
    }

    /// Decodes schema 2 or the former unversioned whole-mix checkpoint. A
    /// legacy cursor is valid for either derived component because all
    /// components previously shared the same absolute 48 kHz timeline domain.
    /// Values beyond a shorter derived component mean that component had
    /// already ended and are clamped only during this one migration.
    public static func recover<Authority>(
        from data: Data,
        expectedAuthority: Authority,
        component: AuthoredAudioComponent,
        maximumCursorSample: Int64
    ) -> AuthoredAudioCursorRecovery?
        where Authority: Codable & Equatable & Sendable {
        guard maximumCursorSample >= 0 else { return nil }
        let decoder = JSONDecoder()
        if let current = try? decoder.decode(
            AuthoredAudioCursorCheckpoint<Authority>.self,
            from: data
        ) {
            guard current.schemaVersion
                    == AuthoredAudioCursorCheckpoint<Authority>
                        .currentSchemaVersion,
                  current.authority == expectedAuthority,
                  current.component == component,
                  current.cursorSample >= 0,
                  current.cursorSample <= maximumCursorSample else {
                return nil
            }
            return .current(current.cursorSample)
        }
        guard let legacy = try? decoder.decode(
            LegacyAuthoredAudioCursorCheckpoint<Authority>.self,
            from: data
        ), legacy.authority == expectedAuthority,
           legacy.cursorSample >= 0 else {
            return nil
        }
        return .migratedLegacy(
            min(legacy.cursorSample, maximumCursorSample)
        )
    }
}

public enum AuthoredAudioCursorCheckpointCodecError: Error, Equatable,
    Sendable {
    case invalidCursor
}
