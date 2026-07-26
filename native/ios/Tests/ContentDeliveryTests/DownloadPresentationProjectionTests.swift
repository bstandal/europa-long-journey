@testable import ContentDelivery
import ContentKit
import XCTest

final class DownloadPresentationProjectionTests: XCTestCase {
    private static let allPackageIDs = LaunchContent.packageIDsInDeliveryOrder
    private static let paidPackageIDs = allPackageIDs.filter {
        $0 != LaunchContent.essentialPackageID
    }
    private static let failure = PackageBatchFailure(domain: "test.delivery", code: 41)

    func testAwaitingBootstrapIsAnExactFailClosedProjection() throws {
        let projection = try DownloadPresentationProjection(snapshot: .awaitingBootstrap)

        XCTAssertEqual(projection.bootstrapState, .awaitingBootstrap)
        XCTAssertEqual(projection.packageRows.map(\.id), Self.allPackageIDs)
        XCTAssertEqual(
            projection.packageRows.map(\.canonicalOrder),
            Array(Self.allPackageIDs.indices)
        )
        XCTAssertEqual(projection.packageRows.first?.state, .includedInApp)
        XCTAssertEqual(
            projection.packageRows.dropFirst().map(\.state),
            Array(repeating: .awaitingBootstrap, count: Self.paidPackageIDs.count)
        )
        XCTAssertEqual(projection.installedPackageIDs, [])
        XCTAssertEqual(projection.pendingPaidPackageIDs, [])
        XCTAssertEqual(projection.outdatedPackages, [])
        XCTAssertEqual(projection.protectedNewerPackages, [])
        XCTAssertEqual(projection.remainingMaximumInstalledBytes, 0)
        XCTAssertEqual(projection.applicationQueueState, .idle)
        XCTAssertEqual(projection.appleSystemTransferState, .idle)
        XCTAssertEqual(projection.allowedCommands, [])
    }

    func testRowsUseCanonicalPackageAndLocalisableChapterMetadata() throws {
        let installed = [Self.paidPackageIDs[0], Self.paidPackageIDs[3]]
        let pending = Self.paidPackageIDs.filter { !installed.contains($0) }
        let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
            installed: installed,
            pending: pending
        ))
        let manifest = LaunchContent.collectionManifest
        let expectedPackageByID = Dictionary(
            uniqueKeysWithValues: manifest.packages.map { ($0.id, $0) }
        )
        let expectedChapterByID = Dictionary(
            uniqueKeysWithValues: manifest.chapters.map { ($0.id, $0) }
        )

        XCTAssertEqual(projection.packageRows.map(\.id), Self.allPackageIDs)
        for row in projection.packageRows {
            let package = try XCTUnwrap(expectedPackageByID[row.id])
            XCTAssertEqual(row.maximumInstalledBytes, package.maximumInstalledBytes)
            XCTAssertEqual(row.chapters.map(\.id), package.chapterIDs)
            for chapter in row.chapters {
                let expected = try XCTUnwrap(expectedChapterByID[chapter.id])
                XCTAssertEqual(chapter.sequence, expected.sequence)
                XCTAssertEqual(chapter.title, expected.title)
                XCTAssertEqual(chapter.period, expected.period)
            }
        }
        XCTAssertEqual(projection.packageRows[0].state, .includedInApp)
        XCTAssertEqual(projection.packageRows[1].state, .installedCurrent)
        XCTAssertEqual(projection.packageRows[2].state, .pending)
        XCTAssertEqual(projection.packageRows[4].state, .installedCurrent)
        XCTAssertEqual(projection.installedPackageIDs, installed)
        XCTAssertEqual(projection.pendingPaidPackageIDs, pending)
        XCTAssertEqual(projection.remainingMaximumInstalledBytes, Self.maximumBytes(for: pending))
    }

    func testEssentialIndexEntryMayBePresentButNeverBecomesDownloadable() throws {
        let installed = [LaunchContent.essentialPackageID, Self.paidPackageIDs[0]]
        let pending = Array(Self.paidPackageIDs.dropFirst())
        let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
            installed: installed,
            pending: pending
        ))

        XCTAssertEqual(projection.installedPackageIDs, installed)
        XCTAssertEqual(projection.packageRows.first?.state, .includedInApp)
        XCTAssertFalse(projection.allowedCommands.contains(
            .requestSinglePackage(LaunchContent.essentialPackageID)
        ))
    }

    func testEveryApplicationQueueStateIsPreservedExactlyAndMapsOnlyItsCommands() throws {
        let p = Self.paidPackageIDs
        let cases: [(PackageBatchInstallationState, [DownloadPresentationCommand])] = [
            (
                .idle,
                p.map(DownloadPresentationCommand.requestSinglePackage) + [.requestDownloadAll]
            ),
            (
                .starting(packageID: p[0], completedPackageIDs: [], totalPackageCount: 7),
                []
            ),
            (
                .installing(packageID: p[1], completedPackageIDs: [p[0]], totalPackageCount: 7),
                [.requestQueuePauseAfterCurrentPackage]
            ),
            (
                .pausingAfterCurrent(
                    packageID: p[1],
                    completedPackageIDs: [p[0]],
                    totalPackageCount: 7
                ),
                [.resumeApplicationQueue]
            ),
            (
                .paused(
                    nextPackageID: p[2],
                    completedPackageIDs: [p[0], p[1]],
                    totalPackageCount: 7
                ),
                [.resumeApplicationQueue]
            ),
            (
                .awaitingExplicitRestore(
                    nextPackageID: p[2],
                    completedPackageIDs: [p[0], p[1]],
                    totalPackageCount: 7
                ),
                [.resumeApplicationQueue]
            ),
            (
                .staleJournal(reason: .unknownOrRemovedPackageIDs(["retired-pack"])),
                [.discardStaleQueue]
            ),
            (
                .staleJournal(reason: .nonCanonicalPackageOrder([p[1], p[0]])),
                [.discardStaleQueue]
            ),
            (
                .staleJournal(reason: .corruptJournal),
                [.discardStaleQueue]
            ),
            (
                .completed(installedPackageIDs: [p[0], p[1]]),
                p.map(DownloadPresentationCommand.requestSinglePackage) + [.requestDownloadAll]
            ),
            (
                .failed(packageID: p[2], completedPackageIDs: [p[0], p[1]], failure: Self.failure),
                [.retryFailedPackage, .removeFailedPackage]
            ),
        ]

        for (state, expectedCommands) in cases {
            let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
                installationState: state
            ))
            XCTAssertEqual(projection.applicationQueueState, state)
            XCTAssertEqual(projection.appleSystemTransferState, .idle)
            XCTAssertEqual(projection.allowedCommands, expectedCommands, "state: \(state)")
        }
    }

    func testEveryAppleSystemTransferStateIsPreservedWithoutChangingQueueCommands() throws {
        let active = Self.paidPackageIDs[1]
        let queueState = PackageBatchInstallationState.installing(
            packageID: active,
            completedPackageIDs: [Self.paidPackageIDs[0]],
            totalPackageCount: Self.paidPackageIDs.count
        )
        let transferStates: [PackageSystemTransferState] = [
            .idle,
            .began(packageID: active, returnedAfterObservedPause: false),
            .began(packageID: active, returnedAfterObservedPause: true),
            .paused(packageID: active),
            .downloading(packageID: active, completedUnitCount: 0, totalUnitCount: 100),
            .downloading(packageID: active, completedUnitCount: 100, totalUnitCount: 100),
            .finished(packageID: active),
            .failed(packageID: active, failure: Self.failure),
        ]

        for transferState in transferStates {
            let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
                installationState: queueState,
                systemTransferState: transferState
            ))
            XCTAssertEqual(projection.applicationQueueState, queueState)
            XCTAssertEqual(projection.appleSystemTransferState, transferState)
            XCTAssertEqual(
                projection.allowedCommands,
                [.requestQueuePauseAfterCurrentPackage],
                "system state must not manufacture transfer controls: \(transferState)"
            )
        }
    }

    func testPausingQueueMayRetainExactAppleTransferObservation() throws {
        let active = Self.paidPackageIDs[0]
        let queueState = PackageBatchInstallationState.pausingAfterCurrent(
            packageID: active,
            completedPackageIDs: [],
            totalPackageCount: Self.paidPackageIDs.count
        )
        let transferState = PackageSystemTransferState.downloading(
            packageID: active,
            completedUnitCount: 63,
            totalUnitCount: 100
        )

        let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
            installationState: queueState,
            systemTransferState: transferState
        ))

        XCTAssertEqual(projection.applicationQueueState, queueState)
        XCTAssertEqual(projection.appleSystemTransferState, transferState)
        XCTAssertEqual(projection.allowedCommands, [.resumeApplicationQueue])
    }

    func testNoPendingPackagesExposeNoNewRequestCommands() throws {
        let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
            installed: Self.paidPackageIDs,
            pending: []
        ))

        XCTAssertEqual(projection.remainingMaximumInstalledBytes, 0)
        XCTAssertEqual(projection.allowedCommands, [])
        XCTAssertEqual(
            projection.packageRows.dropFirst().map(\.state),
            Array(repeating: .installedCurrent, count: Self.paidPackageIDs.count)
        )
    }

    func testProtectedNewerPackageRequiresAppUpdateAndCannotBeRequested() throws {
        let protected = Self.protectedVersion(for: Self.paidPackageIDs[0])
        let pending = Array(Self.paidPackageIDs.dropFirst())
        let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
            pending: pending,
            protectedNewer: [protected]
        ))

        XCTAssertEqual(projection.protectedNewerPackages, [protected])
        XCTAssertEqual(
            projection.packageRows[1].state,
            .requiresNewerApp(
                installedVersion: protected.installedVersion,
                expectedVersion: protected.expectedVersion
            )
        )
        XCTAssertFalse(projection.allowedCommands.contains(
            .requestSinglePackage(protected.packageID)
        ))
        XCTAssertTrue(projection.allowedCommands.contains(.requestDownloadAll))
        XCTAssertEqual(
            projection.remainingMaximumInstalledBytes,
            Self.maximumBytes(for: pending)
        )
    }

    func testOutdatedPackageIsPresentedAsAnUpdateAndRemainsRequestable() throws {
        let outdated = Self.outdatedVersion(for: Self.paidPackageIDs[0])
        let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
            outdated: [outdated]
        ))

        XCTAssertEqual(projection.outdatedPackages, [outdated])
        XCTAssertEqual(
            projection.packageRows[1].state,
            .updatePending(
                installedVersion: outdated.installedVersion,
                expectedVersion: outdated.expectedVersion
            )
        )
        XCTAssertTrue(projection.allowedCommands.contains(
            .requestSinglePackage(outdated.packageID)
        ))
        XCTAssertTrue(projection.allowedCommands.contains(.requestDownloadAll))
        XCTAssertTrue(
            projection.packageRows[1].state
                .allowsVerifiedInstalledGenerationOpen
        )
    }

    func testOnlyInstalledPresentationStatesCanReachVerifiedRuntimeOpening() {
        let version = SchemaVersion(major: 1)
        XCTAssertTrue(
            DownloadPackagePresentationState.includedInApp
                .allowsVerifiedInstalledGenerationOpen
        )
        XCTAssertTrue(
            DownloadPackagePresentationState.installedCurrent
                .allowsVerifiedInstalledGenerationOpen
        )
        XCTAssertTrue(
            DownloadPackagePresentationState.updatePending(
                installedVersion: version,
                expectedVersion: SchemaVersion(major: 2)
            ).allowsVerifiedInstalledGenerationOpen
        )
        XCTAssertFalse(
            DownloadPackagePresentationState.awaitingBootstrap
                .allowsVerifiedInstalledGenerationOpen
        )
        XCTAssertFalse(
            DownloadPackagePresentationState.pending
                .allowsVerifiedInstalledGenerationOpen
        )
        XCTAssertFalse(
            DownloadPackagePresentationState.requiresNewerApp(
                installedVersion: SchemaVersion(major: 2),
                expectedVersion: version
            ).allowsVerifiedInstalledGenerationOpen
        )
    }

    func testQueueReferencingProtectedNewerPackageCannotResumeOrBeDiscarded() throws {
        let protected = Self.protectedVersion(for: Self.paidPackageIDs[0])
        let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
            pending: Array(Self.paidPackageIDs.dropFirst()),
            protectedNewer: [protected],
            installationState: .staleJournal(
                reason: .protectedNewerPackageVersions([protected.packageID])
            )
        ))

        XCTAssertEqual(projection.allowedCommands, [])
        XCTAssertEqual(
            projection.applicationQueueState,
            .staleJournal(
                reason: .protectedNewerPackageVersions([protected.packageID])
            )
        )
    }

    func testFutureQueueSchemaRequiresAppUpdateAndCannotBeDiscarded() throws {
        let futureFormat = PackageBatchQueueJournal.currentFormatVersion + 1
        let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
            installationState: .staleJournal(
                reason: .requiresNewerApp(formatVersion: futureFormat)
            )
        ))

        XCTAssertEqual(projection.allowedCommands, [])
        XCTAssertEqual(
            projection.applicationQueueState,
            .staleJournal(reason: .requiresNewerApp(formatVersion: futureFormat))
        )

        assertProjectionError(
            .invalidInstallationState,
            snapshot: Self.readySnapshot(
                installationState: .staleJournal(
                    reason: .requiresNewerApp(
                        formatVersion: PackageBatchQueueJournal.currentFormatVersion
                    )
                )
            )
        )
    }

    func testRefreshFailurePreservesMachineStateButSuppressesNewRequestsFromStalePlan() throws {
        let snapshot = Self.readySnapshot(refreshFailure: Self.failure)
        let projection = try DownloadPresentationProjection(snapshot: snapshot)

        XCTAssertEqual(projection.refreshFailure, Self.failure)
        XCTAssertEqual(projection.pendingPaidPackageIDs, Self.paidPackageIDs)
        XCTAssertEqual(projection.allowedCommands, [.refreshInstalledChapters])

        let failedQueue = PackageBatchInstallationState.failed(
            packageID: Self.paidPackageIDs[0],
            completedPackageIDs: [],
            failure: Self.failure
        )
        let recovery = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
            installationState: failedQueue,
            refreshFailure: Self.failure
        ))
        XCTAssertEqual(recovery.allowedCommands, [.retryFailedPackage, .removeFailedPackage])
    }

    func testMalformedAwaitingBootstrapSnapshotsAreRejected() {
        let malformed = DownloadControllerSnapshot(
            bootstrapState: .awaitingBootstrap,
            currentInstalledPackageIDs: [],
            pendingPaidPackageIDs: Self.paidPackageIDs,
            outdatedPackages: [],
            protectedNewerPackages: [],
            remainingMaximumInstalledBytes: Self.maximumBytes(for: Self.paidPackageIDs),
            installationState: .idle,
            systemTransferState: .idle
        )
        assertProjectionError(.invalidAwaitingBootstrapSnapshot, snapshot: malformed)
    }

    func testUnknownDuplicateAndReorderedInstalledIDsAreRejected() {
        let malformedIDs: [[PackageID]] = [
            ["unknown-package"],
            [Self.paidPackageIDs[0], Self.paidPackageIDs[0]],
            [Self.paidPackageIDs[2], Self.paidPackageIDs[1]],
            [Self.paidPackageIDs[0], LaunchContent.essentialPackageID],
        ]

        for ids in malformedIDs {
            let pending = Self.paidPackageIDs.filter { !Set(ids).contains($0) }
            assertProjectionError(
                .nonCanonicalInstalledPackageIDs(ids),
                snapshot: Self.readySnapshot(installed: ids, pending: pending)
            )
        }
    }

    func testUnknownDuplicateReorderedAndEssentialPendingIDsAreRejected() {
        let malformedIDs: [[PackageID]] = [
            ["unknown-package"],
            [Self.paidPackageIDs[0], Self.paidPackageIDs[0]],
            [Self.paidPackageIDs[2], Self.paidPackageIDs[1]],
            [LaunchContent.essentialPackageID],
        ]

        for ids in malformedIDs {
            assertProjectionError(
                .nonCanonicalPendingPackageIDs(ids),
                snapshot: Self.readySnapshot(installed: [], pending: ids)
            )
        }
    }

    func testMalformedProtectedNewerPackagesAreRejected() {
        let first = Self.protectedVersion(for: Self.paidPackageIDs[0])
        let second = Self.protectedVersion(for: Self.paidPackageIDs[1])
        let malformedOrder = [second, first]
        assertProjectionError(
            .nonCanonicalProtectedNewerPackageIDs(malformedOrder.map(\.packageID)),
            snapshot: Self.readySnapshot(
                pending: Array(Self.paidPackageIDs.dropFirst(2)),
                protectedNewer: malformedOrder
            )
        )

        let invalidVersion = ProtectedNewerPackageVersion(
            packageID: first.packageID,
            installedVersion: first.expectedVersion,
            expectedVersion: first.expectedVersion
        )
        assertProjectionError(
            .invalidProtectedNewerPackageVersion(invalidVersion),
            snapshot: Self.readySnapshot(
                pending: Array(Self.paidPackageIDs.dropFirst()),
                protectedNewer: [invalidVersion]
            )
        )
    }

    func testMalformedOutdatedPackagesAreRejected() {
        let first = Self.outdatedVersion(for: Self.paidPackageIDs[0])
        let second = Self.outdatedVersion(for: Self.paidPackageIDs[1])
        let malformedOrder = [second, first]
        assertProjectionError(
            .nonCanonicalOutdatedPackageIDs(malformedOrder.map(\.packageID)),
            snapshot: Self.readySnapshot(outdated: malformedOrder)
        )

        let invalidVersion = OutdatedPackageVersion(
            packageID: first.packageID,
            installedVersion: first.expectedVersion,
            expectedVersion: first.expectedVersion
        )
        assertProjectionError(
            .invalidOutdatedPackageVersion(invalidVersion),
            snapshot: Self.readySnapshot(outdated: [invalidVersion])
        )

        assertProjectionError(
            .outdatedPackagesAreNotPending,
            snapshot: Self.readySnapshot(
                installed: [first.packageID],
                pending: Array(Self.paidPackageIDs.dropFirst()),
                outdated: [first]
            )
        )
    }

    func testPaidInstalledPendingAndProtectedIDsMustBeAnExactDisjointPartition() {
        let overlap = [Self.paidPackageIDs[0]]
        assertProjectionError(
            .installedPendingAndProtectedPackagesDoNotPartitionPaidLaunchPackages,
            snapshot: Self.readySnapshot(installed: overlap, pending: Self.paidPackageIDs)
        )

        assertProjectionError(
            .installedPendingAndProtectedPackagesDoNotPartitionPaidLaunchPackages,
            snapshot: Self.readySnapshot(
                installed: [],
                pending: Array(Self.paidPackageIDs.dropLast())
            )
        )

        let protected = Self.protectedVersion(for: Self.paidPackageIDs[0])
        assertProjectionError(
            .installedPendingAndProtectedPackagesDoNotPartitionPaidLaunchPackages,
            snapshot: Self.readySnapshot(
                pending: Self.paidPackageIDs,
                protectedNewer: [protected]
            )
        )
    }

    func testRemainingMaximumInstalledBytesMustEqualCanonicalPendingCeilings() {
        let pending = Array(Self.paidPackageIDs.dropFirst(2))
        let installed = Array(Self.paidPackageIDs.prefix(2))
        let expected = Self.maximumBytes(for: pending)
        let malformed = DownloadControllerSnapshot(
            bootstrapState: .ready,
            currentInstalledPackageIDs: installed,
            pendingPaidPackageIDs: pending,
            outdatedPackages: [],
            protectedNewerPackages: [],
            remainingMaximumInstalledBytes: expected - 1,
            installationState: .idle,
            systemTransferState: .idle
        )

        assertProjectionError(
            .remainingMaximumInstalledBytesMismatch(expected: expected, actual: expected - 1),
            snapshot: malformed
        )
    }

    func testMalformedApplicationQueueStatesAreRejected() {
        let p = Self.paidPackageIDs
        let malformed: [PackageBatchInstallationState] = [
            .starting(packageID: "unknown", completedPackageIDs: [], totalPackageCount: 1),
            .installing(packageID: p[0], completedPackageIDs: [], totalPackageCount: 0),
            .installing(packageID: p[2], completedPackageIDs: [p[1], p[0]], totalPackageCount: 3),
            .pausingAfterCurrent(
                packageID: p[1],
                completedPackageIDs: [p[0], p[1]],
                totalPackageCount: 3
            ),
            .paused(nextPackageID: nil, completedPackageIDs: [p[0]], totalPackageCount: 2),
            .paused(nextPackageID: p[1], completedPackageIDs: [p[0]], totalPackageCount: 8),
            .awaitingExplicitRestore(
                nextPackageID: p[0],
                completedPackageIDs: [p[1]],
                totalPackageCount: 2
            ),
            .staleJournal(reason: .unknownOrRemovedPackageIDs([])),
            .staleJournal(reason: .unknownOrRemovedPackageIDs([p[0]])),
            .staleJournal(reason: .nonCanonicalPackageOrder([p[0], p[1]])),
            .staleJournal(reason: .protectedNewerPackageVersions([p[0]])),
            .completed(installedPackageIDs: [p[1], p[0]]),
            .failed(packageID: p[0], completedPackageIDs: [p[0]], failure: Self.failure),
        ]

        for state in malformed {
            assertProjectionError(
                .invalidInstallationState,
                snapshot: Self.readySnapshot(installationState: state)
            )
        }
    }

    func testNonIdleSystemTransferRequiresMatchingInstallingOrPausingQueue() {
        let active = Self.paidPackageIDs[0]
        let nonIdle: [PackageSystemTransferState] = [
            .began(packageID: active, returnedAfterObservedPause: false),
            .paused(packageID: active),
            .downloading(packageID: active, completedUnitCount: 1, totalUnitCount: 2),
            .finished(packageID: active),
            .failed(packageID: active, failure: Self.failure),
        ]

        for transfer in nonIdle {
            assertProjectionError(
                .inconsistentSystemTransferState,
                snapshot: Self.readySnapshot(systemTransferState: transfer)
            )
        }

        let installing = PackageBatchInstallationState.installing(
            packageID: active,
            completedPackageIDs: [],
            totalPackageCount: 1
        )
        assertProjectionError(
            .inconsistentSystemTransferState,
            snapshot: Self.readySnapshot(
                installationState: installing,
                systemTransferState: .paused(packageID: Self.paidPackageIDs[1])
            )
        )
    }

    func testSystemProgressCountsRemainOpaqueExactTelemetry() throws {
        let active = Self.paidPackageIDs[0]
        let installing = PackageBatchInstallationState.installing(
            packageID: active,
            completedPackageIDs: [],
            totalPackageCount: 1
        )
        let opaqueCounts: [PackageSystemTransferState] = [
            .downloading(packageID: active, completedUnitCount: -1, totalUnitCount: 100),
            .downloading(packageID: active, completedUnitCount: 0, totalUnitCount: 0),
            .downloading(packageID: active, completedUnitCount: 101, totalUnitCount: 100),
        ]

        for transfer in opaqueCounts {
            let projection = try DownloadPresentationProjection(snapshot: Self.readySnapshot(
                installationState: installing,
                systemTransferState: transfer
            ))
            XCTAssertEqual(projection.appleSystemTransferState, transfer)
            XCTAssertEqual(
                projection.allowedCommands,
                [.requestQueuePauseAfterCurrentPackage]
            )
        }
    }

    private static func readySnapshot(
        installed: [PackageID] = [],
        pending: [PackageID] = paidPackageIDs,
        outdated: [OutdatedPackageVersion] = [],
        protectedNewer: [ProtectedNewerPackageVersion] = [],
        installationState: PackageBatchInstallationState = .idle,
        systemTransferState: PackageSystemTransferState = .idle,
        refreshFailure: PackageBatchFailure? = nil
    ) -> DownloadControllerSnapshot {
        DownloadControllerSnapshot(
            bootstrapState: .ready,
            currentInstalledPackageIDs: installed,
            pendingPaidPackageIDs: pending,
            outdatedPackages: outdated,
            protectedNewerPackages: protectedNewer,
            remainingMaximumInstalledBytes: Self.maximumBytes(for: pending),
            installationState: installationState,
            systemTransferState: systemTransferState,
            refreshFailure: refreshFailure
        )
    }

    private static func maximumBytes(for packageIDs: [PackageID]) -> Int64 {
        let packageByID = Dictionary(
            uniqueKeysWithValues: LaunchContent.collectionManifest.packages.map { ($0.id, $0) }
        )
        return packageIDs.reduce(into: Int64(0)) { total, packageID in
            total += packageByID[packageID]?.maximumInstalledBytes ?? 0
        }
    }

    private static func protectedVersion(
        for packageID: PackageID
    ) -> ProtectedNewerPackageVersion {
        let package = LaunchContent.collectionManifest.packages.first {
            $0.id == packageID
        }!
        return ProtectedNewerPackageVersion(
            packageID: packageID,
            installedVersion: SchemaVersion(
                major: package.version.major + 1,
                minor: package.version.minor,
                patch: package.version.patch
            ),
            expectedVersion: package.version
        )
    }

    private static func outdatedVersion(
        for packageID: PackageID
    ) -> OutdatedPackageVersion {
        let package = LaunchContent.collectionManifest.packages.first {
            $0.id == packageID
        }!
        return OutdatedPackageVersion(
            packageID: packageID,
            installedVersion: SchemaVersion(major: 0),
            expectedVersion: package.version
        )
    }

    private func assertProjectionError(
        _ expected: DownloadPresentationProjectionError,
        snapshot: DownloadControllerSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try DownloadPresentationProjection(snapshot: snapshot),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? DownloadPresentationProjectionError,
                expected,
                file: file,
                line: line
            )
        }
    }
}
