import ContentKit

public enum ChapterResponsiveAudioChoice: String, Equatable, Sendable {
    case undecided
    case starting
    case playing
    case silent
    case resumeRequired

    public var authorizesPlayback: Bool {
        self == .playing
    }
}

public struct ChapterResponsiveAudioPlaybackAttempt: Equatable, Sendable {
    fileprivate enum Kind: Equatable, Sendable {
        case explicitChoice
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

/// Keeps one explicit sound decision for one uninterrupted chapter visit.
/// Every runtime binding receives a new generation, so a completion from an
/// older beat, program, crop or reduce-motion controller cannot publish state
/// into its successor.
public struct ChapterResponsiveAudioSessionPolicy: Equatable, Sendable {
    public private(set) var choice: ChapterResponsiveAudioChoice = .undecided

    private var activeChapterID: ChapterID?
    private var bindingGeneration: UInt64 = 0
    private var responsiveAudioIsBound = false

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
            choice = hasResponsiveAudio && restoredSessionIsActive
                ? .resumeRequired
                : .undecided
        } else if choice == .starting {
            // The controller that owned this start is being replaced. Keep the
            // user's intent visible, but require a fresh action before sound.
            choice = .resumeRequired
        } else if hasResponsiveAudio,
                  restoredSessionIsActive,
                  choice == .undecided {
            // A new route session may be presenting a crash- or suspension-
            // restored audio session. Preserve its exact paused cursor, but do
            // not mistake the new view process for fresh consent or autoplay.
            choice = .resumeRequired
        }
        responsiveAudioIsBound = hasResponsiveAudio

        guard continuesChapter,
              hasResponsiveAudio,
              choice == .playing else {
            return .none
        }
        return .startAuthorizedPlayback(
            attempt(kind: .authorizedRebind, chapterID: chapterID)
        )
    }

    public mutating func chooseSound() -> ChapterResponsiveAudioPlaybackAttempt? {
        guard responsiveAudioIsBound,
              let activeChapterID,
              choice != .starting,
              choice != .playing else {
            return nil
        }
        choice = .starting
        return attempt(kind: .explicitChoice, chapterID: activeChapterID)
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
        case .explicitChoice:
            guard choice == .starting else { return false }
        case .authorizedRebind:
            guard choice == .playing else { return false }
        }
        choice = didStart ? .playing : .resumeRequired
        return true
    }

    public mutating func continueInSilence() {
        guard responsiveAudioIsBound, choice == .undecided else { return }
        choice = .silent
    }

    public mutating func requireExplicitResume() {
        guard choice == .playing || choice == .starting else { return }
        bindingGeneration &+= 1
        choice = .resumeRequired
    }

    public mutating func deactivate() {
        bindingGeneration &+= 1
        activeChapterID = nil
        responsiveAudioIsBound = false
        choice = .undecided
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
