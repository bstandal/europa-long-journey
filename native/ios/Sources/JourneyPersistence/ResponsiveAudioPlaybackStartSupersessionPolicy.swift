import Foundation
import ContentKit

/// The authored material covered by one explicit user choice to start sound.
/// Persistence receipts and repository revisions may rotate around this
/// lease; a different package generation or authored program may not inherit
/// it.
public struct ResponsiveAudioPlaybackStartLease: Equatable, Sendable {
    public let chapterID: ChapterID
    public let packageID: PackageID
    public let packageManifestDigest: String
    public let beatID: BeatID
    public let programID: ResponsiveAudioProgramID
    public let programScope: ResponsiveAudioProgramScope

    public init(
        chapterID: ChapterID,
        packageID: PackageID,
        packageManifestDigest: String,
        beatID: BeatID,
        programID: ResponsiveAudioProgramID,
        programScope: ResponsiveAudioProgramScope
    ) {
        self.chapterID = chapterID
        self.packageID = packageID
        self.packageManifestDigest = packageManifestDigest
        self.beatID = beatID
        self.programID = programID
        self.programScope = programScope
    }
}

/// A failed start may be retried by the current caller only when a controller
/// rebind superseded the operation. Lifecycle suspension and authored start
/// failures remain explicit stops.
public enum ResponsiveAudioPlaybackStartSupersessionPolicy {
    public static func shouldRetry(
        didStart: Bool,
        callerIsCancelled: Bool,
        operationLifecycleToken: UUID?,
        currentLifecycleToken: UUID,
        suspensionIsActive: Bool
    ) -> Bool {
        guard !didStart,
              !callerIsCancelled,
              !suspensionIsActive,
              let operationLifecycleToken else {
            return false
        }
        return operationLifecycleToken != currentLifecycleToken
    }
}

/// Carries one explicit sound choice across a controller replacement only
/// while the exact authored route remains current. The app supplies the
/// opaque route authorization; this policy cannot weaken its equality.
public enum ResponsiveAudioPlaybackStartContinuationPolicy {
    public enum Decision: Equatable, Sendable {
        case stop
        case awaitAuthority
        case retry
    }

    /// Decides whether an explicit choice can survive a controller
    /// replacement. An ordered Journey transition is a hard boundary: an old
    /// choice can wait for package-authority replacement, but never for a
    /// world, visit or beat transition.
    public static func decide<Authorization: Equatable>(
        expectedAuthorization: Authorization,
        currentAuthorization: Authorization?,
        callerIsCancelled: Bool,
        suspensionIsActive: Bool,
        orderedTransitionIsInFlight: Bool,
        authorityPreparationIsInFlight: Bool,
        authorityRestoreIsInFlight: Bool,
        acceptedAuthorityMatchesDesired: Bool,
        runtimeTransitionIsInactive: Bool
    ) -> Decision {
        guard !callerIsCancelled,
              !suspensionIsActive,
              !orderedTransitionIsInFlight,
              currentAuthorization == expectedAuthorization else {
            return .stop
        }
        if authorityPreparationIsInFlight || authorityRestoreIsInFlight {
            return .awaitAuthority
        }
        guard acceptedAuthorityMatchesDesired,
              runtimeTransitionIsInactive else {
            return .stop
        }
        return .retry
    }

}

public enum ResponsiveAudioPlaybackStartAdmission: Equatable, Sendable {
    case startPausedTransport
    case acceptProtectedCurrentPlayback
    case failClosedUnprotectedPlayback
}

/// A repeated start is successful without touching the transport only when
/// the already-playing controller is still protected by the exact durable
/// authority and crash-cursor writer that admitted it.
public enum ResponsiveAudioPlaybackStartAdmissionPolicy {
    public static func decide(
        controllerIsPlaying: Bool,
        controllerIsCurrent: Bool,
        sessionProgramAndAuthorityAreCurrent: Bool,
        lifecycleIsCurrent: Bool,
        suspensionIsActive: Bool,
        runtimeTransitionIsInactive: Bool,
        cursorPumpIsRunning: Bool,
        cursorPumpDidFailClosed: Bool,
        sidecarSessionIsCurrent: Bool,
        durableSnapshotIsCurrent: Bool
    ) -> ResponsiveAudioPlaybackStartAdmission {
        guard controllerIsPlaying else { return .startPausedTransport }
        guard controllerIsCurrent,
              sessionProgramAndAuthorityAreCurrent,
              lifecycleIsCurrent,
              !suspensionIsActive,
              runtimeTransitionIsInactive,
              cursorPumpIsRunning,
              !cursorPumpDidFailClosed,
              sidecarSessionIsCurrent,
              durableSnapshotIsCurrent else {
            return .failClosedUnprotectedPlayback
        }
        return .acceptProtectedCurrentPlayback
    }
}
