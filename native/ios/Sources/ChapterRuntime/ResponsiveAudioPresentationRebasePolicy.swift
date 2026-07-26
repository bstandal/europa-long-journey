import JourneyDomain

/// Decides whether a scene presentation may adopt a newer Journey state
/// without constructing a new verified chapter runtime.
///
/// Responsive audio deliberately shares the Journey journal with scene input.
/// Its cursor and playback lease do not change the authored scene projection,
/// but every other durable field remains scene authority and must invalidate a
/// stale presentation. This policy keeps that exception explicit and testable.
public enum ResponsiveAudioPresentationRebaseDecision: Equatable, Sendable {
    case unchanged
    case rebase
    case reject
}

public enum ResponsiveAudioPresentationRebasePolicy {
    public static func decide(
        published: JourneyState,
        committed: JourneyState
    ) -> ResponsiveAudioPresentationRebaseDecision {
        guard published != committed else { return .unchanged }
        guard committed.appliedEventCount > published.appliedEventCount,
              committed.lastLogicalTimeMillis > published.lastLogicalTimeMillis,
              committed.route == published.route,
              let publishedSession = published.activeChapter,
              var normalizedSession = committed.activeChapter,
              normalizedSession.chapterID == publishedSession.chapterID else {
            return .reject
        }

        var normalized = committed
        normalized.lastLogicalTimeMillis = published.lastLogicalTimeMillis
        normalized.appliedEventCount = published.appliedEventCount
        normalizedSession.responsiveAudioSnapshot =
            publishedSession.responsiveAudioSnapshot
        normalizedSession.responsiveAudioChapterOpenNonce =
            publishedSession.responsiveAudioChapterOpenNonce
        normalizedSession.responsiveAudioSessionGeneration =
            publishedSession.responsiveAudioSessionGeneration
        normalizedSession.responsiveAudioSessionIsActive =
            publishedSession.responsiveAudioSessionIsActive
        normalized.activeChapter = normalizedSession

        return normalized == published ? .rebase : .reject
    }
}
