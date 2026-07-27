import ChapterRuntime
import ContentKit
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
}

@MainActor
final class ProductionChapterRouteSession: ObservableObject {
    @Published private(set) var presentation: ChapterScenePresentation?
    @Published private(set) var failure: ProductionChapterRouteFailure?
    @Published private(set) var inputIsPending = false
    @Published private(set) var lifecyclePresentationRefreshIsPending = false
    @Published private(set) var responsiveAudioChoice =
        ChapterResponsiveAudioChoice.undecided
    @Published private(set) var desiredResponsiveAudioPhase:
        ResponsiveInteractionAudioPhase?
#if DEBUG
    @Published private(set) var failureDiagnosticForTesting = ""
    @Published private(set) var responsiveAudioChoiceDiagnosticForTesting =
        "initial:undecided"
    @Published private(set) var chapterInputAdmissionDiagnosticForTesting =
        "none"
    @Published private(set) var chapterInputResolutionDiagnosticForTesting =
        "none"
    @Published private(set) var responsiveAudioBindingReadyForTesting =
        "not-ready"
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

    private var responsiveAudioRouteKey: ResponsiveAudioRouteKey?
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
            && responsiveAudioChoice == .playing
#if DEBUG
        let previousIdentity = self.identity
#endif
        cancelOutstandingPerformanceActions()
        cancelEphemeralResponseCleanup()
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
        }
        _ = responsiveAudioPolicy.bind(
            chapterID: identity.chapterID,
            hasResponsiveAudio: false
        )
        responsiveAudioChoice = responsiveAudioPolicy.choice
#if DEBUG
        responsiveAudioChoiceDiagnosticForTesting =
            "activate-\(generation)-bind-silent:\(responsiveAudioChoice.rawValue)"
#endif
        responsiveAudioRouteKey = nil
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
              responsiveAudioChoice == .starting,
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
        traceTouchSampleCountForTesting = 0
        firstTraceViewportPointForTesting = nil
#endif
        reportedAssetFailureAuthority = nil
        responsiveAudioPolicy.deactivate()
        responsiveAudioRouteKey = nil
        desiredResponsiveAudioPhase = nil
        responsiveAudioChoice = responsiveAudioPolicy.choice
#if DEBUG
        responsiveAudioChoiceDiagnosticForTesting =
            "deactivate:\(responsiveAudioChoice.rawValue)"
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
              responsiveAudioChoice != .starting,
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
    }

    /// The same explicit action serves touch and VoiceOver. A new chapter
    /// visit begins undecided, and backgrounding converts existing consent to
    /// an explicit resume rather than starting sound on return.
    func hearScene(expectedIdentity: ChapterRuntimeRouteIdentity) {
        let inputIsAdmitted = admitsInput(for: expectedIdentity)
        let hasProgram = presentation?.cursor.responsiveAudioProgram != nil
        guard inputIsAdmitted,
              !inputIsPending,
              hasProgram,
              responsiveAudioChoice != .starting,
              responsiveAudioChoice != .playing,
              let model,
              let routeKey = responsiveAudioRouteKey,
              let attempt = responsiveAudioPolicy.chooseSound() else {
#if DEBUG
            responsiveAudioBindingReadyForTesting =
                "blocked;stage=hear;generation=\(routeGeneration);"
                    + "admitted=\(inputIsAdmitted ? 1 : 0);"
                    + "input=\(inputIsPending ? 1 : 0);"
                    + "refresh=\(lifecyclePresentationRefreshIsPending ? 1 : 0);"
                    + "program=\(hasProgram ? 1 : 0);"
                    + "routeKey=\(responsiveAudioRouteKey == nil ? 0 : 1);"
                    + "choice=\(responsiveAudioChoice.rawValue)"
#endif
            return
        }
        responsiveAudioChoice = responsiveAudioPolicy.choice
#if DEBUG
        responsiveAudioChoiceDiagnosticForTesting =
            "choose-sound:\(responsiveAudioChoice.rawValue)"
#endif
        startResponsiveAudioPlayback(
            attempt,
            routeKey: routeKey,
            startEpoch:
                model.responsiveAudioPlaybackStartEpochForCurrentLifecycle()
        )
    }

    func continueInSilence(expectedIdentity: ChapterRuntimeRouteIdentity) {
        guard admitsInput(for: expectedIdentity),
              !inputIsPending,
              responsiveAudioChoice == .undecided,
              presentation?.cursor.responsiveAudioProgram != nil else { return }
        responsiveAudioPolicy.continueInSilence()
        responsiveAudioChoice = responsiveAudioPolicy.choice
#if DEBUG
        responsiveAudioChoiceDiagnosticForTesting =
            "continue-silent:\(responsiveAudioChoice.rawValue)"
#endif
    }

    func requireExplicitResponsiveAudioResume() {
        guard responsiveAudioChoice == .playing
                || responsiveAudioChoice == .starting else { return }
        responsiveAudioPlaybackTask?.cancel()
        responsiveAudioPlaybackTask = nil
        responsiveAudioAuthorizedStartEpoch = nil
        responsiveAudioPolicy.requireExplicitResume()
        responsiveAudioChoice = responsiveAudioPolicy.choice
#if DEBUG
        responsiveAudioChoiceDiagnosticForTesting =
            "physical-pause-event:\(responsiveAudioChoice.rawValue)"
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
            let started = await model.startResponsiveAudioPlayback(
                startEpoch: startEpoch
            )
            guard !Task.isCancelled,
                  self.routeGeneration == generation,
                  self.responsiveAudioRouteKey == routeKey else {
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
            guard self.responsiveAudioPolicy.completePlayback(
                attempt,
                didStart: mayPublishPlayback
            ) else { return }
            self.responsiveAudioPlaybackTask = nil
            self.responsiveAudioAuthorizedStartEpoch = mayPublishPlayback
                ? startEpoch
                : nil
            self.responsiveAudioChoice = self.responsiveAudioPolicy.choice
#if DEBUG
            self.responsiveAudioChoiceDiagnosticForTesting =
                "playback-complete:\(self.responsiveAudioChoice.rawValue)"
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
            if publishesVisualResponse {
                let compositorState = compositor.update(
                    preview.presentation.framePlan
                )
                guard case .sceneReady = compositorState else {
                    routeReplacementIsPending = true
                    failure = ProductionChapterRouteFailure(
                        kind: .rendererUnavailable,
                        assetAuthority: nil
                    )
                    return .routeFailed
                }
                presentation = preview.presentation
            }
            return .classified(protection(for: preview.semantic))
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
            cancelEphemeralResponseCleanup()
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
                        responsiveAudioChoice.authorizesPlayback
                )
            case let .semantic(elementID, action):
                next = try await model.submitChapterSceneVoiceOver(
                    elementID: elementID,
                    authoredAction: action,
                    runtime: runtime,
                    identity: identity,
                    reservation: instrumentedInput.reservation,
                    responsiveAudioIsUserAuthorized:
                        responsiveAudioChoice.authorizesPlayback
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
        guard let program = presentation.cursor.responsiveAudioProgram else {
            if responsiveAudioRouteKey != nil {
                responsiveAudioPlaybackTask?.cancel()
                responsiveAudioPlaybackTask = nil
                responsiveAudioRouteKey = nil
                responsiveAudioAuthorizedStartEpoch = nil
                _ = responsiveAudioPolicy.bind(
                    chapterID: identity.chapterID,
                    hasResponsiveAudio: false
                )
                responsiveAudioChoice = responsiveAudioPolicy.choice
#if DEBUG
                responsiveAudioChoiceDiagnosticForTesting =
                    "program-removed:\(responsiveAudioChoice.rawValue)"
#endif
            }
            desiredResponsiveAudioPhase = nil
            clearRememberedResponsiveAudioLifecyclePhase()
            return
        }
        let nextKey = ResponsiveAudioRouteKey(
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
        let previousKey = responsiveAudioRouteKey
        if previousKey != nextKey {
#if DEBUG
            let bindingChange: String
            if let previousKey {
                if previousKey.routeIdentity != identity {
                    bindingChange = "route-identity"
                } else if previousKey.playbackLease.programID != program.id {
                    bindingChange = "program"
                } else {
                    bindingChange = "unknown"
                }
            } else {
                bindingChange = "initial"
            }
#endif
            responsiveAudioPlaybackTask?.cancel()
            responsiveAudioPlaybackTask = nil
            responsiveAudioRouteKey = nextKey
            desiredResponsiveAudioPhase = nil
            clearRememberedResponsiveAudioLifecyclePhase()
            let action = responsiveAudioPolicy.bind(
                chapterID: identity.chapterID,
                hasResponsiveAudio: true,
                restoredSessionIsActive: presentation.journeyState
                    .activeChapter?.responsiveAudioSessionIsActive == true
            )
            responsiveAudioChoice = responsiveAudioPolicy.choice
#if DEBUG
            responsiveAudioChoiceDiagnosticForTesting =
                "program-bind-\(bindingChange)-generation-\(routeGeneration):"
                    + responsiveAudioChoice.rawValue
                    + ":\(responsiveAudioActivationDiagnosticForTesting)"
#endif
            if case let .startAuthorizedPlayback(attempt) = action {
                if let startEpoch = responsiveAudioAuthorizedStartEpoch {
                    startResponsiveAudioPlayback(
                        attempt,
                        routeKey: nextKey,
                        startEpoch: startEpoch
                    )
                } else {
                    _ = responsiveAudioPolicy.completePlayback(
                        attempt,
                        didStart: false
                    )
                    responsiveAudioChoice = responsiveAudioPolicy.choice
                }
            }
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
                      self.presentation?.ephemeralResponseCleanupToken
                        == token else {
                    return
                }
                guard let cleared = try await model
                    .clearChapterSceneEphemeralResponse(
                        matching: token,
                        runtime: runtime,
                        identity: identity,
                        responsiveAudioIsUserAuthorized:
                            self.responsiveAudioChoice.authorizesPlayback
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

struct ProductionChapterView: View {
    @ObservedObject var model: JourneyModel
    @ObservedObject var session: ProductionChapterRouteSession
    let identity: ChapterRuntimeRouteIdentity
    @Environment(\.scenePhase) private var scenePhase
    @State private var continuousGestureCancellationEpoch: UInt64 = 0

    private var presentation: ChapterScenePresentation? {
        session.presentation(for: identity)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
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
                        identity: identity
                    )
                    .frame(maxHeight: geometry.size.height * 0.43, alignment: .bottom)
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
                        .accessibilityLabel("Responsive audio presentation")
                        .accessibilityValue(
                            "\(session.responsiveAudioChoice.rawValue):\(session.desiredResponsiveAudioPhase?.rawValue ?? "none")"
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
                        .accessibilityLabel("Responsive audio choice diagnostic")
                        .accessibilityValue(
                            session.responsiveAudioChoiceDiagnosticForTesting
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
                            model.showWorld(expectedIdentity: identity)
                        }
                    )
                    .accessibilityHidden(true)
                }

                VStack {
                    HStack {
                        Button("Return to the road") {
                            model.showWorld(expectedIdentity: identity)
                        }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(red: 0.86, green: 0.70, blue: 0.40))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(.black.opacity(0.62), in: Capsule())
                            .disabled(
                                model.chapterTransitionIsPending
                                    || session.inputIsPending
                                    || session
                                        .lifecyclePresentationRefreshIsPending
                            )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, geometry.safeAreaInsets.top + 8)

                if let failure = session.failure {
                    ChapterRouteFailureSurface(message: failure.message) {
                        model.showWorldRecoveringChapterFailure(
                            expectedIdentity: identity
                        )
                    }
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

private struct ChapterNarrativeSurface: View {
    let presentation: ChapterScenePresentation
    @ObservedObject var model: JourneyModel
    @ObservedObject var session: ProductionChapterRouteSession
    let identity: ChapterRuntimeRouteIdentity

    private var interactionIsComplete: Bool {
        presentation.journeyState.activeChapter?.interaction?.phase == .complete
    }

    private var canAdvance: Bool {
        presentation.cursor.beat.interaction == nil || interactionIsComplete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(presentation.cursor.chapter.period.launchEnglish.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color(red: 0.74, green: 0.63, blue: 0.43))
                Text(presentation.cursor.beat.narrative.heading.launchEnglish)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.87))
                    .accessibilityAddTraits(.isHeader)
                ForEach(presentation.cursor.beat.narrative.paragraphs) { paragraph in
                    Text(paragraph.launchEnglish)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(Color(red: 0.84, green: 0.83, blue: 0.79))
                }

                if presentation.cursor.responsiveAudioProgram != nil,
                   session.responsiveAudioChoice != .playing {
                    ChapterResponsiveAudioChoiceSurface(
                        choice: session.responsiveAudioChoice,
                        isEnabled: !session.inputIsPending
                            && !session.lifecyclePresentationRefreshIsPending,
                        hearScene: {
                            session.hearScene(expectedIdentity: identity)
                        },
                        continueInSilence: {
                            session.continueInSilence(
                                expectedIdentity: identity
                            )
                        }
                    )
                }

                if let interaction = presentation.cursor.beat.interaction,
                   !interactionIsComplete {
                    Text(
                        presentation.cursor.beat.narrative.actionPrompt?.launchEnglish
                            ?? interaction.prompt.launchEnglish
                    )
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Color(red: 0.90, green: 0.73, blue: 0.43))

                    if case .allocate = interaction.grammar {
                        Button("Set the allocation") {
                            session.submitTouch(
                                .commitAllocation,
                                expectedIdentity: identity
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.82, green: 0.64, blue: 0.34))
                        .foregroundStyle(.black)
                        .disabled(session.inputIsPending)
                        .accessibilityHidden(true)
                    }
                }

                if canAdvance {
                    Button {
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
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.82, green: 0.64, blue: 0.34))
                    .foregroundStyle(.black)
                    .controlSize(.large)
                    .disabled(
                        model.chapterTransitionIsPending
                            || session.inputIsPending
                            || session.lifecyclePresentationRefreshIsPending
                    )
                    .accessibilityIdentifier("chapter-continue")
                }

                if let audioFailure = model.responsiveAudioFailure {
                    Text(audioFailure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(.black.opacity(0.64))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chapter-beat-\(presentation.cursor.beat.id)")
    }
}

private struct ChapterResponsiveAudioChoiceSurface: View {
    let choice: ChapterResponsiveAudioChoice
    let isEnabled: Bool
    let hearScene: () -> Void
    let continueInSilence: () -> Void

    private let accent = Color(red: 0.82, green: 0.64, blue: 0.34)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if choice == .resumeRequired {
                Text("Sound paused")
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color(red: 0.74, green: 0.63, blue: 0.43))
                    .textCase(.uppercase)
            }

            if choice == .starting {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(accent)
                    Text("Opening sound")
                        .font(.system(.body, design: .serif, weight: .medium))
                        .foregroundStyle(Color(red: 0.88, green: 0.86, blue: 0.80))
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Opening sound")
                .accessibilityIdentifier("chapter-audio-starting")
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { controls }
                    VStack(alignment: .leading, spacing: 10) { controls }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chapter-responsive-audio-choice")
    }

    @ViewBuilder
    private var controls: some View {
        Button(action: hearScene) {
            Label("Hear the scene", systemImage: "waveform")
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .foregroundStyle(.black)
        .accessibilityLabel("Hear the scene")
        .accessibilityIdentifier("chapter-audio-hear-scene")
        .disabled(!isEnabled)

        if choice == .undecided {
            Button("Continue in silence", action: continueInSilence)
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.82, green: 0.80, blue: 0.74))
                .frame(minHeight: 44)
                .accessibilityLabel("Continue in silence")
                .accessibilityIdentifier("chapter-audio-continue-silently")
                .disabled(!isEnabled)
        }
    }
}

private struct ChapterRouteFailureSurface: View {
    let message: String
    let returnToRoad: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("This scene could not be opened.")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(Color(red: 0.90, green: 0.84, blue: 0.72))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .foregroundStyle(.secondary)
            Button("Return to the road", action: returnToRoad)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.52, green: 0.37, blue: 0.20))
                .accessibilityIdentifier("chapter-failure-return-to-road")
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.035, green: 0.029, blue: 0.027))
    }
}

private struct ChapterSemanticInteractionSurface: View {
    let semanticModel: SemanticInteractionModel?
    let submit: (String, AccessibilityActionSpec) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let semanticModel {
                ForEach(semanticModel.controls) { control in
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

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(control.label)
            .accessibilityValue(control.value ?? "")
            .accessibilityHint(control.hint ?? "")
            .accessibilityIdentifier("chapter-semantic-\(control.id)")
            .accessibilityAction {
                if let activation { submit(control.id, activation) }
            }
            .accessibilityAdjustableAction { direction in
                let kind: ContentKit.AccessibilityActionKind = direction == .increment
                    ? .increment : .decrement
                if let action = control.actions.first(where: { $0.kind == kind }) {
                    submit(control.id, action)
                }
            }
            .accessibilityActions {
                ForEach(Array(control.actions.enumerated()), id: \.offset) { _, action in
                    Button(action.label.launchEnglish) { submit(control.id, action) }
                }
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
