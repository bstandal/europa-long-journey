import ContentKit
import Foundation

/// The read-only chapter index consumed by ChapterCoordinator. Production
/// ContentRepository remains the only launch repository; this narrow boundary
/// lets DEBUG builds exercise an explicitly non-shipping package without
/// weakening any launch-manifest or essential-package rule.
public protocol ChapterContentRepository: Sendable {
    func chapter(_ id: ChapterID) -> ChapterSpec?
    func arc(_ id: ArcID) -> ArcSpec?
    func beat(_ id: BeatID) -> BeatSpec?
    func scene(_ id: SceneID) -> SceneSpec?
    func interaction(_ id: InteractionID) -> InteractionSpec?
    func accessibility(_ id: AccessibilityID) -> AccessibilitySpec?
    func packageID(for chapterID: ChapterID) -> PackageID?
    func contentVersion(for chapterID: ChapterID) -> SchemaVersion?
    func location(of arcID: ArcID) -> ArcContentLocation?
    func location(of beatID: BeatID) -> BeatContentLocation?
    func audioTimelineIDs(for beatID: BeatID) -> [AudioTimelineID]?
    func responsiveAudioProgram(
        for interactionID: InteractionID
    ) -> ResponsiveAudioProgramSpec?
    func responsiveAudioTimelines(
        for interactionID: InteractionID
    ) -> [AudioTimeline]?
}

extension ContentRepository: ChapterContentRepository {}
