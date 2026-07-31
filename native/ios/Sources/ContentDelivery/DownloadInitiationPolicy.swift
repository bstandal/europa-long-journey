import ExperiencePreferences

/// The network basis known at the instant the app considers creating a new
/// download request. This is deliberately independent of Apple's state for a
/// transfer that has already begun.
public enum DownloadNetworkBasis: String, CaseIterable, Equatable, Sendable {
    case wifi
    case cellular
    case wired
    case offline
    case unknown
}

public enum DownloadInitiationIntent: String, CaseIterable, Equatable, Sendable {
    case explicitSinglePackage
    case explicitDownloadAll
    case automaticDeepDive
}

/// Machine-readable reasons are kept inside the delivery boundary. User-facing
/// wording belongs to the product shell that presents or retries the action.
public enum DownloadInitiationBlockReason: String, CaseIterable, Equatable, Sendable {
    case offline
    case unknownNetwork
    case cellularDownloadsDisabled
    case automaticDeepDiveDownloadsDisabled
    case lowDataMode
}

/// This decision governs creation of one new request. `doNotInitiateNewRequest`
/// is not an instruction to cancel, suspend or otherwise control an Apple-
/// managed transfer that is already in progress.
public enum DownloadInitiationDecision: Equatable, Sendable {
    case initiateNewRequest
    case doNotInitiateNewRequest(reason: DownloadInitiationBlockReason)

    public var shouldInitiateNewRequest: Bool {
        self == .initiateNewRequest
    }
}

/// Pure initiation policy derived only from the two download preferences.
/// Authored-audio and haptic choices cannot affect delivery decisions.
public struct DownloadInitiationPolicy: Equatable, Sendable {
    public let cellularDownloadsEnabled: Bool
    public let automaticDeepDiveDownloadsEnabled: Bool

    public init(preferences: ExperiencePreferences) {
        cellularDownloadsEnabled = preferences.cellularDownloadsEnabled
        automaticDeepDiveDownloadsEnabled = preferences.automaticDeepDiveDownloadsEnabled
    }

    public func decision(
        for intent: DownloadInitiationIntent,
        networkBasis: DownloadNetworkBasis,
        isConstrained: Bool = false
    ) -> DownloadInitiationDecision {
        switch networkBasis {
        case .offline:
            return .doNotInitiateNewRequest(reason: .offline)
        case .unknown:
            return .doNotInitiateNewRequest(reason: .unknownNetwork)
        case .cellular where !cellularDownloadsEnabled:
            return .doNotInitiateNewRequest(reason: .cellularDownloadsDisabled)
        case .wifi, .wired, .cellular:
            break
        }

        if intent == .automaticDeepDive,
           !automaticDeepDiveDownloadsEnabled {
            return .doNotInitiateNewRequest(reason: .automaticDeepDiveDownloadsDisabled)
        }
        if intent == .automaticDeepDive, isConstrained {
            return .doNotInitiateNewRequest(reason: .lowDataMode)
        }

        return .initiateNewRequest
    }
}
