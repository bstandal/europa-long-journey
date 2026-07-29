import ContentDelivery
import ContentKit
import Foundation

public enum VerifiedJourneyRepositoryAuthorityError: Error, Equatable, Sendable {
    case downloadedEssentialPackage(PackageID)
    case unknownPackage(PackageID)
}

/// Immutable authority captured at the same verified-content boundary which
/// either exposed an asset root or rejected an installed generation. A later
/// integrity report must present this exact snapshot/generation identity;
/// package ID alone is never mutation authority.
public struct PackageAssetFailureAuthority: Equatable, Sendable {
    public let snapshotRevision: UInt64
    public let packageID: PackageID
    public let installedGeneration: InstalledPackageGeneration?
    public let manifestDigest: String

    public init(
        snapshotRevision: UInt64,
        packageID: PackageID,
        installedGeneration: InstalledPackageGeneration?,
        manifestDigest: String
    ) {
        self.snapshotRevision = snapshotRevision
        self.packageID = packageID
        self.installedGeneration = installedGeneration
        self.manifestDigest = manifestDigest
    }
}

public enum AssetFailureReportOutcome: Equatable, Sendable {
    case ignoredStaleReport
    case ignoredDurableAuthority
    case essentialRequiresReinstallOrUpdate
    case rolledBack(to: InstalledPackageGeneration)
    case quarantined(InstalledPackageGeneration)
}

/// One immutable runtime truth shared by chapter lookup, package-root asset
/// resolution and the download plan. Only roots resolved by PackageActivator
/// and runtime-admitted again in this process can appear here.
public struct VerifiedJourneyContentSnapshot: Sendable {
    public let revision: UInt64
    public let repository: ContentRepository
    public let reconciledInstalledIndex: InstalledPackageIndex
    public let packageRootURLs: [PackageID: URL]
    /// Verifier-created package values for the exact roots in this snapshot.
    /// Essential and downloaded content therefore cross one asset-inventory
    /// boundary before Metal or audio can resolve package-relative files.
    public let verifiedPackagesByID: [PackageID: VerifiedContentPackage]
    public let repairedPackageIDs: [PackageID]
    public let unavailableCurrentPackageIDs: [PackageID]
    /// Exact durable generations omitted from runtime content after package
    /// verification failed. The public ID projection remains available for
    /// existing consumers; only this generation-bound map can authorize a
    /// quarantine or rollback.
    public let unavailableCurrentGenerationsByPackageID: [
        PackageID: InstalledPackageGeneration
    ]

    public init(
        revision: UInt64,
        repository: ContentRepository,
        reconciledInstalledIndex: InstalledPackageIndex,
        packageRootURLs: [PackageID: URL],
        verifiedPackagesByID: [PackageID: VerifiedContentPackage],
        repairedPackageIDs: [PackageID] = [],
        unavailableCurrentPackageIDs: [PackageID] = [],
        unavailableCurrentGenerationsByPackageID: [
            PackageID: InstalledPackageGeneration
        ] = [:]
    ) {
        self.revision = revision
        self.repository = repository
        self.reconciledInstalledIndex = reconciledInstalledIndex
        self.packageRootURLs = packageRootURLs
        self.verifiedPackagesByID = verifiedPackagesByID
        self.repairedPackageIDs = repairedPackageIDs
        self.unavailableCurrentGenerationsByPackageID =
            unavailableCurrentGenerationsByPackageID
        self.unavailableCurrentPackageIDs = Set(unavailableCurrentPackageIDs)
            .union(unavailableCurrentGenerationsByPackageID.keys)
            .sorted()
    }

    public func packageRootURL(for packageID: PackageID) -> URL? {
        packageRootURLs[packageID]
    }

    public func verifiedPackage(
        for packageID: PackageID
    ) -> VerifiedContentPackage? {
        verifiedPackagesByID[packageID]
    }

    /// Captures the exact authority a lazy asset resolver must return if a
    /// signed byte digest later fails. Essential content deliberately carries
    /// no mutable installed generation.
    public func assetFailureAuthority(
        for packageID: PackageID
    ) -> PackageAssetFailureAuthority? {
        guard let verified = verifiedPackagesByID[packageID] else { return nil }
        if packageID == LaunchContent.essentialPackageID {
            return PackageAssetFailureAuthority(
                snapshotRevision: revision,
                packageID: packageID,
                installedGeneration: nil,
                manifestDigest: verified.manifest.manifestDigest
            )
        }
        guard let generation = reconciledInstalledIndex.activeGeneration(
            for: packageID
        ), generation.manifestDigest == verified.manifest.manifestDigest else {
            return nil
        }
        return PackageAssetFailureAuthority(
            snapshotRevision: revision,
            packageID: packageID,
            installedGeneration: generation,
            manifestDigest: verified.manifest.manifestDigest
        )
    }

    /// Returns mutation authority only for the exact installed generation
    /// which this snapshot rejected. A newer activation necessarily produces
    /// a different token and makes the old report a stale no-op.
    public func unavailablePackageFailureAuthority(
        for packageID: PackageID
    ) -> PackageAssetFailureAuthority? {
        guard packageID != LaunchContent.essentialPackageID,
              unavailableCurrentPackageIDs.contains(packageID),
              let generation =
                unavailableCurrentGenerationsByPackageID[packageID],
              generation.packageID == packageID,
              verifiedPackagesByID[packageID] == nil,
              packageRootURLs[packageID] == nil,
              reconciledInstalledIndex.activeGeneration(
                  for: packageID
              ) == nil else {
            return nil
        }
        return PackageAssetFailureAuthority(
            snapshotRevision: revision,
            packageID: packageID,
            installedGeneration: generation,
            manifestDigest: generation.manifestDigest
        )
    }
}

/// Rebuilds the Journey's paid-content repository from durable activation
/// authority. A bad package is omitted without taking down the code-signed
/// essential package or another independently valid paid package.
public actor VerifiedJourneyRepositoryAuthority {
    public typealias AuthorityProvider = @Sendable () async throws
        -> RetainedPackageAuthority
    public typealias ExactRollback = @Sendable (
        PackageID,
        InstalledPackageGeneration,
        InstalledPackageGeneration
    ) async throws -> ExactPackageRollbackResult
    public typealias Deactivate = @Sendable (
        PackageID,
        InstalledPackageGeneration
    ) async throws -> PackageDeactivationResult

    private struct InFlightRefresh {
        let id: UUID
        let task: Task<VerifiedJourneyContentSnapshot, any Error>
    }

    private struct PredecessorVerification {
        let generation: InstalledPackageGeneration
        let package: ActivatedPackage
        let verified: Task<VerifiedContentPackage?, Never>
    }

    private enum DurableAuthorityMatch {
        case matching(RetainedPackageAuthority)
        case stale
        case unavailable
    }

    public nonisolated let initialSnapshot: VerifiedJourneyContentSnapshot

    private let manifest: CollectionManifest
    private let assembler: VerifiedContentRepositoryAssembler
    private let bundledEssentialPackage: VerifiedContentPackage
    private let bundledEssentialRootURL: URL
    private let trustedPublicKeys: [String: Data]
    private let authorityProvider: AuthorityProvider
    private let exactRollback: ExactRollback
    private let deactivate: Deactivate

    private var currentSnapshot: VerifiedJourneyContentSnapshot
    private var inFlightRefresh: InFlightRefresh?
    private var observers: [
        UUID: AsyncStream<VerifiedJourneyContentSnapshot>.Continuation
    ] = [:]

    public init(
        bundledEssentialPackage: VerifiedContentPackage,
        bundledEssentialRootURL: URL,
        trustedPublicKeys: [String: Data],
        manifest: CollectionManifest = LaunchContent.collectionManifest,
        supportedSchema: SchemaVersion = SchemaVersion(major: 1),
        runtimeVersion: SchemaVersion = SchemaVersion(major: 1),
        authorityProvider: @escaping AuthorityProvider,
        exactRollback: @escaping ExactRollback = { _, _, _ in .staleAuthority },
        deactivate: @escaping Deactivate = { _, _ in .staleAuthority }
    ) throws {
        let assembler = VerifiedContentRepositoryAssembler(
            manifest: manifest,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion
        )
        let essentialRepository = try assembler.assemble(
            verifiedBundledEssentialPackage: bundledEssentialPackage,
            verifiedPackages: []
        )
        let initial = VerifiedJourneyContentSnapshot(
            revision: 0,
            repository: essentialRepository,
            reconciledInstalledIndex: .empty,
            packageRootURLs: [
                LaunchContent.essentialPackageID: bundledEssentialRootURL.standardizedFileURL,
            ],
            verifiedPackagesByID: [
                LaunchContent.essentialPackageID: bundledEssentialPackage,
            ]
        )

        self.manifest = manifest
        self.assembler = assembler
        self.bundledEssentialPackage = bundledEssentialPackage
        self.bundledEssentialRootURL = bundledEssentialRootURL.standardizedFileURL
        self.trustedPublicKeys = trustedPublicKeys
        self.authorityProvider = authorityProvider
        self.exactRollback = exactRollback
        self.deactivate = deactivate
        initialSnapshot = initial
        currentSnapshot = initial
    }

    public func snapshot() -> VerifiedJourneyContentSnapshot {
        currentSnapshot
    }

    public func snapshotUpdates() -> AsyncStream<VerifiedJourneyContentSnapshot> {
        let observerID = UUID()
        let pair = AsyncStream<VerifiedJourneyContentSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        observers[observerID] = pair.continuation
        pair.continuation.yield(currentSnapshot)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(observerID) }
        }
        return pair.stream
    }

    /// Coalesces concurrent controller reads so one activation boundary cannot
    /// trigger duplicate rollback attempts or publish partially different
    /// repository/index pairs.
    @discardableResult
    public func refresh() async throws -> VerifiedJourneyContentSnapshot {
        if let inFlightRefresh {
            return try await awaitRefresh(inFlightRefresh)
        }

        let id = UUID()
        let task = Task { try await self.performRefresh(refreshID: id) }
        inFlightRefresh = InFlightRefresh(id: id, task: task)
        return try await awaitRefresh(InFlightRefresh(id: id, task: task))
    }

    public func reconciledInstalledIndex() async throws -> InstalledPackageIndex {
        try await refresh().reconciledInstalledIndex
    }

    /// Reverts an activation which could not be joined to the durable save.
    /// Both the generation being withdrawn and an optional predecessor are
    /// exact identities captured from verified Journey snapshots. A stale
    /// durable pointer is a no-op, never a best-effort package mutation.
    public func revertSaveMigrationAuthorityChange(
        packageID: PackageID,
        expectedCurrent: InstalledPackageGeneration,
        expectedPrevious: InstalledPackageGeneration?
    ) async throws -> VerifiedJourneyContentSnapshot? {
        await finishInFlightRefreshIfNeeded()
        guard packageID != LaunchContent.essentialPackageID,
              currentSnapshot.reconciledInstalledIndex.activeGeneration(
                for: packageID
              ) == expectedCurrent,
              let expectedPackage = manifest.packages.first(where: {
                  $0.id == packageID
              }) else {
            return nil
        }
        let authority = try await authorityProvider()
        try validateGlobalAuthority(authority)
        guard authority.index.activeGeneration(for: packageID)
                == expectedCurrent,
              authority.locationsByPackage[packageID]?.activeGeneration
                == expectedCurrent else {
            return nil
        }

        if let expectedPrevious {
            guard let predecessor = fullVerifiedImmediatePredecessor(
                in: authority,
                packageID: packageID,
                expectedPackage: expectedPackage
            ), predecessor.generation == expectedPrevious,
               let verified = await predecessor.verified.value,
               canJoinCurrentRepository(verified, replacing: packageID),
               case let .matching(latest) = await durableAuthority(
                   matching: expectedCurrent
               ),
               latest.locationsByPackage[packageID]?.previousGeneration
                    == expectedPrevious,
               latest.locationsByPackage[packageID]?.previousPackage
                    == predecessor.package else {
                return nil
            }
            switch try await exactRollback(
                packageID,
                expectedCurrent,
                expectedPrevious
            ) {
            case let .rolledBack(activated)
                where activated == predecessor.package:
                invalidateInFlightRefresh()
                publishWithdrawal(
                    packageID: packageID,
                    generation: expectedCurrent
                )
                return try await refresh()
            case .rolledBack, .staleAuthority:
                return nil
            }
        }

        switch try await deactivate(packageID, expectedCurrent) {
        case let .deactivated(generation) where generation == expectedCurrent:
            invalidateInFlightRefresh()
            publishWithdrawal(
                packageID: packageID,
                generation: expectedCurrent
            )
            return try await refresh()
        case .deactivated, .staleAuthority:
            return nil
        }
    }

    /// Handles a digest failure discovered after lazy runtime admission. The
    /// report is accepted only for the exact currently published snapshot and
    /// exact still-active durable generation. A predecessor crosses complete
    /// byte verification on a detached utility task before an atomic rollback;
    /// otherwise only the failed active pointer is durably quarantined.
    public func reportAssetFailure(
        packageID: PackageID,
        expectedAuthority: PackageAssetFailureAuthority
    ) async -> AssetFailureReportOutcome {
        await finishInFlightRefreshIfNeeded()
        guard isCurrent(
            packageID: packageID,
            expectedAuthority: expectedAuthority
        ) else {
            return .ignoredStaleReport
        }
        if packageID == LaunchContent.essentialPackageID {
            return .essentialRequiresReinstallOrUpdate
        }
        guard let activeGeneration = expectedAuthority.installedGeneration,
              let expectedPackage = manifest.packages.first(where: {
                  $0.id == packageID
              }) else {
            return .ignoredStaleReport
        }
        let firstAuthority: RetainedPackageAuthority
        switch await durableAuthority(matching: activeGeneration) {
        case let .matching(authority):
            firstAuthority = authority
        case .stale:
            return .ignoredStaleReport
        case .unavailable:
            return .ignoredDurableAuthority
        }

        if let predecessor = fullVerifiedImmediatePredecessor(
            in: firstAuthority,
            packageID: packageID,
            expectedPackage: expectedPackage
        ) {
            let fullyVerified = await predecessor.verified.value
            if let fullyVerified,
               isCurrent(
                   packageID: packageID,
                   expectedAuthority: expectedAuthority
               ),
               canJoinCurrentRepository(
                   fullyVerified,
                   replacing: packageID
               ),
               case let .matching(latestAuthority) = await durableAuthority(
                   matching: activeGeneration
               ),
               latestAuthority.locationsByPackage[packageID]?
                   .previousGeneration == predecessor.generation,
               latestAuthority.locationsByPackage[packageID]?
                   .previousPackage == predecessor.package {
                do {
                    let result = try await exactRollback(
                        packageID,
                        activeGeneration,
                        predecessor.generation
                    )
                    switch result {
                    case let .rolledBack(activated)
                        where activated == predecessor.package:
                        await publishAfterAssetRecovery(
                            packageID: packageID,
                            generation: activeGeneration
                        )
                        return .rolledBack(to: predecessor.generation)
                    case .rolledBack, .staleAuthority:
                        return .ignoredStaleReport
                    }
                } catch {
                    return .ignoredDurableAuthority
                }
            }
        }

        guard isCurrent(
            packageID: packageID,
            expectedAuthority: expectedAuthority
        ) else {
            return .ignoredStaleReport
        }
        switch await durableAuthority(matching: activeGeneration) {
        case .matching:
            break
        case .stale:
            return .ignoredStaleReport
        case .unavailable:
            return .ignoredDurableAuthority
        }
        do {
            switch try await deactivate(packageID, activeGeneration) {
            case let .deactivated(generation) where generation == activeGeneration:
                await publishAfterAssetRecovery(
                    packageID: packageID,
                    generation: activeGeneration
                )
                return .quarantined(generation)
            case .deactivated, .staleAuthority:
                return .ignoredStaleReport
            }
        } catch {
            return .ignoredDurableAuthority
        }
    }

    private func isCurrent(
        packageID: PackageID,
        expectedAuthority: PackageAssetFailureAuthority
    ) -> Bool {
        guard expectedAuthority.packageID == packageID,
              expectedAuthority.snapshotRevision == currentSnapshot.revision
        else {
            return false
        }
        if currentSnapshot.unavailablePackageFailureAuthority(
            for: packageID
        ) == expectedAuthority {
            return true
        }
        guard let verified = currentSnapshot.verifiedPackage(for: packageID),
              verified.manifest.manifestDigest == expectedAuthority.manifestDigest,
              currentSnapshot.packageRootURL(for: packageID) != nil else {
            return false
        }

        if packageID == LaunchContent.essentialPackageID {
            return expectedAuthority.installedGeneration == nil
                && currentSnapshot.reconciledInstalledIndex.activeGeneration(
                    for: packageID
                ) == nil
        }
        guard let generation = expectedAuthority.installedGeneration else {
            return false
        }
        return generation.packageID == packageID
            && generation.manifestDigest == expectedAuthority.manifestDigest
            && currentSnapshot.reconciledInstalledIndex.activeGeneration(
                for: packageID
            ) == generation
    }

    private func durableAuthority(
        matching generation: InstalledPackageGeneration
    ) async -> DurableAuthorityMatch {
        let authority: RetainedPackageAuthority
        do {
            authority = try await authorityProvider()
            try validateGlobalAuthority(authority)
        } catch {
            return .unavailable
        }
        guard authority.index.activeGeneration(for: generation.packageID) == generation,
              authority.locationsByPackage[generation.packageID]?
                  .activeGeneration == generation else {
            return .stale
        }
        return .matching(authority)
    }

    private func fullVerifiedImmediatePredecessor(
        in authority: RetainedPackageAuthority,
        packageID: PackageID,
        expectedPackage: ContentPackageSpec
    ) -> PredecessorVerification? {
        guard let locations = authority.locationsByPackage[packageID],
              let generation = locations.previousGeneration,
              generation.packageID == packageID,
              let retainedContract = continuityPackageSpec(
                  trustedPackage: expectedPackage,
                  generation: generation
              ),
              let package = locations.previousPackage,
              package.generation == generation else {
            return nil
        }

        let trustedPublicKeys = trustedPublicKeys
        let supportedSchema = assembler.supportedSchema
        let runtimeVersion = assembler.runtimeVersion
        let verified = Task.detached(priority: .utility) {
            () -> VerifiedContentPackage? in
            guard let candidate = try? ContentPackageVerifier.verifyPackage(
                at: package.packageURL,
                expectedPackage: retainedContract,
                trustedPublicKeys: trustedPublicKeys,
                supportedSchema: supportedSchema,
                runtimeVersion: runtimeVersion
            ), candidate.verificationScope == .completePackage,
               candidate.manifest.packageID == generation.packageID,
               candidate.manifest.packageVersion == generation.packageVersion,
               candidate.manifest.manifestDigest == generation.manifestDigest else {
                return nil
            }
            return candidate
        }
        return PredecessorVerification(
            generation: generation,
            package: package,
            verified: verified
        )
    }

    private func canJoinCurrentRepository(
        _ replacement: VerifiedContentPackage,
        replacing packageID: PackageID
    ) -> Bool {
        let paidPackages = LaunchContent.packageIDsInDeliveryOrder.compactMap {
            candidateID -> VerifiedContentPackage? in
            guard candidateID != LaunchContent.essentialPackageID else {
                return nil
            }
            if candidateID == packageID { return replacement }
            return currentSnapshot.verifiedPackage(for: candidateID)
        }
        return (try? assembleContinuityRepository(
            verifiedPackages: paidPackages
        )) != nil
    }

    private func finishInFlightRefreshIfNeeded() async {
        guard let inFlightRefresh else { return }
        _ = try? await awaitRefresh(inFlightRefresh)
    }

    private func publishAfterAssetRecovery(
        packageID: PackageID,
        generation: InstalledPackageGeneration
    ) async {
        invalidateInFlightRefresh()
        publishWithdrawal(packageID: packageID, generation: generation)
        _ = try? await refresh()
    }

    private func awaitRefresh(
        _ refresh: InFlightRefresh
    ) async throws -> VerifiedJourneyContentSnapshot {
        do {
            let snapshot = try await refresh.task.value
            if inFlightRefresh?.id == refresh.id {
                inFlightRefresh = nil
                if snapshot.revision != currentSnapshot.revision {
                    publish(snapshot)
                }
                return snapshot
            }
            // A successful exact-CAS mutation invalidated this task while it
            // was suspended. Its candidate may still name the withdrawn
            // generation, so neither callers nor observers may receive it.
            return currentSnapshot
        } catch {
            if inFlightRefresh?.id == refresh.id {
                inFlightRefresh = nil
                throw error
            }
            // Cancellation is advisory: a provider may still complete with
            // bytes captured before the mutation. The newer fail-closed
            // snapshot remains authoritative in either case.
            return currentSnapshot
        }
    }

    private func invalidateInFlightRefresh() {
        inFlightRefresh?.task.cancel()
        inFlightRefresh = nil
    }

    private func performRefresh(
        refreshID: UUID
    ) async throws -> VerifiedJourneyContentSnapshot {
        let authority: RetainedPackageAuthority
        do {
            authority = try await authorityProvider()
            try validateGlobalAuthority(authority)
        } catch {
            if inFlightRefresh?.id == refreshID {
                publishEssentialOnlyIfNeeded()
            }
            throw error
        }

        let packageByID = Dictionary(
            uniqueKeysWithValues: manifest.packages.map { ($0.id, $0) }
        )
        var reconciledIndex = authority.index
        var verifiedPackages: [VerifiedContentPackage] = []
        var repository = try assembler.assemble(
            verifiedBundledEssentialPackage: bundledEssentialPackage,
            verifiedPackages: []
        )
        var packageRoots: [PackageID: URL] = [
            LaunchContent.essentialPackageID: bundledEssentialRootURL,
        ]
        var verifiedByID: [PackageID: VerifiedContentPackage] = [
            LaunchContent.essentialPackageID: bundledEssentialPackage,
        ]
        var repaired: [PackageID] = []
        var unavailableGenerations: [
            PackageID: InstalledPackageGeneration
        ] = [:]

        for packageID in LaunchContent.packageIDsInDeliveryOrder
            where packageID != LaunchContent.essentialPackageID {
            guard let expectedPackage = packageByID[packageID],
                  let activeGeneration = authority.index.activeGeneration(for: packageID) else {
                continue
            }

            let verificationContract: ContentPackageSpec
            switch InstalledPackageVersionAuthority(
                activeGeneration: activeGeneration,
                expectedVersion: expectedPackage.version
            ) {
            case .protectedNewer:
                // Newer bytes remain protected from downgrade and cannot
                // enter an older runtime.
                continue
            case .updateRequired:
                guard let retained = continuityPackageSpec(
                    trustedPackage: expectedPackage,
                    generation: activeGeneration
                ) else { continue }
                verificationContract = retained
            case .current:
                verificationContract = expectedPackage
            }

            let locations = authority.locationsByPackage[packageID]
            if let activePackage = locations?.activePackage,
               let verified = try? verifiedCandidate(
                   activePackage,
                   generation: activeGeneration,
                   expectedPackage: verificationContract
               ),
               let joined = try? assembleContinuityRepository(
                   verifiedPackages: verifiedPackages + [verified]
               ) {
                verifiedPackages.append(verified)
                repository = joined
                packageRoots[packageID] = activePackage.packageURL
                verifiedByID[packageID] = verified
                continue
            }

            if let previousGeneration = locations?.previousGeneration,
               let previousContract = continuityPackageSpec(
                   trustedPackage: expectedPackage,
                   generation: previousGeneration
               ),
               let previousPackage = locations?.previousPackage,
               let verified = try? verifiedCandidate(
                   previousPackage,
                   generation: previousGeneration,
                   expectedPackage: previousContract
               ),
               let joined = try? assembleContinuityRepository(
                   verifiedPackages: verifiedPackages + [verified]
               ),
               case let .rolledBack(activated)? = try? await exactRollback(
                   packageID,
                   activeGeneration,
                   previousGeneration
               ), activated == previousPackage {
                reconciledIndex.activeGenerationByPackage[packageID] =
                    previousGeneration.generationID
                verifiedPackages.append(verified)
                repository = joined
                packageRoots[packageID] = activated.packageURL
                verifiedByID[packageID] = verified
                repaired.append(packageID)
                continue
            }

            // The durable index remains untouched when no runtime-admitted
            // previous generation can repair it. Runtime truth treats only
            // this exact package as absent, making it a download target.
            reconciledIndex.activeGenerationByPackage.removeValue(forKey: packageID)
            unavailableGenerations[packageID] = activeGeneration
        }

        let repairedIDs = repaired.sorted()
        let unavailableIDs = unavailableGenerations.keys.sorted()
        if currentSnapshot.reconciledInstalledIndex == reconciledIndex,
           currentSnapshot.packageRootURLs == packageRoots,
           currentSnapshot.repairedPackageIDs == repairedIDs,
           currentSnapshot.unavailableCurrentPackageIDs == unavailableIDs,
           currentSnapshot.unavailableCurrentGenerationsByPackageID
               == unavailableGenerations {
            return currentSnapshot
        }

        let next = VerifiedJourneyContentSnapshot(
            revision: currentSnapshot.revision &+ 1,
            repository: repository,
            reconciledInstalledIndex: reconciledIndex,
            packageRootURLs: packageRoots,
            verifiedPackagesByID: verifiedByID,
            repairedPackageIDs: repairedIDs,
            unavailableCurrentPackageIDs: unavailableIDs,
            unavailableCurrentGenerationsByPackageID:
                unavailableGenerations
        )
        return next
    }

    /// Withdraws an exact superseded generation synchronously after its
    /// durable pointer changes. This closes the actor-reentrancy window before
    /// the mandatory fresh rebuild crosses its first await.
    private func publishWithdrawal(
        packageID: PackageID,
        generation: InstalledPackageGeneration
    ) {
        guard currentSnapshot.reconciledInstalledIndex.activeGeneration(
            for: packageID
        ) == generation else {
            return
        }

        let remaining = LaunchContent.packageIDsInDeliveryOrder.compactMap {
            candidateID -> VerifiedContentPackage? in
            guard candidateID != LaunchContent.essentialPackageID,
                  candidateID != packageID else {
                return nil
            }
            return currentSnapshot.verifiedPackage(for: candidateID)
        }
        guard let repository = try? assembleContinuityRepository(
            verifiedPackages: remaining
        ) else {
            var unavailable = Set(
                currentSnapshot.unavailableCurrentPackageIDs
            )
            unavailable.formUnion(
                currentSnapshot.reconciledInstalledIndex
                    .activeGenerationByPackage.keys
            )
            publish(VerifiedJourneyContentSnapshot(
                revision: currentSnapshot.revision &+ 1,
                repository: initialSnapshot.repository,
                reconciledInstalledIndex: .empty,
                packageRootURLs: initialSnapshot.packageRootURLs,
                verifiedPackagesByID: initialSnapshot.verifiedPackagesByID,
                unavailableCurrentPackageIDs: Array(unavailable).sorted(),
                unavailableCurrentGenerationsByPackageID:
                    currentSnapshot
                        .unavailableCurrentGenerationsByPackageID
            ))
            return
        }

        var reconciledIndex = currentSnapshot.reconciledInstalledIndex
        reconciledIndex.activeGenerationByPackage.removeValue(
            forKey: packageID
        )
        var roots = currentSnapshot.packageRootURLs
        roots.removeValue(forKey: packageID)
        var verifiedByID = currentSnapshot.verifiedPackagesByID
        verifiedByID.removeValue(forKey: packageID)
        var unavailable = Set(currentSnapshot.unavailableCurrentPackageIDs)
        unavailable.insert(packageID)
        publish(VerifiedJourneyContentSnapshot(
            revision: currentSnapshot.revision &+ 1,
            repository: repository,
            reconciledInstalledIndex: reconciledIndex,
            packageRootURLs: roots,
            verifiedPackagesByID: verifiedByID,
            repairedPackageIDs: currentSnapshot.repairedPackageIDs.filter {
                $0 != packageID
            },
            unavailableCurrentPackageIDs: Array(unavailable).sorted(),
            unavailableCurrentGenerationsByPackageID:
                currentSnapshot.unavailableCurrentGenerationsByPackageID
        ))
    }

    private func continuityPackageSpec(
        trustedPackage: ContentPackageSpec,
        generation: InstalledPackageGeneration
    ) -> ContentPackageSpec? {
        guard generation.packageID == trustedPackage.id,
              generation.packageVersion <= trustedPackage.version else {
            return nil
        }
        return ContentPackageSpec(
            id: trustedPackage.id,
            version: generation.packageVersion,
            chapterIDs: trustedPackage.chapterIDs,
            maximumInstalledBytes: trustedPackage.maximumInstalledBytes,
            minimumRuntime: trustedPackage.minimumRuntime,
            isEssentialInstall: trustedPackage.isEssentialInstall
        )
    }

    private func assembleContinuityRepository(
        verifiedPackages: [VerifiedContentPackage]
    ) throws -> ContentRepository {
        var versionsByPackage: [PackageID: SchemaVersion] = [:]
        for verified in verifiedPackages {
            guard versionsByPackage.updateValue(
                verified.manifest.packageVersion,
                forKey: verified.manifest.packageID
            ) == nil else {
                throw VerifiedJourneyRepositoryAuthorityError
                    .unknownPackage(verified.manifest.packageID)
            }
        }
        let continuityManifest = CollectionManifest(
            schemaVersion: manifest.schemaVersion,
            collectionID: manifest.collectionID,
            locale: manifest.locale,
            product: manifest.product,
            chapters: manifest.chapters,
            packages: manifest.packages.map { package in
                guard let retainedVersion = versionsByPackage[package.id]
                else { return package }
                return ContentPackageSpec(
                    id: package.id,
                    version: retainedVersion,
                    chapterIDs: package.chapterIDs,
                    maximumInstalledBytes: package.maximumInstalledBytes,
                    minimumRuntime: package.minimumRuntime,
                    isEssentialInstall: package.isEssentialInstall
                )
            },
            entitlements: manifest.entitlements
        )
        return try ContentRepository(
            retainedLaunchContinuityManifest: continuityManifest,
            bundledEssentialPayload: bundledEssentialPackage.payload,
            verifiedPackages: verifiedPackages
        )
    }

    private func validateGlobalAuthority(
        _ authority: RetainedPackageAuthority
    ) throws {
        let declared = Set(manifest.packages.map(\.id))
        for packageID in Set(authority.index.generations.map(\.packageID))
            .union(authority.index.activeGenerationByPackage.keys) {
            guard packageID != LaunchContent.essentialPackageID else {
                throw VerifiedJourneyRepositoryAuthorityError
                    .downloadedEssentialPackage(packageID)
            }
            guard declared.contains(packageID) else {
                throw VerifiedJourneyRepositoryAuthorityError.unknownPackage(packageID)
            }
        }
        guard Set(authority.locationsByPackage.keys)
            == Set(authority.index.activeGenerationByPackage.keys) else {
            let mismatch = Set(authority.locationsByPackage.keys)
                .symmetricDifference(authority.index.activeGenerationByPackage.keys)
                .sorted()
                .first ?? LaunchContent.essentialPackageID
            throw VerifiedJourneyRepositoryAuthorityError.unknownPackage(mismatch)
        }
    }

    private func verifiedCandidate(
        _ package: ActivatedPackage,
        generation: InstalledPackageGeneration,
        expectedPackage: ContentPackageSpec
    ) throws -> VerifiedContentPackage {
        guard package.generation == generation else {
            throw PackageActivationError.verificationIdentityMismatch
        }
        let verified = try assembler.verifyDownloadedPackage(
            at: package.packageURL,
            expectedPackage: expectedPackage,
            trustedPublicKeys: trustedPublicKeys
        )
        guard verified.manifest.packageID == generation.packageID,
              verified.manifest.packageVersion == generation.packageVersion,
              verified.manifest.manifestDigest == generation.manifestDigest else {
            throw PackageActivationError.verificationIdentityMismatch
        }
        return verified
    }

    private func publishEssentialOnlyIfNeeded() {
        guard currentSnapshot.repository.availablePackageIDs
            != [LaunchContent.essentialPackageID]
            || currentSnapshot.reconciledInstalledIndex != .empty else {
            return
        }
        let next = VerifiedJourneyContentSnapshot(
            revision: currentSnapshot.revision &+ 1,
            repository: initialSnapshot.repository,
            reconciledInstalledIndex: .empty,
            packageRootURLs: initialSnapshot.packageRootURLs,
            verifiedPackagesByID: initialSnapshot.verifiedPackagesByID
        )
        publish(next)
    }

    private func publish(_ snapshot: VerifiedJourneyContentSnapshot) {
        currentSnapshot = snapshot
        for observer in observers.values {
            observer.yield(snapshot)
        }
    }

    private func removeObserver(_ observerID: UUID) {
        observers.removeValue(forKey: observerID)
    }
}
