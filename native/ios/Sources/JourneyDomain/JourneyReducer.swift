import ContentKit
import Foundation

public struct JourneyReducer: Sendable {
    public init() {}

    @discardableResult
    public func reduce(state: inout JourneyState, event: JourneyEvent) -> [JourneyEffect] {
        state.lastLogicalTimeMillis = max(state.lastLogicalTimeMillis, event.logicalTimeMillis)
        state.appliedEventCount += 1
        return reduce(state: &state, action: event.action)
    }

    @discardableResult
    public func reduce(state: inout JourneyState, action: JourneyAction) -> [JourneyEffect] {
        if state.chapterReview != nil, Self.requiresClosedReview(action) {
            return [.rejected("Close review before changing the causal chapter state")]
        }
        switch action {
        case .launch:
            state.prepareForColdRestore()
            guard state.chapterReview != nil,
                  !reviewStateMatchesDurableSession(state) else {
                return []
            }
            state.chapterReview = nil
            return [.checkpoint(.reviewChanged)]

        case let .updatePrologueTrace(value):
            guard value.isFinite else {
                return [.rejected("Prologue trace progress must be finite")]
            }
            let progress = min(max(value, state.prologue.traceProgress), 1)
            state.prologue.traceProgress = progress
            state.prologue.phase = progress > 0 ? .tracing : .dormant
            return [.haptic(.drag)]

        case let .completePrologue(effects):
            guard state.prologue.phase != .awakened else { return [] }
            guard apply(effects, to: &state) else {
                return [.rejected("The prologue world effects were not internally consistent")]
            }
            state.prologue.traceProgress = 1
            state.prologue.phase = .awakened
            state.route = .world
            state.chapterReview = nil
            return [
                .haptic(.seal),
                .worldChanged(effects.map(\.id)),
                .checkpoint(.prologueCompleted),
            ]

        case .showWorld:
            state.route = .world
            state.chapterReview = nil
            return [.checkpoint(.routeChanged)]

        case let .selectChapter(chapterID, packageID, contentVersion):
            state.route = .chapter(chapterID)
            state.chapterReview = nil
            if let existing = state.chapterSession(chapterID) {
                guard existing.packageID == packageID,
                      existing.contentVersion == contentVersion else {
                    state.route = .world
                    return [.rejected("Saved chapter content requires migration before it can open")]
                }
            } else {
                state.activeChapter = ChapterSession(
                    chapterID: chapterID,
                    packageID: packageID,
                    contentVersion: contentVersion
                )
            }
            return [.checkpoint(.routeChanged)]

        case let .beginChapter(chapterID, packageID, contentVersion, arcID, beatID):
            state.route = .chapter(chapterID)
            state.chapterReview = nil
            if var existing = state.chapterSession(chapterID) {
                guard existing.packageID == packageID,
                      existing.contentVersion == contentVersion else {
                    state.route = .world
                    return [.rejected("Saved chapter content requires migration before it can begin")]
                }
                existing.arcID = existing.arcID ?? arcID
                existing.beatID = existing.beatID ?? beatID
                state.activeChapter = existing
            } else {
                state.activeChapter = ChapterSession(
                    chapterID: chapterID,
                    packageID: packageID,
                    contentVersion: contentVersion,
                    arcID: arcID,
                    beatID: beatID
                )
            }
            return [.checkpoint(.beatChanged)]

        case let .beginAuthoredChapter(contract):
            let existing = state.chapterSession(contract.chapterID)
            guard contract.isStructurallyValid,
                  contract.arcIndex == 0,
                  contract.beatIndex == 0,
                  contract.absoluteBeatIndex == 0,
                  !state.completedChapterIDs.contains(contract.chapterID),
                  existing.map({ emptySessionCanBegin($0, contract: contract) }) ?? true,
                  installedVersionMatches(contract, state: state) else {
                return [.rejected("The authored chapter opening did not match durable content state")]
            }
            state.route = .chapter(contract.chapterID)
            state.chapterReview = nil
            var session = existing ?? ChapterSession(
                chapterID: contract.chapterID,
                packageID: contract.packageID,
                contentVersion: contract.contentVersion
            )
            session.arcID = contract.arcID
            session.beatID = contract.beatID
            session.beatCompletionContract = contract
            state.activeChapter = session
            return [.checkpoint(.beatChanged)]

        case let .enterBeat(arcID, beatID):
            guard state.activeChapter != nil else {
                return [.rejected("A beat requires an active chapter")]
            }
            guard state.activeChapter?.beatCompletionContract == nil else {
                return [.rejected("An authored chapter requires an authored beat transition")]
            }
            state.activeChapter?.arcID = arcID
            state.activeChapter?.beatID = beatID
            state.activeChapter?.sceneVisualSnapshot = nil
            state.activeChapter?.interaction = nil
            state.activeChapter?.responsiveAudioSnapshot = nil
            state.activeChapter?.responsiveAudioChapterOpenNonce = nil
            state.activeChapter?.responsiveAudioSessionGeneration = 0
            state.activeChapter?.responsiveAudioSessionIsActive = false
            state.activeChapter?.readingAnchor = nil
            return [.checkpoint(.beatChanged)]

        case let .enterAuthoredBeat(contract):
            guard contract.isStructurallyValid,
                  var session = state.activeChapter,
                  let previous = session.beatCompletionContract,
                  previous.matches(session: session),
                  contract.packageID == session.packageID,
                  contract.contentVersion == session.contentVersion,
                  contract.chapterID == session.chapterID,
                  installedVersionMatches(contract, state: state),
                  session.completedBeatIDs.contains(previous.beatID),
                  !session.completedBeatIDs.contains(contract.beatID),
                  contract.absoluteBeatIndex == previous.absoluteBeatIndex + 1,
                  contract.absoluteBeatIndex == session.completedBeatIDs.count,
                  contract.arcIndex == session.completedArcIDs.count else {
                return [.rejected("The authored beat was not the next durable causal step")]
            }
            if contract.arcID == previous.arcID {
                guard contract.arcIndex == previous.arcIndex,
                      contract.beatIndex == previous.beatIndex + 1 else {
                    return [.rejected("The authored beat order did not match its arc")]
                }
            } else {
                guard contract.arcIndex == previous.arcIndex + 1,
                      contract.beatIndex == 0,
                      session.completedArcIDs.contains(previous.arcID) else {
                    return [.rejected("The authored arc transition was incomplete")]
                }
            }
            session.arcID = contract.arcID
            session.beatID = contract.beatID
            session.beatCompletionContract = contract
            session.sceneVisualSnapshot = nil
            session.interaction = nil
            session.responsiveAudioSnapshot = nil
            session.responsiveAudioChapterOpenNonce = nil
            session.responsiveAudioSessionGeneration = 0
            session.responsiveAudioSessionIsActive = false
            session.readingAnchor = nil
            state.activeChapter = session
            return [.checkpoint(.beatChanged)]

        case let .restoreAuthoredBeat(contract):
            guard contract.isStructurallyValid,
                  var session = state.activeChapter,
                  session.beatCompletionContract == nil,
                  contract.matches(session: session),
                  installedVersionMatches(contract, state: state),
                  completionPositionMatches(contract, session: session),
                  restoredInteractionMatches(
                      contract,
                      session: session,
                      world: state.world
                  ) else {
                return [.rejected("The saved beat could not be rebound to authored content")]
            }
            session.beatCompletionContract = contract
            state.activeChapter = session
            return [.checkpoint(.beatChanged)]

        case let .beginInteraction(spec):
            guard let session = state.activeChapter else {
                return [.rejected("An interaction requires an active chapter")]
            }
            if let contract = session.beatCompletionContract {
                guard contract.matches(session: session),
                      let authored = contract.interactionIdentity,
                      authored.id == spec.id,
                      authored.effects == spec.completionEffects else {
                    return [.rejected("The interaction did not match the authored beat contract")]
                }
            }
            state.activeChapter?.interaction = InteractionRuntimeState(spec: spec)
            state.activeChapter?.responsiveAudioSnapshot = nil
            state.activeChapter?.responsiveAudioChapterOpenNonce = nil
            state.activeChapter?.responsiveAudioSessionGeneration = 0
            state.activeChapter?.responsiveAudioSessionIsActive = false
            return [.checkpoint(.interactionChanged)]

        case let .interact(spec, interactionAction):
            guard let session = state.activeChapter,
                  var interaction = session.interaction else {
                return [.rejected("No active interaction")]
            }
            guard interaction.phase != .complete else {
                return [.rejected("The interaction is already complete")]
            }
            if let contract = session.beatCompletionContract {
                guard contract.matches(session: session),
                      let authored = contract.interactionIdentity,
                      authored.id == spec.id,
                      authored.effects == spec.completionEffects else {
                    return [.rejected("The interaction did not match the authored beat contract")]
                }
            }
            do {
                let result = try InteractionReducer.reduce(
                    state: &interaction,
                    spec: spec,
                    action: interactionAction
                )
                if !result.completedEffects.isEmpty,
                   !apply(result.completedEffects, to: &state) {
                    return [.rejected("The interaction effects were not internally consistent")]
                }
                state.activeChapter?.interaction = interaction
                var effects: [JourneyEffect] = [.checkpoint(.interactionChanged)]
                if let haptic = Self.haptic(
                    for: result.feedback,
                    grammar: spec.grammar,
                    action: interactionAction
                ) {
                    effects.insert(.haptic(haptic), at: 0)
                }
                if !result.completedEffects.isEmpty {
                    effects.append(.worldChanged(result.completedEffects.map(\.id)))
                }
                return effects
            } catch {
                return [.rejected("Interaction action did not match its authored grammar")]
            }

        case let .setResponsiveAudioSnapshot(snapshot):
            return Self.applyResponsiveAudioSnapshot(snapshot, to: &state)

        case let .beginResponsiveAudioSession(
            chapterOpenNonce,
            generation,
            snapshot
        ):
            guard let session = state.activeChapter,
                  !session.responsiveAudioSessionIsActive,
                  session.responsiveAudioSessionGeneration < UInt64.max,
                  generation == session.responsiveAudioSessionGeneration + 1,
                  session.responsiveAudioChapterOpenNonce == nil
                    || session.responsiveAudioChapterOpenNonce == chapterOpenNonce else {
                return [.rejected("Responsive audio playback authority was stale")]
            }
            var candidate = state
            let effects = Self.applyResponsiveAudioSnapshot(snapshot, to: &candidate)
            guard !effects.contains(where: {
                if case .rejected = $0 { return true }
                return false
            }), var candidateSession = candidate.activeChapter else {
                return effects
            }
            candidateSession.responsiveAudioChapterOpenNonce = chapterOpenNonce
            candidateSession.responsiveAudioSessionGeneration = generation
            candidateSession.responsiveAudioSessionIsActive = true
            candidate.activeChapter = candidateSession
            state = candidate
            return effects

        case let .endResponsiveAudioSession(snapshot):
            guard let session = state.activeChapter,
                  session.responsiveAudioChapterOpenNonce != nil,
                  session.responsiveAudioSessionGeneration > 0,
                  session.responsiveAudioSessionIsActive else {
                return [.rejected("Responsive audio playback authority was unavailable")]
            }
            var candidate = state
            let effects = Self.applyResponsiveAudioSnapshot(snapshot, to: &candidate)
            guard !effects.contains(where: {
                if case .rejected = $0 { return true }
                return false
            }), var candidateSession = candidate.activeChapter else {
                return effects
            }
            candidateSession.responsiveAudioChapterOpenNonce = nil
            candidateSession.responsiveAudioSessionIsActive = false
            candidate.activeChapter = candidateSession
            state = candidate
            return effects

        case let .activateScene(contract):
            guard let session = state.activeChapter,
                  session.sceneVisualSnapshot == nil,
                  contract.matches(session: session),
                  installedVersionMatches(
                      packageID: contract.packageID,
                      contentVersion: contract.contentVersion,
                      state: state
                  ) else {
                return [.rejected("Scene activation did not match the active authored beat")]
            }
            state.activeChapter?.sceneVisualSnapshot = SceneVisualSnapshot(
                sceneID: contract.sceneID,
                deterministicTick: contract.initialDeterministicTick
            )
            return [.checkpoint(.sceneVisualChanged)]

        case let .updateSceneVisualTick(contract, deterministicTick):
            guard let session = state.activeChapter,
                  let snapshot = session.sceneVisualSnapshot,
                  contract.matches(session: session),
                  installedVersionMatches(
                      packageID: contract.packageID,
                      contentVersion: contract.contentVersion,
                      state: state
                  ),
                  snapshot.sceneID == contract.sceneID,
                  deterministicTick >= contract.initialDeterministicTick,
                  deterministicTick >= snapshot.deterministicTick else {
                return [.rejected("Scene tick did not match the active authored scene")]
            }
            state.activeChapter?.sceneVisualSnapshot = SceneVisualSnapshot(
                sceneID: contract.sceneID,
                deterministicTick: deterministicTick
            )
            return [.checkpoint(.sceneVisualChanged)]

        case let .setCameraAnchor(anchor):
            guard state.activeChapter != nil else { return [] }
            state.activeChapter?.cameraAnchor = min(max(anchor, 0), 1)
            return []

        case let .setReadingAnchor(anchor):
            state.activeChapter?.readingAnchor = anchor
            return [.checkpoint(.suspension)]

        case let .setNarration(cueID, sampleOffset, enabled, playing):
            guard state.activeChapter != nil else { return [] }
            state.activeChapter?.narration = NarrationCursor(
                cueID: cueID,
                sampleOffset: max(0, sampleOffset),
                isEnabled: enabled,
                isPlaying: playing
            )
            return []

        case .pauseNarration:
            state.activeChapter?.narration.isPlaying = false
            return [.checkpoint(.suspension)]

        case let .recordChapterVisit(chapterID, atEpochMillis):
            guard atEpochMillis >= 0,
                  var session = state.chapterSession(chapterID) else {
                return [.rejected("A chapter visit requires a saved chapter session and valid time")]
            }
            session.lastVisitedAtEpochMillis = max(
                session.lastVisitedAtEpochMillis ?? 0,
                atEpochMillis
            )
            state.chapterSessions.removeAll { $0.chapterID == chapterID }
            state.chapterSessions.append(session)
            state.chapterSessions.sort { $0.chapterID < $1.chapterID }
            return [.checkpoint(.suspension)]

        case let .completeBeat(arcID, beatID):
            guard var session = state.activeChapter,
                  session.arcID == arcID,
                  session.beatID == beatID else {
                return [.rejected("Only the active causal beat can be completed")]
            }
            if let contract = session.beatCompletionContract {
                guard contract.matches(session: session),
                      let interaction = contract.interactionIdentity,
                      session.interaction?.interactionID == interaction.id,
                      session.interaction?.phase == .complete,
                      let sceneVisualSnapshot = session.sceneVisualSnapshot,
                      session.reviewRecord(for: contract.beatID) == nil,
                      completionPositionMatches(contract, session: session),
                      appliedStatus(of: interaction.effects, in: state.world) == .all else {
                    return [.rejected("Only the completed authored interaction can complete this beat")]
                }
                let reviewRecord = CompletedBeatReviewRecord(
                    completionContract: contract,
                    sceneVisualSnapshot: sceneVisualSnapshot,
                    interaction: session.interaction,
                    cameraAnchor: session.cameraAnchor,
                    readingAnchor: session.readingAnchor
                )
                guard reviewRecord.isStructurallyValid else {
                    return [.rejected("The completed scene could not be archived exactly")]
                }
                session.completedBeatReviewRecords.append(reviewRecord)
                session.completedBeatReviewRecords.sort {
                    $0.absoluteBeatIndex < $1.absoluteBeatIndex
                }
            }
            if !session.completedBeatIDs.contains(beatID) {
                session.completedBeatIDs.append(beatID)
                session.completedBeatIDs.sort()
            }
            state.activeChapter = session
            return [.checkpoint(.beatChanged)]

        case let .completeDocumentaryBeat(contract):
            guard var session = state.activeChapter,
                  session.beatCompletionContract == contract,
                  contract.matches(session: session),
                  installedVersionMatches(contract, state: state),
                  let effects = contract.documentaryEffects,
                  session.interaction == nil,
                  let sceneVisualSnapshot = session.sceneVisualSnapshot,
                  completionPositionMatches(contract, session: session),
                  !session.completedBeatIDs.contains(contract.beatID),
                  session.reviewRecord(for: contract.beatID) == nil,
                  appliedStatus(of: effects, in: state.world) == .none else {
                return [.rejected("The documentary beat completion did not match authored content")]
            }
            let reviewRecord = CompletedBeatReviewRecord(
                completionContract: contract,
                sceneVisualSnapshot: sceneVisualSnapshot,
                interaction: nil,
                cameraAnchor: session.cameraAnchor,
                readingAnchor: session.readingAnchor
            )
            guard reviewRecord.isStructurallyValid else {
                return [.rejected("The completed scene could not be archived exactly")]
            }
            guard apply(effects, to: &state) else {
                return [.rejected("The documentary beat effects were not internally consistent")]
            }
            session.completedBeatReviewRecords.append(reviewRecord)
            session.completedBeatReviewRecords.sort {
                $0.absoluteBeatIndex < $1.absoluteBeatIndex
            }
            session.completedBeatIDs.append(contract.beatID)
            session.completedBeatIDs.sort()
            state.activeChapter = session
            var emitted: [JourneyEffect] = [.checkpoint(.beatChanged)]
            if !effects.isEmpty {
                emitted.insert(.haptic(.seal), at: 0)
                emitted.insert(.worldChanged(effects.map(\.id)), at: 1)
            }
            return emitted

        case let .completeAuthoredArc(contract):
            guard contract.isStructurallyValid,
                  var session = state.activeChapter,
                  contract.matches(session: session),
                  installedVersionMatches(
                      packageID: contract.packageID,
                      contentVersion: contract.contentVersion,
                      state: state
                  ),
                  let finalBeat = contract.finalBeat,
                  session.beatCompletionContract == finalBeat.completion,
                  session.sceneVisualSnapshot?.sceneID == finalBeat.sceneID,
                  !session.completedArcIDs.contains(contract.arcID),
                  session.completedArcIDs.count == contract.arcIndex,
                  Set(contract.orderedBeatIDs).isSubset(of: Set(session.completedBeatIDs)),
                  session.completedBeatIDs.count
                    == finalBeat.completion.absoluteBeatIndex + 1,
                  contract.beats.allSatisfy({ beat in
                      let expected: AppliedEffectStatus = beat.completion.effects.isEmpty
                          ? .none
                          : .all
                      return appliedStatus(
                          of: beat.completion.effects,
                          in: state.world
                      ) == expected
                  }),
                  finalInteractionMatches(finalBeat.interaction, session: session) else {
                return [.rejected("Arc completion did not match its full authored beat inventory")]
            }
            session.completedArcIDs.append(contract.arcID)
            session.completedArcIDs.sort()
            state.activeChapter = session
            return [.checkpoint(.beatChanged)]

        case let .suspendChapter(atEpochMillis):
            guard atEpochMillis >= 0 else {
                return [.rejected("Chapter suspension time must be valid")]
            }
            guard var session = state.activeChapter else { return [] }
            session.narration.isPlaying = false
            session.lastVisitedAtEpochMillis = max(
                session.lastVisitedAtEpochMillis ?? 0,
                atEpochMillis
            )
            state.activeChapter = session
            return [.checkpoint(.suspension)]

        case let .completeAuthoredChapter(contract):
            guard contract.isStructurallyValid,
                  let session = state.activeChapter,
                  contract.matches(session: session),
                  installedVersionMatches(
                      packageID: contract.packageID,
                      contentVersion: contract.contentVersion,
                      state: state
                  ),
                  let finalBeat = contract.finalBeat,
                  session.beatCompletionContract == finalBeat.completion,
                  session.sceneVisualSnapshot?.sceneID == finalBeat.sceneID,
                  Set(session.completedBeatIDs) == Set(contract.orderedBeatIDs),
                  session.completedBeatIDs.count == contract.orderedBeatIDs.count,
                  Set(session.completedArcIDs) == Set(contract.orderedArcIDs),
                  session.completedArcIDs.count == contract.orderedArcIDs.count,
                  contract.beatInventory.allSatisfy({ beat in
                      let expected: AppliedEffectStatus = beat.completion.effects.isEmpty
                          ? .none
                          : .all
                      return appliedStatus(
                          of: beat.completion.effects,
                          in: state.world
                      ) == expected
                  }),
                  finalInteractionMatches(
                      finalBeat.interaction,
                      session: session
                  ),
                  appliedStatus(
                      of: contract.completionEffects,
                      in: state.world
                  ) == .none else {
                return [.rejected("Chapter completion did not match the full authored chapter")]
            }
            guard apply(contract.completionEffects, to: &state) else {
                return [.rejected("The chapter effects were not internally consistent")]
            }
            if !state.completedChapterIDs.contains(contract.chapterID) {
                state.completedChapterIDs.append(contract.chapterID)
                state.completedChapterIDs.sort()
            }
            state.route = .world
            state.chapterReview = nil
            return [
                .haptic(.seal),
                .worldChanged(contract.completionEffects.map(\.id)),
                .checkpoint(.chapterCompleted),
            ]

        case let .installContent(packageID, version):
            if state.chapterSessions.contains(where: {
                $0.packageID == packageID && $0.contentVersion != version
            }) {
                return [.rejected("Active content must be migrated before package activation")]
            }
            state.installedContent.removeAll { $0.packageID == packageID }
            state.installedContent.append(
                InstalledContentVersion(packageID: packageID, version: version)
            )
            state.installedContent.sort { $0.packageID < $1.packageID }
            return [.checkpoint(.contentChanged)]

        case let .openBeatReview(chapterID, beatID):
            guard state.chapterReview == nil,
                  let session = state.chapterSession(chapterID),
                  routePermitsReview(of: chapterID, state: state),
                  let record = session.reviewRecord(for: beatID),
                  reviewRecord(record, matches: session, state: state) else {
                return [.rejected("Review requires an exact completed scene record")]
            }
            var pausedSession = session
            pausedSession.narration.isPlaying = false
            replace(pausedSession, in: &state)
            state.chapterReview = ChapterReviewState(
                chapterID: chapterID,
                packageID: session.packageID,
                contentVersion: session.contentVersion,
                beatID: beatID
            )
            return [.checkpoint(.reviewChanged)]

        case let .moveBeatReview(beatID):
            guard var review = state.chapterReview,
                  let session = state.chapterSession(review.chapterID),
                  review.packageID == session.packageID,
                  review.contentVersion == session.contentVersion,
                  let record = session.reviewRecord(for: beatID),
                  reviewRecord(record, matches: session, state: state),
                  routePermitsReview(of: review.chapterID, state: state) else {
                return [.rejected("Review can move only to an exact completed scene record")]
            }
            review.beatID = beatID
            review.readingAnchor = nil
            state.chapterReview = review
            return [.checkpoint(.reviewChanged)]

        case let .setReviewReadingAnchor(anchor):
            guard var review = state.chapterReview else {
                return [.rejected("A review reading anchor requires an open review")]
            }
            review.readingAnchor = anchor
            state.chapterReview = review
            return [.checkpoint(.reviewChanged)]

        case .closeBeatReview:
            guard state.chapterReview != nil else { return [] }
            state.chapterReview = nil
            return [.checkpoint(.reviewChanged)]
        }
    }

    private static func requiresClosedReview(_ action: JourneyAction) -> Bool {
        switch action {
        case .launch, .showWorld, .selectChapter, .beginChapter,
             .beginAuthoredChapter, .recordChapterVisit, .suspendChapter,
             .installContent, .openBeatReview, .moveBeatReview,
             .setReviewReadingAnchor, .closeBeatReview:
            return false
        default:
            return true
        }
    }

    private func routePermitsReview(
        of chapterID: ChapterID,
        state: JourneyState
    ) -> Bool {
        switch state.route {
        case let .chapter(activeChapterID):
            return activeChapterID == chapterID
        case .world:
            return state.completedChapterIDs.contains(chapterID)
        case .prologue:
            return false
        }
    }

    private func reviewRecord(
        _ record: CompletedBeatReviewRecord,
        matches session: ChapterSession,
        state: JourneyState
    ) -> Bool {
        record.isStructurallyValid
            && record.chapterID == session.chapterID
            && record.packageID == session.packageID
            && record.contentVersion == session.contentVersion
            && session.completedBeatIDs.contains(record.beatID)
            && installedVersionMatches(
                packageID: record.packageID,
                contentVersion: record.contentVersion,
                state: state
            )
    }

    private func reviewStateMatchesDurableSession(_ state: JourneyState) -> Bool {
        guard let review = state.chapterReview,
              let session = state.chapterSession(review.chapterID),
              review.packageID == session.packageID,
              review.contentVersion == session.contentVersion,
              let record = session.reviewRecord(for: review.beatID) else {
            return false
        }
        return routePermitsReview(of: review.chapterID, state: state)
            && reviewRecord(record, matches: session, state: state)
    }

    private func replace(_ session: ChapterSession, in state: inout JourneyState) {
        state.chapterSessions.removeAll { $0.chapterID == session.chapterID }
        state.chapterSessions.append(session)
        state.chapterSessions.sort { $0.chapterID < $1.chapterID }
    }

    private func apply(_ effects: [WorldEffect], to state: inout JourneyState) -> Bool {
        do {
            try state.world.applyAtomically(effects)
            return true
        } catch {
            return false
        }
    }

    private func installedVersionMatches(
        _ contract: BeatCompletionContract,
        state: JourneyState
    ) -> Bool {
        installedVersionMatches(
            packageID: contract.packageID,
            contentVersion: contract.contentVersion,
            state: state
        )
    }

    private func installedVersionMatches(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        state: JourneyState
    ) -> Bool {
        let installed = state.installedContent.filter { $0.packageID == packageID }
        return installed.count <= 1
            && !installed.contains { $0.version != contentVersion }
    }

    private func completionPositionMatches(
        _ contract: BeatCompletionContract,
        session: ChapterSession
    ) -> Bool {
        let isCompleted = session.completedBeatIDs.contains(contract.beatID)
        let expectedCount = contract.absoluteBeatIndex + (isCompleted ? 1 : 0)
        guard session.completedBeatIDs.count == expectedCount else { return false }
        let expectedArcCount = contract.arcIndex
            + (session.completedArcIDs.contains(contract.arcID) ? 1 : 0)
        return session.completedArcIDs.count == expectedArcCount
    }

    private func emptySessionCanBegin(
        _ session: ChapterSession,
        contract: BeatCompletionContract
    ) -> Bool {
        session.chapterID == contract.chapterID
            && session.packageID == contract.packageID
            && session.contentVersion == contract.contentVersion
            && session.arcID == nil
            && session.beatID == nil
            && session.beatCompletionContract == nil
            && session.sceneVisualSnapshot == nil
            && session.interaction == nil
            && session.responsiveAudioSnapshot == nil
            && session.cameraAnchor == 0
            && session.readingAnchor == nil
            && session.narration == NarrationCursor()
            && session.completedBeatIDs.isEmpty
            && session.completedArcIDs.isEmpty
            && session.completedBeatReviewRecords.isEmpty
    }

    private func restoredInteractionMatches(
        _ contract: BeatCompletionContract,
        session: ChapterSession,
        world: WorldGraph
    ) -> Bool {
        switch (contract.mode, session.interaction) {
        case (.documentary, nil):
            return true
        case (.documentary, .some):
            return false
        case (.interaction, nil):
            return true
        case let (.interaction(id, effects), runtime?):
            guard runtime.interactionID == id else { return false }
            let status = appliedStatus(of: effects, in: world)
            return runtime.phase == .complete ? status == .all : status == .none
        }
    }

    private enum AppliedEffectStatus {
        case none
        case partial
        case all
        case conflict
    }

    private func appliedStatus(
        of effects: [WorldEffect],
        in world: WorldGraph
    ) -> AppliedEffectStatus {
        guard !effects.isEmpty else { return .none }
        var appliedCount = 0
        for effect in effects {
            guard let applied = world.appliedEffects.first(where: { $0.id == effect.id }) else {
                continue
            }
            guard applied == effect else { return .conflict }
            appliedCount += 1
        }
        if appliedCount == 0 { return .none }
        if appliedCount == effects.count { return .all }
        return .partial
    }

    private func finalInteractionMatches(
        _ authored: InteractionSpec?,
        session: ChapterSession
    ) -> Bool {
        switch (authored, session.interaction) {
        case (nil, nil):
            return true
        case (nil, .some), (.some, nil):
            return false
        case let (spec?, runtime?):
            return runtime.phase == .complete
                && runtime.interactionID == spec.id
                && Self.runtimeState(runtime, matches: spec)
        }
    }

    private static func applyResponsiveAudioSnapshot(
        _ snapshot: ResponsiveAudioProgramSnapshot,
        to state: inout JourneyState
    ) -> [JourneyEffect] {
        guard snapshot.formatVersion == ResponsiveAudioProgramSnapshot.currentFormatVersion,
              snapshot.cursorSample >= 0,
              let session = state.activeChapter,
              let interaction = session.interaction else {
            return [.rejected("Responsive audio requires the active authored interaction")]
        }
        let previousCausalStage = session.responsiveAudioSnapshot?.causalStage
        switch (interaction.progress, snapshot.causalStage) {
        case let (.transform(progress), .some(next)):
            guard next.completedStageCount >= 0,
                  next.completedStageCount == progress.completedStageCount else {
                return [.rejected(
                    "Responsive audio stage did not match durable Transform progress"
                )]
            }
            if let previous = previousCausalStage {
                guard next.completedStageCount >= previous.completedStageCount else {
                    return [.rejected("Responsive audio stage cannot regress")]
                }
                guard next.completedStageCount - previous.completedStageCount <= 1 else {
                    return [.rejected("Responsive audio stage cannot skip history")]
                }
            }

        case (.transform, .none):
            guard previousCausalStage == nil else {
                return [.rejected("Responsive audio stage cannot be discarded")]
            }

        case (_, .some):
            return [.rejected(
                "Responsive audio stage requires durable Transform progress"
            )]

        case (_, .none):
            guard previousCausalStage == nil else {
                return [.rejected("Responsive audio stage cannot be discarded")]
            }
        }
        switch snapshot.stage {
        case .approach, .interaction:
            guard interaction.phase != .complete,
                  snapshot.durableCompletionSequence == nil else {
                return [.rejected("Pre-consequence audio cannot outlive the interaction")]
            }
        case .consequence, .completed:
            guard interaction.phase == .complete,
                  let sequence = snapshot.durableCompletionSequence,
                  sequence > 0,
                  session.beatCompletionContract?.interactionIdentity?.id
                    == interaction.interactionID else {
                return [.rejected("Audio consequence requires the durable historical consequence")]
            }
        }
        state.activeChapter?.responsiveAudioSnapshot = snapshot
        return [.checkpoint(.responsiveAudioChanged)]
    }

    private static func runtimeState(
        _ runtime: InteractionRuntimeState,
        matches interaction: InteractionSpec
    ) -> Bool {
        let isInitial: Bool
        let isComplete: Bool
        let permitsCompleteShapeBeforeCommit: Bool

        switch (runtime.progress, interaction.grammar) {
        case let (.trace(progress), .trace(configuration)):
            guard (0 ... configuration.anchors.count).contains(progress.reachedAnchorCount),
                  progress.lastPoint?.isUnitPoint != false else {
                return false
            }
            isInitial = progress.reachedAnchorCount == 0 && progress.lastPoint == nil
            isComplete = progress.reachedAnchorCount == configuration.anchors.count
            permitsCompleteShapeBeforeCommit = false

        case let (.allocate(progress), .allocate(configuration)):
            let destinationIDs = configuration.destinations.map(\.id).sorted()
            guard progress.allocations.map(\.destinationID) == destinationIDs,
                  progress.allocations.allSatisfy({ $0.units >= 0 }) else {
                return false
            }
            let total = progress.allocations.reduce(0) { $0 + $1.units }
            guard total <= configuration.totalUnits else { return false }
            isInitial = progress.allocations.allSatisfy { $0.units == 0 }
            isComplete = total == configuration.totalUnits
                && configuration.destinations.allSatisfy { destination in
                    progress.allocations.first {
                        $0.destinationID == destination.id
                    }!.units >= destination.minimumUnits
                }
            permitsCompleteShapeBeforeCommit = true

        case let (.assemble(progress), .assemble(configuration)):
            let componentByID = Dictionary(
                uniqueKeysWithValues: configuration.components.map { ($0.id, $0) }
            )
            let placementIDs = progress.placements.map(\.componentID)
            guard Set(placementIDs).count == placementIDs.count,
                  progress.placements.allSatisfy({ placement in
                      guard let component = componentByID[placement.componentID] else {
                          return false
                      }
                      return placement.slotID == component.targetSlot
                          && component.prerequisites.allSatisfy(placementIDs.contains)
                  }) else {
                return false
            }
            isInitial = progress.placements.isEmpty
            isComplete = progress.placements.count == configuration.components.count
            permitsCompleteShapeBeforeCommit = false

        case let (.pressure(progress), .pressure(configuration)):
            let forceByID = Dictionary(
                uniqueKeysWithValues: configuration.forces.map { ($0.id, $0) }
            )
            let valueIDs = progress.values.map(\.forceID)
            guard Set(valueIDs).count == valueIDs.count,
                  Set(valueIDs) == Set(forceByID.keys),
                  progress.values.allSatisfy({ value in
                      guard let force = forceByID[value.forceID],
                            value.magnitude.isFinite,
                            (0 ... 1).contains(value.magnitude) else {
                          return false
                      }
                      return force.userControllable
                          || value.magnitude == force.initialMagnitude
                  }),
                  progress.stableMillis >= 0 else {
                return false
            }
            isInitial = progress.stableMillis == 0
                && progress.values.allSatisfy { value in
                    value.magnitude == forceByID[value.forceID]?.initialMagnitude
                }
            isComplete = progress.stableMillis >= configuration.requiredHoldMillis
            permitsCompleteShapeBeforeCommit = false

        case let (.transform(progress), .transform(configuration)):
            guard (0 ... configuration.stages.count).contains(progress.completedStageCount),
                  progress.currentAmount.isFinite,
                  (0 ... 1).contains(progress.currentAmount) else {
                return false
            }
            if progress.completedStageCount < configuration.stages.count,
               progress.currentAmount >= configuration.stages[
                   progress.completedStageCount
               ].requiredAmount {
                return false
            }
            isInitial = progress.completedStageCount == 0 && progress.currentAmount == 0
            isComplete = progress.completedStageCount == configuration.stages.count
                && progress.currentAmount == 0
            permitsCompleteShapeBeforeCommit = false

        default:
            return false
        }

        switch runtime.phase {
        case .ready:
            return isInitial && !isComplete
        case .active:
            return !isComplete || permitsCompleteShapeBeforeCommit
        case .complete:
            return isComplete
        }
    }

    private static func haptic(
        for feedback: InteractionFeedback,
        grammar: InteractionSpec.Grammar,
        action: InteractionAction
    ) -> HapticSemantic? {
        switch feedback {
        case .none:
            return nil
        case .contact:
            return .contact
        case .resistance:
            // Trace resistance is carried by the scene and responsive audio
            // bed. A physical resistance pulse would turn every brief route
            // departure into a false historical event.
            if case .trace = grammar { return nil }
            return .resistance
        case .threshold:
            return .break
        case .completed:
            return .seal
        case .progress:
            if action == .begin { return .contact }
            switch grammar {
            case .trace, .pressure, .transform:
                return .drag
            case .allocate:
                return .transfer
            case .assemble:
                return .contact
            }
        }
    }
}
