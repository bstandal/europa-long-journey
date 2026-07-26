import ExperiencePreferences

public enum DownloadRequestInitiationResult: Equatable, Sendable {
    case startedNewRequest
    case didNotStartNewRequest(reason: DownloadInitiationBlockReason)
}

public enum DownloadRequestInitiatorError: Error, Equatable, Sendable {
    case startOperationRequired
}

/// Applies the latest path observation and current preferences immediately
/// before asking an injected operation to create one new request.
///
/// This coordinator deliberately exposes no pause, resume, retry, cancellation
/// or transfer-status operation. Those remain under `PackageBatchInstaller` and
/// Apple's existing-transfer lifecycle.
public struct DownloadRequestInitiator: Sendable {
    public typealias StartOperation = @Sendable (DownloadInitiationIntent) async throws -> Void

    private let networkBasisProvider: any DownloadNetworkBasisProviding
    private let defaultStartOperation: StartOperation?

    public init(networkBasisProvider: any DownloadNetworkBasisProviding) {
        self.networkBasisProvider = networkBasisProvider
        defaultStartOperation = nil
    }

    public init(
        networkBasisProvider: any DownloadNetworkBasisProviding,
        startOperation: @escaping StartOperation
    ) {
        self.networkBasisProvider = networkBasisProvider
        defaultStartOperation = startOperation
    }

    public func initiateNewRequest(
        intent: DownloadInitiationIntent,
        preferences: ExperiencePreferences
    ) async throws -> DownloadRequestInitiationResult {
        guard let defaultStartOperation else {
            throw DownloadRequestInitiatorError.startOperationRequired
        }
        return try await initiateNewRequest(
            intent: intent,
            preferences: preferences,
            startOperation: defaultStartOperation
        )
    }

    /// Applies policy to one concrete new-request operation. The operation is
    /// supplied per call so a higher-level controller can select an exact
    /// package queue without storing mutable request intent between awaits.
    public func initiateNewRequest(
        intent: DownloadInitiationIntent,
        preferences: ExperiencePreferences,
        startOperation: @escaping StartOperation
    ) async throws -> DownloadRequestInitiationResult {
        let decision = decisionForNewRequest(intent: intent, preferences: preferences)

        switch decision {
        case .initiateNewRequest:
            try await startOperation(intent)
            return .startedNewRequest
        case let .doNotInitiateNewRequest(reason):
            return .didNotStartNewRequest(reason: reason)
        }
    }

    /// Performs the final synchronous policy read. A caller that already owns
    /// the concrete start boundary can invoke this immediately before its actor
    /// hop into the installer, without an intervening coordinator hop.
    public func decisionForNewRequest(
        intent: DownloadInitiationIntent,
        preferences: ExperiencePreferences
    ) -> DownloadInitiationDecision {
        let networkContext = networkBasisProvider.currentNetworkContext()
        return DownloadInitiationPolicy(preferences: preferences).decision(
            for: intent,
            networkBasis: networkContext.basis,
            isConstrained: networkContext.isConstrained
        )
    }
}
