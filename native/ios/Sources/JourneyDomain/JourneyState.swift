import ContentKit
import Foundation

public enum JourneyRoute: Codable, Equatable, Sendable {
    case prologue
    case world
    case chapter(ChapterID)
}

public enum ProloguePhase: String, Codable, Equatable, Sendable {
    case dormant
    case tracing
    case awakened
}

public struct PrologueState: Codable, Equatable, Sendable {
    public var phase: ProloguePhase
    public var traceProgress: Double

    public init(phase: ProloguePhase = .dormant, traceProgress: Double = 0) {
        self.phase = phase
        self.traceProgress = traceProgress
    }
}

public struct NarrationCursor: Codable, Equatable, Sendable {
    public var cueID: AudioCueID?
    public var sampleOffset: Int64
    public var isEnabled: Bool
    public var isPlaying: Bool

    public init(
        cueID: AudioCueID? = nil,
        sampleOffset: Int64 = 0,
        isEnabled: Bool = false,
        isPlaying: Bool = false
    ) {
        self.cueID = cueID
        self.sampleOffset = sampleOffset
        self.isEnabled = isEnabled
        self.isPlaying = isPlaying
    }
}

/// The stable visual inputs required to reproduce a scene frame after process
/// termination. Gesture position, particles and other transient presentation
/// state do not belong in this snapshot.
public struct SceneVisualSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let sceneID: SceneID
    public let deterministicTick: UInt64

    public init(
        sceneID: SceneID,
        deterministicTick: UInt64,
        formatVersion: Int = currentFormatVersion
    ) {
        self.formatVersion = formatVersion
        self.sceneID = sceneID
        self.deterministicTick = deterministicTick
    }
}

public struct ChapterSession: Codable, Equatable, Sendable {
    public let chapterID: ChapterID
    public let packageID: PackageID
    public let contentVersion: SchemaVersion
    public var arcID: ArcID?
    public var beatID: BeatID?
    public var beatCompletionContract: BeatCompletionContract?
    public var sceneVisualSnapshot: SceneVisualSnapshot?
    public var interaction: InteractionRuntimeState?
    public var responsiveAudioSnapshot: ResponsiveAudioProgramSnapshot?
    /// Random authority created by a durable Journey event when this chapter
    /// opening first starts responsive playback. A graceful route exit clears
    /// it; a process kill leaves it in the journal so the cursor sidecar can
    /// prove that it belongs to this exact opening.
    public var responsiveAudioChapterOpenNonce: UUID?
    /// Increases before every new playback run. Cursor checkpoints written at
    /// high frequency are accepted only for this exact durable generation.
    public var responsiveAudioSessionGeneration: UInt64
    public var responsiveAudioSessionIsActive: Bool
    public var cameraAnchor: Double
    public var readingAnchor: String?
    public var narration: NarrationCursor
    public var completedBeatIDs: [BeatID]
    public var completedArcIDs: [ArcID]
    public var completedBeatReviewRecords: [CompletedBeatReviewRecord]
    public var lastVisitedAtEpochMillis: Int64?

    public init(
        chapterID: ChapterID,
        packageID: PackageID,
        contentVersion: SchemaVersion,
        arcID: ArcID? = nil,
        beatID: BeatID? = nil,
        beatCompletionContract: BeatCompletionContract? = nil,
        sceneVisualSnapshot: SceneVisualSnapshot? = nil,
        interaction: InteractionRuntimeState? = nil,
        responsiveAudioSnapshot: ResponsiveAudioProgramSnapshot? = nil,
        responsiveAudioChapterOpenNonce: UUID? = nil,
        responsiveAudioSessionGeneration: UInt64 = 0,
        responsiveAudioSessionIsActive: Bool = false,
        cameraAnchor: Double = 0,
        readingAnchor: String? = nil,
        narration: NarrationCursor = NarrationCursor(),
        completedBeatIDs: [BeatID] = [],
        completedArcIDs: [ArcID] = [],
        completedBeatReviewRecords: [CompletedBeatReviewRecord] = [],
        lastVisitedAtEpochMillis: Int64? = nil
    ) {
        self.chapterID = chapterID
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.arcID = arcID
        self.beatID = beatID
        self.beatCompletionContract = beatCompletionContract
        self.sceneVisualSnapshot = sceneVisualSnapshot
        self.interaction = interaction
        self.responsiveAudioSnapshot = responsiveAudioSnapshot
        self.responsiveAudioChapterOpenNonce = responsiveAudioChapterOpenNonce
        self.responsiveAudioSessionGeneration = responsiveAudioSessionGeneration
        self.responsiveAudioSessionIsActive = responsiveAudioSessionIsActive
        self.cameraAnchor = cameraAnchor
        self.readingAnchor = readingAnchor
        self.narration = narration
        self.completedBeatIDs = Array(Set(completedBeatIDs)).sorted()
        self.completedArcIDs = Array(Set(completedArcIDs)).sorted()
        self.completedBeatReviewRecords = Self.normalized(completedBeatReviewRecords)
        self.lastVisitedAtEpochMillis = lastVisitedAtEpochMillis
    }

    private enum CodingKeys: String, CodingKey {
        case chapterID
        case packageID
        case contentVersion
        case arcID
        case beatID
        case beatCompletionContract
        case sceneVisualSnapshot
        case interaction
        case responsiveAudioSnapshot
        case responsiveAudioChapterOpenNonce
        case responsiveAudioSessionGeneration
        case responsiveAudioSessionIsActive
        case cameraAnchor
        case readingAnchor
        case narration
        case completedBeatIDs
        case completedArcIDs
        case completedBeatReviewRecords
        case lastVisitedAtEpochMillis
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chapterID = try container.decode(ChapterID.self, forKey: .chapterID)
        packageID = try container.decode(PackageID.self, forKey: .packageID)
        contentVersion = try container.decode(SchemaVersion.self, forKey: .contentVersion)
        arcID = try container.decodeIfPresent(ArcID.self, forKey: .arcID)
        beatID = try container.decodeIfPresent(BeatID.self, forKey: .beatID)
        beatCompletionContract = try container.decodeIfPresent(
            BeatCompletionContract.self,
            forKey: .beatCompletionContract
        )
        sceneVisualSnapshot = try container.decodeIfPresent(
            SceneVisualSnapshot.self,
            forKey: .sceneVisualSnapshot
        )
        interaction = try container.decodeIfPresent(
            InteractionRuntimeState.self,
            forKey: .interaction
        )
        responsiveAudioSnapshot = try container.decodeIfPresent(
            ResponsiveAudioProgramSnapshot.self,
            forKey: .responsiveAudioSnapshot
        )
        responsiveAudioChapterOpenNonce = try container.decodeIfPresent(
            UUID.self,
            forKey: .responsiveAudioChapterOpenNonce
        )
        responsiveAudioSessionGeneration = try container.decodeIfPresent(
            UInt64.self,
            forKey: .responsiveAudioSessionGeneration
        ) ?? 0
        responsiveAudioSessionIsActive = try container.decodeIfPresent(
            Bool.self,
            forKey: .responsiveAudioSessionIsActive
        ) ?? false
        cameraAnchor = try container.decodeIfPresent(Double.self, forKey: .cameraAnchor) ?? 0
        readingAnchor = try container.decodeIfPresent(String.self, forKey: .readingAnchor)
        narration = try container.decodeIfPresent(NarrationCursor.self, forKey: .narration)
            ?? NarrationCursor()
        completedBeatIDs = Array(Set(
            try container.decodeIfPresent([BeatID].self, forKey: .completedBeatIDs) ?? []
        )).sorted()
        completedArcIDs = Array(Set(
            try container.decodeIfPresent([ArcID].self, forKey: .completedArcIDs) ?? []
        )).sorted()
        completedBeatReviewRecords = Self.normalized(
            try container.decodeIfPresent(
                [CompletedBeatReviewRecord].self,
                forKey: .completedBeatReviewRecords
            ) ?? []
        )
        lastVisitedAtEpochMillis = try container.decodeIfPresent(
            Int64.self,
            forKey: .lastVisitedAtEpochMillis
        )
    }

    public func reviewRecord(for beatID: BeatID) -> CompletedBeatReviewRecord? {
        completedBeatReviewRecords.first { $0.beatID == beatID }
    }

    /// Whether every completed beat has one sealed, canonically indexed review
    /// record belonging to this exact persisted content identity. Authored arc,
    /// beat and scene identities still require validation against ContentKit.
    public var hasSealedReviewArchiveForCompletedBeats: Bool {
        guard !completedBeatIDs.isEmpty,
              Set(completedBeatIDs).count == completedBeatIDs.count,
              completedBeatReviewRecords.count == completedBeatIDs.count else {
            return false
        }

        let archivedBeatIDs = completedBeatReviewRecords.map(\.beatID)
        guard Set(archivedBeatIDs).count == archivedBeatIDs.count,
              Set(archivedBeatIDs) == Set(completedBeatIDs),
              completedBeatReviewRecords.map(\.absoluteBeatIndex)
                == Array(completedBeatReviewRecords.indices) else {
            return false
        }

        return completedBeatReviewRecords.allSatisfy { record in
            record.isStructurallyValid
                && record.chapterID == chapterID
                && record.packageID == packageID
                && record.contentVersion == contentVersion
        }
    }

    private static func normalized(
        _ records: [CompletedBeatReviewRecord]
    ) -> [CompletedBeatReviewRecord] {
        var byBeatID: [BeatID: CompletedBeatReviewRecord] = [:]
        for record in records {
            byBeatID[record.beatID] = record
        }
        return byBeatID.values.sorted {
            if $0.absoluteBeatIndex != $1.absoluteBeatIndex {
                return $0.absoluteBeatIndex < $1.absoluteBeatIndex
            }
            return $0.beatID < $1.beatID
        }
    }
}

public struct InstalledContentVersion: Codable, Equatable, Sendable {
    public let packageID: PackageID
    public let version: SchemaVersion

    public init(packageID: PackageID, version: SchemaVersion) {
        self.packageID = packageID
        self.version = version
    }
}

public struct JourneyState: Codable, Equatable, Sendable {
    public static let currentStateSchemaVersion = 4

    public private(set) var stateSchemaVersion: Int
    public var route: JourneyRoute
    public var prologue: PrologueState
    public var world: WorldGraph
    public var chapterReview: ChapterReviewState?
    public var chapterSessions: [ChapterSession]
    public var completedChapterIDs: [ChapterID]
    public var installedContent: [InstalledContentVersion]
    public var lastLogicalTimeMillis: Int64
    public var appliedEventCount: Int

    public init(
        route: JourneyRoute = .prologue,
        prologue: PrologueState = PrologueState(),
        world: WorldGraph = WorldGraph(),
        chapterReview: ChapterReviewState? = nil,
        activeChapter: ChapterSession? = nil,
        chapterSessions: [ChapterSession] = [],
        completedChapterIDs: [ChapterID] = [],
        installedContent: [InstalledContentVersion] = [],
        lastLogicalTimeMillis: Int64 = 0,
        appliedEventCount: Int = 0
    ) {
        stateSchemaVersion = Self.currentStateSchemaVersion
        self.route = route
        self.prologue = prologue
        self.world = world
        self.chapterReview = chapterReview
        var sessions = chapterSessions
        if let activeChapter {
            sessions.removeAll { $0.chapterID == activeChapter.chapterID }
            sessions.append(activeChapter)
        }
        self.chapterSessions = sessions.sorted { $0.chapterID < $1.chapterID }
        self.completedChapterIDs = completedChapterIDs.sorted()
        self.installedContent = installedContent.sorted { $0.packageID < $1.packageID }
        self.lastLogicalTimeMillis = lastLogicalTimeMillis
        self.appliedEventCount = appliedEventCount
    }

    public static let initial = JourneyState()

    public var activeChapter: ChapterSession? {
        get {
            guard case let .chapter(chapterID) = route else { return nil }
            return chapterSessions.first { $0.chapterID == chapterID }
        }
        set {
            let previousID: ChapterID?
            if case let .chapter(chapterID) = route {
                previousID = chapterID
            } else {
                previousID = nil
            }
            if let newValue {
                chapterSessions.removeAll { $0.chapterID == newValue.chapterID }
                chapterSessions.append(newValue)
                chapterSessions.sort { $0.chapterID < $1.chapterID }
            } else if let previousID {
                chapterSessions.removeAll { $0.chapterID == previousID }
            }
        }
    }

    public func chapterSession(_ chapterID: ChapterID) -> ChapterSession? {
        chapterSessions.first { $0.chapterID == chapterID }
    }

    public var mostRecentlyVisitedChapterID: ChapterID? {
        chapterSessions.max { lhs, rhs in
            let leftTime = lhs.lastVisitedAtEpochMillis ?? Int64.min
            let rightTime = rhs.lastVisitedAtEpochMillis ?? Int64.min
            if leftTime != rightTime { return leftTime < rightTime }
            return lhs.chapterID < rhs.chapterID
        }?.chapterID
    }

    public mutating func prepareForColdRestore() {
        for index in chapterSessions.indices {
            chapterSessions[index].narration.isPlaying = false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case stateSchemaVersion
        case route
        case prologue
        case world
        case chapterReview
        case activeChapter
        case chapterSessions
        case completedChapterIDs
        case installedContent
        case lastLogicalTimeMillis
        case appliedEventCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .stateSchemaVersion
        ) ?? 1
        guard (1 ... Self.currentStateSchemaVersion).contains(decodedVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .stateSchemaVersion,
                in: container,
                debugDescription: "Unsupported JourneyState schema version \(decodedVersion)"
            )
        }
        stateSchemaVersion = Self.currentStateSchemaVersion
        route = try container.decode(JourneyRoute.self, forKey: .route)
        prologue = try container.decode(PrologueState.self, forKey: .prologue)
        world = try container.decode(WorldGraph.self, forKey: .world)
        chapterReview = try container.decodeIfPresent(
            ChapterReviewState.self,
            forKey: .chapterReview
        )
        completedChapterIDs = try container.decodeIfPresent(
            [ChapterID].self,
            forKey: .completedChapterIDs
        ) ?? []
        installedContent = try container.decodeIfPresent(
            [InstalledContentVersion].self,
            forKey: .installedContent
        ) ?? []
        lastLogicalTimeMillis = try container.decodeIfPresent(
            Int64.self,
            forKey: .lastLogicalTimeMillis
        ) ?? 0
        appliedEventCount = try container.decodeIfPresent(
            Int.self,
            forKey: .appliedEventCount
        ) ?? 0

        var sessions = try container.decodeIfPresent(
            [ChapterSession].self,
            forKey: .chapterSessions
        ) ?? []
        if sessions.isEmpty,
           let legacyActive = try container.decodeIfPresent(
               ChapterSession.self,
               forKey: .activeChapter
           ) {
            sessions = [legacyActive]
        }
        var uniqueSessions: [ChapterID: ChapterSession] = [:]
        for session in sessions {
            uniqueSessions[session.chapterID] = session
        }
        chapterSessions = uniqueSessions.values.sorted { $0.chapterID < $1.chapterID }
        completedChapterIDs = Array(Set(completedChapterIDs)).sorted()
        installedContent.sort { $0.packageID < $1.packageID }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentStateSchemaVersion, forKey: .stateSchemaVersion)
        try container.encode(route, forKey: .route)
        try container.encode(prologue, forKey: .prologue)
        try container.encode(world, forKey: .world)
        try container.encodeIfPresent(chapterReview, forKey: .chapterReview)
        try container.encode(chapterSessions, forKey: .chapterSessions)
        try container.encode(completedChapterIDs, forKey: .completedChapterIDs)
        try container.encode(installedContent, forKey: .installedContent)
        try container.encode(lastLogicalTimeMillis, forKey: .lastLogicalTimeMillis)
        try container.encode(appliedEventCount, forKey: .appliedEventCount)
    }
}

public struct SaveSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let state: JourneyState

    public init(formatVersion: Int = currentFormatVersion, state: JourneyState) {
        self.formatVersion = formatVersion
        self.state = state
    }
}

public enum JourneyAction: Codable, Equatable, Sendable {
    case launch
    case updatePrologueTrace(Double)
    case completePrologue([WorldEffect])
    case showWorld
    case selectChapter(chapterID: ChapterID, packageID: PackageID, contentVersion: SchemaVersion)
    case beginChapter(
        chapterID: ChapterID,
        packageID: PackageID,
        contentVersion: SchemaVersion,
        arcID: ArcID,
        beatID: BeatID
    )
    case beginAuthoredChapter(BeatCompletionContract)
    case enterBeat(arcID: ArcID, beatID: BeatID)
    case enterAuthoredBeat(BeatCompletionContract)
    case restoreAuthoredBeat(BeatCompletionContract)
    case beginInteraction(InteractionSpec)
    case interact(spec: InteractionSpec, action: InteractionAction)
    case setResponsiveAudioSnapshot(ResponsiveAudioProgramSnapshot)
    case beginResponsiveAudioSession(
        chapterOpenNonce: UUID,
        generation: UInt64,
        snapshot: ResponsiveAudioProgramSnapshot
    )
    case endResponsiveAudioSession(ResponsiveAudioProgramSnapshot)
    case activateScene(SceneActivationContract)
    case updateSceneVisualTick(
        contract: SceneActivationContract,
        deterministicTick: UInt64
    )
    case setCameraAnchor(Double)
    case setReadingAnchor(String?)
    case setNarration(cueID: AudioCueID?, sampleOffset: Int64, enabled: Bool, playing: Bool)
    case pauseNarration
    case recordChapterVisit(chapterID: ChapterID, atEpochMillis: Int64)
    case completeBeat(arcID: ArcID, beatID: BeatID)
    case completeDocumentaryBeat(BeatCompletionContract)
    case completeAuthoredArc(ArcCompletionContract)
    case suspendChapter(atEpochMillis: Int64)
    case completeAuthoredChapter(ChapterCompletionContract)
    case installContent(packageID: PackageID, version: SchemaVersion)
    case openBeatReview(chapterID: ChapterID, beatID: BeatID)
    case moveBeatReview(beatID: BeatID)
    case setReviewReadingAnchor(String?)
    case closeBeatReview
}

public struct JourneyEvent: Codable, Equatable, Sendable {
    public let logicalTimeMillis: Int64
    public let action: JourneyAction

    public init(logicalTimeMillis: Int64, action: JourneyAction) {
        self.logicalTimeMillis = logicalTimeMillis
        self.action = action
    }
}

public enum CheckpointReason: String, Codable, Equatable, Sendable {
    case prologueCompleted
    case routeChanged
    case beatChanged
    case interactionChanged
    case responsiveAudioChanged
    case sceneVisualChanged
    case chapterCompleted
    case contentChanged
    case suspension
    case reviewChanged
}

public enum JourneyEffect: Equatable, Sendable {
    case checkpoint(CheckpointReason)
    case haptic(HapticSemantic)
    case worldChanged([WorldEffectID])
    case rejected(String)
}
