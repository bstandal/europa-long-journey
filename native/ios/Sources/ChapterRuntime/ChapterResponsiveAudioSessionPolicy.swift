import ContentKit

public enum ChapterAudioPlaybackState: String, Equatable, Sendable {
    /// The bound scene has no responsive audio program.
    case inactive
    /// Authored audio is available and can start from a user-authorized entry
    /// or an explicit sound-control action.
    case ready
    case starting
    case playing
    case resumeRequired

    public var authorizesPlayback: Bool {
        self == .playing
    }
}

public struct ChapterResponsiveAudioPlaybackAttempt: Equatable, Sendable {
    fileprivate enum Kind: Equatable, Sendable {
        case userAuthorizedStart
        case authorizedRebind
    }

    fileprivate let chapterID: ChapterID
    fileprivate let bindingGeneration: UInt64
    fileprivate let kind: Kind
}

public enum ChapterResponsiveAudioBindingAction: Equatable, Sendable {
    case none
    case startAuthorizedPlayback(ChapterResponsiveAudioPlaybackAttempt)
}

/// Keeps playback authority for one uninterrupted chapter visit. A deliberate
/// chapter entry or sound-control action calls `requestPlayback()`; rebinding
/// the already-playing authored program does not ask the user again. Every
/// runtime binding receives a new generation, so a completion from an older
/// beat, program, crop or reduce-motion controller cannot publish state into
/// its successor.
public struct ChapterResponsiveAudioSessionPolicy: Equatable, Sendable {
    public private(set) var playbackState: ChapterAudioPlaybackState = .inactive

    private var activeChapterID: ChapterID?
    private var bindingGeneration: UInt64 = 0
    private var responsiveAudioIsBound = false
    /// Persists chapter playback intent through bindings that intentionally
    /// contain no responsive program, while `playbackState` remains an honest
    /// description of the currently bound scene.
    private var retainedChapterPlaybackState: ChapterAudioPlaybackState = .inactive

    public init() {}

    @discardableResult
    public mutating func bind(
        chapterID: ChapterID,
        hasResponsiveAudio: Bool,
        restoredSessionIsActive: Bool = false
    ) -> ChapterResponsiveAudioBindingAction {
        bindingGeneration &+= 1
        let continuesChapter = activeChapterID == chapterID
        if !continuesChapter {
            activeChapterID = chapterID
            retainedChapterPlaybackState = hasResponsiveAudio
                ? (restoredSessionIsActive ? .resumeRequired : .ready)
                : .inactive
        } else if retainedChapterPlaybackState == .starting {
            // The controller that owned this start is being replaced. Keep the
            // user's intent visible, but require a fresh action before sound.
            retainedChapterPlaybackState = .resumeRequired
        } else if hasResponsiveAudio,
                  restoredSessionIsActive,
                  retainedChapterPlaybackState == .ready {
            // A new route session may be presenting a crash- or suspension-
            // restored audio session. Preserve its exact paused cursor and
            // require a fresh resume action.
            retainedChapterPlaybackState = .resumeRequired
        } else if hasResponsiveAudio,
                  retainedChapterPlaybackState == .inactive {
            retainedChapterPlaybackState = restoredSessionIsActive
                ? .resumeRequired
                : .ready
        }
        responsiveAudioIsBound = hasResponsiveAudio

        guard hasResponsiveAudio else {
            playbackState = .inactive
            return .none
        }
        playbackState = retainedChapterPlaybackState

        guard continuesChapter,
              playbackState == .playing else {
            return .none
        }
        return .startAuthorizedPlayback(
            attempt(kind: .authorizedRebind, chapterID: chapterID)
        )
    }

    public mutating func requestPlayback() -> ChapterResponsiveAudioPlaybackAttempt? {
        guard responsiveAudioIsBound,
              let activeChapterID,
              playbackState == .ready || playbackState == .resumeRequired else {
            return nil
        }
        retainedChapterPlaybackState = .starting
        playbackState = .starting
        return attempt(kind: .userAuthorizedStart, chapterID: activeChapterID)
    }

    /// Returns false when a newer binding, background transition or route exit
    /// has already invalidated this completion.
    @discardableResult
    public mutating func completePlayback(
        _ attempt: ChapterResponsiveAudioPlaybackAttempt,
        didStart: Bool
    ) -> Bool {
        guard accepts(attempt) else { return false }
        switch attempt.kind {
        case .userAuthorizedStart:
            guard playbackState == .starting,
                  retainedChapterPlaybackState == .starting else { return false }
        case .authorizedRebind:
            guard playbackState == .playing,
                  retainedChapterPlaybackState == .playing else { return false }
        }
        retainedChapterPlaybackState = didStart ? .playing : .resumeRequired
        playbackState = retainedChapterPlaybackState
        return true
    }

    public mutating func requireExplicitResume() {
        guard retainedChapterPlaybackState == .playing
                || retainedChapterPlaybackState == .starting else { return }
        bindingGeneration &+= 1
        retainedChapterPlaybackState = .resumeRequired
        playbackState = responsiveAudioIsBound ? .resumeRequired : .inactive
    }

    /// A one-shot authored timeline has reached its verified terminal sample.
    /// Keep the binding available for an explicit replay, but invalidate the
    /// completed playback generation so a scene rebind cannot restart it.
    public mutating func completeFinitePlayback() {
        requireExplicitResume()
    }

    public mutating func deactivate() {
        bindingGeneration &+= 1
        activeChapterID = nil
        responsiveAudioIsBound = false
        retainedChapterPlaybackState = .inactive
        playbackState = .inactive
    }

    public func accepts(_ attempt: ChapterResponsiveAudioPlaybackAttempt) -> Bool {
        responsiveAudioIsBound
            && activeChapterID == attempt.chapterID
            && bindingGeneration == attempt.bindingGeneration
    }

    private func attempt(
        kind: ChapterResponsiveAudioPlaybackAttempt.Kind,
        chapterID: ChapterID
    ) -> ChapterResponsiveAudioPlaybackAttempt {
        ChapterResponsiveAudioPlaybackAttempt(
            chapterID: chapterID,
            bindingGeneration: bindingGeneration,
            kind: kind
        )
    }
}
