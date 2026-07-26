import ContentKit
import Foundation

public struct ChapterReorientationContext: Equatable, Sendable {
    public let chapterID: ChapterID
    public let arcID: ArcID?
    public let beatID: BeatID?
    public let absenceMillis: Int64

    public init(
        chapterID: ChapterID,
        arcID: ArcID?,
        beatID: BeatID?,
        absenceMillis: Int64
    ) {
        self.chapterID = chapterID
        self.arcID = arcID
        self.beatID = beatID
        self.absenceMillis = absenceMillis
    }
}

/// Determines only whether a short authored reorientation may be offered.
/// It never changes the saved causal point and never replays completed work.
public struct ChapterReorientationPolicy: Sendable {
    public static let defaultMinimumAbsenceMillis: Int64 = 6 * 60 * 60 * 1_000

    public let minimumAbsenceMillis: Int64

    public init(
        minimumAbsenceMillis: Int64 = Self.defaultMinimumAbsenceMillis
    ) {
        self.minimumAbsenceMillis = max(0, minimumAbsenceMillis)
    }

    public func context(
        for session: ChapterSession,
        nowEpochMillis: Int64
    ) -> ChapterReorientationContext? {
        guard let lastVisited = session.lastVisitedAtEpochMillis,
              nowEpochMillis >= lastVisited else {
            return nil
        }
        let absence = nowEpochMillis - lastVisited
        guard absence >= minimumAbsenceMillis else { return nil }
        return ChapterReorientationContext(
            chapterID: session.chapterID,
            arcID: session.arcID,
            beatID: session.beatID,
            absenceMillis: absence
        )
    }
}
