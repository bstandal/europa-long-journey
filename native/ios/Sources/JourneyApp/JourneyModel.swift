import CommerceKit
import ChapterRuntime
import ContentDelivery
import ContentKit
#if DEBUG
import CryptoKit
#endif
import DramaticAudio
import ExperiencePreferences
import Foundation
import JourneyContent
import JourneyDomain
import JourneyPersistence
import ProgressStore
import ReleaseDiscovery
import SceneRuntime
import SwiftUI

struct LockedRoad: Identifiable, Equatable {
    let chapter: ChapterIndexEntry

    var id: ChapterID { chapter.id }
}

struct OfflineChapterRequest: Identifiable, Equatable {
    let chapterID: ChapterID
    let packageID: PackageID

    var id: ChapterID { chapterID }
}

enum PurchasePresentationState: Equatable {
    case idle
    case purchasing
    case restoring
    case pending
    case failed(String)
}

enum ExperiencePreferencesPresentationFailure: Equatable {
    case recoveredDefaults
    case readOnlyUntilAppUpdate
    case storageUnavailable

    var message: String {
        switch self {
        case .recoveredDefaults:
            "Narration, sound and haptics returned to their defaults."
        case .readOnlyUntilAppUpdate:
            "Settings are read-only until this app is updated."
        case .storageUnavailable:
            "Changes cannot be saved."
        }
    }

    var blocksWrites: Bool {
        switch self {
        case .recoveredDefaults:
            false
        case .readOnlyUntilAppUpdate, .storageUnavailable:
            true
        }
    }
}

enum DownloadSurfaceFailure: Equatable {
    case configurationUnavailable
    case requiresNewerApp
    case statusUnavailable
    case command(String)

    var message: String {
        switch self {
        case .configurationUnavailable:
            "Chapter downloads are not available."
        case .requiresNewerApp:
            "Update the app to read the newer chapter installation already on this iPhone."
        case .statusUnavailable:
            "Installed chapters could not be checked. Nothing already on this iPhone changed."
        case let .command(message):
            message
        }
    }
}

struct ChapterRuntimeRouteIdentity: Equatable, Hashable {
    let persistenceAuthority: PersistenceAuthorityFence.Receipt
    let contentRevision: UInt64
    let chapterID: ChapterID
    let packageID: PackageID
    let packageManifestDigest: String
    let beatID: BeatID
    let viewportCropID: String
    let reduceMotion: Bool
}

enum JourneyChapterRuntimeError: Error, Equatable {
    case routeAuthorityUnavailable
    case routeAuthorityChanged
    case authoredAudioUnavailable
    case persistenceUnavailable
}

enum ResponsiveAudioPhysicalPauseReason: String, Equatable, Sendable {
    case sceneInactive
    case sceneBackground
    case interruption
    case audioRouteChange
    case cursorDurabilityFailure
}

struct ResponsiveAudioPhysicalPauseEvent: Equatable, Sendable {
    let generation: UInt64
    let reason: ResponsiveAudioPhysicalPauseReason
}

struct ResponsiveAudioPlaybackStartEpoch: Equatable, Sendable {
    let physicalPauseGeneration: UInt64?
}

enum FutureReleasePresentationState: Equatable {
    case unavailable
    case availableToDownload
    case awaitingResume
    case preparing
    case ready
    case failed
}

struct FutureReleasePresentationFailure: Equatable {
    enum Scope: Equatable {
        case allReleases
        case release(ReleaseID)
    }

    let scope: Scope
    let message: String

    func applies(to releaseID: ReleaseID) -> Bool {
        switch scope {
        case .allReleases:
            true
        case let .release(failedReleaseID):
            failedReleaseID == releaseID
        }
    }
}

private enum FutureReleaseCatalogAuthorityError: Error {
    case noncanonicalRetainedCatalog
    case retainedIdentityMismatch
}

private enum JourneySaveMigrationIntegrationError: Error {
    case verifiedLaunchAuthorityUnavailable
    case authorityChangedDuringRestoration
    case persistenceMutationDuringRestoration
    case exactPackageReversionUnavailable(PackageID)
    case saveRollbackUncertain
}

#if DEBUG
private enum JourneyUITestInjectedPersistenceError: Error, Sendable {
    case suspensionAppend
    case authorityPauseCompletion
    case orderedExitPauseCompletion
}

private struct JourneyUITestResponsiveAudioBindingContext {
    let plan: ResponsiveAudioRestorationPlan
    let restoration: JourneyRestoration
    let resolver: any OfflineAudioAssetResolving
}

/// A process-local, one-shot fault boundary for the signed-runtime UI tests.
/// The shipping committer still calls the real `ProgressStore`; this actor
/// withholds exactly one `suspendChapter` append before any journal write so
/// retry exercises the model's genuine restore path without corrupting disk.
private actor JourneyUITestSuspensionAppendFault {
    private var failureIsArmed = true

    func shouldFail(_ request: ConditionalJourneyAppendRequest) -> Bool {
        guard failureIsArmed,
              case .suspendChapter = request.event.action else {
            return false
        }
        failureIsArmed = false
        return true
    }
}
#endif

private extension DownloadPresentationCommand {
    var requestsPaidLaunchContent: Bool {
        switch self {
        case .requestSinglePackage, .requestDownloadAll,
             .resumeApplicationQueue, .retryFailedPackage:
            true
        case .requestQueuePauseAfterCurrentPackage, .removeFailedPackage,
             .refreshInstalledChapters, .discardStaleQueue:
            false
        }
    }
}

@MainActor
protocol JourneyCausalHapticTransport: AnyObject {
    func applyPreferences(_ preferences: ExperiencePreferences)
    func play(_ semantic: HapticSemantic)
    func quiesceForSuspension()
    func resumeAfterSuspension()
}

extension NativeSemanticHapticTransport: JourneyCausalHapticTransport {}

@MainActor
final class JourneyModel: ObservableObject {
    private enum OrderedRouteAuthorityBoundary {
        case chapterOpen
        case beatAdvance
        case worldExit

        func matches(_ action: JourneyAction) -> Bool {
            switch (self, action) {
            case (.chapterOpen, .selectChapter),
                 (.chapterOpen, .beginChapter),
                 (.chapterOpen, .beginAuthoredChapter),
                 (.beatAdvance, .enterBeat),
                 (.beatAdvance, .enterAuthoredBeat),
                 (.worldExit, .showWorld),
                 (.worldExit, .completeAuthoredChapter):
                true
            default:
                false
            }
        }

        static func inferred(
            from actions: [JourneyAction]
        ) -> OrderedRouteAuthorityBoundary? {
            if actions.contains(where: { Self.worldExit.matches($0) }) {
                return .worldExit
            }
            if actions.contains(where: { Self.beatAdvance.matches($0) }) {
                return .beatAdvance
            }
            if actions.contains(where: { Self.chapterOpen.matches($0) }) {
                return .chapterOpen
            }
            return nil
        }
    }

    private struct PendingAction {
        let action: JourneyAction
        let prologuePreviewRevision: UInt64
        let completionID: UUID?
        let durableCommitHook: (@MainActor () -> Void)?
        let responsiveAudioJournalCapture:
            ResponsiveAudioJournalCapture?

        init(
            action: JourneyAction,
            prologuePreviewRevision: UInt64,
            completionID: UUID? = nil,
            durableCommitHook: (@MainActor () -> Void)? = nil,
            responsiveAudioJournalCapture:
                ResponsiveAudioJournalCapture? = nil
        ) {
            self.action = action
            self.prologuePreviewRevision = prologuePreviewRevision
            self.completionID = completionID
            self.durableCommitHook = durableCommitHook
            self.responsiveAudioJournalCapture =
                responsiveAudioJournalCapture
        }
    }

    /// Process-local timing receipt for the exact responsive-audio snapshot
    /// written into the Journey journal. Uptime nanoseconds are deliberately
    /// never serialized; they only keep the live 250 ms crash-cursor deadline
    /// continuous across the journal-to-sidecar authority handoff.
    private struct ResponsiveAudioJournalCapture: Equatable {
        let snapshot: ResponsiveAudioProgramSnapshot
        let capturedAtMonotonicNanoseconds: UInt64
    }

    private struct ProloguePreview {
        let revision: UInt64
        let progress: Double
    }

    private struct PendingDurabilityCallback {
        let succeeded: @MainActor () -> Void
        let failed: @MainActor () -> Void
    }

    private struct ResponsiveAudioBindingIdentity: Equatable, Sendable {
        let contentRevision: UInt64?
        let chapterID: ChapterID
        let packageID: PackageID
        let beatID: BeatID
        let manifestDigest: String?
        let programID: ResponsiveAudioProgramID
        let programScope: ResponsiveAudioProgramScope
    }

    private struct ResponsiveAudioPlaybackStartAuthority: Equatable {
        let contentRevision: UInt64?
        let chapterID: ChapterID
        let packageID: PackageID
        let beatID: BeatID
        let programID: ResponsiveAudioProgramID
        let scope: ResponsiveAudioProgramScope
        let chapterOpenNonce: UUID
        let sessionGeneration: UInt64
        let lifecycleToken: UUID
    }

    /// The exact historical route that received an explicit sound choice.
    /// Persistence receipts and repository revisions may rotate while an
    /// unrelated content authority is accepted; authored route identity may
    /// not.
    private typealias ResponsiveAudioExplicitStartAuthorization =
        ResponsiveAudioPlaybackStartLease

    private struct PreparedPersistenceRestoration {
        let store: ProgressStore
        let committer: DurableJourneyCommitter
        let restoration: JourneyRestoration
        let saveMigrationPreparation: PreparedSaveMigrationRestoration

        func rollbackCommittedSaveMigrationIfNeeded() async throws {
            try await saveMigrationPreparation
                .rollbackCommittedSaveMigrationIfNeeded()
        }
    }

    @Published private(set) var state = JourneyState.initial
    @Published private(set) var isRestoring = true
    @Published private(set) var persistenceFailure: String?
    @Published private(set) var responsiveAudioFailure: String?
    @Published private(set) var responsiveAudioPhysicalPauseEvent:
        ResponsiveAudioPhysicalPauseEvent?
#if DEBUG
    @Published private(set) var responsiveAudioBindingDiagnosticForTesting = "not-started"
    @Published private(set) var responsiveAudioControllerBindingForTesting: UInt64 = 0
    @Published private(set) var responsiveAudioRouteChangeDiagnosticForTesting = "none"
    @Published private(set) var responsiveAudioDurableCursorForTesting:
        ResponsiveAudioProgramSnapshot?
    private var responsiveAudioStartAdmissionDiagnosticForTesting = "none"
    @Published private var responsiveAudioCursorFailureDiagnosticForTesting =
        "none"
    @Published private var responsiveAudioPresentationSyncDiagnosticForTesting =
        "none"
    @Published private(set) var contentAuthorityBarrierDiagnosticForTesting =
        "none"
    @Published private(set) var contentAuthorityAudioDiagnosticForTesting =
        "none"
    @Published private(set) var orderedExitAudioDiagnosticForTesting = "none"
    private var contentAuthorityBarrierInjectionDidRun = false
    private var contentAuthorityQuiesceFailureInjectionDidRun = false
    private var contentAuthorityForcedControllerSwapDidRun = false
    private var contentAuthorityAudioPreSnapshotForTesting:
        ResponsiveAudioProgramSnapshot?
    private var contentAuthorityAudioPartialSnapshotForTesting:
        NativeTimelineTransportSnapshot?
    private var contentAuthorityAudioCapturedSnapshotForTesting:
        ResponsiveAudioProgramSnapshot?
    private var contentAuthorityAudioFallbackSnapshotForTesting:
        ResponsiveAudioProgramSnapshot?
    private var contentAuthorityAudioBaselineSnapshotForTesting:
        ResponsiveAudioProgramSnapshot?
    private var contentAuthorityAudioCommittedSnapshotForTesting:
        ResponsiveAudioProgramSnapshot?
    private var contentAuthorityAudioSequenceBeforeForTesting: UInt64?
    private var contentAuthorityAudioSequenceAfterForTesting: UInt64?
    private var contentAuthorityAudioTransportPausedForTesting = false
    private var contentAuthorityAudioControllerSwappedForTesting = false
    private var contentAuthorityAudioSnapshotWasStaleForTesting = false
    private var contentAuthorityAudioAuditIsFinalForTesting = false
    private var orderedExitAudioFailureInjectionDidRun = false
    private var orderedExitAudioChapterIDForTesting: ChapterID?
    private var orderedExitAudioPreSnapshotForTesting:
        ResponsiveAudioProgramSnapshot?
    private var orderedExitAudioPartialSnapshotForTesting:
        NativeTimelineTransportSnapshot?
    private var orderedExitAudioBaselineSnapshotForTesting:
        ResponsiveAudioProgramSnapshot?
    private var orderedExitAudioFallbackSnapshotForTesting:
        ResponsiveAudioProgramSnapshot?
    private var orderedExitAudioCommittedSnapshotForTesting:
        ResponsiveAudioProgramSnapshot?
    private var orderedExitAudioSidecarSnapshotForTesting:
        ResponsiveAudioProgramSnapshot?
    private var orderedExitAudioCursorAuthorityForTesting:
        ResponsiveAudioCursorAuthority?
    private var orderedExitAudioSequenceBeforeForTesting: UInt64?
    private var orderedExitAudioSequenceAfterForTesting: UInt64?
    private var orderedExitAudioTransportPausedForTesting = false
    private var orderedExitAudioFallbackRecoveredForTesting = false
    private var orderedExitAudioControllerDiscardedForTesting = false
    private var orderedExitAudioCursorProtectionRetiredForTesting = false
    private var orderedExitAudioAuthorityRequestedForTesting = false
    private var orderedExitAudioAuthorityPublishedForTesting = false
    private var orderedExitAudioActorRecoveryQueriedForTesting = false
    private var orderedExitForcedControllerSwapDidRun = false
    private var orderedExitAudioSuccessorControllerIDForTesting:
        ObjectIdentifier?
    private var orderedExitAudioBindingIdentityForTesting:
        ResponsiveAudioBindingIdentity?
    private var orderedExitAudioLifecycleTokenForTesting: UUID?
    private var orderedExitPreinstallSuccessorWasArmedForTesting = false
    private var orderedExitAudioAuditIsFinalForTesting = false
    private var responsiveAudioAuthorityProbeTransportForTesting:
        (controllerID: ObjectIdentifier, transport: NativeTimelineTransport)?
    private var responsiveAudioAuthoritySwapContextForTesting:
        JourneyUITestResponsiveAudioBindingContext?
    @Published private(set) var suspensionPersistenceRetryDiagnosticForTesting =
        "none"
    private var suspensionPersistenceRetryInjectionDidRun = false
    @Published private(set) var orderedRecoveryEpochProbeIsHoldingForTesting =
        false
    private var orderedRecoveryEpochProbeSecondEpisodeID: UInt64?
    private var orderedRecoveryEpochProbeReachedReservationGate = false
    private var orderedRecoveryEpochProbeHoldContinuation:
        CheckedContinuation<Void, Never>?
    private lazy var suspensionAppendFaultForTesting:
        JourneyUITestSuspensionAppendFault? = {
            guard ProcessInfo.processInfo.arguments.contains(
                "--ui-testing-suspension-persistence-retry"
            ) else { return nil }
            return JourneyUITestSuspensionAppendFault()
        }()

    var responsiveAudioRuntimeDiagnosticForTesting: String {
        let pauseReason = responsiveAudioPhysicalPauseEvent?.reason.rawValue
            ?? "none"
        let durableCursor = Self.responsiveAudioCursorDiagnostic(
            responsiveAudioDurableCursorForTesting
        )
        let journalCursor = Self.responsiveAudioCursorDiagnostic(
            committedState.activeChapter?.responsiveAudioSnapshot
        )
        let lifecycle = responsiveAudioLifecycleDiagnosticForTesting
        guard let controller = responsiveAudioController else {
            return "binding=\(responsiveAudioControllerBindingForTesting);playback=unbound;stage=none"
                + ";phase=none;durable=none;pending=none"
                + ";pause=\(pauseReason)"
                + ";liveCursor=none;durableCursor=\(durableCursor)"
                + ";journalCursor=\(journalCursor)"
                + ";route=\(responsiveAudioRouteChangeDiagnosticForTesting)"
                + ";startAdmission=\(responsiveAudioStartAdmissionDiagnosticForTesting)"
                + ";cursorFailure=\(responsiveAudioCursorFailureDiagnosticForTesting)"
                + ";presentationSync=\(responsiveAudioPresentationSyncDiagnosticForTesting)"
                + lifecycle
        }
        let liveCursor = Self.responsiveAudioCursorDiagnostic(
            controller.runtime.snapshot()
        )
        return "binding=\(responsiveAudioControllerBindingForTesting);playback="
            + (controller.runtime.isPlaying ? "playing" : "paused")
            + ";stage=\(controller.runtime.stage.rawValue)"
            + ";phase=\(controller.runtime.interactionPhase?.rawValue ?? "none")"
            + ";durable=\(committedState.activeChapter?.responsiveAudioSnapshot?.interactionPhase?.rawValue ?? "none")"
            + ";pending=\(pendingResponsiveAudioPhaseIntent?.rawValue ?? "none")"
            + ";pause=\(pauseReason)"
            + ";liveCursor=\(liveCursor);durableCursor=\(durableCursor)"
            + ";journalCursor=\(journalCursor)"
            + ";route=\(responsiveAudioRouteChangeDiagnosticForTesting)"
            + ";startAdmission=\(responsiveAudioStartAdmissionDiagnosticForTesting)"
            + ";cursorFailure=\(responsiveAudioCursorFailureDiagnosticForTesting)"
            + ";presentationSync=\(responsiveAudioPresentationSyncDiagnosticForTesting)"
            + lifecycle
    }

    var causalLifecycleStateDiagnosticForTesting: String {
        let route: String = switch committedState.route {
        case .prologue: "prologue"
        case .world: "world"
        case let .chapter(chapterID): "chapter:\(chapterID.rawValue)"
        }
        let episodeResult: String = switch suspensionEpisodeCoordinator
            .lastResult {
        case .some(.durable): "durable"
        case .some(.failed): "failed"
        case nil: "none"
        }
        func bit(_ value: Bool) -> Int { value ? 1 : 0 }
        return "route=\(route)"
            + ";accepted=r\(runtimeContentSnapshot?.revision ?? 0)"
            + ";desired=r\(desiredRuntimeContentSnapshot?.revision ?? 0)"
            + ";retry=\(bit(deferredContentAuthorityRetryIsPending))"
            + ";episode=\(suspensionEpisodeCoordinator.episodeID.map(String.init) ?? "none")"
            + ";episodeResult=\(episodeResult)"
            + ";physicalPause=\(bit(unresolvedResponsiveAudioPhysicalPauseEvent != nil))"
            + ";reservations=\(chapterRuntimeInputReservationGate.activeCount)"
            + ";restore=\(bit(isRestoring))"
            + ";lock=\(bit(persistenceIsLocked))"
            + ";ordered=\(bit(orderedJourneyTransitionTask != nil))"
            + ";chapterPending=\(bit(chapterTransitionIsPending))"
            + ";persistenceFailure=\(bit(persistenceFailure != nil))"
    }

    private var responsiveAudioLifecycleDiagnosticForTesting: String {
        let episodeResult: String = switch suspensionEpisodeCoordinator
            .lastResult {
        case .some(.durable): "durable"
        case .some(.failed): "failed"
        case nil: "none"
        }
        let failure = (responsiveAudioFailure ?? "none")
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "=", with: ":")
        return ";bindingState=\(responsiveAudioBindingDiagnosticForTesting)"
            + ";bindingTask=\(responsiveAudioBindingTask == nil ? "none" : "active")"
            + ";startTask=\(responsiveAudioPlaybackStartTask == nil ? "none" : "active")"
            + ";episode=\(suspensionEpisodeCoordinator.episodeID.map(String.init) ?? "none")"
            + ";episodeResult=\(episodeResult);audioFailure=\(failure)"
    }

    private static func responsiveAudioCursorDiagnostic(
        _ snapshot: ResponsiveAudioProgramSnapshot?
    ) -> String {
        guard let snapshot else { return "none" }
        return "\(snapshot.cursorSample)@\(snapshot.loopIteration)"
    }

    private static func responsiveAudioIdentityDiagnostic(
        _ snapshot: ResponsiveAudioProgramSnapshot?
    ) -> String {
        guard let snapshot else { return "none" }
        return "v\(snapshot.formatVersion)"
            + "|\(snapshot.programID.rawValue)"
            + "|\(snapshot.stage.rawValue)"
            + "|\(snapshot.interactionPhase?.rawValue ?? "none")"
            + "|\(snapshot.timelineID.rawValue)"
            + "|c\(snapshot.causalStage?.completedStageCount.description ?? "none")"
            + "|d\(snapshot.durableCompletionSequence?.description ?? "none")"
    }

    func persistenceRestoreDiagnosticForTesting() async -> String? {
        guard let committer else { return nil }
        return await committer.persistenceRestoreDiagnosticForTestingValue()
    }

    func releaseOrderedRecoveryEpochProbeForTesting() {
        guard contentAuthorityRecoverySecondSuspensionProbeIsEnabled,
              orderedRecoveryEpochProbeIsHoldingForTesting else { return }
        orderedRecoveryEpochProbeIsHoldingForTesting = false
        orderedRecoveryEpochProbeHoldContinuation?.resume()
        orderedRecoveryEpochProbeHoldContinuation = nil
    }
#endif
    @Published private(set) var entitlementSnapshot: EntitlementSnapshot?
    @Published private(set) var lockedRoad: LockedRoad?
    @Published private(set) var purchaseState = PurchasePresentationState.idle
    @Published private(set) var storeDisplayPrice: String?
    @Published private(set) var chapterCursor: ChapterCursor?
    @Published private(set) var contentFailure: String?
    @Published private(set) var chapterTransitionIsPending = false
    @Published private(set) var experiencePreferences = ExperiencePreferences.standard
    @Published private(set) var experiencePreferencesFailure: ExperiencePreferencesPresentationFailure?
    @Published private(set) var experiencePreferenceWriteIsPending = false
    @Published private(set) var downloadPresentation: DownloadPresentationProjection?
    @Published private(set) var downloadFailure: DownloadSurfaceFailure?
    @Published private(set) var downloadCommandIsPending = false
    @Published private(set) var offlineChapterRequest: OfflineChapterRequest?
    @Published private(set) var releaseWorldFocus: ReleaseDeepLinkIntent?
    @Published private(set) var futureReleaseDownloadSnapshot:
        FutureReleaseDownloadSnapshot?
    @Published private(set) var retainedFutureReleaseCatalogEntries:
        [ReleaseCatalogEntry] = []
    @Published private(set) var futureReleaseContentSnapshot =
        VerifiedFutureReleaseContentSnapshot.empty
    @Published private(set) var futureReleaseFailure:
        FutureReleasePresentationFailure?
    @Published private(set) var futureReleaseCommandIsPending = false

    private let previewReducer = JourneyReducer()
    private let storageURL: URL
    private let experiencePreferencesStorageURL: URL
    private let causalHapticTransport: any JourneyCausalHapticTransport
    private let downloadClient: JourneyDownloadClient?
    private let contentClient: JourneyContentClient?
    private let futureReleaseClient: JourneyFutureReleaseClient?
    private let releaseDiscovery: ReleaseDiscoveryApplicationModel?
    private var store: ProgressStore?
    private var experiencePreferencesStore: ExperiencePreferencesStore?
    private var committer: DurableJourneyCommitter?
    private var committedState = JourneyState.initial
    private var pendingActions: [PendingAction] = []
    private var pendingWriteCompletions: [
        UUID: CheckedContinuation<Void, Error>
    ] = [:]
    private var pendingDurabilityCallbacks: [
        UUID: PendingDurabilityCallback
    ] = [:]
    private var isDrainingWrites = false
    private var persistenceMutationBarrier =
        JourneyPersistenceMutationBarrier()
    private var persistenceIsLocked = true
    private var prologuePreviewRevision: UInt64 = 0
    private var prologuePreview: ProloguePreview?
    private let accessResolver = ChapterAccessResolver()
    private var responsiveAudioController: ResponsiveAudioProgramController?
    private var responsiveAudioCursorStore:
        ResponsiveAudioCursorCheckpointStore?
    private var responsiveAudioCursorSession:
        ResponsiveAudioCursorCheckpointSession?
    private var responsiveAudioCursorDurableSnapshot:
        ResponsiveAudioProgramSnapshot?
    private let responsiveAudioCursorPump =
        ResponsiveAudioCursorCheckpointPump()
    private var outgoingResponsiveAudioTail: ResponsiveAudioOutgoingTail?
    private var preQuiescedSuspensionAction: JourneyAction?
    private var preQuiescedSuspensionFailed = false
    private var pendingResponsiveAudioPhaseIntent:
        ResponsiveInteractionAudioPhase?
    /// The live transport may briefly leave its journalled waiting bed for a
    /// gesture response. This flag never enters JourneyState; lifecycle paths
    /// normalize it before producing a durable cursor.
    private var audioSessionLifecycleObserver:
        JourneyAudioSessionLifecycleObserver?
    private lazy var suspensionEpisodeCoordinator =
        JourneySuspensionEpisodeCoordinator(
            leaseFactory: { expiration in
                ApplicationSuspensionExecutionLease.begin(
                    expiration: expiration
                )
            },
            quiesce: { [weak self] trigger in
                self?.quiesceResponsiveAudioForSuspension(trigger)
            },
            flush: { [weak self] trigger in
                guard let self else { return }
                try await self.performSuspensionFlush(trigger: trigger)
            }
        )
    private var responsiveAudioBindingTask: Task<Void, Never>?
    private var responsiveAudioPlaybackStartTask: Task<Bool, Never>?
    private var responsiveAudioPlaybackStartID: UUID?
    private var responsiveAudioPlaybackStartLifecycleToken: UUID?
    private var responsiveAudioPlaybackStartAuthorization:
        ResponsiveAudioExplicitStartAuthorization?
    private var responsiveAudioLifecycleToken = UUID()
    private var responsiveAudioPhysicalPauseGeneration: UInt64 = 0
    private var orderedJourneyTransitionTask: Task<Void, Never>?
    private var responsiveAudioBindingIdentity: ResponsiveAudioBindingIdentity?
    private var responsiveAudioSceneMutationGate =
        ResponsiveAudioSceneMutationGate()
    private var responsiveAudioSceneMutationWaiters: [
        CheckedContinuation<Void, Never>
    ] = []
    private var chapterRuntimeInputReservationGate =
        ChapterRuntimeInputReservationGate()
    private var chapterRuntimeInputReservationIdentities: [
        ChapterRuntimeInputReservationGate.Token:
            ChapterRuntimeRouteIdentity
    ] = [:]
    private struct ChapterRuntimeInputReservationWaiter {
        let excludedToken: ChapterRuntimeInputReservationGate.Token?
        let continuation: CheckedContinuation<Void, Never>
    }
    private var chapterRuntimeInputReservationWaiters: [
        ChapterRuntimeInputReservationWaiter
    ] = []
    private struct ChapterRuntimePhysicalPauseGate: Equatable {
        let event: ResponsiveAudioPhysicalPauseEvent
        let persistenceAuthority: PersistenceAuthorityFence.Receipt
        let contentRevision: UInt64
        let chapterID: ChapterID
        let packageID: PackageID
        let packageManifestDigest: String
        let beatID: BeatID

        func matches(_ identity: ChapterRuntimeRouteIdentity) -> Bool {
            persistenceAuthority == identity.persistenceAuthority
                && contentRevision == identity.contentRevision
                && chapterID == identity.chapterID
                && packageID == identity.packageID
                && packageManifestDigest == identity.packageManifestDigest
                && beatID == identity.beatID
        }
    }
    private var chapterRuntimePhysicalPauseGate:
        ChapterRuntimePhysicalPauseGate?
    /// Route-neutral ownership for the newest physical pause until either the
    /// exact successor chapter has rebuilt after its durable flush or a world
    /// flush has completed with no chapter to refresh.
    private var unresolvedResponsiveAudioPhysicalPauseEvent:
        ResponsiveAudioPhysicalPauseEvent?
    private var responsiveAudioAutomaticBoundaryWaiters: [
        CheckedContinuation<Void, Never>
    ] = []
    private var commerceClient: JourneyCommerceClient?
    private var entitlementObservationTask: Task<Void, Never>?
    private var downloadObservationTask: Task<Void, Never>?
    private var contentObservationTask: Task<Void, Never>?
    private var futureReleaseObservationTask: Task<Void, Never>?
    private var chapterCoordinator: ChapterCoordinator?
    private var runtimeContentSnapshot: VerifiedJourneyContentSnapshot?
    private var desiredRuntimeContentSnapshot: VerifiedJourneyContentSnapshot?
    private var desiredFutureReleaseContentSnapshot =
        VerifiedFutureReleaseContentSnapshot.empty
    private var authorityTransitionTask: Task<Void, Never>?
    private var authorityTransitionPreparationTask: Task<Void, Never>?
    private var deferredContentAuthorityRetryIsPending = false
    private var authorityRestoreIsInFlight = false
    private let saveMigrationRegistry: SaveMigrationRegistry
    private var activeFutureReleaseID: ReleaseID?
    private var postRestoreUnavailableChapterFallbackIsPending = false
    private var lastCommittedSequence: UInt64 = 0
    private var persistenceAuthorityFence = PersistenceAuthorityFence()
#if DEBUG
    private var developmentFirstFarmers: DevelopmentFirstFarmersEnvelope?
#endif

    init(
        applicationSupportURL: URL? = nil,
        causalHapticTransport: (any JourneyCausalHapticTransport)? = nil,
        downloadClient suppliedDownloadClient: JourneyDownloadClient? = nil,
        contentClient suppliedContentClient: JourneyContentClient? = nil,
        futureReleaseClient: JourneyFutureReleaseClient? = nil,
        commerceClient suppliedCommerceClient: JourneyCommerceClient? = nil,
        releaseDiscovery: ReleaseDiscoveryApplicationModel? = nil,
        saveMigrationRegistry: SaveMigrationRegistry =
            JourneySaveMigrationRuntime.compiledRegistry,
        automaticallyBootstrap: Bool = true
    ) {
        let applicationSupport = applicationSupportURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        storageURL = applicationSupport.appendingPathComponent(
            "journey-progress-v1",
            isDirectory: true
        )
        responsiveAudioCursorStore = try? ResponsiveAudioCursorCheckpointStore(
            directoryURL: storageURL.appendingPathComponent(
                "responsive-audio-cursor-v1",
                isDirectory: true
            )
        )
        experiencePreferencesStorageURL = applicationSupport.appendingPathComponent(
            "experience-preferences-v1",
            isDirectory: true
        )
        self.causalHapticTransport = causalHapticTransport
            ?? NativeSemanticHapticTransport(preferences: .standard)
        let preparedPreferencesStore = try? ExperiencePreferencesStore(
            directoryURL: experiencePreferencesStorageURL
        )
        experiencePreferencesStore = preparedPreferencesStore

        var preparedDownloadClient = suppliedDownloadClient
        var preparedContentClient = suppliedContentClient
#if DEBUG
        if preparedDownloadClient == nil,
           ProcessInfo.processInfo.arguments.contains("--ui-testing-download-surface") {
            preparedDownloadClient = .developmentFixture()
        }
#endif
        var downloadConfigurationFailed = false
        if preparedDownloadClient == nil, let preparedPreferencesStore {
            do {
                let composition = try JourneyDownloadComposition.makeIfConfigured(
                    applicationSupportURL: applicationSupport,
                    preferencesStore: preparedPreferencesStore
                )
                preparedDownloadClient = composition?.downloadClient
                if preparedContentClient == nil {
                    preparedContentClient = composition?.contentClient
                }
            } catch {
                downloadConfigurationFailed = true
            }
        }
        downloadClient = preparedDownloadClient
        contentClient = preparedContentClient
        self.futureReleaseClient = futureReleaseClient
        self.releaseDiscovery = releaseDiscovery
        self.saveMigrationRegistry = saveMigrationRegistry
        if let initialContent = preparedContentClient?.initialSnapshot {
            runtimeContentSnapshot = initialContent
            desiredRuntimeContentSnapshot = initialContent
            chapterCoordinator = ChapterCoordinator(
                repository: initialContent.repository
            )
        }
        var preparedCommerceClient = suppliedCommerceClient
#if DEBUG
        if preparedCommerceClient == nil {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing-commerce-ready")
                || arguments.contains("--ui-testing-owned-downloads") {
                preparedCommerceClient = .developmentFixture(
                    initiallyOwned: arguments.contains("--ui-testing-owned-downloads")
                )
            }
        }
#endif
        commerceClient = preparedCommerceClient
        if downloadConfigurationFailed {
            downloadFailure = .configurationUnavailable
        }
#if DEBUG
        if preparedContentClient == nil {
            do {
            let envelope = try DevelopmentFirstFarmersAppContent.load()
            developmentFirstFarmers = envelope
            chapterCoordinator = ChapterCoordinator(repository: envelope.repository)
            } catch {
                developmentFirstFarmers = nil
            }
        }
#endif
        if automaticallyBootstrap {
            Task { @MainActor [weak self] in
                await self?.bootstrap()
            }
        }
    }

    var experiencePreferenceEditingIsDisabled: Bool {
        experiencePreferenceWriteIsPending
            || experiencePreferencesFailure?.blocksWrites == true
    }

    var downloadSurfaceIsConfigured: Bool { downloadClient != nil }

    var completeWorkPurchaseIsAvailable: Bool {
        commerceClient != nil
            && storeDisplayPrice != nil
            && downloadPresentation?.bootstrapState == .ready
            && downloadPresentation?.refreshFailure == nil
    }

    var completeWorkRestoreIsAvailable: Bool {
        commerceClient != nil
            && downloadPresentation?.bootstrapState == .ready
            && downloadPresentation?.refreshFailure == nil
    }

    var completeWorkIsOwned: Bool {
        return entitlementSnapshot?.grantsAccess(at: Date()) == true
    }

    /// Durable world entry points are projected from the authenticated
    /// installation ledger, never from the current CloudKit query. A route
    /// becomes playable only through `futureReleaseContentSnapshot`, which
    /// still requires the exact active generation and signed package.
    var retainedFutureReleaseWorldEntries: [ReleaseCatalogEntry] {
        let installedPackageIDs = Set(
            futureReleaseDownloadSnapshot?.currentInstalledPackageIDs ?? []
        )
        let verifiedReleaseIDs = Set(
            futureReleaseContentSnapshot.contentsByReleaseID.keys
        )
        let queuedPackageID = futureReleaseDownloadSnapshot.flatMap {
            Self.queuedFutureReleasePackageID(in: $0.installationState)
        }
        return retainedFutureReleaseCatalogEntries.filter {
            installedPackageIDs.contains($0.release.packageID)
                || verifiedReleaseIDs.contains($0.id)
                || queuedPackageID == $0.release.packageID
        }
    }

    var allowedDownloadCommands: Set<DownloadPresentationCommand> {
        Set((downloadPresentation?.allowedCommands ?? []).filter {
            !$0.requestsPaidLaunchContent || completeWorkIsOwned
        })
    }

#if DEBUG
    var journeyProgressFingerprintForTesting: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(committedState)) ?? Data()
        return "\(lastCommittedSequence):\(bytes.count):\(bytes.hashValue)"
    }

    var signedRuntimeProgressDigestForTesting: String {
        guard ProcessInfo.processInfo.arguments.contains(
            DevelopmentSignedRuntimeFixtureAppContent.launchArgument
        ) else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(committedState)) ?? Data()
        let digest = SHA256.hash(data: bytes).map {
            String(format: "%02x", $0)
        }.joined()
        return "\(lastCommittedSequence):\(digest)"
    }
#endif

    func setNarrationEnabled(_ enabled: Bool) {
        persistExperiencePreference(\.narrationEnabled, value: enabled)
    }

    func setScoreEnabled(_ enabled: Bool) {
        persistExperiencePreference(\.scoreEnabled, value: enabled)
    }

    func setSoundscapeEnabled(_ enabled: Bool) {
        persistExperiencePreference(\.soundscapeEnabled, value: enabled)
    }

    func setHapticsEnabled(_ enabled: Bool) {
        persistExperiencePreference(\.hapticsEnabled, value: enabled)
    }

    func setCellularDownloadsEnabled(_ enabled: Bool) {
        persistExperiencePreference(\.cellularDownloadsEnabled, value: enabled)
    }

    func setAutomaticDeepDiveDownloadsEnabled(_ enabled: Bool) {
        persistExperiencePreference(\.automaticDeepDiveDownloadsEnabled, value: enabled)
    }

    func dismissOfflineChapterRequest() {
        offlineChapterRequest = nil
    }

    func dismissDownloadFailure() {
        downloadFailure = nil
    }

    func retryDownloadStatus() {
        guard !downloadCommandIsPending, let downloadClient else { return }
        downloadCommandIsPending = true
        downloadFailure = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                downloadCommandIsPending = false
                pausePaidQueueAfterCurrentPackageIfNeeded()
            }
            do {
                applyDownloadSnapshot(try await downloadClient.bootstrap())
            } catch InstalledPackageIndexError.requiresNewerApp(_) {
                downloadFailure = .requiresNewerApp
            } catch {
                downloadFailure = .statusUnavailable
            }
        }
    }

    func performDownloadCommand(_ command: DownloadPresentationCommand) {
        guard !downloadCommandIsPending,
              let downloadClient,
              let projection = downloadPresentation,
              projection.allowedCommands.contains(command) else {
            return
        }
        if command.requestsPaidLaunchContent, !completeWorkIsOwned {
            downloadFailure = .command(
                "Unlock the complete work from a locked road before downloading these chapters."
            )
            return
        }

        downloadCommandIsPending = true
        downloadFailure = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                downloadCommandIsPending = false
                pausePaidQueueAfterCurrentPackageIfNeeded()
            }
            do {
                let outcome = try await downloadClient.execute(command)
                if case let .request(result) = outcome {
                    presentDownloadRequestResult(result)
                }
                applyDownloadSnapshot(await downloadClient.snapshot())
            } catch {
                downloadFailure = .command(
                    "The request did not complete. Check the chapter list before trying again."
                )
            }
        }
    }

    func previewPrologue(progress: Double) {
        guard !persistenceIsLocked else { return }
        guard state.route == .prologue, state.prologue.phase != .awakened else { return }

        // Finger movement is deliberately ephemeral. It may animate the road,
        // but it cannot reveal the world or publish another lasting consequence.
        state = prologuePreview(in: state, progress: progress)
        prologuePreviewRevision &+= 1
        prologuePreview = ProloguePreview(
            revision: prologuePreviewRevision,
            progress: state.prologue.traceProgress
        )
    }

    func persistPrologue(progress: Double) {
        send(.updatePrologueTrace(progress))
    }

    func completePrologue() {
        send(.completePrologue(FoundationCatalog.prologueWorldEffects))
    }

    @discardableResult
    func openReleaseDeepLink(_ intent: ReleaseDeepLinkIntent) -> Bool {
        guard !isRestoring,
              !persistenceIsLocked,
              persistenceFailure == nil,
              committedState.prologue.phase == .awakened,
              committedState.world.nodes.contains(where: {
                  $0.id == intent.worldNodeID && $0.visibility != .hidden
              }) else {
            return false
        }
        if committedState.route != .world {
            chapterTransitionIsPending = true
            enqueueOrderedJourneyTransition([.showWorld])
            // The release remains pending until the Journey journal has made
            // the world route authoritative. A termination between enqueue
            // and commit must not consume the notification tap.
            return false
        }
        releaseWorldFocus = intent
        contentFailure = nil
        return true
    }

    @discardableResult
    func focusRetainedFutureRelease(_ releaseID: ReleaseID) -> Bool {
        guard committedState.route == .world,
              !isRestoring,
              !persistenceIsLocked,
              persistenceFailure == nil,
              let entry = retainedFutureReleaseWorldEntries.first(where: {
                  $0.id == releaseID
              }),
              committedState.world.nodes.contains(where: {
                  $0.id == entry.placement.worldNodeID
                      && $0.visibility != .hidden
              }) else {
            return false
        }
        releaseWorldFocus = entry.deepLinkIntent
        contentFailure = nil
        return true
    }

    func futureReleaseAnnouncement(
        for releaseID: ReleaseID
    ) -> ReleaseAnnouncement? {
        releaseCatalogEntry(for: releaseID)?.announcement
    }

    func futureReleasePresentationState(
        for releaseID: ReleaseID
    ) -> FutureReleasePresentationState {
        if futureReleaseContentSnapshot.content(for: releaseID) != nil {
            return .ready
        }
        guard futureReleaseClient != nil,
              let entry = releaseCatalogEntry(for: releaseID) else {
            return .unavailable
        }
        if futureReleaseFailure?.applies(to: releaseID) == true {
            return .failed
        }
        if futureReleaseContentSnapshot.unavailableInstalledPackageIDs
            .contains(entry.release.packageID) {
            return .failed
        }
        guard let snapshot = futureReleaseDownloadSnapshot else {
            return .unavailable
        }
        switch snapshot.installationState {
        case let .failed(packageID, _, _) where packageID == entry.release.packageID:
            return .failed
        case let .starting(packageID, _, _)
            where packageID == entry.release.packageID:
            return .preparing
        case let .installing(packageID, _, _)
            where packageID == entry.release.packageID:
            return .preparing
        case let .pausingAfterCurrent(packageID, _, _)
            where packageID == entry.release.packageID:
            return .preparing
        case let .paused(nextPackageID, _, _)
            where nextPackageID == entry.release.packageID:
            return .awaitingResume
        case let .awaitingExplicitRestore(nextPackageID, _, _)
            where nextPackageID == entry.release.packageID:
            return .awaitingResume
        default:
            break
        }
        if snapshot.retainedReleaseIDs.contains(releaseID) {
            if snapshot.currentInstalledPackageIDs.contains(
                entry.release.packageID
            ) {
                return .failed
            }
        }
        return .availableToDownload
    }

    func futureReleaseFailureMessage(for releaseID: ReleaseID) -> String? {
        if futureReleaseFailure?.applies(to: releaseID) == true {
            return futureReleaseFailure?.message
        }
        guard futureReleaseContentSnapshot.content(for: releaseID) == nil,
              let entry = releaseCatalogEntry(for: releaseID) else {
            return nil
        }
        if futureReleaseContentSnapshot.unavailableInstalledPackageIDs
            .contains(entry.release.packageID)
            || futureReleaseDownloadSnapshot?.currentInstalledPackageIDs
                .contains(entry.release.packageID) == true {
            return "The installed historical route could not be verified."
        }
        if case let .failed(packageID, _, _)? =
            futureReleaseDownloadSnapshot?.installationState,
           packageID == entry.release.packageID {
            return "This historical route could not be prepared."
        }
        return nil
    }

    func requestFutureReleaseDownload(_ releaseID: ReleaseID) {
        guard !futureReleaseCommandIsPending,
              let futureReleaseClient else { return }
        futureReleaseCommandIsPending = true
        futureReleaseFailure = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { futureReleaseCommandIsPending = false }
            do {
                if futureReleaseDownloadSnapshot == nil {
                    let bootstrap = try await futureReleaseClient.bootstrap()
                    try applyFutureReleaseDownloadSnapshot(
                        bootstrap.download,
                        bootstrapEntries: bootstrap.retainedCatalogEntries
                    )
                    applyFutureReleaseContentSnapshot(bootstrap.content)
                    futureReleaseFailure = nil
                }
                if futureReleasePresentationState(for: releaseID)
                    == .awaitingResume {
                    try await futureReleaseClient.resumeQueue()
                    try applyFutureReleaseDownloadSnapshot(
                        try await futureReleaseClient.downloadSnapshot()
                    )
                    return
                }
                if futureReleasePresentationState(for: releaseID) == .failed {
                    do {
                        try await futureReleaseClient.retryFailedPackage()
                        try applyFutureReleaseDownloadSnapshot(
                            try await futureReleaseClient.downloadSnapshot()
                        )
                        return
                    } catch {
                        // A quarantined generation has no failed queue. Fall
                        // through to a fresh explicit request while the live
                        // authenticated Release remains available.
                    }
                }
                let result = try await futureReleaseClient.request(
                    releaseID,
                    .explicit
                )
                // A valid request seals its complete catalog entry before
                // network or installer gates run. Refresh the retained world
                // authority for every outcome, including a blocked transfer.
                try applyFutureReleaseDownloadSnapshot(
                    try await futureReleaseClient.downloadSnapshot()
                )
                switch result {
                case .started:
                    break
                case .noOperation(.alreadyCurrent):
                    applyFutureReleaseContentSnapshot(
                        try await futureReleaseClient.refreshContent()
                    )
                case .noOperation(.newerVersionRequiresNewerApp):
                    futureReleaseFailure = FutureReleasePresentationFailure(
                        scope: .release(releaseID),
                        message: "Update the app to open this historical route."
                    )
                case .noOperation(.requiresRuntime):
                    futureReleaseFailure = FutureReleasePresentationFailure(
                        scope: .release(releaseID),
                        message: "Update the app to open this historical route."
                    )
                case .noOperation(.notPublished), .noOperation(.unknownRelease):
                    futureReleaseFailure = FutureReleasePresentationFailure(
                        scope: .release(releaseID),
                        message: "This historical route is not available."
                    )
                case .blocked:
                    futureReleaseFailure = FutureReleasePresentationFailure(
                        scope: .release(releaseID),
                        message:
                            "This download cannot start with the current network settings."
                    )
                case .installerRejected:
                    futureReleaseFailure = FutureReleasePresentationFailure(
                        scope: .release(releaseID),
                        message:
                            "Another historical route is already being prepared."
                    )
                }
            } catch {
                futureReleaseFailure = FutureReleasePresentationFailure(
                    scope: .release(releaseID),
                    message: "This historical route could not be prepared."
                )
            }
        }
    }

    @discardableResult
    func openFutureRelease(_ releaseID: ReleaseID) -> Bool {
        guard !chapterTransitionIsPending,
              let content = futureReleaseContentSnapshot.content(
                  for: releaseID
              ), let chapter = content.repository.catalogEntry(
                  ChapterID(content.release.contentID)
              ), let authority = futureReleaseContentSnapshot
                  .chapterRuntimeAuthority(for: releaseID) else {
            return false
        }
        return openVerifiedChapter(
            chapter,
            authority: authority,
            futureReleaseID: releaseID
        )
    }

    func showWorld() {
        guard !chapterTransitionIsPending else { return }
        contentFailure = nil
        chapterTransitionIsPending = true
        enqueueOrderedJourneyTransition([.showWorld])
    }

    func showWorld(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard !chapterTransitionIsPending,
              let reservation = reserveChapterRuntimeInput(
                  expectedIdentity
              ) else { return }
        contentFailure = nil
        chapterTransitionIsPending = true
        enqueueOrderedJourneyTransition(
            [.showWorld],
            causalReservation: reservation
        )
    }

    /// A failed post-pause scene rebuild must not trap the reader behind the
    /// same gate that correctly blocks further chapter actions. This exit is
    /// admitted only by the exact gated route/event, waits the episode to
    /// finish, and returns to the world from the last durable chapter cursor.
    func showWorldRecoveringChapterFailure(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard !chapterTransitionIsPending,
              let recoveryEvent = pendingChapterRuntimePhysicalPauseEvent(
                  for: expectedIdentity
              ), unresolvedResponsiveAudioPhysicalPauseEvent
                == recoveryEvent,
              chapterRuntimeRouteAuthorityAdmitsInput(
                  expectedIdentity
              ) else {
            showWorld(expectedIdentity: expectedIdentity)
            return
        }
        contentFailure = nil
        chapterTransitionIsPending = true
        enqueueOrderedJourneyTransition(
            [.showWorld],
            physicalPauseRecoveryEvent: recoveryEvent
        )
    }

    /// The full-screen failure surface no longer owns the scene's crop and
    /// motion-specific route identity. Recover only when the route-neutral
    /// pause gate still belongs to the exact durable chapter authority.
    func showWorldRecoveringChapterFailure() {
        guard !chapterTransitionIsPending,
              let gate = chapterRuntimePhysicalPauseGate,
              unresolvedResponsiveAudioPhysicalPauseEvent == gate.event,
              chapterRuntimePhysicalPauseGateMatchesCurrentAuthority(gate)
        else {
            showWorld()
            return
        }
        contentFailure = nil
        chapterTransitionIsPending = true
        enqueueOrderedJourneyTransition(
            [.showWorld],
            physicalPauseRecoveryEvent: gate.event
        )
    }

    private func enqueueOrderedJourneyTransition(
        _ routeActions: [JourneyAction],
        routeAuthorityCommit: (@MainActor () -> Void)? = nil,
        authorityBoundary: OrderedRouteAuthorityBoundary? = nil,
        causalReservation:
            ChapterRuntimeInputReservationGate.Token? = nil,
        physicalPauseRecoveryEvent:
            ResponsiveAudioPhysicalPauseEvent? = nil,
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard orderedJourneyTransitionTask == nil, !routeActions.isEmpty else {
            chapterTransitionIsPending = false
            if let causalReservation {
                finishChapterRuntimeInputReservation(causalReservation)
            }
            completion?()
            return
        }
        let initialTransitionReservation:
            ChapterRuntimeInputReservationGate.Token?
        let waitsForPreexistingSuspension: Bool
        if let causalReservation {
            guard chapterRuntimeInputReservationGate.owns(
                causalReservation
            ) else {
                chapterTransitionIsPending = false
                completion?()
                return
            }
            initialTransitionReservation = causalReservation
            waitsForPreexistingSuspension = false
        } else if suspensionEpisodeCoordinator.episodeID == nil {
            guard let reservation = chapterRuntimeInputReservationGate
                .reserve() else {
                chapterTransitionIsPending = false
                completion?()
                return
            }
            initialTransitionReservation = reservation
            waitsForPreexistingSuspension = false
        } else {
            initialTransitionReservation = nil
            waitsForPreexistingSuspension = true
        }
        let resolvedAuthorityBoundary = authorityBoundary
            ?? OrderedRouteAuthorityBoundary.inferred(from: routeActions)
        responsiveAudioLifecycleToken = UUID()
        responsiveAudioPlaybackStartTask?.cancel()
        orderedJourneyTransitionTask = Task { @MainActor [weak self] in
            guard let self else {
                completion?()
                return
            }
            var transitionReservation = initialTransitionReservation
#if DEBUG
            var recoveryReservationWasAcquired = false
#endif
            defer {
                self.orderedJourneyTransitionTask = nil
                if let transitionReservation {
                    self.finishChapterRuntimeInputReservation(
                        transitionReservation
                    )
                }
#if DEBUG
                if recoveryReservationWasAcquired {
                    self.recordContentAuthorityBarrierMilestoneForTesting(
                        "transition:released"
                    )
                }
#endif
                self.chapterTransitionIsPending = false
                completion?()
                self.resumeDeferredContentAuthorityRetryIfPossible()
            }
            do {
                // A route exit or beat advance is ordered after every chapter
                // action that already crossed synchronous input admission.
                // New reservations are closed by orderedJourneyTransitionTask.
                await self.awaitChapterRuntimeInputReservationQuiescence(
                    excluding: transitionReservation
                )
                if waitsForPreexistingSuspension {
                    while true {
                        let awaitedEpisodeID = self
                            .suspensionEpisodeCoordinator.episodeID
                        let awaitedPhysicalPauseGeneration = self
                            .responsiveAudioPhysicalPauseGeneration
                        let result = await self.suspensionEpisodeCoordinator
                            .awaitCurrentFlush()
                        // Admission has remained closed through the ordered
                        // task. Reserve before inspecting the handoff: a later
                        // episode will now wait for the full route boundary.
                        guard let reservation = self
                            .chapterRuntimeInputReservationGate.reserve()
                        else {
                            throw JourneyChapterRuntimeError
                                .persistenceUnavailable
                        }
                        let handoffIsStable = self
                            .suspensionEpisodeCoordinator.episodeID
                                == awaitedEpisodeID
                            && self.responsiveAudioPhysicalPauseGeneration
                                == awaitedPhysicalPauseGeneration
                        if handoffIsStable {
                            transitionReservation = reservation
                            guard result == .durable
                                    || (physicalPauseRecoveryEvent != nil
                                        && result == .failed) else {
                                throw JourneyChapterRuntimeError
                                    .persistenceUnavailable
                            }
#if DEBUG
                            if physicalPauseRecoveryEvent != nil,
                               self
                                .contentAuthorityFailedPauseRecoveryProbeIsEnabled {
                                recoveryReservationWasAcquired = true
                                self
                                    .recordContentAuthorityBarrierMilestoneForTesting(
                                        "recovery:reserved"
                                    )
                            }
#endif
                            break
                        }
                        // A newer episode may already have crossed its initial
                        // reservation check. Release first so that flush can
                        // finish, then repeat the handoff against that epoch.
                        self.finishChapterRuntimeInputReservation(reservation)
                    }
                }
                if let physicalPauseRecoveryEvent {
                    guard self.unresolvedResponsiveAudioPhysicalPauseEvent
                            == physicalPauseRecoveryEvent,
                          self.chapterRuntimePhysicalPauseGate?.event
                            == physicalPauseRecoveryEvent else {
                        throw JourneyChapterRuntimeError.routeAuthorityChanged
                    }
                } else if self.preQuiescedSuspensionFailed {
                    throw JourneyChapterRuntimeError.authoredAudioUnavailable
                }
                if let startTask = self.responsiveAudioPlaybackStartTask {
                    _ = await startTask.value
                }
                let finalAudioAction = try await self
                    .prepareResponsiveAudioForOrderedExit()
                var actions: [JourneyAction] = []
                if let finalAudioAction { actions.append(finalAudioAction) }
                actions.append(contentsOf: routeActions)
                let routeAuthorityActionIndex = resolvedAuthorityBoundary
                    .flatMap { boundary in
                        actions.firstIndex(where: boundary.matches)
                    }
                if (routeAuthorityCommit != nil
                        || resolvedAuthorityBoundary != nil),
                   routeAuthorityActionIndex == nil {
                    throw JourneyChapterRuntimeError.routeAuthorityChanged
                }
                let durableRouteBoundaryCommit: (@MainActor () -> Void)?
                if routeAuthorityActionIndex != nil {
                    durableRouteBoundaryCommit = { [weak self] in
                        routeAuthorityCommit?()
                        guard let self else { return }
                        self.reconcilePhysicalPauseAtDurableRouteBoundary(
                            boundary: resolvedAuthorityBoundary,
                            resolvedRecoveryEvent:
                                physicalPauseRecoveryEvent
                        )
#if DEBUG
                        if physicalPauseRecoveryEvent != nil,
                           self.contentAuthorityFailedPauseRecoveryProbeIsEnabled,
                           case .world = self.committedState.route {
                            self
                                .recordContentAuthorityBarrierMilestoneForTesting(
                                    "world:durable"
                                )
                            if self
                                .contentAuthorityRecoverySecondSuspensionProbeIsEnabled {
                                self.orderedRecoveryEpochProbeReachedReservationGate =
                                    false
                                self.requestSuspension(.audioRouteChange)
                                self.orderedRecoveryEpochProbeSecondEpisodeID =
                                    self.suspensionEpisodeCoordinator.episodeID
                                self
                                    .recordContentAuthorityBarrierMilestoneForTesting(
                                        "e2:requested"
                                    )
                            }
                        }
#endif
                    }
                } else {
                    durableRouteBoundaryCommit = nil
                }
                try await self.enqueueAndAwaitDurability(
                    actions,
                    durableCommitHookAt: routeAuthorityActionIndex,
                    durableCommitHook: durableRouteBoundaryCommit
                )
#if DEBUG
                self.finalizeOrderedExitAudioDurabilityForTesting()
#endif
#if DEBUG
                if physicalPauseRecoveryEvent != nil,
                   self.contentAuthorityRecoverySecondSuspensionProbeIsEnabled {
                    while !self
                        .orderedRecoveryEpochProbeReachedReservationGate {
                        await Task.yield()
                    }
                    self.orderedRecoveryEpochProbeIsHoldingForTesting = true
                    self.recordContentAuthorityBarrierMilestoneForTesting(
                        "recovery:holding"
                    )
                    await withCheckedContinuation {
                        (continuation: CheckedContinuation<Void, Never>) in
                        self.orderedRecoveryEpochProbeHoldContinuation =
                            continuation
                    }
                    self.recordContentAuthorityBarrierMilestoneForTesting(
                        "probe:released"
                    )
                }
#endif
            } catch {
                self.canonicalizeAfterOrderedTransitionFailure()
#if DEBUG
                self.finalizeOrderedExitAudioFailureForTesting(
                    controllerWasDiscarded:
                        self.responsiveAudioController == nil
                )
#endif
                self.chapterTransitionIsPending = false
                if case .chapter = self.committedState.route {
                    self.contentFailure =
                        "Your exact place could not be saved. The chapter remains open."
                }
            }
        }
    }

    /// The write drain already revokes responsive outputs synchronously when
    /// persistence fails. For earlier ordered-preparation failures, publish
    /// only the canonical committed presentation. Do not stop whatever
    /// controller happens to be current here: an await may have allowed a
    /// newer content authority to install its own correctly fenced graph.
    private func canonicalizeAfterOrderedTransitionFailure() {
        state = committedState
        guard !persistenceIsLocked else { return }
        refreshChapterPresentation(bindResponsiveAudio: true)
    }

    private func prepareResponsiveAudioForOrderedExit() async throws
        -> JourneyAction? {
        await awaitResponsiveAudioSceneMutationQuiescence()
        guard !isRestoring, !persistenceIsLocked else {
            throw JourneyChapterRuntimeError.persistenceUnavailable
        }
        guard committedState.activeChapter?.responsiveAudioSessionIsActive == true else {
            responsiveAudioController?.stopWithoutPersisting()
            await retireResponsiveAudioCursorProtection()
            return nil
        }
        guard let controller = responsiveAudioController else {
            guard let snapshot = committedState.activeChapter?
                .responsiveAudioSnapshot else {
                throw JourneyChapterRuntimeError.authoredAudioUnavailable
            }
            await retireResponsiveAudioCursorProtection()
            return .endResponsiveAudioSession(snapshot)
        }
        let capturedLifecycleToken = responsiveAudioLifecycleToken

        // Close periodic capture before the physical route quiesce. A
        // transport failure can expose a later rendered cursor while the
        // controller rolls back; no pump tick may race that rejected cursor
        // into the recoverable sidecar.
        responsiveAudioCursorPump.stop()
        let finalSnapshot: ResponsiveAudioProgramSnapshot
        if controller.runtime.stage == .consequence,
           controller.runtime.isPlaying {
            let tail = try controller.relinquishConsequence(
                exitPolicy: controller.runtime.program.exitPolicy
            )
            finalSnapshot = controller.runtime.snapshot()
            retainOutgoingResponsiveAudioTail(tail)
        } else {
#if DEBUG
            beginOrderedExitAudioAuditForTesting(controller: controller)
            armOrderedExitTransportProbeForTesting(controller: controller)
#endif
            let exactFailureFallback = controller.runtime.snapshot()
            do {
                let action = try controller.quiesceForSuspension(.routeChange)
                guard case let .setResponsiveAudioSnapshot(snapshot) = action
                else {
                    throw JourneyChapterRuntimeError.authoredAudioUnavailable
                }
                finalSnapshot = snapshot
            } catch let initialError {
                // The transactional controller has restored c0, while the
                // native graph may already be paused at rejected c1. Stop the
                // graph synchronously, then read only the controller's exact
                // pre-call authority. No transport cursor participates in
                // this retry.
                controller.stopWithoutPersisting()
                do {
                    let fallbackAction = try controller
                        .quiesceForSuspension(.routeChange)
                    guard case let .setResponsiveAudioSnapshot(snapshot) =
                            fallbackAction,
                          snapshot == exactFailureFallback else {
                        throw JourneyChapterRuntimeError
                            .authoredAudioUnavailable
                    }
                    finalSnapshot = snapshot
#if DEBUG
                    markOrderedExitAudioFallbackRecoveredForTesting(snapshot)
#endif
                } catch {
                    let controllerWasDiscarded =
                        discardResponsiveAudioControllerIfStillOwned(
                            controller,
                            lifecycleToken: capturedLifecycleToken
                        )
                    await retireResponsiveAudioCursorProtection()
                    responsiveAudioFailure =
                        "The authored sound paused before its place could be verified."
#if DEBUG
                    finalizeOrderedExitAudioFailureForTesting(
                        controllerWasDiscarded: controllerWasDiscarded
                    )
#endif
                    throw initialError
                }
            }
        }
        await retireResponsiveAudioCursorProtection()
#if DEBUG
        await finalizeOrderedExitAudioSuccessForTesting(finalSnapshot)
#endif
        guard responsiveAudioController === controller,
              responsiveAudioLifecycleToken == capturedLifecycleToken,
              responsiveAudioControllerMatchesCurrentJourney() else {
            let controllerWasDiscarded =
                discardResponsiveAudioControllerIfStillOwned(
                    controller,
                    lifecycleToken: capturedLifecycleToken
                )
#if DEBUG
            finalizeOrderedExitAudioFailureForTesting(
                controllerWasDiscarded: controllerWasDiscarded
            )
#endif
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        return .endResponsiveAudioSession(finalSnapshot)
    }

    /// Discards only the controller generation captured by the caller. An
    /// await may have installed a successor controller or rotated the
    /// lifecycle while the old sidecar retired; that successor and its
    /// binding identity belong to the new generation and remain untouched.
    @discardableResult
    private func discardResponsiveAudioControllerIfStillOwned(
        _ controller: ResponsiveAudioProgramController,
        lifecycleToken: UUID
    ) -> Bool {
        guard responsiveAudioController === controller else {
            controller.stopWithoutPersisting()
            return false
        }
        controller.stopWithoutPersisting()
        responsiveAudioController = nil
        if responsiveAudioLifecycleToken == lifecycleToken {
            cancelPendingResponsiveAudioBinding()
        }
        return true
    }

    private func retainOutgoingResponsiveAudioTail(
        _ tail: ResponsiveAudioOutgoingTail?
    ) {
        stopOutgoingResponsiveAudioTailImmediately()
        outgoingResponsiveAudioTail = tail
        guard let tail else { return }
        tail.observeCompletion { @MainActor [weak self, weak tail] _ in
            guard let self, let tail,
                  self.outgoingResponsiveAudioTail === tail else {
                return
            }
            self.outgoingResponsiveAudioTail = nil
        }
    }

    private func stopOutgoingResponsiveAudioTailImmediately() {
        let tail = outgoingResponsiveAudioTail
        outgoingResponsiveAudioTail = nil
        tail?.stopImmediately()
    }

    private var journeyAudioRequiresRouteSuspension: Bool {
        JourneyAudioRouteChangeSuspensionPolicy
            .journeyAudioRequiresSuspension(
                controllerIsPlaying:
                    responsiveAudioController?.runtime.isPlaying == true,
                playbackStartIsInFlight:
                    responsiveAudioPlaybackStartTask != nil,
                crashCursorIsArmed: responsiveAudioCursorPump.isRunning,
                outgoingTailIsActive: outgoingResponsiveAudioTail != nil
            )
    }

    private func releaseCatalogEntry(
        for releaseID: ReleaseID
    ) -> ReleaseCatalogEntry? {
        if let retained = retainedFutureReleaseCatalogEntries.first(where: {
            $0.id == releaseID
        }) {
            return retained
        }
        return releaseDiscovery?.latestUpdate?.discovery.availableEntries.first(
            where: { $0.id == releaseID }
        )
    }

    private func currentChapterRuntimeAuthority()
        -> VerifiedChapterRuntimeContentAuthority? {
        if let activeFutureReleaseID,
           let authority = futureReleaseContentSnapshot.chapterRuntimeAuthority(
               for: activeFutureReleaseID
           ), case let .chapter(chapterID) = committedState.route,
           authority.repository.chapter(chapterID) != nil {
            return authority
        }
        return runtimeContentSnapshot?.chapterRuntimeAuthority
    }

    private func installedFutureRelease(
        containing chapterID: ChapterID
    ) -> (
        releaseID: ReleaseID,
        authority: VerifiedChapterRuntimeContentAuthority
    )? {
        for releaseID in futureReleaseContentSnapshot.contentsByReleaseID.keys
            .sorted() {
            guard let authority = futureReleaseContentSnapshot
                .chapterRuntimeAuthority(for: releaseID),
                  authority.repository.chapter(chapterID) != nil else {
                continue
            }
            return (releaseID, authority)
        }
        return nil
    }

    func selectChapter(_ chapterID: ChapterID) {
        guard !chapterTransitionIsPending else { return }
        guard let chapter = FoundationCatalog.chapters.first(where: { $0.id == chapterID }) else {
            return
        }
        switch access(to: chapterID) {
        case .included, .purchased:
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains(
                DevelopmentSignedRuntimeFixtureAppContent.launchArgument
            ), let snapshot = runtimeContentSnapshot,
               let verifiedChapter = snapshot.repository.catalogEntry(
                   chapterID
               ) {
                _ = openVerifiedChapter(
                    verifiedChapter,
                    snapshot: snapshot
                )
                return
            }
#endif
            openChapter(chapter)
        case .locked:
            purchaseState = .idle
            lockedRoad = LockedRoad(chapter: chapter)
        }
    }

    func access(to chapterID: ChapterID) -> ChapterAccess {
        accessResolver.access(
            to: chapterID,
            snapshot: entitlementSnapshot,
            at: Date()
        )
    }

    func dismissLockedRoad() {
        guard purchaseState != .purchasing, purchaseState != .restoring else { return }
        lockedRoad = nil
        purchaseState = .idle
    }

    func dismissContentFailure() {
        contentFailure = nil
    }

    func advanceCurrentBeat() {
        guard chapterRuntimePhysicalPauseGate == nil else { return }
        advanceCurrentBeat(reservation: nil)
    }

    func advanceCurrentBeat(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard let reservation = reserveChapterRuntimeInput(
            expectedIdentity
        ) else { return }
        advanceCurrentBeat(reservation: reservation)
    }

    private func advanceCurrentBeat(
        reservation: ChapterRuntimeInputReservationGate.Token?
    ) {
        guard !chapterTransitionIsPending,
              let chapterCoordinator else {
            if let reservation {
                finishChapterRuntimeInputReservation(reservation)
            }
            return
        }
        do {
            let plan = try chapterCoordinator.advanceActions(state: committedState)
            chapterTransitionIsPending = true
            enqueueOrderedJourneyTransition(
                plan.actions,
                causalReservation: reservation
            )
        } catch {
            if let reservation {
                finishChapterRuntimeInputReservation(reservation)
            }
            contentFailure = "This historical step could not be verified. Saved progress has not changed."
        }
    }

    func chapterRuntimeRouteIdentity(
        for chapterID: ChapterID,
        viewportCropID: String,
        reduceMotion: Bool
    ) -> ChapterRuntimeRouteIdentity? {
        guard case let .chapter(activeChapterID) = committedState.route,
              activeChapterID == chapterID,
              let authority = currentChapterRuntimeAuthority(),
              let persistenceAuthority =
                persistenceAuthorityFence.currentReceipt,
              let cursor = chapterCursor,
              cursor.chapter.id == chapterID,
              let packageID = authority.repository.packageID(for: chapterID),
              cursor.packageID == packageID,
              cursor.scene.sceneCanvas.viewportCrops.contains(where: {
                  $0.id == viewportCropID
              }),
              cursor.scene.reduceMotionComposition.viewportCrops.contains(where: {
                  $0.id == viewportCropID
              }),
              let verifiedPackage = authority.verifiedPackage(for: packageID),
              authority.packageRootURL(for: packageID) != nil else {
            return nil
        }
        return ChapterRuntimeRouteIdentity(
            persistenceAuthority: persistenceAuthority,
            contentRevision: authority.revision,
            chapterID: chapterID,
            packageID: packageID,
            packageManifestDigest:
                verifiedPackage.manifest.manifestDigest,
            beatID: cursor.beat.id,
            viewportCropID: viewportCropID,
            reduceMotion: reduceMotion
        )
    }

    private var chapterRuntimeInputAdmissionState:
        ChapterRuntimeInputAdmissionPolicy.State {
        ChapterRuntimeInputAdmissionPolicy.State(
            restorationIsInFlight: isRestoring,
            persistenceIsLocked: persistenceIsLocked,
            authorityPreparationIsInFlight:
                authorityTransitionPreparationTask != nil,
            authorityTransitionIsInFlight: authorityTransitionTask != nil,
            authorityRestoreIsInFlight: authorityRestoreIsInFlight,
            orderedTransitionIsInFlight: orderedJourneyTransitionTask != nil,
            chapterTransitionIsPending: chapterTransitionIsPending
        )
    }

    private var runtimeTransitionIsInactive: Bool {
        ChapterRuntimeInputAdmissionPolicy.runtimeTransitionIsInactive(
            chapterRuntimeInputAdmissionState
        )
    }

#if DEBUG
    private func recordResponsiveAudioStartAdmissionRejection(
        stage: String
    ) {
        guard responsiveAudioStartAdmissionDiagnosticForTesting == "none"
        else { return }
        let state = chapterRuntimeInputAdmissionState
        func bit(_ value: Bool) -> String { value ? "1" : "0" }
        responsiveAudioStartAdmissionDiagnosticForTesting =
            "\(stage)[restore=\(bit(state.restorationIsInFlight))"
                + ",lock=\(bit(state.persistenceIsLocked))"
                + ",prep=\(bit(state.authorityPreparationIsInFlight))"
                + ",transition=\(bit(state.authorityTransitionIsInFlight))"
                + ",authorityRestore=\(bit(state.authorityRestoreIsInFlight))"
                + ",ordered=\(bit(state.orderedTransitionIsInFlight))"
                + ",chapter=\(bit(state.chapterTransitionIsPending))]"
    }

    func chapterRuntimeInputAdmissionDiagnosticForTesting(
        _ expectedIdentity: ChapterRuntimeRouteIdentity
    ) -> String {
        let state = chapterRuntimeInputAdmissionState
        let currentIdentity = chapterRuntimeRouteIdentity(
            for: expectedIdentity.chapterID,
            viewportCropID: expectedIdentity.viewportCropID,
            reduceMotion: expectedIdentity.reduceMotion
        )
        let identityStatus: String
        if let currentIdentity {
            identityStatus = currentIdentity == expectedIdentity
                ? "exact"
                : "mismatch[persistence=\(currentIdentity.persistenceAuthority == expectedIdentity.persistenceAuthority ? 1 : 0),revision=\(currentIdentity.contentRevision == expectedIdentity.contentRevision ? 1 : 0),chapter=\(currentIdentity.chapterID == expectedIdentity.chapterID ? 1 : 0),package=\(currentIdentity.packageID == expectedIdentity.packageID ? 1 : 0),manifest=\(currentIdentity.packageManifestDigest == expectedIdentity.packageManifestDigest ? 1 : 0),beat=\(currentIdentity.beatID == expectedIdentity.beatID ? 1 : 0),crop=\(currentIdentity.viewportCropID == expectedIdentity.viewportCropID ? 1 : 0),motion=\(currentIdentity.reduceMotion == expectedIdentity.reduceMotion ? 1 : 0)]"
        } else {
            identityStatus = "missing"
        }
        func bit(_ value: Bool) -> Int { value ? 1 : 0 }
        return "identity=\(identityStatus)"
            + ";restore=\(bit(state.restorationIsInFlight))"
            + ";lock=\(bit(state.persistenceIsLocked))"
            + ";prep=\(bit(state.authorityPreparationIsInFlight))"
            + ";transition=\(bit(state.authorityTransitionIsInFlight))"
            + ";authorityRestore=\(bit(state.authorityRestoreIsInFlight))"
            + ";ordered=\(bit(state.orderedTransitionIsInFlight))"
            + ";chapter=\(bit(state.chapterTransitionIsPending))"
            + ";physicalPause=\(bit(chapterRuntimePhysicalPauseGate?.matches(expectedIdentity) == true))"
            + ";reservations=\(chapterRuntimeInputReservationGate.activeCount)"
    }

    func recordContentAuthorityBarrierInputMilestoneForTesting(
        _ stage: String,
        identity: ChapterRuntimeRouteIdentity
    ) {
        recordContentAuthorityBarrierMilestoneForTesting(
            "\(stage):r\(identity.contentRevision)"
        )
    }

    private var contentAuthorityBarrierProbeIsEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing-content-authority-barrier")
            || arguments.contains(
                "--ui-testing-content-authority-quiesce-recovery"
            )
            || arguments.contains(
                "--ui-testing-content-authority-stale-controller-swap"
            )
            || arguments.contains(
                "--ui-testing-content-authority-failed-pause-recovery"
            )
            || arguments.contains(
                "--ui-testing-content-authority-failed-pause-recovery-e2"
            )
    }

    private var contentAuthorityFailedPauseRecoveryProbeIsEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(
            "--ui-testing-content-authority-failed-pause-recovery"
        ) || arguments.contains(
            "--ui-testing-content-authority-failed-pause-recovery-e2"
        )
    }

    private var contentAuthorityQuiesceRecoveryProbeIsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-content-authority-quiesce-recovery"
        )
    }

    private var contentAuthorityStaleControllerSwapProbeIsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-content-authority-stale-controller-swap"
        )
    }

    private var contentAuthorityAudioAuditProbeIsEnabled: Bool {
        contentAuthorityQuiesceRecoveryProbeIsEnabled
            || contentAuthorityStaleControllerSwapProbeIsEnabled
    }

    private var contentAuthorityRecoverySecondSuspensionProbeIsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-content-authority-failed-pause-recovery-e2"
        )
    }

    private var suspensionPersistenceRetryProbeIsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-suspension-persistence-retry"
        )
    }

    private func recordContentAuthorityBarrierMilestoneForTesting(
        _ milestone: String
    ) {
        guard contentAuthorityBarrierProbeIsEnabled else { return }
        if contentAuthorityBarrierDiagnosticForTesting == "none" {
            contentAuthorityBarrierDiagnosticForTesting = milestone
        } else {
            contentAuthorityBarrierDiagnosticForTesting += ">" + milestone
        }
    }

    private func updateContentAuthorityAudioDiagnosticForTesting() {
        guard contentAuthorityAudioAuditProbeIsEnabled else { return }
        let mode = contentAuthorityQuiesceRecoveryProbeIsEnabled
            ? "recovery"
            : "stale"
        let partial = contentAuthorityAudioPartialSnapshotForTesting.map {
            "\($0.cursorSample)@\($0.loopIteration)"
        } ?? "none"
        let sequenceBefore = contentAuthorityAudioSequenceBeforeForTesting
            .map(String.init) ?? "none"
        let sequenceAfter = contentAuthorityAudioSequenceAfterForTesting
            .map(String.init) ?? "none"
        let appendDelta: String
        if let before = contentAuthorityAudioSequenceBeforeForTesting,
           let after = contentAuthorityAudioSequenceAfterForTesting,
           after >= before {
            appendDelta = String(after - before)
        } else {
            appendDelta = "none"
        }
        func bit(_ value: Bool) -> Int { value ? 1 : 0 }
        func fullMatch(
            _ lhs: ResponsiveAudioProgramSnapshot?,
            _ rhs: ResponsiveAudioProgramSnapshot?
        ) -> Bool {
            guard let lhs, let rhs else { return false }
            return lhs == rhs
        }
        let capturedIdentityMatchesPre: Bool = {
            guard let captured =
                    contentAuthorityAudioCapturedSnapshotForTesting,
                  let pre = contentAuthorityAudioPreSnapshotForTesting else {
                return false
            }
            return Self.responsiveAudioNonPositionMatches(captured, pre)
        }()
        contentAuthorityAudioDiagnosticForTesting = "mode=\(mode)"
            + ";pre=\(Self.responsiveAudioCursorDiagnostic(contentAuthorityAudioPreSnapshotForTesting))"
            + ";partial=\(partial)"
            + ";captured=\(Self.responsiveAudioCursorDiagnostic(contentAuthorityAudioCapturedSnapshotForTesting))"
            + ";fallback=\(Self.responsiveAudioCursorDiagnostic(contentAuthorityAudioFallbackSnapshotForTesting))"
            + ";baseline=\(Self.responsiveAudioCursorDiagnostic(contentAuthorityAudioBaselineSnapshotForTesting))"
            + ";committed=\(Self.responsiveAudioCursorDiagnostic(contentAuthorityAudioCommittedSnapshotForTesting))"
            + ";sequenceBefore=\(sequenceBefore)"
            + ";sequenceAfter=\(sequenceAfter)"
            + ";appendDelta=\(appendDelta)"
            + ";preIdentity=\(Self.responsiveAudioIdentityDiagnostic(contentAuthorityAudioPreSnapshotForTesting))"
            + ";capturedIdentity=\(Self.responsiveAudioIdentityDiagnostic(contentAuthorityAudioCapturedSnapshotForTesting))"
            + ";fallbackIdentity=\(Self.responsiveAudioIdentityDiagnostic(contentAuthorityAudioFallbackSnapshotForTesting))"
            + ";baselineIdentity=\(Self.responsiveAudioIdentityDiagnostic(contentAuthorityAudioBaselineSnapshotForTesting))"
            + ";committedIdentity=\(Self.responsiveAudioIdentityDiagnostic(contentAuthorityAudioCommittedSnapshotForTesting))"
            + ";capturedExists=\(bit(contentAuthorityAudioCapturedSnapshotForTesting != nil))"
            + ";capturedIdentityEqualsPre=\(bit(capturedIdentityMatchesPre))"
            + ";fallbackEqualsPre=\(bit(fullMatch(contentAuthorityAudioFallbackSnapshotForTesting, contentAuthorityAudioPreSnapshotForTesting)))"
            + ";committedEqualsFallback=\(bit(fullMatch(contentAuthorityAudioCommittedSnapshotForTesting, contentAuthorityAudioFallbackSnapshotForTesting)))"
            + ";committedEqualsBaseline=\(bit(fullMatch(contentAuthorityAudioCommittedSnapshotForTesting, contentAuthorityAudioBaselineSnapshotForTesting)))"
            + ";transportPaused=\(bit(contentAuthorityAudioTransportPausedForTesting))"
            + ";controllerSwapped=\(bit(contentAuthorityAudioControllerSwappedForTesting))"
            + ";stale=\(bit(contentAuthorityAudioSnapshotWasStaleForTesting))"
            + ";final=\(bit(contentAuthorityAudioAuditIsFinalForTesting))"
    }

    private func beginContentAuthorityAudioAuditForTesting(
        controller: ResponsiveAudioProgramController
    ) {
        guard contentAuthorityAudioAuditProbeIsEnabled else { return }
        contentAuthorityAudioPreSnapshotForTesting = controller.runtime
            .snapshot()
        contentAuthorityAudioPartialSnapshotForTesting = nil
        contentAuthorityAudioCapturedSnapshotForTesting = nil
        contentAuthorityAudioFallbackSnapshotForTesting = nil
        contentAuthorityAudioBaselineSnapshotForTesting = committedState
            .activeChapter?.responsiveAudioSnapshot
        contentAuthorityAudioCommittedSnapshotForTesting = nil
        contentAuthorityAudioSequenceBeforeForTesting = lastCommittedSequence
        contentAuthorityAudioSequenceAfterForTesting = nil
        contentAuthorityAudioTransportPausedForTesting = false
        contentAuthorityAudioControllerSwappedForTesting = false
        contentAuthorityAudioSnapshotWasStaleForTesting = false
        contentAuthorityAudioAuditIsFinalForTesting = false
        updateContentAuthorityAudioDiagnosticForTesting()
    }

    private func finalizeContentAuthorityAudioAuditForTesting() {
        guard contentAuthorityAudioAuditProbeIsEnabled else { return }
        contentAuthorityAudioCommittedSnapshotForTesting = committedState
            .activeChapter?.responsiveAudioSnapshot
        contentAuthorityAudioSequenceAfterForTesting = lastCommittedSequence
        contentAuthorityAudioAuditIsFinalForTesting = true
        updateContentAuthorityAudioDiagnosticForTesting()
    }

    private var orderedExitAudioProbeIsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-ordered-exit-quiesce-recovery"
        )
    }

    private var orderedExitControllerSwapProbeIsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-ordered-exit-controller-swap-during-retirement"
        )
    }

    private var orderedExitPreinstallSuccessorProbeIsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-ordered-exit-preinstall-successor-during-retirement"
        )
    }

    private func updateOrderedExitAudioDiagnosticForTesting() {
        guard orderedExitAudioProbeIsEnabled else { return }
        let partial = orderedExitAudioPartialSnapshotForTesting.map {
            "\($0.cursorSample)@\($0.loopIteration)"
        } ?? "none"
        let sequenceBefore = orderedExitAudioSequenceBeforeForTesting
            .map(String.init) ?? "none"
        let sequenceAfter = orderedExitAudioSequenceAfterForTesting
            .map(String.init) ?? "none"
        let appendDelta: String
        if let before = orderedExitAudioSequenceBeforeForTesting,
           let after = orderedExitAudioSequenceAfterForTesting,
           after >= before {
            appendDelta = String(after - before)
        } else {
            appendDelta = "none"
        }
        func bit(_ value: Bool) -> Int { value ? 1 : 0 }
        func matchesPartial(
            _ snapshot: ResponsiveAudioProgramSnapshot?
        ) -> Bool {
            guard let snapshot,
                  let partial = orderedExitAudioPartialSnapshotForTesting
            else { return false }
            return snapshot.timelineID == partial.timelineID
                && snapshot.cursorSample == partial.cursorSample
                && snapshot.loopIteration == partial.loopIteration
        }
        orderedExitAudioDiagnosticForTesting = "mode=ordered-exit"
            + ";pre=\(Self.responsiveAudioCursorDiagnostic(orderedExitAudioPreSnapshotForTesting))"
            + ";partial=\(partial)"
            + ";baseline=\(Self.responsiveAudioCursorDiagnostic(orderedExitAudioBaselineSnapshotForTesting))"
            + ";fallback=\(Self.responsiveAudioCursorDiagnostic(orderedExitAudioFallbackSnapshotForTesting))"
            + ";committed=\(Self.responsiveAudioCursorDiagnostic(orderedExitAudioCommittedSnapshotForTesting))"
            + ";sidecar=\(Self.responsiveAudioCursorDiagnostic(orderedExitAudioSidecarSnapshotForTesting))"
            + ";sequenceBefore=\(sequenceBefore)"
            + ";sequenceAfter=\(sequenceAfter)"
            + ";appendDelta=\(appendDelta)"
            + ";preIdentity=\(Self.responsiveAudioIdentityDiagnostic(orderedExitAudioPreSnapshotForTesting))"
            + ";baselineIdentity=\(Self.responsiveAudioIdentityDiagnostic(orderedExitAudioBaselineSnapshotForTesting))"
            + ";fallbackIdentity=\(Self.responsiveAudioIdentityDiagnostic(orderedExitAudioFallbackSnapshotForTesting))"
            + ";committedIdentity=\(Self.responsiveAudioIdentityDiagnostic(orderedExitAudioCommittedSnapshotForTesting))"
            + ";transportPaused=\(bit(orderedExitAudioTransportPausedForTesting))"
            + ";fallbackRecovered=\(bit(orderedExitAudioFallbackRecoveredForTesting))"
            + ";controllerDiscarded=\(bit(orderedExitAudioControllerDiscardedForTesting))"
            + ";cursorRetired=\(bit(orderedExitAudioCursorProtectionRetiredForTesting))"
            + ";pumpStopped=\(bit(!responsiveAudioCursorPump.isRunning))"
            + ";authorityRequested=\(bit(orderedExitAudioAuthorityRequestedForTesting))"
            + ";authorityPublished=\(bit(orderedExitAudioAuthorityPublishedForTesting))"
            + ";actorRecoveryQueried=\(bit(orderedExitAudioActorRecoveryQueriedForTesting))"
            + ";successorInstalled=\(bit(orderedExitAudioSuccessorControllerIDForTesting != nil))"
            + ";successorPreserved=\(bit(orderedExitAudioSuccessorControllerIDForTesting.map { id in responsiveAudioController.map(ObjectIdentifier.init) == id } ?? false))"
            + ";bindingIdentityPreserved=\(bit(orderedExitAudioBindingIdentityForTesting.map { $0 == responsiveAudioBindingIdentity } ?? false))"
            + ";preinstallSuccessorArmed=\(bit(orderedExitPreinstallSuccessorWasArmedForTesting))"
            + ";preinstallSuccessorPreserved=\(bit(orderedExitPreinstallSuccessorWasArmedForTesting && responsiveAudioController == nil && responsiveAudioBindingTask != nil && orderedExitAudioBindingIdentityForTesting == responsiveAudioBindingIdentity && orderedExitAudioLifecycleTokenForTesting != responsiveAudioLifecycleToken))"
            + ";partialCommitted=\(bit(matchesPartial(orderedExitAudioCommittedSnapshotForTesting)))"
            + ";partialInSidecar=\(bit(matchesPartial(orderedExitAudioSidecarSnapshotForTesting)))"
            + ";route=\(committedState.route == .world ? "world" : "chapter")"
            + ";final=\(bit(orderedExitAudioAuditIsFinalForTesting))"
    }

    private func beginOrderedExitAudioAuditForTesting(
        controller: ResponsiveAudioProgramController
    ) {
        guard orderedExitAudioProbeIsEnabled,
              !orderedExitAudioFailureInjectionDidRun else { return }
        orderedExitAudioChapterIDForTesting =
            controller.runtime.program.scope.chapterID
        orderedExitAudioPreSnapshotForTesting = controller.runtime.snapshot()
        orderedExitAudioPartialSnapshotForTesting = nil
        orderedExitAudioBaselineSnapshotForTesting =
            orderedExitCommittedSnapshotForTesting()
        orderedExitAudioFallbackSnapshotForTesting = nil
        orderedExitAudioCommittedSnapshotForTesting = nil
        orderedExitAudioSidecarSnapshotForTesting = nil
        orderedExitAudioCursorAuthorityForTesting = try?
            responsiveAudioCursorAuthority(for: controller)
        orderedExitAudioSequenceBeforeForTesting = lastCommittedSequence
        orderedExitAudioSequenceAfterForTesting = nil
        orderedExitAudioTransportPausedForTesting = false
        orderedExitAudioFallbackRecoveredForTesting = false
        orderedExitAudioControllerDiscardedForTesting = false
        orderedExitAudioCursorProtectionRetiredForTesting = false
        orderedExitAudioAuthorityRequestedForTesting = false
        orderedExitAudioAuthorityPublishedForTesting = false
        orderedExitAudioActorRecoveryQueriedForTesting = false
        orderedExitForcedControllerSwapDidRun = false
        orderedExitAudioSuccessorControllerIDForTesting = nil
        orderedExitAudioBindingIdentityForTesting =
            responsiveAudioBindingIdentity
        orderedExitAudioLifecycleTokenForTesting = responsiveAudioLifecycleToken
        orderedExitPreinstallSuccessorWasArmedForTesting = false
        orderedExitAudioAuditIsFinalForTesting = false
        updateOrderedExitAudioDiagnosticForTesting()
    }

    private func armOrderedExitTransportProbeForTesting(
        controller: ResponsiveAudioProgramController
    ) {
        guard orderedExitAudioProbeIsEnabled,
              !orderedExitAudioFailureInjectionDidRun,
              let probeTransport = responsiveAudioAuthorityProbeTransportForTesting,
              probeTransport.controllerID == ObjectIdentifier(controller)
        else { return }
        probeTransport.transport.armPauseCompletionFaultForTesting(
            minimumRenderedSampleAdvance: 256
        ) { [weak self, weak controller] snapshot in
            guard let self, let controller,
                  self.responsiveAudioController === controller,
                  !self.orderedExitAudioFailureInjectionDidRun else { return }
            self.orderedExitAudioFailureInjectionDidRun = true
            self.orderedExitAudioPartialSnapshotForTesting = snapshot
            self.orderedExitAudioTransportPausedForTesting =
                !snapshot.isPlaying
            self.updateOrderedExitAudioDiagnosticForTesting()
            throw JourneyUITestInjectedPersistenceError
                .orderedExitPauseCompletion
        }
    }

    private func markOrderedExitAudioFallbackRecoveredForTesting(
        _ snapshot: ResponsiveAudioProgramSnapshot
    ) {
        guard orderedExitAudioProbeIsEnabled,
              orderedExitAudioFailureInjectionDidRun else { return }
        orderedExitAudioFallbackSnapshotForTesting = snapshot
        orderedExitAudioFallbackRecoveredForTesting = true
        updateOrderedExitAudioDiagnosticForTesting()
    }

    private func finalizeOrderedExitAudioSuccessForTesting(
        _ snapshot: ResponsiveAudioProgramSnapshot
    ) async {
        guard orderedExitAudioProbeIsEnabled,
              orderedExitAudioFailureInjectionDidRun else { return }
        if orderedExitAudioFallbackSnapshotForTesting == nil {
            orderedExitAudioFallbackSnapshotForTesting = snapshot
        }
        // This reads the actor's verified durable record, not the model's
        // presentation mirror. Retirement has already drained every write
        // admitted by the old writer; one full production pump period then
        // proves that no cancelled periodic generation can publish later.
        try? await Task.sleep(
            nanoseconds: ResponsiveAudioCursorCheckpointPump
                .productionIntervalNanoseconds
        )
        if let store = responsiveAudioCursorStore,
           let authority = orderedExitAudioCursorAuthorityForTesting {
            orderedExitAudioSidecarSnapshotForTesting = try? await store
                .recover(authority: authority)
            orderedExitAudioActorRecoveryQueriedForTesting = true
        }
        orderedExitAudioCursorProtectionRetiredForTesting =
            responsiveAudioCursorSession == nil
                && !responsiveAudioCursorPump.isRunning
        updateOrderedExitAudioDiagnosticForTesting()
    }

    private func finalizeOrderedExitAudioDurabilityForTesting() {
        guard orderedExitAudioProbeIsEnabled,
              orderedExitAudioFailureInjectionDidRun else { return }
        orderedExitAudioCommittedSnapshotForTesting =
            orderedExitCommittedSnapshotForTesting()
        orderedExitAudioSequenceAfterForTesting = lastCommittedSequence
        orderedExitAudioAuditIsFinalForTesting = false
        updateOrderedExitAudioDiagnosticForTesting()
        requestOrderedExitAuthorityPublicationForTesting()
    }

    private func finalizeOrderedExitAudioFailureForTesting(
        controllerWasDiscarded: Bool
    ) {
        guard orderedExitAudioProbeIsEnabled,
              orderedExitAudioFailureInjectionDidRun else { return }
        orderedExitAudioControllerDiscardedForTesting =
            orderedExitAudioControllerDiscardedForTesting
                || controllerWasDiscarded
        orderedExitAudioCommittedSnapshotForTesting =
            orderedExitCommittedSnapshotForTesting()
        orderedExitAudioSequenceAfterForTesting = lastCommittedSequence
        orderedExitAudioCursorProtectionRetiredForTesting =
            responsiveAudioCursorSession == nil
                && !responsiveAudioCursorPump.isRunning
        orderedExitAudioAuditIsFinalForTesting = true
        updateOrderedExitAudioDiagnosticForTesting()
    }

    private func orderedExitCommittedSnapshotForTesting()
        -> ResponsiveAudioProgramSnapshot? {
        guard let chapterID = orderedExitAudioChapterIDForTesting else {
            return nil
        }
        return committedState.chapterSession(chapterID)?
            .responsiveAudioSnapshot
    }

    private func requestOrderedExitAuthorityPublicationForTesting() {
        guard orderedExitAudioProbeIsEnabled,
              orderedExitAudioFailureInjectionDidRun,
              !orderedExitAudioAuthorityRequestedForTesting else { return }
        if ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-ordered-exit-skip-authority-publication"
        ) {
            orderedExitAudioAuditIsFinalForTesting = true
            updateOrderedExitAudioDiagnosticForTesting()
            return
        }
        guard let snapshot = runtimeContentSnapshot else { return }
        orderedExitAudioAuthorityRequestedForTesting = true
        let replacement = VerifiedJourneyContentSnapshot(
            revision: snapshot.revision + 1,
            repository: snapshot.repository,
            reconciledInstalledIndex: snapshot.reconciledInstalledIndex,
            packageRootURLs: snapshot.packageRootURLs,
            verifiedPackagesByID: snapshot.verifiedPackagesByID,
            repairedPackageIDs: snapshot.repairedPackageIDs,
            unavailableCurrentPackageIDs:
                snapshot.unavailableCurrentPackageIDs
        )
        applyRuntimeContentSnapshot(replacement)
        updateOrderedExitAudioDiagnosticForTesting()
    }

    private func recordSuspensionPersistenceRetryMilestoneForTesting(
        _ milestone: String
    ) {
        guard suspensionPersistenceRetryProbeIsEnabled else { return }
        if suspensionPersistenceRetryDiagnosticForTesting == "none" {
            suspensionPersistenceRetryDiagnosticForTesting = milestone
        } else {
            suspensionPersistenceRetryDiagnosticForTesting += ">" + milestone
        }
    }

    private func injectContentAuthorityBarrierAfterFirstInputIfNeeded(
        identity: ChapterRuntimeRouteIdentity
    ) {
        guard contentAuthorityBarrierProbeIsEnabled,
              !contentAuthorityBarrierInjectionDidRun,
              identity.chapterID == ChapterID("european-world"),
              identity.contentRevision == 1,
              let snapshot = runtimeContentSnapshot,
              snapshot.revision == identity.contentRevision else {
            return
        }
        contentAuthorityBarrierInjectionDidRun = true
        recordContentAuthorityBarrierMilestoneForTesting("reserved:r1")
        if contentAuthorityFailedPauseRecoveryProbeIsEnabled {
            // Exercise the model's real failed-episode recovery without
            // replacing the production suspension coordinator or route task.
            preQuiescedSuspensionFailed = true
        }
        if !contentAuthorityAudioAuditProbeIsEnabled {
            requestSuspension(.audioRouteChange)
        }
        if contentAuthorityFailedPauseRecoveryProbeIsEnabled {
            recordContentAuthorityBarrierMilestoneForTesting("e1:requested")
        }
        let replacement = VerifiedJourneyContentSnapshot(
            revision: 2,
            repository: snapshot.repository,
            reconciledInstalledIndex: snapshot.reconciledInstalledIndex,
            packageRootURLs: snapshot.packageRootURLs,
            verifiedPackagesByID: snapshot.verifiedPackagesByID,
            repairedPackageIDs: snapshot.repairedPackageIDs,
            unavailableCurrentPackageIDs:
                snapshot.unavailableCurrentPackageIDs
        )
        applyRuntimeContentSnapshot(replacement)
        recordContentAuthorityBarrierMilestoneForTesting("desired:r2")
    }

    private func injectSuspensionPersistenceRetryAfterFirstInputIfNeeded(
        identity: ChapterRuntimeRouteIdentity
    ) {
        guard suspensionPersistenceRetryProbeIsEnabled,
              !suspensionPersistenceRetryInjectionDidRun,
              identity.chapterID == ChapterID("european-world") else {
            return
        }
        suspensionPersistenceRetryInjectionDidRun = true
        recordSuspensionPersistenceRetryMilestoneForTesting("reserved")
        requestSuspension(.audioRouteChange)
        recordSuspensionPersistenceRetryMilestoneForTesting(
            "pause-requested"
        )
    }
#endif

    func admitsChapterRuntimeInput(
        _ identity: ChapterRuntimeRouteIdentity
    ) -> Bool {
        guard chapterRuntimePhysicalPauseGate?.matches(identity) != true else {
            return false
        }
        return chapterRuntimeRouteAuthorityAdmitsInput(identity)
    }

    private func chapterRuntimeRouteAuthorityAdmitsInput(
        _ identity: ChapterRuntimeRouteIdentity
    ) -> Bool {
        ChapterRuntimeInputAdmissionPolicy.admits(
            expectedIdentity: identity,
            currentIdentity: chapterRuntimeRouteIdentity(
                for: identity.chapterID,
                viewportCropID: identity.viewportCropID,
                reduceMotion: identity.reduceMotion
            ),
            state: chapterRuntimeInputAdmissionState
        )
    }

    func reserveChapterRuntimeInput(
        _ identity: ChapterRuntimeRouteIdentity
    ) -> ChapterRuntimeInputReservationGate.Token? {
        guard admitsChapterRuntimeInput(identity),
              let token = chapterRuntimeInputReservationGate.reserve() else {
            return nil
        }
        chapterRuntimeInputReservationIdentities[token] = identity
#if DEBUG
        injectContentAuthorityBarrierAfterFirstInputIfNeeded(
            identity: identity
        )
        injectSuspensionPersistenceRetryAfterFirstInputIfNeeded(
            identity: identity
        )
#endif
        return token
    }

    func ownsChapterRuntimeInputReservation(
        _ token: ChapterRuntimeInputReservationGate.Token,
        identity: ChapterRuntimeRouteIdentity
    ) -> Bool {
        chapterRuntimeInputReservationGate.owns(token)
            && chapterRuntimeInputReservationIdentities[token] == identity
    }

    func finishChapterRuntimeInputReservation(
        _ token: ChapterRuntimeInputReservationGate.Token
    ) {
        guard chapterRuntimeInputReservationGate.finish(token) else { return }
        chapterRuntimeInputReservationIdentities[token] = nil
        releaseChapterRuntimeInputReservationWaitersIfEligible()
    }

    private func awaitChapterRuntimeInputReservationQuiescence(
        excluding excludedToken: ChapterRuntimeInputReservationGate.Token?
            = nil
    ) async {
        guard chapterRuntimeInputReservationGate.activeCount(
            excluding: excludedToken
        ) > 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            chapterRuntimeInputReservationWaiters.append(
                ChapterRuntimeInputReservationWaiter(
                    excludedToken: excludedToken,
                    continuation: continuation
                )
            )
        }
    }

    private func releaseChapterRuntimeInputReservationWaitersIfEligible() {
        var retained: [ChapterRuntimeInputReservationWaiter] = []
        for waiter in chapterRuntimeInputReservationWaiters {
            if chapterRuntimeInputReservationGate.activeCount(
                excluding: waiter.excludedToken
            ) == 0 {
                waiter.continuation.resume()
            } else {
                retained.append(waiter)
            }
        }
        chapterRuntimeInputReservationWaiters = retained
    }

    func pendingChapterRuntimePhysicalPauseEvent(
        for identity: ChapterRuntimeRouteIdentity
    ) -> ResponsiveAudioPhysicalPauseEvent? {
        guard let gate = chapterRuntimePhysicalPauseGate,
              gate.matches(identity) else { return nil }
        return gate.event
    }

    @discardableResult
    func completeChapterRuntimePhysicalPauseRefresh(
        _ event: ResponsiveAudioPhysicalPauseEvent,
        identity: ChapterRuntimeRouteIdentity
    ) -> Bool {
        guard let gate = chapterRuntimePhysicalPauseGate,
              gate.event == event,
              gate.matches(identity),
              unresolvedResponsiveAudioPhysicalPauseEvent == event,
              responsiveAudioPhysicalPauseEvent == event,
              chapterRuntimeRouteAuthorityAdmitsInput(identity) else {
            return false
        }
        chapterRuntimePhysicalPauseGate = nil
        unresolvedResponsiveAudioPhysicalPauseEvent = nil
        suspensionEpisodeCoordinator.physicalPauseDidResolve()
#if DEBUG
        recordContentAuthorityBarrierInputMilestoneForTesting(
            "refreshed",
            identity: identity
        )
#endif
        resumeDeferredContentAuthorityRetryIfPossible()
        return true
    }

    func makeChapterSceneRuntime(
        identity: ChapterRuntimeRouteIdentity
    ) async throws -> VerifiedChapterSceneRuntime {
        guard identity == chapterRuntimeRouteIdentity(
            for: identity.chapterID,
            viewportCropID: identity.viewportCropID,
            reduceMotion: identity.reduceMotion
        ), let authority = currentChapterRuntimeAuthority(),
              let capturedCommitter = committer,
              persistenceAuthorityFence.matches(
                  identity.persistenceAuthority,
                  authority: capturedCommitter
              ) else {
            throw JourneyChapterRuntimeError.routeAuthorityUnavailable
        }
        while true {
            try Task.checkCancellation()
            let pauseEventAtConstruction =
                pendingChapterRuntimePhysicalPauseEvent(for: identity)
            if pauseEventAtConstruction != nil {
                guard await suspensionEpisodeCoordinator.awaitCurrentFlush()
                        == .durable else {
                    throw JourneyChapterRuntimeError.persistenceUnavailable
                }
            }
            if chapterCursor?.responsiveAudioProgram != nil {
                await awaitResponsiveAudioBindingIfNeeded()
                guard responsiveAudioController != nil else {
                    throw JourneyChapterRuntimeError.authoredAudioUnavailable
                }
            }

            guard committer === capturedCommitter,
                  persistenceAuthorityFence.matches(
                      identity.persistenceAuthority,
                      authority: capturedCommitter
                  ), identity == chapterRuntimeRouteIdentity(
                      for: identity.chapterID,
                      viewportCropID: identity.viewportCropID,
                      reduceMotion: identity.reduceMotion
                  ) else {
                throw JourneyChapterRuntimeError.routeAuthorityChanged
            }

            let runtime = try await VerifiedChapterSceneRuntimeFactory.make(
                authority: authority,
                chapterID: identity.chapterID,
                committer: capturedCommitter,
                viewportCropID: identity.viewportCropID,
                reduceMotion: identity.reduceMotion,
                hapticBridge: self,
                audioConsequenceBridge: self
            )
            guard !Task.isCancelled,
                  committer === capturedCommitter,
                  persistenceAuthorityFence.matches(
                      identity.persistenceAuthority,
                      authority: capturedCommitter
                  ),
                  runtime.contentRevision == identity.contentRevision,
                  identity == chapterRuntimeRouteIdentity(
                      for: identity.chapterID,
                      viewportCropID: identity.viewportCropID,
                      reduceMotion: identity.reduceMotion
                  ), runtime.controller.presentation.cursor.beat.id
                        == identity.beatID else {
                throw JourneyChapterRuntimeError.routeAuthorityChanged
            }
            guard pendingChapterRuntimePhysicalPauseEvent(for: identity)
                    == pauseEventAtConstruction else {
                continue
            }
            return runtime
        }
    }

    func submitChapterSceneTouch(
        _ intent: SceneTouchIntent,
        runtime: VerifiedChapterSceneRuntime,
        identity: ChapterRuntimeRouteIdentity,
        reservation: ChapterRuntimeInputReservationGate.Token,
        alphaSampler: (any SceneAlphaMaskSampling)? = nil,
        responsiveAudioIsUserAuthorized: Bool = false
    ) async throws -> ChapterScenePresentation {
        guard ownsChapterRuntimeInputReservation(
                  reservation,
                  identity: identity
              ),
              runtimeMatchesCurrentRoute(runtime, identity: identity) else {
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        let audioMutation = try await beginResponsiveAudioSceneMutationIfNeeded(
            runtime: runtime,
            identity: identity
        )
        guard let mutation = beginPersistenceMutation() else {
            _ = finishResponsiveAudioSceneMutationIfNeeded(audioMutation)
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        defer {
            finishResponsiveAudioSceneAndPersistenceMutation(
                audioMutation,
                persistenceMutation: mutation
            )
        }
        let transition = try await runtime.controller.submitTouch(
            intent,
            alphaSampler: alphaSampler
        )
        try await adoptChapterSceneTransition(transition)
        guard ownsChapterRuntimeInputReservation(
                  reservation,
                  identity: identity
              ), !persistenceIsLocked,
              runtimeMatchesCurrentRoute(runtime, identity: identity) else {
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        return try await applyResponsiveAudioPhaseIfAuthorized(
            from: transition.presentation,
            runtime: runtime,
            isUserAuthorized: responsiveAudioIsUserAuthorized
        )
    }

    func chapterAssetFailureAuthority(
        for identity: ChapterRuntimeRouteIdentity
    ) -> PackageAssetFailureAuthority? {
        guard let authority = currentChapterRuntimeAuthority(),
              authority.revision == identity.contentRevision,
              authority.repository.packageID(for: identity.chapterID) == identity.packageID else {
            return nil
        }
        return authority.assetFailureAuthority(for: identity.packageID)
    }

    @discardableResult
    func reportChapterAssetFailure(
        _ authority: PackageAssetFailureAuthority
    ) async -> AssetFailureReportOutcome? {
        if let activeFutureReleaseID, let futureReleaseClient {
            let outcome = await futureReleaseClient.reportAssetFailure(
                activeFutureReleaseID,
                authority
            )
            applyFutureReleaseContentSnapshot(
                await futureReleaseClient.contentSnapshot()
            )
            return outcome
        }
        guard let contentClient else { return nil }
        return await contentClient.reportAssetFailure(
            authority.packageID,
            authority
        )
    }

    func submitChapterSceneVoiceOver(
        elementID: String,
        authoredAction: AccessibilityActionSpec,
        runtime: VerifiedChapterSceneRuntime,
        identity: ChapterRuntimeRouteIdentity,
        reservation: ChapterRuntimeInputReservationGate.Token,
        responsiveAudioIsUserAuthorized: Bool = false
    ) async throws -> ChapterScenePresentation {
        guard ownsChapterRuntimeInputReservation(
                  reservation,
                  identity: identity
              ),
              runtimeMatchesCurrentRoute(runtime, identity: identity) else {
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        let audioMutation = try await beginResponsiveAudioSceneMutationIfNeeded(
            runtime: runtime,
            identity: identity
        )
        guard let mutation = beginPersistenceMutation() else {
            _ = finishResponsiveAudioSceneMutationIfNeeded(audioMutation)
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        defer {
            finishResponsiveAudioSceneAndPersistenceMutation(
                audioMutation,
                persistenceMutation: mutation
            )
        }
        let transition = try await runtime.controller.submitVoiceOver(
            elementID: elementID,
            authoredAction: authoredAction
        )
        try await adoptChapterSceneTransition(transition)
        guard ownsChapterRuntimeInputReservation(
                  reservation,
                  identity: identity
              ), !persistenceIsLocked,
              runtimeMatchesCurrentRoute(runtime, identity: identity) else {
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        return try await applyResponsiveAudioPhaseIfAuthorized(
            from: transition.presentation,
            runtime: runtime,
            isUserAuthorized: responsiveAudioIsUserAuthorized
        )
    }

    /// Retires one bounded visual/audio response without reserving or appending
    /// a Journey input. The controller token makes a late timer a no-op after a
    /// newer gesture has already replaced the response.
    func clearChapterSceneEphemeralResponse(
        matching token: ChapterSceneEphemeralResponseCleanupToken,
        runtime: VerifiedChapterSceneRuntime,
        identity: ChapterRuntimeRouteIdentity,
        responsiveAudioIsUserAuthorized: Bool = false
    ) async throws -> ChapterScenePresentation? {
        guard runtimeMatchesCurrentRoute(runtime, identity: identity) else {
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        let audioMutation = try await beginResponsiveAudioSceneMutationIfNeeded(
            runtime: runtime,
            identity: identity
        )
        guard let mutation = beginPersistenceMutation() else {
            _ = finishResponsiveAudioSceneMutationIfNeeded(audioMutation)
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        defer {
            finishResponsiveAudioSceneAndPersistenceMutation(
                audioMutation,
                persistenceMutation: mutation
            )
        }
        guard let cleared = try await runtime.controller
            .clearEphemeralInteractionResponse(matching: token) else {
            return nil
        }
        guard !persistenceIsLocked,
              runtimeMatchesCurrentRoute(runtime, identity: identity) else {
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        return try await applyResponsiveAudioPhaseIfAuthorized(
            from: cleared,
            runtime: runtime,
            isUserAuthorized: responsiveAudioIsUserAuthorized
        )
    }

    private func applyResponsiveAudioPhaseIfAuthorized(
        from presentation: ChapterScenePresentation,
        runtime: VerifiedChapterSceneRuntime,
        isUserAuthorized: Bool
    ) async throws -> ChapterScenePresentation {
        guard let phase = SceneResponsiveAudioPhaseResolver.phase(
                  interactionPhase: presentation.journeyState.activeChapter?
                      .interaction?.phase,
                  feedback: presentation.interactionFeedback,
                  directManipulation: presentation.directManipulation
              ), let controller = responsiveAudioController else {
            if presentation.journeyState.activeChapter?.interaction?.phase
                == .complete {
                pendingResponsiveAudioPhaseIntent = nil
            }
            return presentation
        }

        switch ResponsiveAudioPhaseDurabilityPolicy.decision(
            desiredPhase: phase,
            currentStage: controller.runtime.stage,
            currentPhase: controller.runtime.interactionPhase,
            isUserAuthorized: isUserAuthorized,
            suspensionIsActive:
                suspensionEpisodeCoordinator.episodeID != nil
        ) {
        case .ignore:
            return presentation
        case .deferUntilInteraction:
            // The latest semantic intent wins while the finite approach is
            // still playing. The boundary applies it to the live transport,
            // but never adds gesture-only phase state to the Journey journal.
            pendingResponsiveAudioPhaseIntent = phase
            return presentation
        case .commit:
            break
        }

        pendingResponsiveAudioPhaseIntent = nil
        do {
            // `selectInteractionPhase` also returns a snapshot action for
            // durable callers. A scene response deliberately discards it:
            // historical progress is already owned by the interaction commit,
            // while contact, resistance and the return to waiting are live
            // authored transport states only.
            _ = try controller.selectInteractionPhase(phase)
        } catch {
            controller.stopWithoutPersisting()
            responsiveAudioController = nil
            cancelPendingResponsiveAudioBinding()
            responsiveAudioFailure =
                "The authored sound state no longer matched this interaction."
            throw JourneyChapterRuntimeError.persistenceUnavailable
        }
        return presentation
    }

    /// A lifecycle cursor may never inherit a contact or rejection bed. The
    /// physical transition happens before the suspension coordinator asks the
    /// controller for a journal action, so the resulting snapshot is waiting.
    private func normalizeEphemeralResponsiveAudioPhaseForDurability() {
        pendingResponsiveAudioPhaseIntent = nil
        guard let controller = responsiveAudioController else {
            return
        }
        guard controller.runtime.stage == .interaction else {
            return
        }
        guard controller.runtime.interactionPhase != .waiting else {
            return
        }
        do {
            _ = try controller.selectInteractionPhase(.waiting)
        } catch {
            controller.stopWithoutPersisting()
            responsiveAudioController = nil
            cancelPendingResponsiveAudioBinding()
            responsiveAudioFailure =
                "The authored sound paused before its place could be verified."
        }
    }

    private func runtimeMatchesCurrentRoute(
        _ runtime: VerifiedChapterSceneRuntime,
        identity: ChapterRuntimeRouteIdentity
    ) -> Bool {
        runtime.contentRevision == identity.contentRevision
            && runtime.chapterID == identity.chapterID
            && runtime.packageID == identity.packageID
            && identity == chapterRuntimeRouteIdentity(
                for: identity.chapterID,
                viewportCropID: identity.viewportCropID,
                reduceMotion: identity.reduceMotion
            )
    }

    /// Brings the exact verified scene controller across the durable responsive-
    /// audio start before the route may publish a playing state. The controller
    /// itself accepts only an audio-only forward delta; these outer fences also
    /// prove that content, persistence authority and the authored beat remained
    /// the route that initiated the start.
    func synchronizeChapterScenePresentationAfterResponsiveAudioStart(
        runtime: VerifiedChapterSceneRuntime,
        identity: ChapterRuntimeRouteIdentity
    ) async throws -> ChapterScenePresentation {
#if DEBUG
        responsiveAudioPresentationSyncDiagnosticForTesting = "entered"
#endif
        while true {
            // A short finite approach may cross into its interaction bed while
            // the route is preparing the first playing presentation. That
            // automatic boundary owns the same journal and cursor-authority
            // handoff, so let it settle before inspecting either authority.
            await awaitResponsiveAudioAutomaticBoundaryDurabilityIfNeeded()
            try Task.checkCancellation()
            let initialInputIsAdmitted = admitsChapterRuntimeInput(identity)
            let initialRuntimeIsCurrent = runtimeMatchesCurrentRoute(
                runtime,
                identity: identity
            )
            let initialSessionIsActive = committedState.activeChapter?
                .responsiveAudioSessionIsActive == true
            let initialCursorIsCurrent =
                runtime.controller.presentation.cursor.chapter.id
                    == identity.chapterID
                && runtime.controller.presentation.cursor.packageID
                    == identity.packageID
                && runtime.controller.presentation.cursor.beat.id
                    == identity.beatID
                && runtime.controller.presentation.cursor
                    .responsiveAudioProgram != nil
            guard initialInputIsAdmitted,
                  initialRuntimeIsCurrent,
                  initialSessionIsActive,
                  initialCursorIsCurrent else {
#if DEBUG
                responsiveAudioPresentationSyncDiagnosticForTesting =
                    "initial-guard;input=\(initialInputIsAdmitted)"
                    + ",runtime=\(initialRuntimeIsCurrent)"
                    + ",session=\(initialSessionIsActive)"
                    + ",cursor=\(initialCursorIsCurrent)"
#endif
                throw JourneyChapterRuntimeError.routeAuthorityChanged
            }

            let synchronized: ChapterScenePresentation
            do {
                synchronized = try await runtime.controller
                    .synchronizeResponsiveAudioPresentation(
                        preserving: nil,
                        directManipulation: nil
                    )
            } catch {
#if DEBUG
                responsiveAudioPresentationSyncDiagnosticForTesting =
                    "controller-error,type="
                    + Self.responsiveAudioCursorErrorType(error)
#endif
                throw error
            }

            // The boundary can be admitted after the first wait and while the
            // scene controller reads its committer. Awaiting again closes that
            // window. Only a strictly forward, audio-only delta may retry;
            // every scene, route or interaction change still fails closed.
            await awaitResponsiveAudioAutomaticBoundaryDurabilityIfNeeded()
            try Task.checkCancellation()
            let finalInputIsAdmitted = admitsChapterRuntimeInput(identity)
            let finalRuntimeIsCurrent = runtimeMatchesCurrentRoute(
                runtime,
                identity: identity
            )
            let finalIdentityIsCurrent = identity == chapterRuntimeRouteIdentity(
                for: identity.chapterID,
                viewportCropID: identity.viewportCropID,
                reduceMotion: identity.reduceMotion
            )
            let finalSessionIsActive = committedState.activeChapter?
                .responsiveAudioSessionIsActive == true
            let finalStateIsCurrent = synchronized.journeyState == committedState
            let finalCursorIsCurrent =
                synchronized.cursor.chapter.id == identity.chapterID
                && synchronized.cursor.packageID == identity.packageID
                && synchronized.cursor.beat.id == identity.beatID
            let finalPresentationIsCurrent =
                runtime.controller.presentation == synchronized
            if !finalStateIsCurrent,
               finalInputIsAdmitted,
               finalRuntimeIsCurrent,
               finalIdentityIsCurrent,
               finalSessionIsActive,
               finalCursorIsCurrent,
               finalPresentationIsCurrent,
               ResponsiveAudioPresentationRebasePolicy.decide(
                   published: synchronized.journeyState,
                   committed: committedState
               ) == .rebase {
#if DEBUG
                responsiveAudioPresentationSyncDiagnosticForTesting =
                    "retry-audio-authority"
#endif
                continue
            }
            guard finalInputIsAdmitted,
                  finalRuntimeIsCurrent,
                  finalIdentityIsCurrent,
                  finalSessionIsActive,
                  finalStateIsCurrent,
                  finalCursorIsCurrent,
                  finalPresentationIsCurrent else {
#if DEBUG
                responsiveAudioPresentationSyncDiagnosticForTesting =
                    "final-guard;input=\(finalInputIsAdmitted)"
                    + ",runtime=\(finalRuntimeIsCurrent)"
                    + ",identity=\(finalIdentityIsCurrent)"
                    + ",session=\(finalSessionIsActive)"
                    + ",state=\(finalStateIsCurrent)"
                    + ",cursor=\(finalCursorIsCurrent)"
                    + ",presentation=\(finalPresentationIsCurrent)"
#endif
                throw JourneyChapterRuntimeError.routeAuthorityChanged
            }
#if DEBUG
            responsiveAudioPresentationSyncDiagnosticForTesting = "succeeded"
#endif
            return synchronized
        }
    }

    /// Reprojects a scene only after the exact physical-pause episode has
    /// reached durable storage. Lifecycle commits may update the visit time,
    /// narration and responsive-audio snapshot together, so they deliberately
    /// use the controller's full restore boundary rather than weakening the
    /// audio-only rebase contract used after an explicit start.
    func refreshChapterScenePresentationAfterPhysicalPause(
        _ pauseEvent: ResponsiveAudioPhysicalPauseEvent,
        runtime: VerifiedChapterSceneRuntime,
        identity: ChapterRuntimeRouteIdentity
    ) async throws -> ChapterScenePresentation {
        try Task.checkCancellation()
        guard responsiveAudioPhysicalPauseEvent == pauseEvent,
              pendingChapterRuntimePhysicalPauseEvent(for: identity)
                == pauseEvent,
              chapterRuntimeRouteAuthorityAdmitsInput(identity),
              runtimeMatchesCurrentRoute(runtime, identity: identity) else {
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        guard await suspensionEpisodeCoordinator.awaitCurrentFlush()
                == .durable else {
            throw JourneyChapterRuntimeError.persistenceUnavailable
        }

        try Task.checkCancellation()
        guard responsiveAudioPhysicalPauseEvent == pauseEvent,
              pendingChapterRuntimePhysicalPauseEvent(for: identity)
                == pauseEvent,
              chapterRuntimeRouteAuthorityAdmitsInput(identity),
              runtimeMatchesCurrentRoute(runtime, identity: identity) else {
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }

        let restored = try await runtime.controller.restorePresentation(
            preserving: nil,
            directManipulation: nil
        )

        try Task.checkCancellation()
        guard responsiveAudioPhysicalPauseEvent == pauseEvent,
              pendingChapterRuntimePhysicalPauseEvent(for: identity)
                == pauseEvent,
              chapterRuntimeRouteAuthorityAdmitsInput(identity),
              runtimeMatchesCurrentRoute(runtime, identity: identity),
              restored.journeyState == committedState,
              restored.cursor.chapter.id == identity.chapterID,
              restored.cursor.packageID == identity.packageID,
              restored.cursor.beat.id == identity.beatID,
              runtime.controller.presentation == restored else {
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        return restored
    }

    /// Stops transport only when the failed presentation synchronization still
    /// belongs to the exact initiating route. If route or beat authority already
    /// moved, its replacement owns audio retirement and this stale caller may
    /// not stop the successor controller.
    func failClosedResponsiveAudioPresentationSynchronization(
        runtime: VerifiedChapterSceneRuntime,
        identity: ChapterRuntimeRouteIdentity,
        playbackLease: ResponsiveAudioPlaybackStartLease
    ) async {
        guard runtimeMatchesCurrentRoute(runtime, identity: identity),
              identity == chapterRuntimeRouteIdentity(
                  for: identity.chapterID,
                  viewportCropID: identity.viewportCropID,
                  reduceMotion: identity.reduceMotion
              ), responsiveAudioExplicitStartAuthorizationForCurrentRoute()
                == playbackLease else { return }
        responsiveAudioController?.stopWithoutPersisting()
        responsiveAudioController = nil
        responsiveAudioLifecycleToken = UUID()
        cancelPendingResponsiveAudioBinding()
        await retireResponsiveAudioCursorProtection()
        responsiveAudioFailure =
            "The authored sound paused before its scene could be synchronized."
    }

    private func beginResponsiveAudioSceneMutationIfNeeded(
        runtime: VerifiedChapterSceneRuntime,
        identity: ChapterRuntimeRouteIdentity
    ) async throws -> ResponsiveAudioSceneMutationGate.Token? {
        let requiresResponsiveAudio = chapterCursor?.responsiveAudioProgram != nil
        if requiresResponsiveAudio {
            await awaitResponsiveAudioAutomaticBoundaryDurabilityIfNeeded()
            guard !Task.isCancelled,
                  runtimeMatchesCurrentRoute(runtime, identity: identity) else {
                throw JourneyChapterRuntimeError.routeAuthorityChanged
            }
            guard !responsiveAudioSceneMutationGate
                .hasActiveResponsiveSceneMutation else {
                // Never touch or rebind the controller while an admitted scene
                // input still owns its Journey commit and audio follow-up.
                throw JourneyChapterRuntimeError.authoredAudioUnavailable
            }
            if !responsiveAudioControllerMatchesCurrentJourney() {
                cancelPendingResponsiveAudioBinding()
                responsiveAudioController?.stopWithoutPersisting()
                responsiveAudioController = nil
                if let chapterCoordinator {
                    configureResponsiveAudioIfAvailable(
                        coordinator: chapterCoordinator
                    )
                }
            }
            await awaitResponsiveAudioBindingIfNeeded()
            await awaitResponsiveAudioAutomaticBoundaryDurabilityIfNeeded()
            guard !Task.isCancelled,
                  runtimeMatchesCurrentRoute(runtime, identity: identity) else {
                throw JourneyChapterRuntimeError.routeAuthorityChanged
            }
            guard responsiveAudioControllerMatchesCurrentJourney() else {
                throw JourneyChapterRuntimeError.authoredAudioUnavailable
            }
        }
        while true {
            do {
                return try responsiveAudioSceneMutationGate.begin(
                    requiresResponsiveAudio: requiresResponsiveAudio,
                    controllerIsReady: !requiresResponsiveAudio
                        || responsiveAudioControllerMatchesCurrentJourney()
                )
            } catch ResponsiveAudioSceneMutationGateError
                .automaticBoundaryDurabilityPending {
                await awaitResponsiveAudioAutomaticBoundaryDurabilityIfNeeded()
                guard !Task.isCancelled,
                      runtimeMatchesCurrentRoute(
                          runtime,
                          identity: identity
                      ), !requiresResponsiveAudio
                        || responsiveAudioControllerMatchesCurrentJourney() else {
                    throw JourneyChapterRuntimeError.routeAuthorityChanged
                }
            } catch {
                throw JourneyChapterRuntimeError.authoredAudioUnavailable
            }
        }
    }

    private func responsiveAudioControllerMatchesCurrentJourney() -> Bool {
        guard let controller = responsiveAudioController,
              let program = chapterCursor?.responsiveAudioProgram,
              controller.runtime.program.id == program.id,
              controller.runtime.program.scope == program.scope,
              let interaction = committedState.activeChapter?.interaction,
              interaction.interactionID == program.scope.interactionID else {
            return false
        }

        switch interaction.progress {
        case let .transform(progress):
            guard controller.runtime.causalStage?.completedStageCount
                == progress.completedStageCount else {
                return false
            }
        default:
            guard controller.runtime.causalStage == nil else { return false }
        }

        switch (interaction.phase, controller.runtime.stage) {
        case (.complete, .consequence), (.complete, .completed),
             (.ready, .approach), (.ready, .interaction),
             (.active, .approach), (.active, .interaction):
            return true
        default:
            return false
        }
    }

    private func finishResponsiveAudioSceneMutationIfNeeded(
        _ token: ResponsiveAudioSceneMutationGate.Token?,
        startDrain: Bool = true
    ) -> Bool {
        guard let token else { return false }
        var queuedDurability = false
        responsiveAudioSceneMutationGate.finish(token) { intents in
            queuedDurability = materializeDeferredResponsiveAudioIntents(
                intents
            )
        }
        releaseResponsiveAudioMutationWaitersIfQuiescent()
        if startDrain, queuedDurability {
            startWriteDrainIfNeeded()
        }
        return queuedDurability
    }

    /// Deferred intents are appended while the scene's persistence mutation
    /// still owns the barrier. Only after that mutation is released may the
    /// drain start; no authority-transition task can interleave on MainActor
    /// between these synchronous steps.
    private func finishResponsiveAudioSceneAndPersistenceMutation(
        _ audioToken: ResponsiveAudioSceneMutationGate.Token?,
        persistenceMutation: JourneyPersistenceMutationToken
    ) {
        let queuedDurability = finishResponsiveAudioSceneMutationIfNeeded(
            audioToken,
            startDrain: false
        )
        finishPersistenceMutation(persistenceMutation)
        if queuedDurability {
            startWriteDrainIfNeeded()
        }
    }

    private func materializeDeferredResponsiveAudioIntents(
        _ intents: ResponsiveAudioSceneMutationGate.DeferredIntents
    ) -> Bool {
        var queuedDurability = false
        if let automaticBoundary = intents.automaticBoundary {
            queuedDurability = materializeResponsiveAudioAutomaticBoundary(
                automaticBoundary
            )
        }
        var audioAction: JourneyAction?
        do {
            if let phase = intents.phase,
               let responsiveAudioController {
                _ = try responsiveAudioController.selectInteractionPhase(
                    phase
                )
            }
            if intents.suspensionEpochMillis != nil {
                // This second snapshot intentionally supersedes a deferred
                // phase action so suspension stores one exact combined cursor.
                normalizeEphemeralResponsiveAudioPhaseForDurability()
                if let responsiveAudioController {
                    audioAction = try responsiveAudioController.pauseAndPersist()
                }
            }
        } catch {
            responsiveAudioController?.stopWithoutPersisting()
            responsiveAudioController = nil
            cancelPendingResponsiveAudioBinding()
            responsiveAudioFailure =
                "The authored sound paused before its place could be verified."
            audioAction = nil
        }

        var actions: [JourneyAction] = []
        if let audioAction { actions.append(audioAction) }
        if let suspensionEpochMillis = intents.suspensionEpochMillis {
            actions.append(
                .suspendChapter(atEpochMillis: suspensionEpochMillis)
            )
        }
        return appendPendingActionsWithoutStartingDrain(actions)
            || queuedDurability
    }

    private func adoptChapterSceneTransition(
        _ transition: ChapterSceneTransition
    ) async throws {
        guard let committer else {
            throw JourneyChapterRuntimeError.persistenceUnavailable
        }
        let commits = [transition.durableCommit, transition.responsiveAudioCommit]
            .compactMap { $0 }
        let previousState = committedState
        if let latest = commits.last {
            committedState = latest.state
            lastCommittedSequence = latest.sequence
            state = latest.state
            do {
                try await rotateResponsiveAudioCursorAuthorityIfNeeded()
            } catch {
                failClosedResponsiveAudioCursorImmediately(
                    diagnostic: "handoffAfterSceneTransition;error="
                        + Self.responsiveAudioCursorErrorType(error)
                )
                throw JourneyChapterRuntimeError.persistenceUnavailable
            }
            refreshChapterPresentation(bindResponsiveAudio: false)
            await recordHistoricalExperienceTransition(
                from: previousState,
                to: latest.state
            )
        }

        if let issue = transition.postCommitIssue {
            switch issue {
            case .audioConsequenceAuthorityInvalid,
                 .audioCausalStageAuthorityInvalid,
                 .audioBridgeFailed,
                 .audioSnapshotAuthorityMismatch,
                 .audioCausalStageSnapshotMismatch,
                 .audioFollowUpRejected,
                 .audioFollowUpDivergedFromPreflight:
                cancelPendingResponsiveAudioBinding()
                responsiveAudioController?.stopWithoutPersisting()
                responsiveAudioController = nil
                responsiveAudioFailure =
                    "The historical consequence was saved; its sound transition was withheld."
            case .durableStateDivergedFromPreflight:
                contentFailure =
                    "The historical consequence was saved. Return to the road before continuing."
            }
        }

        if commits.contains(where: \.requiresCheckpoint), let latest = commits.last {
            do {
                try await committer.checkpoint(latest)
            } catch let error as DurableJourneyCommitterError {
                if case .staleCheckpoint = error {
                    // A newer route or content transition already owns the
                    // journal. Replay remains complete and authoritative.
                } else {
                    failPersistenceAfterCommit(
                        message: "Progress was recorded, but its checkpoint could not be completed."
                    )
                    throw JourneyChapterRuntimeError.persistenceUnavailable
                }
            } catch {
                failPersistenceAfterCommit(
                    message: "Progress was recorded, but its checkpoint could not be completed."
                )
                throw JourneyChapterRuntimeError.persistenceUnavailable
            }
        }
    }

    func purchaseCompleteWork() {
        guard lockedRoad != nil else { return }
        guard completeWorkPurchaseIsAvailable else {
            purchaseState = .failed("The complete work is unavailable.")
            return
        }
        guard let commerceClient else {
            purchaseState = .failed("The App Store could not be reached. The free roads remain available offline.")
            return
        }
        purchaseState = .purchasing
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                switch try await commerceClient.purchase() {
                case let .success(snapshot):
                    applyEntitlementSnapshot(snapshot)
                    openLockedRoadAfterPurchase()
                case .pending:
                    purchaseState = .pending
                case .cancelled:
                    purchaseState = .idle
                }
            } catch {
                purchaseState = .failed(
                    "The purchase could not be completed. Your saved place has not changed."
                )
            }
        }
    }

    func restoreCompleteWork() {
        guard lockedRoad != nil else { return }
        guard completeWorkRestoreIsAvailable else {
            purchaseState = .failed("The complete work is unavailable.")
            return
        }
        guard let commerceClient else {
            purchaseState = .failed("The App Store could not be reached. The free roads remain available offline.")
            return
        }
        purchaseState = .restoring
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await commerceClient.restorePurchases()
            switch outcome {
            case let .updated(snapshot), let .retainedCached(snapshot, _):
                applyEntitlementSnapshot(snapshot)
            }
            if entitlementSnapshot?.grantsAccess(at: Date()) == true {
                openLockedRoadAfterPurchase()
            } else {
                purchaseState = .failed("No purchase for the complete work was found.")
            }
        }
    }

    private func openChapter(_ chapter: ChapterIndexEntry) {
        contentFailure = nil
        if let runtimeContentSnapshot,
           runtimeContentSnapshot.repository.chapter(chapter.id) != nil {
            if chapter.packageID != LaunchContent.essentialPackageID {
                guard let packageRow = downloadPresentation?.packageRows.first(where: {
                    $0.id == chapter.packageID
                }) else {
                    offlineChapterRequest = OfflineChapterRequest(
                        chapterID: chapter.id,
                        packageID: chapter.packageID
                    )
                    return
                }
                if case .requiresNewerApp = packageRow.state {
                    contentFailure = "Update the app to open the newer chapter files already on this iPhone."
                    return
                }
                guard packageRow.state
                    .allowsVerifiedInstalledGenerationOpen else {
                    offlineChapterRequest = OfflineChapterRequest(
                        chapterID: chapter.id,
                        packageID: chapter.packageID
                    )
                    return
                }
            }
            if openVerifiedChapter(chapter, snapshot: runtimeContentSnapshot) {
                offlineChapterRequest = nil
            }
            return
        }
#if DEBUG
        if chapter.id == DevelopmentFirstFarmersRepository.chapterID {
            openDevelopmentFirstFarmers()
            return
        }
#endif
        if chapter.packageID != LaunchContent.essentialPackageID {
            if let packageRow = downloadPresentation?.packageRows.first(where: {
                $0.id == chapter.packageID
            }) {
                if case .requiresNewerApp = packageRow.state {
                    contentFailure = "Update the app to open the newer chapter files already on this iPhone."
                    return
                }
            }
            if contentFailure == nil {
                offlineChapterRequest = OfflineChapterRequest(
                    chapterID: chapter.id,
                    packageID: chapter.packageID
                )
            }
            return
        }
        contentFailure = "This chapter is not installed in this build."
    }

    @discardableResult
    private func openVerifiedChapter(
        _ chapter: ChapterIndexEntry,
        snapshot: VerifiedJourneyContentSnapshot
    ) -> Bool {
        openVerifiedChapter(
            chapter,
            authority: snapshot.chapterRuntimeAuthority,
            futureReleaseID: nil
        )
    }

    @discardableResult
    private func openVerifiedChapter(
        _ chapter: ChapterIndexEntry,
        authority: VerifiedChapterRuntimeContentAuthority,
        futureReleaseID: ReleaseID?
    ) -> Bool {
        let coordinator = ChapterCoordinator(repository: authority.repository)
        guard authority.repository.chapter(chapter.id) != nil,
              authority.repository.packageID(for: chapter.id) == chapter.packageID,
              let contentVersion = authority.repository.contentVersion(for: chapter.id),
              authority.packageRootURL(for: chapter.packageID) != nil,
              authority.verifiedPackage(for: chapter.packageID) != nil,
              (
                  chapter.packageID == LaunchContent.essentialPackageID
                      || authority.assetFailureAuthority(
                          for: chapter.packageID
                      ) != nil
              ) else {
            contentFailure = "The chapter files could not be verified. Saved progress has not changed."
            return false
        }

        do {
            var actions: [JourneyAction] = []
            var planningState = committedState
            let installed = committedState.installedContent.filter {
                $0.packageID == chapter.packageID
            }
            guard installed.count <= 1,
                  !installed.contains(where: { $0.version != contentVersion }) else {
                throw ChapterCoordinatorError.installedVersionMismatch(chapter.packageID)
            }
            if installed.isEmpty {
                let install = JourneyAction.installContent(
                    packageID: chapter.packageID,
                    version: contentVersion
                )
                let effects = previewReducer.reduce(
                    state: &planningState,
                    action: install
                )
                guard !effects.contains(where: {
                    if case .rejected = $0 { return true }
                    return false
                }) else {
                    throw ChapterCoordinatorError.installedVersionMismatch(
                        chapter.packageID
                    )
                }
                actions.append(install)
            }

            if planningState.chapterSession(chapter.id) == nil {
                actions.append(contentsOf: try coordinator.beginActions(
                    chapterID: chapter.id,
                    state: planningState
                ))
            } else {
                actions.append(contentsOf: try coordinator.resumeActions(
                    chapterID: chapter.id,
                    state: planningState
                ))
            }
            actions.append(
                .recordChapterVisit(
                    chapterID: chapter.id,
                    atEpochMillis: Self.nowEpochMillis()
                )
            )
            chapterTransitionIsPending = true
            enqueueOrderedJourneyTransition(
                actions,
                routeAuthorityCommit: { [weak self] in
                self?.activeFutureReleaseID = futureReleaseID
                self?.chapterCoordinator = coordinator
                }
            )
            return true
        } catch {
            contentFailure = "The chapter files could not be joined to saved progress. Saved progress has not changed."
            return false
        }
    }

    private func openPendingChapterIfAvailable() {
        guard !isRestoring,
              !persistenceIsLocked,
              !chapterTransitionIsPending,
              let request = offlineChapterRequest,
              let chapter = FoundationCatalog.chapters.first(where: {
                  $0.id == request.chapterID && $0.packageID == request.packageID
              }),
              let snapshot = runtimeContentSnapshot,
              snapshot.repository.chapter(request.chapterID) != nil,
              downloadPresentation?.packageRows.first(where: {
                  $0.id == request.packageID
              })?.state.allowsVerifiedInstalledGenerationOpen == true else {
            return
        }
        if openVerifiedChapter(chapter, snapshot: snapshot) {
            offlineChapterRequest = nil
        }
    }

#if DEBUG
    private func openDevelopmentFirstFarmers() {
        guard let developmentFirstFarmers,
              let chapterCoordinator else {
            contentFailure = "The First Farmers development payload could not be verified. Saved progress has not changed."
            return
        }

        do {
            var actions: [JourneyAction] = []
            let packageID = DevelopmentFirstFarmersRepository.packageID
            let contentVersion = developmentFirstFarmers.repository.contentVersion
            let installed = committedState.installedContent.filter {
                $0.packageID == packageID
            }
            guard installed.count <= 1,
                  !installed.contains(where: { $0.version != contentVersion }) else {
                throw ChapterCoordinatorError.installedVersionMismatch(packageID)
            }
            if installed.isEmpty {
                actions.append(
                    .installContent(packageID: packageID, version: contentVersion)
                )
            }

            if committedState.chapterSession(DevelopmentFirstFarmersRepository.chapterID) == nil {
                actions.append(contentsOf: try chapterCoordinator.beginActions(
                    chapterID: DevelopmentFirstFarmersRepository.chapterID,
                    state: committedState
                ))
            } else {
                actions.append(contentsOf: try chapterCoordinator.resumeActions(
                    chapterID: DevelopmentFirstFarmersRepository.chapterID,
                    state: committedState
                ))
            }
            actions.append(
                .recordChapterVisit(
                    chapterID: DevelopmentFirstFarmersRepository.chapterID,
                    atEpochMillis: Self.nowEpochMillis()
                )
            )
            chapterTransitionIsPending = true
            enqueueOrderedJourneyTransition(actions)
        } catch {
            contentFailure = "The First Farmers development payload could not be joined to saved progress. Saved progress has not changed."
        }
    }
#endif

    private func openLockedRoadAfterPurchase() {
        guard let chapter = lockedRoad?.chapter else { return }
        lockedRoad = nil
        purchaseState = .idle
        openChapter(chapter)
    }

    func startLifecycleObservation() {
        guard audioSessionLifecycleObserver == nil else { return }
        let observer = JourneyAudioSessionLifecycleObserver { [weak self] event in
            guard let self else { return }
            switch event {
            case .interruptionBegan:
                self.requestSuspension(.audioInterruption)
            case .interruptionEnded:
                // Playback remains user-controlled. The episode is reset by
                // an explicit play request, never by a system notification.
                break
            case let .routeChanged(reasonRawValue):
#if DEBUG
                self.responsiveAudioRouteChangeDiagnosticForTesting =
                    Self.audioRouteChangeReasonDiagnostic(reasonRawValue)
#endif
                guard self.journeyAudioRequiresRouteSuspension else {
                    return
                }
                self.requestSuspension(.audioRouteChange)
            }
        }
        audioSessionLifecycleObserver = observer
        observer.start()
    }

#if DEBUG
    private static func audioRouteChangeReasonDiagnostic(
        _ rawValue: UInt?
    ) -> String {
        switch rawValue {
        case 0: "unknown(0)"
        case 1: "newDeviceAvailable(1)"
        case 2: "oldDeviceUnavailable(2)"
        case 3: "categoryChange(3)"
        case 4: "override(4)"
        case 6: "wakeFromSleep(6)"
        case 7: "noSuitableRouteForCategory(7)"
        case 8: "routeConfigurationChange(8)"
        case let rawValue?: "unrecognized(\(rawValue))"
        case nil: "missing"
        }
    }
#endif

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            suspensionEpisodeCoordinator.sceneBecameActive()
            causalHapticTransport.resumeAfterSuspension()
            resumeDeferredContentAuthorityRetryIfPossible()
        case .inactive:
            requestSuspension(.sceneInactive)
        case .background:
            requestSuspension(.sceneBackground)
        @unknown default:
            requestSuspension(.sceneInactive)
        }
    }

    func suspend() {
        requestSuspension(.sceneInactive)
    }

    private func requestSuspension(_ trigger: JourneySuspensionTrigger) {
        guard !isRestoring, !persistenceIsLocked else { return }
        // A start that has not yet crossed transport.play must never race a
        // lifecycle pause and publish a false playing state afterwards.
        responsiveAudioLifecycleToken = UUID()
        responsiveAudioPlaybackStartTask?.cancel()
        normalizeEphemeralResponsiveAudioPhaseForDurability()
        let priorEpisodeID = suspensionEpisodeCoordinator.episodeID
        let admittedEpisodeID = suspensionEpisodeCoordinator
            .requestSuspension(trigger)
        if priorEpisodeID == nil, admittedEpisodeID != nil {
            publishResponsiveAudioPhysicalPause(trigger)
        }
    }

    private func publishResponsiveAudioPhysicalPause(
        _ trigger: JourneySuspensionTrigger
    ) {
        responsiveAudioPhysicalPauseGeneration &+= 1
        let reason: ResponsiveAudioPhysicalPauseReason = switch trigger {
        case .sceneInactive: .sceneInactive
        case .sceneBackground: .sceneBackground
        case .audioInterruption: .interruption
        case .audioRouteChange: .audioRouteChange
        case .cursorDurabilityFailure: .cursorDurabilityFailure
        }
        let event = ResponsiveAudioPhysicalPauseEvent(
            generation: responsiveAudioPhysicalPauseGeneration,
            reason: reason
        )
        unresolvedResponsiveAudioPhysicalPauseEvent = event
        // Every physical event supersedes the preceding route gate, including
        // events received on the world or another surface where no chapter
        // gate can be constructed.
        chapterRuntimePhysicalPauseGate = nil
        chapterRuntimePhysicalPauseGate = makeChapterRuntimePhysicalPauseGate(
            event: event
        )
        // The input gate above closes in this MainActor turn before observers
        // can receive the event. No post-pause touch, semantic action or Hear
        // request can therefore be mistaken for pre-pause work.
        responsiveAudioPhysicalPauseEvent = event
    }

    private func makeChapterRuntimePhysicalPauseGate(
        event: ResponsiveAudioPhysicalPauseEvent
    ) -> ChapterRuntimePhysicalPauseGate? {
        if let persistenceAuthority = persistenceAuthorityFence.currentReceipt,
           let authority = currentChapterRuntimeAuthority(),
           case let .chapter(chapterID) = committedState.route,
           let session = committedState.activeChapter,
           session.chapterID == chapterID,
           let beatID = session.beatID,
           let verifiedPackage = authority.verifiedPackage(
               for: session.packageID
           ) {
            return ChapterRuntimePhysicalPauseGate(
                event: event,
                persistenceAuthority: persistenceAuthority,
                contentRevision: authority.revision,
                chapterID: chapterID,
                packageID: session.packageID,
                packageManifestDigest:
                    verifiedPackage.manifest.manifestDigest,
                beatID: beatID
            )
        }
        return nil
    }

    /// The route action has already crossed the synchronised journal boundary
    /// and `committedState` contains its successor, but SwiftUI has not yet
    /// received that state. Move the same physical event to that successor in
    /// this turn so neither the new beat nor a newly opened chapter can admit
    /// input in the publication gap. A durable world destination owns the
    /// final resolution because no later suspension callback is guaranteed.
    private func reconcilePhysicalPauseAtDurableRouteBoundary(
        boundary: OrderedRouteAuthorityBoundary?,
        resolvedRecoveryEvent: ResponsiveAudioPhysicalPauseEvent? = nil
    ) {
        let physicalPauseEvent =
            unresolvedResponsiveAudioPhysicalPauseEvent
        preQuiescedSuspensionAction = nil
        let reachesWorld: Bool
        if case .worldExit? = boundary,
           case .world = committedState.route {
            reachesWorld = true
        } else {
            reachesWorld = false
        }
        if reachesWorld || (resolvedRecoveryEvent != nil
            && unresolvedResponsiveAudioPhysicalPauseEvent
                == resolvedRecoveryEvent) {
            unresolvedResponsiveAudioPhysicalPauseEvent = nil
            preQuiescedSuspensionFailed = false
            suspensionEpisodeCoordinator.physicalPauseDidResolve()
        }
        chapterRuntimePhysicalPauseGate = reachesWorld ? nil : physicalPauseEvent.flatMap {
            makeChapterRuntimePhysicalPauseGate(event: $0)
        }
    }

    /// Content publication can change the revision component of an otherwise
    /// identical route identity. Keep an unresolved physical pause attached
    /// to that new exact authority before the refreshed scene is exposed.
    private func rebasePhysicalPauseGateAfterContentAuthorityPublication() {
        guard let event = unresolvedResponsiveAudioPhysicalPauseEvent else {
            return
        }
        chapterRuntimePhysicalPauseGate =
            makeChapterRuntimePhysicalPauseGate(event: event)
    }

    private func chapterRuntimePhysicalPauseGateMatchesCurrentAuthority(
        _ gate: ChapterRuntimePhysicalPauseGate
    ) -> Bool {
        guard case let .chapter(chapterID) = committedState.route,
              chapterID == gate.chapterID,
              let session = committedState.activeChapter,
              session.chapterID == chapterID,
              session.packageID == gate.packageID,
              session.beatID == gate.beatID,
              persistenceAuthorityFence.currentReceipt
                == gate.persistenceAuthority,
              let authority = currentChapterRuntimeAuthority(),
              authority.revision == gate.contentRevision,
              authority.repository.packageID(for: chapterID)
                == gate.packageID,
              authority.verifiedPackage(for: gate.packageID)?
                .manifest.manifestDigest == gate.packageManifestDigest else {
            return false
        }
        return true
    }

    private func quiesceResponsiveAudioForSuspension(
        _ trigger: JourneySuspensionTrigger
    ) {
        stopOutgoingResponsiveAudioTailImmediately()
        causalHapticTransport.quiesceForSuspension()
        responsiveAudioCursorPump.stop()
        defer { cancelResponsiveAudioAutomaticBoundary() }
        guard !preQuiescedSuspensionFailed,
              preQuiescedSuspensionAction == nil,
              let controller = responsiveAudioController else {
            return
        }
        guard responsiveAudioControllerMatchesCurrentJourney() else {
            controller.stopWithoutPersisting()
            responsiveAudioController = nil
            cancelPendingResponsiveAudioBinding()
            return
        }
        do {
            // Physical render stop is synchronous. The action waits behind
            // any admitted scene mutation before it enters the journal.
            preQuiescedSuspensionAction = try controller
                .quiesceForSuspension(
                    responsiveAudioSuspensionReason(for: trigger)
                )
        } catch {
            controller.stopWithoutPersisting()
            responsiveAudioController = nil
            cancelPendingResponsiveAudioBinding()
            preQuiescedSuspensionFailed = true
            responsiveAudioFailure =
                "The authored sound paused before its place could be verified."
        }
    }

    private func performSuspensionFlush(
        trigger: JourneySuspensionTrigger
    ) async throws {
        let suspensionEpochMillis = Self.nowEpochMillis()
        stopOutgoingResponsiveAudioTailImmediately()
        causalHapticTransport.quiesceForSuspension()

        // Reservations begin at synchronous route admission and remain owned
        // until the session has published the resulting compositor state.
        // Waiting here closes the otherwise invisible gap between one queued
        // direct-manipulation sample completing and the next task starting.
#if DEBUG
        let isOrderedRecoverySecondEpisode =
            contentAuthorityRecoverySecondSuspensionProbeIsEnabled
            && suspensionEpisodeCoordinator.episodeID
                == orderedRecoveryEpochProbeSecondEpisodeID
        if isOrderedRecoverySecondEpisode {
            orderedRecoveryEpochProbeReachedReservationGate = true
            recordContentAuthorityBarrierMilestoneForTesting("e2:waiting")
        }
#endif
        await awaitChapterRuntimeInputReservationQuiescence()
#if DEBUG
        if isOrderedRecoverySecondEpisode {
            recordContentAuthorityBarrierMilestoneForTesting("e2:admitted")
        }
#endif
        await awaitResponsiveAudioSceneMutationQuiescence()
        guard !isRestoring, !persistenceIsLocked else {
            throw JourneyChapterRuntimeError.persistenceUnavailable
        }
        guard case .chapter = committedState.route,
              committedState.activeChapter != nil else {
            preQuiescedSuspensionAction = nil
            preQuiescedSuspensionFailed = false
            cancelPendingResponsiveAudioBinding()
            responsiveAudioController?.stopWithoutPersisting()
            responsiveAudioController = nil
            await retireResponsiveAudioCursorProtection()
            unresolvedResponsiveAudioPhysicalPauseEvent = nil
            chapterRuntimePhysicalPauseGate = nil
            suspensionEpisodeCoordinator.physicalPauseDidResolve()
#if DEBUG
            if isOrderedRecoverySecondEpisode {
                recordContentAuthorityBarrierMilestoneForTesting(
                    "e2:durable"
                )
                orderedRecoveryEpochProbeSecondEpisodeID = nil
                orderedRecoveryEpochProbeReachedReservationGate = false
            }
#endif
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.resumeDeferredContentAuthorityRetryIfPossible()
            }
            return
        }
        if preQuiescedSuspensionFailed {
            preQuiescedSuspensionFailed = false
            preQuiescedSuspensionAction = nil
            await retireResponsiveAudioCursorProtection()
#if DEBUG
            if contentAuthorityFailedPauseRecoveryProbeIsEnabled {
                recordContentAuthorityBarrierMilestoneForTesting(
                    "e1:flush-failed"
                )
            }
#endif
            throw JourneyChapterRuntimeError.authoredAudioUnavailable
        }
        if let responsiveAudioController,
           !responsiveAudioControllerMatchesCurrentJourney() {
            responsiveAudioController.stopWithoutPersisting()
            self.responsiveAudioController = nil
            preQuiescedSuspensionAction = nil
            cancelPendingResponsiveAudioBinding()
        }
        var actions: [JourneyAction] = []
        if let preQuiescedSuspensionAction {
            if let responsiveAudioController,
               responsiveAudioControllerMatchesCurrentJourney() {
                // The scene transaction may have advanced a causal/phase
                // state while the transport was already stopped. Capture the
                // same physical cursor under that now-durable non-position.
                actions.append(
                    try responsiveAudioController.quiesceForSuspension(
                        responsiveAudioSuspensionReason(for: trigger)
                    )
                )
            } else if responsiveAudioController == nil {
                actions.append(preQuiescedSuspensionAction)
            }
            self.preQuiescedSuspensionAction = nil
        } else if let responsiveAudioController,
                  responsiveAudioControllerMatchesCurrentJourney() {
            do {
                actions.append(
                    try responsiveAudioController.quiesceForSuspension(
                        responsiveAudioSuspensionReason(for: trigger)
                    )
                )
            } catch {
                responsiveAudioController.stopWithoutPersisting()
                responsiveAudioFailure =
                    "The authored sound paused before its place could be verified."
                throw error
            }
        }
        cancelPendingResponsiveAudioBinding()
        await retireResponsiveAudioCursorProtection()
        actions.append(
            .suspendChapter(atEpochMillis: suspensionEpochMillis)
        )
        do {
            try await enqueueAndAwaitDurability(actions)
        } catch {
#if DEBUG
            if suspensionPersistenceRetryProbeIsEnabled {
                recordSuspensionPersistenceRetryMilestoneForTesting(
                    "append-failed"
                )
            }
#endif
            throw error
        }
#if DEBUG
        responsiveAudioDurableCursorForTesting = committedState
            .activeChapter?.responsiveAudioSnapshot
#endif
        preQuiescedSuspensionFailed = false
    }

    private func responsiveAudioSuspensionReason(
        for trigger: JourneySuspensionTrigger
    ) -> ResponsiveAudioSuspensionReason {
        switch trigger {
        case .sceneInactive: .sceneInactive
        case .sceneBackground: .sceneBackground
        case .audioInterruption: .interruption
        case .audioRouteChange: .routeChange
        case .cursorDurabilityFailure: .sceneInactive
        }
    }

    private func awaitResponsiveAudioSceneMutationQuiescence() async {
        while responsiveAudioSceneMutationGate
            .hasActiveResponsiveSceneMutation
                || responsiveAudioSceneMutationGate
                    .automaticBoundaryDurabilityIsPending {
            await withCheckedContinuation { continuation in
                responsiveAudioSceneMutationWaiters.append(continuation)
            }
        }
    }

    private func awaitResponsiveAudioAutomaticBoundaryDurabilityIfNeeded()
        async {
        while responsiveAudioSceneMutationGate
            .automaticBoundaryDurabilityIsPending {
            await withCheckedContinuation { continuation in
                responsiveAudioAutomaticBoundaryWaiters.append(continuation)
            }
        }
    }

    private func releaseResponsiveAudioMutationWaitersIfQuiescent() {
        guard !responsiveAudioSceneMutationGate
                .hasActiveResponsiveSceneMutation,
              !responsiveAudioSceneMutationGate
                .automaticBoundaryDurabilityIsPending else { return }
        releaseResponsiveAudioSceneMutationWaiters()
    }

    private func releaseResponsiveAudioSceneMutationWaiters() {
        guard !responsiveAudioSceneMutationWaiters.isEmpty else { return }
        let waiters = responsiveAudioSceneMutationWaiters
        responsiveAudioSceneMutationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func releaseResponsiveAudioAutomaticBoundaryWaiters() {
        guard !responsiveAudioAutomaticBoundaryWaiters.isEmpty else { return }
        let waiters = responsiveAudioAutomaticBoundaryWaiters
        responsiveAudioAutomaticBoundaryWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    @discardableResult
    private func finishResponsiveAudioAutomaticBoundary(
        _ token: ResponsiveAudioSceneMutationGate.AutomaticBoundaryToken
    ) -> Bool {
        guard responsiveAudioSceneMutationGate.finishAutomaticBoundary(
            token
        ) else { return false }
        releaseResponsiveAudioAutomaticBoundaryWaiters()
        releaseResponsiveAudioMutationWaitersIfQuiescent()
        return true
    }

    private func cancelResponsiveAudioAutomaticBoundary() {
        guard responsiveAudioSceneMutationGate.cancelAutomaticBoundary()
        else { return }
        releaseResponsiveAudioAutomaticBoundaryWaiters()
        releaseResponsiveAudioMutationWaitersIfQuiescent()
    }

    /// Installs the exact program resolved by ChapterCoordinator after its
    /// package and Journey restoration have both crossed integrity checks.
    func bindResponsiveAudio(
        plan: ResponsiveAudioRestorationPlan,
        restoration: JourneyRestoration,
        resolver: any OfflineAudioAssetResolving
    ) throws {
        responsiveAudioController?.stopWithoutPersisting()
        cancelResponsiveAudioAutomaticBoundary()
        let transport = NativeTimelineTransport(
            preferences: experiencePreferences
        )
        let controller = try ResponsiveAudioProgramController(
            restorationPlan: plan,
            restoration: restoration,
            transport: transport,
            resolver: resolver
        )
        if controller.runtime.stage == .interaction,
           controller.runtime.interactionPhase != .waiting {
            // Interaction response beds are never restoration authority. The
            // durable historical state restores exactly; its live bed starts
            // from the neutral waiting composition.
            _ = try controller.selectInteractionPhase(.waiting)
        }
        responsiveAudioController = controller
#if DEBUG
        responsiveAudioControllerBindingForTesting &+= 1
        responsiveAudioDurableCursorForTesting = plan.snapshot
        responsiveAudioAuthorityProbeTransportForTesting = (
            ObjectIdentifier(controller),
            transport
        )
        responsiveAudioAuthoritySwapContextForTesting =
            JourneyUITestResponsiveAudioBindingContext(
                plan: plan,
                restoration: restoration,
                resolver: resolver
            )
#endif
        controller.setAutomaticBoundaryActionHandler {
            [weak self, weak controller] action in
            guard let self, let controller else { return }
            self.receiveResponsiveAudioAutomaticBoundary(
                action,
                controller: controller
            )
        }
        controller.applyPreferences(experiencePreferences)
        responsiveAudioFailure = nil
    }

    private func receiveResponsiveAudioAutomaticBoundary(
        _ action: JourneyAction,
        controller: ResponsiveAudioProgramController
    ) {
        guard !isRestoring, !persistenceIsLocked,
              orderedJourneyTransitionTask == nil,
              responsiveAudioController === controller,
              committedState.activeChapter?
                .responsiveAudioSessionIsActive == true,
              case .setResponsiveAudioSnapshot = action else {
            failClosedResponsiveAudioCursorImmediately(
                diagnostic: "automaticBoundaryGuard"
            )
            return
        }

        switch responsiveAudioSceneMutationGate.receiveAutomaticBoundary(
            controllerIdentifier: ObjectIdentifier(controller)
        ) {
        case .deferred:
            return
        case let .admitted(intent):
            if materializeResponsiveAudioAutomaticBoundary(intent) {
                startWriteDrainIfNeeded()
            }
        case .rejected:
            failClosedResponsiveAudioCursorImmediately(
                diagnostic: "automaticBoundaryGateRejected"
            )
        }
    }

    /// Rederives the action from the exact current controller only after any
    /// active scene transaction has committed its historical and conditional
    /// audio records. The callback's captured action is never retained.
    @discardableResult
    private func materializeResponsiveAudioAutomaticBoundary(
        _ intent: ResponsiveAudioSceneMutationGate.AutomaticBoundaryIntent
    ) -> Bool {
        guard !isRestoring, !persistenceIsLocked,
              orderedJourneyTransitionTask == nil,
              let controller = responsiveAudioController,
              ObjectIdentifier(controller) == intent.controllerIdentifier,
              responsiveAudioControllerMatchesCurrentJourney(),
              let durableSnapshot = committedState.activeChapter?
                .responsiveAudioSnapshot,
              committedState.activeChapter?
                .responsiveAudioSessionIsActive == true else {
            _ = finishResponsiveAudioAutomaticBoundary(intent.token)
            failClosedResponsiveAudioCursorImmediately(
                diagnostic: "automaticBoundaryMaterializationGuard"
            )
            return false
        }

        let freshSnapshotCapturedAt = DispatchTime.now().uptimeNanoseconds
        let freshSnapshot: ResponsiveAudioProgramSnapshot
        do {
            freshSnapshot = try controller.checkpointForDurability()
        } catch {
            _ = finishResponsiveAudioAutomaticBoundary(intent.token)
            failClosedResponsiveAudioCursorImmediately(
                diagnostic: "automaticBoundaryCapture;error="
                    + Self.responsiveAudioCursorErrorType(error)
            )
            return false
        }
        guard freshSnapshot.programID == durableSnapshot.programID else {
            _ = finishResponsiveAudioAutomaticBoundary(intent.token)
            failClosedResponsiveAudioCursorImmediately(
                diagnostic: "automaticBoundaryCaptureIdentityMismatch"
            )
            return false
        }

        if Self.responsiveAudioNonPositionMatches(
            durableSnapshot,
            freshSnapshot
        ) {
            _ = finishResponsiveAudioAutomaticBoundary(intent.token)
            return applyPendingResponsiveAudioPhaseAfterAutomaticBoundary(
                controller: controller
            )
        }

        let completionID = UUID()
        pendingDurabilityCallbacks[completionID] = PendingDurabilityCallback(
            succeeded: { [weak self, weak controller] in
                guard let self else { return }
                guard self.finishResponsiveAudioAutomaticBoundary(
                    intent.token
                ), let controller,
                      self.responsiveAudioController === controller else {
                    return
                }
                _ = self.applyPendingResponsiveAudioPhaseAfterAutomaticBoundary(
                    controller: controller
                )
            },
            failed: { [weak self] in
                guard let self else { return }
                _ = self.finishResponsiveAudioAutomaticBoundary(
                    intent.token
                )
                self.failClosedResponsiveAudioCursorImmediately(
                    diagnostic: "automaticBoundaryDurableCommit"
                )
            }
        )
        pendingActions.append(
            PendingAction(
                action: .setResponsiveAudioSnapshot(freshSnapshot),
                prologuePreviewRevision: prologuePreviewRevision,
                completionID: completionID,
                responsiveAudioJournalCapture:
                    ResponsiveAudioJournalCapture(
                        snapshot: freshSnapshot,
                        capturedAtMonotonicNanoseconds:
                            freshSnapshotCapturedAt
                    )
            )
        )
        return true
    }

    @discardableResult
    private func applyPendingResponsiveAudioPhaseAfterAutomaticBoundary(
        controller: ResponsiveAudioProgramController
    ) -> Bool {
        guard suspensionEpisodeCoordinator.episodeID == nil,
              controller.runtime.isPlaying,
              controller.runtime.stage == .interaction,
              let phase = pendingResponsiveAudioPhaseIntent else {
            return false
        }
        guard controller.runtime.interactionPhase != phase else {
            pendingResponsiveAudioPhaseIntent = nil
            return false
        }
        do {
            _ = try controller.selectInteractionPhase(phase)
            pendingResponsiveAudioPhaseIntent = nil
            return false
        } catch {
            failClosedResponsiveAudioCursorImmediately(
                diagnostic: "automaticBoundaryPhase;error="
                    + Self.responsiveAudioCursorErrorType(error)
            )
            return false
        }
    }

    func playResponsiveAudio() {
        let startEpoch = responsiveAudioPlaybackStartEpochForCurrentLifecycle()
        Task { @MainActor [weak self] in
            _ = await self?.startResponsiveAudioPlayback(
                startEpoch: startEpoch
            )
        }
    }

    func responsiveAudioPlaybackStartEpochForCurrentLifecycle()
        -> ResponsiveAudioPlaybackStartEpoch {
        ResponsiveAudioPlaybackStartEpoch(
            physicalPauseGeneration:
                responsiveAudioPhysicalPauseEvent?.generation
        )
    }

    /// Returns only after playback authority, its crash cursor session and the
    /// transport have all started for the same chapter route. Callers must not
    /// expose a playing UI state before this returns `true`.
    @discardableResult
    func startResponsiveAudioPlayback(
        startEpoch: ResponsiveAudioPlaybackStartEpoch
    ) async -> Bool {
        guard runtimeTransitionIsInactive,
              startEpoch
                == responsiveAudioPlaybackStartEpochForCurrentLifecycle(),
              let authorization =
            responsiveAudioExplicitStartAuthorizationForCurrentRoute()
        else { return false }

        while true {
            guard !Task.isCancelled,
                  startEpoch
                    == responsiveAudioPlaybackStartEpochForCurrentLifecycle(),
                  responsiveAudioExplicitStartAuthorizationForCurrentRoute()
                    == authorization else {
                return false
            }

            // A newly authorized resume may arrive while an interruption or
            // route-change episode still owns its completed durability flush.
            // The durable starter below awaits that exact episode and can
            // close it only when the coordinator still knows the scene is
            // active. The exact physical-pause epoch above also proves that
            // this caller's action was issued after the latest suspension. It
            // remains mandatory after an episode resets, so a route task made
            // just before backgrounding cannot wake later and start sound.

            let task: Task<Bool, Never>
            let startID: UUID?
            let startLifecycleToken: UUID?
            if let activeTask = responsiveAudioPlaybackStartTask {
                guard responsiveAudioPlaybackStartAuthorization
                    == authorization else {
                    return false
                }
                if responsiveAudioPlaybackStartLifecycleToken
                    != responsiveAudioLifecycleToken {
                    let staleID = responsiveAudioPlaybackStartID
                    _ = await withTaskCancellationHandler {
                        await activeTask.value
                    } onCancel: {
                        activeTask.cancel()
                    }
                    if responsiveAudioPlaybackStartID == staleID {
                        responsiveAudioPlaybackStartID = nil
                        responsiveAudioPlaybackStartLifecycleToken = nil
                        responsiveAudioPlaybackStartAuthorization = nil
                        responsiveAudioPlaybackStartTask = nil
                    }
                    guard !Task.isCancelled,
                          startEpoch
                            == responsiveAudioPlaybackStartEpochForCurrentLifecycle()
                    else { return false }
                    continue
                }
                task = activeTask
                startID = responsiveAudioPlaybackStartID
                startLifecycleToken =
                    responsiveAudioPlaybackStartLifecycleToken
            } else {
                let newStartID = UUID()
                let newLifecycleToken = responsiveAudioLifecycleToken
                task = Task { @MainActor [weak self] in
                    guard let self else { return false }
                    return await self.startResponsiveAudioPlaybackDurably()
                }
                responsiveAudioPlaybackStartID = newStartID
                responsiveAudioPlaybackStartLifecycleToken =
                    newLifecycleToken
                responsiveAudioPlaybackStartAuthorization = authorization
                responsiveAudioPlaybackStartTask = task
                startID = newStartID
                startLifecycleToken = newLifecycleToken
            }

            let result = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            if responsiveAudioPlaybackStartID == startID {
                responsiveAudioPlaybackStartID = nil
                responsiveAudioPlaybackStartLifecycleToken = nil
                responsiveAudioPlaybackStartAuthorization = nil
                responsiveAudioPlaybackStartTask = nil
            }
            guard ResponsiveAudioPlaybackStartSupersessionPolicy.shouldRetry(
                didStart: result,
                callerIsCancelled: Task.isCancelled,
                operationLifecycleToken: startLifecycleToken,
                currentLifecycleToken: responsiveAudioLifecycleToken,
                suspensionIsActive:
                    suspensionEpisodeCoordinator.episodeID != nil
            ) else {
                return result
            }
            guard await awaitResponsiveAudioStartContinuation(
                authorization: authorization
            ) else {
                return false
            }
        }
    }

    private func awaitResponsiveAudioStartContinuation(
        authorization: ResponsiveAudioExplicitStartAuthorization
    ) async -> Bool {
        while true {
            switch responsiveAudioStartContinuationDecision(
                authorization: authorization
            ) {
            case .stop:
                return false
            case .awaitAuthority:
                if let preparation = authorityTransitionPreparationTask {
                    await preparation.value
                    continue
                }
                if let transition = authorityTransitionTask {
                    await transition.value
                    continue
                }
                return false
            case .retry:
                break
            }

            await awaitResponsiveAudioBindingIfNeeded()

            switch responsiveAudioStartContinuationDecision(
                authorization: authorization
            ) {
            case .stop:
                return false
            case .awaitAuthority:
                continue
            case .retry:
                return responsiveAudioControllerMatchesCurrentJourney()
            }
        }
    }

    private func responsiveAudioStartContinuationDecision(
        authorization: ResponsiveAudioExplicitStartAuthorization
    ) -> ResponsiveAudioPlaybackStartContinuationPolicy.Decision {
        ResponsiveAudioPlaybackStartContinuationPolicy.decide(
            expectedAuthorization: authorization,
            currentAuthorization:
                responsiveAudioExplicitStartAuthorizationForCurrentRoute(),
            callerIsCancelled: Task.isCancelled,
            suspensionIsActive:
                suspensionEpisodeCoordinator.episodeID != nil,
            orderedTransitionIsInFlight:
                orderedJourneyTransitionTask != nil,
            authorityPreparationIsInFlight:
                authorityTransitionPreparationTask != nil,
            authorityRestoreIsInFlight:
                authorityTransitionTask != nil || authorityRestoreIsInFlight,
            acceptedAuthorityMatchesDesired:
                acceptedSaveMigrationAuthorityMatchesDesired,
            runtimeTransitionIsInactive: runtimeTransitionIsInactive
        )
    }

    private var acceptedSaveMigrationAuthorityMatchesDesired: Bool {
        do {
            let accepted = try saveMigrationAuthorityIdentities(
                launchSnapshot: runtimeContentSnapshot,
                futureReleaseSnapshot: futureReleaseContentSnapshot
            )
            let desired = try saveMigrationAuthorityIdentities(
                launchSnapshot: desiredRuntimeContentSnapshot
                    ?? runtimeContentSnapshot,
                futureReleaseSnapshot: desiredFutureReleaseContentSnapshot
            )
            return accepted == desired
        } catch {
            return false
        }
    }

    private func responsiveAudioExplicitStartAuthorizationForCurrentRoute()
        -> ResponsiveAudioExplicitStartAuthorization? {
        guard case let .chapter(chapterID) = committedState.route,
              let session = committedState.activeChapter,
              session.chapterID == chapterID,
              let packageManifestDigest = currentChapterRuntimeAuthority()?
                .verifiedPackage(for: session.packageID)?
                .manifest.manifestDigest,
              let beatID = session.beatID,
              chapterCursor?.beat.id == beatID,
              let program = chapterCursor?.responsiveAudioProgram,
              program.scope.chapterID == chapterID,
              program.scope.beatID == beatID else {
            return nil
        }
        return ResponsiveAudioExplicitStartAuthorization(
            chapterID: chapterID,
            packageID: session.packageID,
            packageManifestDigest: packageManifestDigest,
            beatID: beatID,
            programID: program.id,
            programScope: program.scope
        )
    }

    private func startResponsiveAudioPlaybackDurably() async -> Bool {
        guard !Task.isCancelled else { return false }
        if let playingController = responsiveAudioController,
           playingController.runtime.isPlaying {
            let admission = await responsiveAudioPlaybackStartAdmission(
                controller: playingController
            )
            switch admission {
            case .acceptProtectedCurrentPlayback:
                responsiveAudioFailure = nil
                return true
            case .failClosedUnprotectedPlayback:
                if playingController !== responsiveAudioController {
                    playingController.stopWithoutPersisting()
                }
                failClosedResponsiveAudioCursorImmediately(
                    diagnostic: "startAdmissionUnprotectedPlayback"
                )
                responsiveAudioFailure =
                    "The authored sound paused before its place could be verified."
                return false
            case .startPausedTransport:
                break
            }
        }
        if suspensionEpisodeCoordinator.episodeID != nil {
            guard await suspensionEpisodeCoordinator.awaitCurrentFlush()
                == .durable else {
                return false
            }
            guard !Task.isCancelled else { return false }
            suspensionEpisodeCoordinator.playbackDidResume()
        }
        guard !Task.isCancelled else { return false }
        guard runtimeTransitionIsInactive,
              let controller = responsiveAudioController,
              !controller.runtime.isPlaying,
              let session = committedState.activeChapter,
              let startAuthority = responsiveAudioPlaybackStartAuthority(
                  controller: controller,
                  session: session
              ) else {
#if DEBUG
            recordResponsiveAudioStartAdmissionRejection(
                stage: "paused-preflight"
            )
#endif
            return false
        }
        do {
            let exactPreparedSnapshot = try controller.checkpointForDurability()
            if session.responsiveAudioSessionIsActive {
                if session.responsiveAudioSnapshot != exactPreparedSnapshot {
                    try await enqueueAndAwaitDurability([
                        .setResponsiveAudioSnapshot(exactPreparedSnapshot),
                    ])
                }
            } else {
                try await enqueueAndAwaitDurability([
                    .beginResponsiveAudioSession(
                        chapterOpenNonce: startAuthority.chapterOpenNonce,
                        generation: startAuthority.sessionGeneration,
                        snapshot: exactPreparedSnapshot
                    ),
                ])
            }

            try Task.checkCancellation()
            guard responsiveAudioPlaybackStartAuthorityIsCurrent(
                startAuthority
            ), suspensionEpisodeCoordinator.episodeID == nil else {
#if DEBUG
                recordResponsiveAudioStartAdmissionRejection(
                    stage: "post-durability"
                )
#endif
                throw JourneyChapterRuntimeError.routeAuthorityChanged
            }
            await awaitResponsiveAudioBindingIfNeeded()
            guard let reboundController = responsiveAudioController,
                  !reboundController.runtime.isPlaying,
                  responsiveAudioPlaybackStartAuthorityIsCurrent(
                      startAuthority,
                      controller: reboundController
                  ) else {
#if DEBUG
                recordResponsiveAudioStartAdmissionRejection(
                    stage: "post-binding"
                )
#endif
                throw JourneyChapterRuntimeError.routeAuthorityChanged
            }
            try Task.checkCancellation()
            try await prepareResponsiveAudioCursorProtection(
                controller: reboundController,
                expectedLifecycleToken: startAuthority.lifecycleToken
            )
            do {
                try Task.checkCancellation()
                guard suspensionEpisodeCoordinator.episodeID == nil,
                      responsiveAudioPlaybackStartAuthorityIsCurrent(
                          startAuthority,
                          controller: reboundController
                      ) else {
#if DEBUG
                    recordResponsiveAudioStartAdmissionRejection(
                        stage: "pre-play"
                    )
#endif
                    throw JourneyChapterRuntimeError.routeAuthorityChanged
                }
                try reboundController.play()
                try armResponsiveAudioCursorProtection(
                    controller: reboundController,
                    expectedLifecycleToken: startAuthority.lifecycleToken
                )
            } catch {
                await retireResponsiveAudioCursorProtection()
                throw error
            }
            suspensionEpisodeCoordinator.playbackDidResume()
            causalHapticTransport.resumeAfterSuspension()
            responsiveAudioFailure = nil
            return true
        } catch {
            responsiveAudioController?.stopWithoutPersisting()
            await retireResponsiveAudioCursorProtection()
            responsiveAudioFailure =
                "The authored sound could not be opened offline."
            return false
        }
    }

    private func responsiveAudioPlaybackStartAdmission(
        controller: ResponsiveAudioProgramController
    ) async -> ResponsiveAudioPlaybackStartAdmission {
        let expectedLifecycleToken = responsiveAudioLifecycleToken
        let capturedStore = responsiveAudioCursorStore
        let capturedSidecarSession = responsiveAudioCursorSession
        let capturedDurableSnapshot = responsiveAudioCursorDurableSnapshot
        let storeOwnsSidecar: Bool
        if let capturedStore, let capturedSidecarSession {
            storeOwnsSidecar = await capturedStore.owns(
                capturedSidecarSession
            )
        } else {
            storeOwnsSidecar = false
        }

        let currentSession = committedState.activeChapter
        let startAuthority = currentSession.flatMap {
            responsiveAudioPlaybackStartAuthority(
                controller: controller,
                session: $0
            )
        }
        let controllerIsCurrent = responsiveAudioController === controller
        let authorityIsCurrent = startAuthority.map {
            responsiveAudioPlaybackStartAuthorityIsCurrent(
                $0,
                controller: controller
            )
        } ?? false
        let sidecarSessionIsCurrent = capturedStore != nil
            && responsiveAudioCursorStore === capturedStore
            && capturedSidecarSession != nil
            && responsiveAudioCursorSession == capturedSidecarSession
            && storeOwnsSidecar
        let durableSnapshotIsCurrent: Bool
        if let capturedDurableSnapshot {
            durableSnapshotIsCurrent =
                responsiveAudioCursorDurableSnapshot
                    == capturedDurableSnapshot
                && committedState.activeChapter?.responsiveAudioSnapshot
                    == capturedDurableSnapshot
                && Self.responsiveAudioNonPositionMatches(
                    controller.runtime.snapshot(),
                    capturedDurableSnapshot
                )
        } else {
            durableSnapshotIsCurrent = false
        }
        return ResponsiveAudioPlaybackStartAdmissionPolicy.decide(
            controllerIsPlaying: controller.runtime.isPlaying,
            controllerIsCurrent: controllerIsCurrent,
            sessionProgramAndAuthorityAreCurrent: authorityIsCurrent,
            lifecycleIsCurrent:
                expectedLifecycleToken == responsiveAudioLifecycleToken,
            suspensionIsActive:
                suspensionEpisodeCoordinator.episodeID != nil,
            runtimeTransitionIsInactive: runtimeTransitionIsInactive,
            cursorPumpIsRunning:
                responsiveAudioCursorPump.isPeriodicallyProtectingPlayback,
            cursorPumpDidFailClosed:
                responsiveAudioCursorPump.didFailClosed,
            sidecarSessionIsCurrent: sidecarSessionIsCurrent,
            durableSnapshotIsCurrent: durableSnapshotIsCurrent
        )
    }

    private func responsiveAudioPlaybackStartAuthority(
        controller: ResponsiveAudioProgramController,
        session: ChapterSession
    ) -> ResponsiveAudioPlaybackStartAuthority? {
        guard case let .chapter(chapterID) = committedState.route,
              chapterID == session.chapterID,
              let beatID = session.beatID,
              chapterCursor?.beat.id == beatID,
              controller.runtime.program == chapterCursor?
                .responsiveAudioProgram else {
            return nil
        }
        if session.responsiveAudioSessionIsActive {
            guard let nonce = session.responsiveAudioChapterOpenNonce,
                  session.responsiveAudioSessionGeneration > 0 else {
                return nil
            }
            return ResponsiveAudioPlaybackStartAuthority(
                contentRevision: currentChapterRuntimeAuthority()?.revision,
                chapterID: chapterID,
                packageID: session.packageID,
                beatID: beatID,
                programID: controller.runtime.program.id,
                scope: controller.runtime.program.scope,
                chapterOpenNonce: nonce,
                sessionGeneration: session.responsiveAudioSessionGeneration,
                lifecycleToken: responsiveAudioLifecycleToken
            )
        }
        guard session.responsiveAudioChapterOpenNonce == nil,
              session.responsiveAudioSessionGeneration < UInt64.max else {
            return nil
        }
        return ResponsiveAudioPlaybackStartAuthority(
            contentRevision: currentChapterRuntimeAuthority()?.revision,
            chapterID: chapterID,
            packageID: session.packageID,
            beatID: beatID,
            programID: controller.runtime.program.id,
            scope: controller.runtime.program.scope,
            chapterOpenNonce: UUID(),
            sessionGeneration: session.responsiveAudioSessionGeneration + 1,
            lifecycleToken: responsiveAudioLifecycleToken
        )
    }

    private func responsiveAudioPlaybackStartAuthorityIsCurrent(
        _ authority: ResponsiveAudioPlaybackStartAuthority,
        controller: ResponsiveAudioProgramController? = nil
    ) -> Bool {
        guard runtimeTransitionIsInactive,
              authority.lifecycleToken == responsiveAudioLifecycleToken,
              case let .chapter(chapterID) = committedState.route,
              chapterID == authority.chapterID,
              currentChapterRuntimeAuthority()?.revision
                == authority.contentRevision,
              let session = committedState.activeChapter,
              session.chapterID == authority.chapterID,
              session.packageID == authority.packageID,
              session.beatID == authority.beatID,
              session.responsiveAudioSessionIsActive,
              session.responsiveAudioChapterOpenNonce
                == authority.chapterOpenNonce,
              session.responsiveAudioSessionGeneration
                == authority.sessionGeneration else {
            return false
        }
        guard let controller else { return true }
        return controller === responsiveAudioController
            && controller.runtime.program.id == authority.programID
            && controller.runtime.program.scope == authority.scope
    }

    private func prepareResponsiveAudioCursorProtection(
        controller: ResponsiveAudioProgramController,
        expectedLifecycleToken: UUID? = nil
    ) async throws {
        let lifecycleToken = expectedLifecycleToken
            ?? responsiveAudioLifecycleToken
        guard let store = responsiveAudioCursorStore,
              let durableSnapshot = committedState.activeChapter?
                .responsiveAudioSnapshot,
              let authority = try responsiveAudioCursorAuthority(
                for: controller
              ) else {
#if DEBUG
            recordResponsiveAudioStartAdmissionRejection(
                stage: "cursor-protection-preflight"
            )
#endif
            throw JourneyChapterRuntimeError.persistenceUnavailable
        }
        let sidecarSession = try await store.beginSession(
            authority: authority
        )
        guard runtimeTransitionIsInactive,
              lifecycleToken == responsiveAudioLifecycleToken,
              responsiveAudioController === controller,
              committedState.activeChapter?
                .responsiveAudioSessionIsActive == true else {
#if DEBUG
            recordResponsiveAudioStartAdmissionRejection(
                stage: "cursor-protection"
            )
#endif
            await store.retire(sidecarSession)
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        responsiveAudioCursorSession = sidecarSession
        responsiveAudioCursorDurableSnapshot = durableSnapshot
    }

    /// `NativeTimelineTransport.play` completes session/graph preparation,
    /// schedules render with a host-time lead and only then returns. Arming in
    /// this same MainActor turn therefore excludes arbitrarily slow pre-render
    /// preparation from the 250 ms cursor age while covering the first sample.
    private func armResponsiveAudioCursorProtection(
        controller: ResponsiveAudioProgramController,
        expectedLifecycleToken: UUID? = nil
    ) throws {
        let lifecycleToken = expectedLifecycleToken
            ?? responsiveAudioLifecycleToken
        guard runtimeTransitionIsInactive,
              lifecycleToken == responsiveAudioLifecycleToken,
              responsiveAudioController === controller,
              controller.runtime.isPlaying,
              committedState.activeChapter?
                .responsiveAudioSessionIsActive == true,
              let store = responsiveAudioCursorStore,
              let sidecarSession = responsiveAudioCursorSession,
              let durableSnapshot = responsiveAudioCursorDurableSnapshot else {
#if DEBUG
            recordResponsiveAudioStartAdmissionRejection(stage: "arming")
#endif
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        startResponsiveAudioCursorPump(
            controller: controller,
            durableSnapshot: durableSnapshot,
            sidecarSession: sidecarSession,
            store: store
        )
        // The journaled session baseline already owns the first 250 ms. Do
        // not await this generation's first sidecar fsync: an approach may
        // cross its automatic boundary and validly replace the generation
        // before that write returns. The armed watchdog remains the physical
        // fail-closed authority throughout that interval.
        guard !Task.isCancelled,
              !responsiveAudioCursorPump.didFailClosed,
              responsiveAudioCursorPump.isRunning,
              lifecycleToken == responsiveAudioLifecycleToken,
              responsiveAudioController === controller,
              controller.runtime.isPlaying,
              suspensionEpisodeCoordinator.episodeID == nil,
              responsiveAudioCursorSession == sidecarSession,
              responsiveAudioCursorDurableSnapshot == durableSnapshot else {
            throw JourneyChapterRuntimeError.persistenceUnavailable
        }
    }

    private func startResponsiveAudioCursorPump(
        controller: ResponsiveAudioProgramController,
        durableSnapshot: ResponsiveAudioProgramSnapshot,
        sidecarSession: ResponsiveAudioCursorCheckpointSession,
        store: ResponsiveAudioCursorCheckpointStore,
        lastVerifiedCaptureNanoseconds: UInt64? = nil
    ) {
#if DEBUG
        responsiveAudioCursorFailureDiagnosticForTesting = "none"
#endif
        responsiveAudioCursorPump.start(
            lastVerifiedCaptureNanoseconds:
                lastVerifiedCaptureNanoseconds,
            capture: { [weak self, weak controller] in
                guard let self, let controller,
                      self.responsiveAudioController === controller,
                      self.responsiveAudioCursorDurableSnapshot
                        == durableSnapshot else {
                    throw JourneyChapterRuntimeError.routeAuthorityChanged
                }
                let result = try controller.checkpointForDurability(
                    constrainedTo: durableSnapshot
                )
                return switch result {
                case let .verified(snapshot):
                    .verified(snapshot)
                case let .awaitingDurableAuthority(projectedOldSnapshot):
                    .awaitingDurableAuthority(
                        projectedOldSnapshot: projectedOldSnapshot
                    )
                }
            },
            persist: { [weak self] snapshot, capturedAt in
                guard let self,
                      self.responsiveAudioCursorSession == sidecarSession else {
                    throw JourneyChapterRuntimeError.routeAuthorityChanged
                }
                try await store.checkpoint(
                    snapshot,
                    session: sidecarSession,
                    capturedAtMonotonicNanoseconds: capturedAt
                )
#if DEBUG
                if self.responsiveAudioCursorSession == sidecarSession,
                   self.responsiveAudioCursorDurableSnapshot
                    == durableSnapshot {
                    self.responsiveAudioDurableCursorForTesting = snapshot
                }
#endif
            },
            failClosed: { [weak self] in
                self?.failClosedResponsiveAudioCursorFromPump()
            }
        )
    }

    private func failClosedResponsiveAudioCursorFromPump() {
#if DEBUG
        let pumpDiagnostic = responsiveAudioCursorPump
            .failureDiagnosticForTesting
            .map(String.init(describing:))
            ?? "missing"
        failClosedResponsiveAudioCursorImmediately(
            diagnostic: "pump;\(pumpDiagnostic)"
        )
#else
        failClosedResponsiveAudioCursorImmediately(diagnostic: "pump")
#endif
    }

    private func failClosedResponsiveAudioCursorImmediately(
        diagnostic: String = "unclassified"
    ) {
#if DEBUG
        if responsiveAudioCursorFailureDiagnosticForTesting == "none" {
            responsiveAudioCursorFailureDiagnosticForTesting = diagnostic
                + ";modelObserved="
                + String(DispatchTime.now().uptimeNanoseconds)
        }
#endif
        guard preQuiescedSuspensionAction == nil else { return }
        if let controller = responsiveAudioController {
            do {
                preQuiescedSuspensionAction = try controller
                    .quiesceForSuspension(.sceneInactive)
            } catch {
                controller.stopWithoutPersisting()
                responsiveAudioController = nil
                cancelPendingResponsiveAudioBinding()
                preQuiescedSuspensionFailed = true
                responsiveAudioFailure =
                    "The authored sound paused before its place could be verified."
            }
        }
        requestSuspension(.cursorDurabilityFailure)
    }

    private static func responsiveAudioCursorErrorType(_ error: Error) -> String {
        String(reflecting: type(of: error))
    }

    private func responsiveAudioCursorAuthority(
        for controller: ResponsiveAudioProgramController
    ) throws -> ResponsiveAudioCursorAuthority? {
        let contentRevision = currentChapterRuntimeAuthority()?.revision
            ?? responsiveAudioBindingIdentity?.contentRevision
            ?? 0
        let snapshot = committedState.activeChapter?.responsiveAudioSnapshot
        guard let timelineID = snapshot?.timelineID,
              let timeline = try controller.runtime.makeTimelineTransportPlan()?.timeline,
              timeline.id == timelineID else {
            return nil
        }
        return try ResponsiveAudioCursorAuthority.make(
            durableState: committedState,
            contentRevision: contentRevision,
            program: controller.runtime.program,
            timeline: timeline
        )
    }

    private func retireResponsiveAudioCursorProtection() async {
        responsiveAudioCursorPump.stop()
        let retiringSession = responsiveAudioCursorSession
        responsiveAudioCursorSession = nil
        responsiveAudioCursorDurableSnapshot = nil
#if DEBUG
        if orderedExitPreinstallSuccessorProbeIsEnabled,
           orderedJourneyTransitionTask != nil,
           orderedExitAudioFailureInjectionDidRun,
           !orderedExitPreinstallSuccessorWasArmedForTesting,
           let successorIdentity = responsiveAudioBindingIdentityForCurrentRoute() {
            // Model the exact interval after a replacement generation has
            // revoked the old lifecycle but before its async controller bind
            // completes. The captured old pointer is intentionally still
            // present so scoped cleanup must stop it without cancelling the
            // successor's pending task or identity.
            orderedExitPreinstallSuccessorWasArmedForTesting = true
            responsiveAudioLifecycleToken = UUID()
            responsiveAudioBindingIdentity = successorIdentity
            responsiveAudioBindingTask?.cancel()
            responsiveAudioBindingTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: UInt64.max)
                } catch {
                    return
                }
            }
            updateOrderedExitAudioDiagnosticForTesting()
        }
        if orderedExitControllerSwapProbeIsEnabled,
           orderedJourneyTransitionTask != nil,
           orderedExitAudioFailureInjectionDidRun,
           !orderedExitForcedControllerSwapDidRun {
            orderedExitForcedControllerSwapDidRun = true
            let retiringController = responsiveAudioController
            // Suspend inside the caller's retirement await, then install a
            // real replacement object. The post-await fence must reject the
            // old transaction without clearing this successor or its binding.
            await Task.yield()
            forceResponsiveAudioControllerSwapForAuthorityProbeForTesting()
            if let successor = responsiveAudioController,
               successor !== retiringController {
                orderedExitAudioSuccessorControllerIDForTesting =
                    ObjectIdentifier(successor)
            }
            updateOrderedExitAudioDiagnosticForTesting()
        }
        if contentAuthorityStaleControllerSwapProbeIsEnabled,
           authorityTransitionPreparationTask != nil,
           !contentAuthorityForcedControllerSwapDidRun {
            contentAuthorityForcedControllerSwapDidRun = true
            recordContentAuthorityBarrierMilestoneForTesting(
                "retire:suspended"
            )
            // The caller is suspended inside its retirement await before the
            // captured action can reach the journal. Replace the actual
            // controller object in that window so the post-await identity
            // fence, rather than a synthetic flag, rejects the old action.
            await Task.yield()
            forceResponsiveAudioControllerSwapForAuthorityProbeForTesting()
            recordContentAuthorityBarrierMilestoneForTesting(
                "retire:resumed"
            )
        }
#endif
        if let retiringSession,
           let responsiveAudioCursorStore {
            await responsiveAudioCursorStore.retire(
                retiringSession
            )
        }
    }

#if DEBUG
    private func forceResponsiveAudioControllerSwapForAuthorityProbeForTesting() {
        guard let oldController = responsiveAudioController,
              let context = responsiveAudioAuthoritySwapContextForTesting
        else { return }
        do {
            let currentPlan = try chapterCoordinator?
                .responsiveAudioRestorationPlan(state: committedState)
                ?? context.plan
            let currentRestoration = JourneyRestoration(
                state: committedState,
                replayedEventCount: 0,
                lastSequence: lastCommittedSequence
            )
            try bindResponsiveAudio(
                plan: currentPlan,
                restoration: currentRestoration,
                resolver: context.resolver
            )
        } catch {
            oldController.stopWithoutPersisting()
            if responsiveAudioController === oldController {
                responsiveAudioController = nil
            }
        }
        let didSwap = responsiveAudioController.map {
            $0 !== oldController
        } ?? false
        contentAuthorityAudioControllerSwappedForTesting = didSwap
        updateContentAuthorityAudioDiagnosticForTesting()
        if didSwap {
            recordContentAuthorityBarrierMilestoneForTesting(
                "controller:swapped"
            )
        }
    }
#endif

    private func rotateResponsiveAudioCursorAuthorityIfNeeded(
        journalCapture: ResponsiveAudioJournalCapture? = nil
    ) async throws {
        guard let durableSnapshot = responsiveAudioCursorDurableSnapshot,
              let nextSnapshot = committedState.activeChapter?
                .responsiveAudioSnapshot,
              committedState.activeChapter?
                .responsiveAudioSessionIsActive == true,
              !Self.responsiveAudioNonPositionMatches(
                  durableSnapshot,
                  nextSnapshot
              ) else {
            return
        }
        guard let controller = responsiveAudioController,
              Self.responsiveAudioNonPositionMatches(
                  controller.runtime.snapshot(),
                  nextSnapshot
              ), let store = responsiveAudioCursorStore,
              let priorSession = responsiveAudioCursorSession,
              let nextAuthority = try responsiveAudioCursorAuthority(
                for: controller
              ) else {
            throw JourneyChapterRuntimeError.authoredAudioUnavailable
        }
        let lifecycleToken = responsiveAudioLifecycleToken
        let lastRecoverableCapture: UInt64
        if let journalCapture {
            guard journalCapture.snapshot == nextSnapshot else {
                throw JourneyChapterRuntimeError.authoredAudioUnavailable
            }
            lastRecoverableCapture =
                journalCapture.capturedAtMonotonicNanoseconds
        } else {
            guard let conservativeBaseline = responsiveAudioCursorPump
                .lastVerifiedCaptureNanoseconds else {
                throw JourneyChapterRuntimeError.persistenceUnavailable
            }
            lastRecoverableCapture = conservativeBaseline
        }
        let capturedAt = DispatchTime.now().uptimeNanoseconds
        let capture = try controller.checkpointForDurability(
            constrainedTo: nextSnapshot
        )
        guard case let .verified(initialSnapshot) = capture else {
            failClosedResponsiveAudioCursorImmediately(
                diagnostic: "handoffCaptureAwaitingDurableAuthority"
            )
            throw JourneyChapterRuntimeError.authoredAudioUnavailable
        }
        // Arm the successor capture's absolute deadline before suspending the
        // prior periodic writer or awaiting the actor handoff. The deadline
        // keeps physical playback fail-closed while the admitted store write
        // continues independently.
        guard let handoffDeadline = responsiveAudioCursorPump
            .beginHandoffDeadline(
                candidateCapturedAtNanoseconds: capturedAt,
                lastRecoverableCaptureNanoseconds:
                    lastRecoverableCapture,
                failClosed: { [weak self] in
                    self?.failClosedResponsiveAudioCursorFromPump()
                }
            ) else {
            throw JourneyChapterRuntimeError.persistenceUnavailable
        }
        let successorSession: ResponsiveAudioCursorCheckpointSession
        do {
            successorSession = try await store.handoffSession(
                from: priorSession,
                to: nextAuthority,
                initialSnapshot: initialSnapshot,
                capturedAtMonotonicNanoseconds: capturedAt
            )
        } catch {
            let observedAt = DispatchTime.now().uptimeNanoseconds
            let elapsed = observedAt >= capturedAt
                ? observedAt - capturedAt
                : UInt64.max
            failClosedResponsiveAudioCursorImmediately(
                diagnostic: "handoffStore;requested=\(capturedAt)"
                    + ";observed=\(observedAt);elapsed=\(elapsed);error="
                    + Self.responsiveAudioCursorErrorType(error)
            )
            throw error
        }
        let handoffDeadlineIsOwned = responsiveAudioCursorPump
            .ownsHandoffDeadline(
                handoffDeadline,
                candidateCapturedAtNanoseconds: capturedAt,
                lastRecoverableCaptureNanoseconds:
                    lastRecoverableCapture
            )
        let lifecycleIsCurrent =
            lifecycleToken == responsiveAudioLifecycleToken
        let controllerIsCurrent = responsiveAudioController === controller
        let controllerIsPlaying = controller.runtime.isPlaying
        let priorSessionIsCurrent =
            responsiveAudioCursorSession == priorSession
        let durableSnapshotIsCurrent =
            responsiveAudioCursorDurableSnapshot == durableSnapshot
        let journalSessionIsActive = committedState.activeChapter?
            .responsiveAudioSessionIsActive == true
        guard handoffDeadlineIsOwned,
              lifecycleIsCurrent,
              controllerIsCurrent,
              controllerIsPlaying,
              priorSessionIsCurrent,
              durableSnapshotIsCurrent,
              journalSessionIsActive else {
            responsiveAudioCursorPump.stop()
            await store.retire(successorSession)
#if DEBUG
            let observedAt = DispatchTime.now().uptimeNanoseconds
            let elapsed = observedAt >= lastRecoverableCapture
                ? observedAt - lastRecoverableCapture
                : UInt64.max
            let diagnostic = "handoffOwnershipLost"
                + ";deadline=\(handoffDeadlineIsOwned)"
                + ";lifecycle=\(lifecycleIsCurrent)"
                + ";controller=\(controllerIsCurrent)"
                + ";playing=\(controllerIsPlaying)"
                + ";priorSession=\(priorSessionIsCurrent)"
                + ";durableSnapshot=\(durableSnapshotIsCurrent)"
                + ";journalSession=\(journalSessionIsActive)"
                + ";baselineElapsed=\(elapsed)"
            failClosedResponsiveAudioCursorImmediately(
                diagnostic: diagnostic
            )
#else
            failClosedResponsiveAudioCursorImmediately(
                diagnostic: "handoffOwnershipLost"
            )
#endif
            throw JourneyChapterRuntimeError.routeAuthorityChanged
        }
        responsiveAudioCursorSession = successorSession
        responsiveAudioCursorDurableSnapshot = nextSnapshot
#if DEBUG
        responsiveAudioDurableCursorForTesting = initialSnapshot
#endif
        startResponsiveAudioCursorPump(
            controller: controller,
            durableSnapshot: nextSnapshot,
            sidecarSession: successorSession,
            store: store,
            lastVerifiedCaptureNanoseconds: capturedAt
        )
        if responsiveAudioCursorPump.didFailClosed
            || !responsiveAudioCursorPump.isRunning {
            throw JourneyChapterRuntimeError.persistenceUnavailable
        }
    }

    private static func responsiveAudioNonPositionMatches(
        _ lhs: ResponsiveAudioProgramSnapshot,
        _ rhs: ResponsiveAudioProgramSnapshot
    ) -> Bool {
        lhs.formatVersion == rhs.formatVersion
            && lhs.programID == rhs.programID
            && lhs.stage == rhs.stage
            && lhs.interactionPhase == rhs.interactionPhase
            && lhs.timelineID == rhs.timelineID
            && lhs.causalStage == rhs.causalStage
            && lhs.durableCompletionSequence
                == rhs.durableCompletionSequence
    }

    func retryPersistence() {
        guard !isRestoring else { return }
        Task { @MainActor [weak self] in
            await self?.restore()
        }
    }

    func bootstrap() async {
        await restoreExperiencePreferences()
        await prepareCommerceForRestoration()
        await beginObservingRuntimeContent()
        await bootstrapDownloads()
        await bootstrapFutureReleases()
        await restore()
        await configureCommerceAfterRestoration()
    }

    private func beginObservingRuntimeContent() async {
        guard let contentClient else { return }
        contentObservationTask?.cancel()
        let updates = await contentClient.snapshotUpdates()
        contentObservationTask = Task { @MainActor [weak self] in
            for await snapshot in updates {
                guard !Task.isCancelled else { return }
                self?.applyRuntimeContentSnapshot(snapshot)
            }
        }
        applyRuntimeContentSnapshot(await contentClient.snapshot())
    }

    private func bootstrapDownloads() async {
        guard let downloadClient else { return }
        downloadObservationTask?.cancel()
        let updates = await downloadClient.snapshotUpdates()
        downloadObservationTask = Task { @MainActor [weak self] in
            for await snapshot in updates {
                guard !Task.isCancelled else { return }
                self?.applyDownloadSnapshot(snapshot)
            }
        }
        do {
            applyDownloadSnapshot(try await downloadClient.bootstrap())
        } catch InstalledPackageIndexError.requiresNewerApp(_) {
            downloadFailure = .requiresNewerApp
        } catch {
            downloadFailure = .statusUnavailable
        }
    }

    private func bootstrapFutureReleases() async {
        guard let futureReleaseClient else { return }
        futureReleaseObservationTask?.cancel()
        let updates = await futureReleaseClient.installationStateUpdates()
        futureReleaseObservationTask = Task { @MainActor [weak self] in
            for await state in updates {
                guard !Task.isCancelled, let self else { return }
                do {
                    try applyFutureReleaseDownloadSnapshot(
                        try await futureReleaseClient.downloadSnapshot()
                    )
                    if case .completed = state {
                        applyFutureReleaseContentSnapshot(
                            try await futureReleaseClient.refreshContent()
                        )
                    }
                    futureReleaseFailure = nil
                } catch {
                    futureReleaseFailure = FutureReleasePresentationFailure(
                        scope: .allReleases,
                        message:
                            "Later historical routes could not be verified on this iPhone."
                    )
                }
            }
        }
        do {
            let snapshot = try await futureReleaseClient.bootstrap()
            try applyFutureReleaseDownloadSnapshot(
                snapshot.download,
                bootstrapEntries: snapshot.retainedCatalogEntries
            )
            applyFutureReleaseContentSnapshot(snapshot.content)
            futureReleaseFailure = nil
        } catch {
            futureReleaseDownloadSnapshot = nil
            retainedFutureReleaseCatalogEntries = []
            futureReleaseFailure = FutureReleasePresentationFailure(
                scope: .allReleases,
                message:
                    "Later historical routes could not be verified on this iPhone."
            )
        }
    }

    private func applyDownloadSnapshot(_ snapshot: DownloadControllerSnapshot) {
        do {
            let projection = try DownloadPresentationProjection(snapshot: snapshot)
            downloadPresentation = projection
            if projection.bootstrapState == .ready,
               downloadFailure == .statusUnavailable {
                downloadFailure = nil
            }
            pausePaidQueueAfterCurrentPackageIfNeeded()
            openPendingChapterIfAvailable()
        } catch {
            downloadPresentation = nil
            downloadFailure = .statusUnavailable
        }
    }

    private func applyRuntimeContentSnapshot(
        _ snapshot: VerifiedJourneyContentSnapshot
    ) {
        guard VerifiedSnapshotRevisionPolicy.admits(
            candidate: snapshot.revision,
            after: desiredRuntimeContentSnapshot?.revision
        ) else {
            return
        }
        desiredRuntimeContentSnapshot = snapshot
        receiveDesiredContentAuthorityChange()
    }

    private func publishRuntimeContentSnapshot(
        _ snapshot: VerifiedJourneyContentSnapshot
    ) {
        guard VerifiedSnapshotRevisionPolicy.admits(
            candidate: snapshot.revision,
            after: runtimeContentSnapshot?.revision
        ) else {
            return
        }
        cancelPendingResponsiveAudioBinding()
        runtimeContentSnapshot = snapshot
        if activeFutureReleaseID == nil {
            chapterCoordinator = ChapterCoordinator(repository: snapshot.repository)
        }
        rebasePhysicalPauseGateAfterContentAuthorityPublication()
#if DEBUG
        if orderedExitAudioProbeIsEnabled,
           orderedExitAudioAuthorityRequestedForTesting,
           snapshot.revision == desiredRuntimeContentSnapshot?.revision {
            orderedExitAudioAuthorityPublishedForTesting = true
            orderedExitAudioCommittedSnapshotForTesting =
                orderedExitCommittedSnapshotForTesting()
            orderedExitAudioSequenceAfterForTesting = lastCommittedSequence
            orderedExitAudioAuditIsFinalForTesting = true
            updateOrderedExitAudioDiagnosticForTesting()
        }
        if contentAuthorityBarrierProbeIsEnabled, snapshot.revision == 2 {
            let gateRevision = chapterRuntimePhysicalPauseGate.map {
                "r\($0.contentRevision)"
            } ?? "none"
            recordContentAuthorityBarrierMilestoneForTesting(
                "published:r2,gate:\(gateRevision)"
            )
            if contentAuthorityAudioAuditProbeIsEnabled {
                finalizeContentAuthorityAudioAuditForTesting()
            }
        }
#endif

        if case let .chapter(chapterID) = committedState.route,
           snapshot.repository.chapter(chapterID) == nil,
           let chapter = FoundationCatalog.chapters.first(where: { $0.id == chapterID }),
           chapter.packageID != LaunchContent.essentialPackageID,
           !persistenceIsLocked,
           orderedJourneyTransitionTask == nil {
            offlineChapterRequest = OfflineChapterRequest(
                chapterID: chapterID,
                packageID: chapter.packageID
            )
            chapterTransitionIsPending = true
            enqueueOrderedJourneyTransition([.showWorld])
            return
        }

        if !persistenceIsLocked {
            refreshChapterPresentation(bindResponsiveAudio: true)
            openPendingChapterIfAvailable()
        }
    }

    private func applyFutureReleaseDownloadSnapshot(
        _ snapshot: FutureReleaseDownloadSnapshot,
        bootstrapEntries: [ReleaseCatalogEntry]? = nil
    ) throws {
        let canonical = try snapshot.retainedCatalogEntries
            .validatedCanonicalReleaseCatalog()
        guard canonical == snapshot.retainedCatalogEntries else {
            throw FutureReleaseCatalogAuthorityError
                .noncanonicalRetainedCatalog
        }
        guard canonical.map(\.id) == snapshot.retainedReleaseIDs,
              bootstrapEntries == nil || bootstrapEntries == canonical else {
            throw FutureReleaseCatalogAuthorityError
                .retainedIdentityMismatch
        }
        futureReleaseDownloadSnapshot = snapshot
        retainedFutureReleaseCatalogEntries = canonical
    }

    private static func queuedFutureReleasePackageID(
        in state: PackageBatchInstallationState
    ) -> PackageID? {
        switch state {
        case let .starting(packageID, _, _),
             let .installing(packageID, _, _),
             let .pausingAfterCurrent(packageID, _, _),
             let .awaitingExplicitRestore(packageID, _, _),
             let .failed(packageID, _, _):
            packageID
        case let .paused(nextPackageID, _, _):
            nextPackageID
        case .idle, .staleJournal, .completed:
            nil
        }
    }

    private func applyFutureReleaseContentSnapshot(
        _ snapshot: VerifiedFutureReleaseContentSnapshot
    ) {
        guard VerifiedSnapshotRevisionPolicy.admits(
            candidate: snapshot.revision,
            after: desiredFutureReleaseContentSnapshot.revision
        ) else {
            return
        }
        desiredFutureReleaseContentSnapshot = snapshot
        receiveDesiredContentAuthorityChange()
    }

    private func publishFutureReleaseContentSnapshot(
        _ snapshot: VerifiedFutureReleaseContentSnapshot
    ) {
        guard VerifiedSnapshotRevisionPolicy.admits(
            candidate: snapshot.revision,
            after: futureReleaseContentSnapshot.revision
        ) else {
            return
        }
        futureReleaseContentSnapshot = snapshot
        guard let activeFutureReleaseID else { return }

        if let authority = snapshot.chapterRuntimeAuthority(
            for: activeFutureReleaseID
        ) {
            chapterCoordinator = ChapterCoordinator(
                repository: authority.repository
            )
            rebasePhysicalPauseGateAfterContentAuthorityPublication()
            if !persistenceIsLocked {
                refreshChapterPresentation(bindResponsiveAudio: true)
            }
            return
        }

        guard case .chapter = committedState.route,
              !persistenceIsLocked,
              orderedJourneyTransitionTask == nil else { return }
        contentFailure =
            "This historical route is no longer available offline on this iPhone."
        chapterTransitionIsPending = true
        enqueueOrderedJourneyTransition(
            [.showWorld],
            routeAuthorityCommit: { [weak self] in
                guard let self else { return }
                self.cancelPendingResponsiveAudioBinding()
                self.activeFutureReleaseID = nil
                if let runtimeContentSnapshot = self.runtimeContentSnapshot {
                    self.chapterCoordinator = ChapterCoordinator(
                        repository: runtimeContentSnapshot.repository
                    )
                }
            },
            authorityBoundary: .worldExit
        )
    }

    private func receiveDesiredContentAuthorityChange() {
        // Before the first disk restore no Journey state or package-backed
        // scene is visible. Bootstrap may therefore assemble the exact pair
        // of verified snapshots which that first restore will consume.
        if store == nil,
           committer == nil,
           isRestoring,
           !authorityRestoreIsInFlight {
            if let desiredRuntimeContentSnapshot {
                publishRuntimeContentSnapshot(desiredRuntimeContentSnapshot)
            }
            publishFutureReleaseContentSnapshot(
                desiredFutureReleaseContentSnapshot
            )
            return
        }
        // An admitted restoration already consumes the latest desired
        // snapshots and calls this method again from its teardown boundary.
        // Starting a second preparation task here would close the UI before
        // either authority is ready to publish.
        guard !isRestoring, !authorityRestoreIsInFlight else { return }

        // A restore can finish after bootstrap has already published the same
        // verified revisions. Neither publisher would admit those snapshots,
        // so do not close chapter admission for an empty authority handoff.
        guard desiredContentAuthorityPublicationIsPending else { return }

        // Save-compatible snapshots can still replace the exact content
        // revision carried by every scene identity. Runtime publication must
        // therefore close admission and drain already accepted work just like
        // a migration; only persistence replacement may be skipped later.
        beginAuthorityTransitionPreparation()
    }

    private var desiredContentAuthorityPublicationIsPending: Bool {
        if let desiredRuntimeContentSnapshot,
           VerifiedSnapshotRevisionPolicy.admits(
               candidate: desiredRuntimeContentSnapshot.revision,
               after: runtimeContentSnapshot?.revision
           ) {
            return true
        }
        return VerifiedSnapshotRevisionPolicy.admits(
            candidate: desiredFutureReleaseContentSnapshot.revision,
            after: futureReleaseContentSnapshot.revision
        )
    }

    private func deferContentAuthorityRetryUntilCausalResolution() {
        deferredContentAuthorityRetryIsPending =
            desiredContentAuthorityPublicationIsPending
    }

    private func resumeDeferredContentAuthorityRetryIfPossible() {
        guard deferredContentAuthorityRetryIsPending else { return }
        guard desiredContentAuthorityPublicationIsPending else {
            deferredContentAuthorityRetryIsPending = false
            return
        }
        guard !isRestoring,
              !persistenceIsLocked,
              !authorityRestoreIsInFlight,
              authorityTransitionPreparationTask == nil,
              authorityTransitionTask == nil,
              orderedJourneyTransitionTask == nil,
              !chapterTransitionIsPending,
              !persistenceMutationBarrier.hasActiveMutations,
              suspensionEpisodeCoordinator.episodeID == nil else {
            return
        }
        deferredContentAuthorityRetryIsPending = false
        receiveDesiredContentAuthorityChange()
    }

    private func beginAuthorityTransitionPreparation() {
        guard authorityTransitionPreparationTask == nil,
              authorityTransitionTask == nil,
              !authorityRestoreIsInFlight,
              !persistenceIsLocked else {
            return
        }
        deferredContentAuthorityRetryIsPending = false
        chapterTransitionIsPending = true
        responsiveAudioLifecycleToken = UUID()
        responsiveAudioPlaybackStartTask?.cancel()
        authorityTransitionPreparationTask = Task { @MainActor [weak self] in
            await self?.prepareForAuthorityTransition()
        }
    }

    private func prepareForAuthorityTransition() async {
        if let orderedJourneyTransitionTask {
            await orderedJourneyTransitionTask.value
        }
        // Preparation has already closed admission through
        // `authorityTransitionPreparationTask` and
        // `chapterTransitionIsPending`. Every earlier reservation still owns
        // its full controller, journal and compositor transaction.
        await awaitChapterRuntimeInputReservationQuiescence()
        await awaitResponsiveAudioSceneMutationQuiescence()
        guard !isRestoring, !persistenceIsLocked else {
            authorityTransitionPreparationTask = nil
            chapterTransitionIsPending = false
            deferContentAuthorityRetryUntilCausalResolution()
            return
        }

        if suspensionEpisodeCoordinator.episodeID != nil {
            guard await suspensionEpisodeCoordinator.awaitCurrentFlush()
                == .durable else {
                authorityTransitionPreparationTask = nil
                chapterTransitionIsPending = false
                deferContentAuthorityRetryUntilCausalResolution()
                return
            }
        }

        stopOutgoingResponsiveAudioTailImmediately()
        causalHapticTransport.quiesceForSuspension()
        cancelPendingResponsiveAudioBinding()

        if let controller = responsiveAudioController {
            var action = captureAuthorityTransitionAudioSnapshot(
                from: controller
            )
            await retireResponsiveAudioCursorProtection()

            // Cursor-sidecar retirement is asynchronous. Although chapter
            // admission remains closed for this preparation, revalidate the
            // exact controller and route before its snapshot can enter the
            // journal. A cancelled/replaced route may continue the authority
            // handoff, but it cannot append the old route's audio state.
            if responsiveAudioController !== controller
                || !responsiveAudioControllerMatchesCurrentJourney() {
                controller.stopWithoutPersisting()
                if responsiveAudioController === controller {
                    responsiveAudioController = nil
                }
                cancelPendingResponsiveAudioBinding()
                action = nil
#if DEBUG
                if contentAuthorityAudioAuditProbeIsEnabled {
                    contentAuthorityAudioSnapshotWasStaleForTesting = true
                    contentAuthorityAudioCommittedSnapshotForTesting =
                        committedState.activeChapter?
                            .responsiveAudioSnapshot
                    contentAuthorityAudioSequenceAfterForTesting =
                        lastCommittedSequence
                    updateContentAuthorityAudioDiagnosticForTesting()
                    recordContentAuthorityBarrierMilestoneForTesting(
                        "quiesce:stale"
                    )
                    recordContentAuthorityBarrierMilestoneForTesting(
                        "quiesce:journal-skipped"
                    )
                }
#endif
            }

            if let action {
                do {
                    try await enqueueAndAwaitDurability([action])
#if DEBUG
                    responsiveAudioDurableCursorForTesting = committedState
                        .activeChapter?.responsiveAudioSnapshot
                    if contentAuthorityAudioAuditProbeIsEnabled {
                        contentAuthorityAudioCommittedSnapshotForTesting =
                            committedState.activeChapter?
                                .responsiveAudioSnapshot
                        contentAuthorityAudioSequenceAfterForTesting =
                            lastCommittedSequence
                        updateContentAuthorityAudioDiagnosticForTesting()
                    }
#endif
                } catch {
                    authorityTransitionPreparationTask = nil
                    chapterTransitionIsPending = false
                    deferContentAuthorityRetryUntilCausalResolution()
                    return
                }
            }
        } else {
            await retireResponsiveAudioCursorProtection()
        }

        guard !isRestoring, !persistenceIsLocked else {
            authorityTransitionPreparationTask = nil
            chapterTransitionIsPending = false
            deferContentAuthorityRetryUntilCausalResolution()
            return
        }

        if suspensionEpisodeCoordinator.episodeID != nil {
            guard await suspensionEpisodeCoordinator.awaitCurrentFlush()
                == .durable else {
                authorityTransitionPreparationTask = nil
                chapterTransitionIsPending = false
                deferContentAuthorityRetryUntilCausalResolution()
                return
            }
        }

        authorityTransitionPreparationTask = nil
        do {
            let accepted = try saveMigrationAuthorityIdentities(
                launchSnapshot: runtimeContentSnapshot,
                futureReleaseSnapshot: futureReleaseContentSnapshot
            )
            let desired = try saveMigrationAuthorityIdentities(
                launchSnapshot: desiredRuntimeContentSnapshot
                    ?? runtimeContentSnapshot,
                futureReleaseSnapshot: desiredFutureReleaseContentSnapshot
            )
            if accepted == desired {
                if let desiredRuntimeContentSnapshot {
                    publishRuntimeContentSnapshot(
                        desiredRuntimeContentSnapshot
                    )
                }
                publishFutureReleaseContentSnapshot(
                    desiredFutureReleaseContentSnapshot
                )
                if orderedJourneyTransitionTask == nil {
                    chapterTransitionIsPending = false
                    refreshChapterPresentation(bindResponsiveAudio: true)
                    openPendingChapterIfAvailable()
                }
                return
            }
        } catch {
            lockPersistenceForAuthorityTransition()
            failClosedAuthorityTransition()
            return
        }

        lockPersistenceForAuthorityTransition()
        startAuthorityTransitionIfPossible()
    }

    /// A native transport can fail while synchronizing its final rendered
    /// cursor. That failure happens before any journal write, so retaining a
    /// deferred authority retry would have no later causal event guaranteed
    /// to wake it. Stop the graph synchronously, then capture the controller's
    /// already-paused deterministic position. The fallback can rewind to the
    /// controller's last coherent cursor; it cannot invent or advance progress.
    private func captureAuthorityTransitionAudioSnapshot(
        from controller: ResponsiveAudioProgramController
    ) -> JourneyAction? {
        let exactFailureFallback = controller.runtime.snapshot()
#if DEBUG
        beginContentAuthorityAudioAuditForTesting(controller: controller)
        armAuthorityTransitionTransportProbeForTesting(
            controller: controller
        )
#endif
        do {
            let action = try quiesceAudioControllerForAuthorityTransition(
                controller
            )
#if DEBUG
            if case let .setResponsiveAudioSnapshot(snapshot) = action,
               contentAuthorityAudioAuditProbeIsEnabled {
                contentAuthorityAudioCapturedSnapshotForTesting = snapshot
                updateContentAuthorityAudioDiagnosticForTesting()
            }
#endif
            return action
        } catch {
            controller.stopWithoutPersisting()
            responsiveAudioFailure =
                "The authored sound paused before its place could be verified."
#if DEBUG
            if contentAuthorityQuiesceRecoveryProbeIsEnabled {
                recordContentAuthorityBarrierMilestoneForTesting(
                    "quiesce:failed"
                )
            }
#endif
            do {
                let action = try
                    quiesceAudioControllerForAuthorityTransition(controller)
                // A partial transport failure may have observed a later valid
                // physical cursor without transferring it to the controller.
                // Recovery is authorized to retain only the controller's
                // exact coherent state from before the failed call. Anything
                // else is discarded instead of silently advancing progress.
                guard case let .setResponsiveAudioSnapshot(snapshot) = action,
                      snapshot == exactFailureFallback else {
                    throw JourneyChapterRuntimeError.authoredAudioUnavailable
                }
#if DEBUG
                if contentAuthorityQuiesceRecoveryProbeIsEnabled {
                    contentAuthorityAudioCapturedSnapshotForTesting = snapshot
                    contentAuthorityAudioFallbackSnapshotForTesting = snapshot
                    updateContentAuthorityAudioDiagnosticForTesting()
                    recordContentAuthorityBarrierMilestoneForTesting(
                        "quiesce:recovered"
                    )
                }
#endif
                return action
            } catch {
                // The controller is already stopped. If even its deterministic
                // paused snapshot cannot be represented, discard the live
                // binding and keep the last durable Journey snapshot.
                if responsiveAudioController === controller {
                    responsiveAudioController = nil
                }
                cancelPendingResponsiveAudioBinding()
#if DEBUG
                if contentAuthorityQuiesceRecoveryProbeIsEnabled {
                    recordContentAuthorityBarrierMilestoneForTesting(
                        "quiesce:discarded"
                    )
                }
#endif
                return nil
            }
        }
    }

    private func quiesceAudioControllerForAuthorityTransition(
        _ controller: ResponsiveAudioProgramController
    ) throws -> JourneyAction {
        return try controller.quiesceForSuspension(.sceneInactive)
    }

#if DEBUG
    private func armAuthorityTransitionTransportProbeForTesting(
        controller: ResponsiveAudioProgramController
    ) {
        guard contentAuthorityAudioAuditProbeIsEnabled,
              let probeTransport =
                responsiveAudioAuthorityProbeTransportForTesting,
              probeTransport.controllerID == ObjectIdentifier(controller)
        else { return }
        if contentAuthorityStaleControllerSwapProbeIsEnabled {
            probeTransport.transport.forceNextPauseCursorAdvanceForTesting(
                minimumRenderedSampleAdvance: 256
            )
            return
        }
        guard contentAuthorityQuiesceRecoveryProbeIsEnabled,
              !contentAuthorityQuiesceFailureInjectionDidRun else { return }
        probeTransport.transport.armPauseCompletionFaultForTesting(
            minimumRenderedSampleAdvance: 256
        ) { [weak self, weak controller] snapshot in
            guard let self, let controller,
                  self.responsiveAudioController === controller,
                  !self.contentAuthorityQuiesceFailureInjectionDidRun else {
                return
            }
            self.contentAuthorityQuiesceFailureInjectionDidRun = true
            self.contentAuthorityAudioPartialSnapshotForTesting = snapshot
            self.contentAuthorityAudioTransportPausedForTesting =
                !snapshot.isPlaying
            self.updateContentAuthorityAudioDiagnosticForTesting()
            throw JourneyUITestInjectedPersistenceError
                .authorityPauseCompletion
        }
    }
#endif

    private func lockPersistenceForAuthorityTransition() {
        persistenceIsLocked = true
        isRestoring = true
        failPendingWriteCompletions(
            JourneyChapterRuntimeError.persistenceUnavailable
        )
        pendingActions.removeAll()
        prologuePreview = nil
        state = committedState
        chapterTransitionIsPending = false
        cancelPendingResponsiveAudioBinding()
        responsiveAudioController?.stopWithoutPersisting()
        responsiveAudioController = nil
        cancelResponsiveAudioAutomaticBoundary()
        releaseResponsiveAudioSceneMutationWaiters()
    }

    private func startAuthorityTransitionIfPossible() {
        guard JourneyAuthorityTransitionStartAdmissionPolicy.admits(
            persistenceIsLocked: persistenceIsLocked,
            restorationIsInFlight: isRestoring,
            authorityPreparationIsInFlight:
                authorityTransitionPreparationTask != nil,
            authorityTransitionIsInFlight: authorityTransitionTask != nil,
            authorityRestoreIsInFlight: authorityRestoreIsInFlight,
            persistenceMutationIsInFlight:
                persistenceMutationBarrier.hasActiveMutations
        ) else { return }
        authorityTransitionTask = Task { @MainActor [weak self] in
            await self?.performAuthorityTransition()
        }
    }

    private func performAuthorityTransition() async {
        authorityRestoreIsInFlight = true
        let admittedMutationGeneration =
            persistenceMutationBarrier.generation
        let acceptedLaunch = runtimeContentSnapshot
        let acceptedFuture = futureReleaseContentSnapshot
        var attemptedLaunch = desiredRuntimeContentSnapshot
            ?? runtimeContentSnapshot
        var attemptedFuture = desiredFutureReleaseContentSnapshot
        var preparedAwaitingAcceptance: PreparedPersistenceRestoration?
        defer {
            authorityRestoreIsInFlight = false
            authorityTransitionTask = nil
        }

        do {
            while true {
                attemptedLaunch = desiredRuntimeContentSnapshot
                    ?? runtimeContentSnapshot
                attemptedFuture = desiredFutureReleaseContentSnapshot
                let attemptedIdentity = try saveMigrationAuthorityIdentities(
                    launchSnapshot: attemptedLaunch,
                    futureReleaseSnapshot: attemptedFuture
                )
                let prepared = try await preparePersistenceRestoration(
                    launchSnapshot: attemptedLaunch,
                    futureReleaseSnapshot: attemptedFuture
                )
                preparedAwaitingAcceptance = prepared
                let latestIdentity = try saveMigrationAuthorityIdentities(
                    launchSnapshot: desiredRuntimeContentSnapshot
                        ?? runtimeContentSnapshot,
                    futureReleaseSnapshot:
                        desiredFutureReleaseContentSnapshot
                )
                guard attemptedIdentity == latestIdentity else {
                    preparedAwaitingAcceptance = nil
                    try await prepared
                        .rollbackCommittedSaveMigrationIfNeeded()
                    continue
                }
                guard persistenceMutationBarrier.generation
                    == admittedMutationGeneration,
                      !persistenceMutationBarrier.hasActiveMutations else {
                    preparedAwaitingAcceptance = nil
                    try await prepared
                        .rollbackCommittedSaveMigrationIfNeeded()
                    throw JourneySaveMigrationIntegrationError
                        .persistenceMutationDuringRestoration
                }

                preparedAwaitingAcceptance = nil
                if let attemptedLaunch {
                    publishRuntimeContentSnapshot(attemptedLaunch)
                }
                publishFutureReleaseContentSnapshot(attemptedFuture)
                try accept(prepared)
                persistenceFailure = nil
                persistenceIsLocked = false
                isRestoring = false
                prepareRestoredChapter()
                return
            }
        } catch {
            if let prepared = preparedAwaitingAcceptance {
                preparedAwaitingAcceptance = nil
                do {
                    try await prepared
                        .rollbackCommittedSaveMigrationIfNeeded()
                } catch {
                    failClosedAuthorityTransition()
                    return
                }
            }
            guard packageReversionIsSafe(after: error),
                  let acceptedLaunch else {
                failClosedAuthorityTransition()
                return
            }
            do {
                let reverted = try await revertPackageAuthorityChanges(
                    acceptedLaunch: acceptedLaunch,
                    acceptedFuture: acceptedFuture,
                    attemptedLaunch: attemptedLaunch,
                    attemptedFuture: attemptedFuture
                )
                try requireAttemptedGenerationsWithdrawn(
                    acceptedLaunch: acceptedLaunch,
                    acceptedFuture: acceptedFuture,
                    attemptedLaunch: attemptedLaunch,
                    attemptedFuture: attemptedFuture,
                    revertedLaunch: reverted.launch,
                    revertedFuture: reverted.future
                )
                try adoptRevertedSnapshotsAsDesiredIfCurrentAttempt(
                    revertedLaunch: reverted.launch,
                    revertedFuture: reverted.future,
                    attemptedLaunch: attemptedLaunch,
                    attemptedFuture: attemptedFuture
                )
                let stable = try await prepareLatestDesiredAuthority(
                    admittedMutationGeneration:
                        admittedMutationGeneration
                )
                publishRuntimeContentSnapshot(stable.launch)
                publishFutureReleaseContentSnapshot(stable.future)
                try accept(stable.prepared)
                persistenceFailure = nil
                persistenceIsLocked = false
                isRestoring = false
                prepareRestoredChapter()
            } catch {
                failClosedAuthorityTransition()
            }
        }
    }

    private func adoptRevertedSnapshotsAsDesiredIfCurrentAttempt(
        revertedLaunch: VerifiedJourneyContentSnapshot,
        revertedFuture: VerifiedFutureReleaseContentSnapshot,
        attemptedLaunch: VerifiedJourneyContentSnapshot?,
        attemptedFuture: VerifiedFutureReleaseContentSnapshot
    ) throws {
        if desiredRuntimeContentSnapshot?.revision
            == attemptedLaunch?.revision {
            guard revertedLaunch.revision
                > (desiredRuntimeContentSnapshot?.revision ?? 0) else {
                throw JourneySaveMigrationIntegrationError
                    .authorityChangedDuringRestoration
            }
            applyRuntimeContentSnapshot(revertedLaunch)
        }
        if desiredFutureReleaseContentSnapshot.revision
            == attemptedFuture.revision,
           revertedFuture.revision
            != attemptedFuture.revision {
            guard revertedFuture.revision
                > desiredFutureReleaseContentSnapshot.revision else {
                throw JourneySaveMigrationIntegrationError
                    .authorityChangedDuringRestoration
            }
            applyFutureReleaseContentSnapshot(revertedFuture)
        }
    }

    private func prepareLatestDesiredAuthority(
        admittedMutationGeneration: UInt64
    ) async throws -> (
        launch: VerifiedJourneyContentSnapshot,
        future: VerifiedFutureReleaseContentSnapshot,
        prepared: PreparedPersistenceRestoration
    ) {
        while true {
            guard let launch = desiredRuntimeContentSnapshot
                ?? runtimeContentSnapshot else {
                throw JourneySaveMigrationIntegrationError
                    .verifiedLaunchAuthorityUnavailable
            }
            let future = desiredFutureReleaseContentSnapshot
            let identity = try saveMigrationAuthorityIdentities(
                launchSnapshot: launch,
                futureReleaseSnapshot: future
            )
            let prepared = try await preparePersistenceRestoration(
                launchSnapshot: launch,
                futureReleaseSnapshot: future
            )
            let latest = try saveMigrationAuthorityIdentities(
                launchSnapshot: desiredRuntimeContentSnapshot
                    ?? runtimeContentSnapshot,
                futureReleaseSnapshot: desiredFutureReleaseContentSnapshot
            )
            guard identity == latest else {
                try await prepared
                    .rollbackCommittedSaveMigrationIfNeeded()
                continue
            }
            guard persistenceMutationBarrier.generation
                == admittedMutationGeneration,
                  !persistenceMutationBarrier.hasActiveMutations else {
                try await prepared
                    .rollbackCommittedSaveMigrationIfNeeded()
                throw JourneySaveMigrationIntegrationError
                    .persistenceMutationDuringRestoration
            }
            return (launch, future, prepared)
        }
    }

    private func revertPackageAuthorityChanges(
        acceptedLaunch: VerifiedJourneyContentSnapshot,
        acceptedFuture: VerifiedFutureReleaseContentSnapshot,
        attemptedLaunch: VerifiedJourneyContentSnapshot?,
        attemptedFuture: VerifiedFutureReleaseContentSnapshot
    ) async throws -> (
        launch: VerifiedJourneyContentSnapshot,
        future: VerifiedFutureReleaseContentSnapshot
    ) {
        guard let attemptedLaunch else {
            throw JourneySaveMigrationIntegrationError
                .verifiedLaunchAuthorityUnavailable
        }
        let acceptedLaunchGenerations = launchGenerations(
            in: acceptedLaunch
        )
        let attemptedLaunchGenerations = launchGenerations(
            in: attemptedLaunch
        )
        let acceptedFutureGenerations = try futureReleaseGenerations(
            in: acceptedFuture
        )
        let attemptedFutureGenerations = try futureReleaseGenerations(
            in: attemptedFuture
        )
        var revertedAny = false

        for packageID in attemptedLaunchGenerations.keys.sorted() {
            guard let current = attemptedLaunchGenerations[packageID],
                  acceptedLaunchGenerations[packageID] != current else {
                continue
            }
            guard let contentClient else {
                throw JourneySaveMigrationIntegrationError
                    .exactPackageReversionUnavailable(packageID)
            }
            let exact = try await contentClient
                .revertSaveMigrationAuthorityChange(
                    packageID,
                    current,
                    acceptedLaunchGenerations[packageID]
                )
            if exact == nil,
               try await contentClient.revertSaveMigrationAuthorityChange(
                   packageID,
                   current,
                   nil
               ) == nil {
                throw JourneySaveMigrationIntegrationError
                    .exactPackageReversionUnavailable(packageID)
            }
            revertedAny = true
        }

        for packageID in attemptedFutureGenerations.keys.sorted() {
            guard let current = attemptedFutureGenerations[packageID],
                  acceptedFutureGenerations[packageID] != current else {
                continue
            }
            guard let futureReleaseClient else {
                throw JourneySaveMigrationIntegrationError
                    .exactPackageReversionUnavailable(packageID)
            }
            let exact = try await futureReleaseClient
                .revertSaveMigrationAuthorityChange(
                    packageID,
                    current,
                    acceptedFutureGenerations[packageID]
                )
            if exact == nil,
               try await futureReleaseClient
                .revertSaveMigrationAuthorityChange(
                    packageID,
                    current,
                    nil
                ) == nil {
                throw JourneySaveMigrationIntegrationError
                    .exactPackageReversionUnavailable(packageID)
            }
            revertedAny = true
        }
        guard revertedAny else {
            throw JourneySaveMigrationIntegrationError
                .authorityChangedDuringRestoration
        }

        let launch = await contentClient?.snapshot() ?? acceptedLaunch
        let future = await futureReleaseClient?.contentSnapshot()
            ?? acceptedFuture
        return (launch, future)
    }

    private func requireAttemptedGenerationsWithdrawn(
        acceptedLaunch: VerifiedJourneyContentSnapshot,
        acceptedFuture: VerifiedFutureReleaseContentSnapshot,
        attemptedLaunch: VerifiedJourneyContentSnapshot?,
        attemptedFuture: VerifiedFutureReleaseContentSnapshot,
        revertedLaunch: VerifiedJourneyContentSnapshot,
        revertedFuture: VerifiedFutureReleaseContentSnapshot
    ) throws {
        guard let attemptedLaunch else {
            throw JourneySaveMigrationIntegrationError
                .verifiedLaunchAuthorityUnavailable
        }
        let attempted = try launchGenerations(in: attemptedLaunch)
            .merging(futureReleaseGenerations(in: attemptedFuture)) {
                _, newer in newer
            }
        let accepted = try launchGenerations(in: acceptedLaunch)
            .merging(futureReleaseGenerations(in: acceptedFuture)) {
                _, newer in newer
            }
        let reverted = try launchGenerations(in: revertedLaunch)
            .merging(futureReleaseGenerations(in: revertedFuture)) {
                _, newer in newer
            }
        for (packageID, attemptedGeneration) in attempted
            where accepted[packageID] != attemptedGeneration
                && reverted[packageID] == attemptedGeneration {
            throw JourneySaveMigrationIntegrationError
                .exactPackageReversionUnavailable(packageID)
        }
    }

    private func launchGenerations(
        in snapshot: VerifiedJourneyContentSnapshot
    ) -> [PackageID: InstalledPackageGeneration] {
        Dictionary(uniqueKeysWithValues: snapshot.verifiedPackagesByID.keys
            .filter { $0 != LaunchContent.essentialPackageID }
            .compactMap { packageID in
                snapshot.reconciledInstalledIndex.activeGeneration(
                    for: packageID
                ).map { (packageID, $0) }
            })
    }

    private func futureReleaseGenerations(
        in snapshot: VerifiedFutureReleaseContentSnapshot
    ) throws -> [PackageID: InstalledPackageGeneration] {
        try VerifiedFutureReleaseSaveMigrationGenerations(
            snapshot: snapshot
        ).byPackageID
    }

    private func packageReversionIsSafe(after error: any Error) -> Bool {
        if let storeError = error as? ProgressStoreError {
            switch storeError {
            case .migrationRollbackTampered, .migrationRollbackAuthorityMismatch,
                 .migrationRollbackStale, .migrationRollbackFailed:
                return false
            default:
                return true
            }
        }
        if let appendFailure = error as? ProgressStoreAppendFailure {
            if appendFailure.disposition == .durabilityIndeterminate {
                return false
            }
            return packageReversionIsSafe(
                after: appendFailure.underlyingError
            )
        }
        return true
    }

    private func failClosedAuthorityTransition() {
        state = committedState
        persistenceIsLocked = true
        isRestoring = false
        persistenceFailure = "Saved progress could not be verified."
    }

    private func presentDownloadRequestResult(_ result: DownloadControllerRequestResult) {
        switch result {
        case .started:
            return
        case let .noOperation(reason):
            if reason == .newerVersionRequiresNewerApp {
                downloadFailure = .command(
                    "Update the app to open the newer chapter files already on this iPhone."
                )
            }
        case let .blocked(reason):
            let message: String
            switch reason {
            case .offline:
                message = "Connect to the internet to begin this download."
            case .unknownNetwork:
                message = "A network connection could not be confirmed. Try again."
            case .cellularDownloadsDisabled:
                message = "Connect to Wi-Fi or allow new downloads to start on cellular in Settings."
            case .automaticDeepDiveDownloadsDisabled:
                message = "Automatic deep-dive downloads are turned off."
            case .lowDataMode:
                message = "This automatic download is waiting until Low Data Mode is off."
            }
            downloadFailure = .command(message)
        case .installerRejected:
            downloadFailure = .command(
                "Another chapter group is already being prepared."
            )
        }
    }

    func restoreExperiencePreferences() async {
        do {
            let activeStore: ExperiencePreferencesStore
            if let experiencePreferencesStore {
                activeStore = experiencePreferencesStore
            } else {
                let created = try ExperiencePreferencesStore(
                    directoryURL: experiencePreferencesStorageURL
                )
                experiencePreferencesStore = created
                activeStore = created
            }

            let result = try await activeStore.load()
            experiencePreferences = result.preferences
            switch result.origin {
            case .defaultsBecauseFileIsMissing, .stored, .migrated:
                experiencePreferencesFailure = nil
            case .recoveredFromCorruptFile:
                experiencePreferencesFailure = .recoveredDefaults
            case .defaultsProtectedFromFutureSchema:
                experiencePreferencesFailure = .readOnlyUntilAppUpdate
            }
            applyExperiencePreferences(result.preferences)
        } catch {
            experiencePreferences = .standard
            experiencePreferencesFailure = .storageUnavailable
            applyExperiencePreferences(.standard)
        }
    }

    func persistExperiencePreference(
        _ keyPath: WritableKeyPath<ExperiencePreferences, Bool>,
        value: Bool
    ) {
        guard !experiencePreferenceEditingIsDisabled else { return }
        var candidate = experiencePreferences
        guard candidate[keyPath: keyPath] != value else { return }
        candidate[keyPath: keyPath] = value
        experiencePreferenceWriteIsPending = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { experiencePreferenceWriteIsPending = false }
            guard let experiencePreferencesStore else {
                experiencePreferencesFailure = .storageUnavailable
                return
            }
            do {
                try await experiencePreferencesStore.save(candidate)
                experiencePreferences = candidate
                if experiencePreferencesFailure == .recoveredDefaults {
                    experiencePreferencesFailure = nil
                }
                applyExperiencePreferences(candidate)
            } catch let error as ExperiencePreferencesStoreError {
                if case .futureSchemaWriteBlocked = error {
                    experiencePreferencesFailure = .readOnlyUntilAppUpdate
                } else {
                    experiencePreferencesFailure = .storageUnavailable
                }
            } catch {
                experiencePreferencesFailure = .storageUnavailable
            }
        }
    }

    private func applyExperiencePreferences(_ preferences: ExperiencePreferences) {
        causalHapticTransport.applyPreferences(preferences)
        responsiveAudioController?.applyPreferences(preferences)
    }

    private func restore() async {
        isRestoring = true
        persistenceIsLocked = true
        authorityRestoreIsInFlight = true
        // An old process-local flush must finish before its committer and
        // persistence receipt can be replaced by this restoration.
        _ = await suspensionEpisodeCoordinator.awaitCurrentFlush()
        failPendingWriteCompletions(
            JourneyChapterRuntimeError.persistenceUnavailable
        )
        pendingActions.removeAll()
        committer = nil
        prologuePreview = nil
        chapterCursor = nil
        contentFailure = nil
        chapterTransitionIsPending = false
        responsiveAudioController?.stopWithoutPersisting()
        responsiveAudioController = nil
        cancelResponsiveAudioAutomaticBoundary()
        releaseResponsiveAudioSceneMutationWaiters()
        defer {
            authorityRestoreIsInFlight = false
            isRestoring = false
            receiveDesiredContentAuthorityChange()
            performPostRestoreUnavailableChapterFallbackIfNeeded()
#if DEBUG
            openSignedRuntimeFixtureIfNeeded()
#endif
        }
        do {
            while true {
                let targetLaunch = desiredRuntimeContentSnapshot
                    ?? runtimeContentSnapshot
                let targetFuture = desiredFutureReleaseContentSnapshot
                let targetIdentity = try saveMigrationAuthorityIdentities(
                    launchSnapshot: targetLaunch,
                    futureReleaseSnapshot: targetFuture
                )
                let prepared = try await preparePersistenceRestoration(
                    launchSnapshot: targetLaunch,
                    futureReleaseSnapshot: targetFuture
                )
                let latestIdentity = try saveMigrationAuthorityIdentities(
                    launchSnapshot: desiredRuntimeContentSnapshot
                        ?? runtimeContentSnapshot,
                    futureReleaseSnapshot:
                        desiredFutureReleaseContentSnapshot
                )
                guard targetIdentity == latestIdentity else {
                    try await prepared
                        .rollbackCommittedSaveMigrationIfNeeded()
                    continue
                }

                if let targetLaunch {
                    publishRuntimeContentSnapshot(targetLaunch)
                }
                publishFutureReleaseContentSnapshot(targetFuture)
                try accept(prepared)
                try await enforceRestoredEntitlementFallbackIfNeeded()
                await recordRestoredHistoricalExperience(
                    committedState
                )
                let latestAfterAcceptedWrites = try
                    saveMigrationAuthorityIdentities(
                        launchSnapshot: desiredRuntimeContentSnapshot
                            ?? runtimeContentSnapshot,
                        futureReleaseSnapshot:
                            desiredFutureReleaseContentSnapshot
                    )
                if targetIdentity != latestAfterAcceptedWrites {
                    // The target is now the accepted current authority and
                    // owns the fallback write. Keep the black persistence
                    // lock in place; defer starts a fresh transition for the
                    // newer desired snapshot after this restore finishes.
                    persistenceFailure = nil
                    return
                }
                break
            }
            persistenceFailure = nil
            persistenceIsLocked = false
            prepareRestoredChapter()
#if DEBUG
            if suspensionPersistenceRetryInjectionDidRun,
               suspensionPersistenceRetryDiagnosticForTesting.contains(
                   "append-failed"
               ),
               !suspensionPersistenceRetryDiagnosticForTesting.hasSuffix(
                   ">restored"
               ) {
                recordSuspensionPersistenceRetryMilestoneForTesting(
                    "restored"
                )
            }
#endif
        } catch {
            state = committedState
            persistenceFailure = "Saved progress could not be verified."
        }
    }

    private func resolvePhysicalPauseAfterAcceptedRestoration() {
        preQuiescedSuspensionAction = nil
        preQuiescedSuspensionFailed = false
        chapterRuntimePhysicalPauseGate = nil
        unresolvedResponsiveAudioPhysicalPauseEvent = nil
        responsiveAudioPhysicalPauseEvent = nil
    }

    private func preparePersistenceRestoration(
        launchSnapshot: VerifiedJourneyContentSnapshot?,
        futureReleaseSnapshot: VerifiedFutureReleaseContentSnapshot
    ) async throws -> PreparedPersistenceRestoration {
        let authorities = try saveMigrationAuthorities(
            launchSnapshot: launchSnapshot,
            futureReleaseSnapshot: futureReleaseSnapshot
        )
        let activeStore = try ProgressStore(
            directoryURL: storageURL,
            saveMigrationRegistry: saveMigrationRegistry,
            saveMigrationAuthorities: authorities
        )
        let initialState = try restorationInitialState(
            launchSnapshot: launchSnapshot
        )
        let saveMigrationPreparation = try await
            SaveMigrationRestorationPreparer.prepare(store: activeStore) {
                try await activeStore.restore(initialState: initialState)
            }
        let restoration = saveMigrationPreparation.restoration
#if DEBUG
        let suspensionAppendFault = suspensionAppendFaultForTesting
#endif
        let restoredCommitter = DurableJourneyCommitter(
            restoredState: restoration.state,
            lastSequence: restoration.lastSequence,
            append: { request in
#if DEBUG
                if let suspensionAppendFault,
                   await suspensionAppendFault.shouldFail(request) {
                    throw ProgressStoreAppendFailure(
                        disposition: .noJournalRecordWriteAttempted,
                        underlyingError:
                            JourneyUITestInjectedPersistenceError
                                .suspensionAppend
                    )
                }
#endif
                return try await activeStore.append(request)
            },
            checkpoint: { commit in
                try await activeStore.checkpoint(commit)
            }
        )
        return PreparedPersistenceRestoration(
            store: activeStore,
            committer: restoredCommitter,
            restoration: restoration,
            saveMigrationPreparation: saveMigrationPreparation
        )
    }

    /// Ownership fallback is an ordinary write under an already accepted
    /// package authority. Keeping it after the target/latest identity check
    /// preserves the exact migration rollback pair if a snapshot continuation
    /// supersedes the prepared authority while restoration is suspended.
    private func enforceRestoredEntitlementFallbackIfNeeded() async throws {
        guard case let .chapter(chapterID) = committedState.route,
              FoundationCatalog.chapters.contains(where: {
                  $0.id == chapterID
              }),
              !accessResolver.canOpen(
                  chapterID,
                  snapshot: entitlementSnapshot,
                  at: Date()
              ), let committer else { return }

        guard let mutation = persistenceMutationBarrier.beginRestoreInternal(
            authorityRestoreIsInFlight: authorityRestoreIsInFlight,
            persistenceIsLocked: persistenceIsLocked
        ) else {
            throw JourneySaveMigrationIntegrationError
                .persistenceMutationDuringRestoration
        }
        var mutationIsActive = true
        defer {
            if mutationIsActive {
                _ = persistenceMutationBarrier.finish(mutation)
            }
        }

        var fallback: DurableJourneyCommit?
        do {
            var actions: [JourneyAction] = []
            if let session = committedState.activeChapter,
               session.responsiveAudioSessionIsActive,
               let snapshot = session.responsiveAudioSnapshot {
                actions.append(.endResponsiveAudioSession(snapshot))
            }
            actions.append(.showWorld)
            for action in actions {
                let commit = try await committer.commit(action)
                if commit.requiresCheckpoint {
                    try await committer.checkpoint(commit)
                }
                fallback = commit
            }
        } catch {
            guard persistenceMutationBarrier.finish(mutation) else {
                throw JourneySaveMigrationIntegrationError
                    .persistenceMutationDuringRestoration
            }
            mutationIsActive = false
            throw error
        }
        guard let fallback else {
            throw JourneySaveMigrationIntegrationError
                .persistenceMutationDuringRestoration
        }
        committedState = fallback.state
        state = fallback.state
        lastCommittedSequence = fallback.sequence
        guard persistenceMutationBarrier.finish(mutation) else {
            throw JourneySaveMigrationIntegrationError
                .persistenceMutationDuringRestoration
        }
        mutationIsActive = false
    }

    private func accept(_ prepared: PreparedPersistenceRestoration) throws {
        guard suspensionEpisodeCoordinator.acceptDurableRestoration() else {
            throw JourneySaveMigrationIntegrationError
                .persistenceMutationDuringRestoration
        }
        try persistenceAuthorityFence.accept(prepared.committer)
        store = prepared.store
        committer = prepared.committer
        state = prepared.restoration.state
        committedState = prepared.restoration.state
        lastCommittedSequence = prepared.restoration.lastSequence
        resolvePhysicalPauseAfterAcceptedRestoration()
    }

    private func restorationInitialState(
        launchSnapshot: VerifiedJourneyContentSnapshot?
    ) throws -> JourneyState {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains(
            DevelopmentSignedRuntimeFixtureAppContent.launchArgument
        ), let launchSnapshot {
            return JourneyState(
                world: try WorldGraph(seed: launchSnapshot.repository.worldSeed)
            )
        }
        if usesDevelopmentFirstFarmersPersistenceAuthority {
            if let developmentFirstFarmers {
                return try developmentInitialJourneyState(
                    envelope: developmentFirstFarmers
                )
            }
            // The two corrupt-envelope UI fixtures intentionally withhold a
            // usable development authority. They still need a fresh empty
            // store so the test can prove that selecting the road fails
            // before any chapter mutation is accepted.
            return .initial
        }
#endif
        return .initial
    }

    private func saveMigrationAuthorities(
        launchSnapshot: VerifiedJourneyContentSnapshot?,
        futureReleaseSnapshot: VerifiedFutureReleaseContentSnapshot
    ) throws -> [VerifiedPackageSaveMigrationAuthority] {
#if DEBUG
        if usesDevelopmentFirstFarmersPersistenceAuthority
            || ProcessInfo.processInfo.arguments.contains(
                DevelopmentSignedRuntimeFixtureAppContent.launchArgument
            ) {
            return []
        }
#endif
        guard let launchSnapshot else {
            throw JourneySaveMigrationIntegrationError
                .verifiedLaunchAuthorityUnavailable
        }
        return try VerifiedSaveMigrationAuthoritySet(
            launchSnapshot: launchSnapshot,
            futureReleaseSnapshot: futureReleaseSnapshot
        ).authorities
    }

    private func saveMigrationAuthorityIdentities(
        launchSnapshot: VerifiedJourneyContentSnapshot?,
        futureReleaseSnapshot: VerifiedFutureReleaseContentSnapshot
    ) throws -> [SaveMigrationPackageAuthorityIdentity] {
#if DEBUG
        if usesDevelopmentFirstFarmersPersistenceAuthority
            || ProcessInfo.processInfo.arguments.contains(
                DevelopmentSignedRuntimeFixtureAppContent.launchArgument
            ) {
            return []
        }
#endif
        guard let launchSnapshot else {
            throw JourneySaveMigrationIntegrationError
                .verifiedLaunchAuthorityUnavailable
        }
        return try VerifiedSaveMigrationAuthoritySet(
            launchSnapshot: launchSnapshot,
            futureReleaseSnapshot: futureReleaseSnapshot
        ).identities
    }

#if DEBUG
    /// Keeps deliberately missing or forged development envelopes inside the
    /// same non-shipping persistence domain as the valid development payload.
    /// This is gated by exact UI-test launch arguments and is absent from
    /// Release builds.
    private var usesDevelopmentFirstFarmersPersistenceAuthority: Bool {
        if developmentFirstFarmers != nil { return true }
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing-missing-development-payload")
            || arguments.contains("--ui-testing-forged-development-payload")
    }
#endif

#if DEBUG
    private func openSignedRuntimeFixtureIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains(
            DevelopmentSignedRuntimeFixtureAppContent.launchArgument
        ), persistenceFailure == nil,
           !persistenceIsLocked,
           !chapterTransitionIsPending else { return }
        let targetChapterID =
            DevelopmentSignedRuntimeFixtureAppContent.targetChapterID()
        if case let .chapter(chapterID) = committedState.route,
           chapterID == targetChapterID {
            return
        }
        guard let snapshot = runtimeContentSnapshot,
              let chapter = snapshot.repository.catalogEntry(targetChapterID) else {
            return
        }
        _ = openVerifiedChapter(chapter, snapshot: snapshot)
    }

    private func developmentInitialJourneyState(
        envelope: DevelopmentFirstFarmersEnvelope
    ) throws -> JourneyState {
        let base = try envelope.initialJourneyState()
        guard ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-paid-restoration"
        ) else {
            return base
        }

        let chapterID: ChapterID = "steppe-comes-west"
        guard let chapter = FoundationCatalog.chapters.first(where: {
                  $0.id == chapterID
              }),
              let package = LaunchContent.collectionManifest.packages.first(where: {
                  $0.id == chapter.packageID
              }) else {
            return base
        }
        return JourneyState(
            route: .chapter(chapterID),
            prologue: base.prologue,
            world: base.world,
            activeChapter: ChapterSession(
                chapterID: chapterID,
                packageID: package.id,
                contentVersion: package.version
            ),
            installedContent: [
                InstalledContentVersion(
                    packageID: package.id,
                    version: package.version
                ),
            ]
        )
    }
#endif

    private func prepareRestoredChapter() {
        guard case let .chapter(chapterID) = committedState.route else {
            chapterCursor = nil
            return
        }
        if let future = installedFutureRelease(containing: chapterID) {
            activeFutureReleaseID = future.releaseID
            let coordinator = ChapterCoordinator(
                repository: future.authority.repository
            )
            chapterCoordinator = coordinator
            prepareRestoredChapter(
                chapterID,
                coordinator: coordinator,
                failureMessage:
                    "The saved historical route could not be verified against installed content."
            )
            return
        }
        if runtimeContentSnapshot?.repository.chapter(chapterID) != nil,
           let chapterCoordinator {
            prepareRestoredChapter(
                chapterID,
                coordinator: chapterCoordinator,
                failureMessage: "The saved chapter position could not be verified against installed content."
            )
            return
        }
#if DEBUG
        guard chapterID == DevelopmentFirstFarmersRepository.chapterID,
              let chapterCoordinator else {
            prepareUnavailableRestoredChapter(chapterID)
            return
        }
        prepareRestoredChapter(
            chapterID,
            coordinator: chapterCoordinator,
            failureMessage: "The saved First Farmers position could not be verified against the development payload."
        )
#else
        prepareUnavailableRestoredChapter(chapterID)
#endif
    }

    private func prepareRestoredChapter(
        _ chapterID: ChapterID,
        coordinator: ChapterCoordinator,
        failureMessage: String
    ) {
        do {
            let resumeActions = try coordinator.resumeActions(
                chapterID: chapterID,
                state: committedState
            )
            let repairActions = resumeActions.filter { action in
                if case .selectChapter = action { return false }
                return true
            }
            if repairActions.isEmpty {
                refreshChapterPresentation(bindResponsiveAudio: true)
            } else {
                chapterTransitionIsPending = true
                enqueue(repairActions, allowWhileRestoring: true)
            }
        } catch {
            chapterCursor = nil
            contentFailure = failureMessage
        }
    }

    private func prepareUnavailableRestoredChapter(_ chapterID: ChapterID) {
        guard let chapter = FoundationCatalog.chapters.first(where: {
            $0.id == chapterID
        }), chapter.packageID != LaunchContent.essentialPackageID else {
            contentFailure = "This saved chapter is not installed in this build."
            return
        }
        offlineChapterRequest = OfflineChapterRequest(
            chapterID: chapterID,
            packageID: chapter.packageID
        )
        if isRestoring {
            postRestoreUnavailableChapterFallbackIsPending = true
            return
        }
        chapterTransitionIsPending = true
        enqueueOrderedJourneyTransition([.showWorld])
    }

    private func performPostRestoreUnavailableChapterFallbackIfNeeded() {
        guard postRestoreUnavailableChapterFallbackIsPending,
              !isRestoring,
              !persistenceIsLocked,
              !chapterTransitionIsPending else {
            return
        }
        postRestoreUnavailableChapterFallbackIsPending = false
        chapterTransitionIsPending = true
        enqueueOrderedJourneyTransition([.showWorld])
    }

    /// Loads only the authenticated local ownership snapshot before Journey
    /// restoration. A paid saved route can therefore never become visible
    /// under an unknown entitlement while StoreKit is still being contacted.
    private func prepareCommerceForRestoration() async {
        do {
            if commerceClient == nil {
                let directory = storageURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("commerce-v1", isDirectory: true)
                let snapshotStore = try EntitlementSnapshotStore(
                    directoryURL: directory,
                    keyProvider: KeychainEntitlementIntegrityKeyProvider()
                )
                let controller = try EntitlementController(
                    provider: StoreKit2Provider(),
                    snapshotStore: snapshotStore
                )
                commerceClient = JourneyCommerceClient(controller: controller)
            }
            guard let commerceClient else { throw CommerceFailure.productUnavailable }
            applyEntitlementSnapshot(await commerceClient.currentSnapshot())
        } catch {
            commerceClient = nil
            entitlementSnapshot = nil
            storeDisplayPrice = nil
        }
    }

    /// Starts live StoreKit work only after the local Journey has restored
    /// against the cached ownership authority.
    private func configureCommerceAfterRestoration() async {
        do {
            guard let commerceClient else { throw CommerceFailure.productUnavailable }
            applyEntitlementSnapshot(entitlementSnapshot)
            let updates = await commerceClient.snapshotUpdates()
            entitlementObservationTask?.cancel()
            entitlementObservationTask = Task { @MainActor [weak self] in
                for await snapshot in updates {
                    guard !Task.isCancelled else { break }
                    self?.applyEntitlementSnapshot(snapshot)
                }
            }
            await commerceClient.startTransactionListener()

            async let productResult: CommerceProduct? = try? commerceClient.productDetails()
            let refresh = await commerceClient.refreshCurrentEntitlements()
            switch refresh {
            case let .updated(snapshot), let .retainedCached(snapshot, _):
                applyEntitlementSnapshot(snapshot)
            }
            storeDisplayPrice = await productResult?.displayPrice
        } catch {
            // Corrupt or unavailable commerce state fails closed without
            // blocking the three included chapters or offline restoration.
            commerceClient = nil
            entitlementSnapshot = nil
            storeDisplayPrice = nil
        }
    }

    private func applyEntitlementSnapshot(_ snapshot: EntitlementSnapshot?) {
        entitlementSnapshot = snapshot
        guard snapshot?.grantsAccess(at: Date()) != true else { return }

        if case let .chapter(chapterID) = committedState.route,
           FoundationCatalog.chapters.contains(where: {
               $0.id == chapterID
           }),
           !accessResolver.canOpen(chapterID, snapshot: snapshot, at: Date()) {
            chapterTransitionIsPending = true
            enqueueOrderedJourneyTransition([.showWorld])
        }

        pausePaidQueueAfterCurrentPackageIfNeeded()
    }

    private func pausePaidQueueAfterCurrentPackageIfNeeded() {
        guard !downloadCommandIsPending,
              entitlementSnapshot?.grantsAccess(at: Date()) != true,
              downloadPresentation?.allowedCommands.contains(
                  .requestQueuePauseAfterCurrentPackage
              ) == true else { return }
        performDownloadCommand(.requestQueuePauseAfterCurrentPackage)
    }

    private func send(_ action: JourneyAction) {
        enqueue([action])
    }

    private func enqueue(
        _ actions: [JourneyAction],
        allowWhileRestoring: Bool = false
    ) {
        guard appendPendingActionsWithoutStartingDrain(
            actions,
            allowWhileRestoring: allowWhileRestoring
        ) else { return }
        startWriteDrainIfNeeded()
    }

    @discardableResult
    private func appendPendingActionsWithoutStartingDrain(
        _ actions: [JourneyAction],
        allowWhileRestoring: Bool = false
    ) -> Bool {
        guard (allowWhileRestoring || !isRestoring),
              !persistenceIsLocked,
              authorityTransitionPreparationTask == nil,
              !actions.isEmpty else { return false }
        pendingActions.append(contentsOf: actions.map {
            PendingAction(
                action: $0,
                prologuePreviewRevision: prologuePreviewRevision
            )
        })
        return true
    }

    /// Enqueues one ordered durability batch and returns only after its final
    /// journal append and required checkpoint have completed. Suspension and
    /// route-exit leases use this boundary so background execution is not
    /// released merely because work entered the in-memory queue.
    private func enqueueAndAwaitDurability(
        _ actions: [JourneyAction],
        durableCommitHookAt hookIndex: Int? = nil,
        durableCommitHook: (@MainActor () -> Void)? = nil
    ) async throws {
        guard !isRestoring, !persistenceIsLocked, !actions.isEmpty else {
            throw JourneyChapterRuntimeError.persistenceUnavailable
        }
        let completionID = UUID()
        let boundaryLatch: DurableCommitBoundaryLatch?
        if let hookIndex, let durableCommitHook {
            boundaryLatch = DurableCommitBoundaryLatch(
                boundaryActionIndex: hookIndex,
                fire: durableCommitHook
            )
        } else {
            boundaryLatch = nil
        }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            pendingWriteCompletions[completionID] = continuation
            for (index, action) in actions.enumerated() {
                let pendingHook: (@MainActor () -> Void)?
                if let boundaryLatch {
                    pendingHook = {
                        boundaryLatch.actionDidBecomeDurable(at: index)
                    }
                } else {
                    pendingHook = nil
                }
                pendingActions.append(
                    PendingAction(
                        action: action,
                        prologuePreviewRevision: prologuePreviewRevision,
                        completionID: index == actions.count - 1
                            ? completionID
                            : nil,
                        durableCommitHook: pendingHook
                    )
                )
            }
            startWriteDrainIfNeeded()
        }
    }

    private func startWriteDrainIfNeeded() {
        guard !isDrainingWrites else { return }
        guard let mutation = beginPersistenceMutation() else { return }
        isDrainingWrites = true
        Task { @MainActor [weak self] in
            await self?.drainWrites(mutation: mutation)
        }
    }

    private func drainWrites(
        mutation: JourneyPersistenceMutationToken
    ) async {
        defer {
            isDrainingWrites = false
            if orderedJourneyTransitionTask == nil {
                chapterTransitionIsPending = false
            }
            refreshChapterPresentation(bindResponsiveAudio: true)
            openPendingChapterIfAvailable()
            finishPersistenceMutation(mutation)
        }
        guard let committer else {
            failPersistence(message: "Local progress storage could not be opened.")
            return
        }
        while !pendingActions.isEmpty {
            let pending = pendingActions.removeFirst()
            let commit: DurableJourneyCommit
            do {
                commit = try await committer.commit(pending.action)
            } catch {
                failPersistence(message: "Progress could not be saved.")
                return
            }

            // The journal record is complete and synchronised. Only now may a
            // causal route, world effect or completion become lasting UI state.
            let previousState = committedState
            committedState = commit.state
            lastCommittedSequence = commit.sequence
            // Authority follows the exact journal record that first opens
            // the new route. A failed prior append leaves the old authority
            // untouched; a later checkpoint failure cannot roll back an
            // already durable chapter selection.
            pending.durableCommitHook?()
            do {
                try await rotateResponsiveAudioCursorAuthorityIfNeeded(
                    journalCapture:
                        pending.responsiveAudioJournalCapture
                )
            } catch {
                failClosedResponsiveAudioCursorImmediately(
                    diagnostic: "handoffAfterDurableCommit;error="
                        + Self.responsiveAudioCursorErrorType(error)
                )
            }
            publish(commit.state, after: pending)
            refreshChapterPresentation(bindResponsiveAudio: false)
            presentCausalEffects(commit.effects)
            enqueueResponsiveAudioFollowUpIfNeeded(after: commit)
            completePendingDurabilityCallbackIfNeeded(pending)
            await recordHistoricalExperienceTransition(
                from: previousState,
                to: commit.state
            )

            if commit.requiresCheckpoint {
                do {
                    try await committer.checkpoint(commit)
                } catch let error as DurableJourneyCommitterError {
                    if case .staleCheckpoint = error {
                        // A later durable commit already superseded this
                        // optional compaction. Its journal record is complete;
                        // skipping this checkpoint cannot lose progress.
                        completePendingWriteIfNeeded(pending)
                        continue
                    }
                    failPersistenceAfterCommit(
                        message: "Progress was recorded, but its checkpoint could not be completed."
                    )
                    return
                } catch {
                    failPersistenceAfterCommit(
                        message: "Progress was recorded, but its checkpoint could not be completed."
                    )
                    return
                }
            }
            completePendingWriteIfNeeded(pending)
        }
    }

    private func completePendingDurabilityCallbackIfNeeded(
        _ pending: PendingAction
    ) {
        guard let id = pending.completionID else { return }
        pendingDurabilityCallbacks.removeValue(forKey: id)?
            .succeeded()
    }

    private func completePendingWriteIfNeeded(_ pending: PendingAction) {
        guard let id = pending.completionID else { return }
        if let continuation = pendingWriteCompletions.removeValue(
            forKey: id
        ) {
            continuation.resume()
        }
    }

    private func failPendingWriteCompletions(_ error: any Error) {
        let continuations = pendingWriteCompletions.values
        pendingWriteCompletions.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
        let callbacks = pendingDurabilityCallbacks.values
        pendingDurabilityCallbacks.removeAll()
        for callback in callbacks { callback.failed() }
    }

    private func beginPersistenceMutation()
        -> JourneyPersistenceMutationToken? {
        guard !persistenceIsLocked else { return nil }
        guard let token = persistenceMutationBarrier.begin() else {
            failPersistence(
                message: "Local progress storage could not admit another write."
            )
            return nil
        }
        return token
    }

    private func finishPersistenceMutation(
        _ token: JourneyPersistenceMutationToken
    ) {
        guard persistenceMutationBarrier.finish(token) else {
            failPersistence(
                message: "Local progress storage lost its write authority."
            )
            return
        }
        if !persistenceMutationBarrier.hasActiveMutations {
            startAuthorityTransitionIfPossible()
            resumeDeferredContentAuthorityRetryIfPossible()
        }
    }

    private func recordRestoredHistoricalExperience(_ restoredState: JourneyState) async {
        guard let releaseDiscovery else { return }
        if restoredState.prologue.phase == .awakened {
            await releaseDiscovery.recordHistoricalExperience(.prologueCompleted)
            return
        }
        if restoredState.chapterSessions.contains(where: {
            !$0.completedBeatIDs.isEmpty
        }) {
            await releaseDiscovery.recordHistoricalExperience(.historicalBeatCompleted)
        }
    }

    private func recordHistoricalExperienceTransition(
        from previous: JourneyState,
        to current: JourneyState
    ) async {
        guard let releaseDiscovery else { return }
        if previous.prologue.phase != .awakened,
           current.prologue.phase == .awakened {
            await releaseDiscovery.recordHistoricalExperience(.prologueCompleted)
            return
        }
        let previousCompletedBeats = previous.chapterSessions.reduce(into: 0) {
            $0 += $1.completedBeatIDs.count
        }
        let currentCompletedBeats = current.chapterSessions.reduce(into: 0) {
            $0 += $1.completedBeatIDs.count
        }
        if currentCompletedBeats > previousCompletedBeats {
            await releaseDiscovery.recordHistoricalExperience(.historicalBeatCompleted)
        }
    }

    private func refreshChapterPresentation(bindResponsiveAudio: Bool) {
        guard case let .chapter(chapterID) = committedState.route else {
            chapterCursor = nil
            activeFutureReleaseID = nil
            if let runtimeContentSnapshot {
                chapterCoordinator = ChapterCoordinator(
                    repository: runtimeContentSnapshot.repository
                )
            }
            cancelPendingResponsiveAudioBinding()
            responsiveAudioController?.stopWithoutPersisting()
            responsiveAudioController = nil
            responsiveAudioFailure = nil
            return
        }
        guard let chapterCoordinator else {
            chapterCursor = nil
            if !chapterTransitionIsPending {
                contentFailure = "This saved chapter is not installed in this build."
            }
            return
        }
        do {
            let cursor = try chapterCoordinator.resolveCursor(
                chapterID: chapterID,
                state: committedState
            )
            chapterCursor = cursor
            contentFailure = nil
            if bindResponsiveAudio {
                configureResponsiveAudioIfAvailable(coordinator: chapterCoordinator)
            }
        } catch {
            chapterCursor = nil
            if !chapterTransitionIsPending {
                contentFailure = "The saved chapter position could not be verified against installed content."
            }
        }
    }

    private func configureResponsiveAudioIfAvailable(
        coordinator: ChapterCoordinator
    ) {
        let requestedIdentity = responsiveAudioBindingIdentityForCurrentRoute()
        if requestedIdentity == responsiveAudioBindingIdentity,
           (responsiveAudioBindingTask != nil || responsiveAudioController != nil) {
            return
        }
        cancelPendingResponsiveAudioBinding()
        let controllerReplacementBarrier =
            beginResponsiveAudioControllerReplacement()
        var authorityForConstructionFailure: PackageAssetFailureAuthority?
        do {
            guard let plan = try coordinator.responsiveAudioRestorationPlan(
                state: committedState
            ) else {
                responsiveAudioFailure = nil
                return
            }
            guard let identity = requestedIdentity else {
                responsiveAudioFailure = "The authored sound could not be joined to this chapter position."
                return
            }
            if let packageID = committedState.activeChapter?.packageID,
               let runtimeAuthority = currentChapterRuntimeAuthority(),
               let packageRootURL = runtimeAuthority.packageRootURL(
                   for: packageID
               ), let verifiedPackage = runtimeAuthority.verifiedPackage(
                   for: packageID
               ) {
                let assetFailureAuthority = runtimeAuthority.assetFailureAuthority(
                    for: packageID
                )
                authorityForConstructionFailure = assetFailureAuthority
                let resolver = try ManifestBoundAudioAssetResolver(
                    verifiedPackage: verifiedPackage,
                    activatedPackageRoot: packageRootURL
                )
                startResponsiveAudioBinding(
                    plan: plan,
                    resolver: resolver,
                    identity: identity,
                    assetFailureAuthority: assetFailureAuthority,
                    failureMessage: "Required authored audio files could not be verified offline.",
                    controllerReplacementBarrier:
                        controllerReplacementBarrier
                )
                return
            }
#if DEBUG
            guard let developmentFirstFarmers else {
                responsiveAudioFailure = "The development audio package is unavailable."
                return
            }
            let resolver = PackageRootAudioAssetResolver(
                packageRootURL: developmentFirstFarmers.resourceRootURL
            )
            startResponsiveAudioBinding(
                plan: plan,
                resolver: resolver,
                identity: identity,
                assetFailureAuthority: nil,
                failureMessage: "Required authored audio files are absent from this development package.",
                controllerReplacementBarrier:
                    controllerReplacementBarrier
            )
#else
            responsiveAudioFailure = "The authored audio package is unavailable."
#endif
        } catch {
            responsiveAudioController?.stopWithoutPersisting()
            responsiveAudioController = nil
            responsiveAudioFailure = "Required authored audio files are absent from this development package."
            if let authorityForConstructionFailure {
                Task { @MainActor [weak self] in
                    _ = await self?.reportChapterAssetFailure(
                        authorityForConstructionFailure
                    )
                }
            }
        }
    }

    private func startResponsiveAudioBinding(
        plan: ResponsiveAudioRestorationPlan,
        resolver: any OfflineAudioAssetResolving,
        identity: ResponsiveAudioBindingIdentity,
        assetFailureAuthority: PackageAssetFailureAuthority?,
        failureMessage: String,
        controllerReplacementBarrier: Task<Void, Never>?
    ) {
        let paths = Array(Set(
            plan.timelines
                .flatMap(\.events)
                .filter { $0.role != .silence }
                .compactMap(\.assetPath)
        )).sorted()
        responsiveAudioBindingIdentity = identity
        responsiveAudioFailure = nil
#if DEBUG
        responsiveAudioBindingDiagnosticForTesting = "started"
#endif
        let task = Task { @MainActor [weak self] in
            defer {
                if let self, self.responsiveAudioBindingIdentity == identity {
                    self.responsiveAudioBindingTask = nil
                }
            }
            do {
                if let controllerReplacementBarrier {
                    await controllerReplacementBarrier.value
                }
                try Task.checkCancellation()
                guard let self,
                      self.responsiveAudioBindingIdentity == identity,
                      self.responsiveAudioBindingIdentityForCurrentRoute()
                        == identity else {
                    return
                }
                try await OfflineAudioAssetPrewarmer.prewarm(
                    paths: paths,
                    resolver: resolver
                )
                try Task.checkCancellation()
#if DEBUG
                self.responsiveAudioBindingDiagnosticForTesting = "prewarmed"
#endif
                guard self.responsiveAudioBindingIdentity == identity,
                      self.responsiveAudioBindingIdentityForCurrentRoute() == identity else {
#if DEBUG
                    self.responsiveAudioBindingDiagnosticForTesting =
                        "identity-changed-after-prewarm stored=\(String(describing: self.responsiveAudioBindingIdentity)) current=\(String(describing: self.responsiveAudioBindingIdentityForCurrentRoute())) expected=\(identity)"
#endif
                    return
                }
                guard let coordinator = self.chapterCoordinator,
                      let latestPlan = try coordinator
                        .responsiveAudioRestorationPlan(
                            state: self.committedState
                        ), latestPlan.program.id == identity.programID,
                      latestPlan.program.scope == identity.programScope,
                      self.responsiveAudioBindingIdentityForCurrentRoute()
                        == identity else {
                    throw JourneyChapterRuntimeError.routeAuthorityChanged
                }
                let latestRestoration = JourneyRestoration(
                    state: self.committedState,
                    replayedEventCount: 0,
                    lastSequence: self.lastCommittedSequence
                )
                let recoveredPlan = try await self
                    .responsiveAudioPlanApplyingCrashCursorIfAvailable(
                        latestPlan,
                        identity: identity
                    )
                guard self.responsiveAudioBindingIdentity == identity,
                      self.responsiveAudioBindingIdentityForCurrentRoute() == identity else {
                    return
                }
                try self.bindResponsiveAudio(
                    plan: recoveredPlan,
                    restoration: latestRestoration,
                    resolver: resolver
                )
#if DEBUG
                self.responsiveAudioBindingDiagnosticForTesting = "bound"
#endif
            } catch is CancellationError {
#if DEBUG
                self?.responsiveAudioBindingDiagnosticForTesting = "cancelled"
#endif
                return
            } catch {
                guard let self,
                      self.responsiveAudioBindingIdentity == identity,
                      self.responsiveAudioBindingIdentityForCurrentRoute() == identity else {
#if DEBUG
                    self?.responsiveAudioBindingDiagnosticForTesting =
                        "identity-changed-after-error: \(String(reflecting: error))"
#endif
                    return
                }
#if DEBUG
                self.responsiveAudioBindingDiagnosticForTesting =
                    "binding-error: \(String(reflecting: error))"
#endif
                self.responsiveAudioController?.stopWithoutPersisting()
                self.responsiveAudioController = nil
#if DEBUG
                self.responsiveAudioFailure =
                    "\(failureMessage) \(String(reflecting: error))"
#else
                self.responsiveAudioFailure = failureMessage
#endif
                if let assetFailureAuthority {
                    _ = await self.reportChapterAssetFailure(assetFailureAuthority)
                }
            }
        }
        responsiveAudioBindingTask = task
    }

    /// Physically ends the old controller generation in the current main-
    /// actor turn. A replacement binding waits for the cancelled start and
    /// its exact crash-cursor writer to retire before installing a controller.
    private func beginResponsiveAudioControllerReplacement()
        -> Task<Void, Never>? {
        responsiveAudioLifecycleToken = UUID()
        let supersededStartTask = responsiveAudioPlaybackStartTask
        let supersededStartID = responsiveAudioPlaybackStartID
        supersededStartTask?.cancel()

        responsiveAudioCursorPump.stop()
        let retiringCursorSession = responsiveAudioCursorSession
        responsiveAudioCursorSession = nil
        responsiveAudioCursorDurableSnapshot = nil

        responsiveAudioController?.stopWithoutPersisting()
        responsiveAudioController = nil

        guard supersededStartTask != nil || retiringCursorSession != nil else {
            return nil
        }
        let cursorStore = responsiveAudioCursorStore
        return Task { @MainActor [weak self] in
            if let supersededStartTask {
                _ = await supersededStartTask.value
            }
            if let self,
               self.responsiveAudioPlaybackStartID == supersededStartID {
                self.responsiveAudioPlaybackStartID = nil
                self.responsiveAudioPlaybackStartLifecycleToken = nil
                self.responsiveAudioPlaybackStartAuthorization = nil
                self.responsiveAudioPlaybackStartTask = nil
            }
            if let retiringCursorSession, let cursorStore {
                await cursorStore.retire(retiringCursorSession)
            }
        }
    }

    private func responsiveAudioPlanApplyingCrashCursorIfAvailable(
        _ plan: ResponsiveAudioRestorationPlan,
        identity: ResponsiveAudioBindingIdentity
    ) async throws -> ResponsiveAudioRestorationPlan {
        guard let store = responsiveAudioCursorStore,
              let durableSnapshot = plan.snapshot,
              let timeline = plan.timelines.first(where: {
                  $0.id == durableSnapshot.timelineID
              }), committedState.activeChapter?.responsiveAudioSessionIsActive == true else {
            return plan
        }
        let authority = try ResponsiveAudioCursorAuthority.make(
            durableState: committedState,
            contentRevision: identity.contentRevision ?? 0,
            program: plan.program,
            timeline: timeline
        )
        guard let recovered = try await store.recover(authority: authority) else {
            return plan
        }
        return ResponsiveAudioRestorationPlan(
            program: plan.program,
            timelines: plan.timelines,
            snapshot: recovered,
            interaction: plan.interaction,
            requiresCompletionAuthority: plan.requiresCompletionAuthority
        )
    }

    private func awaitResponsiveAudioBindingIfNeeded() async {
        while responsiveAudioController == nil {
            if Task.isCancelled { return }
            guard let requestedIdentity = responsiveAudioBindingIdentityForCurrentRoute(),
                  let chapterCoordinator else { return }
            if responsiveAudioBindingTask == nil
                || responsiveAudioBindingIdentity != requestedIdentity {
                configureResponsiveAudioIfAvailable(coordinator: chapterCoordinator)
            }
            guard let task = responsiveAudioBindingTask else { return }
            let attemptedIdentity = responsiveAudioBindingIdentity
            await task.value
            if responsiveAudioController != nil || Task.isCancelled { return }
            guard let currentIdentity = responsiveAudioBindingIdentityForCurrentRoute()
            else { return }
            // Durable Journey writes do not change authored material identity.
            // A stable identity with no controller is a real authored-audio
            // failure and remains fail-closed.
            if attemptedIdentity == currentIdentity,
               responsiveAudioBindingTask == nil {
                return
            }
        }
    }

    private func responsiveAudioBindingIdentityForCurrentRoute()
        -> ResponsiveAudioBindingIdentity? {
        guard case let .chapter(chapterID) = committedState.route,
              let session = committedState.activeChapter,
              session.chapterID == chapterID,
              let beatID = chapterCursor?.beat.id,
              let program = chapterCursor?.responsiveAudioProgram,
              program.scope.chapterID == chapterID,
              program.scope.beatID == beatID else {
            return nil
        }
        let authority = currentChapterRuntimeAuthority()
        return ResponsiveAudioBindingIdentity(
            contentRevision: authority?.revision,
            chapterID: chapterID,
            packageID: session.packageID,
            beatID: beatID,
            manifestDigest: authority?.verifiedPackage(for: session.packageID)?
                .manifest.manifestDigest,
            programID: program.id,
            programScope: program.scope
        )
    }

    private func cancelPendingResponsiveAudioBinding() {
        responsiveAudioBindingTask?.cancel()
        responsiveAudioBindingTask = nil
        responsiveAudioBindingIdentity = nil
    }

    private func enqueueResponsiveAudioFollowUpIfNeeded(
        after commit: DurableJourneyCommit
    ) {
        guard let responsiveAudioController,
              case .interact = commit.event.action else {
            return
        }
        do {
            let action: JourneyAction?
            if commit.effects.contains(where: { effect in
                if case .worldChanged = effect { return true }
                return false
            }) {
                action = try responsiveAudioController.accept(durableCommit: commit)
            } else if let authority = try DurableInteractionAudioCausalStageReceipt.make(
                from: commit
            ) {
                action = try responsiveAudioController.selectCausalStage(authority)
            } else {
                action = nil
            }
            guard let action else { return }
            pendingActions.insert(
                PendingAction(
                    action: action,
                    prologuePreviewRevision: prologuePreviewRevision
                ),
                at: 0
            )
        } catch {
            responsiveAudioController.stopWithoutPersisting()
            self.responsiveAudioController = nil
            responsiveAudioFailure = "The historical action was saved; its sound transition was withheld."
        }
    }

    private func presentCausalEffects(_ effects: [JourneyEffect]) {
        for effect in effects {
            guard case let .haptic(semantic) = effect else { continue }
            causalHapticTransport.play(semantic)
        }
    }

    private func publish(_ durableState: JourneyState, after pending: PendingAction) {
        guard let preview = prologuePreview,
              preview.revision > pending.prologuePreviewRevision,
              durableState.route == .prologue,
              durableState.prologue.phase != .awakened else {
            state = durableState
            if prologuePreview?.revision ?? 0 <= pending.prologuePreviewRevision
                || durableState.route != .prologue
                || durableState.prologue.phase == .awakened {
                prologuePreview = nil
            }
            return
        }

        // A new drag may begin while the preceding write is in flight. Rebase
        // that visual-only progress over the newly durable state rather than
        // making the thumb jump backwards.
        state = prologuePreview(
            in: durableState,
            progress: preview.progress
        )
    }

    private func prologuePreview(
        in visibleState: JourneyState,
        progress: Double
    ) -> JourneyState {
        var candidate = visibleState
        previewReducer.reduce(
            state: &candidate,
            action: .updatePrologueTrace(progress)
        )

        // Copy back only the visual prologue field. Preview code cannot alter
        // the route, cumulative world, completion or replay bookkeeping.
        var preview = visibleState
        preview.prologue = candidate.prologue
        return preview
    }

    private func failPersistence(message: String) {
        SynchronousPersistenceFailureGate.close(
            physicalStop: { [self] in
                failClosedResponsiveOutputsWithoutPersistence()
            },
            lockPersistence: { [self] in
                persistenceIsLocked = true
            }
        )
        failPendingWriteCompletions(
            JourneyChapterRuntimeError.persistenceUnavailable
        )
        pendingActions.removeAll()
        releaseResponsiveAudioSceneMutationWaiters()
        prologuePreview = nil
        state = committedState
        persistenceFailure = message
    }

    private func failPersistenceAfterCommit(message: String) {
        SynchronousPersistenceFailureGate.close(
            physicalStop: { [self] in
                failClosedResponsiveOutputsWithoutPersistence()
            },
            lockPersistence: { [self] in
                persistenceIsLocked = true
            }
        )
        failPendingWriteCompletions(
            JourneyChapterRuntimeError.persistenceUnavailable
        )
        pendingActions.removeAll()
        releaseResponsiveAudioSceneMutationWaiters()
        prologuePreview = nil
        state = committedState
        persistenceFailure = message
    }

    private func failClosedResponsiveOutputsWithoutPersistence() {
        responsiveAudioLifecycleToken = UUID()
        responsiveAudioPlaybackStartTask?.cancel()
        stopOutgoingResponsiveAudioTailImmediately()
        causalHapticTransport.quiesceForSuspension()
        responsiveAudioCursorPump.stop()
        let retiringSession = responsiveAudioCursorSession
        responsiveAudioCursorSession = nil
        responsiveAudioCursorDurableSnapshot = nil
        if let retiringSession, let responsiveAudioCursorStore {
            Task {
                await responsiveAudioCursorStore.retire(retiringSession)
            }
        }
        cancelPendingResponsiveAudioBinding()
        responsiveAudioController?.stopWithoutPersisting()
        responsiveAudioController = nil
        cancelResponsiveAudioAutomaticBoundary()
        preQuiescedSuspensionAction = nil
        preQuiescedSuspensionFailed = false
        pendingResponsiveAudioPhaseIntent = nil
    }

    private static func nowEpochMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
    }
}

@MainActor
extension JourneyModel: ChapterRuntimeHapticBridging {
    func play(_ semantic: HapticSemantic) {
        causalHapticTransport.play(semantic)
    }
}

@MainActor
extension JourneyModel: ChapterRuntimeAudioConsequenceBridging {
    func responsiveAudioSnapshot(
        after commit: DurableJourneyCommit,
        causalStageAuthority: DurableInteractionAudioCausalStageReceipt
    ) async throws -> ResponsiveAudioProgramSnapshot? {
        guard causalStageAuthority.sequence == commit.sequence,
              let responsiveAudioController else {
            throw JourneyChapterRuntimeError.authoredAudioUnavailable
        }
        do {
            guard let action = try responsiveAudioController.selectCausalStage(
                causalStageAuthority
            ) else {
                return nil
            }
            guard case let .setResponsiveAudioSnapshot(snapshot) = action else {
                throw JourneyChapterRuntimeError.authoredAudioUnavailable
            }
            responsiveAudioFailure = nil
            return snapshot
        } catch {
            responsiveAudioController.stopWithoutPersisting()
            self.responsiveAudioController = nil
            responsiveAudioFailure =
                "The historical action was saved; its sound transition was withheld."
            throw error
        }
    }

    func responsiveAudioSnapshot(
        after commit: DurableJourneyCommit,
        authority: DurableInteractionAudioCompletionReceipt
    ) async throws -> ResponsiveAudioProgramSnapshot? {
        guard authority.sequence == commit.sequence,
              let responsiveAudioController else {
            throw JourneyChapterRuntimeError.authoredAudioUnavailable
        }
        do {
            let action = try responsiveAudioController.accept(durableCommit: commit)
            guard case let .setResponsiveAudioSnapshot(snapshot) = action else {
                throw JourneyChapterRuntimeError.authoredAudioUnavailable
            }
            responsiveAudioFailure = nil
            return snapshot
        } catch {
            responsiveAudioController.stopWithoutPersisting()
            self.responsiveAudioController = nil
            responsiveAudioFailure =
                "The historical consequence was saved; its sound transition was withheld."
            throw error
        }
    }
}
