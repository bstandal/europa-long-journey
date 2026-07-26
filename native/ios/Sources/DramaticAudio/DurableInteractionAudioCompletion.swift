import ContentKit
import Foundation
import JourneyDomain
import ProgressStore

public struct DurableInteractionAudioCompletionReceipt: Equatable, Sendable {
    public let sequence: UInt64
    public let scope: ResponsiveAudioProgramScope

    fileprivate init(sequence: UInt64, scope: ResponsiveAudioProgramScope) {
        self.sequence = sequence
        self.scope = scope
    }

    /// Converts only the exact write-ahead commit that first completed an
    /// interaction. Replayed taps after completion do not carry worldChanged
    /// and therefore cannot release the audio consequence.
    public static func make(
        from commit: DurableJourneyCommit
    ) throws -> DurableInteractionAudioCompletionReceipt {
        guard commit.sequence > 0,
              commit.event.logicalTimeMillis == commit.state.lastLogicalTimeMillis,
              commit.state.appliedEventCount > 0 else {
            throw DurableInteractionAudioCompletionError.invalidCommitBoundary
        }
        guard case let .interact(spec, _) = commit.event.action else {
            throw DurableInteractionAudioCompletionError.notAnInteractionCommit
        }
        guard !commit.effects.contains(where: { effect in
            if case .rejected = effect { return true }
            return false
        }) else {
            throw DurableInteractionAudioCompletionError.rejectedJourneyTransition
        }

        let worldChanges = commit.effects.compactMap { effect -> [WorldEffectID]? in
            if case let .worldChanged(ids) = effect { return ids }
            return nil
        }
        let expectedEffectIDs = spec.completionEffects.map(\.id)
        guard worldChanges == [expectedEffectIDs],
              spec.completionEffects.allSatisfy({ authoredEffect in
                  commit.state.world.appliedEffects.contains(authoredEffect)
              }) else {
            throw DurableInteractionAudioCompletionError.missingDurableConsequence
        }
        guard let session = commit.state.activeChapter,
              let arcID = session.arcID,
              let beatID = session.beatID,
              let interaction = session.interaction,
              interaction.interactionID == spec.id,
              interaction.phase == .complete else {
            throw DurableInteractionAudioCompletionError.interactionNotComplete
        }

        return DurableInteractionAudioCompletionReceipt(
            sequence: commit.sequence,
            scope: ResponsiveAudioProgramScope(
                chapterID: session.chapterID,
                arcID: arcID,
                beatID: beatID,
                interactionID: spec.id
            )
        )
    }

    /// Reconstitutes transition authority after a cold launch from the
    /// integrity-checked Journey restoration and the exact authored
    /// InteractionSpec. An audio snapshot cannot authorize itself.
    public static func makeForRestore(
        sequence: UInt64,
        scope: ResponsiveAudioProgramScope,
        interactionSpec: InteractionSpec,
        restoration: JourneyRestoration
    ) throws -> DurableInteractionAudioCompletionReceipt {
        guard sequence > 0,
              sequence <= restoration.lastSequence,
              interactionSpec.id == scope.interactionID,
              restoration.state.lastLogicalTimeMillis > 0,
              restoration.state.appliedEventCount > 0 else {
            throw DurableInteractionAudioCompletionError.invalidCommitBoundary
        }
        guard let session = restoration.state.activeChapter,
              session.chapterID == scope.chapterID,
              session.arcID == scope.arcID,
              session.beatID == scope.beatID,
              let interaction = session.interaction,
              interaction.interactionID == interactionSpec.id,
              interaction.phase == .complete else {
            throw DurableInteractionAudioCompletionError.interactionNotComplete
        }
        guard interactionSpec.completionEffects.allSatisfy({ authoredEffect in
            restoration.state.world.appliedEffects.contains(authoredEffect)
        }) else {
            throw DurableInteractionAudioCompletionError.missingDurableConsequence
        }
        return DurableInteractionAudioCompletionReceipt(sequence: sequence, scope: scope)
    }
}

public enum DurableInteractionAudioCompletionError: Error, Equatable, Sendable {
    case invalidCommitBoundary
    case notAnInteractionCommit
    case rejectedJourneyTransition
    case missingDurableConsequence
    case interactionNotComplete
}

/// Narrow authority for an audio stage derived from an already journalled
/// Transform action. Audio receives only the irreversible count and the exact
/// historical scope; Transform controls and authored stage names remain in
/// JourneyDomain.
public struct DurableInteractionAudioCausalStageReceipt: Equatable, Sendable {
    public let sequence: UInt64
    public let scope: ResponsiveAudioProgramScope
    public let causalStage: ResponsiveAudioCausalStage

    fileprivate init(
        sequence: UInt64,
        scope: ResponsiveAudioProgramScope,
        causalStage: ResponsiveAudioCausalStage
    ) {
        self.sequence = sequence
        self.scope = scope
        self.causalStage = causalStage
    }

    /// Returns nil for a phase-only grammar. A Transform receipt is produced
    /// only from the committed post-action state; a speculative preview cannot
    /// create one.
    public static func make(
        from commit: DurableJourneyCommit
    ) throws -> DurableInteractionAudioCausalStageReceipt? {
        guard commit.sequence > 0,
              commit.event.logicalTimeMillis == commit.state.lastLogicalTimeMillis,
              commit.state.appliedEventCount > 0 else {
            throw DurableInteractionAudioCausalStageError.invalidCommitBoundary
        }
        guard case let .interact(spec, _) = commit.event.action else {
            throw DurableInteractionAudioCausalStageError.notAnInteractionCommit
        }
        guard !commit.effects.contains(where: { effect in
            if case .rejected = effect { return true }
            return false
        }) else {
            throw DurableInteractionAudioCausalStageError.rejectedJourneyTransition
        }
        guard case let .transform(configuration) = spec.grammar else {
            return nil
        }
        guard let session = commit.state.activeChapter,
              let arcID = session.arcID,
              let beatID = session.beatID,
              let interaction = session.interaction,
              interaction.interactionID == spec.id,
              case let .transform(progress) = interaction.progress,
              (0 ... configuration.stages.count).contains(
                  progress.completedStageCount
              ) else {
            throw DurableInteractionAudioCausalStageError.invalidTransformState
        }
        return DurableInteractionAudioCausalStageReceipt(
            sequence: commit.sequence,
            scope: ResponsiveAudioProgramScope(
                chapterID: session.chapterID,
                arcID: arcID,
                beatID: beatID,
                interactionID: spec.id
            ),
            causalStage: ResponsiveAudioCausalStage(
                completedStageCount: progress.completedStageCount
            )
        )
    }

    /// Derives the current stage from integrity-checked Journey restoration.
    /// A nil audio field in an older save can therefore be hydrated without a
    /// save-format migration. The next persisted audio cursor carries it.
    public static func restoredCausalStage(
        scope: ResponsiveAudioProgramScope,
        interactionSpec: InteractionSpec,
        restoration: JourneyRestoration
    ) throws -> ResponsiveAudioCausalStage? {
        guard interactionSpec.id == scope.interactionID else {
            throw DurableInteractionAudioCausalStageError.scopeMismatch
        }
        guard case let .transform(configuration) = interactionSpec.grammar else {
            return nil
        }
        guard let session = restoration.state.activeChapter,
              session.chapterID == scope.chapterID,
              session.arcID == scope.arcID,
              session.beatID == scope.beatID,
              let interaction = session.interaction,
              interaction.interactionID == interactionSpec.id,
              case let .transform(progress) = interaction.progress,
              (0 ... configuration.stages.count).contains(
                  progress.completedStageCount
              ) else {
            throw DurableInteractionAudioCausalStageError.invalidTransformState
        }
        return ResponsiveAudioCausalStage(
            completedStageCount: progress.completedStageCount
        )
    }
}

public enum DurableInteractionAudioCausalStageError: Error, Equatable, Sendable {
    case invalidCommitBoundary
    case notAnInteractionCommit
    case rejectedJourneyTransition
    case invalidTransformState
    case scopeMismatch
}
