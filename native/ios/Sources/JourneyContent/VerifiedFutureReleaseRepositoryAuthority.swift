import ContentDelivery
import ContentKit
import Foundation

public enum VerifiedFutureReleaseRepositoryAuthorityError: Error, Equatable, Sendable {
    case duplicateReleaseID(ReleaseID)
    case duplicatePackageBinding(packageID: PackageID, version: SchemaVersion)
    case duplicateActiveChapterID(ChapterID)
    case activePackageWithoutRetainedContract(PackageID)
}

/// One independently verified, fully offline post-launch work. Its repository
/// is isolated from the 24-chapter launch collection, while the shared Journey
/// state supplies the living world and prior historical consequences.
public struct VerifiedFutureReleaseContent: Sendable {
    public let release: Release
    public let repository: ContentRepository
    public let packageRootURL: URL
    public let installedGeneration: InstalledPackageGeneration
    public let verifiedPackage: VerifiedContentPackage

    public init(
        release: Release,
        repository: ContentRepository,
        packageRootURL: URL,
        installedGeneration: InstalledPackageGeneration,
        verifiedPackage: VerifiedContentPackage
    ) {
        self.release = release
        self.repository = repository
        self.packageRootURL = packageRootURL
        self.installedGeneration = installedGeneration
        self.verifiedPackage = verifiedPackage
    }
}

public struct VerifiedFutureReleaseContentSnapshot: Sendable {
    public let revision: UInt64
    public let contentsByReleaseID: [ReleaseID: VerifiedFutureReleaseContent]
    public let unavailableInstalledPackageIDs: [PackageID]

    public init(
        revision: UInt64,
        contentsByReleaseID: [ReleaseID: VerifiedFutureReleaseContent],
        unavailableInstalledPackageIDs: [PackageID]
    ) {
        self.revision = revision
        self.contentsByReleaseID = contentsByReleaseID
        self.unavailableInstalledPackageIDs = unavailableInstalledPackageIDs.sorted()
    }

    public static let empty = VerifiedFutureReleaseContentSnapshot(
        revision: 0,
        contentsByReleaseID: [:],
        unavailableInstalledPackageIDs: []
    )

    public func content(
        for releaseID: ReleaseID
    ) -> VerifiedFutureReleaseContent? {
        contentsByReleaseID[releaseID]
    }
}

/// Reconstructs runtime authority from two durable stores which remain useful
/// offline: the authenticated Release installation ledger and PackageActivator's
/// active-generation index. Every active root then crosses canonical payload
/// admission again before it becomes addressable by a chapter coordinator.
public actor VerifiedFutureReleaseRepositoryAuthority {
    public typealias ReleaseContractProvider = @Sendable () async throws -> [Release]
    public typealias PackageAuthorityProvider = @Sendable () async throws
        -> RetainedPackageAuthority
    public typealias PackageAdmission = @Sendable (
        URL,
        ContentPackageSpec,
        [String: Data],
        SchemaVersion,
        SchemaVersion
    ) throws -> VerifiedContentPackage
    public typealias Deactivate = @Sendable (
        PackageID,
        InstalledPackageGeneration
    ) async throws -> PackageDeactivationResult
    public typealias ExactRollback = @Sendable (
        PackageID,
        InstalledPackageGeneration,
        InstalledPackageGeneration
    ) async throws -> ExactPackageRollbackResult
    public typealias CompletePackageVerification = @Sendable (
        URL,
        ContentPackageSpec,
        [String: Data],
        SchemaVersion,
        SchemaVersion
    ) throws -> VerifiedContentPackage

    private struct InFlightRefresh {
        let id: UUID
        let task: Task<VerifiedFutureReleaseContentSnapshot, any Error>
    }

    private let expectedWorldSeed: WorldSeedSpec
    private let trustedPublicKeys: [String: Data]
    private let supportedSchema: SchemaVersion
    private let runtimeVersion: SchemaVersion
    private let releaseContractProvider: ReleaseContractProvider
    private let packageAuthorityProvider: PackageAuthorityProvider
    private let packageAdmission: PackageAdmission
    private let deactivate: Deactivate
    private let exactRollback: ExactRollback
    private let completePackageVerification: CompletePackageVerification

    private var currentSnapshot = VerifiedFutureReleaseContentSnapshot.empty
    private var inFlightRefresh: InFlightRefresh?
    private var observers: [
        UUID: AsyncStream<VerifiedFutureReleaseContentSnapshot>.Continuation
    ] = [:]

    public init(
        expectedWorldSeed: WorldSeedSpec,
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion,
        releaseContractProvider: @escaping ReleaseContractProvider,
        packageAuthorityProvider: @escaping PackageAuthorityProvider,
        deactivate: @escaping Deactivate = { _, _ in .staleAuthority },
        exactRollback: @escaping ExactRollback = { _, _, _ in .staleAuthority },
        packageAdmission: @escaping PackageAdmission = {
            packageRoot,
            expectedPackage,
            trustedPublicKeys,
            supportedSchema,
            runtimeVersion in
            try ContentPackageVerifier.admitPackageAtRuntime(
                at: packageRoot,
                expectedPackage: expectedPackage,
                trustedPublicKeys: trustedPublicKeys,
                supportedSchema: supportedSchema,
                runtimeVersion: runtimeVersion
            )
        },
        completePackageVerification: @escaping CompletePackageVerification = {
            packageRoot,
            expectedPackage,
            trustedPublicKeys,
            supportedSchema,
            runtimeVersion in
            try ContentPackageVerifier.verifyPackage(
                at: packageRoot,
                expectedPackage: expectedPackage,
                trustedPublicKeys: trustedPublicKeys,
                supportedSchema: supportedSchema,
                runtimeVersion: runtimeVersion
            )
        }
    ) {
        self.expectedWorldSeed = expectedWorldSeed
        self.trustedPublicKeys = trustedPublicKeys
        self.supportedSchema = supportedSchema
        self.runtimeVersion = runtimeVersion
        self.releaseContractProvider = releaseContractProvider
        self.packageAuthorityProvider = packageAuthorityProvider
        self.packageAdmission = packageAdmission
        self.deactivate = deactivate
        self.exactRollback = exactRollback
        self.completePackageVerification = completePackageVerification
    }

    public func snapshot() -> VerifiedFutureReleaseContentSnapshot {
        currentSnapshot
    }

    public func snapshotUpdates()
        -> AsyncStream<VerifiedFutureReleaseContentSnapshot> {
        let observerID = UUID()
        let pair = AsyncStream<VerifiedFutureReleaseContentSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        observers[observerID] = pair.continuation
        pair.continuation.yield(currentSnapshot)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(observerID) }
        }
        return pair.stream
    }

    /// Exact package-side compensation for a save migration that failed
    /// before its new content snapshot could be exposed. A predecessor is
    /// completely byte-verified again before PackageActivator may select it.
    public func revertSaveMigrationAuthorityChange(
        packageID: PackageID,
        expectedCurrent: InstalledPackageGeneration,
        expectedPrevious: InstalledPackageGeneration?
    ) async throws -> VerifiedFutureReleaseContentSnapshot? {
        if let inFlightRefresh {
            _ = try? await awaitRefresh(inFlightRefresh)
        }
        guard let content = currentSnapshot.contentsByReleaseID.values.first(
            where: { $0.release.packageID == packageID }
        ), content.installedGeneration == expectedCurrent else {
            return nil
        }
        let authority = try await packageAuthorityProvider()
        guard authority.index.activeGeneration(for: packageID)
                == expectedCurrent,
              authority.locationsByPackage[packageID]?.activeGeneration
                == expectedCurrent else {
            return nil
        }

        if let expectedPrevious {
            guard let locations = authority.locationsByPackage[packageID],
                  locations.previousGeneration == expectedPrevious,
                  let previousPackage = locations.previousPackage,
                  previousPackage.generation == expectedPrevious else {
                return nil
            }
            let expectedPackage = try Self.retainedPackageSpec(
                release: content.release,
                generation: expectedPrevious
            )
            let verified = try completePackageVerification(
                previousPackage.packageURL,
                expectedPackage,
                trustedPublicKeys,
                supportedSchema,
                runtimeVersion
            )
            guard verified.manifest.packageID == expectedPrevious.packageID,
                  verified.manifest.packageVersion
                    == expectedPrevious.packageVersion,
                  verified.manifest.manifestDigest
                    == expectedPrevious.manifestDigest else {
                return nil
            }
            _ = try ContentRepository(
                trustedFutureReleaseContinuity: content.release,
                retainedVerifiedPackage: verified,
                expectedWorldSeed: expectedWorldSeed,
                retainedPackageVersion: expectedPrevious.packageVersion
            )
            let latest = try await packageAuthorityProvider()
            guard latest.index.activeGeneration(for: packageID)
                    == expectedCurrent,
                  latest.locationsByPackage[packageID]?.previousGeneration
                    == expectedPrevious,
                  latest.locationsByPackage[packageID]?.previousPackage
                    == previousPackage else {
                return nil
            }
            switch try await exactRollback(
                packageID,
                expectedCurrent,
                expectedPrevious
            ) {
            case let .rolledBack(activated) where activated == previousPackage:
                invalidateInFlightRefresh()
                publishQuarantine(
                    releaseID: content.release.id,
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
            publishQuarantine(
                releaseID: content.release.id,
                packageID: packageID,
                generation: expectedCurrent
            )
            return try await refresh()
        case .deactivated, .staleAuthority:
            return nil
        }
    }

    /// Quarantines a lazily detected asset failure only while the report still
    /// names the exact published snapshot, manifest and active generation.
    /// Package ID alone is never deactivation authority.
    public func reportAssetFailure(
        releaseID: ReleaseID,
        expectedAuthority: PackageAssetFailureAuthority
    ) async -> AssetFailureReportOutcome {
        guard let content = currentSnapshot.content(for: releaseID),
              expectedAuthority.snapshotRevision == currentSnapshot.revision,
              expectedAuthority.packageID == content.release.packageID,
              expectedAuthority.installedGeneration
                == content.installedGeneration,
              expectedAuthority.manifestDigest
                == content.verifiedPackage.manifest.manifestDigest else {
            return .ignoredStaleReport
        }
        do {
            let durable = try await packageAuthorityProvider()
            guard durable.index.activeGeneration(
                for: content.release.packageID
            ) == content.installedGeneration else {
                return .ignoredDurableAuthority
            }
            switch try await deactivate(
                content.release.packageID,
                content.installedGeneration
            ) {
            case let .deactivated(generation):
                // A refresh which captured the active root before the atomic
                // deactivation is no longer allowed to publish or escape to
                // one of its callers as playable authority. Withdraw the
                // exact generation immediately, then rebuild from durable
                // post-deactivation state. If that rebuild fails, the local
                // withdrawal remains the published fail-closed authority.
                invalidateInFlightRefresh()
                publishQuarantine(
                    releaseID: releaseID,
                    packageID: content.release.packageID,
                    generation: generation
                )
                _ = try? await refresh()
                return .quarantined(generation)
            case .staleAuthority:
                return .ignoredDurableAuthority
            }
        } catch {
            return .ignoredDurableAuthority
        }
    }

    @discardableResult
    public func bootstrap() async throws -> VerifiedFutureReleaseContentSnapshot {
        try await refresh()
    }

    @discardableResult
    public func refresh() async throws -> VerifiedFutureReleaseContentSnapshot {
        if let inFlightRefresh {
            return try await awaitRefresh(inFlightRefresh)
        }

        let refreshID = UUID()
        let revision = currentSnapshot.revision &+ 1
        let expectedWorldSeed = expectedWorldSeed
        let trustedPublicKeys = trustedPublicKeys
        let supportedSchema = supportedSchema
        let runtimeVersion = runtimeVersion
        let releaseContractProvider = releaseContractProvider
        let packageAuthorityProvider = packageAuthorityProvider
        let packageAdmission = packageAdmission
        let task = Task {
            let releases = try await releaseContractProvider()
            let authority = try await packageAuthorityProvider()
            return try Self.buildSnapshot(
                revision: revision,
                releases: releases,
                authority: authority,
                expectedWorldSeed: expectedWorldSeed,
                trustedPublicKeys: trustedPublicKeys,
                supportedSchema: supportedSchema,
                runtimeVersion: runtimeVersion,
                packageAdmission: packageAdmission
            )
        }
        inFlightRefresh = InFlightRefresh(id: refreshID, task: task)
        return try await awaitRefresh(
            InFlightRefresh(id: refreshID, task: task)
        )
    }

    private func awaitRefresh(
        _ refresh: InFlightRefresh
    ) async throws -> VerifiedFutureReleaseContentSnapshot {
        do {
            let snapshot = try await refresh.task.value
            if inFlightRefresh?.id == refresh.id {
                inFlightRefresh = nil
                publish(snapshot)
                return snapshot
            }
            // A mutating authority transition invalidated this task while it
            // was suspended. Its candidate may name bytes which are no
            // longer active, so callers receive only the newer published
            // snapshot.
            return currentSnapshot
        } catch {
            if inFlightRefresh?.id == refresh.id {
                inFlightRefresh = nil
                throw error
            }
            // Cancellation caused by a newer fail-closed authority must not
            // turn that newer authority into a transient presentation error.
            return currentSnapshot
        }
    }

    private static func buildSnapshot(
        revision: UInt64,
        releases: [Release],
        authority: RetainedPackageAuthority,
        expectedWorldSeed: WorldSeedSpec,
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion,
        packageAdmission: PackageAdmission
    ) throws -> VerifiedFutureReleaseContentSnapshot {
        let releases = try validateAndSort(releases)
        let retainedPackageIDs = Set(releases.map(\.packageID))
        if let unknown = authority.index.activeGenerationByPackage.keys
            .filter({ !retainedPackageIDs.contains($0) })
            .sorted()
            .first {
            throw VerifiedFutureReleaseRepositoryAuthorityError
                .activePackageWithoutRetainedContract(unknown)
        }

        var contents: [ReleaseID: VerifiedFutureReleaseContent] = [:]
        var unavailable: Set<PackageID> = []

        for release in releases {
            guard let locations = authority.locationsByPackage[release.packageID],
                  let generation = locations.activeGeneration else {
                if authority.index.generations.contains(where: {
                    $0.packageID == release.packageID
                        && $0.packageVersion == release.version
                }) {
                    // Deactivated bytes remain retained for diagnosis, but
                    // no active pointer means they are deliberately
                    // unavailable to the Journey.
                    unavailable.insert(release.packageID)
                }
                continue
            }
            guard generation.packageVersion <= release.version,
                  let activePackage = locations.activePackage,
                  activePackage.generation == generation else {
                unavailable.insert(release.packageID)
                continue
            }

            do {
                let packageSpec = try retainedPackageSpec(
                    release: release,
                    generation: generation
                )
                let verified = try packageAdmission(
                    activePackage.packageURL,
                    packageSpec,
                    trustedPublicKeys,
                    supportedSchema,
                    runtimeVersion
                )
                guard verified.manifest.manifestDigest == generation.manifestDigest,
                      verified.manifest.packageID == generation.packageID,
                      verified.manifest.packageVersion == generation.packageVersion else {
                    unavailable.insert(release.packageID)
                    continue
                }
                let repository = try ContentRepository(
                    trustedFutureReleaseContinuity: release,
                    retainedVerifiedPackage: verified,
                    expectedWorldSeed: expectedWorldSeed,
                    retainedPackageVersion: generation.packageVersion
                )
                contents[release.id] = VerifiedFutureReleaseContent(
                    release: release,
                    repository: repository,
                    packageRootURL: activePackage.packageURL,
                    installedGeneration: generation,
                    verifiedPackage: verified
                )
            } catch {
                unavailable.insert(release.packageID)
            }
        }

        var activeChapterIDs: Set<ChapterID> = []
        for content in contents.values {
            for chapterID in content.repository.availableChapterIDs {
                guard activeChapterIDs.insert(chapterID).inserted else {
                    throw VerifiedFutureReleaseRepositoryAuthorityError
                        .duplicateActiveChapterID(chapterID)
                }
            }
        }

        return VerifiedFutureReleaseContentSnapshot(
            revision: revision,
            contentsByReleaseID: contents,
            unavailableInstalledPackageIDs: Array(unavailable)
        )
    }

    private static func validateAndSort(_ releases: [Release]) throws -> [Release] {
        var releaseIDs: Set<ReleaseID> = []
        var packageBindings: Set<String> = []
        for release in releases {
            try release.validate()
            guard releaseIDs.insert(release.id).inserted else {
                throw VerifiedFutureReleaseRepositoryAuthorityError
                    .duplicateReleaseID(release.id)
            }
            let binding = "\(release.packageID.rawValue)@\(release.version)"
            guard packageBindings.insert(binding).inserted else {
                throw VerifiedFutureReleaseRepositoryAuthorityError
                    .duplicatePackageBinding(
                        packageID: release.packageID,
                        version: release.version
                    )
            }
        }
        return releases.sorted {
            if $0.publishedAtUnixMillis != $1.publishedAtUnixMillis {
                return $0.publishedAtUnixMillis < $1.publishedAtUnixMillis
            }
            return $0.id < $1.id
        }
    }

    private static func retainedPackageSpec(
        release: Release,
        generation: InstalledPackageGeneration
    ) throws -> ContentPackageSpec {
        try release.validate()
        guard generation.packageID == release.packageID,
              generation.packageVersion <= release.version else {
            throw VerifiedFutureReleaseRepositoryAuthorityError
                .activePackageWithoutRetainedContract(generation.packageID)
        }
        return ContentPackageSpec(
            id: release.packageID,
            version: generation.packageVersion,
            chapterIDs: release.chapterIDs,
            maximumInstalledBytes: release.maximumInstalledBytes,
            minimumRuntime: release.minimumRuntime,
            isEssentialInstall: false
        )
    }

    private func publish(_ snapshot: VerifiedFutureReleaseContentSnapshot) {
        currentSnapshot = snapshot
        for observer in observers.values {
            observer.yield(snapshot)
        }
    }

    private func invalidateInFlightRefresh() {
        inFlightRefresh?.task.cancel()
        inFlightRefresh = nil
    }

    private func publishQuarantine(
        releaseID: ReleaseID,
        packageID: PackageID,
        generation: InstalledPackageGeneration
    ) {
        var contents = currentSnapshot.contentsByReleaseID
        if let current = contents[releaseID],
           current.installedGeneration == generation {
            contents.removeValue(forKey: releaseID)
        }
        var unavailable = Set(
            currentSnapshot.unavailableInstalledPackageIDs
        )
        unavailable.insert(packageID)
        publish(
            VerifiedFutureReleaseContentSnapshot(
                revision: currentSnapshot.revision &+ 1,
                contentsByReleaseID: contents,
                unavailableInstalledPackageIDs: Array(unavailable)
            )
        )
    }

    private func removeObserver(_ observerID: UUID) {
        observers.removeValue(forKey: observerID)
    }
}
