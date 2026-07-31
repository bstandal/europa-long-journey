import ContentKit
import Foundation

public struct PackageInstallationContext: Sendable {
    public let trustedPublicKeys: [String: Data]
    public let supportedSchema: SchemaVersion
    public let runtimeVersion: SchemaVersion
    public let requireLatestVersion: Bool

    public init(
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion,
        requireLatestVersion: Bool = true
    ) {
        self.trustedPublicKeys = trustedPublicKeys
        self.supportedSchema = supportedSchema
        self.runtimeVersion = runtimeVersion
        self.requireLatestVersion = requireLatestVersion
    }
}

public struct PackageBatchFailure: Codable, Equatable, Sendable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }

    init(_ error: any Error) {
        let bridged = error as NSError
        domain = bridged.domain
        code = bridged.code
    }

    /// Covers both the proactive staging-capacity gate and a filesystem race
    /// where another process consumes space after that gate but before the
    /// bounded copy completes.
    public var isInsufficientStorage: Bool {
        if domain == ManagedPackageMaterializationError.errorDomain,
           code == ManagedPackageMaterializationError.insufficientStorageErrorCode {
            return true
        }
        return domain == NSPOSIXErrorDomain
            && code == Int(POSIXErrorCode.ENOSPC.rawValue)
    }
}

public enum PackageSystemTransferState: Equatable, Sendable {
    case idle
    case began(packageID: PackageID, returnedAfterObservedPause: Bool)
    case paused(packageID: PackageID)
    case downloading(
        packageID: PackageID,
        completedUnitCount: Int64,
        totalUnitCount: Int64
    )
    case finished(packageID: PackageID)
    case failed(packageID: PackageID, failure: PackageBatchFailure)
}

public enum PackageBatchInstallationState: Equatable, Sendable {
    case idle
    case starting(
        packageID: PackageID,
        completedPackageIDs: [PackageID],
        totalPackageCount: Int
    )
    case installing(
        packageID: PackageID,
        completedPackageIDs: [PackageID],
        totalPackageCount: Int
    )
    case pausingAfterCurrent(
        packageID: PackageID,
        completedPackageIDs: [PackageID],
        totalPackageCount: Int
    )
    case paused(
        nextPackageID: PackageID?,
        completedPackageIDs: [PackageID],
        totalPackageCount: Int
    )
    case awaitingExplicitRestore(
        nextPackageID: PackageID,
        completedPackageIDs: [PackageID],
        totalPackageCount: Int
    )
    case staleJournal(reason: PackageBatchStaleJournalReason)
    case completed(installedPackageIDs: [PackageID])
    case failed(
        packageID: PackageID,
        completedPackageIDs: [PackageID],
        failure: PackageBatchFailure
    )
}

public enum PackageBatchStaleJournalReason: Equatable, Sendable {
    case unknownOrRemovedPackageIDs([PackageID])
    case nonCanonicalPackageOrder([PackageID])
    /// Queue intent references active generations newer than this runtime's
    /// signed package contract. The journal is preserved and cannot be retired
    /// by this runtime.
    case protectedNewerPackageVersions([PackageID])
    /// The durable queue was written by a newer schema. Its bytes remain
    /// untouched until a compatible app can interpret them.
    case requiresNewerApp(formatVersion: Int)
    case corruptJournal
}

public enum PackageBatchRestorePolicy: Equatable, Sendable {
    /// Reconstructs the queue but never restarts an interrupted running intent.
    case requireExplicitResume
    /// Restarts only a journal whose prior intent was running. A user-paused or
    /// failed journal remains paused or failed.
    case resumeRunning
}

public enum PackageBatchInstallationError: Error, Equatable, Sendable {
    case alreadyRunning
    case unresolvedQueue
    case duplicatePackageID(PackageID)
    case noFailedPackage
    case noStaleJournal
    case newerPackageVersionRequiresNewerApp
    case journalUnavailable
}

/// Installs a caller-supplied package order one verified package at a time.
///
/// Queue pause is deliberately distinct from Apple's system transfer state. A
/// queue pause lets the active transfer, verification and atomic activation
/// finish, then holds before another package starts. It never claims a byte-
/// exact pause of an Apple-managed transfer.
public actor PackageBatchInstaller {
    public typealias InstallOperation = @Sendable (ContentPackageSpec) async throws -> ActivatedPackage
    public typealias TransferUpdates = @Sendable (PackageID) -> AsyncStream<AssetPackTransferStatus>

    private struct RuntimeQueue: Sendable {
        var packages: [ContentPackageSpec]
        var completedPackageIDs: [PackageID]
        var failedPackageID: PackageID?
        var failure: PackageBatchFailure?

        var pendingPackages: [ContentPackageSpec] {
            Array(packages.dropFirst(completedPackageIDs.count))
        }

        var nextPackage: ContentPackageSpec? { pendingPackages.first }
    }

    private let installOperation: InstallOperation
    private let transferUpdates: TransferUpdates?
    private let journalStore: PackageBatchQueueJournalStore?

    private var currentState: PackageBatchInstallationState = .idle
    private var currentSystemTransferState: PackageSystemTransferState = .idle
    private var runTask: Task<Void, Never>?
    private var transferTask: Task<Void, Never>?
    private var activeTransferToken: UUID?
    private var runtimeQueue: RuntimeQueue?
    private var pauseRequested = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var observers: [UUID: AsyncStream<PackageBatchInstallationState>.Continuation] = [:]
    private var transferObservers: [UUID: AsyncStream<PackageSystemTransferState>.Continuation] = [:]

    public init(
        installOperation: @escaping InstallOperation,
        transferUpdates: TransferUpdates? = nil,
        journalStore: PackageBatchQueueJournalStore? = nil
    ) {
        self.installOperation = installOperation
        self.transferUpdates = transferUpdates
        self.journalStore = journalStore
    }

    public init(
        materializer: ManagedPackageMaterializer,
        context: PackageInstallationContext,
        journalStore: PackageBatchQueueJournalStore? = nil
    ) {
        installOperation = { package in
            try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: context.trustedPublicKeys,
                supportedSchema: context.supportedSchema,
                runtimeVersion: context.runtimeVersion,
                requireLatestVersion: context.requireLatestVersion
            )
        }
        transferUpdates = { packageID in
            materializer.statusUpdates(for: packageID)
        }
        self.journalStore = journalStore
    }

    public func state() -> PackageBatchInstallationState {
        currentState
    }

    public func systemTransferState() -> PackageSystemTransferState {
        currentSystemTransferState
    }

    public func stateUpdates() -> AsyncStream<PackageBatchInstallationState> {
        let observerID = UUID()
        let pair = AsyncStream<PackageBatchInstallationState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        observers[observerID] = pair.continuation
        pair.continuation.yield(currentState)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(observerID) }
        }
        return pair.stream
    }

    public func systemTransferStateUpdates() -> AsyncStream<PackageSystemTransferState> {
        let observerID = UUID()
        let pair = AsyncStream<PackageSystemTransferState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        transferObservers[observerID] = pair.continuation
        pair.continuation.yield(currentSystemTransferState)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeTransferObserver(observerID) }
        }
        return pair.stream
    }

    public func start(packages: [ContentPackageSpec]) throws {
        guard runTask == nil else { throw PackageBatchInstallationError.alreadyRunning }
        guard !hasUnresolvedQueue else { throw PackageBatchInstallationError.unresolvedQueue }
        if let journalStore,
           let priorJournal = try journalStore.load(),
           priorJournal.intent != .completed {
            throw PackageBatchInstallationError.unresolvedQueue
        }
        try Self.validateUniquePackageIDs(packages)

        let queue = RuntimeQueue(
            packages: packages,
            completedPackageIDs: [],
            failedPackageID: nil,
            failure: nil
        )
        runtimeQueue = queue
        pauseRequested = false
        pauseContinuation = nil

        do {
            if packages.isEmpty {
                try persist(intent: .completed)
                publish(.completed(installedPackageIDs: []))
            } else {
                try persist(intent: .running)
                startWorker()
            }
        } catch {
            runtimeQueue = nil
            throw error
        }
    }

    /// Accepted only while an installation operation is actually active.
    public func requestPauseAfterCurrentPackage() throws {
        guard case let .installing(packageID, completed, total) = currentState,
              runtimeQueue != nil else {
            return
        }
        try persist(intent: .paused)
        pauseRequested = true
        publish(.pausingAfterCurrent(
            packageID: packageID,
            completedPackageIDs: completed,
            totalPackageCount: total
        ))
    }

    public func resume() throws {
        switch currentState {
        case let .pausingAfterCurrent(packageID, completed, total):
            try persist(intent: .running)
            pauseRequested = false
            publish(.installing(
                packageID: packageID,
                completedPackageIDs: completed,
                totalPackageCount: total
            ))

        case .paused, .awaitingExplicitRestore:
            try persist(intent: .running)
            pauseRequested = false
            if let continuation = pauseContinuation {
                pauseContinuation = nil
                continuation.resume()
            } else {
                startWorker()
            }

        default:
            return
        }
    }

    public func retryFailed() throws {
        guard case .failed = currentState,
              var queue = runtimeQueue,
              queue.failedPackageID != nil else {
            throw PackageBatchInstallationError.noFailedPackage
        }
        queue.failedPackageID = nil
        queue.failure = nil
        runtimeQueue = queue
        pauseRequested = false
        do {
            try persist(intent: .running)
            startWorker()
        } catch {
            runtimeQueue?.failedPackageID = queue.nextPackage?.id
            runtimeQueue?.failure = PackageBatchFailure(error)
            throw error
        }
    }

    public func removeFailed() throws {
        guard case .failed = currentState,
              var queue = runtimeQueue,
              let failedPackageID = queue.failedPackageID else {
            throw PackageBatchInstallationError.noFailedPackage
        }
        let priorQueue = queue
        queue.packages.removeAll { $0.id == failedPackageID }
        queue.failedPackageID = nil
        queue.failure = nil
        runtimeQueue = queue
        pauseRequested = false

        do {
            if queue.nextPackage == nil {
                try persist(intent: .completed)
                publish(.completed(installedPackageIDs: queue.completedPackageIDs))
            } else {
                try persist(intent: .running)
                startWorker()
            }
        } catch {
            runtimeQueue = priorQueue
            throw error
        }
    }

    /// Replaces an obsolete, non-runnable queue with an empty completed
    /// journal. Installed package generations and the active package index are
    /// untouched; only the user's pending application queue is discarded.
    public func discardStaleJournal() throws {
        guard case let .staleJournal(reason) = currentState else {
            throw PackageBatchInstallationError.noStaleJournal
        }
        if case .protectedNewerPackageVersions = reason {
            throw PackageBatchInstallationError.newerPackageVersionRequiresNewerApp
        }
        if case .requiresNewerApp = reason {
            throw PackageBatchInstallationError.newerPackageVersionRequiresNewerApp
        }
        guard let journalStore else {
            throw PackageBatchInstallationError.journalUnavailable
        }

        try journalStore.retireCurrentQueue()
        runtimeQueue = nil
        pauseRequested = false
        pauseContinuation = nil
        publishTransfer(.idle)
        publish(.idle)
    }

    /// Restores journaled package-ID intent against today's canonical package
    /// contract and the active, integrity-checked package index.
    ///
    /// A safe ID subsequence is migrated to today's complete package specs
    /// before it can be resumed. Unknown, removed or reordered IDs remain in
    /// the durable journal and surface as an unresolved machine state.
    public func restoreQueue(
        installedIndex: InstalledPackageIndex,
        canonicalPackages: [ContentPackageSpec],
        policy: PackageBatchRestorePolicy = .requireExplicitResume
    ) throws {
        guard runTask == nil else { throw PackageBatchInstallationError.alreadyRunning }
        guard !hasUnresolvedQueue else { throw PackageBatchInstallationError.unresolvedQueue }
        guard let journalStore else { throw PackageBatchInstallationError.journalUnavailable }
        try installedIndex.validate()
        let journal: PackageBatchQueueJournal
        do {
            guard let loaded = try journalStore.load() else { return }
            journal = loaded
        } catch PackageBatchQueueJournalError.corruptJournal {
            runtimeQueue = nil
            publishTransfer(.idle)
            publish(.staleJournal(reason: .corruptJournal))
            return
        } catch let PackageBatchQueueJournalError.requiresNewerApp(formatVersion) {
            runtimeQueue = nil
            publishTransfer(.idle)
            publish(.staleJournal(
                reason: .requiresNewerApp(formatVersion: formatVersion)
            ))
            return
        }
        try journal.validate()
        try Self.validateUniquePackageIDs(canonicalPackages)

        let canonicalIDs = canonicalPackages.map(\.id)
        let journalIDs = journal.packages.map(\.id)
        let canonicalPackageByID = Dictionary(
            uniqueKeysWithValues: canonicalPackages.map { ($0.id, $0) }
        )
        let unknownPackageIDs = journalIDs.filter { canonicalPackageByID[$0] == nil }
        guard unknownPackageIDs.isEmpty else {
            runtimeQueue = nil
            publishTransfer(.idle)
            publish(.staleJournal(
                reason: .unknownOrRemovedPackageIDs(unknownPackageIDs)
            ))
            return
        }

        let canonicalPositionByID = Dictionary(
            uniqueKeysWithValues: canonicalIDs.enumerated().map { ($0.element, $0.offset) }
        )
        let journalPositions = journalIDs.compactMap { canonicalPositionByID[$0] }
        guard zip(journalPositions, journalPositions.dropFirst())
            .allSatisfy({ left, right in left < right }) else {
            runtimeQueue = nil
            publishTransfer(.idle)
            publish(.staleJournal(reason: .nonCanonicalPackageOrder(journalIDs)))
            return
        }

        // IDs carry the user's queue intent. Every other field comes from the
        // current signed launch contract so an old version/spec can never run.
        let reconciledPackages = journalIDs.compactMap { canonicalPackageByID[$0] }
        let protectedNewerPackageIDs = reconciledPackages.compactMap { package -> PackageID? in
            guard case .protectedNewer = InstalledPackageVersionAuthority(
                activeGeneration: installedIndex.activeGeneration(for: package.id),
                expectedVersion: package.version
            ) else {
                return nil
            }
            return package.id
        }
        guard protectedNewerPackageIDs.isEmpty else {
            runtimeQueue = nil
            publishTransfer(.idle)
            publish(.staleJournal(
                reason: .protectedNewerPackageVersions(protectedNewerPackageIDs)
            ))
            return
        }
        let migratedToCurrentSpecs = reconciledPackages != journal.packages

        var completed: [PackageID] = []
        for package in reconciledPackages {
            guard InstalledPackageVersionAuthority(
                activeGeneration: installedIndex.activeGeneration(for: package.id),
                expectedVersion: package.version
            ) == .current else {
                break
            }
            completed.append(package.id)
        }

        var queue = RuntimeQueue(
            packages: reconciledPackages,
            completedPackageIDs: completed,
            failedPackageID: nil,
            failure: nil
        )
        runtimeQueue = queue
        pauseRequested = false
        pauseContinuation = nil

        guard let next = queue.nextPackage else {
            try persist(intent: .completed)
            publish(.completed(installedPackageIDs: completed))
            return
        }

        switch journal.intent {
        case .paused:
            pauseRequested = true
            try persist(intent: .paused)
            publish(.paused(
                nextPackageID: next.id,
                completedPackageIDs: completed,
                totalPackageCount: queue.packages.count
            ))

        case .failed:
            if journal.failedPackageID == next.id, let failure = journal.failure {
                queue.failedPackageID = next.id
                queue.failure = failure
                runtimeQueue = queue
                try persist(intent: .failed)
                publish(.failed(
                    packageID: next.id,
                    completedPackageIDs: completed,
                    failure: failure
                ))
            } else {
                try persist(intent: .running)
                publish(.awaitingExplicitRestore(
                    nextPackageID: next.id,
                    completedPackageIDs: completed,
                    totalPackageCount: queue.packages.count
                ))
            }

        case .running:
            try persist(intent: .running)
            if policy == .resumeRunning, !migratedToCurrentSpecs {
                startWorker()
            } else {
                publish(.awaitingExplicitRestore(
                    nextPackageID: next.id,
                    completedPackageIDs: completed,
                    totalPackageCount: queue.packages.count
                ))
            }

        case .completed:
            // The journal claimed completion, but the installed index no longer
            // has a current contiguous prefix. Never download implicitly.
            try persist(intent: .running)
            publish(.awaitingExplicitRestore(
                nextPackageID: next.id,
                completedPackageIDs: completed,
                totalPackageCount: queue.packages.count
            ))
        }
    }

    private var hasUnresolvedQueue: Bool {
        switch currentState {
        case .starting, .installing, .pausingAfterCurrent, .paused,
             .awaitingExplicitRestore, .staleJournal, .failed:
            true
        case .idle, .completed:
            false
        }
    }

    private static func validateUniquePackageIDs(_ packages: [ContentPackageSpec]) throws {
        var packageIDs = Set<PackageID>()
        for package in packages where !packageIDs.insert(package.id).inserted {
            throw PackageBatchInstallationError.duplicatePackageID(package.id)
        }
    }

    private func startWorker() {
        guard runTask == nil,
              let queue = runtimeQueue,
              let next = queue.nextPackage else {
            return
        }
        publish(.starting(
            packageID: next.id,
            completedPackageIDs: queue.completedPackageIDs,
            totalPackageCount: queue.packages.count
        ))
        publishTransfer(.idle)
        let operation = installOperation
        runTask = Task { [weak self] in
            await self?.run(operation: operation)
        }
    }

    private func run(operation: InstallOperation) async {
        var isFirstPackage = true
        while let package = runtimeQueue?.nextPackage {
            if pauseRequested {
                await waitIfPaused(nextPackageID: package.id)
            }
            guard let queue = runtimeQueue else { return }
            if !isFirstPackage {
                publish(.starting(
                    packageID: package.id,
                    completedPackageIDs: queue.completedPackageIDs,
                    totalPackageCount: queue.packages.count
                ))
            }
            publish(.installing(
                packageID: package.id,
                completedPackageIDs: queue.completedPackageIDs,
                totalPackageCount: queue.packages.count
            ))

            beginTransferMonitoring(for: package.id)
            do {
                _ = try await operation(package)
            } catch {
                endTransferMonitoring()
                fail(packageID: package.id, error: error)
                return
            }
            endTransferMonitoring()

            guard var updatedQueue = runtimeQueue else { return }
            updatedQueue.completedPackageIDs.append(package.id)
            runtimeQueue = updatedQueue

            if updatedQueue.nextPackage == nil {
                pauseRequested = false
                pauseContinuation = nil
                do {
                    try persist(intent: .completed)
                } catch {
                    // The active index is authoritative. A stale running journal
                    // is reconciled to this completed prefix on next launch.
                }
                publish(.completed(installedPackageIDs: updatedQueue.completedPackageIDs))
                runTask = nil
                return
            }

            do {
                try persist(intent: pauseRequested ? .paused : .running)
            } catch {
                haltAfterJournalFailure(error)
                return
            }
            isFirstPackage = false
        }
    }

    private func waitIfPaused(nextPackageID: PackageID) async {
        guard pauseRequested, let queue = runtimeQueue else { return }
        publish(.paused(
            nextPackageID: nextPackageID,
            completedPackageIDs: queue.completedPackageIDs,
            totalPackageCount: queue.packages.count
        ))
        await withCheckedContinuation { continuation in
            pauseContinuation = continuation
        }
    }

    private func fail(packageID: PackageID, error: any Error) {
        guard var queue = runtimeQueue else { return }
        let failure = PackageBatchFailure(error)
        queue.failedPackageID = packageID
        queue.failure = failure
        runtimeQueue = queue
        pauseRequested = false
        pauseContinuation = nil
        try? persist(intent: .failed)
        publish(.failed(
            packageID: packageID,
            completedPackageIDs: queue.completedPackageIDs,
            failure: failure
        ))
        runTask = nil
    }

    private func haltAfterJournalFailure(_ error: any Error) {
        guard var queue = runtimeQueue, let next = queue.nextPackage else {
            runTask = nil
            return
        }
        let failure = PackageBatchFailure(error)
        queue.failedPackageID = next.id
        queue.failure = failure
        runtimeQueue = queue
        pauseRequested = false
        pauseContinuation = nil
        publish(.failed(
            packageID: next.id,
            completedPackageIDs: queue.completedPackageIDs,
            failure: failure
        ))
        runTask = nil
    }

    private func persist(intent: PackageBatchQueueIntent) throws {
        guard let journalStore, let queue = runtimeQueue else { return }
        let journal = PackageBatchQueueJournal(
            intent: intent,
            packages: queue.packages,
            completedPackageIDs: queue.completedPackageIDs,
            failedPackageID: intent == .failed ? queue.failedPackageID : nil,
            failure: intent == .failed ? queue.failure : nil
        )
        try journalStore.save(journal)
    }

    private func beginTransferMonitoring(for packageID: PackageID) {
        transferTask?.cancel()
        let token = UUID()
        activeTransferToken = token
        publishTransfer(.idle)
        guard let transferUpdates else {
            transferTask = nil
            return
        }

        // Creating the stream subscribes before the install operation calls
        // ensureLocalAvailability. Buffered updates cannot race past setup.
        let updates = transferUpdates(packageID)
        transferTask = Task { [weak self] in
            for await update in updates {
                guard !Task.isCancelled else { return }
                await self?.receiveTransferUpdate(
                    update,
                    packageID: packageID,
                    token: token
                )
            }
        }
    }

    private func endTransferMonitoring() {
        activeTransferToken = nil
        transferTask?.cancel()
        transferTask = nil
        publishTransfer(.idle)
    }

    private func receiveTransferUpdate(
        _ update: AssetPackTransferStatus,
        packageID: PackageID,
        token: UUID
    ) {
        guard token == activeTransferToken else { return }
        switch update {
        case .began:
            let returnedAfterPause: Bool
            if case let .paused(observedPackageID) = currentSystemTransferState,
               observedPackageID == packageID {
                returnedAfterPause = true
            } else {
                returnedAfterPause = false
            }
            publishTransfer(.began(
                packageID: packageID,
                returnedAfterObservedPause: returnedAfterPause
            ))
        case .paused:
            publishTransfer(.paused(packageID: packageID))
        case let .downloading(completedUnitCount, totalUnitCount):
            publishTransfer(.downloading(
                packageID: packageID,
                completedUnitCount: completedUnitCount,
                totalUnitCount: totalUnitCount
            ))
        case .finished:
            publishTransfer(.finished(packageID: packageID))
        case let .failed(domain, code):
            publishTransfer(.failed(
                packageID: packageID,
                failure: PackageBatchFailure(domain: domain, code: code)
            ))
        }
    }

    private func publish(_ state: PackageBatchInstallationState) {
        currentState = state
        for observer in observers.values {
            observer.yield(state)
        }
    }

    private func publishTransfer(_ state: PackageSystemTransferState) {
        currentSystemTransferState = state
        for observer in transferObservers.values {
            observer.yield(state)
        }
    }

    private func removeObserver(_ observerID: UUID) {
        observers.removeValue(forKey: observerID)
    }

    private func removeTransferObserver(_ observerID: UUID) {
        transferObservers.removeValue(forKey: observerID)
    }
}
