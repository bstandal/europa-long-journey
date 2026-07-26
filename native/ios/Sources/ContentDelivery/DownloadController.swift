import ContentKit
import ExperiencePreferences
import Foundation

public enum DownloadControllerBootstrapState: Equatable, Sendable {
    case awaitingBootstrap
    case ready
}

public struct DownloadControllerSnapshot: Equatable, Sendable {
    public let bootstrapState: DownloadControllerBootstrapState
    public let currentInstalledPackageIDs: [PackageID]
    public let pendingPaidPackageIDs: [PackageID]
    public let outdatedPackages: [OutdatedPackageVersion]
    public let protectedNewerPackages: [ProtectedNewerPackageVersion]
    public let remainingMaximumInstalledBytes: Int64
    public let installationState: PackageBatchInstallationState
    public let systemTransferState: PackageSystemTransferState
    public let refreshFailure: PackageBatchFailure?

    public init(
        bootstrapState: DownloadControllerBootstrapState,
        currentInstalledPackageIDs: [PackageID],
        pendingPaidPackageIDs: [PackageID],
        outdatedPackages: [OutdatedPackageVersion],
        protectedNewerPackages: [ProtectedNewerPackageVersion],
        remainingMaximumInstalledBytes: Int64,
        installationState: PackageBatchInstallationState,
        systemTransferState: PackageSystemTransferState,
        refreshFailure: PackageBatchFailure? = nil
    ) {
        self.bootstrapState = bootstrapState
        self.currentInstalledPackageIDs = currentInstalledPackageIDs
        self.pendingPaidPackageIDs = pendingPaidPackageIDs
        self.outdatedPackages = outdatedPackages
        self.protectedNewerPackages = protectedNewerPackages
        self.remainingMaximumInstalledBytes = remainingMaximumInstalledBytes
        self.installationState = installationState
        self.systemTransferState = systemTransferState
        self.refreshFailure = refreshFailure
    }

    public static let awaitingBootstrap = DownloadControllerSnapshot(
        bootstrapState: .awaitingBootstrap,
        currentInstalledPackageIDs: [],
        pendingPaidPackageIDs: [],
        outdatedPackages: [],
        protectedNewerPackages: [],
        remainingMaximumInstalledBytes: 0,
        installationState: .idle,
        systemTransferState: .idle,
        refreshFailure: nil
    )
}

public enum DownloadControllerNoOperationReason: Equatable, Sendable {
    case nothingPending
    case essentialPackage
    case alreadyCurrent
    case newerVersionRequiresNewerApp
    case unknownPackage
    case nonLaunchPackage
}

public enum DownloadControllerRequestResult: Equatable, Sendable {
    case started(packageIDs: [PackageID])
    case blocked(reason: DownloadInitiationBlockReason)
    case noOperation(reason: DownloadControllerNoOperationReason)
    case installerRejected(reason: PackageBatchInstallationError)
}

public enum DownloadControllerError: Error, Equatable, Sendable {
    case bootstrapRequired
    case startInputsDidNotStabilize
}

/// Owns the launch-package delivery composition without adding persistence of
/// its own. The installed-package index is the active-byte authority and the
/// `PackageBatchQueueJournalStore` configured on `PackageBatchInstaller` is the
/// sole queue authority across process death.
public actor DownloadController {
    public typealias InstalledIndexProvider = @Sendable () async throws -> InstalledPackageIndex
    public typealias PreferencesProvider = @Sendable () async throws -> ExperiencePreferences

    private struct BootstrapResult: Sendable {
        let installedIndex: InstalledPackageIndex
        let plan: LaunchDownloadPlan
        let installationState: PackageBatchInstallationState
        let transferState: PackageSystemTransferState
    }

    private struct StartInputs: Equatable, Sendable {
        let installedIndex: InstalledPackageIndex
        let preferences: ExperiencePreferences
        let plan: LaunchDownloadPlan
    }

    private static let maximumStartInputSnapshots = 8

    private let manifest: CollectionManifest
    private let installer: PackageBatchInstaller
    private let requestInitiator: DownloadRequestInitiator
    private let installedIndexProvider: InstalledIndexProvider
    private let preferencesProvider: PreferencesProvider
    private let knownNonLaunchPackageIDs: Set<PackageID>

    private var latestInstalledIndex: InstalledPackageIndex?
    private var latestPlan: LaunchDownloadPlan?
    private var currentSnapshot: DownloadControllerSnapshot = .awaitingBootstrap
    private var bootstrapTask: Task<BootstrapResult, any Error>?
    private var activeNewRequestToken: UUID?
    private var nextRefreshToken: UInt64 = 0
    private var latestStartedRefreshToken: UInt64 = 0
    private var stateObserverTask: Task<Void, Never>?
    private var transferObserverTask: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<DownloadControllerSnapshot>.Continuation] = [:]

    public init(
        manifest: CollectionManifest = LaunchContent.collectionManifest,
        installer: PackageBatchInstaller,
        networkBasisProvider: any DownloadNetworkBasisProviding,
        installedIndexProvider: @escaping InstalledIndexProvider,
        preferencesProvider: @escaping PreferencesProvider,
        knownNonLaunchPackageIDs: Set<PackageID> = []
    ) {
        self.manifest = manifest
        self.installer = installer
        requestInitiator = DownloadRequestInitiator(
            networkBasisProvider: networkBasisProvider
        )
        self.installedIndexProvider = installedIndexProvider
        self.preferencesProvider = preferencesProvider
        self.knownNonLaunchPackageIDs = knownNonLaunchPackageIDs
    }

    deinit {
        stateObserverTask?.cancel()
        transferObserverTask?.cancel()
        for observer in observers.values {
            observer.finish()
        }
    }

    public func snapshot() -> DownloadControllerSnapshot {
        currentSnapshot
    }

    public func snapshotUpdates() -> AsyncStream<DownloadControllerSnapshot> {
        let observerID = UUID()
        let pair = AsyncStream<DownloadControllerSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        observers[observerID] = pair.continuation
        pair.continuation.yield(currentSnapshot)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(observerID) }
        }
        return pair.stream
    }

    /// Loads the latest integrity-checked active index, derives the canonical
    /// paid plan and restores any journaled queue without starting it.
    @discardableResult
    public func bootstrap() async throws -> DownloadControllerSnapshot {
        if currentSnapshot.bootstrapState == .ready {
            return currentSnapshot
        }

        let task: Task<BootstrapResult, any Error>
        if let bootstrapTask {
            task = bootstrapTask
        } else {
            let installedIndexProvider = installedIndexProvider
            let manifest = manifest
            let installer = installer
            let canonicalPaidPackages = try LaunchDownloadPlan(
                manifest: manifest,
                installedIndex: .empty
            ).packages
            task = Task {
                let installedIndex = try await installedIndexProvider()
                let plan = try LaunchDownloadPlan(
                    manifest: manifest,
                    installedIndex: installedIndex
                )
                try await installer.restoreQueue(
                    installedIndex: installedIndex,
                    canonicalPackages: canonicalPaidPackages,
                    policy: .requireExplicitResume
                )
                return BootstrapResult(
                    installedIndex: installedIndex,
                    plan: plan,
                    installationState: await installer.state(),
                    transferState: await installer.systemTransferState()
                )
            }
            bootstrapTask = task
        }

        do {
            let result = try await task.value
            if currentSnapshot.bootstrapState != .ready {
                latestInstalledIndex = result.installedIndex
                latestPlan = result.plan
                publish(makeSnapshot(
                    bootstrapState: .ready,
                    installedIndex: result.installedIndex,
                    plan: result.plan,
                    installationState: result.installationState,
                    transferState: result.transferState
                ))
                await beginObservingInstallerIfNeeded()
            }
            bootstrapTask = nil
            return currentSnapshot
        } catch {
            bootstrapTask = nil
            throw error
        }
    }

    public func requestSinglePackage(
        _ packageID: PackageID
    ) async throws -> DownloadControllerRequestResult {
        try requireBootstrap()

        if packageID == LaunchContent.essentialPackageID {
            return .noOperation(reason: .essentialPackage)
        }
        if knownNonLaunchPackageIDs.contains(packageID) {
            return .noOperation(reason: .nonLaunchPackage)
        }
        guard LaunchContent.packageIDsInDeliveryOrder.contains(packageID) else {
            return .noOperation(reason: .unknownPackage)
        }

        guard activeNewRequestToken == nil else {
            return .installerRejected(reason: .alreadyRunning)
        }
        let requestToken = UUID()
        activeNewRequestToken = requestToken
        defer {
            if activeNewRequestToken == requestToken {
                activeNewRequestToken = nil
            }
        }

        let inputs = try await stabilizedStartInputs()
        guard let package = manifest.packages.first(where: { $0.id == packageID }) else {
            return .noOperation(reason: .unknownPackage)
        }
        switch InstalledPackageVersionAuthority(
            activeGeneration: inputs.installedIndex.activeGeneration(for: packageID),
            expectedVersion: package.version
        ) {
        case .current:
            return .noOperation(reason: .alreadyCurrent)
        case .protectedNewer:
            return .noOperation(reason: .newerVersionRequiresNewerApp)
        case .updateRequired:
            break
        }
        guard inputs.plan.packages.contains(where: { $0.id == packageID }) else {
            return .noOperation(reason: .alreadyCurrent)
        }

        return try await initiate(
            intent: .explicitSinglePackage,
            preferences: inputs.preferences,
            packages: [package]
        )
    }

    public func requestDownloadAll() async throws -> DownloadControllerRequestResult {
        try requireBootstrap()

        guard activeNewRequestToken == nil else {
            return .installerRejected(reason: .alreadyRunning)
        }
        let requestToken = UUID()
        activeNewRequestToken = requestToken
        defer {
            if activeNewRequestToken == requestToken {
                activeNewRequestToken = nil
            }
        }

        let inputs = try await stabilizedStartInputs()
        guard !inputs.plan.packages.isEmpty else {
            return .noOperation(reason: .nothingPending)
        }
        return try await initiate(
            intent: .explicitDownloadAll,
            preferences: inputs.preferences,
            packages: inputs.plan.packages
        )
    }

    /// Holds the queue after the active package has completed verification and
    /// activation. It does not suspend an Apple-managed transfer.
    public func requestPauseAfterCurrentPackage() async throws {
        try requireBootstrap()
        try await installer.requestPauseAfterCurrentPackage()
    }

    /// Resumes an already journaled queue. New-request network policy does not
    /// govern this operation and cannot be interpreted as transfer control.
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
        _ = try await refreshPlan()
    }

    /// Re-reads the integrity-checked active index and rebuilds the paid plan.
    /// This is the explicit recovery edge after a transient refresh failure.
    @discardableResult
    public func refresh() async throws -> DownloadControllerSnapshot {
        try requireBootstrap()
        _ = try await refreshPlan()
        return currentSnapshot
    }

    /// Discards only an obsolete pending queue. Installed, verified package
    /// generations remain authoritative and are reprojected immediately.
    public func discardStaleQueue() async throws {
        try requireBootstrap()
        try await installer.discardStaleJournal()
        await receiveInstallationState(await installer.state())
        _ = try await refreshPlan()
    }

    private func initiate(
        intent: DownloadInitiationIntent,
        preferences: ExperiencePreferences,
        packages: [ContentPackageSpec]
    ) async throws -> DownloadControllerRequestResult {
        // Index and preferences were stabilized immediately above. This final
        // synchronous read is deliberately last; the following installer actor
        // hop is the unavoidable non-transactional boundary between stores.
        switch requestInitiator.decisionForNewRequest(
            intent: intent,
            preferences: preferences
        ) {
        case .initiateNewRequest:
            do {
                try await installer.start(packages: packages)
                return .started(packageIDs: packages.map(\.id))
            } catch let error as PackageBatchInstallationError {
                return .installerRejected(reason: error)
            }
        case let .doNotInitiateNewRequest(reason):
            return .blocked(reason: reason)
        }
    }

    private func stabilizedStartInputs() async throws -> StartInputs {
        let refreshToken = beginRefresh()
        var prior: StartInputs?

        do {
            for _ in 0 ..< Self.maximumStartInputSnapshots {
                let installedIndex = try await installedIndexProvider()
                let preferences = try await preferencesProvider()
                let inputs = StartInputs(
                    installedIndex: installedIndex,
                    preferences: preferences,
                    plan: try LaunchDownloadPlan(
                        manifest: manifest,
                        installedIndex: installedIndex
                    )
                )
                if inputs == prior {
                    applyRefresh(
                        token: refreshToken,
                        installedIndex: installedIndex,
                        plan: inputs.plan
                    )
                    return inputs
                }
                prior = inputs
            }
            throw DownloadControllerError.startInputsDidNotStabilize
        } catch {
            applyRefreshFailure(token: refreshToken, error: error)
            throw error
        }
    }

    @discardableResult
    private func refreshPlan() async throws -> (InstalledPackageIndex, LaunchDownloadPlan) {
        let refreshToken = beginRefresh()
        let installedIndex: InstalledPackageIndex
        let plan: LaunchDownloadPlan
        do {
            installedIndex = try await installedIndexProvider()
            plan = try LaunchDownloadPlan(
                manifest: manifest,
                installedIndex: installedIndex
            )
        } catch {
            applyRefreshFailure(token: refreshToken, error: error)
            throw error
        }
        applyRefresh(token: refreshToken, installedIndex: installedIndex, plan: plan)
        return (installedIndex, plan)
    }

    private func beginRefresh() -> UInt64 {
        nextRefreshToken &+= 1
        latestStartedRefreshToken = nextRefreshToken
        return nextRefreshToken
    }

    private func applyRefresh(
        token: UInt64,
        installedIndex: InstalledPackageIndex,
        plan: LaunchDownloadPlan
    ) {
        guard token == latestStartedRefreshToken else { return }
        latestInstalledIndex = installedIndex
        latestPlan = plan
        publish(makeSnapshot(
            bootstrapState: .ready,
            installedIndex: installedIndex,
            plan: plan,
            installationState: currentSnapshot.installationState,
            transferState: currentSnapshot.systemTransferState,
            refreshFailure: nil
        ))
    }

    private func applyRefreshFailure(token: UInt64, error: any Error) {
        guard token == latestStartedRefreshToken else { return }
        publish(DownloadControllerSnapshot(
            bootstrapState: currentSnapshot.bootstrapState,
            currentInstalledPackageIDs: currentSnapshot.currentInstalledPackageIDs,
            pendingPaidPackageIDs: currentSnapshot.pendingPaidPackageIDs,
            outdatedPackages: currentSnapshot.outdatedPackages,
            protectedNewerPackages: currentSnapshot.protectedNewerPackages,
            remainingMaximumInstalledBytes: currentSnapshot.remainingMaximumInstalledBytes,
            installationState: currentSnapshot.installationState,
            systemTransferState: normalizedTransferState(
                currentSnapshot.systemTransferState,
                for: currentSnapshot.installationState
            ),
            refreshFailure: PackageBatchFailure(error)
        ))
    }

    private func beginObservingInstallerIfNeeded() async {
        guard stateObserverTask == nil, transferObserverTask == nil else { return }
        let stateUpdates = await installer.stateUpdates()
        let transferUpdates = await installer.systemTransferStateUpdates()

        stateObserverTask = Task { [weak self] in
            for await state in stateUpdates {
                guard !Task.isCancelled else { return }
                await self?.receiveInstallationState(state)
            }
        }
        transferObserverTask = Task { [weak self] in
            for await state in transferUpdates {
                guard !Task.isCancelled else { return }
                await self?.receiveTransferState(state)
            }
        }
    }

    private func receiveInstallationState(_ state: PackageBatchInstallationState) async {
        publish(DownloadControllerSnapshot(
            bootstrapState: currentSnapshot.bootstrapState,
            currentInstalledPackageIDs: currentSnapshot.currentInstalledPackageIDs,
            pendingPaidPackageIDs: currentSnapshot.pendingPaidPackageIDs,
            outdatedPackages: currentSnapshot.outdatedPackages,
            protectedNewerPackages: currentSnapshot.protectedNewerPackages,
            remainingMaximumInstalledBytes: currentSnapshot.remainingMaximumInstalledBytes,
            installationState: state,
            systemTransferState: normalizedTransferState(
                currentSnapshot.systemTransferState,
                for: state
            ),
            refreshFailure: currentSnapshot.refreshFailure
        ))

        guard shouldRefreshIndex(after: state) else { return }
        do {
            _ = try await refreshPlan()
        } catch {
            // `refreshPlan` has already preserved the last verified index and
            // published the machine-readable failure for this newest token.
        }
    }

    private func receiveTransferState(_ state: PackageSystemTransferState) {
        publish(DownloadControllerSnapshot(
            bootstrapState: currentSnapshot.bootstrapState,
            currentInstalledPackageIDs: currentSnapshot.currentInstalledPackageIDs,
            pendingPaidPackageIDs: currentSnapshot.pendingPaidPackageIDs,
            outdatedPackages: currentSnapshot.outdatedPackages,
            protectedNewerPackages: currentSnapshot.protectedNewerPackages,
            remainingMaximumInstalledBytes: currentSnapshot.remainingMaximumInstalledBytes,
            installationState: currentSnapshot.installationState,
            systemTransferState: normalizedTransferState(
                state,
                for: currentSnapshot.installationState
            ),
            refreshFailure: currentSnapshot.refreshFailure
        ))
    }

    private func shouldRefreshIndex(after state: PackageBatchInstallationState) -> Bool {
        switch state {
        case .completed, .failed, .paused, .awaitingExplicitRestore:
            true
        case let .starting(_, completedPackageIDs, _),
             let .installing(_, completedPackageIDs, _),
             let .pausingAfterCurrent(_, completedPackageIDs, _):
            !completedPackageIDs.isEmpty
        case .idle, .staleJournal:
            false
        }
    }

    private func makeSnapshot(
        bootstrapState: DownloadControllerBootstrapState,
        installedIndex: InstalledPackageIndex,
        plan: LaunchDownloadPlan,
        installationState: PackageBatchInstallationState,
        transferState: PackageSystemTransferState,
        refreshFailure: PackageBatchFailure? = nil
    ) -> DownloadControllerSnapshot {
        let packageByID = Dictionary(
            uniqueKeysWithValues: manifest.packages.map { ($0.id, $0) }
        )
        let currentInstalledPackageIDs = LaunchContent.packageIDsInDeliveryOrder.filter { packageID in
            guard let expected = packageByID[packageID],
                  let active = installedIndex.activeGeneration(for: packageID) else {
                return false
            }
            return active.packageVersion == expected.version
        }
        return DownloadControllerSnapshot(
            bootstrapState: bootstrapState,
            currentInstalledPackageIDs: currentInstalledPackageIDs,
            pendingPaidPackageIDs: plan.packages.map(\.id),
            outdatedPackages: plan.outdatedPackages,
            protectedNewerPackages: plan.protectedNewerPackages,
            remainingMaximumInstalledBytes: plan.remainingMaximumInstalledBytes,
            installationState: installationState,
            systemTransferState: normalizedTransferState(
                transferState,
                for: installationState
            ),
            refreshFailure: refreshFailure
        )
    }

    private func normalizedTransferState(
        _ transferState: PackageSystemTransferState,
        for installationState: PackageBatchInstallationState
    ) -> PackageSystemTransferState {
        let activePackageID: PackageID
        switch installationState {
        case let .installing(packageID, _, _),
             let .pausingAfterCurrent(packageID, _, _):
            activePackageID = packageID
        case .idle, .starting, .paused, .awaitingExplicitRestore,
             .staleJournal, .completed, .failed:
            return .idle
        }

        switch transferState {
        case .idle:
            return .idle
        case let .began(packageID, _),
             let .paused(packageID),
             let .downloading(packageID, _, _),
             let .finished(packageID),
             let .failed(packageID, _):
            return packageID == activePackageID ? transferState : .idle
        }
    }

    private func requireBootstrap() throws {
        guard currentSnapshot.bootstrapState == .ready,
              latestInstalledIndex != nil,
              latestPlan != nil else {
            throw DownloadControllerError.bootstrapRequired
        }
    }

    private func publish(_ snapshot: DownloadControllerSnapshot) {
        guard snapshot != currentSnapshot else { return }
        currentSnapshot = snapshot
        for observer in observers.values {
            observer.yield(snapshot)
        }
    }

    private func removeObserver(_ observerID: UUID) {
        observers.removeValue(forKey: observerID)
    }
}
