import ContentKit
import Foundation

/// The exact terminal state of one authored beat. Review presentation reads
/// this value; it never replays the interaction or derives a new outcome from
/// the cumulative world.
public struct CompletedBeatReviewRecord: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let completionContract: BeatCompletionContract
    public let sceneVisualSnapshot: SceneVisualSnapshot
    public let interaction: InteractionRuntimeState?
    public let cameraAnchor: Double
    public let readingAnchor: String?

    public var packageID: PackageID { completionContract.packageID }
    public var contentVersion: SchemaVersion { completionContract.contentVersion }
    public var chapterID: ChapterID { completionContract.chapterID }
    public var arcID: ArcID { completionContract.arcID }
    public var beatID: BeatID { completionContract.beatID }
    public var arcIndex: Int { completionContract.arcIndex }
    public var beatIndex: Int { completionContract.beatIndex }
    public var absoluteBeatIndex: Int { completionContract.absoluteBeatIndex }

    public init(
        completionContract: BeatCompletionContract,
        sceneVisualSnapshot: SceneVisualSnapshot,
        interaction: InteractionRuntimeState?,
        cameraAnchor: Double,
        readingAnchor: String?,
        formatVersion: Int = Self.currentFormatVersion
    ) {
        self.formatVersion = formatVersion
        self.completionContract = completionContract
        self.sceneVisualSnapshot = sceneVisualSnapshot
        self.interaction = interaction
        self.cameraAnchor = cameraAnchor
        self.readingAnchor = readingAnchor
    }

    @_spi(JourneyContent)
    public var isStructurallyValid: Bool {
        guard formatVersion == Self.currentFormatVersion,
              completionContract.isStructurallyValid,
              sceneVisualSnapshot.formatVersion == SceneVisualSnapshot.currentFormatVersion,
              cameraAnchor.isFinite,
              (0 ... 1).contains(cameraAnchor) else {
            return false
        }
        switch (completionContract.mode, interaction) {
        case (.documentary, nil):
            return true
        case let (.interaction(id, _), runtime?):
            return runtime.interactionID == id && runtime.phase == .complete
        case (.documentary, .some), (.interaction, nil):
            return false
        }
    }
}

/// A durable, read-only overlay. The underlying Journey route remains the
/// active causal route (or the living world for a completed chapter).
public struct ChapterReviewState: Codable, Equatable, Sendable {
    public let chapterID: ChapterID
    public let packageID: PackageID
    public let contentVersion: SchemaVersion
    public var beatID: BeatID
    public var readingAnchor: String?

    public init(
        chapterID: ChapterID,
        packageID: PackageID,
        contentVersion: SchemaVersion,
        beatID: BeatID,
        readingAnchor: String? = nil
    ) {
        self.chapterID = chapterID
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.beatID = beatID
        self.readingAnchor = readingAnchor
    }
}

/// Process-local authority for resuming the active scene's authored audio
/// after a deliberate review detour. This value is intentionally not Codable:
/// a restored review must always require an explicit sound resume.
public struct ChapterReviewReturnAudioAuthorization: Equatable, Sendable {
    private struct Origin: Equatable, Sendable {
        let chapterID: ChapterID
        let packageID: PackageID
        let contentVersion: SchemaVersion
        let beatID: BeatID
    }

    private var origin: Origin?

    public init() {}

    /// Captures only an already-durable review opened beside the active causal
    /// chapter. A completed chapter reviewed from the world has no scene to
    /// resume and therefore cannot mint this authority.
    @discardableResult
    public mutating func authorizeReturnFromReview(
        in state: JourneyState
    ) -> Bool {
        guard let review = state.chapterReview,
              case let .chapter(chapterID) = state.route,
              chapterID == review.chapterID,
              let session = state.activeChapter,
              session.packageID == review.packageID,
              session.contentVersion == review.contentVersion,
              let beatID = session.beatID,
              let record = session.reviewRecord(for: review.beatID),
              record.isStructurallyValid,
              record.packageID == review.packageID,
              record.contentVersion == review.contentVersion else {
            origin = nil
            return false
        }
        origin = Origin(
            chapterID: chapterID,
            packageID: session.packageID,
            contentVersion: session.contentVersion,
            beatID: beatID
        )
        return true
    }

    /// Consumes the authority exactly once, after the durable close has
    /// restored the same active scene and content identity.
    public mutating func consumeReturnGrant(
        in state: JourneyState
    ) -> ChapterID? {
        guard let origin else { return nil }
        self.origin = nil
        guard state.chapterReview == nil,
              case let .chapter(chapterID) = state.route,
              chapterID == origin.chapterID,
              let session = state.activeChapter,
              session.packageID == origin.packageID,
              session.contentVersion == origin.contentVersion,
              session.beatID == origin.beatID else {
            return nil
        }
        return chapterID
    }

    public mutating func invalidate() {
        origin = nil
    }
}
