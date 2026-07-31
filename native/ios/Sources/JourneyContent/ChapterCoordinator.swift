import ContentKit
import Foundation
@_spi(JourneyContent) import JourneyDomain

public enum ChapterCoordinatorError: Error, Equatable, Sendable, CustomStringConvertible {
    case chapterUnavailable(ChapterID)
    case chapterAlreadyHasSession(ChapterID)
    case chapterHasNoSession(ChapterID)
    case noActiveChapter
    case incompleteSessionCursor(ChapterID)
    case unknownArc(ArcID)
    case unknownBeat(BeatID)
    case arcOutsideChapter(arcID: ArcID, chapterID: ChapterID)
    case beatOutsideArc(beatID: BeatID, arcID: ArcID)
    case sessionPackageMismatch(ChapterID)
    case sessionVersionMismatch(ChapterID)
    case installedVersionMismatch(PackageID)
    case sceneUnavailable(SceneID)
    case accessibilityUnavailable(AccessibilityID)
    case malformedCompletionPrefix(ChapterID)
    case completedChapterIsActive(ChapterID)
    case sceneSnapshotMissing(SceneID)
    case sceneSnapshotMismatch(expected: SceneID, actual: SceneID)
    case interactionMismatch(expected: InteractionID, actual: InteractionID)
    case interactionProgressMismatch(InteractionID)
    case interactionEffectMismatch(InteractionID)
    case beatCompletionContractMismatch(BeatID)
    case documentaryEffectMismatch(BeatID)
    case unexpectedInteraction(InteractionID)
    case interactionIncomplete(InteractionID)
    case responsiveAudioUnavailable(InteractionID)
    case responsiveAudioSnapshotMismatch(InteractionID)
    case unexpectedResponsiveAudio(BeatID)
    case reviewAlreadyOpen
    case reviewNotOpen
    case reviewUnavailable(ChapterID)
    case reviewBeatUnavailable(BeatID)
    case reviewRecordMismatch(BeatID)

    public var description: String {
        switch self {
        case let .chapterUnavailable(id):
            "Chapter content is not available: \(id)"
        case let .chapterAlreadyHasSession(id):
            "Chapter already has a saved session and must resume: \(id)"
        case let .chapterHasNoSession(id):
            "Chapter has no saved session to resume: \(id)"
        case .noActiveChapter:
            "The Journey has no active chapter cursor"
        case let .incompleteSessionCursor(id):
            "Chapter session has only part of its arc-and-beat cursor: \(id)"
        case let .unknownArc(id):
            "The saved arc is unavailable: \(id)"
        case let .unknownBeat(id):
            "The saved beat is unavailable: \(id)"
        case let .arcOutsideChapter(arcID, chapterID):
            "Arc \(arcID) does not belong to chapter \(chapterID)"
        case let .beatOutsideArc(beatID, arcID):
            "Beat \(beatID) does not belong to arc \(arcID)"
        case let .sessionPackageMismatch(chapterID):
            "Saved package identity does not match chapter \(chapterID)"
        case let .sessionVersionMismatch(chapterID):
            "Saved content version does not match chapter \(chapterID)"
        case let .installedVersionMismatch(packageID):
            "Installed content version does not match package \(packageID)"
        case let .sceneUnavailable(id):
            "The saved beat's scene is unavailable: \(id)"
        case let .accessibilityUnavailable(id):
            "The saved scene's accessibility specification is unavailable: \(id)"
        case let .malformedCompletionPrefix(id):
            "Completed beats and arcs are not a causal prefix of chapter \(id)"
        case let .completedChapterIsActive(id):
            "A completed chapter cannot remain the active causal route: \(id)"
        case let .sceneSnapshotMissing(expected):
            "The active scene must be durably activated before presentation: \(expected)"
        case let .sceneSnapshotMismatch(expected, actual):
            "Scene snapshot \(actual) does not match active scene \(expected)"
        case let .interactionMismatch(expected, actual):
            "Interaction state \(actual) does not match active interaction \(expected)"
        case let .interactionProgressMismatch(id):
            "Interaction progress does not match the authored grammar: \(id)"
        case let .interactionEffectMismatch(id):
            "Interaction state and its permanent world consequence disagree: \(id)"
        case let .beatCompletionContractMismatch(id):
            "Saved beat completion authority does not match authored content: \(id)"
        case let .documentaryEffectMismatch(id):
            "Documentary beat and its permanent world consequence disagree: \(id)"
        case let .unexpectedInteraction(id):
            "A non-interactive beat carries interaction state: \(id)"
        case let .interactionIncomplete(id):
            "The historical interaction must complete before advancing: \(id)"
        case let .responsiveAudioUnavailable(id):
            "The authored responsive-audio program is unavailable: \(id)"
        case let .responsiveAudioSnapshotMismatch(id):
            "The saved responsive-audio cursor does not match the authored interaction: \(id)"
        case let .unexpectedResponsiveAudio(id):
            "A non-interactive beat carries responsive-audio state: \(id)"
        case .reviewAlreadyOpen:
            "A chapter review is already open"
        case .reviewNotOpen:
            "No chapter review is open"
        case let .reviewUnavailable(id):
            "No exact completed scene records are available for chapter \(id)"
        case let .reviewBeatUnavailable(id):
            "The completed scene is not available for review: \(id)"
        case let .reviewRecordMismatch(id):
            "The completed scene record no longer matches verified content: \(id)"
        }
    }
}

public struct ChapterReviewCursor: Equatable, Sendable {
    public let packageID: PackageID
    public let contentVersion: SchemaVersion
    public let chapter: ChapterSpec
    public let arc: ArcSpec
    public let beat: BeatSpec
    public let scene: SceneSpec
    public let accessibility: AccessibilitySpec
    public let audioTimelineIDs: [AudioTimelineID]
    public let record: CompletedBeatReviewRecord
    public let arcIndex: Int
    public let beatIndex: Int
    public let absoluteBeatIndex: Int

    init(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapter: ChapterSpec,
        arc: ArcSpec,
        beat: BeatSpec,
        scene: SceneSpec,
        accessibility: AccessibilitySpec,
        audioTimelineIDs: [AudioTimelineID],
        record: CompletedBeatReviewRecord,
        arcIndex: Int,
        beatIndex: Int,
        absoluteBeatIndex: Int
    ) {
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.chapter = chapter
        self.arc = arc
        self.beat = beat
        self.scene = scene
        self.accessibility = accessibility
        self.audioTimelineIDs = audioTimelineIDs
        self.record = record
        self.arcIndex = arcIndex
        self.beatIndex = beatIndex
        self.absoluteBeatIndex = absoluteBeatIndex
    }
}

/// Pure projection consumed by the chapter header, visited-scene sheet and
/// Previous/Next review controls.
public struct ChapterReviewProjection: Equatable, Sendable {
    public let cursors: [ChapterReviewCursor]
    public let selectedIndex: Int
    public let visitedBeatCount: Int
    public let totalBeatCount: Int

    public var selected: ChapterReviewCursor { cursors[selectedIndex] }
    public var previousBeatID: BeatID? {
        selectedIndex > 0 ? cursors[selectedIndex - 1].beat.id : nil
    }
    public var nextBeatID: BeatID? {
        selectedIndex + 1 < cursors.count ? cursors[selectedIndex + 1].beat.id : nil
    }

    init(
        cursors: [ChapterReviewCursor],
        selectedIndex: Int,
        visitedBeatCount: Int,
        totalBeatCount: Int
    ) {
        self.cursors = cursors
        self.selectedIndex = selectedIndex
        self.visitedBeatCount = visitedBeatCount
        self.totalBeatCount = totalBeatCount
    }
}

public struct ChapterReviewActionPlan: Equatable, Sendable {
    public let action: JourneyAction
    public let projection: ChapterReviewProjection

    init(action: JourneyAction, projection: ChapterReviewProjection) {
        self.action = action
        self.projection = projection
    }
}

public struct ChapterCursor: Equatable, Sendable {
    public let packageID: PackageID
    public let contentVersion: SchemaVersion
    public let chapter: ChapterSpec
    public let arc: ArcSpec
    public let beat: BeatSpec
    public let scene: SceneSpec
    public let accessibility: AccessibilitySpec
    public let audioTimelineIDs: [AudioTimelineID]
    public let responsiveAudioProgram: ResponsiveAudioProgramSpec?
    public let responsiveAudioTimelineIDs: [AudioTimelineID]
    public let arcIndex: Int
    public let beatIndex: Int

    public init(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapter: ChapterSpec,
        arc: ArcSpec,
        beat: BeatSpec,
        scene: SceneSpec,
        accessibility: AccessibilitySpec,
        audioTimelineIDs: [AudioTimelineID],
        responsiveAudioProgram: ResponsiveAudioProgramSpec?,
        responsiveAudioTimelineIDs: [AudioTimelineID],
        arcIndex: Int,
        beatIndex: Int
    ) {
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.chapter = chapter
        self.arc = arc
        self.beat = beat
        self.scene = scene
        self.accessibility = accessibility
        self.audioTimelineIDs = audioTimelineIDs
        self.responsiveAudioProgram = responsiveAudioProgram
        self.responsiveAudioTimelineIDs = responsiveAudioTimelineIDs
        self.arcIndex = arcIndex
        self.beatIndex = beatIndex
    }
}

/// Exact authored material and durable cursor required to reconstruct one
/// user-paced audio program. If `requiresCompletionAuthority` is true the
/// DramaticAudio boundary must derive a receipt from JourneyRestoration before
/// it may enter or restore the consequence timeline.
public struct ResponsiveAudioRestorationPlan: Equatable, Sendable {
    public let program: ResponsiveAudioProgramSpec
    public let timelines: [AudioTimeline]
    public let snapshot: ResponsiveAudioProgramSnapshot?
    public let interaction: InteractionSpec
    public let requiresCompletionAuthority: Bool

    public init(
        program: ResponsiveAudioProgramSpec,
        timelines: [AudioTimeline],
        snapshot: ResponsiveAudioProgramSnapshot?,
        interaction: InteractionSpec,
        requiresCompletionAuthority: Bool
    ) {
        self.program = program
        self.timelines = timelines
        self.snapshot = snapshot
        self.interaction = interaction
        self.requiresCompletionAuthority = requiresCompletionAuthority
    }
}

public enum ChapterAdvanceDestination: Equatable, Sendable {
    case beat(chapterID: ChapterID, arcID: ArcID, beatID: BeatID)
    case world(completedChapterID: ChapterID)
}

public struct ChapterAdvancePlan: Equatable, Sendable {
    public let actions: [JourneyAction]
    public let destination: ChapterAdvanceDestination
    /// Non-empty only when the plan completes the chapter. These are the same
    /// effects bound into the final `.completeAuthoredChapter` action.
    public let chapterCompletionEffects: [WorldEffect]

    public init(
        actions: [JourneyAction],
        destination: ChapterAdvanceDestination,
        chapterCompletionEffects: [WorldEffect]
    ) {
        self.actions = actions
        self.destination = destination
        self.chapterCompletionEffects = chapterCompletionEffects
    }
}

/// Converts immutable authored content and an exact persisted JourneyState into
/// deterministic domain actions. It never guesses a chapter, arc or beat and
/// cannot advance around an unfinished causal interaction.
public struct ChapterCoordinator: Sendable {
    public let repository: any ChapterContentRepository

    public init(repository: any ChapterContentRepository) {
        self.repository = repository
    }

    public func beginActions(
        chapterID: ChapterID,
        state: JourneyState
    ) throws -> [JourneyAction] {
        let root = try chapterRoot(chapterID)
        guard !state.completedChapterIDs.contains(chapterID) else {
            throw ChapterCoordinatorError.completedChapterIsActive(chapterID)
        }
        guard state.chapterSession(chapterID) == nil else {
            throw ChapterCoordinatorError.chapterAlreadyHasSession(chapterID)
        }
        try validateInstalledVersion(
            packageID: root.packageID,
            version: root.contentVersion,
            state: state
        )
        let contract = try completionContract(
            packageID: root.packageID,
            contentVersion: root.contentVersion,
            chapter: root.chapter,
            arcIndex: 0,
            beatIndex: 0
        )
        let sceneContract = try sceneActivationContract(
            packageID: root.packageID,
            contentVersion: root.contentVersion,
            chapter: root.chapter,
            arcIndex: 0,
            beatIndex: 0,
            scene: root.scene
        )
        var actions: [JourneyAction] = [
            .beginAuthoredChapter(contract),
            .activateScene(sceneContract),
        ]
        if let interaction = root.beat.interaction {
            actions.append(.beginInteraction(interaction))
        }
        return actions
    }

    public func resumeActions(
        chapterID: ChapterID,
        state: JourneyState
    ) throws -> [JourneyAction] {
        let root = try chapterRoot(chapterID)
        guard !state.completedChapterIDs.contains(chapterID) else {
            throw ChapterCoordinatorError.completedChapterIsActive(chapterID)
        }
        guard let session = state.chapterSession(chapterID) else {
            throw ChapterCoordinatorError.chapterHasNoSession(chapterID)
        }
        try validateSessionIdentity(
            session,
            packageID: root.packageID,
            contentVersion: root.contentVersion,
            state: state
        )

        switch (session.arcID, session.beatID) {
        case (nil, nil):
            guard session.completedBeatIDs.isEmpty,
                  session.completedArcIDs.isEmpty,
                  session.interaction == nil,
                  session.sceneVisualSnapshot == nil else {
                throw ChapterCoordinatorError.malformedCompletionPrefix(chapterID)
            }
            let contract = try completionContract(
                packageID: root.packageID,
                contentVersion: root.contentVersion,
                chapter: root.chapter,
                arcIndex: 0,
                beatIndex: 0
            )
            let sceneContract = try sceneActivationContract(
                packageID: root.packageID,
                contentVersion: root.contentVersion,
                chapter: root.chapter,
                arcIndex: 0,
                beatIndex: 0,
                scene: root.scene
            )
            var actions: [JourneyAction] = [
                .beginAuthoredChapter(contract),
                .activateScene(sceneContract),
            ]
            if let interaction = root.beat.interaction {
                actions.append(.beginInteraction(interaction))
            }
            return actions

        case (.some, .some):
            let cursor = try resolveCursor(
                chapterID: chapterID,
                state: state,
                requireSceneSnapshot: false
            )
            var actions: [JourneyAction] = [
                .selectChapter(
                    chapterID: chapterID,
                    packageID: cursor.packageID,
                    contentVersion: cursor.contentVersion
                ),
            ]
            let contract = try completionContract(for: cursor)
            if session.beatCompletionContract == nil {
                actions.append(.restoreAuthoredBeat(contract))
            }
            if session.sceneVisualSnapshot == nil {
                actions.append(.activateScene(try sceneActivationContract(for: cursor)))
            }
            if let interaction = cursor.beat.interaction,
               session.interaction == nil {
                actions.append(.beginInteraction(interaction))
            }
            return actions

        default:
            throw ChapterCoordinatorError.incompleteSessionCursor(chapterID)
        }
    }

    public func currentCursor(state: JourneyState) throws -> ChapterCursor {
        guard case let .chapter(chapterID) = state.route else {
            throw ChapterCoordinatorError.noActiveChapter
        }
        return try resolveCursor(chapterID: chapterID, state: state)
    }

    public func resolveCursor(
        chapterID: ChapterID,
        state: JourneyState
    ) throws -> ChapterCursor {
        try resolveCursor(
            chapterID: chapterID,
            state: state,
            requireSceneSnapshot: true
        )
    }

    /// Opens an exact archived beat without moving the causal Journey route.
    /// A nil beat selects the first archived record, which is the completed
    /// chapter entry point from the living world.
    public func openReviewPlan(
        chapterID: ChapterID,
        beatID: BeatID? = nil,
        state: JourneyState
    ) throws -> ChapterReviewActionPlan {
        guard state.chapterReview == nil else {
            throw ChapterCoordinatorError.reviewAlreadyOpen
        }
        let projection = try reviewProjection(
            chapterID: chapterID,
            selectedBeatID: beatID,
            state: state
        )
        return ChapterReviewActionPlan(
            action: .openBeatReview(
                chapterID: chapterID,
                beatID: projection.selected.beat.id
            ),
            projection: projection
        )
    }

    public func moveReviewPlan(
        to beatID: BeatID,
        state: JourneyState
    ) throws -> ChapterReviewActionPlan {
        guard let review = state.chapterReview else {
            throw ChapterCoordinatorError.reviewNotOpen
        }
        let projection = try reviewProjection(
            chapterID: review.chapterID,
            selectedBeatID: beatID,
            state: state
        )
        return ChapterReviewActionPlan(
            action: .moveBeatReview(beatID: beatID),
            projection: projection
        )
    }

    public func currentReviewProjection(
        state: JourneyState
    ) throws -> ChapterReviewProjection {
        guard let review = state.chapterReview else {
            throw ChapterCoordinatorError.reviewNotOpen
        }
        guard let session = state.chapterSession(review.chapterID),
              session.packageID == review.packageID,
              session.contentVersion == review.contentVersion else {
            throw ChapterCoordinatorError.reviewUnavailable(review.chapterID)
        }
        return try reviewProjection(
            chapterID: review.chapterID,
            selectedBeatID: review.beatID,
            state: state
        )
    }

    private func resolveCursor(
        chapterID: ChapterID,
        state: JourneyState,
        requireSceneSnapshot: Bool
    ) throws -> ChapterCursor {
        guard let session = state.chapterSession(chapterID) else {
            throw ChapterCoordinatorError.chapterHasNoSession(chapterID)
        }
        guard let chapter = repository.chapter(chapterID),
              let packageID = repository.packageID(for: chapterID),
              let contentVersion = repository.contentVersion(for: chapterID) else {
            throw ChapterCoordinatorError.chapterUnavailable(chapterID)
        }
        try validateSessionIdentity(
            session,
            packageID: packageID,
            contentVersion: contentVersion,
            state: state
        )
        guard let arcID = session.arcID, let beatID = session.beatID else {
            throw ChapterCoordinatorError.incompleteSessionCursor(chapterID)
        }
        guard let arc = repository.arc(arcID),
              let arcLocation = repository.location(of: arcID) else {
            throw ChapterCoordinatorError.unknownArc(arcID)
        }
        guard arcLocation.chapterID == chapterID else {
            throw ChapterCoordinatorError.arcOutsideChapter(
                arcID: arcID,
                chapterID: chapterID
            )
        }
        guard let beat = repository.beat(beatID),
              let beatLocation = repository.location(of: beatID) else {
            throw ChapterCoordinatorError.unknownBeat(beatID)
        }
        guard beatLocation.chapterID == chapterID,
              beatLocation.arcID == arcID else {
            throw ChapterCoordinatorError.beatOutsideArc(beatID: beatID, arcID: arcID)
        }
        guard let scene = repository.scene(beat.sceneID) else {
            throw ChapterCoordinatorError.sceneUnavailable(beat.sceneID)
        }
        guard let accessibility = repository.accessibility(scene.accessibilityID) else {
            throw ChapterCoordinatorError.accessibilityUnavailable(scene.accessibilityID)
        }

        try validateCompletionPrefix(
            session: session,
            chapter: chapter,
            currentArcIndex: beatLocation.arcIndex,
            currentBeatIndex: beatLocation.beatIndex
        )
        try validateCompletedBeatConsequences(
            session: session,
            chapter: chapter,
            world: state.world
        )
        if state.completedChapterIDs.contains(chapterID) {
            throw ChapterCoordinatorError.completedChapterIsActive(chapterID)
        }
        if let snapshot = session.sceneVisualSnapshot,
           snapshot.sceneID != scene.id {
            throw ChapterCoordinatorError.sceneSnapshotMismatch(
                expected: scene.id,
                actual: snapshot.sceneID
            )
        } else if requireSceneSnapshot, session.sceneVisualSnapshot == nil {
            throw ChapterCoordinatorError.sceneSnapshotMissing(scene.id)
        }
        try validateInteraction(session: session, beat: beat, world: state.world)

        let responsiveAudioProgram: ResponsiveAudioProgramSpec?
        let responsiveAudioTimelineIDs: [AudioTimelineID]
        if let interaction = beat.interaction {
            guard let program = repository.responsiveAudioProgram(for: interaction.id),
                  program.scope == ResponsiveAudioProgramScope(
                    chapterID: chapterID,
                    arcID: arcID,
                    beatID: beatID,
                    interactionID: interaction.id
                  ),
                  let timelines = repository.responsiveAudioTimelines(for: interaction.id) else {
                throw ChapterCoordinatorError.responsiveAudioUnavailable(interaction.id)
            }
            responsiveAudioProgram = program
            responsiveAudioTimelineIDs = timelines.map(\.id)
            try validateResponsiveAudioSnapshot(
                session.responsiveAudioSnapshot,
                program: program,
                timelines: timelines,
                interaction: interaction,
                runtime: session.interaction
            )
        } else {
            guard session.responsiveAudioSnapshot == nil else {
                throw ChapterCoordinatorError.unexpectedResponsiveAudio(beat.id)
            }
            responsiveAudioProgram = nil
            responsiveAudioTimelineIDs = []
        }

        let cursorContract = try completionContract(
            packageID: packageID,
            contentVersion: contentVersion,
            chapter: chapter,
            arcIndex: beatLocation.arcIndex,
            beatIndex: beatLocation.beatIndex
        )
        try validateBeatCompletionContract(
            session: session,
            expected: cursorContract,
            beat: beat,
            world: state.world
        )

        return ChapterCursor(
            packageID: packageID,
            contentVersion: contentVersion,
            chapter: chapter,
            arc: arc,
            beat: beat,
            scene: scene,
            accessibility: accessibility,
            audioTimelineIDs: repository.audioTimelineIDs(for: beat.id) ?? [],
            responsiveAudioProgram: responsiveAudioProgram,
            responsiveAudioTimelineIDs: responsiveAudioTimelineIDs,
            arcIndex: beatLocation.arcIndex,
            beatIndex: beatLocation.beatIndex
        )
    }

    private func reviewProjection(
        chapterID: ChapterID,
        selectedBeatID: BeatID?,
        state: JourneyState
    ) throws -> ChapterReviewProjection {
        guard let session = state.chapterSession(chapterID),
              let chapter = repository.chapter(chapterID),
              let packageID = repository.packageID(for: chapterID),
              let contentVersion = repository.contentVersion(for: chapterID) else {
            throw ChapterCoordinatorError.reviewUnavailable(chapterID)
        }
        try validateSessionIdentity(
            session,
            packageID: packageID,
            contentVersion: contentVersion,
            state: state
        )
        let requiresCompleteChapterArchive: Bool
        switch state.route {
        case let .chapter(activeChapterID):
            guard activeChapterID == chapterID else {
                throw ChapterCoordinatorError.reviewUnavailable(chapterID)
            }
            requiresCompleteChapterArchive = false
        case .world:
            guard state.completedChapterIDs.contains(chapterID) else {
                throw ChapterCoordinatorError.reviewUnavailable(chapterID)
            }
            requiresCompleteChapterArchive = true
        case .prologue:
            throw ChapterCoordinatorError.reviewUnavailable(chapterID)
        }

        guard let currentArcID = session.arcID,
              let currentBeatID = session.beatID,
              let currentArcLocation = repository.location(of: currentArcID),
              let currentBeatLocation = repository.location(of: currentBeatID),
              currentArcLocation.chapterID == chapterID,
              currentBeatLocation.chapterID == chapterID,
              currentBeatLocation.arcID == currentArcID,
              currentBeatLocation.arcIndex == currentArcLocation.arcIndex else {
            throw ChapterCoordinatorError.malformedCompletionPrefix(chapterID)
        }
        try validateCompletionPrefix(
            session: session,
            chapter: chapter,
            currentArcIndex: currentArcLocation.arcIndex,
            currentBeatIndex: currentBeatLocation.beatIndex
        )
        try validateCompletedBeatConsequences(
            session: session,
            chapter: chapter,
            world: state.world
        )

        let orderedBeatIDs = chapter.arcs.flatMap { $0.beats.map(\.id) }
        let completedBeatIDs = Set(session.completedBeatIDs)
        let archivedBeatIDs = Set(
            session.completedBeatReviewRecords.map(\.beatID)
        )
        guard session.completedBeatReviewRecords.count == session.completedBeatIDs.count,
              archivedBeatIDs.count == session.completedBeatReviewRecords.count,
              archivedBeatIDs == completedBeatIDs else {
            throw ChapterCoordinatorError.reviewUnavailable(chapterID)
        }
        if requiresCompleteChapterArchive {
            guard session.completedBeatIDs.count == orderedBeatIDs.count,
                  completedBeatIDs == Set(orderedBeatIDs) else {
                throw ChapterCoordinatorError.reviewUnavailable(chapterID)
            }
        }

        let cursors = try session.completedBeatReviewRecords.map { record in
            try reviewCursor(
                record: record,
                session: session,
                chapter: chapter,
                packageID: packageID,
                contentVersion: contentVersion
            )
        }.sorted { $0.absoluteBeatIndex < $1.absoluteBeatIndex }
        guard !cursors.isEmpty else {
            throw ChapterCoordinatorError.reviewUnavailable(chapterID)
        }
        let selected = selectedBeatID ?? cursors[0].beat.id
        guard let selectedIndex = cursors.firstIndex(where: {
            $0.beat.id == selected
        }) else {
            throw ChapterCoordinatorError.reviewBeatUnavailable(selected)
        }
        return ChapterReviewProjection(
            cursors: cursors,
            selectedIndex: selectedIndex,
            visitedBeatCount: session.completedBeatIDs.count,
            totalBeatCount: chapter.arcs.reduce(0) { $0 + $1.beats.count }
        )
    }

    private func reviewCursor(
        record: CompletedBeatReviewRecord,
        session: ChapterSession,
        chapter: ChapterSpec,
        packageID: PackageID,
        contentVersion: SchemaVersion
    ) throws -> ChapterReviewCursor {
        let fail = ChapterCoordinatorError.reviewRecordMismatch(record.beatID)
        guard record.isStructurallyValid,
              record.packageID == packageID,
              record.contentVersion == contentVersion,
              record.chapterID == chapter.id,
              session.completedBeatIDs.contains(record.beatID),
              let location = repository.location(of: record.beatID),
              location.chapterID == chapter.id,
              chapter.arcs.indices.contains(location.arcIndex),
              chapter.arcs[location.arcIndex].beats.indices.contains(location.beatIndex) else {
            throw fail
        }
        let arc = chapter.arcs[location.arcIndex]
        let beat = arc.beats[location.beatIndex]
        guard arc.id == record.arcID,
              beat.id == record.beatID,
              let scene = repository.scene(beat.sceneID),
              scene.id == record.sceneVisualSnapshot.sceneID,
              let accessibility = repository.accessibility(scene.accessibilityID),
              record.completionContract == (try completionContract(
                  packageID: packageID,
                  contentVersion: contentVersion,
                  chapter: chapter,
                  arcIndex: location.arcIndex,
                  beatIndex: location.beatIndex
              )) else {
            throw fail
        }
        switch (beat.interaction, record.interaction) {
        case (nil, nil):
            break
        case let (interaction?, runtime?) where InteractionReducer.terminalState(
            runtime,
            matches: interaction
        ):
            break
        default:
            throw fail
        }
        let absoluteBeatIndex = chapter.arcs.prefix(location.arcIndex)
            .reduce(0) { $0 + $1.beats.count } + location.beatIndex
        guard record.arcIndex == location.arcIndex,
              record.beatIndex == location.beatIndex,
              record.absoluteBeatIndex == absoluteBeatIndex else {
            throw fail
        }
        return ChapterReviewCursor(
            packageID: packageID,
            contentVersion: contentVersion,
            chapter: chapter,
            arc: arc,
            beat: beat,
            scene: scene,
            accessibility: accessibility,
            audioTimelineIDs: repository.audioTimelineIDs(for: beat.id) ?? [],
            record: record,
            arcIndex: location.arcIndex,
            beatIndex: location.beatIndex,
            absoluteBeatIndex: absoluteBeatIndex
        )
    }

    public func responsiveAudioRestorationPlan(
        state: JourneyState
    ) throws -> ResponsiveAudioRestorationPlan? {
        let cursor = try currentCursor(state: state)
        guard let interaction = cursor.beat.interaction,
              let program = cursor.responsiveAudioProgram,
              let timelines = repository.responsiveAudioTimelines(for: interaction.id),
              let session = state.activeChapter else {
            return nil
        }
        let snapshot = session.responsiveAudioSnapshot
        let completed = session.interaction?.phase == .complete
        let needsAuthority = completed && (
            snapshot == nil
                || snapshot?.stage == .approach
                || snapshot?.stage == .interaction
                || snapshot?.stage == .consequence
                || snapshot?.stage == .completed
        )
        return ResponsiveAudioRestorationPlan(
            program: program,
            timelines: timelines,
            snapshot: snapshot,
            interaction: interaction,
            requiresCompletionAuthority: needsAuthority
        )
    }

    /// Returns the only presentation-facing action that may advance the
    /// durable deterministic clock of the currently authored scene.
    public func sceneTickAction(
        deterministicTick: UInt64,
        state: JourneyState
    ) throws -> JourneyAction {
        let cursor = try currentCursor(state: state)
        return .updateSceneVisualTick(
            contract: try sceneActivationContract(for: cursor),
            deterministicTick: deterministicTick
        )
    }

    private func validateResponsiveAudioSnapshot(
        _ snapshot: ResponsiveAudioProgramSnapshot?,
        program: ResponsiveAudioProgramSpec,
        timelines: [AudioTimeline],
        interaction: InteractionSpec,
        runtime: InteractionRuntimeState?
    ) throws {
        guard let snapshot else { return }
        let fail = ChapterCoordinatorError.responsiveAudioSnapshotMismatch(interaction.id)
        guard snapshot.formatVersion == ResponsiveAudioProgramSnapshot.currentFormatVersion,
              snapshot.programID == program.id,
              snapshot.cursorSample >= 0 else {
            throw fail
        }
        if let causalStage = snapshot.causalStage {
            guard causalStage.completedStageCount >= 0,
                  let runtime,
                  case let .transform(progress) = runtime.progress,
                  causalStage.completedStageCount <= progress.completedStageCount,
                  progress.completedStageCount - causalStage.completedStageCount <= 1 else {
                throw fail
            }
        }
        let timelineByID = Dictionary(uniqueKeysWithValues: timelines.map { ($0.id, $0) })
        let runtimeCompleted = runtime?.phase == .complete
        let expectedTimelineID: AudioTimelineID
        let expectedDuration: Int64
        switch snapshot.stage {
        case .approach:
            guard snapshot.interactionPhase == nil,
                  snapshot.loopIteration == 0,
                  snapshot.durableCompletionSequence == nil else {
                throw fail
            }
            expectedTimelineID = program.approachTimelineID
            guard let timeline = timelineByID[expectedTimelineID] else { throw fail }
            expectedDuration = timeline.authoredDurationSamples
            guard snapshot.cursorSample < expectedDuration else { throw fail }

        case .interaction:
            guard let phase = snapshot.interactionPhase,
                  let bed = program.interactionBed(for: phase),
                  snapshot.durableCompletionSequence == nil else {
                throw fail
            }
            expectedTimelineID = bed.timelineID
            guard let timeline = timelineByID[expectedTimelineID] else { throw fail }
            expectedDuration = timeline.authoredDurationSamples
            guard snapshot.cursorSample < expectedDuration else { throw fail }

        case .consequence:
            guard runtimeCompleted,
                  snapshot.interactionPhase == nil,
                  snapshot.loopIteration == 0,
                  (snapshot.durableCompletionSequence ?? 0) > 0 else {
                throw fail
            }
            expectedTimelineID = program.consequenceTimelineID
            guard let timeline = timelineByID[expectedTimelineID] else { throw fail }
            expectedDuration = timeline.authoredDurationSamples
            guard snapshot.cursorSample < expectedDuration else { throw fail }

        case .completed:
            guard runtimeCompleted,
                  snapshot.interactionPhase == nil,
                  snapshot.loopIteration == 0,
                  (snapshot.durableCompletionSequence ?? 0) > 0 else {
                throw fail
            }
            expectedTimelineID = program.consequenceTimelineID
            guard let timeline = timelineByID[expectedTimelineID] else { throw fail }
            expectedDuration = timeline.authoredDurationSamples
            guard snapshot.cursorSample == expectedDuration else { throw fail }
        }
        guard expectedDuration > 0,
              snapshot.timelineID == expectedTimelineID else {
            throw fail
        }
    }

    public func advanceActions(state: JourneyState) throws -> ChapterAdvancePlan {
        let cursor = try currentCursor(state: state)
        guard let session = state.chapterSession(cursor.chapter.id) else {
            throw ChapterCoordinatorError.chapterHasNoSession(cursor.chapter.id)
        }
        let activeContract = try completionContract(for: cursor)
        guard session.beatCompletionContract == activeContract else {
            throw ChapterCoordinatorError.beatCompletionContractMismatch(cursor.beat.id)
        }
        if let interaction = cursor.beat.interaction {
            guard session.interaction?.interactionID == interaction.id,
                  session.interaction?.phase == .complete else {
                throw ChapterCoordinatorError.interactionIncomplete(interaction.id)
            }
        }

        var actions: [JourneyAction] = []
        if !session.completedBeatIDs.contains(cursor.beat.id) {
            if cursor.beat.interaction == nil {
                actions.append(.completeDocumentaryBeat(activeContract))
            } else {
                actions.append(.completeBeat(arcID: cursor.arc.id, beatID: cursor.beat.id))
            }
        }

        if cursor.beatIndex + 1 < cursor.arc.beats.count {
            let nextBeat = cursor.arc.beats[cursor.beatIndex + 1]
            let nextContract = try completionContract(
                packageID: cursor.packageID,
                contentVersion: cursor.contentVersion,
                chapter: cursor.chapter,
                arcIndex: cursor.arcIndex,
                beatIndex: cursor.beatIndex + 1
            )
            actions.append(.enterAuthoredBeat(nextContract))
            guard let nextScene = repository.scene(nextBeat.sceneID) else {
                throw ChapterCoordinatorError.sceneUnavailable(nextBeat.sceneID)
            }
            actions.append(
                .activateScene(
                    try sceneActivationContract(
                        packageID: cursor.packageID,
                        contentVersion: cursor.contentVersion,
                        chapter: cursor.chapter,
                        arcIndex: cursor.arcIndex,
                        beatIndex: cursor.beatIndex + 1,
                        scene: nextScene
                    )
                )
            )
            if let interaction = nextBeat.interaction {
                actions.append(.beginInteraction(interaction))
            }
            return ChapterAdvancePlan(
                actions: actions,
                destination: .beat(
                    chapterID: cursor.chapter.id,
                    arcID: cursor.arc.id,
                    beatID: nextBeat.id
                ),
                chapterCompletionEffects: []
            )
        }

        if !session.completedArcIDs.contains(cursor.arc.id) {
            actions.append(
                .completeAuthoredArc(
                    try ArcCompletionContract(
                        packageID: cursor.packageID,
                        contentVersion: cursor.contentVersion,
                        chapter: cursor.chapter,
                        arcIndex: cursor.arcIndex
                    )
                )
            )
        }
        if cursor.arcIndex + 1 < cursor.chapter.arcs.count {
            let nextArc = cursor.chapter.arcs[cursor.arcIndex + 1]
            guard let nextBeat = nextArc.beats.first else {
                throw ChapterCoordinatorError.unknownArc(nextArc.id)
            }
            let nextContract = try completionContract(
                packageID: cursor.packageID,
                contentVersion: cursor.contentVersion,
                chapter: cursor.chapter,
                arcIndex: cursor.arcIndex + 1,
                beatIndex: 0
            )
            actions.append(.enterAuthoredBeat(nextContract))
            guard let nextScene = repository.scene(nextBeat.sceneID) else {
                throw ChapterCoordinatorError.sceneUnavailable(nextBeat.sceneID)
            }
            actions.append(
                .activateScene(
                    try sceneActivationContract(
                        packageID: cursor.packageID,
                        contentVersion: cursor.contentVersion,
                        chapter: cursor.chapter,
                        arcIndex: cursor.arcIndex + 1,
                        beatIndex: 0,
                        scene: nextScene
                    )
                )
            )
            if let interaction = nextBeat.interaction {
                actions.append(.beginInteraction(interaction))
            }
            return ChapterAdvancePlan(
                actions: actions,
                destination: .beat(
                    chapterID: cursor.chapter.id,
                    arcID: nextArc.id,
                    beatID: nextBeat.id
                ),
                chapterCompletionEffects: []
            )
        }

        actions.append(
            .completeAuthoredChapter(
                try ChapterCompletionContract(
                    packageID: cursor.packageID,
                    contentVersion: cursor.contentVersion,
                    chapter: cursor.chapter
                )
            )
        )
        return ChapterAdvancePlan(
            actions: actions,
            destination: .world(completedChapterID: cursor.chapter.id),
            chapterCompletionEffects: cursor.chapter.completionEffects
        )
    }

    private func completionContract(
        for cursor: ChapterCursor
    ) throws -> BeatCompletionContract {
        try completionContract(
            packageID: cursor.packageID,
            contentVersion: cursor.contentVersion,
            chapter: cursor.chapter,
            arcIndex: cursor.arcIndex,
            beatIndex: cursor.beatIndex
        )
    }

    private func sceneActivationContract(
        for cursor: ChapterCursor
    ) throws -> SceneActivationContract {
        try sceneActivationContract(
            packageID: cursor.packageID,
            contentVersion: cursor.contentVersion,
            chapter: cursor.chapter,
            arcIndex: cursor.arcIndex,
            beatIndex: cursor.beatIndex,
            scene: cursor.scene
        )
    }

    private func sceneActivationContract(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapter: ChapterSpec,
        arcIndex: Int,
        beatIndex: Int,
        scene: SceneSpec
    ) throws -> SceneActivationContract {
        guard chapter.arcs.indices.contains(arcIndex),
              chapter.arcs[arcIndex].beats.indices.contains(beatIndex) else {
            throw ChapterCoordinatorError.malformedCompletionPrefix(chapter.id)
        }
        let arc = chapter.arcs[arcIndex]
        let beat = arc.beats[beatIndex]
        guard beat.sceneID == scene.id else {
            throw ChapterCoordinatorError.sceneUnavailable(beat.sceneID)
        }
        let absoluteBeatIndex = chapter.arcs.prefix(arcIndex)
            .reduce(0) { $0 + $1.beats.count } + beatIndex
        return try SceneActivationContract(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapter.id,
            arcID: arc.id,
            arcIndex: arcIndex,
            beatIndex: beatIndex,
            absoluteBeatIndex: absoluteBeatIndex,
            beat: beat,
            scene: scene,
            initialDeterministicTick: 0
        )
    }

    private func completionContract(
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapter: ChapterSpec,
        arcIndex: Int,
        beatIndex: Int
    ) throws -> BeatCompletionContract {
        guard chapter.arcs.indices.contains(arcIndex),
              chapter.arcs[arcIndex].beats.indices.contains(beatIndex) else {
            throw ChapterCoordinatorError.malformedCompletionPrefix(chapter.id)
        }
        let arc = chapter.arcs[arcIndex]
        let beat = arc.beats[beatIndex]
        let absoluteBeatIndex = chapter.arcs.prefix(arcIndex)
            .reduce(0) { $0 + $1.beats.count } + beatIndex
        return try BeatCompletionContract(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapter.id,
            arcID: arc.id,
            arcIndex: arcIndex,
            beatIndex: beatIndex,
            absoluteBeatIndex: absoluteBeatIndex,
            beat: beat
        )
    }

    private func validateBeatCompletionContract(
        session: ChapterSession,
        expected: BeatCompletionContract,
        beat: BeatSpec,
        world: WorldGraph
    ) throws {
        if let saved = session.beatCompletionContract, saved != expected {
            throw ChapterCoordinatorError.beatCompletionContractMismatch(beat.id)
        }
        guard beat.interaction == nil else { return }
        let status = Self.appliedStatus(of: beat.completionEffects, in: world)
        if session.completedBeatIDs.contains(beat.id) {
            guard status == (beat.completionEffects.isEmpty ? .none : .all) else {
                throw ChapterCoordinatorError.documentaryEffectMismatch(beat.id)
            }
        } else if status != .none {
            throw ChapterCoordinatorError.documentaryEffectMismatch(beat.id)
        }
    }

    private func validateCompletedBeatConsequences(
        session: ChapterSession,
        chapter: ChapterSpec,
        world: WorldGraph
    ) throws {
        let completed = Set(session.completedBeatIDs)
        for beat in chapter.arcs.flatMap(\.beats) where completed.contains(beat.id) {
            if let interaction = beat.interaction {
                guard Self.appliedStatus(
                    of: interaction.completionEffects,
                    in: world
                ) == .all else {
                    throw ChapterCoordinatorError.interactionEffectMismatch(interaction.id)
                }
            } else {
                let expected: AppliedEffectStatus = beat.completionEffects.isEmpty ? .none : .all
                guard Self.appliedStatus(of: beat.completionEffects, in: world) == expected else {
                    throw ChapterCoordinatorError.documentaryEffectMismatch(beat.id)
                }
            }
        }
    }

    private enum AppliedEffectStatus {
        case none
        case partial
        case all
        case conflict
    }

    private static func appliedStatus(
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

    private func chapterRoot(
        _ chapterID: ChapterID
    ) throws -> (
        packageID: PackageID,
        contentVersion: SchemaVersion,
        chapter: ChapterSpec,
        arc: ArcSpec,
        beat: BeatSpec,
        scene: SceneSpec
    ) {
        guard let chapter = repository.chapter(chapterID),
              let packageID = repository.packageID(for: chapterID),
              let contentVersion = repository.contentVersion(for: chapterID),
              let arc = chapter.arcs.first,
              let beat = arc.beats.first,
              let scene = repository.scene(beat.sceneID) else {
            throw ChapterCoordinatorError.chapterUnavailable(chapterID)
        }
        return (packageID, contentVersion, chapter, arc, beat, scene)
    }

    private func validateSessionIdentity(
        _ session: ChapterSession,
        packageID: PackageID,
        contentVersion: SchemaVersion,
        state: JourneyState
    ) throws {
        guard session.packageID == packageID else {
            throw ChapterCoordinatorError.sessionPackageMismatch(session.chapterID)
        }
        guard session.contentVersion == contentVersion else {
            throw ChapterCoordinatorError.sessionVersionMismatch(session.chapterID)
        }
        try validateInstalledVersion(
            packageID: packageID,
            version: contentVersion,
            state: state
        )
    }

    private func validateInstalledVersion(
        packageID: PackageID,
        version: SchemaVersion,
        state: JourneyState
    ) throws {
        let installed = state.installedContent.filter { $0.packageID == packageID }
        if installed.count > 1 || installed.contains(where: { $0.version != version }) {
            throw ChapterCoordinatorError.installedVersionMismatch(packageID)
        }
    }

    private func validateCompletionPrefix(
        session: ChapterSession,
        chapter: ChapterSpec,
        currentArcIndex: Int,
        currentBeatIndex: Int
    ) throws {
        let orderedBeatIDs = chapter.arcs.flatMap { $0.beats.map(\.id) }
        let completedBeatIDs = Set(session.completedBeatIDs)
        guard completedBeatIDs.count == session.completedBeatIDs.count,
              completedBeatIDs.isSubset(of: Set(orderedBeatIDs)) else {
            throw ChapterCoordinatorError.malformedCompletionPrefix(chapter.id)
        }
        let expectedBeatPrefix = Set(orderedBeatIDs.prefix(completedBeatIDs.count))
        guard completedBeatIDs == expectedBeatPrefix else {
            throw ChapterCoordinatorError.malformedCompletionPrefix(chapter.id)
        }
        let absoluteBeatIndex = chapter.arcs.prefix(currentArcIndex)
            .reduce(0) { $0 + $1.beats.count } + currentBeatIndex
        guard completedBeatIDs.count == absoluteBeatIndex
                || completedBeatIDs.count == absoluteBeatIndex + 1 else {
            throw ChapterCoordinatorError.malformedCompletionPrefix(chapter.id)
        }

        let orderedArcIDs = chapter.arcs.map(\.id)
        let completedArcIDs = Set(session.completedArcIDs)
        guard completedArcIDs.count == session.completedArcIDs.count,
              completedArcIDs.isSubset(of: Set(orderedArcIDs)),
              completedArcIDs == Set(orderedArcIDs.prefix(completedArcIDs.count)),
              completedArcIDs.count == currentArcIndex
                || completedArcIDs.count == currentArcIndex + 1 else {
            throw ChapterCoordinatorError.malformedCompletionPrefix(chapter.id)
        }
        if completedArcIDs.count == currentArcIndex + 1 {
            guard currentBeatIndex == chapter.arcs[currentArcIndex].beats.count - 1,
                  completedBeatIDs.count == absoluteBeatIndex + 1 else {
                throw ChapterCoordinatorError.malformedCompletionPrefix(chapter.id)
            }
        }
        for completedArcIndex in 0 ..< completedArcIDs.count {
            let beatIDs = Set(chapter.arcs[completedArcIndex].beats.map(\.id))
            guard beatIDs.isSubset(of: completedBeatIDs) else {
                throw ChapterCoordinatorError.malformedCompletionPrefix(chapter.id)
            }
        }
    }

    private func validateInteraction(
        session: ChapterSession,
        beat: BeatSpec,
        world: WorldGraph
    ) throws {
        switch (beat.interaction, session.interaction) {
        case (nil, nil):
            return
        case (nil, let runtime?):
            throw ChapterCoordinatorError.unexpectedInteraction(runtime.interactionID)
        case (let interaction?, nil):
            if interaction.completionEffects.contains(where: world.appliedEffects.contains) {
                throw ChapterCoordinatorError.interactionEffectMismatch(interaction.id)
            }
            if session.completedBeatIDs.contains(beat.id) {
                throw ChapterCoordinatorError.interactionIncomplete(interaction.id)
            }
        case (let interaction?, let runtime?):
            guard runtime.interactionID == interaction.id else {
                throw ChapterCoordinatorError.interactionMismatch(
                    expected: interaction.id,
                    actual: runtime.interactionID
                )
            }
            guard Self.runtimeState(runtime, matches: interaction) else {
                throw ChapterCoordinatorError.interactionProgressMismatch(interaction.id)
            }
            let effectsApplied = interaction.completionEffects.allSatisfy { effect in
                world.appliedEffects.contains(effect)
            }
            guard effectsApplied == (runtime.phase == .complete) else {
                throw ChapterCoordinatorError.interactionEffectMismatch(interaction.id)
            }
            if session.completedBeatIDs.contains(beat.id), runtime.phase != .complete {
                throw ChapterCoordinatorError.interactionIncomplete(interaction.id)
            }
        }
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
            // Allocate has a separate authored confirmation action. A user may
            // therefore suspend after every unit has been assigned but before
            // `commitAllocation` seals the historical consequence.
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
}
