import ContentKit
import DramaticAudio
import Foundation
import JourneyAccessibility
import JourneyContent
import JourneyDomain
import ProgressStore
import SceneRuntime

public enum ChapterSceneEphemeralResponseKind: String, Equatable, Sendable {
    case cancelledSnapBack
    case reducerResistance
    case accepted
}

/// Identifies one bounded presentation-only response. The epoch prevents a
/// late cleanup task from clearing a newer, value-identical rejection.
public struct ChapterSceneEphemeralResponseCleanupToken: Equatable, Sendable {
    public let kind: ChapterSceneEphemeralResponseKind
    fileprivate let epoch: UInt64

    fileprivate init(
        kind: ChapterSceneEphemeralResponseKind,
        epoch: UInt64
    ) {
        self.kind = kind
        self.epoch = epoch
    }
}

/// Authored upper bounds for terminal gesture responses. The route injects
/// its sleeper, so tests can advance this lifecycle without wall-clock waits.
public struct ChapterSceneEphemeralResponseTiming: Equatable, Sendable {
    public let cancelledSnapBackNanoseconds: UInt64
    public let reducerResistanceNanoseconds: UInt64
    public let acceptedNanoseconds: UInt64

    public init(
        cancelledSnapBackNanoseconds: UInt64,
        reducerResistanceNanoseconds: UInt64,
        acceptedNanoseconds: UInt64
    ) {
        self.cancelledSnapBackNanoseconds = cancelledSnapBackNanoseconds
        self.reducerResistanceNanoseconds = reducerResistanceNanoseconds
        self.acceptedNanoseconds = acceptedNanoseconds
    }

    public func delayNanoseconds(
        for kind: ChapterSceneEphemeralResponseKind
    ) -> UInt64 {
        switch kind {
        case .cancelledSnapBack:
            cancelledSnapBackNanoseconds
        case .reducerResistance:
            reducerResistanceNanoseconds
        case .accepted:
            acceptedNanoseconds
        }
    }

    public static let authored = Self(
        cancelledSnapBackNanoseconds:
            SceneTransientResponseTimeline.snapBackDurationMilliseconds * 1_000_000,
        reducerResistanceNanoseconds: 260_000_000,
        acceptedNanoseconds: 180_000_000
    )
}

/// One immutable projection of the durable Journey into the scene-facing
/// runtime. It is output only: the controller never uses this value as a
/// second state authority beside its `DurableJourneyCommitter`.
public struct ChapterScenePresentation: Equatable, Sendable {
    public let cursor: ChapterCursor
    public let journeyState: JourneyState
    public let framePlan: SceneFramePlan
    public let metalPreparationPlan: SceneMetalPreparationPlan
    public let semanticInteractionModel: SemanticInteractionModel?
    /// Grammar-neutral response from the last accepted interaction action.
    /// Touch and VoiceOver enter the same reducer before this value is
    /// published, so scene-facing systems never infer feedback from input
    /// modality. Nil denotes an initial, restored or direct-manipulation-only
    /// presentation.
    public let interactionFeedback: InteractionFeedback?
    public let directManipulation: SceneDirectManipulationState?
    let ephemeralResponseEpoch: UInt64?

    public var ephemeralResponseCleanupToken:
        ChapterSceneEphemeralResponseCleanupToken? {
        guard let ephemeralResponseEpoch,
              let kind = Self.ephemeralResponseKind(
                  feedback: interactionFeedback,
                  directManipulation: directManipulation
              ) else {
            return nil
        }
        return ChapterSceneEphemeralResponseCleanupToken(
            kind: kind,
            epoch: ephemeralResponseEpoch
        )
    }

    public init(
        cursor: ChapterCursor,
        journeyState: JourneyState,
        framePlan: SceneFramePlan,
        metalPreparationPlan: SceneMetalPreparationPlan,
        semanticInteractionModel: SemanticInteractionModel?,
        interactionFeedback: InteractionFeedback?,
        directManipulation: SceneDirectManipulationState?,
        ephemeralResponseEpoch: UInt64? = nil
    ) {
        self.cursor = cursor
        self.journeyState = journeyState
        self.framePlan = framePlan
        self.metalPreparationPlan = metalPreparationPlan
        self.semanticInteractionModel = semanticInteractionModel
        self.interactionFeedback = interactionFeedback
        self.directManipulation = directManipulation
        self.ephemeralResponseEpoch = ephemeralResponseEpoch
    }

    fileprivate static func ephemeralResponseKind(
        feedback: InteractionFeedback?,
        directManipulation: SceneDirectManipulationState?
    ) -> ChapterSceneEphemeralResponseKind? {
        if let directManipulation {
            switch directManipulation.outcome {
            case .cancelled:
                return .cancelledSnapBack
            case .rejectedByReducer:
                return .reducerResistance
            case .accepted:
                return .accepted
            case .pending:
                break
            }
        }
        switch feedback {
        case .some(.resistance):
            return .reducerResistance
        case .some(.contact), .some(.progress), .some(.threshold):
            return .accepted
        case nil, .some(.none), .some(.completed):
            return nil
        }
    }
}

/// The result of one scene input. Contact, lift, carry, slot approach and
/// cancellation updates have no commit or preview because they remain
/// presentation-only gesture state.
public struct ChapterSceneTransition: Equatable, Sendable {
    public let presentation: ChapterScenePresentation
    public let preview: SceneInteractionPreview?
    public let durableCommit: DurableJourneyCommit?
    public let responsiveAudioCommit: DurableJourneyCommit?
    /// Non-nil only when history crossed the durable boundary but a later
    /// consequence-side operation failed. Callers must treat `durableCommit`
    /// as accepted and must never retry its domain action.
    public let postCommitIssue: ChapterScenePostCommitIssue?

    public init(
        presentation: ChapterScenePresentation,
        preview: SceneInteractionPreview?,
        durableCommit: DurableJourneyCommit?,
        responsiveAudioCommit: DurableJourneyCommit?,
        postCommitIssue: ChapterScenePostCommitIssue? = nil
    ) {
        self.presentation = presentation
        self.preview = preview
        self.durableCommit = durableCommit
        self.responsiveAudioCommit = responsiveAudioCommit
        self.postCommitIssue = postCommitIssue
    }
}

/// A display-only response for raw Trace, Pressure or Transform motion.
/// `interactionPreview` is a pure reducer proposal; `presentation` retains the
/// exact committed JourneyState and current signed texture set, adding only a
/// shader-level contact response. Publishing it therefore cannot complete an
/// interaction, emit effects, append history or become restoration authority.
public enum ChapterSceneContinuousTouchSemantic: Equatable, Sendable {
    case ordinary
    case traceAnchor(Int)
    case pressureStabilityBoundary(isStable: Bool)
    case transformStage(Int)
}

public struct ChapterSceneContinuousTouchPreview: Equatable, Sendable {
    public let presentation: ChapterScenePresentation
    public let interactionPreview: SceneInteractionPreview
    public let semantic: ChapterSceneContinuousTouchSemantic

    public init(
        presentation: ChapterScenePresentation,
        interactionPreview: SceneInteractionPreview,
        semantic: ChapterSceneContinuousTouchSemantic
    ) {
        self.presentation = presentation
        self.interactionPreview = interactionPreview
        self.semantic = semantic
    }
}

public enum ChapterScenePostCommitIssue: String, Equatable, Sendable {
    case durableStateDivergedFromPreflight
    case audioConsequenceAuthorityInvalid
    case audioCausalStageAuthorityInvalid
    case audioBridgeFailed
    case audioSnapshotAuthorityMismatch
    case audioCausalStageSnapshotMismatch
    case audioFollowUpRejected
    case audioFollowUpDivergedFromPreflight
}

/// Narrow semantic haptic boundary shared by ephemeral gesture responses and
/// already-durable Journey consequences. The controller preserves that
/// distinction: contact/rejection are presentation-only; completion is emitted
/// only from a successful commit.
@MainActor
public protocol ChapterRuntimeHapticBridging: AnyObject {
    func play(_ semantic: HapticSemantic)
}

#if os(iOS)
extension NativeSemanticHapticTransport: ChapterRuntimeHapticBridging {}
#endif

/// Optional responsive-audio hook. Each receipt proves that `commit` already
/// crossed the durable interaction boundary. Returning a snapshot is
/// deliberately narrower than returning an arbitrary Journey action; this
/// controller alone creates and commits the follow-up.
public protocol ChapterRuntimeAudioConsequenceBridging: Sendable {
    func responsiveAudioSnapshot(
        after commit: DurableJourneyCommit,
        causalStageAuthority: DurableInteractionAudioCausalStageReceipt
    ) async throws -> ResponsiveAudioProgramSnapshot?

    func responsiveAudioSnapshot(
        after commit: DurableJourneyCommit,
        authority: DurableInteractionAudioCompletionReceipt
    ) async throws -> ResponsiveAudioProgramSnapshot?
}

public extension ChapterRuntimeAudioConsequenceBridging {
    /// Existing phase-only bridges have no historical-stage follow-up.
    func responsiveAudioSnapshot(
        after _: DurableJourneyCommit,
        causalStageAuthority _: DurableInteractionAudioCausalStageReceipt
    ) async throws -> ResponsiveAudioProgramSnapshot? {
        nil
    }
}

public enum ChapterSceneRuntimeControllerError: Error, Equatable, Sendable {
    case presentationDivergedFromCommitter
    case noActiveChapterSession
    case noActiveInteraction
    case interactionAlreadyComplete
    case interactionStateMismatch
    case candidateJourneyRejected
    case candidateInteractionMismatch
    case unsupportedContinuousTouchPreview
    case continuousTouchPreviewFrameMismatch
}

/// The sole presentation bridge from durable `JourneyState` to SceneRuntime.
///
/// The controller receives the app's one committer. Scene interaction inputs
/// accepted through `submitTouch` and `submitVoiceOver` are FIFO-serialised
/// across preflight, journal append, presentation publication, haptics and any
/// durable audio follow-up. Navigation, beat advancement and other app-shell
/// actions are outside this queue. The committer's conditional revision gate
/// prevents those independent owners from invalidating a scene preflight and
/// still causing its stale action to append.
@MainActor
public final class ChapterSceneRuntimeController {
    public private(set) var presentation: ChapterScenePresentation

    private let coordinator: ChapterCoordinator
    private let assets: SceneAssetInventory
    private let viewportCropID: String
    private let reduceMotion: Bool
    private let committer: DurableJourneyCommitter
    private let hapticBridge: (any ChapterRuntimeHapticBridging)?
    private let audioConsequenceBridge: (any ChapterRuntimeAudioConsequenceBridging)?

    private struct TransitionWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var transitionIsInFlight = false
    private var transitionWaiters: [TransitionWaiter] = []
    private var nextEphemeralResponseEpoch: UInt64 = 0

    private struct ContinuousTouchProjection {
        let committedState: JourneyState
        var runtimeState: InteractionRuntimeState
        var terminalSemantic: ChapterSceneContinuousTouchSemantic?
    }

    private var continuousTouchProjection: ContinuousTouchProjection?

    private struct GestureContactKey: Equatable {
        let subjectID: String?
        let sourceTargetID: String?
    }

    private var activeGestureContactKey: GestureContactKey?

    public init(
        committer: DurableJourneyCommitter,
        coordinator: ChapterCoordinator,
        assets: SceneAssetInventory,
        viewportCropID: String,
        reduceMotion: Bool,
        hapticBridge: (any ChapterRuntimeHapticBridging)? = nil,
        audioConsequenceBridge: (any ChapterRuntimeAudioConsequenceBridging)? = nil
    ) async throws {
        self.coordinator = coordinator
        self.assets = assets
        self.viewportCropID = viewportCropID
        self.reduceMotion = reduceMotion
        self.hapticBridge = hapticBridge
        self.audioConsequenceBridge = audioConsequenceBridge
        self.committer = committer
        let state = await committer.currentCommittedState()
        presentation = try Self.makePresentation(
            state: state,
            coordinator: coordinator,
            assets: assets,
            viewportCropID: viewportCropID,
            reduceMotion: reduceMotion,
            directManipulation: nil
        )
    }

    /// Internal construction boundary for tests. Production callers can only
    /// inject the app's existing committer through the public initializer.
    convenience init(
        restoration: JourneyRestoration,
        coordinator: ChapterCoordinator,
        assets: SceneAssetInventory,
        viewportCropID: String,
        reduceMotion: Bool,
        append: @escaping DurableJourneyCommitter.AppendOperation,
        hapticBridge: (any ChapterRuntimeHapticBridging)? = nil,
        audioConsequenceBridge: (any ChapterRuntimeAudioConsequenceBridging)? = nil
    ) async throws {
        let committer = DurableJourneyCommitter(
            restoredState: restoration.state,
            lastSequence: restoration.lastSequence,
            append: append
        )
        try await self.init(
            committer: committer,
            coordinator: coordinator,
            assets: assets,
            viewportCropID: viewportCropID,
            reduceMotion: reduceMotion,
            hapticBridge: hapticBridge,
            audioConsequenceBridge: audioConsequenceBridge
        )
    }

    /// Resolves a gesture against the exact frame currently displayed. An
    /// Direct-manipulation motion may update the frame, but cannot reach the
    /// journal because it contains no `InteractionAction`.
    @discardableResult
    public func submitTouch(
        _ intent: SceneTouchIntent,
        alphaSampler: (any SceneAlphaMaskSampling)? = nil
    ) async throws -> ChapterSceneTransition {
        try await acquireTransitionSlot()
        return try await finishAcceptedTransition { [self] in
            try await processTouch(intent, alphaSampler: alphaSampler)
        }
    }

    /// Produces immediate display feedback for high-frequency motion without
    /// entering the transition slot or the durability boundary. The caller
    /// supplies the exact frame currently on screen so an in-flight durable
    /// update cannot make touch geometry or texture identity jump ahead of
    /// what the user can see.
    public func previewContinuousTouch(
        _ intent: SceneTouchIntent,
        displayedFramePlan: SceneFramePlan,
        alphaSampler: (any SceneAlphaMaskSampling)? = nil
    ) throws -> ChapterSceneContinuousTouchPreview {
        let state = presentation.journeyState
        let context = try interactionContext(state: state)
        guard displayedFramePlan.sceneID == context.cursor.scene.id,
              displayedFramePlan.viewportCropID == viewportCropID,
              displayedFramePlan.reduceMotion == reduceMotion else {
            throw ChapterSceneRuntimeControllerError
                .continuousTouchPreviewFrameMismatch
        }
        let activeProjection: ContinuousTouchProjection?
        if let continuousTouchProjection,
           continuousTouchProjection.committedState == state,
           continuousTouchProjection.runtimeState.interactionID
                == context.interaction.id {
            activeProjection = continuousTouchProjection
        } else {
            activeProjection = nil
        }
        let projectedRuntimeState = activeProjection?.runtimeState
            ?? context.runtimeState
        let resolution = try SceneTouchActionResolver.resolve(
            intent,
            scene: context.cursor.scene,
            interaction: context.interaction,
            runtimeState: projectedRuntimeState,
            frame: displayedFramePlan,
            accessibility: context.cursor.accessibility,
            alphaSampler: alphaSampler
        )
        guard let action = resolution.action else {
            throw ChapterSceneRuntimeControllerError
                .unsupportedContinuousTouchPreview
        }
        switch action {
        case .trace, .setPressure, .transform:
            break
        case .begin, .allocate, .commitAllocation, .place,
             .advancePressure, .reset:
            throw ChapterSceneRuntimeControllerError
                .unsupportedContinuousTouchPreview
        }
        let interactionPreview = try SceneInteractionDriver.preview(
            spec: context.interaction,
            state: projectedRuntimeState,
            input: .touch(action)
        )
        var semantic = continuousTouchSemantic(
            before: projectedRuntimeState,
            after: interactionPreview.candidateState,
            interaction: context.interaction
        )
        if interactionPreview.candidateState.phase == .complete {
            if activeProjection?.terminalSemantic == semantic {
                semantic = .ordinary
            }
            continuousTouchProjection = ContinuousTouchProjection(
                committedState: state,
                runtimeState: projectedRuntimeState,
                terminalSemantic: semantic == .ordinary
                    ? activeProjection?.terminalSemantic : semantic
            )
        } else {
            continuousTouchProjection = ContinuousTouchProjection(
                committedState: state,
                runtimeState: interactionPreview.candidateState,
                terminalSemantic: nil
            )
        }
        let previewFrame = try continuousTouchFeedbackFrame(
            displayedFramePlan,
            resolution: resolution,
            intent: intent
        )
        let previewPresentation = ChapterScenePresentation(
            cursor: presentation.cursor,
            journeyState: state,
            framePlan: previewFrame,
            metalPreparationPlan: try SceneMetalPreparationPlanner.make(
                from: previewFrame
            ),
            semanticInteractionModel:
                presentation.semanticInteractionModel,
            interactionFeedback: nil,
            directManipulation: nil
        )
        return ChapterSceneContinuousTouchPreview(
            presentation: previewPresentation,
            interactionPreview: interactionPreview,
            semantic: semantic
        )
    }

    public func resetContinuousTouchPreview() {
        continuousTouchProjection = nil
    }

    /// Ends display-only raw motion on the exact presentation the caller has
    /// already published. The controller's durable presentation may be newer
    /// while the route prepares its textures, so this deliberately never
    /// projects from or mutates that newer authority.
    @discardableResult
    public func neutralizeContinuousTouchPreview(
        displayedPresentation: ChapterScenePresentation
    ) throws
        -> ChapterScenePresentation {
        continuousTouchProjection = nil
        let displayedFrame = displayedPresentation.framePlan
        guard displayedFrame.sceneID
                == displayedPresentation.cursor.scene.id,
              displayedFrame.viewportCropID == viewportCropID,
              displayedFrame.reduceMotion == reduceMotion else {
            throw ChapterSceneRuntimeControllerError
                .continuousTouchPreviewFrameMismatch
        }
        let neutralFrame = SceneFramePlan(
            sceneID: displayedFrame.sceneID,
            viewportCropID: displayedFrame.viewportCropID,
            viewport: displayedFrame.viewport,
            deterministicTick: displayedFrame.deterministicTick,
            reduceMotion: displayedFrame.reduceMotion,
            camera: displayedFrame.camera,
            drawCommands: displayedFrame.drawCommands,
            atmosphere: displayedFrame.atmosphere,
            interactionSourceHitRegion:
                displayedFrame.interactionSourceHitRegion,
            interactionHitRegions: displayedFrame.interactionHitRegions,
            interactionResponse: nil,
            safeTextRegions: displayedFrame.safeTextRegions
        )
        return ChapterScenePresentation(
            cursor: displayedPresentation.cursor,
            journeyState: displayedPresentation.journeyState,
            framePlan: neutralFrame,
            metalPreparationPlan: try SceneMetalPreparationPlanner.make(
                from: neutralFrame
            ),
            semanticInteractionModel:
                displayedPresentation.semanticInteractionModel,
            interactionFeedback: nil,
            directManipulation: nil
        )
    }

    private func processTouch(
        _ intent: SceneTouchIntent,
        alphaSampler: (any SceneAlphaMaskSampling)?
    ) async throws -> ChapterSceneTransition {
        let authority = await committer.currentCommittedSnapshot()
        let state = authority.state
        try requirePublishedAuthority(state)
        let context = try interactionContext(state: state)
        let resolution = try SceneTouchActionResolver.resolve(
            intent,
            scene: context.cursor.scene,
            interaction: context.interaction,
            runtimeState: context.runtimeState,
            frame: presentation.framePlan,
            accessibility: context.cursor.accessibility,
            alphaSampler: alphaSampler
        )

        guard let action = resolution.action else {
            let preservedFeedback = resolution.directManipulation == nil
                ? presentation.interactionFeedback
                : nil
            let ephemeral = try makePresentation(
                state: state,
                interactionFeedback: preservedFeedback,
                directManipulation: resolution.directManipulation
            )
            presentation = ephemeral
            emitEphemeralHaptic(for: resolution.directManipulation)
            return ChapterSceneTransition(
                presentation: ephemeral,
                preview: nil,
                durableCommit: nil,
                responsiveAudioCommit: nil,
                postCommitIssue: nil
            )
        }

        return try await submit(
            action: action,
            source: .touch,
            touchResolution: resolution,
            authority: authority,
            context: context
        )
    }

    /// Translates one authored VoiceOver operation to the same domain action
    /// as touch before entering the shared submission path.
    @discardableResult
    public func submitVoiceOver(
        elementID: String,
        authoredAction: AccessibilityActionSpec
    ) async throws -> ChapterSceneTransition {
        try await acquireTransitionSlot()
        return try await finishAcceptedTransition { [self] in
            try await processVoiceOver(
                elementID: elementID,
                authoredAction: authoredAction
            )
        }
    }

    private func processVoiceOver(
        elementID: String,
        authoredAction: AccessibilityActionSpec
    ) async throws -> ChapterSceneTransition {
        let authority = await committer.currentCommittedSnapshot()
        let state = authority.state
        try requirePublishedAuthority(state)
        let context = try interactionContext(state: state)
        let action = try SemanticInteractionAdapter.action(
            for: elementID,
            authoredAction: authoredAction,
            spec: context.interaction,
            accessibility: context.cursor.accessibility,
            state: context.runtimeState
        )
        emitEphemeralSemanticContactHapticIfNeeded(action)
        return try await submit(
            action: action,
            source: .semantic,
            touchResolution: nil,
            authority: authority,
            context: context
        )
    }

    /// Reprojects the current committed state without advancing history.
    @discardableResult
    public func restorePresentation(
        preserving interactionFeedback: InteractionFeedback? = nil,
        directManipulation: SceneDirectManipulationState? = nil
    ) async throws -> ChapterScenePresentation {
        try await acquireTransitionSlot()
        return try await finishAcceptedTransition { [self] in
            try await processRestorePresentation(
                interactionFeedback: interactionFeedback,
                directManipulation: directManipulation
            )
        }
    }

    /// Clears one terminal response only while it is still the exact response
    /// scheduled by the route. This mutates neither the Journey journal nor its
    /// interaction state and is safe to call after the delay raced newer input.
    @discardableResult
    public func clearEphemeralInteractionResponse(
        matching token: ChapterSceneEphemeralResponseCleanupToken
    ) async throws -> ChapterScenePresentation? {
        try await acquireTransitionSlot()
        return try await finishAcceptedTransition { [self] in
            guard presentation.ephemeralResponseCleanupToken == token else {
                return nil
            }
            let authority = await committer.currentCommittedSnapshot()
            try reconcileResponsiveAudioAuthorityIfPossible(
                authority.state,
                interactionFeedback: presentation.interactionFeedback,
                directManipulation: presentation.directManipulation
            )
            guard presentation.journeyState == authority.state else {
                throw ChapterSceneRuntimeControllerError
                    .presentationDivergedFromCommitter
            }
            let cleared = try makePresentation(
                state: authority.state,
                interactionFeedback: nil,
                directManipulation: nil
            )
            presentation = cleared
            activeGestureContactKey = nil
            return cleared
        }
    }

    private func processRestorePresentation(
        interactionFeedback: InteractionFeedback?,
        directManipulation: SceneDirectManipulationState?
    ) async throws -> ChapterScenePresentation {
        let authority = await committer.currentCommittedSnapshot()
        let restored = try makePresentation(
            state: authority.state,
            interactionFeedback: interactionFeedback,
            directManipulation: directManipulation
        )
        presentation = restored
        return restored
    }

    /// Reprojects one externally committed responsive-audio change into this
    /// controller before a route publishes that playback has started. The
    /// committer may have advanced only its monotonic event metadata and the
    /// active chapter session's four responsive-audio fields. Any other durable
    /// change still invalidates this controller instead of being hidden by a
    /// broad presentation refresh.
    @discardableResult
    public func synchronizeResponsiveAudioPresentation(
        preserving interactionFeedback: InteractionFeedback? = nil,
        directManipulation: SceneDirectManipulationState? = nil
    ) async throws -> ChapterScenePresentation {
        try await acquireTransitionSlot()
        return try await finishAcceptedTransition { [self] in
            let state = await committer.currentCommittedState()
            try reconcileResponsiveAudioAuthorityIfPossible(
                state,
                interactionFeedback: interactionFeedback,
                directManipulation: directManipulation
            )
            try requirePublishedAuthority(state)
            return presentation
        }
    }

    private enum InputSource {
        case touch
        case semantic
    }

    private struct InteractionContext {
        let cursor: ChapterCursor
        let interaction: InteractionSpec
        let runtimeState: InteractionRuntimeState
    }

    private func submit(
        action: InteractionAction,
        source: InputSource,
        touchResolution: SceneTouchActionResolution?,
        authority: DurableJourneyStateSnapshot,
        context: InteractionContext
    ) async throws -> ChapterSceneTransition {
        let state = authority.state
        guard state.activeChapter?.interaction == context.runtimeState else {
            throw ChapterSceneRuntimeControllerError.interactionStateMismatch
        }
        let input: SceneInteractionInput = switch source {
        case .touch: .touch(action)
        case .semantic: .semantic(action)
        }
        let preview = try SceneInteractionDriver.preview(
            spec: context.interaction,
            state: context.runtimeState,
            input: input
        )

        let responseOverlay: SceneDirectManipulationState?
        if let touchResolution {
            responseOverlay = try SceneTouchActionResolver.directManipulationAfterPreview(
                resolution: touchResolution,
                preview: preview
            )
        } else {
            responseOverlay = nil
        }

        if case .place = action,
           preview.feedback == .resistance {
            // A rejected placement is local resistance, not a historical
            // mutation. Touch and VoiceOver share this reducer decision; its
            // pure preview is discarded without appending an event or changing
            // the Journey revision.
            let rejected = try makePresentation(
                state: state,
                interactionFeedback: .resistance,
                directManipulation: responseOverlay
            )
            presentation = rejected
            emitEphemeralResistanceHaptic()
            activeGestureContactKey = nil
            return ChapterSceneTransition(
                presentation: rejected,
                preview: preview,
                durableCommit: nil,
                responsiveAudioCommit: nil,
                postCommitIssue: nil
            )
        }
        let domainAction = JourneyAction.interact(
            spec: context.interaction,
            action: action
        )
        let candidateTransition = try preflight(
            action: domainAction,
            from: state,
            logicalTimeMillis: authority.logicalTimeMillis,
            interactionFeedback: preview.feedback,
            directManipulation: responseOverlay
        )
        guard candidateTransition.state.activeChapter?.interaction == preview.candidateState else {
            throw ChapterSceneRuntimeControllerError.candidateInteractionMismatch
        }

        let durableCommit = try await committer.commit(
            domainAction,
            expectedRevision: authority.revision
        )
        let suppressesDuplicateAssembleContact = shouldSuppressDurableContact(
            source: source,
            action: action
        )
        guard durableCommit.event == candidateTransition.event,
              durableCommit.state == candidateTransition.state,
              durableCommit.effects == candidateTransition.effects else {
            // The commit is real even if another owner violated the active
            // chapter routing rule between preflight and append. Return it as
            // accepted and retain the last known coherent presentation.
            emitHaptics(
                from: durableCommit,
                suppressingContact: suppressesDuplicateAssembleContact
            )
            finishGestureIfNeeded(action)
            return ChapterSceneTransition(
                presentation: presentation,
                preview: preview,
                durableCommit: durableCommit,
                responsiveAudioCommit: nil,
                postCommitIssue: .durableStateDivergedFromPreflight
            )
        }

        var published = candidateTransition.presentation
        presentation = published

        // These effects become observable only after DurableJourneyCommitter
        // has returned from its write-ahead append.
        emitHaptics(
            from: durableCommit,
            suppressingContact: suppressesDuplicateAssembleContact
        )
        finishGestureIfNeeded(action)

        var responsiveAudioCommit: DurableJourneyCommit?
        if let audioConsequenceBridge {
            let causalAuthority: DurableInteractionAudioCausalStageReceipt?
            do {
                causalAuthority = try DurableInteractionAudioCausalStageReceipt.make(
                    from: durableCommit
                )
            } catch {
                return ChapterSceneTransition(
                    presentation: published,
                    preview: preview,
                    durableCommit: durableCommit,
                    responsiveAudioCommit: nil,
                    postCommitIssue: .audioCausalStageAuthorityInvalid
                )
            }

            let snapshot: ResponsiveAudioProgramSnapshot?
            let expectedCompletionSequence: UInt64?
            if isInteractionConsequence(durableCommit) {
                let completionAuthority: DurableInteractionAudioCompletionReceipt
                do {
                    completionAuthority = try DurableInteractionAudioCompletionReceipt.make(
                        from: durableCommit
                    )
                } catch {
                    return ChapterSceneTransition(
                        presentation: published,
                        preview: preview,
                        durableCommit: durableCommit,
                        responsiveAudioCommit: nil,
                        postCommitIssue: .audioConsequenceAuthorityInvalid
                    )
                }
                expectedCompletionSequence = completionAuthority.sequence
                do {
                    snapshot = try await audioConsequenceBridge.responsiveAudioSnapshot(
                        after: durableCommit,
                        authority: completionAuthority
                    )
                } catch {
                    return ChapterSceneTransition(
                        presentation: published,
                        preview: preview,
                        durableCommit: durableCommit,
                        responsiveAudioCommit: nil,
                        postCommitIssue: .audioBridgeFailed
                    )
                }
            } else if let causalAuthority {
                expectedCompletionSequence = nil
                do {
                    snapshot = try await audioConsequenceBridge.responsiveAudioSnapshot(
                        after: durableCommit,
                        causalStageAuthority: causalAuthority
                    )
                } catch {
                    return ChapterSceneTransition(
                        presentation: published,
                        preview: preview,
                        durableCommit: durableCommit,
                        responsiveAudioCommit: nil,
                        postCommitIssue: .audioBridgeFailed
                    )
                }
            } else {
                expectedCompletionSequence = nil
                snapshot = nil
            }

            if let snapshot {
                if let expectedCompletionSequence {
                    guard snapshot.stage == .consequence || snapshot.stage == .completed,
                          snapshot.durableCompletionSequence == expectedCompletionSequence else {
                        return ChapterSceneTransition(
                            presentation: published,
                            preview: preview,
                            durableCommit: durableCommit,
                            responsiveAudioCommit: nil,
                            postCommitIssue: .audioSnapshotAuthorityMismatch
                        )
                    }
                } else if snapshot.stage == .consequence
                    || snapshot.stage == .completed
                    || snapshot.durableCompletionSequence != nil {
                    return ChapterSceneTransition(
                        presentation: published,
                        preview: preview,
                        durableCommit: durableCommit,
                        responsiveAudioCommit: nil,
                        postCommitIssue: .audioSnapshotAuthorityMismatch
                    )
                }
                if snapshot.causalStage != causalAuthority?.causalStage {
                    return ChapterSceneTransition(
                        presentation: published,
                        preview: preview,
                        durableCommit: durableCommit,
                        responsiveAudioCommit: nil,
                        postCommitIssue: .audioCausalStageSnapshotMismatch
                    )
                }
                let beforeAudioState = durableCommit.state
                let followUpAction = JourneyAction.setResponsiveAudioSnapshot(snapshot)
                let followUpPreflight: CandidateTransition
                do {
                    followUpPreflight = try preflight(
                        action: followUpAction,
                        from: beforeAudioState,
                        logicalTimeMillis: durableCommit.event.logicalTimeMillis,
                        interactionFeedback: preview.feedback,
                        directManipulation: responseOverlay
                    )
                } catch {
                    return ChapterSceneTransition(
                        presentation: published,
                        preview: preview,
                        durableCommit: durableCommit,
                        responsiveAudioCommit: nil,
                        postCommitIssue: .audioFollowUpRejected
                    )
                }
                let followUp: DurableJourneyCommit
                do {
                    followUp = try await committer.commit(
                        followUpAction,
                        expectedRevision: durableCommit.revision
                    )
                } catch {
                    return ChapterSceneTransition(
                        presentation: published,
                        preview: preview,
                        durableCommit: durableCommit,
                        responsiveAudioCommit: nil,
                        postCommitIssue: .audioFollowUpRejected
                    )
                }
                responsiveAudioCommit = followUp
                guard followUp.event == followUpPreflight.event,
                      followUp.state == followUpPreflight.state,
                      followUp.effects == followUpPreflight.effects,
                      followUp.state.activeChapter?.interaction
                        == beforeAudioState.activeChapter?.interaction,
                      followUp.state.world == beforeAudioState.world else {
                    return ChapterSceneTransition(
                        presentation: published,
                        preview: preview,
                        durableCommit: durableCommit,
                        responsiveAudioCommit: followUp,
                        postCommitIssue: .audioFollowUpDivergedFromPreflight
                    )
                }
                published = followUpPreflight.presentation
                presentation = published
                emitHaptics(from: followUp)
            }
        }

        return ChapterSceneTransition(
            presentation: published,
            preview: preview,
            durableCommit: durableCommit,
            responsiveAudioCommit: responsiveAudioCommit,
            postCommitIssue: nil
        )
    }

    private struct CandidateTransition {
        let event: JourneyEvent
        let state: JourneyState
        let effects: [JourneyEffect]
        let presentation: ChapterScenePresentation
    }

    /// Runs the exact Journey reducer and the complete scene projection on a
    /// private value before any bytes reach the append boundary.
    private func preflight(
        action: JourneyAction,
        from state: JourneyState,
        logicalTimeMillis: Int64,
        interactionFeedback: InteractionFeedback?,
        directManipulation: SceneDirectManipulationState?
    ) throws -> CandidateTransition {
        guard logicalTimeMillis < Int64.max else {
            throw DurableJourneyCommitterError.logicalClockExhausted
        }
        let event = JourneyEvent(
            logicalTimeMillis: logicalTimeMillis + 1,
            action: action
        )
        var candidate = state
        let effects = JourneyReducer().reduce(state: &candidate, event: event)
        guard !effects.contains(where: { effect in
            if case .rejected = effect { return true }
            return false
        }) else {
            throw ChapterSceneRuntimeControllerError.candidateJourneyRejected
        }
        return try CandidateTransition(
            event: event,
            state: candidate,
            effects: effects,
            presentation: makePresentation(
                state: candidate,
                interactionFeedback: interactionFeedback,
                directManipulation: directManipulation
            )
        )
    }

    private func continuousTouchSemantic(
        before: InteractionRuntimeState,
        after: InteractionRuntimeState,
        interaction: InteractionSpec
    ) -> ChapterSceneContinuousTouchSemantic {
        switch (interaction.grammar, before.progress, after.progress) {
        case let (
            .trace,
            .trace(previous),
            .trace(candidate)
        ) where candidate.reachedAnchorCount
            == previous.reachedAnchorCount + 1:
            return .traceAnchor(previous.reachedAnchorCount)

        case let (
            .pressure(configuration),
            .pressure(previous),
            .pressure(candidate)
        ):
            let wasStable = configuration.stableRange.contains(
                netPressure(configuration, progress: previous)
            )
            let isStable = configuration.stableRange.contains(
                netPressure(configuration, progress: candidate)
            )
            return wasStable == isStable
                ? .ordinary
                : .pressureStabilityBoundary(isStable: isStable)

        case let (
            .transform,
            .transform(previous),
            .transform(candidate)
        ) where candidate.completedStageCount
            == previous.completedStageCount + 1:
            return .transformStage(previous.completedStageCount)

        default:
            return .ordinary
        }
    }

    private func netPressure(
        _ configuration: PressureInteractionSpec,
        progress: PressureProgress
    ) -> Double {
        configuration.forces.reduce(0) { partial, force in
            partial + force.direction * (
                progress.values.first(where: {
                    $0.forceID == force.id
                })?.magnitude ?? force.initialMagnitude
            )
        }
    }

    private func continuousTouchFeedbackFrame(
        _ displayedFramePlan: SceneFramePlan,
        resolution: SceneTouchActionResolution,
        intent: SceneTouchIntent
    ) throws -> SceneFramePlan {
        guard let targetID = resolution.targetID else {
            throw ChapterSceneRuntimeControllerError
                .unsupportedContinuousTouchPreview
        }
        let targetRegions = displayedFramePlan.interactionHitRegions.filter {
            $0.interactionTargetID == targetID
        }
        guard targetRegions.count == 1,
              let targetRegion = targetRegions.first,
              displayedFramePlan.drawCommands.contains(where: { command in
                  guard case let .layer(layerID, _) = command.source else {
                      return false
                  }
                  return layerID == targetRegion.layerID
              }) else {
            throw ChapterSceneRuntimeControllerError
                .continuousTouchPreviewFrameMismatch
        }
        let rawContactAmount: Double = switch intent {
        case let .trace(viewportPoint):
            0.3 + 0.5 * min(
                1,
                max(0, (viewportPoint.x + viewportPoint.y) * 0.5)
            )
        case let .adjustTarget(_, amount):
            0.2 + 0.8 * min(1, max(0, amount))
        default:
            throw ChapterSceneRuntimeControllerError
                .unsupportedContinuousTouchPreview
        }
        let response = SceneInteractionResponsePlan(
            phase: .contact,
            targetID: targetID,
            transferLayerID: targetRegion.layerID,
            viewportMaterialPosition: nil,
            viewportTransferPath: [],
            progress: min(1, max(0, resolution.progress)),
            contactAmount: rawContactAmount,
            resistanceAmount: 0
        )
        return SceneFramePlan(
            sceneID: displayedFramePlan.sceneID,
            viewportCropID: displayedFramePlan.viewportCropID,
            viewport: displayedFramePlan.viewport,
            deterministicTick: displayedFramePlan.deterministicTick,
            reduceMotion: displayedFramePlan.reduceMotion,
            camera: displayedFramePlan.camera,
            drawCommands: displayedFramePlan.drawCommands,
            atmosphere: displayedFramePlan.atmosphere,
            interactionSourceHitRegion:
                displayedFramePlan.interactionSourceHitRegion,
            interactionHitRegions:
                displayedFramePlan.interactionHitRegions,
            interactionResponse: response,
            safeTextRegions: displayedFramePlan.safeTextRegions
        )
    }

    private func interactionContext(state: JourneyState) throws -> InteractionContext {
        guard let session = state.activeChapter else {
            throw ChapterSceneRuntimeControllerError.noActiveChapterSession
        }
        let cursor = try coordinator.currentCursor(state: state)
        guard let interaction = cursor.beat.interaction,
              let runtimeState = session.interaction else {
            throw ChapterSceneRuntimeControllerError.noActiveInteraction
        }
        guard runtimeState.interactionID == interaction.id else {
            throw ChapterSceneRuntimeControllerError.interactionStateMismatch
        }
        guard runtimeState.phase != .complete else {
            throw ChapterSceneRuntimeControllerError.interactionAlreadyComplete
        }
        return InteractionContext(
            cursor: cursor,
            interaction: interaction,
            runtimeState: runtimeState
        )
    }

    private func requirePublishedAuthority(_ state: JourneyState) throws {
        try reconcileResponsiveAudioAuthorityIfPossible(
            state,
            interactionFeedback: presentation.interactionFeedback,
            directManipulation: presentation.directManipulation
        )
        guard presentation.journeyState == state else {
            throw ChapterSceneRuntimeControllerError.presentationDivergedFromCommitter
        }
    }

    /// Closes the user race between a durable audio start/checkpoint and the
    /// route session's explicit presentation refresh. This is deliberately not
    /// a general rebase seam: camera, narration, interaction, beat, route,
    /// package, world and every inactive chapter session must remain byte-for-
    /// byte equivalent at the value level.
    private func reconcileResponsiveAudioAuthorityIfPossible(
        _ state: JourneyState,
        interactionFeedback: InteractionFeedback?,
        directManipulation: SceneDirectManipulationState?
    ) throws {
        let publishedState = presentation.journeyState
        guard publishedState != state else { return }
        guard ResponsiveAudioPresentationRebasePolicy.decide(
            published: publishedState,
            committed: state
        ) != .reject else {
            return
        }
        presentation = try makePresentation(
            state: state,
            interactionFeedback: interactionFeedback,
            directManipulation: directManipulation
        )
    }

    private func makePresentation(
        state: JourneyState,
        interactionFeedback: InteractionFeedback? = nil,
        directManipulation: SceneDirectManipulationState?
    ) throws -> ChapterScenePresentation {
        let ephemeralResponseEpoch: UInt64?
        if ChapterScenePresentation.ephemeralResponseKind(
            feedback: interactionFeedback,
            directManipulation: directManipulation
        ) != nil {
            nextEphemeralResponseEpoch &+= 1
            if nextEphemeralResponseEpoch == 0 {
                nextEphemeralResponseEpoch = 1
            }
            ephemeralResponseEpoch = nextEphemeralResponseEpoch
        } else {
            ephemeralResponseEpoch = nil
        }
        return try Self.makePresentation(
            state: state,
            coordinator: coordinator,
            assets: assets,
            viewportCropID: viewportCropID,
            reduceMotion: reduceMotion,
            interactionFeedback: interactionFeedback,
            directManipulation: directManipulation,
            ephemeralResponseEpoch: ephemeralResponseEpoch
        )
    }

    private static func makePresentation(
        state: JourneyState,
        coordinator: ChapterCoordinator,
        assets: SceneAssetInventory,
        viewportCropID: String,
        reduceMotion: Bool,
        interactionFeedback: InteractionFeedback? = nil,
        directManipulation: SceneDirectManipulationState?,
        ephemeralResponseEpoch: UInt64? = nil
    ) throws -> ChapterScenePresentation {
        let cursor = try coordinator.currentCursor(state: state)
        guard let session = state.activeChapter else {
            throw ChapterSceneRuntimeControllerError.noActiveChapterSession
        }
        let interaction = cursor.beat.interaction
        let request = try SceneFrameRequestFactory.make(
            scene: cursor.scene,
            session: session,
            viewportCropID: viewportCropID,
            interaction: interaction,
            directManipulation: directManipulation,
            reduceMotion: reduceMotion
        )
        let frame = try SceneFramePlanner.plan(
            scene: cursor.scene,
            request: request,
            assets: assets
        )
        let metal = try SceneMetalPreparationPlanner.make(from: frame)

        let semanticModel: SemanticInteractionModel?
        if let interaction {
            guard let runtime = session.interaction else {
                throw ChapterSceneRuntimeControllerError.noActiveInteraction
            }
            semanticModel = try SemanticInteractionAdapter.model(
                for: interaction,
                accessibility: cursor.accessibility,
                state: runtime
            )
        } else {
            semanticModel = nil
        }
        return ChapterScenePresentation(
            cursor: cursor,
            journeyState: state,
            framePlan: frame,
            metalPreparationPlan: metal,
            semanticInteractionModel: semanticModel,
            interactionFeedback: interactionFeedback,
            directManipulation: directManipulation,
            ephemeralResponseEpoch: ephemeralResponseEpoch
        )
    }

    private func emitEphemeralHaptic(
        for directManipulation: SceneDirectManipulationState?
    ) {
        guard let directManipulation else { return }
        switch directManipulation.phase {
        case .contact:
            let key = GestureContactKey(
                subjectID: directManipulation.subjectID,
                sourceTargetID: directManipulation.sourceTargetID
            )
            guard activeGestureContactKey != key else { return }
            activeGestureContactKey = key
            hapticBridge?.play(.contact)
        case .snapBack:
            if directManipulation.outcome == .cancelled {
                activeGestureContactKey = nil
            }
        case .resistance, .accepted:
            activeGestureContactKey = nil
        case .lift, .carrying, .targetContact, .slotApproach:
            break
        }
    }

    private func emitEphemeralResistanceHaptic() {
        hapticBridge?.play(.resistance)
    }

    private func shouldSuppressDurableContact(
        source: InputSource,
        action: InteractionAction
    ) -> Bool {
        guard case let .place(componentID, _) = action else {
            return false
        }
        switch source {
        case .semantic:
            // VoiceOver receives the same immediate contact response before
            // reducer submission, so a successful append must not replay it.
            return true
        case .touch:
            return activeGestureContactKey?.subjectID == componentID
        }
    }

    private func emitEphemeralSemanticContactHapticIfNeeded(
        _ action: InteractionAction
    ) {
        guard case .place = action else { return }
        hapticBridge?.play(.contact)
    }

    private func finishGestureIfNeeded(_ action: InteractionAction) {
        switch action {
        case .allocate, .place:
            activeGestureContactKey = nil
        default:
            break
        }
    }

    private func emitHaptics(
        from commit: DurableJourneyCommit,
        suppressingContact: Bool = false
    ) {
        guard let hapticBridge else { return }
        for effect in commit.effects {
            guard case let .haptic(semantic) = effect else { continue }
            if suppressingContact, semantic == .contact { continue }
            hapticBridge.play(semantic)
        }
    }

    private func isInteractionConsequence(_ commit: DurableJourneyCommit) -> Bool {
        guard case .interact = commit.event.action else { return false }
        return commit.effects.contains { effect in
            if case let .worldChanged(ids) = effect { return !ids.isEmpty }
            return false
        }
    }

    /// Cancellation is observed only while an input is waiting for admission.
    /// Once admitted, work runs in an independent task so the durable result is
    /// returned even if the submitting task is cancelled during append/audio.
    private func acquireTransitionSlot() async throws {
        try Task.checkCancellation()
        guard transitionIsInFlight else {
            transitionIsInFlight = true
            return
        }
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                transitionWaiters.append(
                    TransitionWaiter(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelTransitionWaiter(waiterID)
            }
        }
    }

    private func finishAcceptedTransition<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        let accepted = Task.detached {
            try await operation()
        }
        do {
            let result = try await accepted.value
            releaseTransitionSlot()
            return result
        } catch {
            releaseTransitionSlot()
            throw error
        }
    }

    private func cancelTransitionWaiter(_ id: UUID) {
        guard let index = transitionWaiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = transitionWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releaseTransitionSlot() {
        guard !transitionWaiters.isEmpty else {
            transitionIsInFlight = false
            return
        }
        transitionWaiters.removeFirst().continuation.resume(returning: ())
    }
}
