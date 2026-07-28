import ChapterRuntime
import ContentKit
import DramaticAudio
import Foundation
import JourneyAccessibility
import JourneyContent
import JourneyDomain
import JourneyPersistence
import ProgressStore
import QualityInstrumentation
import SceneRuntime
import SwiftUI
import UIKit

/// Authority-bound crash cursor for the finite main beat
/// timeline. Its 125 ms cadence and native render-clock feed run outside
/// MainActor, so rapid direct manipulation cannot push recovery beyond the
/// 250 ms review limit.
private actor PrimaryAudioCursorStore {
    typealias Failure = @Sendable (UUID) -> Void

    private static let cadenceNanoseconds: UInt64 = 125_000_000

    private let component: AuthoredAudioComponent
    private let directoryURL: URL
    private let fileURL: URL
    private let legacyFileURL: URL
    private var activeToken: UUID?
    private var cadenceTask: Task<Void, Never>?
    private var newestCursorSample: Int64 = 0

    init(
        directoryURL: URL,
        component: AuthoredAudioComponent
    ) {
        self.component = component
        self.directoryURL = directoryURL
        fileURL = directoryURL.appendingPathComponent(
            "cursor-\(component.rawValue)-v2.json",
            isDirectory: false
        )
        legacyFileURL = directoryURL.appendingPathComponent(
            "cursor.json",
            isDirectory: false
        )
    }

    func recover(
        authority: PrimaryAudioAuthority,
        maximumCursorSample: Int64
    ) -> Int64? {
        guard maximumCursorSample >= 0 else { return nil }
        for candidateURL in [fileURL, legacyFileURL] {
            guard let bytes = try? Data(contentsOf: candidateURL),
                  let recovery = AuthoredAudioCursorCheckpointCodec.recover(
                      from: bytes,
                      expectedAuthority: authority,
                      component: component,
                      maximumCursorSample: maximumCursorSample
                  ) else { continue }
            return recovery.cursorSample
        }
        return nil
    }

    func reset(
        authority: PrimaryAudioAuthority,
        maximumCursorSample: Int64
    ) {
        for candidateURL in [fileURL, legacyFileURL] {
            guard let bytes = try? Data(contentsOf: candidateURL),
                  AuthoredAudioCursorCheckpointCodec.recover(
                      from: bytes,
                      expectedAuthority: authority,
                      component: component,
                      maximumCursorSample: maximumCursorSample
                  ) != nil else { continue }
            try? FileManager.default.removeItem(at: candidateURL)
        }
        newestCursorSample = 0
    }

    func save(
        authority: PrimaryAudioAuthority,
        cursorSample: Int64,
        maximumCursorSample: Int64
    ) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try persist(
            authority: authority,
            cursorSample: cursorSample,
            maximumCursorSample: maximumCursorSample
        )
        newestCursorSample = cursorSample
    }

    func start(
        token: UUID,
        authority: PrimaryAudioAuthority,
        maximumCursorSample: Int64,
        feed: NativeAudioCursorFeed,
        gateToken: NativeAudioDurabilityGate.EpochToken,
        maximumUndurableGraphSampleCount: Int64,
        failure: @escaping Failure
    ) throws {
        cadenceTask?.cancel()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        activeToken = token
        newestCursorSample = recover(
            authority: authority,
            maximumCursorSample: maximumCursorSample
        ) ?? 0
        cadenceTask = Task { [weak self] in
            await self?.run(
                token: token,
                authority: authority,
                maximumCursorSample: maximumCursorSample,
                feed: feed,
                gateToken: gateToken,
                maximumUndurableGraphSampleCount:
                    maximumUndurableGraphSampleCount,
                failure: failure
            )
        }
    }

    func finish(
        token: UUID,
        authority: PrimaryAudioAuthority,
        cursorSample: Int64,
        maximumCursorSample: Int64
    ) {
        guard activeToken == token else { return }
        cadenceTask?.cancel()
        cadenceTask = nil
        defer { activeToken = nil }
        guard cursorSample >= newestCursorSample,
              cursorSample <= maximumCursorSample else { return }
        try? persist(
            authority: authority,
            cursorSample: cursorSample,
            maximumCursorSample: maximumCursorSample
        )
    }

    func cancel(token: UUID) {
        guard activeToken == token else { return }
        cadenceTask?.cancel()
        cadenceTask = nil
        activeToken = nil
    }

    private func run(
        token: UUID,
        authority: PrimaryAudioAuthority,
        maximumCursorSample: Int64,
        feed: NativeAudioCursorFeed,
        gateToken: NativeAudioDurabilityGate.EpochToken,
        maximumUndurableGraphSampleCount: Int64,
        failure: @escaping Failure
    ) async {
        do {
            while !Task.isCancelled {
                guard activeToken == token else { return }
                let capture = try feed.capture()
                guard capture.snapshot.timelineID == authority.timelineID,
                      capture.snapshot.cursorSample >= 0,
                      capture.snapshot.cursorSample <= maximumCursorSample,
                      capture.snapshot.cursorSample >= newestCursorSample,
                      gateToken.claimCapture(
                          atRenderedGraphSample:
                              capture.renderedGraphSample
                      ) else {
                    throw NativeAudioCursorFeedError.unavailable
                }
                try persist(
                    authority: authority,
                    cursorSample: capture.snapshot.cursorSample,
                    maximumCursorSample: maximumCursorSample
                )
                newestCursorSample = capture.snapshot.cursorSample
                let cutoff = capture.renderedGraphSample
                    .addingReportingOverflow(
                        maximumUndurableGraphSampleCount
                    )
                guard !cutoff.overflow,
                      gateToken.authorizeAudio(
                          throughRenderedGraphSample: cutoff.partialValue
                      ) else {
                    throw NativeAudioCursorFeedError.unavailable
                }
                if !capture.snapshot.isPlaying
                    || capture.snapshot.cursorSample == maximumCursorSample {
                    cadenceTask = nil
                    activeToken = nil
                    return
                }
                try await Task.sleep(
                    nanoseconds: Self.cadenceNanoseconds
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard activeToken == token else { return }
            cadenceTask = nil
            activeToken = nil
            failure(token)
        }
    }

    private func persist(
        authority: PrimaryAudioAuthority,
        cursorSample: Int64,
        maximumCursorSample: Int64
    ) throws {
        let data = try AuthoredAudioCursorCheckpointCodec.encode(
            authority: authority,
            component: component,
            cursorSample: cursorSample,
            maximumCursorSample: maximumCursorSample
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
#if DEBUG
private extension Notification.Name {
    static let pressureHoldLifecycleProbeStart = Notification.Name(
        "com.thelongwest.journey.pressure-hold-lifecycle-probe-start"
    )
}
#endif

private enum ContinuousInputProtection: Equatable {
    case ordinary
    case traceAnchor(Int)
    case pressureStabilityBoundary(isStable: Bool)
    case transformStage(Int)
    case previewUnavailable
    case terminal

    var isProtected: Bool {
        self != .ordinary
    }

    var tracePriority: TraceDeferredSamplePriority {
        guard case let .traceAnchor(index) = self else {
            return TraceDeferredSamplePriority()
        }
        return TraceDeferredSamplePriority(protectedAnchorIndex: index)
    }

#if DEBUG
    var diagnosticLabel: String {
        switch self {
        case .ordinary:
            "ordinary"
        case let .traceAnchor(index):
            "trace-\(index)"
        case let .pressureStabilityBoundary(isStable):
            isStable ? "pressure-enter" : "pressure-exit"
        case let .transformStage(index):
            "transform-\(index)"
        case .previewUnavailable:
            "preview-fallback"
        case .terminal:
            "terminal"
        }
    }
#endif
}

private enum ContinuousInputPreviewOutcome {
    case notApplicable
    case classified(ContinuousInputProtection)
    case ignored
    case routeFailed
}

/// Ordinary historical motion may cross the journal at most every 200 ms.
/// Protected causal contacts and preview-fallback samples bypass the cadence
/// but reset its next window, so a boundary never permits an immediate
/// redundant ordinary write.
private struct ContinuousInputJournalRatePolicy {
    static let ordinaryIntervalNanoseconds: UInt64 = 200_000_000

    private var lastSubmissionNanoseconds: UInt64?

    mutating func admits(
        _ protection: ContinuousInputProtection,
        capturedAtMonotonicNanoseconds capturedAt: UInt64
    ) -> Bool {
        if protection.isProtected {
            lastSubmissionNanoseconds = capturedAt
            return true
        }
        guard let lastSubmissionNanoseconds else {
            self.lastSubmissionNanoseconds = capturedAt
            return true
        }
        guard capturedAt >= lastSubmissionNanoseconds,
              capturedAt - lastSubmissionNanoseconds
                >= Self.ordinaryIntervalNanoseconds else {
            return false
        }
        self.lastSubmissionNanoseconds = capturedAt
        return true
    }

    mutating func recordProtectedFlush(
        capturedAtMonotonicNanoseconds capturedAt: UInt64
    ) {
        lastSubmissionNanoseconds = capturedAt
    }

    mutating func reset() {
        lastSubmissionNanoseconds = nil
    }
}

/// Sub-pixel jitter can cross a Pressure stability edge many times. One
/// unstable exit per 250 ms hold epoch invalidates continuous hold time
/// immediately; later absolute samples use the ordinary 5 Hz path and the
/// latest is drained before the next hold event.
private struct PressureContinuousInputProtectionPolicy {
    private var protectedUnstableExitInCurrentHoldEpoch = false

    mutating func protection(
        isStable: Bool
    ) -> ContinuousInputProtection {
        guard !isStable else { return .ordinary }
        guard !protectedUnstableExitInCurrentHoldEpoch else {
            return .ordinary
        }
        protectedUnstableExitInCurrentHoldEpoch = true
        return .pressureStabilityBoundary(isStable: false)
    }

    mutating func beginNextHoldEpoch() {
        protectedUnstableExitInCurrentHoldEpoch = false
    }

    /// Returns and consumes the invalidation raised by the first unstable
    /// sample in this 250 ms epoch. A consumed epoch must not also advance
    /// hold time: stability has not been continuous for the full interval.
    mutating func consumeInvalidatedHoldEpoch() -> Bool {
        guard protectedUnstableExitInCurrentHoldEpoch else { return false }
        protectedUnstableExitInCurrentHoldEpoch = false
        return true
    }

    mutating func reset() {
        protectedUnstableExitInCurrentHoldEpoch = false
    }
}

enum ProductionChapterRouteFailureKind: Equatable {
    case authorityUnavailable
    case rendererUnavailable
    case signedSceneAsset
    case signedAudioAsset
}

struct ProductionChapterRouteFailure: Equatable {
    let kind: ProductionChapterRouteFailureKind
    let assetAuthority: PackageAssetFailureAuthority?

    var message: String {
        switch kind {
        case .signedSceneAsset, .signedAudioAsset:
            if assetAuthority?.packageID == LaunchContent.essentialPackageID {
                return "The included chapter files failed their integrity check. Update or reinstall the app before opening this road."
            }
            return "This downloaded chapter failed its integrity check and cannot be opened."
        case .rendererUnavailable:
            return "This iPhone could not prepare the authored scene."
        case .authorityUnavailable:
            return "The verified scene files could not be opened."
        }
    }

    var canReportPackageAssetFailure: Bool {
        assetAuthority != nil
            && (kind == .signedSceneAsset || kind == .signedAudioAsset)
    }

    var canOfferRedownload: Bool {
        canReportPackageAssetFailure
            && assetAuthority?.packageID
                != LaunchContent.essentialPackageID
    }
}

@MainActor
final class ProductionChapterRouteSession: ObservableObject {
    @Published private(set) var presentation: ChapterScenePresentation?
    @Published private(set) var failure: ProductionChapterRouteFailure?
    @Published private(set) var inputIsPending = false
    @Published private(set) var lifecyclePresentationRefreshIsPending = false
    @Published private(set) var audioPlaybackState =
        ChapterAudioPlaybackState.inactive
    @Published private(set) var soundIsEnabledForPresentation = true
    @Published private(set) var desiredResponsiveAudioPhase:
        ResponsiveInteractionAudioPhase?
#if DEBUG
    @Published private(set) var failureDiagnosticForTesting = ""
    @Published private(set) var audioPlaybackStateDiagnosticForTesting =
        "initial:inactive"
    @Published private(set) var chapterInputAdmissionDiagnosticForTesting =
        "none"
    @Published private(set) var chapterInputResolutionDiagnosticForTesting =
        "none"
    @Published private(set) var responsiveAudioBindingReadyForTesting =
        "not-ready"
    @Published private(set) var primaryAudioDiagnosticForTesting = "unbound"
    private var responsiveAudioActivationDiagnosticForTesting = "none"
    private var traceTouchSampleCountForTesting = 0
    private var firstTraceViewportPointForTesting: SceneFramePoint?
    @Published private(set) var inputFIFOProbeDiagnosticForTesting =
        "disabled"
    @Published private(set) var continuousInputEnergyDiagnosticForTesting =
        "not-run"
    @Published private(set) var pressureHoldAttemptCountForTesting = 0
    private var pressureJitterEnergyProbeIsRunning = false
    private var pressureJitterEnergyProbeDiagnosticPrefix = ""
    private var pressureJitterEnergyProbeInitialLogicalTime: Int64 = 0
    private var pressureJitterEnergyProbeAcceptedCount = 0
    private var pressureJitterEnergyProbePerformedCount = 0
    private var pressureJitterEnergyProbeCompletedCount = 0
    private var pressureJitterEnergyProbeProtectedExitCount = 0
    private var pressureJitterEnergyProbeMaximumReservations = 0
    private var pressureJitterEnergyProbeOutsideNeutralized = false
    private var pressureJitterEnergyProbeDroppedHoldCount = 0
    private var pressureJitterEnergyProbeAcceptedHoldCount = 0
    @Published private(set) var inputFIFOProbeIsHoldingForTesting = false
    private var inputFIFOProbeCycleForTesting = 0
    private var inputFIFOProbePhaseForTesting = "idle"
    private var inputFIFOProbeDidHoldForTesting = false
    private var inputFIFOProbeHoldContinuationForTesting:
        CheckedContinuation<Void, Never>?
    private var inputFIFOProbeAcceptedForTesting: [Int] = []
    private var inputFIFOProbePerformedForTesting: [Int] = []
    private var inputFIFOProbeCompletedForTesting: [Int] = []
    private var inputFIFOProbeCoalescedForTesting: [Int] = []
    private var inputFIFOProbeDroppedForTesting: [Int] = []
    private var inputFIFOProbeDeferredOrdinalsForTesting: [Int] = []
    private var inputFIFOProbeTrackedOrdinalForTesting: Int?
    private var inputFIFOProbeActivePerformsForTesting = 0
    private var inputFIFOProbeMaximumActivePerformsForTesting = 0
    private var inputFIFOProbeMaximumReservationsForTesting = 0
    private var inputFIFOProbeUntrackedPerformsForTesting: [Int] = []
#endif

    let compositor: SceneMetalCompositor
    private let performanceRecorder: (any PerformanceRecording)?

    private enum PendingInput {
        case touch(SceneTouchIntent)
        case semantic(elementID: String, action: AccessibilityActionSpec)

        var isContinuousTransportSample: Bool {
            guard case let .touch(intent) = self else { return false }
            return switch intent {
            case .trace, .allocateContact, .allocateCarry,
                 .assembleContact, .assembleLift, .assembleCarry,
                 .assembleSlotApproach, .adjustTarget:
                true
            case .allocateDrop, .allocateReturn, .activateTarget,
                 .assembleDrop, .assembleCancel,
                 .holdPressure, .commitAllocation:
                false
            }
        }

        var performanceSource: PerformanceActionSource {
            switch self {
            case .touch: .touch
            case .semantic: .voiceOver
            }
        }

        var performanceActionName: String {
            switch self {
            case let .touch(intent): intent.performanceActionName
            case let .semantic(_, action): "semantic-\(action.kind.rawValue)"
            }
        }

#if DEBUG
        var isPressureEnergyProbeInput: Bool {
            guard case let .touch(intent) = self else { return false }
            return switch intent {
            case .adjustTarget, .holdPressure:
                true
            default:
                false
            }
        }

        var isPressureHoldInput: Bool {
            guard case .touch(.holdPressure) = self else { return false }
            return true
        }
#endif
    }

    private var alphaSampler = SceneImageAlphaMaskSampler()
    private weak var model: JourneyModel?
    private var runtime: VerifiedChapterSceneRuntime?
    private var identity: ChapterRuntimeRouteIdentity?
    private var routeGeneration: UInt64 = 0
    private var activationRequestFence = ChapterRouteActivationRequestFence()
    private var inputTask: Task<Void, Never>?
    private var lifecyclePresentationRefreshTask: Task<Void, Never>?
    private var lifecyclePresentationRefreshRequestID: UUID?
    private var ephemeralResponseCleanupTask: Task<Void, Never>?
    private var ephemeralResponseCleanupRequestID: UUID?
    private let ephemeralResponseTiming: ChapterSceneEphemeralResponseTiming
    private let ephemeralResponseSleeper:
        @Sendable (UInt64) async throws -> Void
    private struct PendingPhysicalPauseRefresh: Equatable {
        let event: ResponsiveAudioPhysicalPauseEvent
        let modelIdentifier: ObjectIdentifier
        let identity: ChapterRuntimeRouteIdentity
        /// Presentation-only phase captured from this live route session. It is
        /// never written to JourneyState and therefore cannot leak into a cold
        /// restore, whose projection remains the authored waiting phase.
        let responsiveAudioPhase: ResponsiveInteractionAudioPhase?
    }
    private var pendingPhysicalPauseRefresh: PendingPhysicalPauseRefresh?
    private struct InstrumentedInput {
        let input: PendingInput
        let actionToken: PerformanceActionToken?
        let reservation: ChapterRuntimeInputReservationGate.Token
        let reservationOwner: JourneyModel
        let identity: ChapterRuntimeRouteIdentity
        let protection: ContinuousInputProtection

        var tracePriority: TraceDeferredSamplePriority {
            protection.tracePriority
        }
    }

    private struct DeferredContinuousInput {
        let input: PendingInput
        let owner: JourneyModel
        let identity: ChapterRuntimeRouteIdentity
        let protection: ContinuousInputProtection
        let capturedAtMonotonicNanoseconds: UInt64

        var tracePriority: TraceDeferredSamplePriority {
            protection.tracePriority
        }
    }

    private var pendingInputs: [InstrumentedInput] = []
    private var currentInput: InstrumentedInput?
    private var deferredContinuousInputs: [DeferredContinuousInput] = []
    private var rateLimitedContinuousInput: DeferredContinuousInput?
    private var latestContinuousJournalInput: DeferredContinuousInput?
    private var continuousInputRatePolicy = ContinuousInputJournalRatePolicy()
    private var pressureInputProtectionPolicy =
        PressureContinuousInputProtectionPolicy()
    private let maximumAcceptedContinuousInputs = 8
    private let maximumDeferredContinuousInputs =
        TraceInteractionSpec.maximumAnchorCount + 1
    private var inputReservationOwners: [
        ChapterRuntimeInputReservationGate.Token: JourneyModel
    ] = [:]
    private var routeReplacementIsPending = false
    private var deactivationIsPending = false
    private var instrumentedActionTokens: Set<PerformanceActionToken> = []
    private var reportedAssetFailureAuthority: PackageAssetFailureAuthority?
    private struct ResponsiveAudioRouteKey: Equatable {
        let routeIdentity: ChapterRuntimeRouteIdentity
        let playbackLease: ResponsiveAudioPlaybackStartLease
    }

    private struct PrimaryAudioRouteKey: Equatable {
        let routeIdentity: ChapterRuntimeRouteIdentity
        let timelineID: AudioTimelineID
    }

    private final class PrimaryAudioComponentPlayback {
        let component: AuthoredAudioComponent
        let timeline: AudioTimeline
        let transport: NativeTimelineTransport
        let cursorStore: PrimaryAudioCursorStore
        let cursorToken: UUID
        var cursorStoreIsActive = false

        init(
            component: AuthoredAudioComponent,
            timeline: AudioTimeline,
            transport: NativeTimelineTransport,
            cursorStore: PrimaryAudioCursorStore,
            cursorToken: UUID
        ) {
            self.component = component
            self.timeline = timeline
            self.transport = transport
            self.cursorStore = cursorStore
            self.cursorToken = cursorToken
        }
    }

    private final class PrimaryAudioPlayback {
        let routeKey: PrimaryAudioRouteKey
        let binding: PrimaryAudioBinding
        let usesVerifiedRoleSeparation: Bool
        var components: [
            AuthoredAudioComponent: PrimaryAudioComponentPlayback
        ]

        init(
            routeKey: PrimaryAudioRouteKey,
            binding: PrimaryAudioBinding,
            usesVerifiedRoleSeparation: Bool,
            components: [
                AuthoredAudioComponent: PrimaryAudioComponentPlayback
            ]
        ) {
            self.routeKey = routeKey
            self.binding = binding
            self.usesVerifiedRoleSeparation = usesVerifiedRoleSeparation
            self.components = components
        }
    }

    private enum PrimaryAudioStartOutcome: Equatable {
        case started
        case noEligibleComponent
        case failed
    }

    private var responsiveAudioRouteKey: ResponsiveAudioRouteKey?
    private var primaryAudioRouteKey: PrimaryAudioRouteKey?
    private var primaryAudioPlayback: PrimaryAudioPlayback?
    /// The latest active or resisted response seen in this live view session.
    /// A restored controller deliberately has no transient feedback, so this
    /// value is consulted only by the matching physical-pause refresh below.
    private var lastMeaningfulResponsiveAudioPhaseForLifecycle:
        ResponsiveInteractionAudioPhase?
    private var responsiveAudioPhaseCapturedAtSceneExit:
        ResponsiveInteractionAudioPhase?
    private var responsiveAudioPhaseCaptureIdentity:
        ChapterRuntimeRouteIdentity?
    private var responsiveAudioPlaybackTask: Task<Void, Never>?
    private var responsiveAudioPolicy = ChapterResponsiveAudioSessionPolicy()
    private var responsiveAudioAuthorizedStartEpoch:
        ResponsiveAudioPlaybackStartEpoch?
    private var suppressesNarrationForCurrentPlayback = false
    /// VoiceOver may hold the speaking component while an independently
    /// verified non-speaking bed keeps running. Ending VoiceOver never consumes
    /// this latch; only the fixed, deliberate Resume action may do that.
    private var narrationRequiresExplicitVoiceOverResume = false

    var hasAuthoredAudio: Bool {
        responsiveAudioRouteKey != nil || primaryAudioRouteKey != nil
    }

    init(
        performanceRecorder: (any PerformanceRecording)? =
            PerformanceCaptureRuntime.shared.recorder,
        ephemeralResponseTiming: ChapterSceneEphemeralResponseTiming =
            .authored,
        ephemeralResponseSleeper: @escaping @Sendable (UInt64) async throws
            -> Void = { nanoseconds in
                try await Task.sleep(nanoseconds: nanoseconds)
            }
    ) {
        self.performanceRecorder = performanceRecorder
        self.ephemeralResponseTiming = ephemeralResponseTiming
        self.ephemeralResponseSleeper = ephemeralResponseSleeper
        compositor = SceneMetalCompositor(performanceRecorder: performanceRecorder)
    }

#if DEBUG
    var inputFIFOProbeIsEnabledForTesting: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-chapter-input-fifo"
        )
    }

    var continuousInputEnergyProbeIsEnabledForTesting: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-continuous-input-energy"
        )
    }

    var pressureHoldLifecycleProbeIsEnabledForTesting: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-pressure-hold-lifecycle"
        )
    }

    func runContinuousInputEnergyProbeForTesting(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard continuousInputEnergyProbeIsEnabledForTesting,
              admitsInput(for: expectedIdentity),
              !inputIsPending,
              inputTask == nil,
              pendingInputs.isEmpty,
              deferredContinuousInputs.isEmpty,
              let runtime,
              let initialPresentation = presentation,
              let targetRegion = initialPresentation.framePlan
                .interactionHitRegions.first,
              !targetRegion.viewportPath.isEmpty else {
            continuousInputEnergyDiagnosticForTesting =
                "result=fail;reason=route-not-ready"
            return
        }

        func ordinaryAdmissionCount() -> Int {
            var policy = ContinuousInputJournalRatePolicy()
            return (0 ..< 120).reduce(into: 0) { count, observation in
                let capturedAt = UInt64(observation) * 1_000_000_000 / 120
                if policy.admits(
                    .ordinary,
                    capturedAtMonotonicNanoseconds: capturedAt
                ) {
                    count += 1
                }
            }
        }

        let point = SceneFramePoint(
            x: targetRegion.viewportPath.reduce(0) { $0 + $1.x }
                / Double(targetRegion.viewportPath.count),
            y: targetRegion.viewportPath.reduce(0) { $0 + $1.y }
                / Double(targetRegion.viewportPath.count)
        )
        let probeIntent: SceneTouchIntent
        switch initialPresentation.cursor.beat.interaction?.grammar {
        case .trace?:
            probeIntent = .trace(viewportPoint: point)
        case .pressure?, .transform?:
            probeIntent = .adjustTarget(
                viewportPoint: point,
                amount: 0.35
            )
        default:
            continuousInputEnergyDiagnosticForTesting =
                "result=fail;reason=unsupported-grammar"
            return
        }

        let durablePresentationBeforeProbe = runtime.controller.presentation
        var visualCount = 0
        var visualMaximumNanoseconds: UInt64 = 0
        for _ in 0 ..< 120 {
            // Keep every timing sample on the same committed reducer state.
            // This makes the probe independent of whether the chosen point is
            // also an authored threshold, while still exercising the real
            // controller-preview and compositor-update path.
            runtime.controller.resetContinuousTouchPreview()
            let started = DispatchTime.now().uptimeNanoseconds
            if case .classified = previewContinuousJournalInput(
                .touch(probeIntent),
                publishesVisualResponse: true
            ) {
                visualCount += 1
            }
            let finished = DispatchTime.now().uptimeNanoseconds
            visualMaximumNanoseconds = max(
                visualMaximumNanoseconds,
                finished >= started ? finished - started : 0
            )
        }
        runtime.controller.resetContinuousTouchPreview()
        _ = compositor.update(initialPresentation.framePlan)
        presentation = initialPresentation

        let authoredSemantics: [ContinuousInputProtection] = [
            .traceAnchor(0),
            .pressureStabilityBoundary(isStable: false),
            .transformStage(0),
            .transformStage(1),
            .previewUnavailable,
            .terminal,
        ]
        var semanticPolicy = ContinuousInputJournalRatePolicy()
        _ = semanticPolicy.admits(
            .ordinary,
            capturedAtMonotonicNanoseconds: 0
        )
        let admittedSemantics = authoredSemantics.enumerated().compactMap {
            offset, semantic in
            semanticPolicy.admits(
                semantic,
                capturedAtMonotonicNanoseconds: UInt64(offset + 1)
            ) ? semantic.diagnosticLabel : nil
        }
        let holdBypassesCadence = !PendingInput.touch(
            .holdPressure(elapsedMillis: 250)
        ).isContinuousTransportSample
        let voiceOverBypassesCadence = !PendingInput.semantic(
            elementID: "semantic",
            action: AccessibilityActionSpec(
                kind: .activate,
                label: LocalizedStringSpec(
                    id: "semantic-action",
                    launchEnglish: "Continue"
                ),
                token: .traceNext
            )
        ).isContinuousTransportSample
        let ordinaryCounts = [
            ordinaryAdmissionCount(),
            ordinaryAdmissionCount(),
            ordinaryAdmissionCount(),
        ]
        let semanticOrder = admittedSemantics.joined(separator: ",")
        let expectedOrder = [
            "trace-0",
            "pressure-exit",
            "transform-0",
            "transform-1",
            "preview-fallback",
            "terminal",
        ].joined(separator: ",")
        let visualMaximumMillis = Double(visualMaximumNanoseconds)
            / 1_000_000
        let previewKeptDurableAuthority =
            runtime.controller.presentation == durablePresentationBeforeProbe
        let passed = ordinaryCounts == [5, 5, 5]
            && semanticOrder == expectedOrder
            && holdBypassesCadence
            && voiceOverBypassesCadence
            && visualCount == 120
            && visualMaximumNanoseconds <= 50_000_000
            && previewKeptDurableAuthority
        let diagnosticPrefix =
            "visual=\(visualCount);visualMaxMillis="
            + String(format: "%.3f", visualMaximumMillis) + ";"
            + "visualUnder50="
            + "\(visualMaximumNanoseconds <= 50_000_000 ? 1 : 0);"
            + "authorityUnchanged=\(previewKeptDurableAuthority ? 1 : 0);"
            + "ordinary=trace:\(ordinaryCounts[0]),"
            + "pressure:\(ordinaryCounts[1]),transform:\(ordinaryCounts[2]);"
            + "protected=\(semanticOrder);"
            + "discrete=pressure-hold:\(holdBypassesCadence ? 1 : 0),"
            + "voice-over:\(voiceOverBypassesCadence ? 1 : 0);"
        if passed,
           case .pressure? = initialPresentation.cursor.beat.interaction?.grammar {
            if startPressureJitterEnergyProbeForTesting(
                initialPresentation: initialPresentation,
                expectedIdentity: expectedIdentity,
                diagnosticPrefix: diagnosticPrefix
            ) {
                return
            }
            continuousInputEnergyDiagnosticForTesting = diagnosticPrefix
                + "realPressure=setup-failed;result=fail"
            return
        }
        continuousInputEnergyDiagnosticForTesting = diagnosticPrefix
            + "result=\(passed ? "pass" : "fail")"
    }

    private func startPressureJitterEnergyProbeForTesting(
        initialPresentation: ChapterScenePresentation,
        expectedIdentity: ChapterRuntimeRouteIdentity,
        diagnosticPrefix: String
    ) -> Bool {
        guard let runtime,
              case let .pressure(configuration)? = initialPresentation.cursor
                .beat.interaction?.grammar,
              case let .pressure(progress)? = initialPresentation.journeyState
                .activeChapter?.interaction?.progress,
              case let .pressure(visual)? = initialPresentation.cursor.scene
                .interactionVisualBinding,
              let force = configuration.forces.first(where: {
                  $0.userControllable && $0.direction != 0
              }),
              let forceVisual = visual.forces.first(where: {
                  $0.forceID == force.id && $0.interactionTargetID != nil
              }),
              let targetID = forceVisual.interactionTargetID,
              let target = initialPresentation.framePlan.interactionHitRegions
                .first(where: { $0.interactionTargetID == targetID }),
              !target.viewportPath.isEmpty else {
            return false
        }
        let fixedNetPressure = configuration.forces
            .filter { $0.id != force.id }
            .reduce(0.0) { partial, authoredForce in
                let magnitude = progress.values.first(where: {
                    $0.forceID == authoredForce.id
                })?.magnitude ?? authoredForce.initialMagnitude
                return partial + authoredForce.direction * magnitude
            }
        let stableNetPressure = (
            configuration.stableRange.lowerBound
                + configuration.stableRange.upperBound
        ) * 0.5
        let stableMagnitude = (
            stableNetPressure - fixedNetPressure
        ) / force.direction
        guard (0 ... 1).contains(stableMagnitude),
              configuration.stableRange.contains(
                  fixedNetPressure + force.direction * stableMagnitude
              ),
              let unstableMagnitude = [0.0, 1.0].first(where: {
                  !configuration.stableRange.contains(
                      fixedNetPressure + force.direction * $0
                  )
              }) else {
            return false
        }
        let point = SceneFramePoint(
            x: target.viewportPath.reduce(0) { $0 + $1.x }
                / Double(target.viewportPath.count),
            y: target.viewportPath.reduce(0) { $0 + $1.y }
                / Double(target.viewportPath.count)
        )
        let outsidePoint = SceneFramePoint(x: -1, y: -1)

        resetContinuousInputSampling()
        pressureJitterEnergyProbeIsRunning = true
        pressureJitterEnergyProbeDiagnosticPrefix = diagnosticPrefix
        pressureJitterEnergyProbeInitialLogicalTime = runtime.controller
            .presentation.journeyState.lastLogicalTimeMillis
        pressureJitterEnergyProbeAcceptedCount = 0
        pressureJitterEnergyProbePerformedCount = 0
        pressureJitterEnergyProbeCompletedCount = 0
        pressureJitterEnergyProbeProtectedExitCount = 0
        pressureJitterEnergyProbeMaximumReservations = 0
        pressureJitterEnergyProbeOutsideNeutralized = false
        pressureJitterEnergyProbeDroppedHoldCount = 0
        pressureJitterEnergyProbeAcceptedHoldCount = 0

        // Invalid geometry must never replace a valid coalesced absolute
        // sample. The final inside sample is held by the 200 ms cadence; the
        // second outside observation clears only display response, then
        // finger-up drains that still-valid sample.
        submitTouch(
            .adjustTarget(
                viewportPoint: outsidePoint,
                amount: stableMagnitude
            ),
            expectedIdentity: expectedIdentity
        )
        submitTouch(
            .adjustTarget(
                viewportPoint: point,
                amount: stableMagnitude
            ),
            expectedIdentity: expectedIdentity
        )
        submitTouch(
            .adjustTarget(
                viewportPoint: point,
                amount: unstableMagnitude
            ),
            expectedIdentity: expectedIdentity
        )
        submitTouch(
            .adjustTarget(
                viewportPoint: point,
                amount: stableMagnitude
            ),
            expectedIdentity: expectedIdentity
        )
        submitTouch(
            .adjustTarget(
                viewportPoint: outsidePoint,
                amount: unstableMagnitude
            ),
            expectedIdentity: expectedIdentity
        )
        let retainedValidSample: Bool
        if case let .touch(.adjustTarget(_, amount))? =
            rateLimitedContinuousInput?.input {
            retainedValidSample = amount == stableMagnitude
        } else {
            retainedValidSample = false
        }
        let neutral = presentation
        pressureJitterEnergyProbeOutsideNeutralized = retainedValidSample
            && neutral?.journeyState == initialPresentation.journeyState
            && neutral?.framePlan.interactionResponse == nil
            && neutral?.metalPreparationPlan.textureRequests.map(\.key)
                == initialPresentation.metalPreparationPlan.textureRequests
                    .map(\.key)
        endContinuousTouchGesture(expectedIdentity: expectedIdentity)

        // Sixty stable/unstable crossings in one hold epoch may protect only
        // its first unstable exit. That invalidates this full 250 ms interval,
        // so the hold tick is dropped after its latest absolute sample drains.
        // The following sample pair belongs to the next epoch, whose first
        // unstable exit must again cross immediately.
        for index in 0 ..< 120 {
            submitTouch(
                .adjustTarget(
                    viewportPoint: point,
                    amount: index.isMultiple(of: 2)
                        ? stableMagnitude : unstableMagnitude
                ),
                expectedIdentity: expectedIdentity
            )
        }
        submitTouch(
            .holdPressure(elapsedMillis: 250),
            expectedIdentity: expectedIdentity
        )
        submitTouch(
            .adjustTarget(
                viewportPoint: point,
                amount: stableMagnitude
            ),
            expectedIdentity: expectedIdentity
        )
        submitTouch(
            .adjustTarget(
                viewportPoint: point,
                amount: unstableMagnitude
            ),
            expectedIdentity: expectedIdentity
        )
        endContinuousTouchGesture(expectedIdentity: expectedIdentity)

        continuousInputEnergyDiagnosticForTesting = diagnosticPrefix
            + "realPressure=running"
        return true
    }

    private func recordPressureJitterProtectionForTesting(
        _ protection: ContinuousInputProtection
    ) {
        guard pressureJitterEnergyProbeIsRunning,
              protection
                == .pressureStabilityBoundary(isStable: false) else {
            return
        }
        pressureJitterEnergyProbeProtectedExitCount += 1
    }

    private func recordPressureJitterAcceptedInputForTesting(
        _ input: PendingInput
    ) {
        guard pressureJitterEnergyProbeIsRunning,
              input.isPressureEnergyProbeInput else { return }
        pressureJitterEnergyProbeAcceptedCount += 1
        if input.isPressureHoldInput {
            pressureJitterEnergyProbeAcceptedHoldCount += 1
        }
        pressureJitterEnergyProbeMaximumReservations = max(
            pressureJitterEnergyProbeMaximumReservations,
            inputReservationOwners.count
        )
    }

    private func recordPressureJitterDroppedInvalidatedHoldForTesting() {
        guard pressureJitterEnergyProbeIsRunning else { return }
        pressureJitterEnergyProbeDroppedHoldCount += 1
    }

    private func recordPressureJitterPerformedInputForTesting(
        _ input: PendingInput
    ) {
        guard pressureJitterEnergyProbeIsRunning,
              input.isPressureEnergyProbeInput else { return }
        pressureJitterEnergyProbePerformedCount += 1
    }

    private func recordPressureJitterCompletedInputForTesting(
        _ input: PendingInput
    ) {
        guard pressureJitterEnergyProbeIsRunning,
              input.isPressureEnergyProbeInput else { return }
        pressureJitterEnergyProbeCompletedCount += 1
    }

    private func finalizePressureJitterEnergyProbeIfNeededForTesting() {
        guard pressureJitterEnergyProbeIsRunning,
              inputTask == nil,
              pendingInputs.isEmpty,
              deferredContinuousInputs.isEmpty,
              rateLimitedContinuousInput == nil,
              let finalState = runtime?.controller.presentation.journeyState
        else { return }
        let journalDelta = finalState.lastLogicalTimeMillis
            - pressureJitterEnergyProbeInitialLogicalTime
        let stableMillis: Int64?
        if case let .pressure(progress)? = finalState.activeChapter?
            .interaction?.progress {
            stableMillis = progress.stableMillis
        } else {
            stableMillis = nil
        }
        let accepted = pressureJitterEnergyProbeAcceptedCount
        let queueStayedBounded = accepted == 6
            && pressureJitterEnergyProbeMaximumReservations <= 8
        let passed = pressureJitterEnergyProbeOutsideNeutralized
            && pressureJitterEnergyProbeProtectedExitCount == 3
            && pressureJitterEnergyProbeDroppedHoldCount == 1
            && pressureJitterEnergyProbeAcceptedHoldCount == 0
            && queueStayedBounded
            && pressureJitterEnergyProbePerformedCount == accepted
            && pressureJitterEnergyProbeCompletedCount == accepted
            && journalDelta == Int64(accepted)
            && stableMillis == 0
        continuousInputEnergyDiagnosticForTesting =
            pressureJitterEnergyProbeDiagnosticPrefix
            + "realPressure=raw:127,protectedExits:"
            + "\(pressureJitterEnergyProbeProtectedExitCount),"
            + "accepted:\(accepted),"
            + "performed:\(pressureJitterEnergyProbePerformedCount),"
            + "completed:\(pressureJitterEnergyProbeCompletedCount),"
            + "journal:\(journalDelta),"
            + "maxReservations:"
            + "\(pressureJitterEnergyProbeMaximumReservations),"
            + "outsideNeutral:\(pressureJitterEnergyProbeOutsideNeutralized ? 1 : 0),"
            + "invalidatedHoldDropped:"
            + "\(pressureJitterEnergyProbeDroppedHoldCount),"
            + "holdCredit:"
            + "\(pressureJitterEnergyProbeAcceptedHoldCount * 250),"
            + "stableMillis:\(stableMillis.map(String.init) ?? "none");"
            + "result=\(passed ? "pass" : "fail")"
        pressureJitterEnergyProbeIsRunning = false
    }

    private var inputFIFOProbeUsesRightAngleTraceForTesting: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-chapter-input-fifo-right-angle-trace"
        )
    }

    func startInputFIFOProbeForTesting(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard inputFIFOProbeIsEnabledForTesting,
              !inputIsPending,
              inputTask == nil,
              inputReservationOwners.isEmpty,
              admitsInput(for: expectedIdentity) else {
            inputFIFOProbePhaseForTesting = "start-rejected"
            publishInputFIFOProbeDiagnosticForTesting()
            return
        }
        inputFIFOProbeCycleForTesting += 1
        inputFIFOProbePhaseForTesting = "submitting"
        inputFIFOProbeDidHoldForTesting = false
        inputFIFOProbeIsHoldingForTesting = false
        inputFIFOProbeHoldContinuationForTesting = nil
        inputFIFOProbeAcceptedForTesting = []
        inputFIFOProbePerformedForTesting = []
        inputFIFOProbeCompletedForTesting = []
        inputFIFOProbeCoalescedForTesting = []
        inputFIFOProbeDroppedForTesting = []
        inputFIFOProbeDeferredOrdinalsForTesting = []
        inputFIFOProbeTrackedOrdinalForTesting = nil
        inputFIFOProbeActivePerformsForTesting = 0
        inputFIFOProbeMaximumActivePerformsForTesting = 0
        inputFIFOProbeMaximumReservationsForTesting = 0
        inputFIFOProbeUntrackedPerformsForTesting = []

        // The standard ten-sample probe retains newest-sample coalescing. The
        // right-angle variant adds two ordered authored contacts and a latest
        // ordinary sample after the eight accepted reservations are full.
        // Negative coordinates keep controller execution outside every real
        // hit region; the debug priority seam below supplies only the genuine
        // 90-degree authored Trace classification under test.
        let finalOrdinal = inputFIFOProbeUsesRightAngleTraceForTesting
            ? 11 : 10
        for ordinal in 1 ... finalOrdinal {
            submitTouch(
                .trace(
                    viewportPoint: inputFIFOProbeViewportPointForTesting(
                        ordinal: ordinal
                    )
                ),
                expectedIdentity: expectedIdentity
            )
        }
        inputFIFOProbePhaseForTesting = "saturated"
        publishInputFIFOProbeDiagnosticForTesting()
    }

    func releaseInputFIFOProbeForTesting() {
        guard inputFIFOProbeIsEnabledForTesting,
              inputFIFOProbeIsHoldingForTesting else { return }
        inputFIFOProbeIsHoldingForTesting = false
        inputFIFOProbePhaseForTesting = "draining"
        publishInputFIFOProbeDiagnosticForTesting()
        inputFIFOProbeHoldContinuationForTesting?.resume()
        inputFIFOProbeHoldContinuationForTesting = nil
    }

    func cancelRouteDuringInputFIFOProbeForTesting() {
        guard inputFIFOProbeIsEnabledForTesting,
              inputFIFOProbeIsHoldingForTesting else { return }
        inputFIFOProbePhaseForTesting = "cancelling"
        deactivate()
        publishInputFIFOProbeDiagnosticForTesting()
    }
#endif

    func activate(
        model: JourneyModel,
        identity: ChapterRuntimeRouteIdentity
    ) async {
        guard model.chapterRuntimeRouteIdentity(
            for: identity.chapterID,
            viewportCropID: identity.viewportCropID,
            reduceMotion: identity.reduceMotion
        ) == identity else {
            return
        }
        soundIsEnabledForPresentation =
            model.experiencePreferences.soundEnabled
        capturePendingPhysicalPauseRefreshIfNeeded(
            model: model,
            identity: identity
        )
        let activationRequest = activationRequestFence.begin()
        if self.model === model,
           self.identity == identity,
           runtime != nil,
           presentation != nil,
           failure == nil {
            // A transient disappear can request deferred teardown while an
            // accepted FIFO input still owns this same route. Reactivation is
            // authoritative: annul that teardown before returning through the
            // ready fast path, or finishInput would destroy the live session.
            deactivationIsPending = false
            routeReplacementIsPending = false
            if pendingPhysicalPauseRefresh != nil {
                requireExplicitResponsiveAudioResume()
                startPendingPhysicalPauseRefreshIfReady()
            }
            return
        }
        routeReplacementIsPending = true
        deactivationIsPending = false
        defer {
            if activationRequestFence.isCurrent(activationRequest) {
                routeReplacementIsPending = false
            }
        }
        // An admitted controller transition ignores submitter cancellation
        // after it owns the transition slot. Drain the finite accepted FIFO
        // through compositor publication before replacing route authority.
        while !Task.isCancelled, let admittedInputTask = inputTask {
            await admittedInputTask.value
        }
        guard !Task.isCancelled,
              activationRequestFence.isCurrent(activationRequest) else {
            return
        }
        if let playbackTask = persistenceOnlyReplacementPlaybackTask(
            model: model,
            identity: identity
        ) {
            await playbackTask.value
            guard !Task.isCancelled,
                  model.chapterRuntimeRouteIdentity(
                      for: identity.chapterID,
                      viewportCropID: identity.viewportCropID,
                      reduceMotion: identity.reduceMotion
                  ) == identity,
                  activationRequestFence.isCurrent(activationRequest) else {
                return
            }
        }
        guard !Task.isCancelled,
              activationRequestFence.isCurrent(activationRequest),
              model.chapterRuntimeRouteIdentity(
                for: identity.chapterID,
                viewportCropID: identity.viewportCropID,
                reduceMotion: identity.reduceMotion
              ) == identity else {
            return
        }
        let preservesAuthorizedAudioEpoch = self.identity?.chapterID
            == identity.chapterID
            && audioPlaybackState == .playing
#if DEBUG
        let previousIdentity = self.identity
#endif
        cancelOutstandingPerformanceActions()
        cancelEphemeralResponseCleanup()
        pausePrimaryAudioForBoundary()
        routeGeneration &+= 1
        let generation = routeGeneration
#if DEBUG
        let identityChange: String
        if let previousIdentity {
            if previousIdentity == identity {
                identityChange = "same-identity"
            } else if previousIdentity.persistenceAuthority
                        != identity.persistenceAuthority {
                identityChange = "persistence-authority"
            } else if previousIdentity.contentRevision != identity.contentRevision {
                identityChange = "content-revision"
            } else if previousIdentity.packageManifestDigest
                        != identity.packageManifestDigest {
                identityChange = "package-manifest"
            } else if previousIdentity.beatID != identity.beatID {
                identityChange = "beat"
            } else if previousIdentity.viewportCropID != identity.viewportCropID {
                identityChange = "viewport-crop"
            } else if previousIdentity.reduceMotion != identity.reduceMotion {
                identityChange = "reduce-motion"
            } else {
                identityChange = "other"
            }
        } else {
            identityChange = "no-previous-identity"
        }
        responsiveAudioActivationDiagnosticForTesting =
            "generation-\(generation)-\(identityChange)"
        responsiveAudioBindingReadyForTesting =
            "preparing;generation=\(generation);change=\(identityChange)"
        traceTouchSampleCountForTesting = 0
        firstTraceViewportPointForTesting = nil
        chapterInputResolutionDiagnosticForTesting = "none"
#endif
        lifecyclePresentationRefreshTask?.cancel()
        lifecyclePresentationRefreshTask = nil
        lifecyclePresentationRefreshRequestID = nil
        lifecyclePresentationRefreshIsPending = false
        responsiveAudioPlaybackTask?.cancel()
        responsiveAudioPlaybackTask = nil
        if !preservesAuthorizedAudioEpoch {
            responsiveAudioAuthorizedStartEpoch = nil
            suppressesNarrationForCurrentPlayback = false
            narrationRequiresExplicitVoiceOverResume = false
        }
        _ = responsiveAudioPolicy.bind(
            chapterID: identity.chapterID,
            hasResponsiveAudio: false
        )
        audioPlaybackState = responsiveAudioPolicy.playbackState
#if DEBUG
        audioPlaybackStateDiagnosticForTesting =
            "activate-\(generation)-bind-silent:\(audioPlaybackState.rawValue)"
#endif
        responsiveAudioRouteKey = nil
        primaryAudioRouteKey = nil
        desiredResponsiveAudioPhase = nil
        lastMeaningfulResponsiveAudioPhaseForLifecycle = nil
        if pendingPhysicalPauseRefresh?.identity != identity {
            responsiveAudioPhaseCapturedAtSceneExit = nil
            responsiveAudioPhaseCaptureIdentity = nil
        }
        inputTask = nil
        pendingInputs.removeAll(keepingCapacity: false)
        currentInput = nil
        deferredContinuousInputs.removeAll(keepingCapacity: false)
        resetContinuousInputSampling()
        inputIsPending = false
        alphaSampler.purge()
        alphaSampler = SceneImageAlphaMaskSampler()
        let routeAlphaSampler = alphaSampler
        compositor.purgeTextureCache()
        presentation = nil
        failure = nil
#if DEBUG
        failureDiagnosticForTesting = ""
#endif
        runtime = nil
        reportedAssetFailureAuthority = nil
        self.identity = identity
        self.model = model
        if pendingPhysicalPauseRefresh != nil {
            requireExplicitResponsiveAudioResume()
        }

        if case .notConfigured = compositor.state {
            _ = compositor.configure()
        }
        guard case .readyForScene = compositor.state else {
            failure = ProductionChapterRouteFailure(
                kind: .rendererUnavailable,
                assetAuthority: nil
            )
            return
        }
        do {
            while true {
            let runtime = try await model.makeChapterSceneRuntime(identity: identity)
            let pauseEventAtRuntimeConstruction = model
                .pendingChapterRuntimePhysicalPauseEvent(for: identity)
            guard !Task.isCancelled,
                  routeGeneration == generation,
                  self.identity == identity else {
                return
            }
            let initialPresentation = runtime.controller.presentation
            guard try await prepareForInput(
                initialPresentation,
                alphaSampler: routeAlphaSampler,
                runtime: runtime,
                generation: generation,
                expectedIdentity: identity
            ) else {
                return
            }
            guard !Task.isCancelled,
                  routeGeneration == generation,
                  self.identity == identity,
                  model.pendingChapterRuntimePhysicalPauseEvent(
                      for: identity
                  ) == pauseEventAtRuntimeConstruction else {
                if !Task.isCancelled,
                   routeGeneration == generation,
                   self.identity == identity {
                    compositor.purgeTextureCache()
                    continue
                }
                compositor.purgeTextureCache()
                return
            }
            capturePendingPhysicalPauseRefreshIfNeeded(
                model: model,
                identity: identity
            )
            self.runtime = runtime
            performanceRecorder?.bindPackage(
                packageID: runtime.packageID.rawValue,
                manifestSHA256: runtime.assetFailureAuthority.manifestDigest
            )
            compositor.markNextCommandBufferCompletionProxyAsRestored()
            presentation = initialPresentation
            routeReplacementIsPending = false
            adoptResponsiveAudioPresentation(
                initialPresentation,
                identity: identity
            )
            if pendingPhysicalPauseRefresh != nil {
                requireExplicitResponsiveAudioResume()
                startPendingPhysicalPauseRefreshIfReady()
            }
#if DEBUG
            publishInputReadinessForTesting(
                stage: "presentation",
                identity: identity,
                generation: generation
            )
#endif
            performanceRecorder?.recordFirstActionReady()
            break
            }
        } catch is CancellationError {
            return
        } catch let error as JourneyChapterRuntimeError
            where error == .routeAuthorityChanged {
            return
        } catch let error as JourneyChapterRuntimeError
            where error == .authoredAudioUnavailable {
            guard routeGeneration == generation, self.identity == identity else { return }
#if DEBUG
            failureDiagnosticForTesting = model.responsiveAudioFailure
                ?? "\(model.responsiveAudioBindingDiagnosticForTesting); \(String(reflecting: error))"
#endif
            publishFailure(
                ProductionChapterRouteFailure(
                    kind: .signedAudioAsset,
                    assetAuthority: model.chapterAssetFailureAuthority(for: identity)
                ),
                generation: generation,
                expectedIdentity: identity
            )
        } catch {
            guard routeGeneration == generation, self.identity == identity else { return }
#if DEBUG
            failureDiagnosticForTesting =
                await model.persistenceRestoreDiagnosticForTesting()
                    ?? String(reflecting: error)
#endif
            publishFailure(
                ProductionChapterRouteFailure(
                    kind: error is SceneAssetInventoryError
                        ? .signedSceneAsset : .authorityUnavailable,
                    assetAuthority: model.chapterAssetFailureAuthority(for: identity)
                ),
                generation: generation,
                expectedIdentity: identity
            )
        }
    }

    private func persistenceOnlyReplacementPlaybackTask(
        model: JourneyModel,
        identity nextIdentity: ChapterRuntimeRouteIdentity
    ) -> Task<Void, Never>? {
        guard self.model === model,
              let currentIdentity = identity,
              currentIdentity.persistenceAuthority
                != nextIdentity.persistenceAuthority,
              currentIdentity.viewportCropID == nextIdentity.viewportCropID,
              currentIdentity.reduceMotion == nextIdentity.reduceMotion,
              let currentKey = responsiveAudioRouteKey,
              currentKey.routeIdentity == currentIdentity,
              runtime != nil,
              failure == nil,
              audioPlaybackState == .starting,
              let nextProgram = model.chapterCursor?
                .responsiveAudioProgram,
              nextProgram.scope.chapterID == nextIdentity.chapterID,
              nextProgram.scope.beatID == nextIdentity.beatID,
              currentKey.playbackLease == ResponsiveAudioPlaybackStartLease(
                  chapterID: nextIdentity.chapterID,
                  packageID: nextIdentity.packageID,
                  packageManifestDigest:
                    nextIdentity.packageManifestDigest,
                  beatID: nextIdentity.beatID,
                  programID: nextProgram.id,
                  programScope: nextProgram.scope
              ) else {
            return nil
        }
        return responsiveAudioPlaybackTask
    }

    func deactivate() {
        activationRequestFence.invalidate()
        routeReplacementIsPending = true
        deactivationIsPending = true
#if DEBUG
        discardDeferredInputFIFOProbeForTesting()
#endif
        deferredContinuousInputs.removeAll(keepingCapacity: false)
        resetContinuousInputSampling()
        guard inputTask == nil else { return }
        finishDeactivation()
    }

    private func finishDeactivation() {
        guard deactivationIsPending else { return }
        deactivationIsPending = false
        cancelOutstandingPerformanceActions()
        cancelEphemeralResponseCleanup()
        pausePrimaryAudioForBoundary()
        routeGeneration &+= 1
        lifecyclePresentationRefreshTask?.cancel()
        lifecyclePresentationRefreshTask = nil
        lifecyclePresentationRefreshRequestID = nil
        lifecyclePresentationRefreshIsPending = false
        responsiveAudioPlaybackTask?.cancel()
        responsiveAudioPlaybackTask = nil
        responsiveAudioAuthorizedStartEpoch = nil
        inputTask = nil
        pendingInputs.removeAll(keepingCapacity: false)
        currentInput = nil
        deferredContinuousInputs.removeAll(keepingCapacity: false)
        resetContinuousInputSampling()
        inputIsPending = false
        pendingPhysicalPauseRefresh = nil
        clearRememberedResponsiveAudioLifecyclePhase()
        runtime = nil
        identity = nil
        model = nil
        presentation = nil
        failure = nil
#if DEBUG
        failureDiagnosticForTesting = ""
        chapterInputAdmissionDiagnosticForTesting = "none"
        chapterInputResolutionDiagnosticForTesting = "none"
        responsiveAudioBindingReadyForTesting = "not-ready"
        primaryAudioDiagnosticForTesting = "unbound"
        traceTouchSampleCountForTesting = 0
        firstTraceViewportPointForTesting = nil
#endif
        reportedAssetFailureAuthority = nil
        responsiveAudioPolicy.deactivate()
        responsiveAudioRouteKey = nil
        primaryAudioRouteKey = nil
        desiredResponsiveAudioPhase = nil
        suppressesNarrationForCurrentPlayback = false
        narrationRequiresExplicitVoiceOverResume = false
        audioPlaybackState = responsiveAudioPolicy.playbackState
#if DEBUG
        audioPlaybackStateDiagnosticForTesting =
            "deactivate:\(audioPlaybackState.rawValue)"
#endif
        alphaSampler.purge()
        alphaSampler = SceneImageAlphaMaskSampler()
        compositor.purgeTextureCache()
#if DEBUG
        if inputFIFOProbeIsEnabledForTesting,
           inputFIFOProbeCycleForTesting > 0 {
            inputFIFOProbePhaseForTesting = "cancelled"
            inputFIFOProbeTrackedOrdinalForTesting = nil
            publishInputFIFOProbeDiagnosticForTesting()
        }
#endif
    }

    func presentation(
        for expectedIdentity: ChapterRuntimeRouteIdentity
    ) -> ChapterScenePresentation? {
        guard ChapterPresentationAuthorityGate.admitsPresentation(
            expectedIdentity: expectedIdentity,
            sessionIdentity: identity,
            runtimeIsReady: runtime != nil
        ) else { return nil }
        return presentation
    }

    private func admitsInput(
        for expectedIdentity: ChapterRuntimeRouteIdentity
    ) -> Bool {
        guard !routeReplacementIsPending,
              !deactivationIsPending,
              !lifecyclePresentationRefreshIsPending,
              audioPlaybackState != .starting,
              let model,
              model.admitsChapterRuntimeInput(expectedIdentity) else {
            return false
        }
        return ChapterPresentationAuthorityGate.admitsInput(
            expectedIdentity: expectedIdentity,
            sessionIdentity: identity,
            runtimeIsReady: runtime != nil,
            presentationIsReady: presentation != nil
        )
    }

    func submitTouch(
        _ intent: SceneTouchIntent,
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
#if DEBUG
        if pressureHoldLifecycleProbeIsEnabledForTesting,
           case .holdPressure = intent {
            pressureHoldAttemptCountForTesting += 1
        }
#endif
        let isAdmitted = admitsInput(for: expectedIdentity)
#if DEBUG
        let intentDiagnostic = chapterTouchIntentDiagnosticForTesting(intent)
        chapterInputAdmissionDiagnosticForTesting =
            "touch-\(isAdmitted ? "admitted" : "rejected");"
            + (model?.chapterRuntimeInputAdmissionDiagnosticForTesting(
                expectedIdentity
            ) ?? "model=missing")
            + ";" + intentDiagnostic
#endif
        guard isAdmitted,
              let model else { return }
        let input = PendingInput.touch(intent)
#if DEBUG
        let bypassesJournalCadence =
            inputFIFOProbeOrdinalForTesting(input) != nil
#else
        let bypassesJournalCadence = false
#endif
        if !bypassesJournalCadence {
            let previewOutcome = previewContinuousJournalInput(
                input,
                publishesVisualResponse: true
            )
            switch previewOutcome {
            case let .classified(protection):
#if DEBUG
                recordPressureJitterProtectionForTesting(protection)
#endif
                let capturedAt = DispatchTime.now().uptimeNanoseconds
                let candidate = DeferredContinuousInput(
                    input: input,
                    owner: model,
                    identity: expectedIdentity,
                    protection: protection,
                    capturedAtMonotonicNanoseconds: capturedAt
                )
                latestContinuousJournalInput = candidate
                guard continuousInputRatePolicy.admits(
                    protection,
                    capturedAtMonotonicNanoseconds: capturedAt
                ) else {
                    replaceRateLimitedContinuousInput(with: candidate)
                    return
                }
                coalesceRateLimitedContinuousInput()
                submitContinuousInputCandidate(candidate)
                return
            case .ignored, .routeFailed:
                return
            case .notApplicable:
                break
            }
        }
        if input.isContinuousTransportSample,
           acceptedContinuousInputCount
                >= maximumAcceptedContinuousInputs {
            // This newest sample has not crossed model admission and owns no
            // durability promise. Keep a content-bounded sequence of authored
            // Trace contacts plus the newest ordinary movement sample while
            // the accepted FIFO is draining.
            let candidate = DeferredContinuousInput(
                input: input,
                owner: model,
                identity: expectedIdentity,
                protection: protection(
                    for: traceDeferredSamplePriority(for: input)
                ),
                capturedAtMonotonicNanoseconds:
                    DispatchTime.now().uptimeNanoseconds
            )
            deferContinuousInput(candidate)
            return
        }
        if !input.isContinuousTransportSample,
           !drainContinuousInputBeforeBoundary(
               expectedIdentity: expectedIdentity
           ) {
            return
        }
        if case .touch(.holdPressure) = input,
           pressureInputProtectionPolicy.consumeInvalidatedHoldEpoch() {
#if DEBUG
            recordPressureJitterDroppedInvalidatedHoldForTesting()
#endif
            return
        }
        let accepted = acceptInput(
            input,
            owner: model,
            identity: expectedIdentity,
            protection: input.isContinuousTransportSample
                ? protection(for: traceDeferredSamplePriority(for: input))
                : .terminal
        )
        if accepted, case .touch(.holdPressure) = input {
            pressureInputProtectionPolicy.beginNextHoldEpoch()
        }
    }

    func submitVoiceOver(
        elementID: String,
        authoredAction: AccessibilityActionSpec,
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard admitsInput(for: expectedIdentity), let model else { return }
        guard drainContinuousInputBeforeBoundary(
            expectedIdentity: expectedIdentity
        ) else { return }
        if authoredAction.token == .holdPressure,
           pressureInputProtectionPolicy.consumeInvalidatedHoldEpoch() {
#if DEBUG
            recordPressureJitterDroppedInvalidatedHoldForTesting()
#endif
            return
        }
        let accepted = acceptInput(
            .semantic(elementID: elementID, action: authoredAction),
            owner: model,
            identity: expectedIdentity,
            protection: .terminal
        )
        if accepted, authoredAction.token == .holdPressure {
            pressureInputProtectionPolicy.beginNextHoldEpoch()
        }
    }

    /// Finger-up turns the newest coalesced journal sample into an accepted
    /// FIFO reservation before the gesture state disappears.
    func endContinuousTouchGesture(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        _ = drainContinuousInputBeforeBoundary(
            expectedIdentity: expectedIdentity
        )
        latestContinuousJournalInput = nil
        pressureInputProtectionPolicy.reset()
        neutralizeContinuousTouchPreview()
    }

    /// `willResignActive` arrives before the root lifecycle gate closes. This
    /// synchronous call creates reservations for every bounded sample that
    /// must precede the model's suspension flush; the flush then waits for the
    /// existing reservation gate exactly as it does for ordinary accepted
    /// input.
    func drainContinuousInputBeforeLifecycle(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        _ = drainContinuousInputBeforeBoundary(
            expectedIdentity: expectedIdentity
        )
        latestContinuousJournalInput = nil
        pressureInputProtectionPolicy.reset()
        neutralizeContinuousTouchPreview()
        pausePrimaryAudioForBoundary()
        requireExplicitResponsiveAudioResume()
    }

    /// The finite main timeline records its sample-exact pause before the
    /// ordered beat transition enters Journey's queue. Responsive interaction
    /// audio remains owned by the model's existing ordered-exit transaction.
    func prepareForBeatExit(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard identity == expectedIdentity else { return }
        pausePrimaryAudioForBoundary()
    }

    /// The same explicit action serves touch and VoiceOver. Backgrounding
    /// converts existing consent to an explicit resume rather than starting
    /// sound on return.
    func requestSoundPlayback(
        expectedIdentity: ChapterRuntimeRouteIdentity,
        suppressesNarration: Bool
    ) {
        suppressesNarrationForCurrentPlayback = suppressesNarration
        if suppressesNarration,
           primaryAudioRouteKey != nil,
           model?.experiencePreferences.narrationEnabled == true {
            narrationRequiresExplicitVoiceOverResume = true
        }
        if resumeHeldPrimaryAudioComponent(
            expectedIdentity: expectedIdentity,
            suppressesNarration: suppressesNarration
        ) {
            return
        }
        if !suppressesNarration {
            // A deliberate Resume may also arrive after VoiceOver ended while
            // the component was still being prepared. Let that same action
            // authorize the pending start rather than requiring a second tap.
            narrationRequiresExplicitVoiceOverResume = false
        }
        let inputIsAdmitted = admitsInput(for: expectedIdentity)
        let hasProgram = responsiveAudioRouteKey != nil
        let hasPrimaryTimeline = primaryAudioRouteKey != nil
        guard inputIsAdmitted,
              !inputIsPending,
              hasProgram || hasPrimaryTimeline,
              audioPlaybackState != .starting,
              audioPlaybackState != .playing,
              let model,
              let attempt = responsiveAudioPolicy.requestPlayback() else {
#if DEBUG
            responsiveAudioBindingReadyForTesting =
                "blocked;stage=sound-control;generation=\(routeGeneration);"
                    + "admitted=\(inputIsAdmitted ? 1 : 0);"
                    + "input=\(inputIsPending ? 1 : 0);"
                    + "refresh=\(lifecyclePresentationRefreshIsPending ? 1 : 0);"
                    + "program=\(hasProgram ? 1 : 0);"
                    + "primary=\(hasPrimaryTimeline ? 1 : 0);"
                    + "routeKey=\(responsiveAudioRouteKey == nil ? 0 : 1);"
                    + "choice=\(audioPlaybackState.rawValue)"
#endif
            return
        }
        audioPlaybackState = responsiveAudioPolicy.playbackState
#if DEBUG
        audioPlaybackStateDiagnosticForTesting =
            "request-playback:\(audioPlaybackState.rawValue)"
#endif
        let startEpoch = model
            .responsiveAudioPlaybackStartEpochForCurrentLifecycle()
        if let routeKey = responsiveAudioRouteKey {
            startResponsiveAudioPlayback(
                attempt,
                routeKey: routeKey,
                startEpoch: startEpoch
            )
            return
        }
        if let primaryAudioRouteKey {
            startPrimaryAudioPlayback(
                attempt,
                routeKey: primaryAudioRouteKey,
                startEpoch: startEpoch
            )
        }
    }

    /// Deliberate Begin, Resume and Review actions mint one process-local
    /// grant. Cold restoration and lifecycle re-entry do not, so they cannot
    /// start authored sound by themselves.
    func startEntrySoundIfAuthorized(
        expectedIdentity: ChapterRuntimeRouteIdentity,
        voiceOverIsRunning: Bool
    ) {
        guard let model,
              model.consumeChapterAudioEntryGrant(for: expectedIdentity) else {
            return
        }
        guard model.experiencePreferences.soundEnabled,
              hasAuthoredAudio else { return }
        requestSoundPlayback(
            expectedIdentity: expectedIdentity,
            suppressesNarration: voiceOverIsRunning
        )
    }

    func turnSoundOff(expectedIdentity: ChapterRuntimeRouteIdentity) {
        guard identity == expectedIdentity else { return }
        soundIsEnabledForPresentation = false
        pausePrimaryAudioForBoundary()
        requireExplicitResponsiveAudioResume()
        model?.setSoundEnabled(false)
    }

    func turnSoundOn(
        expectedIdentity: ChapterRuntimeRouteIdentity,
        voiceOverIsRunning: Bool
    ) {
        guard identity == expectedIdentity else { return }
        soundIsEnabledForPresentation = true
        model?.setSoundEnabled(true)
        requestSoundPlayback(
            expectedIdentity: expectedIdentity,
            suppressesNarration: voiceOverIsRunning
        )
    }

    func pauseNarrationForVoiceOver(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard identity == expectedIdentity,
              audioPlaybackState == .playing
                || audioPlaybackState == .starting else { return }
        suppressesNarrationForCurrentPlayback = true
        narrationRequiresExplicitVoiceOverResume = primaryAudioRouteKey != nil
            && model?.experiencePreferences.narrationEnabled == true
        guard let playback = primaryAudioPlayback else { return }
        guard let component = AuthoredAudioPlaybackBoundaryPolicy
                .componentToPauseForVoiceOver(
                    available: Set(playback.components.keys),
                    usesVerifiedRoleSeparation:
                        playback.usesVerifiedRoleSeparation
                ),
              let narration = playback.components[component],
              narration.transport.state == .playing else { return }
        let snapshot: NativeTimelineTransportSnapshot
        do {
            snapshot = try narration.transport.pause()
        } catch {
            // If the exact component boundary cannot be proven, stop every
            // authored transport. Continuing would let narration drift.
            pausePrimaryAudioForBoundary()
            responsiveAudioPolicy.requireExplicitResume()
            audioPlaybackState = responsiveAudioPolicy.playbackState
            return
        }
        narration.cursorStoreIsActive = false
        let cursor = min(
            max(snapshot.cursorSample, 0),
            narration.timeline.authoredDurationSamples
        )
        Task {
            await narration.cursorStore.finish(
                token: narration.cursorToken,
                authority: playback.binding.authority,
                cursorSample: cursor,
                maximumCursorSample:
                    narration.timeline.authoredDurationSamples
            )
        }
        if let cueID = narrationCueID(
            in: playback.binding.timeline,
            at: cursor
        ) {
            model?.recordPrimaryAudioCursor(
                cueID: cueID,
                sampleOffset: cursor,
                isPlaying: false,
                expectedIdentity: expectedIdentity
            )
        }
        let nonSpeakingContinues = playback.components[.nonSpeaking]?
            .transport.state == .playing
            || responsiveAudioRouteKey != nil
        audioPlaybackState = nonSpeakingContinues
            ? .playing : .resumeRequired
    }

    func voiceOverDidStop(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard identity == expectedIdentity else { return }
        suppressesNarrationForCurrentPlayback = false
        guard narrationRequiresExplicitVoiceOverResume else { return }
        // The pending start will publish Resume after it has established the
        // held component. If preparation has already finished, expose that
        // deliberate action now even while the non-speaking bed remains live.
        guard responsiveAudioPlaybackTask == nil else { return }
        audioPlaybackState = .resumeRequired
    }

    func requireExplicitResponsiveAudioResume() {
        let primaryTransportIsRunning = primaryAudioPlayback?.components
            .values.contains(where: { $0.transport.state == .playing })
            == true
        guard audioPlaybackState == .playing
                || audioPlaybackState == .starting
                || primaryTransportIsRunning else { return }
        pausePrimaryAudioForBoundary()
        responsiveAudioPlaybackTask?.cancel()
        responsiveAudioPlaybackTask = nil
        responsiveAudioAuthorizedStartEpoch = nil
        responsiveAudioPolicy.requireExplicitResume()
        audioPlaybackState = responsiveAudioPolicy.playbackState
#if DEBUG
        audioPlaybackStateDiagnosticForTesting =
            "physical-pause-event:\(audioPlaybackState.rawValue)"
#endif
    }

    /// Closes scene input synchronously, then waits for the already-admitted
    /// input and the exact lifecycle pause commit before publishing a fresh
    /// presentation. The responsive-audio choice is not rebound, so an
    /// explicit resume requirement and a prior silence choice both survive.
    func handlePhysicalPause(
        _ pauseEvent: ResponsiveAudioPhysicalPauseEvent,
        model: JourneyModel,
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        cancelEphemeralResponseCleanup()
        guard model.pendingChapterRuntimePhysicalPauseEvent(
            for: expectedIdentity
        ) == pauseEvent else {
            if pendingPhysicalPauseRefresh?.modelIdentifier
                == ObjectIdentifier(model),
               pendingPhysicalPauseRefresh?.identity == expectedIdentity {
                pendingPhysicalPauseRefresh = nil
            }
            return
        }
        let capturedPhase = if responsiveAudioPhaseCaptureIdentity
            == expectedIdentity {
            responsiveAudioPhaseCapturedAtSceneExit
        } else {
            lastMeaningfulResponsiveAudioPhaseForLifecycle
        }
        let candidate = PendingPhysicalPauseRefresh(
            event: pauseEvent,
            modelIdentifier: ObjectIdentifier(model),
            identity: expectedIdentity,
            responsiveAudioPhase: capturedPhase
        )
        if let pendingPhysicalPauseRefresh {
            if pendingPhysicalPauseRefresh.modelIdentifier
                != ObjectIdentifier(model)
                || pendingPhysicalPauseRefresh.identity != expectedIdentity
                || pendingPhysicalPauseRefresh.event.generation
                    < pauseEvent.generation {
                self.pendingPhysicalPauseRefresh = candidate
            }
        } else {
            pendingPhysicalPauseRefresh = candidate
        }
        guard self.model === model, identity == expectedIdentity else { return }
        requireExplicitResponsiveAudioResume()
        startPendingPhysicalPauseRefreshIfReady()
    }

    /// Captures transient presentation state before the root lifecycle handler
    /// can rebuild the route. SwiftUI does not guarantee parent/child observer
    /// order, so an already-published matching event is upgraded in place too.
    func captureResponsiveAudioPhaseAtSceneExit() {
        guard let identity,
              let phase = lastMeaningfulResponsiveAudioPhaseForLifecycle else {
            responsiveAudioPhaseCapturedAtSceneExit = nil
            responsiveAudioPhaseCaptureIdentity = nil
            return
        }
        responsiveAudioPhaseCapturedAtSceneExit = phase
        responsiveAudioPhaseCaptureIdentity = identity
        guard let pendingPhysicalPauseRefresh,
              pendingPhysicalPauseRefresh.identity == identity,
              pendingPhysicalPauseRefresh.responsiveAudioPhase == nil else {
            return
        }
        self.pendingPhysicalPauseRefresh = PendingPhysicalPauseRefresh(
            event: pendingPhysicalPauseRefresh.event,
            modelIdentifier: pendingPhysicalPauseRefresh.modelIdentifier,
            identity: identity,
            responsiveAudioPhase: phase
        )
    }

    /// Silent playback has no active transport to publish an audio pause event.
    /// Reapply only the phase captured by this same live view when the scene
    /// returns; a new process or a different route has no such capture.
    func restoreResponsiveAudioPhaseAfterSceneActivation(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard identity == expectedIdentity,
              responsiveAudioPhaseCaptureIdentity == expectedIdentity,
              let capturedPhase = responsiveAudioPhaseCapturedAtSceneExit,
              presentation?.cursor.responsiveAudioProgram != nil,
              presentation?.journeyState.activeChapter?.interaction?.phase
                != .complete else {
            return
        }
        if pendingPhysicalPauseRefresh != nil
            || lifecyclePresentationRefreshIsPending {
            // The exact physical refresh publishes the capture after its
            // durability and compositor barriers instead.
            return
        }
        desiredResponsiveAudioPhase = capturedPhase
        lastMeaningfulResponsiveAudioPhaseForLifecycle = capturedPhase
        responsiveAudioPhaseCapturedAtSceneExit = nil
        responsiveAudioPhaseCaptureIdentity = nil
    }

    private func capturePendingPhysicalPauseRefreshIfNeeded(
        model: JourneyModel,
        identity: ChapterRuntimeRouteIdentity
    ) {
        let modelIdentifier = ObjectIdentifier(model)
        if let pendingPhysicalPauseRefresh,
           pendingPhysicalPauseRefresh.modelIdentifier != modelIdentifier
            || pendingPhysicalPauseRefresh.identity != identity {
            self.pendingPhysicalPauseRefresh = nil
        }
        if responsiveAudioPhaseCaptureIdentity != nil,
           responsiveAudioPhaseCaptureIdentity != identity {
            responsiveAudioPhaseCapturedAtSceneExit = nil
            responsiveAudioPhaseCaptureIdentity = nil
        }
        guard let event = model.pendingChapterRuntimePhysicalPauseEvent(
            for: identity
        ) else {
            pendingPhysicalPauseRefresh = nil
            return
        }
        // Preserve an exact event already captured by handlePhysicalPause.
        // Activation can reset the live-session latch while rebuilding the
        // route; replacing on equality would then lose the pre-pause phase.
        if pendingPhysicalPauseRefresh?.event == event {
            return
        }
        if pendingPhysicalPauseRefresh?.event.generation ?? 0
            < event.generation {
            pendingPhysicalPauseRefresh = PendingPhysicalPauseRefresh(
                event: event,
                modelIdentifier: modelIdentifier,
                identity: identity,
                responsiveAudioPhase:
                    lastMeaningfulResponsiveAudioPhaseForLifecycle
            )
        }
    }

    private func startPendingPhysicalPauseRefreshIfReady() {
        guard let pending = pendingPhysicalPauseRefresh,
              let model,
              pending.modelIdentifier == ObjectIdentifier(model),
              identity == pending.identity,
              let runtime,
              presentation != nil else {
            return
        }

        lifecyclePresentationRefreshTask?.cancel()
        lifecyclePresentationRefreshIsPending = true
        let requestID = UUID()
        lifecyclePresentationRefreshRequestID = requestID
        let generation = routeGeneration
#if DEBUG
        responsiveAudioBindingReadyForTesting =
            "refreshing;stage=physical-pause;generation=\(generation);"
                + "event=\(pending.event.generation);"
                + "input=\(inputTask == nil ? 0 : 1)"
        publishInputFIFOProbeDiagnosticForTesting()
#endif

        lifecyclePresentationRefreshTask = Task {
            @MainActor [weak self, weak model] in
            guard let self, let model else { return }
            defer {
                if self.lifecyclePresentationRefreshRequestID == requestID {
                    self.lifecyclePresentationRefreshTask = nil
                    self.lifecyclePresentationRefreshRequestID = nil
                    self.lifecyclePresentationRefreshIsPending = false
#if DEBUG
                    self.publishInputFIFOProbeDiagnosticForTesting()
#endif
                }
            }
            // Every queued input crossed the same user-input admission gate
            // before physical pause closed it. Drain that finite FIFO queue;
            // the suspension flush owns the matching model reservations until
            // each compositor publication has completed. Only then may the
            // full lifecycle restore publish over their pre-pause scenes.
            while !Task.isCancelled, let admittedInputTask = self.inputTask {
                await admittedInputTask.value
            }
            do {
                try Task.checkCancellation()
                guard self.lifecyclePresentationRefreshRequestID == requestID,
                      self.routeGeneration == generation,
                      self.identity == pending.identity,
                      self.runtime?.controller === runtime.controller,
                      model.pendingChapterRuntimePhysicalPauseEvent(
                          for: pending.identity
                      ) == pending.event else {
                    return
                }
                let restored = try await model
                    .refreshChapterScenePresentationAfterPhysicalPause(
                        pending.event,
                        runtime: runtime,
                        identity: pending.identity
                    )
                guard try await self.prepareForInput(
                    restored,
                    alphaSampler: self.alphaSampler,
                    runtime: runtime,
                    generation: generation,
                    expectedIdentity: pending.identity
                ) else { return }
                try Task.checkCancellation()
                guard self.lifecyclePresentationRefreshRequestID == requestID,
                      self.routeGeneration == generation,
                      self.identity == pending.identity,
                      self.runtime?.controller === runtime.controller,
                      model.pendingChapterRuntimePhysicalPauseEvent(
                          for: pending.identity
                      ) == pending.event else {
                    return
                }
                self.presentation = restored
                self.adoptResponsiveAudioPresentation(
                    restored,
                    identity: pending.identity,
                    sameProcessLifecyclePhase:
                        pending.responsiveAudioPhase
                        ?? (self.responsiveAudioPhaseCaptureIdentity
                            == pending.identity
                            ? self.responsiveAudioPhaseCapturedAtSceneExit
                            : nil)
                        ?? self
                            .lastMeaningfulResponsiveAudioPhaseForLifecycle
                )
                guard model.completeChapterRuntimePhysicalPauseRefresh(
                    pending.event,
                    identity: pending.identity
                ) else {
                    throw JourneyChapterRuntimeError.routeAuthorityChanged
                }
                if self.pendingPhysicalPauseRefresh == pending {
                    self.pendingPhysicalPauseRefresh = nil
                }
                self.responsiveAudioPhaseCapturedAtSceneExit = nil
                self.responsiveAudioPhaseCaptureIdentity = nil
#if DEBUG
                self.responsiveAudioBindingReadyForTesting =
                    "ready;stage=physical-pause;generation=\(generation);"
                        + "event=\(pending.event.generation);identity=exact"
#endif
            } catch is CancellationError {
                return
            } catch let error as JourneyChapterRuntimeError
                where error == .routeAuthorityChanged {
                return
            } catch {
                guard self.lifecyclePresentationRefreshRequestID == requestID,
                      self.routeGeneration == generation,
                      self.identity == pending.identity else { return }
#if DEBUG
                self.failureDiagnosticForTesting = String(reflecting: error)
#endif
                self.publishFailure(
                    ProductionChapterRouteFailure(
                        kind: .authorityUnavailable,
                        assetAuthority: nil
                    ),
                    generation: generation,
                    expectedIdentity: pending.identity
                )
            }
        }
    }

    private func narrationCueID(
        in timeline: AudioTimeline,
        at cursorSample: Int64
    ) -> AudioCueID? {
        let narration = timeline.events.filter { $0.role == .narration }
        return narration.last(where: { $0.startSample <= cursorSample })?
            .cueID ?? narration.first?.cueID
    }

    private func startPrimaryAudioComponent(
        routeKey: PrimaryAudioRouteKey,
        startEpoch: ResponsiveAudioPlaybackStartEpoch,
        model: JourneyModel,
        generation: UInt64,
        recordsJournalStart: Bool = true
    ) async -> PrimaryAudioStartOutcome {
        do {
            guard let binding = try model
                    .primaryAudioBinding(
                        for: routeKey.routeIdentity
                    ), binding.authority.timelineID == routeKey.timelineID,
                  !binding.narrationCueIDs.isEmpty else { return .failed }
            let paths = Array(Set(
                binding.timeline.events
                    .filter { $0.role != .silence }
                    .compactMap(\.assetPath)
            )).sorted()
            try await OfflineAudioAssetPrewarmer.prewarm(
                paths: paths,
                resolver: binding.resolver
            )
            try Task.checkCancellation()
            guard routeGeneration == generation,
                  primaryAudioRouteKey == routeKey,
                  identity == routeKey.routeIdentity,
                  startEpoch == model
                    .responsiveAudioPlaybackStartEpochForCurrentLifecycle(),
                  model.chapterRuntimeRouteIdentity(
                      for: routeKey.routeIdentity.chapterID,
                      viewportCropID: routeKey.routeIdentity.viewportCropID,
                      reduceMotion: routeKey.routeIdentity.reduceMotion
                  ) == routeKey.routeIdentity else { return .failed }

            let componentTimelines: [
                AuthoredAudioComponent: AudioTimeline
            ]
            let usesVerifiedRoleSeparation: Bool
            do {
                componentTimelines = try AuthoredAudioRoleSeparation(
                    validating: binding.timeline
                ).componentTimelines
                usesVerifiedRoleSeparation = true
            } catch {
                // An unprovable role partition must never mute narration while
                // allowing the rest of the same clock to run ahead. Keep the
                // signed whole mix and let VoiceOver pause that transport.
                componentTimelines = [.wholeMix: binding.timeline]
                usesVerifiedRoleSeparation = false
            }

            let componentOrder: [AuthoredAudioComponent] = [
                .nonSpeaking, .narration, .wholeMix,
            ]
            var playbackPreferences = model.experiencePreferences
            // Playback reaches this point only through a deliberate, admitted
            // sound action. Persisting the preference is asynchronous, so the
            // transport must not inherit a momentarily stale muted value.
            playbackPreferences.soundEnabled = true
            let availableComponents = Set(componentTimelines.keys)
            let narrationIsHeldForVoiceOver = playbackPreferences
                .narrationEnabled
                && (suppressesNarrationForCurrentPlayback
                    || narrationRequiresExplicitVoiceOverResume)
            let heldVoiceOverComponent = narrationIsHeldForVoiceOver
                ? AuthoredAudioPlaybackBoundaryPolicy
                    .componentToPauseForVoiceOver(
                        available: availableComponents,
                        usesVerifiedRoleSeparation:
                            usesVerifiedRoleSeparation
                    )
                : nil
            var retainedComponents = AuthoredAudioPlaybackBoundaryPolicy
                .componentsToPlay(
                    available: availableComponents,
                    usesVerifiedRoleSeparation:
                        usesVerifiedRoleSeparation,
                    suppressesNarration: narrationIsHeldForVoiceOver
                        || !playbackPreferences.narrationEnabled,
                    narrationIsEnabled:
                        playbackPreferences.narrationEnabled
                )
            if let heldVoiceOverComponent {
                retainedComponents.insert(heldVoiceOverComponent)
                narrationRequiresExplicitVoiceOverResume = true
            }
            guard !retainedComponents.isEmpty else {
                primaryAudioPlayback = nil
#if DEBUG
                primaryAudioDiagnosticForTesting =
                    "inactive;reason=no-eligible-component"
#endif
                return .noEligibleComponent
            }
            var cursorStores: [
                AuthoredAudioComponent: PrimaryAudioCursorStore
            ] = [:]
            var componentCursors: [AuthoredAudioComponent: Int64] = [:]
            // Recover every component before any migration write or reset.
            // Both schema-2 stores may therefore consume the same former
            // whole-mix cursor consistently on their first launch.
            for component in componentOrder {
                guard let timeline = componentTimelines[component] else {
                    continue
                }
                let maximum = timeline.authoredDurationSamples
                let store = PrimaryAudioCursorStore(
                    directoryURL: binding.cursorDirectoryURL,
                    component: component
                )
                cursorStores[component] = store
                let recovered = await store.recover(
                    authority: binding.authority,
                    maximumCursorSample: maximum
                ) ?? 0
                componentCursors[component] = max(
                    min(binding.journalCursorSample, maximum),
                    recovered
                )
            }
            let allRetainedComponentsCompleted = retainedComponents
                .allSatisfy { component in
                    guard let cursor = componentCursors[component],
                          let maximum = componentTimelines[component]?
                            .authoredDurationSamples else { return false }
                    return cursor >= maximum
                }
            if allRetainedComponentsCompleted {
                // Replaying a finished finite scene still requires this new
                // deliberate sound action. Reset only components eligible for
                // this run; a narration-disabled clock must not block or move
                // the independently authored non-speaking bed.
                for component in componentOrder {
                    guard retainedComponents.contains(component),
                          let timeline = componentTimelines[component],
                          let store = cursorStores[component] else { continue }
                    await store.reset(
                        authority: binding.authority,
                        maximumCursorSample:
                            timeline.authoredDurationSamples
                    )
                    componentCursors[component] = 0
                }
            }

            var components: [
                AuthoredAudioComponent: PrimaryAudioComponentPlayback
            ] = [:]
            for component in componentOrder {
                guard retainedComponents.contains(component),
                      let timeline = componentTimelines[component],
                      let cursorSample = componentCursors[component],
                      let cursorStore = cursorStores[component] else {
                    continue
                }
                let maximum = timeline.authoredDurationSamples
                if cursorSample >= maximum {
                    try await cursorStore.save(
                        authority: binding.authority,
                        cursorSample: maximum,
                        maximumCursorSample: maximum
                    )
                    continue
                }
                let transport = NativeTimelineTransport(
                    preferences: playbackPreferences
                )
                let cursorToken = UUID()
                try transport.prepare(
                    timeline: timeline,
                    cursorSample: cursorSample,
                    resolver: binding.resolver
                )
                let componentPlayback = PrimaryAudioComponentPlayback(
                    component: component,
                    timeline: timeline,
                    transport: transport,
                    cursorStore: cursorStore,
                    cursorToken: cursorToken
                )
                components[component] = componentPlayback
            }
            let playback = PrimaryAudioPlayback(
                routeKey: routeKey,
                binding: binding,
                usesVerifiedRoleSeparation: usesVerifiedRoleSeparation,
                components: components
            )
            primaryAudioPlayback = playback

            for component in componentOrder {
                guard let componentPlayback = components[component] else {
                    continue
                }
                try componentPlayback.transport
                    .configureEndOfTimelineBoundary(
                        resolver: binding.resolver
                    ) { [weak self] snapshot in
                        self?.completePrimaryAudioComponent(
                            routeKey: routeKey,
                            component: component,
                            cursorToken: componentPlayback.cursorToken,
                            snapshot: snapshot
                        )
                    }
            }

            var startedComponentCount = 0
            for component in componentOrder {
                guard let componentPlayback = components[component] else {
                    continue
                }
                let narrationMustRemainHeld = playbackPreferences
                    .narrationEnabled
                    && (suppressesNarrationForCurrentPlayback
                        || narrationRequiresExplicitVoiceOverResume)
                let componentsToPlay = AuthoredAudioPlaybackBoundaryPolicy
                    .componentsToPlay(
                        available: Set(components.keys),
                        usesVerifiedRoleSeparation:
                            usesVerifiedRoleSeparation,
                        suppressesNarration: narrationMustRemainHeld
                            || !playbackPreferences.narrationEnabled,
                        narrationIsEnabled:
                            playbackPreferences.narrationEnabled
                    )
                guard componentsToPlay.contains(component) else {
                    try await componentPlayback.cursorStore.save(
                        authority: binding.authority,
                        cursorSample: componentCursors[component] ?? 0,
                        maximumCursorSample:
                            componentPlayback.timeline
                                .authoredDurationSamples
                    )
                    continue
                }
                try componentPlayback.transport.play()
                let nativeCursor = try componentPlayback.transport
                    .activeAudioCursorBinding()
                componentPlayback.cursorStoreIsActive = true
                try await componentPlayback.cursorStore.start(
                    token: componentPlayback.cursorToken,
                    authority: binding.authority,
                    maximumCursorSample:
                        componentPlayback.timeline
                            .authoredDurationSamples,
                    feed: nativeCursor.feed,
                    gateToken: nativeCursor.gateToken,
                    maximumUndurableGraphSampleCount: Int64(
                        nativeCursor.renderedGraphSampleRate / 4
                    ),
                    failure: { [weak self] failedToken in
                        Task { @MainActor [weak self] in
                            self?.failPrimaryAudioCursor(
                                token: failedToken,
                                routeKey: routeKey,
                                component: component
                            )
                        }
                    }
                )
                startedComponentCount += 1
            }
#if DEBUG
            let diagnosticCursor = componentCursors[.narration]
                ?? componentCursors[.wholeMix]
                ?? binding.journalCursorSample
            primaryAudioDiagnosticForTesting =
                "playing;timeline=\(routeKey.timelineID.rawValue);"
                    + "cursor=\(diagnosticCursor);"
                    + "components=\(startedComponentCount);"
                    + "separated=\(usesVerifiedRoleSeparation ? 1 : 0)"
#endif
            try Task.checkCancellation()
            guard primaryAudioPlayback === playback,
                  playback.routeKey == routeKey,
                  !playback.components.isEmpty else {
                pausePrimaryAudioForBoundary()
                return .failed
            }
            let narrationCursor = componentCursors[.narration]
                ?? componentCursors[.wholeMix]
                ?? binding.journalCursorSample
            guard let cueID = narrationCueID(
                in: binding.timeline,
                at: narrationCursor
            ) else {
                pausePrimaryAudioForBoundary()
                return .failed
            }
            if recordsJournalStart {
                let narrationIsPlaying = playback.components[.narration]?
                    .transport.state == .playing
                    || playback.components[.wholeMix]?.transport.state
                        == .playing
                model.recordPrimaryAudioCursor(
                    cueID: cueID,
                    sampleOffset: narrationCursor,
                    isPlaying: narrationIsPlaying,
                    expectedIdentity: routeKey.routeIdentity
                )
            }
            return .started
        } catch is CancellationError {
            pausePrimaryAudioForBoundary()
            return .failed
        } catch {
#if DEBUG
            failureDiagnosticForTesting = String(reflecting: error)
            primaryAudioDiagnosticForTesting =
                "failed;error=\(String(reflecting: error))"
#endif
            pausePrimaryAudioForBoundary()
            return .failed
        }
    }

    /// Resumes only the component held at an exact VoiceOver boundary. The
    /// already-running non-speaking transport is neither rebuilt nor rewound,
    /// so its haptic authority cannot replay.
    private func resumeHeldPrimaryAudioComponent(
        expectedIdentity: ChapterRuntimeRouteIdentity,
        suppressesNarration: Bool
    ) -> Bool {
        guard !suppressesNarration,
              narrationRequiresExplicitVoiceOverResume,
              let model,
              model.experiencePreferences.narrationEnabled,
              let playback = primaryAudioPlayback,
              playback.routeKey.routeIdentity == expectedIdentity else {
            return false
        }
        guard let component = AuthoredAudioPlaybackBoundaryPolicy
                .componentToPauseForVoiceOver(
                    available: Set(playback.components.keys),
                    usesVerifiedRoleSeparation:
                        playback.usesVerifiedRoleSeparation
                ),
              let held = playback.components[component],
              held.transport.state == .prepared
                || held.transport.state == .paused else {
            return false
        }
        let routeKey = playback.routeKey
        let generation = routeGeneration
        audioPlaybackState = .starting
        Task { @MainActor [weak self, weak model] in
            guard let self, let model else { return }
            do {
                guard self.routeGeneration == generation,
                      self.identity == expectedIdentity,
                      self.primaryAudioPlayback === playback,
                      playback.components[component] === held,
                      model.chapterRuntimeRouteIdentity(
                          for: expectedIdentity.chapterID,
                          viewportCropID: expectedIdentity.viewportCropID,
                          reduceMotion: expectedIdentity.reduceMotion
                      ) == expectedIdentity else {
                    throw JourneyChapterRuntimeError.routeAuthorityChanged
                }
                var preferences = model.experiencePreferences
                preferences.soundEnabled = true
                held.transport.applyPreferences(preferences)
                try held.transport.play()
                let nativeCursor = try held.transport
                    .activeAudioCursorBinding()
                held.cursorStoreIsActive = true
                try await held.cursorStore.start(
                    token: held.cursorToken,
                    authority: playback.binding.authority,
                    maximumCursorSample:
                        held.timeline.authoredDurationSamples,
                    feed: nativeCursor.feed,
                    gateToken: nativeCursor.gateToken,
                    maximumUndurableGraphSampleCount: Int64(
                        nativeCursor.renderedGraphSampleRate / 4
                    ),
                    failure: { [weak self] failedToken in
                        Task { @MainActor [weak self] in
                            self?.failPrimaryAudioCursor(
                                token: failedToken,
                                routeKey: routeKey,
                                component: component
                            )
                        }
                    }
                )
                guard self.routeGeneration == generation,
                      self.primaryAudioPlayback === playback,
                      playback.components[component] === held else {
                    throw JourneyChapterRuntimeError.routeAuthorityChanged
                }
                self.suppressesNarrationForCurrentPlayback = false
                self.narrationRequiresExplicitVoiceOverResume = false
                self.audioPlaybackState = .playing
                let cursor = min(
                    held.transport.snapshot().cursorSample,
                    held.timeline.authoredDurationSamples
                )
                if let cueID = self.narrationCueID(
                    in: playback.binding.timeline,
                    at: cursor
                ) {
                    model.recordPrimaryAudioCursor(
                        cueID: cueID,
                        sampleOffset: cursor,
                        isPlaying: true,
                        expectedIdentity: expectedIdentity
                    )
                }
            } catch let error as JourneyChapterRuntimeError
                where error == .routeAuthorityChanged {
                self.pausePrimaryAudioForBoundary()
            } catch {
                self.pausePrimaryAudioForBoundary()
                self.responsiveAudioPolicy.requireExplicitResume()
                self.audioPlaybackState =
                    self.responsiveAudioPolicy.playbackState
            }
        }
        return true
    }

    private func startPrimaryAudioPlayback(
        _ attempt: ChapterResponsiveAudioPlaybackAttempt,
        routeKey: PrimaryAudioRouteKey,
        startEpoch: ResponsiveAudioPlaybackStartEpoch
    ) {
        guard let model else { return }
        responsiveAudioPlaybackTask?.cancel()
        let generation = routeGeneration
        responsiveAudioPlaybackTask = Task { @MainActor [weak self, weak model] in
            guard let self, let model else { return }
            let outcome = await self.startPrimaryAudioComponent(
                routeKey: routeKey,
                startEpoch: startEpoch,
                model: model,
                generation: generation
            )
            let authorityIsCurrent = outcome != .failed
                && !Task.isCancelled
                && self.routeGeneration == generation
                && self.primaryAudioRouteKey == routeKey
                && startEpoch == model
                    .responsiveAudioPlaybackStartEpochForCurrentLifecycle()
            if !authorityIsCurrent {
                self.pausePrimaryAudioForBoundary()
            }
            let didStart = authorityIsCurrent && outcome == .started
            guard self.responsiveAudioPolicy.completePlayback(
                attempt,
                didStart: didStart
            ) else {
                self.pausePrimaryAudioForBoundary()
                return
            }
            self.responsiveAudioPlaybackTask = nil
            self.responsiveAudioAuthorizedStartEpoch = didStart
                ? startEpoch : nil
            let primaryTransportIsRunning = self.primaryAudioPlayback?
                .components.values.contains(where: {
                    $0.transport.state == .playing
                }) == true
            if authorityIsCurrent, outcome == .noEligibleComponent {
                self.audioPlaybackState = .inactive
            } else if self.narrationRequiresExplicitVoiceOverResume,
                      !self.suppressesNarrationForCurrentPlayback {
                self.audioPlaybackState = .resumeRequired
            } else {
                self.audioPlaybackState = didStart
                    && !primaryTransportIsRunning
                    ? .resumeRequired
                    : self.responsiveAudioPolicy.playbackState
            }
#if DEBUG
            self.audioPlaybackStateDiagnosticForTesting =
                "primary-playback-complete:"
                    + self.audioPlaybackState.rawValue
#endif
        }
    }

    private func completePrimaryAudioComponent(
        routeKey: PrimaryAudioRouteKey,
        component: AuthoredAudioComponent,
        cursorToken: UUID,
        snapshot: NativeTimelineTransportSnapshot
    ) {
        guard let playback = primaryAudioPlayback,
              playback.routeKey == routeKey,
              let completed = playback.components[component],
              completed.cursorToken == cursorToken,
              snapshot.timelineID == routeKey.timelineID,
              !snapshot.isPlaying else { return }
        playback.components[component] = nil
        let endSample = completed.timeline.authoredDurationSamples
        let cursorSample = min(max(snapshot.cursorSample, 0), endSample)
#if DEBUG
        primaryAudioDiagnosticForTesting =
            "completed;timeline=\(routeKey.timelineID.rawValue);"
                + "component=\(component.rawValue);cursor=\(cursorSample)"
#endif
        if component == .narration || component == .wholeMix,
           let cueID = narrationCueID(
            in: playback.binding.timeline,
            at: cursorSample
        ) {
            model?.recordPrimaryAudioCursor(
                cueID: cueID,
                sampleOffset: cursorSample,
                isPlaying: false,
                expectedIdentity: routeKey.routeIdentity
            )
        }
        Task {
            await completed.cursorStore.finish(
                token: cursorToken,
                authority: playback.binding.authority,
                cursorSample: cursorSample,
                maximumCursorSample: endSample
            )
        }

        // Each role owns its own transport and durability epoch. Completing
        // narration cannot tear down a score/soundscape clock, and completing
        // that clock cannot consume a VoiceOver-paused narration cursor.
        guard playback.components.isEmpty else {
            let remainingTransportIsRunning = playback.components.values
                .contains { $0.transport.state == .playing }
            if !remainingTransportIsRunning,
               responsiveAudioRouteKey == nil {
                audioPlaybackState = .resumeRequired
            }
            return
        }
        primaryAudioPlayback = nil

        // A responsive bed may continue after its finite narration ends. A
        // primary-only scene instead becomes explicitly replayable and must
        // not inherit automatic playback through a later presentation rebind.
        guard responsiveAudioRouteKey == nil else { return }
        responsiveAudioPlaybackTask?.cancel()
        responsiveAudioPlaybackTask = nil
        responsiveAudioAuthorizedStartEpoch = nil
        responsiveAudioPolicy.completeFinitePlayback()
        audioPlaybackState = responsiveAudioPolicy.playbackState
#if DEBUG
        audioPlaybackStateDiagnosticForTesting =
            "primary-timeline-complete:\(audioPlaybackState.rawValue)"
#endif
    }

    private func pausePrimaryAudioForBoundary() {
        narrationRequiresExplicitVoiceOverResume = false
        guard let playback = primaryAudioPlayback else { return }
        primaryAudioPlayback = nil
        var narrationCursor: Int64?
        for component in [
            AuthoredAudioComponent.narration,
            .nonSpeaking,
            .wholeMix,
        ] {
            guard let componentPlayback = playback.components[component]
            else { continue }
            let snapshot: NativeTimelineTransportSnapshot
            do {
                snapshot = try componentPlayback.transport.pause()
            } catch {
                snapshot = componentPlayback.transport.snapshot()
            }
            componentPlayback.transport.stop()
            let maximum = componentPlayback.timeline
                .authoredDurationSamples
            let cursorSample = min(
                max(snapshot.cursorSample, 0),
                maximum
            )
            if component == .narration || component == .wholeMix {
                narrationCursor = cursorSample
            }
            Task {
                if componentPlayback.cursorStoreIsActive {
                    await componentPlayback.cursorStore.finish(
                        token: componentPlayback.cursorToken,
                        authority: playback.binding.authority,
                        cursorSample: cursorSample,
                        maximumCursorSample: maximum
                    )
                } else {
                    try? await componentPlayback.cursorStore.save(
                        authority: playback.binding.authority,
                        cursorSample: cursorSample,
                        maximumCursorSample: maximum
                    )
                }
            }
        }
#if DEBUG
        primaryAudioDiagnosticForTesting =
            "paused;timeline=\(playback.routeKey.timelineID.rawValue);"
                + "components=all"
#endif
        if let narrationCursor,
           let cueID = narrationCueID(
            in: playback.binding.timeline,
            at: narrationCursor
        ) {
            model?.recordPrimaryAudioCursor(
                cueID: cueID,
                sampleOffset: narrationCursor,
                isPlaying: false,
                expectedIdentity: playback.routeKey.routeIdentity
            )
        }
    }

    private func failPrimaryAudioCursor(
        token: UUID,
        routeKey: PrimaryAudioRouteKey,
        component: AuthoredAudioComponent
    ) {
        guard let playback = primaryAudioPlayback,
              playback.routeKey == routeKey,
              playback.components[component]?.cursorToken == token else {
            return
        }
        pausePrimaryAudioForBoundary()
        responsiveAudioPolicy.requireExplicitResume()
        audioPlaybackState = responsiveAudioPolicy.playbackState
#if DEBUG
        failureDiagnosticForTesting =
            "primary audio cursor persistence failed"
        primaryAudioDiagnosticForTesting = "failed"
#endif
    }
    private func startResponsiveAudioPlayback(
        _ attempt: ChapterResponsiveAudioPlaybackAttempt,
        routeKey: ResponsiveAudioRouteKey,
        startEpoch: ResponsiveAudioPlaybackStartEpoch
    ) {
        guard let model else { return }
        responsiveAudioPlaybackTask?.cancel()
        let generation = routeGeneration
        responsiveAudioPlaybackTask = Task { @MainActor [weak self, weak model] in
            guard let self, let model else { return }
            let primaryKey = self.primaryAudioRouteKey
            let primaryOutcome: PrimaryAudioStartOutcome
            if let primaryKey {
                primaryOutcome = await self.startPrimaryAudioComponent(
                    routeKey: primaryKey,
                    startEpoch: startEpoch,
                    model: model,
                    generation: generation,
                    // The responsive session is the durable consent record
                    // for a combined scene. Its cursor sidecar protects a
                    // hard kill, while explicit pause still journals the
                    // primary cue. A second start record here would race the
                    // scene controller's deliberately audio-only rebase.
                    recordsJournalStart: false
                )
            } else {
                primaryOutcome = .noEligibleComponent
            }
            guard primaryOutcome != .failed else {
                guard self.responsiveAudioPolicy.completePlayback(
                    attempt,
                    didStart: false
                ) else { return }
                self.responsiveAudioPlaybackTask = nil
                self.responsiveAudioAuthorizedStartEpoch = nil
                self.audioPlaybackState = self.responsiveAudioPolicy.playbackState
                return
            }
            let started = await model.startResponsiveAudioPlayback(
                startEpoch: startEpoch
            )
            guard !Task.isCancelled,
                  self.routeGeneration == generation,
                  self.responsiveAudioRouteKey == routeKey else {
                self.pausePrimaryAudioForBoundary()
                return
            }

            var presentationWasSynchronized = false
            var replacementWillPublishCurrentAuthority = false
            if started,
               self.identity == routeKey.routeIdentity,
               let runtime = self.runtime {
                let currentIdentity = model.chapterRuntimeRouteIdentity(
                    for: routeKey.routeIdentity.chapterID,
                    viewportCropID: routeKey.routeIdentity.viewportCropID,
                    reduceMotion: routeKey.routeIdentity.reduceMotion
                )
                if currentIdentity == routeKey.routeIdentity {
                    do {
                        let synchronized = try await model
                            .synchronizeChapterScenePresentationAfterResponsiveAudioStart(
                                runtime: runtime,
                                identity: routeKey.routeIdentity
                            )
                        let prepared = try await self.prepareForInput(
                            synchronized,
                            alphaSampler: self.alphaSampler,
                            runtime: runtime,
                            generation: generation,
                            expectedIdentity: routeKey.routeIdentity
                        )
                        guard !Task.isCancelled,
                              self.routeGeneration == generation,
                              self.responsiveAudioRouteKey == routeKey,
                              self.runtime?.controller === runtime.controller else {
                            return
                        }
                        if prepared {
                            self.presentation = synchronized
                            self.adoptResponsiveAudioPresentation(
                                synchronized,
                                identity: routeKey.routeIdentity
                            )
                            presentationWasSynchronized = true
                        } else {
                            await model
                                .failClosedResponsiveAudioPresentationSynchronization(
                                    runtime: runtime,
                                    identity: routeKey.routeIdentity,
                                    playbackLease: routeKey.playbackLease
                                )
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        await model
                            .failClosedResponsiveAudioPresentationSynchronization(
                                runtime: runtime,
                                identity: routeKey.routeIdentity,
                                playbackLease: routeKey.playbackLease
                            )
#if DEBUG
                        self.failureDiagnosticForTesting = String(reflecting: error)
#endif
                    }
                } else if let currentIdentity,
                          let currentProgram = model.chapterCursor?
                            .responsiveAudioProgram,
                          currentIdentity.viewportCropID
                            == routeKey.routeIdentity.viewportCropID,
                          currentIdentity.reduceMotion
                            == routeKey.routeIdentity.reduceMotion,
                          ResponsiveAudioPlaybackStartLease(
                              chapterID: currentIdentity.chapterID,
                              packageID: currentIdentity.packageID,
                              packageManifestDigest:
                                currentIdentity.packageManifestDigest,
                              beatID: currentIdentity.beatID,
                              programID: currentProgram.id,
                              programScope: currentProgram.scope
                          ) == routeKey.playbackLease {
                    // A verified persistence-authority replacement is already
                    // waiting for this task. Its fresh controller is built from
                    // the current committer after this completion returns.
                    replacementWillPublishCurrentAuthority = true
                }
            }

            let mayPublishPlayback = started
                && (presentationWasSynchronized
                    || replacementWillPublishCurrentAuthority)
            if !mayPublishPlayback {
                self.pausePrimaryAudioForBoundary()
            }
            guard self.responsiveAudioPolicy.completePlayback(
                attempt,
                didStart: mayPublishPlayback
            ) else { return }
            self.responsiveAudioPlaybackTask = nil
            self.responsiveAudioAuthorizedStartEpoch = mayPublishPlayback
                ? startEpoch
                : nil
            self.audioPlaybackState = self
                .narrationRequiresExplicitVoiceOverResume
                && !self.suppressesNarrationForCurrentPlayback
                ? .resumeRequired
                : self.responsiveAudioPolicy.playbackState
#if DEBUG
            self.audioPlaybackStateDiagnosticForTesting =
                "playback-complete:\(self.audioPlaybackState.rawValue)"
            if presentationWasSynchronized {
                self.publishInputReadinessForTesting(
                    stage: "after-hear",
                    identity: routeKey.routeIdentity,
                    generation: generation
                )
            }
#endif
        }
    }

#if DEBUG
    private func inputFIFOProbeOrdinalForTesting(
        _ input: PendingInput
    ) -> Int? {
        guard inputFIFOProbeIsEnabledForTesting,
              case let .touch(.trace(viewportPoint)) = input else {
            return nil
        }
        if viewportPoint.y == -1,
           viewportPoint.x <= -1,
           viewportPoint.x >= -11 {
            return Int(-viewportPoint.x)
        }
        if inputFIFOProbeUsesRightAngleTraceForTesting {
            return (9 ... 11).first { ordinal in
                viewportPoint == inputFIFOProbeViewportPointForTesting(
                    ordinal: ordinal
                )
            }
        }
        return nil
    }

    private func inputFIFOProbeTracePriorityForTesting(
        _ input: PendingInput
    ) -> TraceDeferredSamplePriority? {
        guard inputFIFOProbeUsesRightAngleTraceForTesting,
              let ordinal = inputFIFOProbeOrdinalForTesting(input),
              (9 ... 11).contains(ordinal),
              case let .touch(.trace(viewportPoint)) = input,
              let presentation,
              case let .trace(visual)? =
                presentation.cursor.scene.interactionVisualBinding,
              let frame = inputFIFOProbeTraceFrameForTesting(
                  visual: visual
              ) else {
            return nil
        }
        return TraceDeferredSamplePriority.classify(
            viewportPoint: viewportPoint,
            frame: frame,
            visual: visual,
            configuration: inputFIFOProbeRightAngleConfigurationForTesting,
            reachedAnchorCount: 1
        )
    }

    private var inputFIFOProbeRightAngleConfigurationForTesting:
        TraceInteractionSpec {
        TraceInteractionSpec(
            anchors: [
                NormalizedPoint(x: 0.32, y: 0.44),
                NormalizedPoint(x: 0.68, y: 0.44),
                NormalizedPoint(x: 0.68, y: 0.60),
            ],
            tolerance: 0.012
        )
    }

    private var inputFIFOProbeAdversarialTraceMotionForTesting:
        SceneLayerMotionState {
        SceneLayerMotionState(
            parallaxOffset: SceneFrameVector(dx: 0.035, dy: 0.022),
            windOffset: SceneFrameVector(dx: 0.018, dy: 0.016),
            focusAmount: 0
        )
    }

    /// Replays the production classifier against a visibly displaced route
    /// layer. The signed lab scene is intentionally still; this DEBUG-only
    /// frame keeps its exact target and layer identities while making an
    /// unbound camera-space conversion miss the authored anchor tolerance.
    private func inputFIFOProbeTraceFrameForTesting(
        visual: SceneTraceVisualBinding
    ) -> SceneFramePlan? {
        guard let base = presentation?.framePlan,
              let originalCommand = base.drawCommands.first(where: {
                  guard case let .layer(layerID, _) = $0.source else {
                      return false
                  }
                  return layerID == visual.layerID
              }),
              base.interactionHitRegions.contains(where: {
                  $0.interactionTargetID == visual.interactionTargetID
                      && $0.layerID == visual.layerID
              }) else {
            return nil
        }
        let replacementMotion =
            inputFIFOProbeAdversarialTraceMotionForTesting
        let oldOffset = SceneFrameVector(
            dx: originalCommand.motion.parallaxOffset.dx
                + originalCommand.motion.windOffset.dx,
            dy: originalCommand.motion.parallaxOffset.dy
                + originalCommand.motion.windOffset.dy
        )
        let newOffset = SceneFrameVector(
            dx: replacementMotion.parallaxOffset.dx
                + replacementMotion.windOffset.dx,
            dy: replacementMotion.parallaxOffset.dy
                + replacementMotion.windOffset.dy
        )
        let delta = SceneFrameVector(
            dx: newOffset.dx - oldOffset.dx,
            dy: newOffset.dy - oldOffset.dy
        )
        let drawCommands = base.drawCommands.map { command in
            guard case let .layer(layerID, _) = command.source,
                  layerID == visual.layerID else {
                return command
            }
            return SceneDrawCommand(
                source: command.source,
                authoredOrder: command.authoredOrder,
                depth: command.depth,
                asset: command.asset,
                masks: command.masks,
                masterFrame: command.masterFrame,
                viewportFrame: command.viewportFrame,
                opacity: command.opacity,
                blendMode: command.blendMode,
                motion: replacementMotion
            )
        }
        let hitRegions = base.interactionHitRegions.map { region in
            guard region.interactionTargetID == visual.interactionTargetID,
                  region.layerID == visual.layerID else {
                return region
            }
            return SceneInteractionHitRegionPlan(
                interactionTargetID: region.interactionTargetID,
                layerID: region.layerID,
                accessibilityElementID: region.accessibilityElementID,
                viewportPath: region.viewportPath.map {
                    SceneFramePoint(
                        x: $0.x + delta.dx,
                        y: $0.y + delta.dy
                    )
                }
            )
        }
        return SceneFramePlan(
            sceneID: base.sceneID,
            viewportCropID: base.viewportCropID,
            viewport: base.viewport,
            deterministicTick: base.deterministicTick,
            reduceMotion: base.reduceMotion,
            camera: base.camera,
            drawCommands: drawCommands,
            atmosphere: base.atmosphere,
            interactionSourceHitRegion: base.interactionSourceHitRegion,
            interactionHitRegions: hitRegions,
            interactionResponse: base.interactionResponse,
            safeTextRegions: base.safeTextRegions
        )
    }

    private func inputFIFOProbeViewportPointForTesting(
        ordinal: Int
    ) -> SceneFramePoint {
        guard inputFIFOProbeUsesRightAngleTraceForTesting,
              (9 ... 11).contains(ordinal),
              let presentation,
              case let .trace(visual)? =
                presentation.cursor.scene.interactionVisualBinding,
              let frame = inputFIFOProbeTraceFrameForTesting(visual: visual),
              let command = frame.drawCommands.first(where: {
                  guard case let .layer(layerID, _) = $0.source else {
                      return false
                  }
                  return layerID == visual.layerID
              }) else {
            return SceneFramePoint(x: -Double(ordinal), y: -1)
        }
        let masterPoint: NormalizedPoint
        if inputFIFOProbeCycleForTesting == 2 {
            switch ordinal {
            case 9:
                masterPoint = inputFIFOProbeRightAngleConfigurationForTesting
                    .anchors[2]
            case 10:
                masterPoint = NormalizedPoint(x: 0.62, y: 0.54)
            default:
                masterPoint = inputFIFOProbeRightAngleConfigurationForTesting
                    .anchors[1]
            }
        } else {
            switch ordinal {
            case 9:
                masterPoint = inputFIFOProbeRightAngleConfigurationForTesting
                    .anchors[1]
            case 10:
                masterPoint = inputFIFOProbeRightAngleConfigurationForTesting
                    .anchors[2]
            default:
                masterPoint = NormalizedPoint(x: 0.62, y: 0.54)
            }
        }
        let source = frame.camera.sourceRect
        return SceneFramePoint(
            x: (masterPoint.x - source.x) / source.width
                + command.motion.parallaxOffset.dx
                + command.motion.windOffset.dx,
            y: (masterPoint.y - source.y) / source.height
                + command.motion.parallaxOffset.dy
                + command.motion.windOffset.dy
        )
    }

    private func nextMissingInputFIFOProbeTraceAnchorForTesting() -> Int? {
        var secured = Set(
            ([currentInput].compactMap { $0 } + pendingInputs)
                .compactMap { $0.tracePriority.protectedAnchorIndex }
        )
        secured.formUnion(
            deferredContinuousInputs.compactMap {
                $0.tracePriority.protectedAnchorIndex
            }
        )
        var candidate = 1
        while candidate < 3, secured.contains(candidate) {
            candidate += 1
        }
        return candidate < 3 ? candidate : nil
    }

    private func appendDeferredInputFIFOProbeForTesting(
        _ input: PendingInput
    ) {
        guard let ordinal = inputFIFOProbeOrdinalForTesting(input) else {
            return
        }
        inputFIFOProbeDeferredOrdinalsForTesting.append(ordinal)
        publishInputFIFOProbeDiagnosticForTesting()
    }

    private func coalesceInputFIFOProbeForTesting(
        _ input: PendingInput
    ) {
        guard let ordinal = inputFIFOProbeOrdinalForTesting(input) else {
            return
        }
        inputFIFOProbeDeferredOrdinalsForTesting.removeAll { $0 == ordinal }
        inputFIFOProbeCoalescedForTesting.append(ordinal)
        publishInputFIFOProbeDiagnosticForTesting()
    }

    private func discardDeferredInputFIFOProbeForTesting() {
        inputFIFOProbeDroppedForTesting.append(
            contentsOf: inputFIFOProbeDeferredOrdinalsForTesting
        )
        inputFIFOProbeDeferredOrdinalsForTesting.removeAll(
            keepingCapacity: false
        )
        publishInputFIFOProbeDiagnosticForTesting()
    }

    private func promoteDeferredInputFIFOProbeForTesting(
        _ input: PendingInput
    ) {
        guard let ordinal = inputFIFOProbeOrdinalForTesting(input),
              let index = inputFIFOProbeDeferredOrdinalsForTesting
                .firstIndex(of: ordinal) else { return }
        inputFIFOProbeDeferredOrdinalsForTesting.remove(at: index)
        publishInputFIFOProbeDiagnosticForTesting()
    }

    private func acceptInputFIFOProbeForTesting(_ input: PendingInput) {
        guard let ordinal = inputFIFOProbeOrdinalForTesting(input) else {
            return
        }
        inputFIFOProbeAcceptedForTesting.append(ordinal)
        inputFIFOProbeMaximumReservationsForTesting = max(
            inputFIFOProbeMaximumReservationsForTesting,
            inputReservationOwners.count
        )
        publishInputFIFOProbeDiagnosticForTesting()
    }

    private func beginInputFIFOProbePerformForTesting(_ ordinal: Int) {
        inputFIFOProbePerformedForTesting.append(ordinal)
        inputFIFOProbeActivePerformsForTesting += 1
        inputFIFOProbeMaximumActivePerformsForTesting = max(
            inputFIFOProbeMaximumActivePerformsForTesting,
            inputFIFOProbeActivePerformsForTesting
        )
        if inputFIFOProbeTrackedOrdinalForTesting != ordinal {
            inputFIFOProbeUntrackedPerformsForTesting.append(ordinal)
        }
        publishInputFIFOProbeDiagnosticForTesting()
    }

    private func completeInputFIFOProbePerformForTesting(_ ordinal: Int) {
        inputFIFOProbeActivePerformsForTesting -= 1
        inputFIFOProbeCompletedForTesting.append(ordinal)
        publishInputFIFOProbeDiagnosticForTesting()
    }

    private func holdFirstInputFIFOProbePerformIfNeededForTesting() async {
        guard !inputFIFOProbeDidHoldForTesting else { return }
        inputFIFOProbeDidHoldForTesting = true
        inputFIFOProbeIsHoldingForTesting = true
        inputFIFOProbePhaseForTesting = "held"
        publishInputFIFOProbeDiagnosticForTesting()
        await withCheckedContinuation { continuation in
            guard inputFIFOProbeIsHoldingForTesting else {
                continuation.resume()
                return
            }
            inputFIFOProbeHoldContinuationForTesting = continuation
        }
    }

    private func publishInputFIFOProbeDiagnosticForTesting() {
        guard inputFIFOProbeIsEnabledForTesting else { return }
        func joined(_ values: [Int]) -> String {
            values.isEmpty ? "-" : values.map(String.init).joined(separator: ",")
        }
        let current = currentInput.flatMap {
            inputFIFOProbeOrdinalForTesting($0.input)
        }
        inputFIFOProbeDiagnosticForTesting =
            "cycle=\(inputFIFOProbeCycleForTesting);"
            + "phase=\(inputFIFOProbePhaseForTesting);"
            + "accepted=\(joined(inputFIFOProbeAcceptedForTesting));"
            + "performed=\(joined(inputFIFOProbePerformedForTesting));"
            + "completed=\(joined(inputFIFOProbeCompletedForTesting));"
            + "coalesced=\(joined(inputFIFOProbeCoalescedForTesting));"
            + "dropped=\(joined(inputFIFOProbeDroppedForTesting));"
            + "current=\(current.map(String.init) ?? "-");"
            + "deferred=\(joined(inputFIFOProbeDeferredOrdinalsForTesting));"
            + "pending=\(pendingInputs.count);"
            + "reservations=\(inputReservationOwners.count)/\(inputFIFOProbeMaximumReservationsForTesting);"
            + "task=\(inputTask == nil ? 0 : 1);"
            + "tracked=\(inputFIFOProbeTrackedOrdinalForTesting.map(String.init) ?? "-");"
            + "active=\(inputFIFOProbeActivePerformsForTesting)/\(inputFIFOProbeMaximumActivePerformsForTesting);"
            + "untracked=\(joined(inputFIFOProbeUntrackedPerformsForTesting));"
            + "lifecycle=\(lifecyclePresentationRefreshIsPending ? 1 : 0);"
            + "deactivation=\(deactivationIsPending ? 1 : 0);"
            + "route=\(identity == nil ? 0 : 1)"
    }

    private func chapterTouchIntentDiagnosticForTesting(
        _ intent: SceneTouchIntent
    ) -> String {
        guard case let .trace(viewportPoint) = intent else {
            return "intent=\(intent.performanceActionName)"
        }
        traceTouchSampleCountForTesting += 1
        if firstTraceViewportPointForTesting == nil {
            firstTraceViewportPointForTesting = viewportPoint
        }
        let first = firstTraceViewportPointForTesting ?? viewportPoint
        var diagnostic =
            "intent=trace;samples=\(traceTouchSampleCountForTesting)"
            + ";first=\(first.x),\(first.y)"
            + ";latest=\(viewportPoint.x),\(viewportPoint.y)"
        if let frame = presentation?.framePlan {
            if let master = try? SceneTouchGeometryResolver.masterPoint(
                for: viewportPoint,
                in: frame
            ) {
                diagnostic += ";latestMaster=\(master.x),\(master.y)"
            }
            do {
                if let hit = try SceneTouchGeometryResolver.target(
                    at: viewportPoint,
                    in: frame
                ) {
                    diagnostic +=
                        ";target=\(hit.interactionTargetID)"
                } else {
                    diagnostic += ";target=none"
                }
            } catch {
                diagnostic += ";targetError=\(String(reflecting: error))"
            }
        }
        return diagnostic
    }

    private func publishInputReadinessForTesting(
        stage: String,
        identity: ChapterRuntimeRouteIdentity,
        generation: UInt64
    ) {
        guard let model else {
            responsiveAudioBindingReadyForTesting =
                "blocked;stage=\(stage);generation=\(generation);model=missing"
            return
        }
        let admitted = admitsInput(for: identity)
        responsiveAudioBindingReadyForTesting =
            "\(admitted ? "ready" : "blocked");stage=\(stage);"
            + "generation=\(generation);"
            + "activation=\(responsiveAudioActivationDiagnosticForTesting);"
            + model.chapterRuntimeInputAdmissionDiagnosticForTesting(identity)
    }
#endif

    private var acceptedContinuousInputCount: Int {
        (currentInput?.input.isContinuousTransportSample == true ? 1 : 0)
            + pendingInputs.reduce(into: 0) { count, input in
                if input.input.isContinuousTransportSample { count += 1 }
            }
    }

    private func previewContinuousJournalInput(
        _ input: PendingInput,
        publishesVisualResponse: Bool
    ) -> ContinuousInputPreviewOutcome {
        guard case let .touch(intent) = input else {
            return .notApplicable
        }
        switch intent {
        case .trace, .adjustTarget:
            break
        default:
            return .notApplicable
        }
        guard let runtime, let displayedPresentation = presentation else {
            // Admission said the route was ready, so losing either authority
            // here is not ordinary motion. Preserve the raw observation at the
            // durable boundary instead of hiding it behind the 200 ms cadence.
            return .classified(.previewUnavailable)
        }
        do {
            let preview = try runtime.controller.previewContinuousTouch(
                intent,
                displayedFramePlan: displayedPresentation.framePlan,
                alphaSampler: alphaSampler
            )
            let previewProtection = protection(for: preview.semantic)
            // A durable input owns asynchronous texture preparation. Keep the
            // last published frame stable until that atomic replacement is
            // ready; subsequent raw samples still retain their causal
            // classification and durability priority.
            if publishesVisualResponse, !inputIsPending {
                let compositorState = compositor.update(
                    preview.presentation.framePlan
                )
                guard case .sceneReady = compositorState else {
#if DEBUG
                    failureDiagnosticForTesting =
                        "continuous-preview-compositor:\(compositorState)"
#endif
                    routeReplacementIsPending = true
                    failure = ProductionChapterRouteFailure(
                        kind: .rendererUnavailable,
                        assetAuthority: nil
                    )
                    return .routeFailed
                }
                presentation = preview.presentation
            }
            return .classified(previewProtection)
        } catch let error as SceneTouchActionResolverError {
            switch error {
            case .targetNotHit, .wrongTarget:
#if DEBUG
                chapterInputResolutionDiagnosticForTesting =
                    "continuous-preview-outside-authored-target"
#endif
                return neutralizeContinuousTouchPreview()
                    ? .ignored : .routeFailed
            default:
#if DEBUG
                chapterInputResolutionDiagnosticForTesting =
                    "continuous-preview-fallback:\(String(reflecting: error))"
#endif
                return .classified(.previewUnavailable)
            }
        } catch let error as ChapterSceneRuntimeControllerError
            where error == .unsupportedContinuousTouchPreview {
#if DEBUG
            chapterInputResolutionDiagnosticForTesting =
                "continuous-preview-no-causal-motion"
#endif
            return neutralizeContinuousTouchPreview()
                ? .ignored : .routeFailed
        } catch {
#if DEBUG
            chapterInputResolutionDiagnosticForTesting =
                "continuous-preview-fallback:\(String(reflecting: error))"
#endif
            return .classified(.previewUnavailable)
        }
    }

    private func protection(
        for semantic: ChapterSceneContinuousTouchSemantic
    ) -> ContinuousInputProtection {
        switch semantic {
        case .ordinary:
            return .ordinary
        case let .traceAnchor(index):
            return protection(
                for: unresolvedTracePriority(
                    TraceDeferredSamplePriority(protectedAnchorIndex: index)
                )
            )
        case let .pressureStabilityBoundary(isStable):
            return pressureInputProtectionPolicy.protection(
                isStable: isStable
            )
        case let .transformStage(index):
            return .transformStage(index)
        }
    }

    private func protection(
        for tracePriority: TraceDeferredSamplePriority
    ) -> ContinuousInputProtection {
        guard let anchorIndex = tracePriority.protectedAnchorIndex else {
            return .ordinary
        }
        return .traceAnchor(anchorIndex)
    }

    private func submitContinuousInputCandidate(
        _ candidate: DeferredContinuousInput
    ) {
        guard acceptedContinuousInputCount
                < maximumAcceptedContinuousInputs else {
            deferContinuousInput(candidate)
            return
        }
        guard acceptInput(
            candidate.input,
            owner: candidate.owner,
            identity: candidate.identity,
            protection: candidate.protection
        ) else {
            failClosedContinuousInputAuthority()
            return
        }
    }

    private func replaceRateLimitedContinuousInput(
        with candidate: DeferredContinuousInput
    ) {
        if let replaced = rateLimitedContinuousInput {
#if DEBUG
            coalesceInputFIFOProbeForTesting(replaced.input)
#endif
        }
        rateLimitedContinuousInput = candidate
    }

    private func coalesceRateLimitedContinuousInput() {
        guard let replaced = rateLimitedContinuousInput else { return }
#if DEBUG
        coalesceInputFIFOProbeForTesting(replaced.input)
#endif
        rateLimitedContinuousInput = nil
    }

    private func resetContinuousInputSampling() {
        rateLimitedContinuousInput = nil
        latestContinuousJournalInput = nil
        continuousInputRatePolicy.reset()
        pressureInputProtectionPolicy.reset()
        runtime?.controller.resetContinuousTouchPreview()
    }

    /// Removes response material from the exact presentation already on screen.
    /// It performs no file access and never jumps to a newer controller state
    /// whose textures may still be behind the route's prepare barrier.
    @discardableResult
    private func neutralizeContinuousTouchPreview() -> Bool {
        guard let runtime, let displayedPresentation = presentation else {
            return false
        }
        if inputIsPending {
            runtime.controller.resetContinuousTouchPreview()
            return true
        }
        do {
            let neutral = try runtime.controller
                .neutralizeContinuousTouchPreview(
                    displayedPresentation: displayedPresentation
                )
            let compositorState = compositor.update(neutral.framePlan)
            guard case .sceneReady = compositorState else {
                routeReplacementIsPending = true
                failure = ProductionChapterRouteFailure(
                    kind: .rendererUnavailable,
                    assetAuthority: nil
                )
                return false
            }
            // Finger-up ends only the display-rate preview. A committed
            // response may already own the controller and its authored
            // cleanup timer; cancelling that timer here would strand the
            // responsive-audio bed in engaged or resistance. The timer is
            // fenced by the controller's response token below, so it remains
            // safe when this neutral display projection no longer carries
            // the token itself.
            presentation = neutral
            return true
        } catch {
            failClosedContinuousInputAuthority()
#if DEBUG
            failureDiagnosticForTesting =
                "continuous-preview-neutralization:\(String(reflecting: error))"
#endif
            return false
        }
    }

    private func failClosedContinuousInputAuthority() {
        routeReplacementIsPending = true
        rateLimitedContinuousInput = nil
        latestContinuousJournalInput = nil
        failure = ProductionChapterRouteFailure(
            kind: .authorityUnavailable,
            assetAuthority: nil
        )
#if DEBUG
        failureDiagnosticForTesting =
            "continuous-input-authority-unavailable"
#endif
    }

    private func traceDeferredSamplePriority(
        for input: PendingInput
    ) -> TraceDeferredSamplePriority {
#if DEBUG
        if let probePriority = inputFIFOProbeTracePriorityForTesting(input) {
            return probePriority
        }
#endif
        guard case let .touch(.trace(viewportPoint)) = input,
              let presentation,
              case let .trace(configuration)? =
                presentation.cursor.beat.interaction?.grammar,
              case let .trace(visual)? =
                presentation.cursor.scene.interactionVisualBinding,
              case let .trace(progress)? = presentation.journeyState
                .activeChapter?.interaction?.progress else {
            return TraceDeferredSamplePriority()
        }
        return TraceDeferredSamplePriority.classify(
            viewportPoint: viewportPoint,
            frame: presentation.framePlan,
            visual: visual,
            configuration: configuration,
            reachedAnchorCount: progress.reachedAnchorCount
        )
    }

    private func unresolvedTracePriority(
        _ priority: TraceDeferredSamplePriority
    ) -> TraceDeferredSamplePriority {
        guard let anchorIndex = priority.protectedAnchorIndex else {
            return priority
        }
        let acceptedAnchorIndices = Set(
            ([currentInput].compactMap { $0 } + pendingInputs)
                .compactMap { $0.tracePriority.protectedAnchorIndex }
                + deferredContinuousInputs.compactMap {
                    $0.tracePriority.protectedAnchorIndex
                }
        )
        return acceptedAnchorIndices.contains(anchorIndex)
            ? TraceDeferredSamplePriority()
            : priority
    }

    private func deferContinuousInput(
        _ candidate: DeferredContinuousInput
    ) {
        if candidate.tracePriority.protectedAnchorIndex != nil {
            let candidatePriority = unresolvedTracePriority(
                candidate.tracePriority
            )
            guard let anchorIndex = candidatePriority.protectedAnchorIndex else {
#if DEBUG
                coalesceInputFIFOProbeForTesting(candidate.input)
#endif
                return
            }
            guard anchorIndex == nextMissingDeferredTraceAnchorIndex() else {
#if DEBUG
                coalesceInputFIFOProbeForTesting(candidate.input)
#endif
                return
            }
            guard deferredContinuousInputs.count
                    < maximumDeferredContinuousInputs else {
                failClosedContinuousInputAuthority()
                return
            }
            deferredContinuousInputs.append(candidate)
#if DEBUG
            appendDeferredInputFIFOProbeForTesting(candidate.input)
#endif
            return
        }

        if candidate.protection.isProtected {
            guard deferredContinuousInputs.count
                    < maximumDeferredContinuousInputs else {
                failClosedContinuousInputAuthority()
                return
            }
            deferredContinuousInputs.append(candidate)
#if DEBUG
            appendDeferredInputFIFOProbeForTesting(candidate.input)
#endif
            return
        }

        if let ordinaryIndex = deferredContinuousInputs.firstIndex(where: {
            !$0.protection.isProtected
        }) {
            let replaced = deferredContinuousInputs.remove(at: ordinaryIndex)
#if DEBUG
            coalesceInputFIFOProbeForTesting(replaced.input)
#endif
        }
        guard deferredContinuousInputs.count
                < maximumDeferredContinuousInputs else {
            failClosedContinuousInputAuthority()
            return
        }
        deferredContinuousInputs.append(candidate)
#if DEBUG
        appendDeferredInputFIFOProbeForTesting(candidate.input)
#endif
    }

    private func nextMissingDeferredTraceAnchorIndex() -> Int? {
#if DEBUG
        if inputFIFOProbeUsesRightAngleTraceForTesting {
            return nextMissingInputFIFOProbeTraceAnchorForTesting()
        }
#endif
        guard let presentation,
              case let .trace(configuration)? =
                presentation.cursor.beat.interaction?.grammar,
              case let .trace(progress)? = presentation.journeyState
                .activeChapter?.interaction?.progress else {
            return nil
        }
        var secured = Set(
            ([currentInput].compactMap { $0 } + pendingInputs)
                .compactMap { $0.tracePriority.protectedAnchorIndex }
        )
        secured.formUnion(
            deferredContinuousInputs.compactMap {
                $0.tracePriority.protectedAnchorIndex
            }
        )
        var candidate = progress.reachedAnchorCount
        while candidate < configuration.anchors.count,
              secured.contains(candidate) {
            candidate += 1
        }
        return candidate < configuration.anchors.count ? candidate : nil
    }

    @discardableResult
    private func acceptInput(
        _ input: PendingInput,
        owner: JourneyModel,
        identity: ChapterRuntimeRouteIdentity,
        protection: ContinuousInputProtection
    ) -> Bool {
        guard let reservation = owner.reserveChapterRuntimeInput(identity)
        else { return false }
        enqueue(
            input,
            reservation: reservation,
            owner: owner,
            identity: identity,
            protection: protection
        )
        return true
    }

    /// Promotes the next unaccepted transport sample ahead of a later discrete
    /// action, preserving chronological order without creating an unbounded
    /// durability queue. Failure means route or lifecycle admission closed;
    /// the later action must then be rejected in the same MainActor turn.
    private func promoteDeferredContinuousInputIfNeeded() -> Bool {
        guard !deferredContinuousInputs.isEmpty else { return true }
        let deferredContinuousInput = deferredContinuousInputs.removeFirst()
#if DEBUG
        promoteDeferredInputFIFOProbeForTesting(
            deferredContinuousInput.input
        )
#endif
        guard admitsInput(for: deferredContinuousInput.identity),
              model === deferredContinuousInput.owner else {
#if DEBUG
            if let ordinal = inputFIFOProbeOrdinalForTesting(
                deferredContinuousInput.input
            ) {
                inputFIFOProbeDroppedForTesting.append(ordinal)
                publishInputFIFOProbeDiagnosticForTesting()
            }
#endif
            return false
        }
        let wasAccepted = acceptInput(
            deferredContinuousInput.input,
            owner: deferredContinuousInput.owner,
            identity: deferredContinuousInput.identity,
            protection: deferredContinuousInput.protection
        )
        guard wasAccepted else {
            deferredContinuousInputs.insert(deferredContinuousInput, at: 0)
#if DEBUG
            if let ordinal = inputFIFOProbeOrdinalForTesting(
                deferredContinuousInput.input
            ) {
                inputFIFOProbeDeferredOrdinalsForTesting.insert(
                    ordinal,
                    at: 0
                )
            }
            publishInputFIFOProbeDiagnosticForTesting()
#endif
            return false
        }
#if DEBUG
        publishInputFIFOProbeDiagnosticForTesting()
#endif
        return deferredContinuousInputs.isEmpty
    }

    /// Reserves the complete content-bounded deferred sequence before a
    /// semantic boundary. Normal worker draining still promotes only one
    /// entry at a time, preserving the eight-reservation transport cap during
    /// ordinary motion.
    private func drainContinuousInputBeforeBoundary(
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) -> Bool {
        guard admitsInput(for: expectedIdentity),
              let model,
              self.model === model else { return false }

        while let deferredContinuousInput =
            deferredContinuousInputs.first {
            guard deferredContinuousInput.identity == expectedIdentity,
                  deferredContinuousInput.owner === model else {
                failClosedContinuousInputAuthority()
                return false
            }
            deferredContinuousInputs.removeFirst()
#if DEBUG
            promoteDeferredInputFIFOProbeForTesting(
                deferredContinuousInput.input
            )
#endif
            guard acceptInput(
                deferredContinuousInput.input,
                owner: model,
                identity: expectedIdentity,
                protection: deferredContinuousInput.protection
            ) else {
                deferredContinuousInputs.insert(
                    deferredContinuousInput,
                    at: 0
                )
                failClosedContinuousInputAuthority()
                return false
            }
        }

        if let finalSample = rateLimitedContinuousInput {
            guard finalSample.identity == expectedIdentity,
                  finalSample.owner === model else {
                failClosedContinuousInputAuthority()
                return false
            }
            guard acceptInput(
                finalSample.input,
                owner: model,
                identity: expectedIdentity,
                protection: .terminal
            ) else {
                failClosedContinuousInputAuthority()
                return false
            }
            rateLimitedContinuousInput = nil
            continuousInputRatePolicy.recordProtectedFlush(
                capturedAtMonotonicNanoseconds:
                    DispatchTime.now().uptimeNanoseconds
            )
        }

        return drainProjectedTransformThresholds(
            model: model,
            expectedIdentity: expectedIdentity
        )
    }

    /// One large drag observation can clear several authored stages only when
    /// those stages share the contacted target. Replaying that exact final
    /// observation once per projected stage preserves their reducer order
    /// without retaining raw display-rate samples.
    private func drainProjectedTransformThresholds(
        model: JourneyModel,
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) -> Bool {
        guard let latestContinuousJournalInput,
              latestContinuousJournalInput.identity == expectedIdentity,
              latestContinuousJournalInput.owner === model,
              case .touch(.adjustTarget) =
                latestContinuousJournalInput.input else {
            return true
        }
        var replayCount = 0
        while replayCount < maximumDeferredContinuousInputs {
            guard case let .classified(
                .transformStage(stageIndex)
            ) = previewContinuousJournalInput(
                latestContinuousJournalInput.input,
                publishesVisualResponse: false
            ) else {
                return true
            }
            guard acceptInput(
                latestContinuousJournalInput.input,
                owner: model,
                identity: expectedIdentity,
                protection: .transformStage(stageIndex)
            ) else {
                failClosedContinuousInputAuthority()
                return false
            }
            replayCount += 1
        }
        failClosedContinuousInputAuthority()
        return false
    }

    private func enqueue(
        _ input: PendingInput,
        reservation: ChapterRuntimeInputReservationGate.Token,
        owner: JourneyModel,
        identity: ChapterRuntimeRouteIdentity,
        protection: ContinuousInputProtection
    ) {
        guard runtime != nil,
              self.identity == identity,
              model === owner,
              owner.ownsChapterRuntimeInputReservation(
                  reservation,
                  identity: identity
              ) else {
            owner.finishChapterRuntimeInputReservation(reservation)
            return
        }
        let actionToken = performanceRecorder?.beginAction(
            source: input.performanceSource,
            actionName: input.performanceActionName
        )
        if let actionToken { instrumentedActionTokens.insert(actionToken) }
        let instrumentedInput = InstrumentedInput(
            input: input,
            actionToken: actionToken,
            reservation: reservation,
            reservationOwner: owner,
            identity: identity,
            protection: protection
        )
        inputReservationOwners[reservation] = owner
#if DEBUG
        recordPressureJitterAcceptedInputForTesting(input)
        acceptInputFIFOProbeForTesting(input)
#endif
        guard !inputIsPending else {
            // Every input that crossed model admission retains FIFO authority.
            // Continuous transport pressure is bounded before reservation;
            // discrete touch and VoiceOver consequences are never replaced.
            pendingInputs.append(instrumentedInput)
            return
        }
        inputIsPending = true
        currentInput = instrumentedInput
        let generation = routeGeneration
        // The accepted-input chain retains its session until every model
        // reservation reaches perform's completion defer. finishInput clears
        // inputTask and breaks this finite cycle after the queue drains.
#if DEBUG
        inputFIFOProbeTrackedOrdinalForTesting =
            inputFIFOProbeOrdinalForTesting(input)
#endif
        inputTask = Task { @MainActor [self] in
            await perform(instrumentedInput, generation: generation)
            finishInput(generation: generation)
        }
    }

    private func perform(_ instrumentedInput: InstrumentedInput, generation: UInt64) async {
        let reservationOwner = instrumentedInput.reservationOwner
#if DEBUG
        let inputFIFOProbeOrdinal = inputFIFOProbeOrdinalForTesting(
            instrumentedInput.input
        )
        if let inputFIFOProbeOrdinal {
            beginInputFIFOProbePerformForTesting(inputFIFOProbeOrdinal)
        }
        defer {
            if let inputFIFOProbeOrdinal {
                completeInputFIFOProbePerformForTesting(
                    inputFIFOProbeOrdinal
                )
            }
        }
#endif
        defer {
            releaseChapterRuntimeInputReservation(
                instrumentedInput.reservation,
                owner: reservationOwner
            )
        }
#if DEBUG
        if inputFIFOProbeOrdinal != nil {
            await holdFirstInputFIFOProbePerformIfNeededForTesting()
        }
#endif
        guard let runtime,
              let identity,
              model === reservationOwner,
              identity == instrumentedInput.identity,
              reservationOwner.ownsChapterRuntimeInputReservation(
                  instrumentedInput.reservation,
                  identity: identity
              ) else {
            cancelPerformanceAction(instrumentedInput.actionToken)
            return
        }
        let model = reservationOwner
#if DEBUG
        recordPressureJitterPerformedInputForTesting(
            instrumentedInput.input
        )
        model.recordContentAuthorityBarrierInputMilestoneForTesting(
            "perform",
            identity: identity
        )
#endif
        do {
            let next: ChapterScenePresentation
            switch instrumentedInput.input {
            case let .touch(intent):
                next = try await model.submitChapterSceneTouch(
                    intent,
                    runtime: runtime,
                    identity: identity,
                    reservation: instrumentedInput.reservation,
                    alphaSampler: alphaSampler,
                    responsiveAudioIsUserAuthorized:
                        audioPlaybackState.authorizesPlayback
                )
            case let .semantic(elementID, action):
                next = try await model.submitChapterSceneVoiceOver(
                    elementID: elementID,
                    authoredAction: action,
                    runtime: runtime,
                    identity: identity,
                    reservation: instrumentedInput.reservation,
                    responsiveAudioIsUserAuthorized:
                        audioPlaybackState.authorizesPlayback
                )
            }
            guard routeGeneration == generation,
                  self.identity == identity,
                  self.runtime?.contentRevision == runtime.contentRevision else {
                cancelPerformanceAction(instrumentedInput.actionToken)
                return
            }
            guard try await prepareForInput(
                next,
                alphaSampler: alphaSampler,
                runtime: runtime,
                generation: generation,
                expectedIdentity: identity
            ) else { return }
            guard routeGeneration == generation,
                  self.identity == identity,
                  self.runtime?.contentRevision == runtime.contentRevision else {
                cancelPerformanceAction(instrumentedInput.actionToken)
                return
            }
            if let actionToken = instrumentedInput.actionToken {
                compositor.expectFirstCommandBufferCompletionProxy(for: actionToken)
            }
            presentation = next
#if DEBUG
            recordPressureJitterCompletedInputForTesting(
                instrumentedInput.input
            )
            model.recordContentAuthorityBarrierInputMilestoneForTesting(
                "presented",
                identity: identity
            )
            if case let .trace(progress)? = next.journeyState.activeChapter?
                .interaction?.progress {
                chapterInputResolutionDiagnosticForTesting =
                    "processed;traceReached=\(progress.reachedAnchorCount)"
            } else {
                chapterInputResolutionDiagnosticForTesting = "processed"
            }
#endif
            adoptResponsiveAudioPresentation(
                next,
                identity: identity
            )
            scheduleEphemeralResponseCleanupIfNeeded(
                for: next,
                runtime: runtime,
                model: model,
                identity: identity,
                generation: generation
            )
        } catch is CancellationError {
            cancelPerformanceAction(instrumentedInput.actionToken)
            return
        } catch let error as JourneyChapterRuntimeError
            where error == .routeAuthorityChanged {
            // A beat, repository or route swap invalidates this view session.
            // The new route identity constructs its own controller and audio.
            cancelPerformanceAction(instrumentedInput.actionToken)
            return
        } catch let error as SceneTouchActionResolverError {
            // A finger may enter or leave an authored hit region. That is local
            // resistance, not a broken chapter or a persistence failure.
#if DEBUG
            chapterInputResolutionDiagnosticForTesting =
                "resolver-error:\(String(reflecting: error))"
#endif
            cancelPerformanceAction(instrumentedInput.actionToken)
            return
        } catch let error as ChapterSceneRuntimeControllerError {
#if DEBUG
            chapterInputResolutionDiagnosticForTesting =
                "controller-error:\(String(reflecting: error))"
#endif
            cancelPerformanceAction(instrumentedInput.actionToken)
            return
        } catch let error as DurableJourneyCommitterError {
            cancelPerformanceAction(instrumentedInput.actionToken)
            if case .staleRevision = error { return }
            guard routeGeneration == generation else { return }
#if DEBUG
            failureDiagnosticForTesting =
                await model.persistenceRestoreDiagnosticForTesting()
                    ?? String(reflecting: error)
#endif
            failure = ProductionChapterRouteFailure(
                kind: .authorityUnavailable,
                assetAuthority: nil
            )
        } catch {
            cancelPerformanceAction(instrumentedInput.actionToken)
            guard routeGeneration == generation else { return }
#if DEBUG
            failureDiagnosticForTesting =
                await model.persistenceRestoreDiagnosticForTesting()
                    ?? String(reflecting: error)
#endif
            failure = ProductionChapterRouteFailure(
                kind: .authorityUnavailable,
                assetAuthority: nil
            )
        }
    }

    private func prepareForInput(
        _ candidate: ChapterScenePresentation,
        alphaSampler: SceneImageAlphaMaskSampler,
        runtime: VerifiedChapterSceneRuntime,
        generation: UInt64,
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) async throws -> Bool {
        let maskPrewarm = Task.detached(priority: .userInitiated) {
            if let source = candidate.framePlan.interactionSourceHitRegion {
                try alphaSampler.prewarm(source.selectedVariantAlphaMask)
            }
        }
        do {
            try await withTaskCancellationHandler {
                try await maskPrewarm.value
            } onCancel: {
                maskPrewarm.cancel()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
#if DEBUG
            failureDiagnosticForTesting = String(reflecting: error)
#endif
            publishFailure(
                ProductionChapterRouteFailure(
                    kind: .signedSceneAsset,
                    assetAuthority: runtime.assetFailureAuthority
                ),
                generation: generation,
                expectedIdentity: expectedIdentity
            )
            return false
        }
        try Task.checkCancellation()
        let state = await compositor.prepare(candidate.framePlan)
        guard routeGeneration == generation,
              identity == expectedIdentity else { return false }
        if case .sceneReady = state { return true }
        guard case let .failed(metalFailure) = state else {
            publishFailure(
                ProductionChapterRouteFailure(
                    kind: .rendererUnavailable,
                    assetAuthority: nil
                ),
                generation: generation,
                expectedIdentity: expectedIdentity
            )
            return false
        }
        switch metalFailure {
        case .assetVerificationFailed, .textureDecodeFailed:
#if DEBUG
            failureDiagnosticForTesting = String(reflecting: metalFailure)
#endif
            publishFailure(
                ProductionChapterRouteFailure(
                    kind: .signedSceneAsset,
                    assetAuthority: runtime.assetFailureAuthority
                ),
                generation: generation,
                expectedIdentity: expectedIdentity
            )
        default:
            publishFailure(
                ProductionChapterRouteFailure(
                    kind: .rendererUnavailable,
                    assetAuthority: nil
                ),
                generation: generation,
                expectedIdentity: expectedIdentity
            )
        }
        return false
    }

    private func publishFailure(
        _ candidate: ProductionChapterRouteFailure,
        generation: UInt64,
        expectedIdentity: ChapterRuntimeRouteIdentity
    ) {
        guard routeGeneration == generation, identity == expectedIdentity else { return }
        failure = candidate
        guard candidate.canReportPackageAssetFailure,
              let authority = candidate.assetAuthority,
              reportedAssetFailureAuthority != authority,
              let model else { return }
        reportedAssetFailureAuthority = authority
        Task { @MainActor [weak model] in
            _ = await model?.reportChapterAssetFailure(authority)
        }
    }

    private func adoptResponsiveAudioPresentation(
        _ presentation: ChapterScenePresentation,
        identity: ChapterRuntimeRouteIdentity,
        sameProcessLifecyclePhase:
            ResponsiveInteractionAudioPhase? = nil
    ) {
        let program = presentation.cursor.responsiveAudioProgram
        let nextResponsiveKey = program.map { program in
            ResponsiveAudioRouteKey(
                routeIdentity: identity,
                playbackLease: ResponsiveAudioPlaybackStartLease(
                    chapterID: identity.chapterID,
                    packageID: identity.packageID,
                    packageManifestDigest: identity.packageManifestDigest,
                    beatID: identity.beatID,
                    programID: program.id,
                    programScope: program.scope
                )
            )
        }
        let nextPrimaryKey = model?
            .primaryAudioTimelineID(for: identity)
            .map {
                PrimaryAudioRouteKey(
                    routeIdentity: identity,
                    timelineID: $0
                )
            }
        let bindingChanged = responsiveAudioRouteKey != nextResponsiveKey
            || primaryAudioRouteKey != nextPrimaryKey
        if bindingChanged {
            responsiveAudioPlaybackTask?.cancel()
            responsiveAudioPlaybackTask = nil
            pausePrimaryAudioForBoundary()
            responsiveAudioRouteKey = nextResponsiveKey
            primaryAudioRouteKey = nextPrimaryKey
            desiredResponsiveAudioPhase = nil
            clearRememberedResponsiveAudioLifecyclePhase()
            let primaryRequiresResume = nextPrimaryKey.map { key in
                model?.primaryAudioRequiresResume(
                    for: identity,
                    timelineID: key.timelineID
                ) == true
            } ?? false
            let hasPrimaryTimeline = nextPrimaryKey != nil
            let action = responsiveAudioPolicy.bind(
                chapterID: identity.chapterID,
                hasResponsiveAudio: nextResponsiveKey != nil
                    || hasPrimaryTimeline,
                restoredSessionIsActive: presentation.journeyState
                    .activeChapter?.responsiveAudioSessionIsActive == true
                    || primaryRequiresResume
            )
            audioPlaybackState = responsiveAudioPolicy.playbackState
#if DEBUG
            audioPlaybackStateDiagnosticForTesting =
                "audio-bind-generation-\(routeGeneration):"
                    + audioPlaybackState.rawValue
                    + ":\(responsiveAudioActivationDiagnosticForTesting)"
            primaryAudioDiagnosticForTesting = nextPrimaryKey.map {
                "bound;timeline=\($0.timelineID.rawValue);cursor=unknown"
            } ?? "unbound"
#endif
            if case let .startAuthorizedPlayback(attempt) = action {
                if let startEpoch = responsiveAudioAuthorizedStartEpoch {
                    if let nextResponsiveKey {
                        startResponsiveAudioPlayback(
                            attempt,
                            routeKey: nextResponsiveKey,
                            startEpoch: startEpoch
                        )
                    }
                    if nextResponsiveKey == nil,
                       let nextPrimaryKey {
                        startPrimaryAudioPlayback(
                            attempt,
                            routeKey: nextPrimaryKey,
                            startEpoch: startEpoch
                        )
                    }
                } else {
                    _ = responsiveAudioPolicy.completePlayback(
                        attempt,
                        didStart: false
                    )
                    audioPlaybackState = responsiveAudioPolicy.playbackState
                }
            }
        }
        guard program != nil else {
            desiredResponsiveAudioPhase = nil
            clearRememberedResponsiveAudioLifecyclePhase()
            return
        }
        let resolvedPhase = SceneResponsiveAudioPhaseResolver.phase(
            interactionPhase: presentation.journeyState.activeChapter?
                .interaction?.phase,
            feedback: presentation.interactionFeedback,
            directManipulation: presentation.directManipulation
        )
        guard let resolvedPhase else {
            // Completion belongs to the durable consequence timeline and may
            // never resurrect a transient phase from this view session.
            desiredResponsiveAudioPhase = nil
            clearRememberedResponsiveAudioLifecyclePhase()
            return
        }

        if presentation.directManipulation?.outcome == .cancelled {
            // A user-authored snap-back is an explicit return to waiting. The
            // automatic response cleanup is not: it only removes a short-lived
            // visual/audio response after an accepted action.
            clearRememberedResponsiveAudioLifecyclePhase()
        }

        let presentedPhase = sameProcessLifecyclePhase ?? resolvedPhase
        desiredResponsiveAudioPhase = presentedPhase
        switch presentedPhase {
        case .engaged, .resistance:
            lastMeaningfulResponsiveAudioPhaseForLifecycle = presentedPhase
        case .waiting:
            break
        }
    }

    private func clearRememberedResponsiveAudioLifecyclePhase() {
        lastMeaningfulResponsiveAudioPhaseForLifecycle = nil
        responsiveAudioPhaseCapturedAtSceneExit = nil
        responsiveAudioPhaseCaptureIdentity = nil
    }

    private func scheduleEphemeralResponseCleanupIfNeeded(
        for candidate: ChapterScenePresentation,
        runtime: VerifiedChapterSceneRuntime,
        model: JourneyModel,
        identity: ChapterRuntimeRouteIdentity,
        generation: UInt64
    ) {
        cancelEphemeralResponseCleanup()
        guard let token = candidate.ephemeralResponseCleanupToken else {
            return
        }
        let requestID = UUID()
        ephemeralResponseCleanupRequestID = requestID
        let delay = ephemeralResponseTiming.delayNanoseconds(for: token.kind)
        let sleeper = ephemeralResponseSleeper
        ephemeralResponseCleanupTask = Task {
            @MainActor [weak self, weak model] in
            defer {
                if let self,
                   self.ephemeralResponseCleanupRequestID == requestID {
                    self.ephemeralResponseCleanupTask = nil
                    self.ephemeralResponseCleanupRequestID = nil
                }
            }
            do {
                try await sleeper(delay)
                try Task.checkCancellation()
                guard let self, let model,
                      self.ephemeralResponseCleanupRequestID == requestID,
                      self.routeGeneration == generation,
                      self.identity == identity,
                      self.runtime?.controller === runtime.controller,
                      runtime.controller.presentation
                        .ephemeralResponseCleanupToken == token else {
                    return
                }
                guard let cleared = try await model
                    .clearChapterSceneEphemeralResponse(
                        matching: token,
                        runtime: runtime,
                        identity: identity,
                        responsiveAudioIsUserAuthorized:
                            self.audioPlaybackState.authorizesPlayback
                    ) else {
                    return
                }
                guard try await self.prepareForInput(
                    cleared,
                    alphaSampler: self.alphaSampler,
                    runtime: runtime,
                    generation: generation,
                    expectedIdentity: identity
                ) else { return }
                try Task.checkCancellation()
                guard self.ephemeralResponseCleanupRequestID == requestID,
                      self.routeGeneration == generation,
                      self.identity == identity,
                      self.runtime?.controller === runtime.controller else {
                    return
                }
                self.presentation = cleared
                self.adoptResponsiveAudioPresentation(
                    cleared,
                    identity: identity
                )
            } catch is CancellationError {
                return
            } catch let error as JourneyChapterRuntimeError
                where error == .routeAuthorityChanged {
                return
            } catch {
#if DEBUG
                self?.failureDiagnosticForTesting = String(reflecting: error)
#endif
                return
            }
        }
    }

    private func cancelEphemeralResponseCleanup() {
        ephemeralResponseCleanupTask?.cancel()
        ephemeralResponseCleanupTask = nil
        ephemeralResponseCleanupRequestID = nil
    }

    private func finishInput(generation: UInt64) {
        guard routeGeneration == generation else {
            inputTask = nil
            currentInput = nil
            inputIsPending = false
#if DEBUG
            inputFIFOProbeTrackedOrdinalForTesting = nil
#endif
            resolveUnstartedPendingInputs()
            return
        }
        currentInput = nil
        // Keep the current task as the authoritative occupied FIFO worker
        // while one entry from the bounded deferred transport buffer is
        // promoted. Otherwise
        // enqueue observes an idle session, starts a second perform task, and
        // the older pending input immediately overwrites its only task handle.
        _ = promoteDeferredContinuousInputIfNeeded()
        guard !pendingInputs.isEmpty else {
            inputTask = nil
            inputIsPending = false
#if DEBUG
            inputFIFOProbeTrackedOrdinalForTesting = nil
            finalizePressureJitterEnergyProbeIfNeededForTesting()
#endif
            if deactivationIsPending {
                finishDeactivation()
                return
            }
#if DEBUG
            if inputFIFOProbeIsEnabledForTesting,
               inputFIFOProbeCycleForTesting > 0 {
                inputFIFOProbePhaseForTesting = "drained"
                publishInputFIFOProbeDiagnosticForTesting()
            }
#endif
            return
        }
        let queued = pendingInputs.removeFirst()
        currentInput = queued
        let generation = routeGeneration
#if DEBUG
        inputFIFOProbeTrackedOrdinalForTesting =
            inputFIFOProbeOrdinalForTesting(queued.input)
#endif
        inputTask = Task { @MainActor [self] in
            await perform(queued, generation: generation)
            finishInput(generation: generation)
        }
    }

    private func resolveUnstartedPendingInputs() {
        let abandoned = pendingInputs
        pendingInputs.removeAll(keepingCapacity: false)
        for input in abandoned {
            cancelPerformanceAction(input.actionToken)
            releaseChapterRuntimeInputReservation(
                input.reservation,
                owner: input.reservationOwner
            )
        }
#if DEBUG
        discardDeferredInputFIFOProbeForTesting()
#endif
        deferredContinuousInputs.removeAll(keepingCapacity: false)
        resetContinuousInputSampling()
    }

    private func releaseChapterRuntimeInputReservation(
        _ reservation: ChapterRuntimeInputReservationGate.Token,
        owner: JourneyModel
    ) {
        inputReservationOwners[reservation] = nil
        owner.finishChapterRuntimeInputReservation(reservation)
#if DEBUG
        publishInputFIFOProbeDiagnosticForTesting()
#endif
    }

    private func cancelPerformanceAction(_ token: PerformanceActionToken?) {
        guard let token else { return }
        performanceRecorder?.cancelAction(token)
        instrumentedActionTokens.remove(token)
    }

    private func cancelOutstandingPerformanceActions() {
        for token in instrumentedActionTokens {
            performanceRecorder?.cancelAction(token)
        }
        instrumentedActionTokens.removeAll(keepingCapacity: false)
    }
}

private extension SceneTouchIntent {
    var performanceActionName: String {
        switch self {
        case .trace: "trace"
        case .allocateContact: "allocate-contact"
        case .allocateCarry: "allocate-carry"
        case .allocateDrop: "allocate-drop"
        case .allocateReturn: "allocate-return"
        case .assembleContact: "assemble-contact"
        case .assembleLift: "assemble-lift"
        case .assembleCarry: "assemble-carry"
        case .assembleSlotApproach: "assemble-slot-approach"
        case .assembleDrop: "assemble-drop"
        case .assembleCancel: "assemble-cancel"
        case .activateTarget: "activate-target"
        case .adjustTarget: "adjust-target"
        case .holdPressure: "hold-pressure"
        case .commitAllocation: "commit-allocation"
        }
    }
}

@MainActor
final class ChapterReviewRouteSession: ObservableObject {
    @Published private(set) var renderPlan: ChapterReviewRenderPlan?
    @Published private(set) var playbackState =
        ChapterAudioPlaybackState.inactive
    @Published private(set) var soundIsEnabledForPresentation = true
    @Published private(set) var failure: ProductionChapterRouteFailure?

    let compositor = SceneMetalCompositor()
    private final class ReviewAudioComponentPlayback {
        let component: AuthoredAudioComponent
        let timeline: AudioTimeline
        let transport: NativeTimelineTransport

        init(
            component: AuthoredAudioComponent,
            timeline: AudioTimeline,
            transport: NativeTimelineTransport
        ) {
            self.component = component
            self.timeline = timeline
            self.transport = transport
        }
    }

    private var audioBinding: ChapterReviewAudioBinding?
    private var audioComponents: [
        AuthoredAudioComponent: ReviewAudioComponentPlayback
    ] = [:]
    private var usesVerifiedRoleSeparation = false
    private var audioSessionLifecycleObserver:
        JourneyAudioSessionLifecycleObserver?
    private var generation: UInt64 = 0
    private var physicalResumeIsRequired = false
    private var voiceOverSuppressionIsActive = false
    private var narrationRequiresExplicitVoiceOverResume = false
    private var narrationIsEnabledForPresentation = true
    private var assetFailureAuthority: PackageAssetFailureAuthority?

    func activate(
        model: JourneyModel,
        viewportCropID: String,
        reduceMotion: Bool,
        voiceOverIsRunning: Bool
    ) async {
        generation &+= 1
        let activationGeneration = generation
        stopAudio()
        physicalResumeIsRequired = false
        voiceOverSuppressionIsActive = voiceOverIsRunning
        narrationRequiresExplicitVoiceOverResume = false
        narrationIsEnabledForPresentation = model.experiencePreferences
            .narrationEnabled
        soundIsEnabledForPresentation =
            model.experiencePreferences.soundEnabled
        startAudioSessionLifecycleObservation()
        renderPlan = nil
        failure = nil
        assetFailureAuthority = model.chapterReviewProjection.flatMap {
            model.chapterAssetFailureAuthority(
                chapterID: $0.selected.chapter.id,
                packageID: $0.selected.packageID
            )
        }
        do {
            let plan = try await model.makeChapterReviewRenderPlan(
                viewportCropID: viewportCropID,
                reduceMotion: reduceMotion
            )
            try Task.checkCancellation()
            guard generation == activationGeneration else { return }
            if case .notConfigured = compositor.state {
                _ = compositor.configure()
            }
            guard case .readyForScene = compositor.state else {
                throw JourneyChapterRuntimeError.routeAuthorityUnavailable
            }
            let prepared = await compositor.prepare(plan.framePlan)
            guard generation == activationGeneration else { return }
            switch prepared {
            case .sceneReady:
                break
            case let .failed(metalFailure):
                let kind: ProductionChapterRouteFailureKind = switch metalFailure {
                case .assetVerificationFailed, .textureDecodeFailed:
                    .signedSceneAsset
                default:
                    .rendererUnavailable
                }
                publishFailure(
                    ProductionChapterRouteFailure(
                        kind: kind,
                        assetAuthority: kind == .signedSceneAsset
                            ? assetFailureAuthority : nil
                    ),
                    model: model,
                    generation: activationGeneration
                )
                return
            default:
                publishFailure(
                    ProductionChapterRouteFailure(
                        kind: .rendererUnavailable,
                        assetAuthority: nil
                    ),
                    model: model,
                    generation: activationGeneration
                )
                return
            }
            renderPlan = plan
            do {
                audioBinding = try model.chapterReviewAudioBinding()
            } catch let error as OfflineAudioAssetResolutionError {
#if DEBUG
                _ = error
#endif
                publishFailure(
                    ProductionChapterRouteFailure(
                        kind: .signedAudioAsset,
                        assetAuthority: assetFailureAuthority
                    ),
                    model: model,
                    generation: activationGeneration
                )
                return
            }
            playbackState = audioBinding == nil ? .inactive : .resumeRequired
            let hasEntryGrant = model.consumeChapterReviewAudioEntryGrant(
                chapterID: plan.cursor.chapter.id,
                beatID: plan.cursor.beat.id
            )
            if hasEntryGrant,
               model.experiencePreferences.soundEnabled,
               !physicalResumeIsRequired {
                await startSound(
                    model: model,
                    suppressesNarration: voiceOverSuppressionIsActive,
                    generation: activationGeneration
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == activationGeneration else { return }
            stopAudio()
            publishFailure(
                ProductionChapterRouteFailure(
                    kind: error is SceneAssetInventoryError
                        ? .signedSceneAsset : .authorityUnavailable,
                    assetAuthority: error is SceneAssetInventoryError
                        ? assetFailureAuthority : nil
                ),
                model: model,
                generation: activationGeneration
            )
        }
    }

    func toggleSound(
        model: JourneyModel,
        voiceOverIsRunning: Bool
    ) {
        voiceOverSuppressionIsActive = voiceOverIsRunning
        if playbackState == .playing {
            soundIsEnabledForPresentation = false
            pauseSound()
            model.setSoundEnabled(false)
            return
        }
        guard playbackState != .starting,
              playbackState != .inactive else { return }
        physicalResumeIsRequired = false
        soundIsEnabledForPresentation = true
        model.setSoundEnabled(true)
        if !audioComponents.isEmpty {
            resumePreparedComponents(
                model: model,
                suppressesNarration: voiceOverIsRunning,
                authorizesHeldNarration: !voiceOverIsRunning
            )
        } else {
            let expectedGeneration = generation
            Task { @MainActor [weak self, weak model] in
                guard let self, let model else { return }
                await self.startSound(
                    model: model,
                    suppressesNarration: voiceOverIsRunning,
                    generation: expectedGeneration
                )
            }
        }
    }

    func pauseForVoiceOver() {
        voiceOverSuppressionIsActive = true
        guard playbackState == .playing
                || playbackState == .starting else { return }
        narrationRequiresExplicitVoiceOverResume =
            narrationIsEnabledForPresentation
        guard let component = AuthoredAudioPlaybackBoundaryPolicy
                .componentToPauseForVoiceOver(
                    available: Set(audioComponents.keys),
                    usesVerifiedRoleSeparation:
                        usesVerifiedRoleSeparation
                ),
              let narration = audioComponents[component],
              narration.transport.state == .playing else { return }
        do {
            _ = try narration.transport.pause()
        } catch {
            // The whole review mix pauses if the role boundary cannot be
            // captured exactly.
            pauseSound()
            return
        }
        playbackState = audioComponents.values.contains(where: {
            $0.transport.state == .playing
        }) ? .playing : .resumeRequired
    }

    func voiceOverDidStop() {
        voiceOverSuppressionIsActive = false
        guard narrationRequiresExplicitVoiceOverResume else { return }
        // Review also requires the visible Resume action; VoiceOver ending
        // cannot start speech on its own, even while the non-speaking bed is
        // still audible.
        guard playbackState != .starting else { return }
        playbackState = .resumeRequired
    }

    func requireExplicitResume(
        for reason: ResponsiveAudioSuspensionReason
    ) {
        physicalResumeIsRequired = true
        let transportIsRunning = audioComponents.values.contains {
            $0.transport.state == .playing
        }
        guard playbackState == .playing
                || playbackState == .starting
                || transportIsRunning else { return }
        if playbackState == .starting {
            generation &+= 1
        }
        var pauseFailed = false
        for component in audioComponents.values {
            do {
                _ = try component.transport.pause(for: reason)
            } catch {
                pauseFailed = true
                break
            }
        }
        if pauseFailed {
            stopAudioComponents()
        }
        playbackState = audioBinding == nil ? .inactive : .resumeRequired
    }

    func requireExplicitResume(
        forPhysicalPause reason: ResponsiveAudioPhysicalPauseReason
    ) {
        let suspensionReason: ResponsiveAudioSuspensionReason = switch reason {
        case .sceneInactive: .sceneInactive
        case .sceneBackground: .sceneBackground
        case .interruption, .cursorDurabilityFailure: .interruption
        case .audioRouteChange: .routeChange
        }
        requireExplicitResume(for: suspensionReason)
    }

    func prepareForNavigation() {
        generation &+= 1
        stopAudioSessionLifecycleObservation()
        stopAudio()
        compositor.purgeTextureCache()
    }

    func deactivate() {
        generation &+= 1
        stopAudioSessionLifecycleObservation()
        stopAudio()
        renderPlan = nil
        compositor.purgeTextureCache()
    }

    private func startSound(
        model: JourneyModel,
        suppressesNarration: Bool,
        generation expectedGeneration: UInt64
    ) async {
        guard let audioBinding,
              generation == expectedGeneration else { return }
        playbackState = .starting
        do {
            let paths = Array(Set(
                audioBinding.timeline.events
                    .filter { $0.role != .silence }
                    .compactMap(\.assetPath)
            )).sorted()
            try await OfflineAudioAssetPrewarmer.prewarm(
                paths: paths,
                resolver: audioBinding.resolver
            )
            try Task.checkCancellation()
            guard generation == expectedGeneration else { return }
            var preferences = model.experiencePreferences
            preferences.soundEnabled = true
            let componentTimelines: [
                AuthoredAudioComponent: AudioTimeline
            ]
            let verifiedRoleSeparation: Bool
            do {
                componentTimelines = try AuthoredAudioRoleSeparation(
                    validating: audioBinding.timeline
                ).reviewComponentTimelines
                verifiedRoleSeparation = true
            } catch {
                componentTimelines = [
                    .wholeMix: AudioTimeline(
                        id: audioBinding.timeline.id,
                        sampleRate: audioBinding.timeline.sampleRate,
                        events: audioBinding.timeline.events,
                        haptics: []
                    ),
                ]
                verifiedRoleSeparation = false
            }
            stopAudioComponents()
            usesVerifiedRoleSeparation = verifiedRoleSeparation
            narrationIsEnabledForPresentation = preferences.narrationEnabled
            let availableComponents = Set(componentTimelines.keys)
            let narrationIsHeldForVoiceOver = preferences.narrationEnabled
                && (suppressesNarration
                    || voiceOverSuppressionIsActive
                    || narrationRequiresExplicitVoiceOverResume)
            let heldVoiceOverComponent = narrationIsHeldForVoiceOver
                ? AuthoredAudioPlaybackBoundaryPolicy
                    .componentToPauseForVoiceOver(
                        available: availableComponents,
                        usesVerifiedRoleSeparation:
                            verifiedRoleSeparation
                    )
                : nil
            var retainedComponents = AuthoredAudioPlaybackBoundaryPolicy
                .componentsToPlay(
                    available: availableComponents,
                    usesVerifiedRoleSeparation:
                        verifiedRoleSeparation,
                    suppressesNarration: narrationIsHeldForVoiceOver
                        || !preferences.narrationEnabled,
                    narrationIsEnabled: preferences.narrationEnabled
                )
            if let heldVoiceOverComponent {
                retainedComponents.insert(heldVoiceOverComponent)
                narrationRequiresExplicitVoiceOverResume = true
            }
            guard !retainedComponents.isEmpty else {
                playbackState = .inactive
                return
            }
            var prepared: [
                AuthoredAudioComponent: ReviewAudioComponentPlayback
            ] = [:]
            for component in [
                AuthoredAudioComponent.nonSpeaking,
                .narration,
                .wholeMix,
            ] {
                guard retainedComponents.contains(component),
                      let timeline = componentTimelines[component] else {
                    continue
                }
                let transport = NativeTimelineTransport(
                    preferences: preferences
                )
                try transport.prepare(
                    timeline: timeline,
                    cursorSample: 0,
                    resolver: audioBinding.resolver
                )
                prepared[component] = ReviewAudioComponentPlayback(
                    component: component,
                    timeline: timeline,
                    transport: transport
                )
            }
            audioComponents = prepared
            for component in [
                AuthoredAudioComponent.nonSpeaking,
                .narration,
                .wholeMix,
            ] {
                guard let prepared = prepared[component] else { continue }
                try prepared.transport.configureEndOfTimelineBoundary(
                    resolver: audioBinding.resolver
                ) { [weak self, weak transport = prepared.transport] snapshot in
                    guard let transport else { return }
                    self?.completeSound(
                        component: component,
                        transport: transport,
                        snapshot: snapshot,
                        generation: expectedGeneration
                    )
                }
            }
            resumePreparedComponents(
                model: model,
                suppressesNarration: voiceOverSuppressionIsActive,
                authorizesHeldNarration: false
            )
            guard generation == expectedGeneration else {
                stopAudioComponents()
                return
            }
        } catch is CancellationError {
            return
        } catch is OfflineAudioAssetResolutionError {
            guard generation == expectedGeneration else { return }
            publishFailure(
                ProductionChapterRouteFailure(
                    kind: .signedAudioAsset,
                    assetAuthority: assetFailureAuthority
                ),
                model: model,
                generation: expectedGeneration
            )
        } catch {
            guard generation == expectedGeneration else { return }
            stopAudioComponents()
            playbackState = .resumeRequired
        }
    }

    private func completeSound(
        component: AuthoredAudioComponent,
        transport: NativeTimelineTransport,
        snapshot: NativeTimelineTransportSnapshot,
        generation expectedGeneration: UInt64
    ) {
        guard generation == expectedGeneration,
              audioComponents[component]?.transport === transport,
              snapshot.timelineID == audioBinding?.timeline.id,
              !snapshot.isPlaying else { return }
        audioComponents[component] = nil
        if audioComponents.values.contains(where: {
            $0.transport.state == .playing
        }) {
            playbackState = .playing
        } else {
            playbackState = audioBinding == nil
                ? .inactive : .resumeRequired
        }
    }

    private func pauseSound() {
        var pauseFailed = false
        for component in audioComponents.values {
            do {
                _ = try component.transport.pause()
            } catch {
                pauseFailed = true
                break
            }
        }
        if pauseFailed { stopAudioComponents() }
        playbackState = audioBinding == nil ? .inactive : .resumeRequired
    }

    private func resumePreparedComponents(
        model: JourneyModel,
        suppressesNarration: Bool,
        authorizesHeldNarration: Bool
    ) {
        var preferences = model.experiencePreferences
        preferences.soundEnabled = true
        if authorizesHeldNarration, !suppressesNarration {
            narrationRequiresExplicitVoiceOverResume = false
        }
        do {
            var runningCount = 0
            let componentsToPlay = AuthoredAudioPlaybackBoundaryPolicy
                .componentsToPlay(
                    available: Set(audioComponents.keys),
                    usesVerifiedRoleSeparation:
                        usesVerifiedRoleSeparation,
                    suppressesNarration: suppressesNarration
                        || narrationRequiresExplicitVoiceOverResume
                        || !preferences.narrationEnabled,
                    narrationIsEnabled: preferences.narrationEnabled
                )
            for component in [
                AuthoredAudioComponent.nonSpeaking,
                .narration,
                .wholeMix,
            ] {
                guard let playback = audioComponents[component] else {
                    continue
                }
                guard componentsToPlay.contains(component) else { continue }
                playback.transport.applyPreferences(preferences)
                switch playback.transport.state {
                case .prepared, .paused:
                    try playback.transport.play()
                case .playing:
                    break
                case .idle, .completed:
                    throw NativeTimelineTransportError.notPrepared
                }
                runningCount += 1
            }
            playbackState = narrationRequiresExplicitVoiceOverResume
                && !voiceOverSuppressionIsActive
                ? .resumeRequired
                : (runningCount > 0 ? .playing : .resumeRequired)
        } catch {
            pauseSound()
        }
    }

    private func stopAudioComponents() {
        for component in audioComponents.values {
            component.transport.stop()
        }
        audioComponents.removeAll(keepingCapacity: false)
        usesVerifiedRoleSeparation = false
    }

    private func stopAudio() {
        stopAudioComponents()
        audioBinding = nil
        physicalResumeIsRequired = false
        narrationRequiresExplicitVoiceOverResume = false
        playbackState = .inactive
    }

    private func publishFailure(
        _ candidate: ProductionChapterRouteFailure,
        model: JourneyModel,
        generation expectedGeneration: UInt64
    ) {
        guard generation == expectedGeneration else { return }
        stopAudio()
        failure = candidate
    }

    private func startAudioSessionLifecycleObservation() {
        guard audioSessionLifecycleObserver == nil else { return }
        let observer = JourneyAudioSessionLifecycleObserver {
            [weak self] event in
            switch event {
            case .interruptionBegan:
                self?.requireExplicitResume(for: .interruption)
            case .routeChanged:
                self?.requireExplicitResume(for: .routeChange)
            case .interruptionEnded:
                // A system interruption ending is not user authorization to
                // restart authored review audio.
                break
            }
        }
        audioSessionLifecycleObserver = observer
        observer.start()
    }

    private func stopAudioSessionLifecycleObservation() {
        audioSessionLifecycleObserver?.stop()
        audioSessionLifecycleObserver = nil
    }
}

struct ChapterReviewView: View {
    @ObservedObject var model: JourneyModel
    @ObservedObject var session: ChapterReviewRouteSession
    @Environment(\.accessibilityVoiceOverEnabled)
    private var voiceOverIsRunning
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var sceneListIsPresented = false

    private var projection: ChapterReviewProjection? {
        model.chapterReviewProjection
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                SceneMetalSurface(
                    compositor: session.compositor,
                    onReturnToRoad: {
                        session.prepareForNavigation()
                        model.closeReviewAndShowWorld()
                    }
                )
                .accessibilityHidden(true)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.18), .black.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                if let projection,
                   let plan = session.renderPlan,
                   plan.cursor.beat.id == projection.selected.beat.id {
                    ChapterReviewNarrativeSurface(
                        projection: projection,
                        initialReadingAnchor:
                            model.state.chapterReview?.readingAnchor,
                        persistReadingAnchor: {
                            model.setReviewReadingAnchor($0)
                        },
                        returnsToCurrent: {
                            if case .chapter = model.state.route {
                                return true
                            }
                            return false
                        }(),
                        move: { beatID in
                            guard !model.chapterTransitionIsPending else {
                                return
                            }
                            model.moveBeatReview(to: beatID)
                            guard model.chapterTransitionIsPending else {
                                return
                            }
                            session.prepareForNavigation()
                        },
                        close: {
                            session.prepareForNavigation()
                            model.closeBeatReview()
                        },
                        transitionIsPending:
                            model.chapterTransitionIsPending
                    )
                    .id(projection.selected.beat.id)
                    .frame(
                        maxHeight: geometry.size.height
                            * (dynamicTypeSize.isAccessibilitySize
                                ? 0.72 : 0.44),
                        alignment: .bottom
                    )

                    ChapterReviewChromeHeader(
                        projection: projection,
                        playbackState: session.playbackState,
                        soundEnabled:
                            model.experiencePreferences.soundEnabled
                                && session.soundIsEnabledForPresentation,
                        controlsAreDisabled:
                            model.chapterTransitionIsPending,
                        sceneListIsPresented: sceneListIsPresented,
                        road: {
                            session.prepareForNavigation()
                            model.closeReviewAndShowWorld()
                        },
                        openVisitedScenes: {
                            sceneListIsPresented = true
                        },
                        toggleSound: {
                            session.toggleSound(
                                model: model,
                                voiceOverIsRunning:
                                    voiceOverIsRunning
                            )
                        }
                    )
                    .padding(.top, geometry.safeAreaInsets.top + 6)
                    .padding(.horizontal, 12)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                } else if let failure = session.failure {
                    ChapterRouteFailureSurface(
                        message: failure.message,
                        redownload: failure.canOfferRedownload
                            ? {
                                guard let projection,
                                      let authority = failure.assetAuthority else {
                                    return
                                }
                                model.requestChapterRedownload(
                                    chapterID: projection.selected.chapter.id,
                                    packageID: projection.selected.packageID,
                                    assetFailureAuthority: authority
                                )
                                model.closeReviewAndShowWorld()
                            } : nil,
                        returnTitle: {
                            if case .chapter = model.state.route {
                                return "Return to current"
                            }
                            return "Done"
                        }(),
                        returnToRoad: {
                            model.closeBeatReview()
                        }
                    )
                } else {
                    ProgressView()
                        .tint(Color(red: 0.82, green: 0.64, blue: 0.34))
                        .accessibilityLabel("Opening completed scene")
                }
            }
            .background(Color(red: 0.012, green: 0.015, blue: 0.016))
            .ignoresSafeArea()
        }
        .onChange(of: voiceOverIsRunning) { _, isRunning in
            if isRunning {
                session.pauseForVoiceOver()
            } else {
                session.voiceOverDidStop()
            }
        }
        .onChange(of: model.responsiveAudioPhysicalPauseEvent?.generation) {
            _, _ in
            guard let event = model.responsiveAudioPhysicalPauseEvent else {
                return
            }
            session.requireExplicitResume(forPhysicalPause: event.reason)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willResignActiveNotification
            )
        ) { _ in
            session.requireExplicitResume(for: .sceneInactive)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                break
            case .inactive:
                session.requireExplicitResume(for: .sceneInactive)
            case .background:
                session.requireExplicitResume(for: .sceneBackground)
            @unknown default:
                session.requireExplicitResume(for: .sceneInactive)
            }
        }
        .onDisappear { session.deactivate() }
        .sheet(isPresented: $sceneListIsPresented) {
            if let projection {
                ChapterReviewVisitedScenesSheet(
                    projection: projection,
                    openReview: { beatID in
                        sceneListIsPresented = false
                        guard beatID != projection.selected.beat.id else {
                            return
                        }
                        guard !model.chapterTransitionIsPending else { return }
                        model.moveBeatReview(to: beatID)
                        guard model.chapterTransitionIsPending else { return }
                        session.prepareForNavigation()
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct ChapterReviewChromeHeader: View {
    let projection: ChapterReviewProjection
    let playbackState: ChapterAudioPlaybackState
    let soundEnabled: Bool
    let controlsAreDisabled: Bool
    let sceneListIsPresented: Bool
    let road: () -> Void
    let openVisitedScenes: () -> Void
    let toggleSound: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @AccessibilityFocusState private var visitedScenesIsFocused: Bool

    private var soundLabel: String {
        switch playbackState {
        case .playing: "Turn sound off"
        case .starting: "Starting sound"
        case .inactive: "Sound unavailable"
        case .ready, .resumeRequired:
            soundEnabled ? "Resume sound" : "Turn sound on"
        }
    }

    private var visitedScenesAccessibilityLabel: String {
        let title = projection.selected.chapter.title.launchEnglish
        let movement = projection.selected.arcIndex + 1
        let scene = projection.selected.absoluteBeatIndex + 1
        return "\(title), Movement \(movement), scene \(scene) "
            + "of \(projection.totalBeatCount). Open visited scenes."
    }

    var body: some View {
        HStack(spacing: 8) {
            Button("Road", action: road)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(
                    Color(red: 0.88, green: 0.72, blue: 0.43)
                )
                .frame(minWidth: 58, minHeight: 44)
                .background(.black.opacity(0.74), in: Capsule())
                .disabled(controlsAreDisabled)
                .accessibilityIdentifier("chapter-review-road")

            Button(action: openVisitedScenes) {
                VStack(spacing: 3) {
                    Text(projection.selected.chapter.title.launchEnglish)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            Color(red: 0.72, green: 0.70, blue: 0.65)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(projection.selected.arc.title.launchEnglish)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(
                            Color(red: 0.94, green: 0.92, blue: 0.86)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    ChapterMovementProgressTrace(
                        progress: Double(
                            projection.selected.absoluteBeatIndex + 1
                        ) / Double(max(projection.totalBeatCount, 1)),
                        separators: movementSeparators,
                        increasedContrast: contrast == .increased
                    )
                    .frame(height: 4)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.black.opacity(0.74), in: Capsule())
                .overlay {
                    Capsule().stroke(
                        .white.opacity(
                            contrast == .increased ? 0.30 : 0.12
                        ),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(controlsAreDisabled)
            .accessibilityLabel(visitedScenesAccessibilityLabel)
            .accessibilityFocused($visitedScenesIsFocused)
            .accessibilityIdentifier("chapter-review-visited-scenes-open")

            Button(action: toggleSound) {
                ZStack {
                    if playbackState == .starting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(red: 0.86, green: 0.70, blue: 0.40))
                    } else {
                        Image(
                            systemName: playbackState == .playing
                                ? "speaker.wave.2.fill"
                                : (soundEnabled
                                    ? "speaker.wave.2" : "speaker.slash.fill")
                        )
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            Color(red: 0.86, green: 0.70, blue: 0.40)
                        )
                    }
                }
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.74), in: Circle())
                .overlay {
                    Circle().stroke(
                        .white.opacity(
                            contrast == .increased ? 0.34 : 0.12
                        ),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(
                controlsAreDisabled
                    || playbackState == .starting
                    || playbackState == .inactive
            )
            .accessibilityLabel(soundLabel)
            .accessibilityIdentifier("chapter-review-sound-control")
        }
        // Chapter chrome stays spatially stable while the narrative adopts
        // the full accessibility scale in its linear, scrollable region.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onChange(of: sceneListIsPresented) { _, isPresented in
            if !isPresented { visitedScenesIsFocused = true }
        }
    }

    private var movementSeparators: [Double] {
        let total = max(projection.totalBeatCount, 1)
        var consumed = 0
        return projection.selected.chapter.arcs.dropLast().map { arc in
            consumed += arc.beats.count
            return Double(consumed) / Double(total)
        }
    }
}

private struct ChapterReviewNarrativeSurface: View {
    let projection: ChapterReviewProjection
    let persistReadingAnchor: (String?) -> Void
    let returnsToCurrent: Bool
    let move: (BeatID) -> Void
    let close: () -> Void
    let transitionIsPending: Bool
    @State private var readingAnchor: String?
    @Environment(\.colorSchemeContrast) private var contrast
    @AccessibilityFocusState private var headingIsFocused: Bool

    init(
        projection: ChapterReviewProjection,
        initialReadingAnchor: String?,
        persistReadingAnchor: @escaping (String?) -> Void,
        returnsToCurrent: Bool,
        move: @escaping (BeatID) -> Void,
        close: @escaping () -> Void,
        transitionIsPending: Bool
    ) {
        self.projection = projection
        self.persistReadingAnchor = persistReadingAnchor
        self.returnsToCurrent = returnsToCurrent
        self.move = move
        self.close = close
        self.transitionIsPending = transitionIsPending
        _readingAnchor = State(initialValue: initialReadingAnchor)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Completed scene")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(
                            Color(red: 0.74, green: 0.63, blue: 0.43)
                        )
                    Text(
                        projection.selected.beat.narrative.heading
                            .launchEnglish
                    )
                    .font(.system(.title, design: .serif))
                    .foregroundStyle(
                        Color(red: 0.95, green: 0.93, blue: 0.87)
                    )
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingIsFocused)
                    ForEach(
                        projection.selected.beat.narrative.paragraphs
                    ) { paragraph in
                        Text(paragraph.launchEnglish)
                            .font(.system(.body, design: .serif))
                            .lineSpacing(5)
                            .foregroundStyle(
                                Color(red: 0.84, green: 0.83, blue: 0.79)
                            )
                            .id(paragraph.id.rawValue)
                    }
                    if let summary = terminalResultSummary {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(
                                Color(red: 0.72, green: 0.70, blue: 0.65)
                            )
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 18)
            }
            .scrollPosition(id: $readingAnchor, anchor: .top)
            .scrollIndicators(.hidden)

            Divider().overlay(
                .white.opacity(contrast == .increased ? 0.28 : 0.10)
            )

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        if let beatID = projection.previousBeatID {
                            move(beatID)
                        }
                    } label: {
                        Text("Previous")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        projection.previousBeatID == nil
                            || transitionIsPending
                    )
                    .accessibilityIdentifier("chapter-review-previous")

                    Button {
                        if let beatID = projection.nextBeatID {
                            move(beatID)
                        }
                    } label: {
                        Text("Next")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        projection.nextBeatID == nil
                            || transitionIsPending
                    )
                    .accessibilityIdentifier("chapter-review-next")
                }

                Button {
                    close()
                } label: {
                    Text(returnsToCurrent ? "Return to current" : "Done")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.82, green: 0.64, blue: 0.34))
                .foregroundStyle(.black)
                .disabled(transitionIsPending)
                .accessibilityIdentifier("chapter-review-close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .safeAreaPadding(.bottom, 8)
        }
        .background(
            .black.opacity(contrast == .increased ? 0.92 : 0.78)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "chapter-review-\(projection.selected.beat.id)"
        )
        .onAppear {
            if readingAnchor == nil { headingIsFocused = true }
        }
        .onChange(of: readingAnchor) { _, anchor in
            persistReadingAnchor(anchor)
        }
    }

    private var terminalResultSummary: String? {
        guard let interaction = projection.selected.record.interaction else {
            return nil
        }
        switch interaction.progress {
        case let .trace(progress):
            return "Completed path: \(progress.reachedAnchorCount) points."
        case let .allocate(progress):
            let values = progress.allocations.map {
                "\($0.destinationID): \($0.units)"
            }.joined(separator: ", ")
            return "Final allocation: \(values)."
        case let .assemble(progress):
            return "Final assembly: \(progress.placements.count) placements."
        case let .pressure(progress):
            return "Final balance held for \(progress.stableMillis) milliseconds."
        case let .transform(progress):
            return "Completed transformation: \(progress.completedStageCount) stages."
        }
    }
}

struct ProductionChapterView: View {
    @ObservedObject var model: JourneyModel
    @ObservedObject var session: ProductionChapterRouteSession
    let identity: ChapterRuntimeRouteIdentity
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled)
    private var voiceOverIsRunning
    @State private var continuousGestureCancellationEpoch: UInt64 = 0
    @State private var sceneListIsPresented = false

    private var presentation: ChapterScenePresentation? {
        session.presentation(for: identity)
    }

    private var controlsAreDisabled: Bool {
        model.chapterTransitionIsPending
            || session.inputIsPending
            || session.lifecyclePresentationRefreshIsPending
            || session.audioPlaybackState == .starting
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Color.black.opacity(0.001)
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Chapter runtime")
                    .accessibilityIdentifier("chapter-runtime-\(identity.chapterID)")

#if DEBUG
                if session.pressureHoldLifecycleProbeIsEnabledForTesting {
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Pressure hold lifecycle probe")
                        .accessibilityValue(
                            "attempts=\(session.pressureHoldAttemptCountForTesting)"
                        )
                        .accessibilityIdentifier(
                            "pressure-hold-lifecycle-diagnostic"
                        )
                        .allowsHitTesting(false)

                    Button("Start pressure hold lifecycle probe") {
                        NotificationCenter.default.post(
                            name: .pressureHoldLifecycleProbeStart,
                            object: nil
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(width: 300, height: 44)
                    .accessibilityIdentifier(
                        "pressure-hold-lifecycle-start"
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .padding(.top, geometry.safeAreaInsets.top + 64)
                    .zIndex(2_000)
                }

                if session.continuousInputEnergyProbeIsEnabledForTesting {
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Continuous input energy probe")
                        .accessibilityValue(
                            session.continuousInputEnergyDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "continuous-input-energy-diagnostic"
                        )
                        .allowsHitTesting(false)

                    Button("Run continuous input energy probe") {
                        session.runContinuousInputEnergyProbeForTesting(
                            expectedIdentity: identity
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(width: 280, height: 44)
                    .disabled(
                        session.inputIsPending
                            || session.lifecyclePresentationRefreshIsPending
                    )
                    .accessibilityIdentifier(
                        "continuous-input-energy-run"
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .padding(.top, geometry.safeAreaInsets.top + 64)
                    .zIndex(2_000)
                }

                if session.inputFIFOProbeIsEnabledForTesting {
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Chapter input FIFO probe")
                        .accessibilityValue(
                            session.inputFIFOProbeDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "chapter-input-fifo-probe-diagnostic"
                        )
                        .allowsHitTesting(false)

                    VStack(spacing: 8) {
                        if session.inputFIFOProbeIsHoldingForTesting {
                            Button("Cancel FIFO probe route") {
                                session
                                    .cancelRouteDuringInputFIFOProbeForTesting()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .frame(width: 240, height: 44)
                            .accessibilityIdentifier(
                                "chapter-input-fifo-cancel-route"
                            )

                            Button("Release FIFO probe") {
                                session.releaseInputFIFOProbeForTesting()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .frame(width: 240, height: 44)
                            .accessibilityIdentifier(
                                "chapter-input-fifo-release"
                            )
                        } else {
                            Button("Saturate chapter input FIFO") {
                                session.startInputFIFOProbeForTesting(
                                    expectedIdentity: identity
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .frame(width: 240, height: 44)
                            .disabled(
                                session.inputIsPending
                                    || session
                                        .lifecyclePresentationRefreshIsPending
                            )
                            .accessibilityIdentifier(
                                "chapter-input-fifo-saturate"
                            )
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .padding(.top, geometry.safeAreaInsets.top + 64)
                    .zIndex(2_000)
                }
#endif

                if let presentation {
                    let interactionIsIncomplete =
                        presentation.cursor.beat.interaction != nil
                        && presentation.journeyState.activeChapter?
                            .interaction?.phase != .complete
                    let narrativeHeightFraction = dynamicTypeSize
                        .isAccessibilitySize
                        ? 0.72
                        : (interactionIsIncomplete ? 0.18 : 0.44)
                    ZStack {
                        SceneMetalSurface(
                            compositor: session.compositor,
                            onReturnToRoad: {
                                model.showWorld(
                                    expectedIdentity: identity
                                )
                            }
                        )
                        .accessibilityHidden(true)
                        ChapterTouchSurface(
                            presentation: presentation,
                            cancellationEpoch:
                                continuousGestureCancellationEpoch,
                            submit: { intent in
                                session.submitTouch(
                                    intent,
                                    expectedIdentity: identity
                                )
                            },
                            endGesture: {
                                session.endContinuousTouchGesture(
                                    expectedIdentity: identity
                                )
                            }
                        )
#if DEBUG
                        .accessibilityElement()
                        .accessibilityLabel("Chapter touch surface")
                        .accessibilityIdentifier("chapter-touch-surface")
#else
                        .accessibilityHidden(true)
#endif
                    }
                    .aspectRatio(
                        presentation.framePlan.viewport.width
                            / presentation.framePlan.viewport.height,
                        contentMode: .fit
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !dynamicTypeSize.isAccessibilitySize {
                        ChapterSemanticInteractionSurface(
                            semanticModel: presentation.semanticInteractionModel,
                            submit: { elementID, action in
                                session.submitVoiceOver(
                                    elementID: elementID,
                                    authoredAction: action,
                                    expectedIdentity: identity
                                )
                            }
                        )
                    }

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.2), .black.opacity(0.94)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                    ChapterNarrativeSurface(
                        presentation: presentation,
                        model: model,
                        session: session,
                        identity: identity,
                        showsLinearSceneSummary:
                            dynamicTypeSize.isAccessibilitySize,
                        linearInteractionModel:
                            dynamicTypeSize.isAccessibilitySize
                                ? presentation.semanticInteractionModel
                                : nil,
                        submitLinearInteraction: { elementID, action in
                            session.submitVoiceOver(
                                elementID: elementID,
                                authoredAction: action,
                                expectedIdentity: identity
                            )
                        },
                        controlsAreDisabled: controlsAreDisabled,
                        openPrevious: {
                            guard let beatID = presentation.journeyState
                                .activeChapter?.completedBeatReviewRecords
                                .last?.beatID else { return }
                            guard model.openBeatReview(
                                chapterID: identity.chapterID,
                                beatID: beatID,
                                expectedIdentity: identity
                            ) else { return }
                            session.prepareForBeatExit(
                                expectedIdentity: identity
                            )
                        }
                    )
                    .id(presentation.cursor.beat.id)
                    .frame(
                        maxHeight: geometry.size.height
                            * narrativeHeightFraction,
                        alignment: .bottom
                    )
#if DEBUG
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Signed runtime state")
                        .accessibilityValue(model.signedRuntimeProgressDigestForTesting)
                        .accessibilityIdentifier("signed-runtime-restore-state")
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Review causal runtime state")
                        .accessibilityValue(
                            model.reviewCausalStateDigestForTesting
                        )
                        .accessibilityIdentifier(
                            "signed-runtime-review-causal-state"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Responsive audio presentation")
                        .accessibilityValue(
                            "\(session.audioPlaybackState.rawValue):\(session.desiredResponsiveAudioPhase?.rawValue ?? "none")"
                        )
                        .accessibilityIdentifier("responsive-audio-presentation-state")
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Responsive audio runtime")
                        .accessibilityValue(
                            model.responsiveAudioRuntimeDiagnosticForTesting
                        )
                        .accessibilityIdentifier("responsive-audio-runtime-state")
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Primary authored audio runtime")
                        .accessibilityValue(
                            session.primaryAudioDiagnosticForTesting
                        )
                        .accessibilityIdentifier("primary-audio-runtime-state")
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Responsive audio choice diagnostic")
                        .accessibilityValue(
                            session.audioPlaybackStateDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "responsive-audio-choice-diagnostic"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Responsive audio binding ready")
                        .accessibilityValue(
                            session.responsiveAudioBindingReadyForTesting
                        )
                        .accessibilityIdentifier(
                            "responsive-audio-binding-ready"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Chapter input admission diagnostic")
                        .accessibilityValue(
                            session.chapterInputAdmissionDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "chapter-input-admission-diagnostic"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Chapter input resolution diagnostic")
                        .accessibilityValue(
                            session.chapterInputResolutionDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "chapter-input-resolution-diagnostic"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(
                            "Content authority barrier diagnostic"
                        )
                        .accessibilityValue(
                            model
                                .contentAuthorityBarrierDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "content-authority-barrier-diagnostic"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(
                            "Content authority final admission diagnostic"
                        )
                        .accessibilityValue(
                            model
                                .chapterRuntimeInputAdmissionDiagnosticForTesting(
                                    identity
                                )
                        )
                        .accessibilityIdentifier(
                            "content-authority-final-admission-diagnostic"
                        )
#endif
                } else {
                    SceneMetalSurface(
                        compositor: session.compositor,
                        onReturnToRoad: {
                            session.prepareForBeatExit(
                                expectedIdentity: identity
                            )
                            model.showWorld(expectedIdentity: identity)
                        }
                    )
                    .accessibilityHidden(true)
                }

                if let presentation {
                    ChapterChromeHeader(
                        presentation: presentation,
                        playbackState: session.audioPlaybackState,
                        soundEnabled:
                            model.experiencePreferences.soundEnabled
                                && session.soundIsEnabledForPresentation,
                        controlsAreDisabled: controlsAreDisabled,
                        sceneListIsPresented: sceneListIsPresented,
                        returnToRoad: {
                            session.prepareForBeatExit(
                                expectedIdentity: identity
                            )
                            model.showWorld(expectedIdentity: identity)
                        },
                        openVisitedScenes: {
                            sceneListIsPresented = true
                        },
                        toggleSound: {
                            if session.audioPlaybackState == .playing {
                                session.turnSoundOff(
                                    expectedIdentity: identity
                                )
                            } else {
                                session.turnSoundOn(
                                    expectedIdentity: identity,
                                    voiceOverIsRunning:
                                        voiceOverIsRunning
                                )
                            }
                        }
                    )
                    .padding(.top, geometry.safeAreaInsets.top + 6)
                    .padding(.horizontal, 12)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .zIndex(1_500)
                }

                if let failure = session.failure {
                    ChapterRouteFailureSurface(
                        message: failure.message,
                        redownload: failure.canOfferRedownload
                            ? {
                                guard let packageID = failure
                                    .assetAuthority?.packageID else {
                                    return
                                }
                                model.requestChapterRedownload(
                                    chapterID: identity.chapterID,
                                    packageID: packageID,
                                    assetFailureAuthority: failure
                                        .assetAuthority
                                )
                                session.prepareForBeatExit(
                                    expectedIdentity: identity
                                )
                                model.showWorldRecoveringChapterFailure(
                                    expectedIdentity: identity
                                )
                            } : nil,
                        returnToRoad: {
                            session.prepareForBeatExit(
                                expectedIdentity: identity
                            )
                            model.showWorldRecoveringChapterFailure(
                                expectedIdentity: identity
                            )
                        }
                    )
#if DEBUG
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Signed runtime failure")
                        .accessibilityValue(session.failureDiagnosticForTesting)
                        .accessibilityIdentifier("signed-runtime-failure-diagnostic")
#endif
                }
            }
            .background(Color(red: 0.012, green: 0.015, blue: 0.016))
            .ignoresSafeArea()
        }
        .sheet(isPresented: $sceneListIsPresented) {
            if let presentation {
                ChapterVisitedScenesSheet(
                    presentation: presentation,
                    openReview: { beatID in
                        sceneListIsPresented = false
                        guard model.openBeatReview(
                            chapterID: identity.chapterID,
                            beatID: beatID,
                            expectedIdentity: identity
                        ) else { return }
                        session.prepareForBeatExit(
                            expectedIdentity: identity
                        )
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .task(id: "\(identity.beatID.rawValue):\(session.audioPlaybackState.rawValue)") {
            guard presentation != nil else { return }
            session.startEntrySoundIfAuthorized(
                expectedIdentity: identity,
                voiceOverIsRunning: voiceOverIsRunning
            )
        }
        .onChange(of: voiceOverIsRunning) { _, isRunning in
            if isRunning {
                session.pauseNarrationForVoiceOver(
                    expectedIdentity: identity
                )
            } else {
                session.voiceOverDidStop(
                    expectedIdentity: identity
                )
            }
        }
        .onChange(of: model.responsiveAudioPhysicalPauseEvent?.generation) {
            _, _ in
            guard let pauseEvent = model.responsiveAudioPhysicalPauseEvent else {
                return
            }
            session.handlePhysicalPause(
                pauseEvent,
                model: model,
                expectedIdentity: identity
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willResignActiveNotification
            )
        ) { _ in
            continuousGestureCancellationEpoch &+= 1
            session.drainContinuousInputBeforeLifecycle(
                expectedIdentity: identity
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                session.restoreResponsiveAudioPhaseAfterSceneActivation(
                    expectedIdentity: identity
                )
            } else {
                continuousGestureCancellationEpoch &+= 1
                session.drainContinuousInputBeforeLifecycle(
                    expectedIdentity: identity
                )
                session.captureResponsiveAudioPhaseAtSceneExit()
            }
        }
    }
}

private struct ChapterChromeHeader: View {
    let presentation: ChapterScenePresentation
    let playbackState: ChapterAudioPlaybackState
    let soundEnabled: Bool
    let controlsAreDisabled: Bool
    let sceneListIsPresented: Bool
    let returnToRoad: () -> Void
    let openVisitedScenes: () -> Void
    let toggleSound: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @AccessibilityFocusState private var visitedScenesIsFocused: Bool

    private var totalSceneCount: Int {
        presentation.cursor.chapter.arcs.reduce(0) {
            $0 + $1.beats.count
        }
    }

    private var absoluteSceneIndex: Int {
        presentation.cursor.chapter.arcs
            .prefix(presentation.cursor.arcIndex)
            .reduce(0) { $0 + $1.beats.count }
            + presentation.cursor.beatIndex
    }

    private var movementSeparators: [Double] {
        guard totalSceneCount > 0 else { return [] }
        var consumed = 0
        return presentation.cursor.chapter.arcs.dropLast().map { arc in
            consumed += arc.beats.count
            return Double(consumed) / Double(totalSceneCount)
        }
    }

    private var soundLabel: String {
        switch playbackState {
        case .playing:
            "Turn sound off"
        case .starting:
            "Starting sound"
        case .inactive:
            "Sound unavailable"
        case .ready, .resumeRequired:
            soundEnabled ? "Resume sound" : "Turn sound on"
        }
    }

    private var soundIcon: String {
        switch playbackState {
        case .playing: "speaker.wave.2.fill"
        case .inactive: "speaker.slash"
        case .ready, .resumeRequired:
            soundEnabled ? "speaker.wave.2" : "speaker.slash.fill"
        case .starting: "speaker.wave.2"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button("Road", action: returnToRoad)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(
                    Color(red: 0.88, green: 0.72, blue: 0.43)
                )
                .frame(minWidth: 58, minHeight: 44)
                .background(.black.opacity(0.72), in: Capsule())
                .overlay {
                    Capsule().stroke(
                        .white.opacity(contrast == .increased ? 0.28 : 0.12),
                        lineWidth: 1
                    )
                }
                .disabled(controlsAreDisabled || playbackState == .starting)
                .accessibilityIdentifier("chapter-road")

            Button(action: openVisitedScenes) {
                VStack(spacing: 4) {
                    Text(presentation.cursor.chapter.title.launchEnglish)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            Color(red: 0.72, green: 0.70, blue: 0.65)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(presentation.cursor.arc.title.launchEnglish)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(
                            Color(red: 0.94, green: 0.92, blue: 0.86)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    ChapterMovementProgressTrace(
                        progress: Double(absoluteSceneIndex + 1)
                            / Double(max(totalSceneCount, 1)),
                        separators: movementSeparators,
                        increasedContrast: contrast == .increased
                    )
                    .frame(height: 4)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.black.opacity(0.72), in: Capsule())
                .overlay {
                    Capsule().stroke(
                        .white.opacity(contrast == .increased ? 0.28 : 0.12),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(controlsAreDisabled)
            .accessibilityLabel(
                "\(presentation.cursor.chapter.title.launchEnglish), "
                    + "Movement \(presentation.cursor.arcIndex + 1), "
                    + "scene \(absoluteSceneIndex + 1) of \(totalSceneCount). "
                    + "Open visited scenes."
            )
            .accessibilityFocused($visitedScenesIsFocused)
            .accessibilityIdentifier("chapter-visited-scenes-open")

            Button(action: toggleSound) {
                ZStack {
                    if playbackState == .starting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(red: 0.86, green: 0.70, blue: 0.40))
                    } else {
                        Image(systemName: soundIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                Color(red: 0.86, green: 0.70, blue: 0.40)
                            )
                    }
                }
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.72), in: Circle())
                .overlay {
                    Circle().stroke(
                        .white.opacity(contrast == .increased ? 0.32 : 0.12),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(
                controlsAreDisabled
                    || playbackState == .starting
                    || playbackState == .inactive
            )
            .accessibilityLabel(soundLabel)
            .accessibilityIdentifier("chapter-sound-control")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onChange(of: sceneListIsPresented) { _, isPresented in
            if !isPresented { visitedScenesIsFocused = true }
        }
    }
}

private struct ChapterMovementProgressTrace: View {
    let progress: Double
    let separators: [Double]
    let increasedContrast: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(increasedContrast ? 0.30 : 0.16))
                Capsule()
                    .fill(Color(red: 0.82, green: 0.64, blue: 0.34))
                    .frame(
                        width: geometry.size.width
                            * min(max(progress, 0), 1)
                    )
                ForEach(Array(separators.enumerated()), id: \.offset) {
                    _, separator in
                    Rectangle()
                        .fill(.black.opacity(0.86))
                        .frame(width: 1)
                        .offset(x: geometry.size.width * separator)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ChapterReviewVisitedScenesSheet: View {
    let projection: ChapterReviewProjection
    let openReview: (BeatID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(
                    Array(
                        projection.selected.chapter.arcs.enumerated()
                    ),
                    id: \.element.id
                ) { movementIndex, arc in
                    let cursors = projection.cursors.filter {
                        $0.arc.id == arc.id
                    }
                    if !cursors.isEmpty {
                        Section {
                            ForEach(cursors, id: \.beat.id) { cursor in
                                if cursor.beat.id
                                    == projection.selected.beat.id {
                                    HStack(spacing: 12) {
                                        Text(
                                            cursor.beat.narrative.heading
                                                .launchEnglish
                                        )
                                        Spacer()
                                        Text("Current")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(
                                                Color(
                                                    red: 0.76,
                                                    green: 0.59,
                                                    blue: 0.31
                                                )
                                            )
                                    }
                                    .frame(minHeight: 44)
                                    .accessibilityElement(children: .combine)
                                } else {
                                    Button {
                                        openReview(cursor.beat.id)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text(
                                                cursor.beat.narrative.heading
                                                    .launchEnglish
                                            )
                                            .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(
                                                    Color(
                                                        red: 0.76,
                                                        green: 0.59,
                                                        blue: 0.31
                                                    )
                                                )
                                        }
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                    }
                                }
                            }
                        } header: {
                            Text(
                                "Movement \(movementIndex + 1) · "
                                    + arc.title.launchEnglish
                            )
                        }
                    }
                }
            }
            .navigationTitle(
                projection.selected.chapter.title.launchEnglish
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .accessibilityIdentifier("chapter-review-visited-scenes-sheet")
    }
}

private struct ChapterVisitedScenesSheet: View {
    let presentation: ChapterScenePresentation
    let openReview: (BeatID) -> Void
    @Environment(\.dismiss) private var dismiss

    private var completedBeatIDs: Set<BeatID> {
        Set(
            presentation.journeyState.activeChapter?
                .completedBeatReviewRecords.map(\.beatID) ?? []
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(
                    Array(presentation.cursor.chapter.arcs.enumerated()),
                    id: \.element.id
                ) { movementIndex, arc in
                    if arc.beats.contains(where: {
                        completedBeatIDs.contains($0.id)
                            || $0.id == presentation.cursor.beat.id
                    }) {
                        Section {
                            ForEach(arc.beats) { beat in
                                if completedBeatIDs.contains(beat.id) {
                                    Button {
                                        openReview(beat.id)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text(
                                                beat.narrative.heading
                                                    .launchEnglish
                                            )
                                            .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(
                                                    Color(
                                                        red: 0.76,
                                                        green: 0.59,
                                                        blue: 0.31
                                                    )
                                                )
                                        }
                                        .frame(minHeight: 44)
                                    }
                                } else if beat.id
                                    == presentation.cursor.beat.id {
                                    HStack(spacing: 12) {
                                        Text(
                                            beat.narrative.heading
                                                .launchEnglish
                                        )
                                        Spacer()
                                        Text("Current")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(
                                                Color(
                                                    red: 0.76,
                                                    green: 0.59,
                                                    blue: 0.31
                                                )
                                            )
                                    }
                                    .frame(minHeight: 44)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        } header: {
                            Text(
                                "Movement \(movementIndex + 1) · "
                                    + arc.title.launchEnglish
                            )
                        }
                    }
                }
            }
            .navigationTitle(presentation.cursor.chapter.title.launchEnglish)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .accessibilityIdentifier("chapter-visited-scenes-sheet")
    }
}

private struct ChapterNarrativeSurface: View {
    let presentation: ChapterScenePresentation
    @ObservedObject var model: JourneyModel
    @ObservedObject var session: ProductionChapterRouteSession
    let identity: ChapterRuntimeRouteIdentity
    let showsLinearSceneSummary: Bool
    let linearInteractionModel: SemanticInteractionModel?
    let submitLinearInteraction: (String, AccessibilityActionSpec) -> Void
    let controlsAreDisabled: Bool
    let openPrevious: () -> Void
    @State private var readingAnchor: String?
    @Environment(\.colorSchemeContrast) private var contrast
    @AccessibilityFocusState private var headingIsFocused: Bool

    private var interactionIsComplete: Bool {
        presentation.journeyState.activeChapter?.interaction?.phase == .complete
    }

    private var interactionIsIncomplete: Bool {
        presentation.cursor.beat.interaction != nil && !interactionIsComplete
    }

    private var canAdvance: Bool {
        presentation.cursor.beat.interaction == nil || interactionIsComplete
    }

    private var hasPrevious: Bool {
        !(presentation.journeyState.activeChapter?
            .completedBeatReviewRecords.isEmpty ?? true)
    }

    private var allocationCanCommit: Bool {
        guard let interaction = presentation.cursor.beat.interaction,
              case let .allocate(configuration) = interaction.grammar,
              let runtime = presentation.journeyState.activeChapter?
                .interaction,
              case let .allocate(progress) = runtime.progress else {
            return false
        }
        return InteractionReducer.allocationCanCommit(
            progress: progress,
            configuration: configuration
        )
    }

    private var interactionStatus: String? {
        switch presentation.interactionFeedback {
        case .contact: "Contact accepted"
        case .progress: "In progress"
        case .resistance: "That movement cannot continue"
        case .threshold: "Threshold reached"
        case .completed: "Complete"
        case .some(.none), nil: nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !interactionIsIncomplete {
                        Text(
                            presentation.cursor.chapter.period.launchEnglish
                                .uppercased()
                        )
                        .font(.caption2.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(
                            Color(red: 0.74, green: 0.63, blue: 0.43)
                        )
                    }
                    Text(
                        presentation.cursor.beat.narrative.heading
                            .launchEnglish
                    )
                    .font(
                        .system(
                            interactionIsIncomplete ? .title2 : .title,
                            design: .serif,
                            weight: .regular
                        )
                    )
                    .foregroundStyle(
                        Color(red: 0.95, green: 0.93, blue: 0.87)
                    )
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingIsFocused)

                    if showsLinearSceneSummary {
                        Text(
                            presentation.cursor.accessibility.sceneSummary
                                .launchEnglish
                        )
                        .font(.system(.callout, design: .serif))
                        .foregroundStyle(
                            Color(red: 0.76, green: 0.75, blue: 0.71)
                        )
                    }

                    ForEach(
                        presentation.cursor.beat.narrative.paragraphs
                    ) { paragraph in
                        Text(paragraph.launchEnglish)
                            .font(
                                .system(
                                    .body,
                                    design: .serif,
                                    weight: .regular
                                )
                            )
                            .lineSpacing(5)
                            .foregroundStyle(
                                Color(red: 0.84, green: 0.83, blue: 0.79)
                            )
                            .id(paragraph.id.rawValue)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24)
                .padding(.top, interactionIsIncomplete ? 4 : 12)
                .padding(.bottom, 18)
            }
            .scrollPosition(id: $readingAnchor, anchor: .top)
            .scrollIndicators(.hidden)

            Divider().overlay(
                .white.opacity(contrast == .increased ? 0.28 : 0.10)
            )

            VStack(alignment: .leading, spacing: 10) {
                if let interaction = presentation.cursor.beat.interaction,
                   !interactionIsComplete {
                    Text(
                        presentation.cursor.beat.narrative.actionPrompt?
                            .launchEnglish
                            ?? interaction.prompt.launchEnglish
                    )
                    .font(
                        .system(
                            .callout,
                            design: .serif,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color(red: 0.90, green: 0.73, blue: 0.43)
                    )
                    .lineLimit(3)

                    if let interactionStatus {
                        Text(interactionStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !interactionIsComplete,
                   let linearInteractionModel {
                    ChapterLinearInteractionControls(
                        semanticModel: linearInteractionModel,
                        submit: submitLinearInteraction
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actionControls }
                    VStack(spacing: 10) { actionControls }
                }

                if let audioFailure = model.responsiveAudioFailure {
                    Text(audioFailure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .safeAreaPadding(.bottom, 8)
        }
        .background(
            .black.opacity(contrast == .increased ? 0.90 : 0.76)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chapter-beat-\(presentation.cursor.beat.id)")
        .onAppear {
            readingAnchor = presentation.journeyState.activeChapter?
                .readingAnchor
            if readingAnchor == nil { headingIsFocused = true }
        }
        .onChange(of: readingAnchor) { _, anchor in
            model.setReadingAnchor(anchor, expectedIdentity: identity)
        }
    }

    @ViewBuilder
    private var actionControls: some View {
        if hasPrevious {
            Button(action: openPrevious) {
                Text("Previous")
                    .frame(minWidth: 88, minHeight: 44)
            }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.78, green: 0.70, blue: 0.56))
                .disabled(controlsAreDisabled)
                .accessibilityIdentifier("chapter-previous")
        }

        if let interaction = presentation.cursor.beat.interaction,
           !interactionIsComplete,
           case .allocate = interaction.grammar {
            Button {
                session.submitTouch(
                    .commitAllocation,
                    expectedIdentity: identity
                )
            } label: {
                Text("Set the allocation")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.82, green: 0.64, blue: 0.34))
            .foregroundStyle(.black)
            .disabled(controlsAreDisabled || !allocationCanCommit)
            .accessibilityLabel("Set the stores")
            .accessibilityIdentifier("chapter-allocate-commit")
        }

        if canAdvance {
            Button {
                session.prepareForBeatExit(
                    expectedIdentity: identity
                )
                model.advanceCurrentBeat(expectedIdentity: identity)
            } label: {
                HStack {
                    Text("Continue")
                    Spacer()
                    if model.chapterTransitionIsPending {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.right")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.82, green: 0.64, blue: 0.34))
            .foregroundStyle(.black)
            .disabled(
                controlsAreDisabled
            )
            .accessibilityIdentifier("chapter-continue")
        }
    }
}

private struct ChapterLinearInteractionControls: View {
    let semanticModel: SemanticInteractionModel
    let submit: (String, AccessibilityActionSpec) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(
                semanticModel.controls.filter {
                    $0.id != "commit-allocation"
                }
            ) { control in
                switch control.kind {
                case .action:
                    ForEach(
                        Array(control.actions.enumerated()),
                        id: \.offset
                    ) { _, action in
                        Button {
                            submit(control.id, action)
                        } label: {
                            HStack {
                                Text(action.label.launchEnglish)
                                Spacer()
                                if let value = control.value {
                                    Text(value)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(control.label)
                        .accessibilityValue(control.value ?? "")
                        .accessibilityHint(control.hint ?? "")
                        .accessibilityIdentifier(
                            "chapter-linear-\(control.id)-\(action.kind.rawValue)"
                        )
                    }
                case .adjustable:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(control.label)
                                .font(.callout.weight(.semibold))
                            Spacer()
                            if let value = control.value {
                                Text(value)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        HStack(spacing: 10) {
                            ForEach(
                                Array(control.actions.enumerated()),
                                id: \.offset
                            ) { _, action in
                                Button(action.label.launchEnglish) {
                                    submit(control.id, action)
                                }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .accessibilityLabel(
                                    "\(control.label), \(action.label.launchEnglish)"
                                )
                                .accessibilityValue(control.value ?? "")
                                .accessibilityIdentifier(
                                    "chapter-linear-\(control.id)-\(action.kind.rawValue)"
                                )
                            }
                        }
                    }
                case .status:
                    HStack {
                        Text(control.label)
                        Spacer()
                        if let value = control.value {
                            Text(value).foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct ChapterRouteFailureSurface: View {
    let message: String
    let redownload: (() -> Void)?
    let returnTitle: String
    let returnToRoad: () -> Void
    @AccessibilityFocusState private var headingIsFocused: Bool

    init(
        message: String,
        redownload: (() -> Void)? = nil,
        returnTitle: String = "Return to the road",
        returnToRoad: @escaping () -> Void
    ) {
        self.message = message
        self.redownload = redownload
        self.returnTitle = returnTitle
        self.returnToRoad = returnToRoad
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("This scene could not be opened.")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(Color(red: 0.90, green: 0.84, blue: 0.72))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingIsFocused)
            Text(message)
                .foregroundStyle(.secondary)
            if let redownload {
                Button(action: redownload) {
                    Text("Download again")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.52, green: 0.37, blue: 0.20))
                .accessibilityIdentifier(
                    "chapter-failure-download-again"
                )
            }
            Button(action: returnToRoad) {
                Text(returnTitle)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.52, green: 0.37, blue: 0.20))
                .accessibilityIdentifier("chapter-failure-return-to-road")
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.035, green: 0.029, blue: 0.027))
        .onAppear { headingIsFocused = true }
    }
}

private struct ChapterSemanticInteractionSurface: View {
    let semanticModel: SemanticInteractionModel?
    let submit: (String, AccessibilityActionSpec) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let semanticModel {
                ForEach(
                    semanticModel.controls.filter {
                        $0.id != "commit-allocation"
                    }
                ) { control in
                    SemanticControlElement(control: control, submit: submit)
                }
            }
        }
        .frame(width: 1, height: 1)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(semanticModel?.label ?? "")
        .accessibilitySortPriority(10)
    }
}

private struct SemanticControlElement: View {
    let control: SemanticControl
    let submit: (String, AccessibilityActionSpec) -> Void

    private var activation: AccessibilityActionSpec? {
        control.actions.first { $0.kind == .activate }
    }

    private var additionalActivations: [AccessibilityActionSpec] {
        Array(control.actions.filter { $0.kind == .activate }.dropFirst())
    }

    private var increment: AccessibilityActionSpec? {
        control.actions.first { $0.kind == .increment }
    }

    private var decrement: AccessibilityActionSpec? {
        control.actions.first { $0.kind == .decrement }
    }

    private var availableAdjustments: [AccessibilityActionSpec] {
        control.actions.filter {
            $0.kind == .increment || $0.kind == .decrement
        }
    }

    private var baseElement: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(control.label)
            .accessibilityValue(control.value ?? "")
            .accessibilityHint(control.hint ?? "")
            .accessibilityIdentifier("chapter-semantic-\(control.id)")
    }

    @ViewBuilder
    private var adjustableElement: some View {
        if increment != nil, decrement != nil {
            baseElement.accessibilityAdjustableAction { direction in
                let action = direction == .increment
                    ? increment : decrement
                if let action { submit(control.id, action) }
            }
        } else {
            // A generic adjustable action always exposes both swipe
            // directions. At a limit, publish only the authored direction
            // that can still change state.
            baseElement.accessibilityActions {
                ForEach(
                    Array(availableAdjustments.enumerated()),
                    id: \.offset
                ) { _, action in
                    Button(action.label.launchEnglish) {
                        submit(control.id, action)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var body: some View {
        switch control.kind {
        case .action:
            baseElement
                .accessibilityAction {
                    if let activation { submit(control.id, activation) }
                }
                .accessibilityActions {
                    ForEach(
                        Array(additionalActivations.enumerated()),
                        id: \.offset
                    ) { _, action in
                        Button(action.label.launchEnglish) {
                            submit(control.id, action)
                        }
                    }
                }
        case .adjustable:
            adjustableElement
        case .status:
            baseElement
        }
    }
}

private struct ChapterTouchSurface: View {
    let presentation: ChapterScenePresentation
    let cancellationEpoch: UInt64
    let submit: (SceneTouchIntent) -> Void
    let endGesture: () -> Void

    var body: some View {
        if let interaction = presentation.cursor.beat.interaction,
           presentation.journeyState.activeChapter?.interaction?.phase != .complete {
            switch interaction.grammar {
            case .trace:
                TraceTouchSurface(
                    submit: submit,
                    endGesture: endGesture
                )
            case .allocate:
                AllocateTouchSurface(
                    presentation: presentation,
                    submit: submit,
                    endGesture: endGesture
                )
            case .assemble:
                AssembleTouchSurface(
                    presentation: presentation,
                    submit: submit,
                    endGesture: endGesture
                )
            case .pressure:
                PressureTouchSurface(
                    cancellationEpoch: cancellationEpoch,
                    submit: submit,
                    endGesture: endGesture
                )
            case .transform:
                TransformTouchSurface(
                    currentAmount: transformAmount(in: presentation),
                    submit: submit,
                    endGesture: endGesture
                )
            }
        }
    }

    private func transformAmount(in presentation: ChapterScenePresentation) -> Double {
        guard case let .transform(progress)? =
            presentation.journeyState.activeChapter?.interaction?.progress else {
            return 0
        }
        return progress.currentAmount
    }
}

private struct TraceTouchSurface: View {
    let submit: (SceneTouchIntent) -> Void
    let endGesture: () -> Void
    @State private var sampleAdmission = TraceTouchSampleAdmissionPolicy()

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let point = normalized(value.location, in: geometry.size)
                            guard sampleAdmission.admits(point) else { return }
                            submit(.trace(viewportPoint: point))
                        }
                        .onEnded { _ in
                            sampleAdmission.endGesture()
                            endGesture()
                        }
                )
                .onDisappear {
                    sampleAdmission.endGesture()
                    endGesture()
                }
        }
    }
}

private struct TargetActivationTouchSurface: View {
    let submit: (SceneTouchIntent) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(coordinateSpace: .local)
                        .onEnded { value in
                            submit(
                                .activateTarget(
                                    viewportPoint: normalized(value.location, in: geometry.size)
                                )
                            )
                        }
                )
        }
    }
}

private struct AssembleTouchSurface: View {
    let presentation: ChapterScenePresentation
    let submit: (SceneTouchIntent) -> Void
    let endGesture: () -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let source = normalized(value.startLocation, in: geometry.size)
                            guard componentSourceHit(at: source) != nil else { return }
                            let current = normalized(value.location, in: geometry.size)
                            let progress = dragProgress(value.translation, in: geometry.size)
                            let transportDistance = abs(value.translation.width)
                                + abs(value.translation.height)
                            if transportDistance < 2 {
                                submit(
                                    .assembleContact(
                                        viewportPoint: source,
                                        progress: progress
                                    )
                                )
                            } else if progress < 0.16 {
                                submit(
                                    .assembleLift(
                                        sourceViewportPoint: source,
                                        currentViewportPoint: current,
                                        progress: progress
                                    )
                                )
                            } else if slotHit(at: current) != nil {
                                submit(
                                    .assembleSlotApproach(
                                        sourceViewportPoint: source,
                                        slotViewportPoint: current,
                                        progress: progress
                                    )
                                )
                            } else {
                                submit(
                                    .assembleCarry(
                                        sourceViewportPoint: source,
                                        currentViewportPoint: current,
                                        progress: progress
                                    )
                                )
                            }
                        }
                        .onEnded { value in
                            defer { endGesture() }
                            let source = normalized(value.startLocation, in: geometry.size)
                            guard componentSourceHit(at: source) != nil else { return }
                            let current = normalized(value.location, in: geometry.size)
                            let progress = dragProgress(value.translation, in: geometry.size)
                            if slotHit(at: current) != nil {
                                submit(
                                    .assembleDrop(
                                        sourceViewportPoint: source,
                                        slotViewportPoint: current,
                                        progress: progress
                                    )
                                )
                            } else {
                                submit(
                                    .assembleCancel(
                                        sourceViewportPoint: source,
                                        currentViewportPoint: current,
                                        progress: progress
                                    )
                                )
                            }
                        }
                )
                .onDisappear { endGesture() }
        }
    }

    private func componentSourceHit(at point: SceneFramePoint) -> SceneTouchTargetHit? {
        guard case let .assemble(visual)? =
            presentation.cursor.scene.interactionVisualBinding,
              case let .assemble(progress)? =
                presentation.journeyState.activeChapter?.interaction?.progress,
              let hit = try? SceneTouchGeometryResolver.target(
                  at: point,
                  in: presentation.framePlan
              ), let component = visual.components.first(where: {
                  $0.slotInteractionTargetID != nil
                      && $0.sourceInteractionTargetID == hit.interactionTargetID
              }), !progress.placements.contains(where: {
                  $0.componentID == component.componentID
              }) else {
            return nil
        }
        return hit
    }

    private func slotHit(at point: SceneFramePoint) -> SceneTouchTargetHit? {
        guard case let .assemble(visual)? =
            presentation.cursor.scene.interactionVisualBinding,
              let hit = try? SceneTouchGeometryResolver.target(
                  at: point,
                  in: presentation.framePlan
              ), visual.components.contains(where: {
                  $0.slotInteractionTargetID == hit.interactionTargetID
              }) else {
            return nil
        }
        return hit
    }
}

private struct AllocateTouchSurface: View {
    let presentation: ChapterScenePresentation
    let submit: (SceneTouchIntent) -> Void
    let endGesture: () -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let source = normalized(value.startLocation, in: geometry.size)
                            let current = normalized(value.location, in: geometry.size)
                            let progress = dragProgress(value.translation, in: geometry.size)
                            if destinationHit(at: source) != nil {
                                // A drag beginning on an authored destination
                                // returns material. Its durable action is
                                // resolved only when the finger reaches the
                                // visible source resource.
                                return
                            }
                            if abs(value.translation.width) + abs(value.translation.height) < 2 {
                                submit(
                                    .allocateContact(
                                        viewportPoint: source,
                                        progress: progress
                                    )
                                )
                            } else {
                                submit(
                                    .allocateCarry(
                                        sourceViewportPoint: source,
                                        currentViewportPoint: current,
                                        progress: progress
                                    )
                                )
                            }
                        }
                        .onEnded { value in
                            defer { endGesture() }
                            let source = normalized(value.startLocation, in: geometry.size)
                            let destination = normalized(value.location, in: geometry.size)
                            if destinationHit(at: source) != nil {
                                submit(
                                    .allocateReturn(
                                        destinationViewportPoint: source,
                                        resourceViewportPoint: destination,
                                        progress: dragProgress(value.translation, in: geometry.size)
                                    )
                                )
                                return
                            }
                            guard let units = destinationUnits(at: destination) else { return }
                            submit(
                                .allocateDrop(
                                    sourceViewportPoint: source,
                                    destinationViewportPoint: destination,
                                    destinationUnits: units,
                                    progress: dragProgress(value.translation, in: geometry.size)
                                )
                            )
                        }
                )
                .onDisappear { endGesture() }
        }
    }

    private func destinationHit(at point: SceneFramePoint) -> SceneTouchTargetHit? {
        guard case let .allocate(visual)? = presentation.cursor.scene.interactionVisualBinding,
              let hit = try? SceneTouchGeometryResolver.target(
                  at: point,
                  in: presentation.framePlan
              ), visual.destinations.contains(where: {
                  $0.interactionTargetID == hit.interactionTargetID
              }) else {
            return nil
        }
        return hit
    }

    private func destinationUnits(at point: SceneFramePoint) -> Int? {
        guard case let .allocate(configuration)? = presentation.cursor.beat.interaction?.grammar,
              case let .allocate(progress)? =
                presentation.journeyState.activeChapter?.interaction?.progress,
              case let .allocate(visual)? = presentation.cursor.scene.interactionVisualBinding,
              let hit = try? SceneTouchGeometryResolver.target(
                  at: point,
                  in: presentation.framePlan
              ), let destinationVisual = visual.destinations.first(where: {
                  $0.interactionTargetID == hit.interactionTargetID
              }), let current = progress.allocations.first(where: {
                  $0.destinationID == destinationVisual.destinationID
              })?.units else {
            return nil
        }
        let authoredStep = presentation.semanticInteractionModel?.controls
            .first(where: { $0.id == hit.accessibilityElementID })?
            .actions
            .compactMap { action -> Int? in
                guard action.kind == .increment,
                      case let .allocate(destinationID, unitsPerStep) = action.token,
                      destinationID == destinationVisual.destinationID else { return nil }
                return unitsPerStep
            }
            .first
        guard let authoredStep else { return nil }
        let unitsElsewhere = progress.allocations
            .filter { $0.destinationID != destinationVisual.destinationID }
            .reduce(0) { $0 + $1.units }
        let available = max(configuration.totalUnits - unitsElsewhere, 0)
        let next = min(current + authoredStep, available)
        return next > 0 && next != current ? next : nil
    }
}

private struct PressureTouchSurface: View {
    let cancellationEpoch: UInt64
    let submit: (SceneTouchIntent) -> Void
    let endGesture: () -> Void
    @State private var heldPoint: SceneFramePoint?
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let point = normalized(value.location, in: geometry.size)
                            heldPoint = point
                            submit(
                                .adjustTarget(
                                    viewportPoint: point,
                                    amount: clamped(1 - point.y)
                                )
                            )
                            startHoldIfNeeded()
                        }
                        .onEnded { _ in
                            stopHold()
                            endGesture()
                        }
                )
                .onDisappear {
                    stopHold()
                    endGesture()
                }
                .onChange(of: cancellationEpoch) { _, _ in
                    stopHold()
                    endGesture()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willResignActiveNotification
                    )
                ) { _ in
                    // Stop synchronously on the earliest lifecycle signal so
                    // the 250 ms loop cannot wake once more in background.
                    stopHold()
                    endGesture()
                }
#if DEBUG
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: .pressureHoldLifecycleProbeStart
                    )
                ) { _ in
                    heldPoint = SceneFramePoint(x: 0.5, y: 0.5)
                    startHoldIfNeeded()
                }
#endif
        }
    }

    private func startHoldIfNeeded() {
        guard holdTask == nil else { return }
        holdTask = Task { @MainActor in
            while !Task.isCancelled, heldPoint != nil {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, heldPoint != nil else { return }
                submit(.holdPressure(elapsedMillis: 250))
            }
        }
    }

    private func stopHold() {
        heldPoint = nil
        holdTask?.cancel()
        holdTask = nil
    }
}

private struct TransformTouchSurface: View {
    let currentAmount: Double
    let submit: (SceneTouchIntent) -> Void
    let endGesture: () -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let point = normalized(value.startLocation, in: geometry.size)
                            let distance = dragProgress(value.translation, in: geometry.size)
                            submit(
                                .adjustTarget(
                                    viewportPoint: point,
                                    amount: max(currentAmount, distance)
                                )
                            )
                        }
                        .onEnded { _ in endGesture() }
                )
                .onDisappear { endGesture() }
        }
    }
}

private func normalized(_ point: CGPoint, in size: CGSize) -> SceneFramePoint {
    SceneFramePoint(
        x: clamped(size.width > 0 ? point.x / size.width : 0),
        y: clamped(size.height > 0 ? point.y / size.height : 0)
    )
}

private func dragProgress(_ translation: CGSize, in size: CGSize) -> Double {
    let denominator = max(min(size.width, size.height) * 0.42, 1)
    return clamped(hypot(translation.width, translation.height) / denominator)
}

private func clamped(_ value: Double) -> Double {
    min(max(value, 0), 1)
}
