import ContentKit
import Foundation

public enum ChapterAccess: Equatable, Sendable {
    case included
    case purchased
    case locked(entitlementID: EntitlementID)
}

/// Launch access is derived only from the stable free-content IDs and the
/// authenticated entitlement snapshot. Unknown or future IDs therefore fail
/// closed until an explicit access rule is added.
public struct ChapterAccessResolver: Sendable {
    public init() {}

    public func access(
        to chapterID: ChapterID,
        snapshot: EntitlementSnapshot?,
        at date: Date
    ) -> ChapterAccess {
        if LaunchContent.freeChapterIDs.contains(chapterID) {
            return .included
        }
        guard LaunchContent.chapterOrder.contains(chapterID),
              snapshot?.grantsAccess(at: date) == true else {
            return .locked(entitlementID: LaunchContent.fullWorkEntitlementID)
        }
        return .purchased
    }

    public func canOpen(
        _ chapterID: ChapterID,
        snapshot: EntitlementSnapshot?,
        at date: Date
    ) -> Bool {
        switch access(to: chapterID, snapshot: snapshot, at: date) {
        case .included, .purchased:
            true
        case .locked:
            false
        }
    }
}
