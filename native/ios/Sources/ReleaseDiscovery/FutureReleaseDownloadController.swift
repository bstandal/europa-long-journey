import ContentDelivery
import ContentKit
import ExperiencePreferences
import Foundation

public enum FutureReleaseDownloadIntent: Equatable, Sendable {
    case explicit
    case automatic
}

public enum FutureReleaseDownloadNoOperationReason: Equatable, Sendable {
    case alreadyCurrent
    case newerVersionRequiresNewerApp
    case requiresRuntime(SchemaVersion)
    case notPublished
    case unknownRelease
}

public enum FutureReleaseDownloadRequestResult: Equatable, Sendable {
    case started(releaseID: ReleaseID, packageID: PackageID)
    case blocked(DownloadInitiationBlockReason)
    case noOperation(FutureReleaseDownloadNoOperationReason)
    case installerRejected(PackageBatchInstallationError)
}

public enum FutureReleaseDownloadControllerError: Error, Equatable, Sendable {
    case bootstrapRequired
    case installedPackageWithoutContract(PackageID)
    case startInputsDidNotStabilize
}

public struct FutureReleaseDownloadSnapshot: Equatable, Sendable {
    /// Complete authenticated installation contracts, including their
    /// authored world placements and public announcements. These come only
    /// from the sealed installation ledger; the live discovery catalog is
    /// never a cold/offline dependency for an already retained release.
    public let retainedCatalogEntries: [ReleaseCatalogEntry]
    public let currentInstalledPackageIDs: [PackageID]
    public let installationState: PackageBatchInstallationState
    public let systemTransferState: PackageSystemTransferState

    public var retainedReleaseIDs: [ReleaseID] {
        retainedCatalogEntries.map(\.id)
    }

    public init(
        retainedCatalogEntries: [ReleaseCatalogEntry],
        currentInstalledPackageIDs: [PackageID],
        installationState: PackageBatchInstallationState,
        systemTransferState: PackageSystemTransferState
    ) {
        self.retainedCatalogEntries = retainedCatalogEntries
        self.currentInstalledPackageIDs = currentInstalledPackageIDs
        self.installationState = installationState
        self.systemTransferState = systemTransferState
    }
}

/// Dynamic post-launch delivery boundary. It accepts only a complete Release
/// resolved and durably retained by `ReleaseDiscoveryController`, then passes
/// the exact derived `ContentPackageSpec` through the same package installer
/// used for launch content. The bounded notification/deep-link model is never
/// installation authority.
public actor FutureReleaseDownloadController {
    public typealias InstalledIndexProvider = @Sendable () async throws
        -> InstalledPackageIndex
    public typealias PreferencesProvider = @Sendable () async throws
        -> ExperiencePreferences

    private struct StartInputs: Equatable, Sendable {
        let installedIndex: InstalledPackageIndex
        let preferences: ExperiencePreferences
    }

    private static let maximumStartInputSnapshots = 8

    private let discovery: ReleaseDiscoveryController
    private let installer: PackageBatchInstaller
    private let requestInitiator: DownloadRequestInitiator
    private let installedIndexProvider: InstalledIndexProvider
    private let preferencesProvider: PreferencesProvider

    private var retainedEntries: [ReleaseCatalogEntry] = []
    private var isBootstrapped = false
    private var activeRequestToken: UUID?

    public init(
        discovery: ReleaseDiscoveryController,
        installer: PackageBatchInstaller,
        networkBasisProvider: any DownloadNetworkBasisProviding,
        installedIndexProvider: @escaping InstalledIndexProvider,
        preferencesProvider: @escaping PreferencesProvider
    ) {
        self.discovery = discovery
        self.installer = installer
        requestInitiator = DownloadRequestInitiator(
            networkBasisProvider: networkBasisProvider
        )
        self.installedIndexProvider = installedIndexProvider
        self.preferencesProvider = preferencesProvider
    }

    /// Restores an interrupted application queue only from the separately
    /// authenticated installation ledger. The live catalog may be empty or
    /// offline at this point.
    @discardableResult
    public func bootstrap() async throws -> FutureReleaseDownloadSnapshot {
        if isBootstrapped {
            return try await snapshot()
        }
        let entries = try await discovery.retainedInstallationContracts()
        let packages = try entries.map { try $0.release.packageSpecForVerification() }
        let index = try await installedIndexProvider()
        try Self.requireContracts(for: index, packages: packages)
        try await installer.restoreQueue(
            installedIndex: index,
            canonicalPackages: packages,
            policy: .requireExplicitResume
        )
        retainedEntries = entries
        isBootstrapped = true
        return try await makeSnapshot(index: index)
    }

    public func snapshot() async throws -> FutureReleaseDownloadSnapshot {
        try requireBootstrap()
        let index = try await installedIndexProvider()
        return try await makeSnapshot(index: index)
    }

    public func request(
        _ releaseID: ReleaseID,
        intent: FutureReleaseDownloadIntent
    ) async throws -> FutureReleaseDownloadRequestResult {
        try requireBootstrap()
        guard activeRequestToken == nil else {
            return .installerRejected(.alreadyRunning)
        }
        let requestToken = UUID()
        activeRequestToken = requestToken
        defer {
            if activeRequestToken == requestToken {
                activeRequestToken = nil
            }
        }

        let resolution = try await discovery
            .retainPackageContractForInstallation(releaseID)
        let entry: ReleaseCatalogEntry
        switch resolution {
        case let .ready(value):
            entry = value
        case let .requiresRuntime(minimum):
            return .noOperation(.requiresRuntime(minimum))
        case .notPublished:
            return .noOperation(.notPublished)
        case .unknownRelease:
            return .noOperation(.unknownRelease)
        }

        retainedEntries = try await discovery.retainedInstallationContracts()
        let package = try entry.release.packageSpecForVerification()
        let inputs = try await stabilizedStartInputs()
        switch InstalledPackageVersionAuthority(
            activeGeneration: inputs.installedIndex.activeGeneration(for: package.id),
            expectedVersion: package.version
        ) {
        case .current:
            return .noOperation(.alreadyCurrent)
        case .protectedNewer:
            return .noOperation(.newerVersionRequiresNewerApp)
        case .updateRequired:
            break
        }

        let downloadIntent: DownloadInitiationIntent = switch intent {
        case .explicit:
            .explicitSinglePackage
        case .automatic:
            .automaticDeepDive
        }
        switch requestInitiator.decisionForNewRequest(
            intent: downloadIntent,
            preferences: inputs.preferences
        ) {
        case .initiateNewRequest:
            do {
                try await installer.start(packages: [package])
                return .started(releaseID: releaseID, packageID: package.id)
            } catch let error as PackageBatchInstallationError {
                return .installerRejected(error)
            }
        case let .doNotInitiateNewRequest(reason):
            return .blocked(reason)
        }
    }

    public func resumeQueue() async throws {
        try requireBootstrap()
        try await installer.resume()
    }

    public func retryFailedPackage() async throws {
        try requireBootstrap()
        try await installer.retryFailed()
    }

    public func removeFailedPackage() async throws {
        try requireBootstrap()
        try await installer.removeFailed()
    }

    public func installationStateUpdates()
        async -> AsyncStream<PackageBatchInstallationState> {
        await installer.stateUpdates()
    }

    public func systemTransferStateUpdates()
        async -> AsyncStream<PackageSystemTransferState> {
        await installer.systemTransferStateUpdates()
    }

    private func stabilizedStartInputs() async throws -> StartInputs {
        var prior: StartInputs?
        for _ in 0 ..< Self.maximumStartInputSnapshots {
            let inputs = StartInputs(
                installedIndex: try await installedIndexProvider(),
                preferences: try await preferencesProvider()
            )
            let packages = try retainedEntries.map {
                try $0.release.packageSpecForVerification()
            }
            try Self.requireContracts(
                for: inputs.installedIndex,
                packages: packages
            )
            if inputs == prior { return inputs }
            prior = inputs
        }
        throw FutureReleaseDownloadControllerError.startInputsDidNotStabilize
    }

    private func makeSnapshot(
        index: InstalledPackageIndex
    ) async throws -> FutureReleaseDownloadSnapshot {
        let packages = try retainedEntries.map {
            try $0.release.packageSpecForVerification()
        }
        try Self.requireContracts(for: index, packages: packages)
        let knownPackageIDs = Set(packages.map(\.id))
        return FutureReleaseDownloadSnapshot(
            retainedCatalogEntries: retainedEntries,
            currentInstalledPackageIDs: index.activeGenerationByPackage.keys
                .filter(knownPackageIDs.contains)
                .sorted(),
            installationState: await installer.state(),
            systemTransferState: await installer.systemTransferState()
        )
    }

    private func requireBootstrap() throws {
        guard isBootstrapped else {
            throw FutureReleaseDownloadControllerError.bootstrapRequired
        }
    }

    private static func requireContracts(
        for index: InstalledPackageIndex,
        packages: [ContentPackageSpec]
    ) throws {
        let knownPackageIDs = Set(packages.map(\.id))
        if let unknown = Set(index.generations.map(\.packageID))
            .union(index.activeGenerationByPackage.keys)
            .subtracting(knownPackageIDs)
            .sorted()
            .first {
            throw FutureReleaseDownloadControllerError
                .installedPackageWithoutContract(unknown)
        }
    }
}
