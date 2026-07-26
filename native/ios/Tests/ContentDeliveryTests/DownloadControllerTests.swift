@testable import ContentDelivery
import ContentKit
import ExperiencePreferences
import Foundation
import XCTest

final class DownloadControllerTests: XCTestCase {
    func testBootstrapDerivesExactCanonicalPaidPlanAndStorageBudget() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }

        let snapshot = try await fixture.controller.bootstrap()

        XCTAssertEqual(snapshot.bootstrapState, .ready)
        XCTAssertEqual(snapshot.currentInstalledPackageIDs, [])
        XCTAssertEqual(snapshot.pendingPaidPackageIDs, Self.paidPackages.map(\.id))
        XCTAssertEqual(snapshot.outdatedPackages, [])
        XCTAssertEqual(snapshot.protectedNewerPackages, [])
        XCTAssertEqual(
            snapshot.remainingMaximumInstalledBytes,
            Self.paidPackages.reduce(Int64(0)) { $0 + $1.maximumInstalledBytes }
        )
        XCTAssertEqual(snapshot.installationState, .idle)
        XCTAssertEqual(snapshot.systemTransferState, .idle)
        XCTAssertEqual(try fixture.journalStore.load(), nil)
    }

    func testBootstrapWithEveryCurrentPaidPackageHasNoPendingWork() async throws {
        let fixture = try makeFixture(initialIndex: Self.installedIndex(for: Self.paidPackages))
        defer { fixture.removeTemporaryFiles() }

        let snapshot = try await fixture.controller.bootstrap()
        let result = try await fixture.controller.requestDownloadAll()

        XCTAssertEqual(snapshot.currentInstalledPackageIDs, Self.paidPackages.map(\.id))
        XCTAssertEqual(snapshot.pendingPaidPackageIDs, [])
        XCTAssertEqual(snapshot.outdatedPackages, [])
        XCTAssertEqual(snapshot.protectedNewerPackages, [])
        XCTAssertEqual(snapshot.remainingMaximumInstalledBytes, 0)
        XCTAssertEqual(result, .noOperation(reason: .nothingPending))
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])
        XCTAssertEqual(try fixture.journalStore.load(), nil)
    }

    func testNewerActivePackageIsProtectedAndExcludedFromEveryDownloadRequest() async throws {
        let expected = Self.paidPackages[0]
        let newerVersion = SchemaVersion(
            major: expected.version.major + 1,
            minor: expected.version.minor,
            patch: expected.version.patch
        )
        let newer = ContentPackageSpec(
            id: expected.id,
            version: newerVersion,
            chapterIDs: expected.chapterIDs,
            maximumInstalledBytes: expected.maximumInstalledBytes,
            minimumRuntime: expected.minimumRuntime,
            isEssentialInstall: false
        )
        let fixture = try makeFixture(initialIndex: Self.installedIndex(for: [newer]))
        defer { fixture.removeTemporaryFiles() }

        let snapshot = try await fixture.controller.bootstrap()
        let pending = Array(Self.paidPackages.dropFirst())

        XCTAssertFalse(snapshot.currentInstalledPackageIDs.contains(expected.id))
        XCTAssertEqual(snapshot.pendingPaidPackageIDs, pending.map(\.id))
        XCTAssertEqual(snapshot.outdatedPackages, [])
        XCTAssertEqual(snapshot.protectedNewerPackages, [
            ProtectedNewerPackageVersion(
                packageID: expected.id,
                installedVersion: newerVersion,
                expectedVersion: expected.version
            ),
        ])
        XCTAssertEqual(
            snapshot.remainingMaximumInstalledBytes,
            pending.reduce(Int64(0)) { $0 + $1.maximumInstalledBytes }
        )

        let single = try await fixture.controller.requestSinglePackage(expected.id)
        XCTAssertEqual(
            single,
            .noOperation(reason: .newerVersionRequiresNewerApp)
        )
        XCTAssertEqual(try fixture.journalStore.load(), nil)

        let all = try await fixture.controller.requestDownloadAll()
        XCTAssertEqual(all, .started(packageIDs: pending.map(\.id)))
        assertControllerTrue(await eventually {
            await fixture.installHarness.packageIDs() == pending.map(\.id)
        })
        let requestedPackageIDs = await fixture.installHarness.packageIDs()
        XCTAssertFalse(requestedPackageIDs.contains(expected.id))
    }

    func testOlderActivePackageIsExposedAsAnUpdateAndInstallsTheExpectedVersion() async throws {
        let expected = Self.paidPackages[0]
        let older = ContentPackageSpec(
            id: expected.id,
            version: SchemaVersion(major: 0),
            chapterIDs: expected.chapterIDs,
            maximumInstalledBytes: expected.maximumInstalledBytes,
            minimumRuntime: expected.minimumRuntime,
            isEssentialInstall: false
        )
        let fixture = try makeFixture(initialIndex: Self.installedIndex(for: [older]))
        defer { fixture.removeTemporaryFiles() }

        let snapshot = try await fixture.controller.bootstrap()

        XCTAssertFalse(snapshot.currentInstalledPackageIDs.contains(expected.id))
        XCTAssertTrue(snapshot.pendingPaidPackageIDs.contains(expected.id))
        XCTAssertEqual(snapshot.outdatedPackages, [
            OutdatedPackageVersion(
                packageID: expected.id,
                installedVersion: older.version,
                expectedVersion: expected.version
            ),
        ])
        XCTAssertEqual(snapshot.protectedNewerPackages, [])

        let result = try await fixture.controller.requestSinglePackage(expected.id)
        XCTAssertEqual(result, .started(packageIDs: [expected.id]))
        assertControllerTrue(await eventually {
            await fixture.installHarness.installedPackages().contains(expected)
        })
    }

    func testExplicitSingleStartsOnlyTheSelectedPendingPaidPackageAndRefreshesPlan() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        let selected = Self.paidPackages[2]
        await fixture.installHarness.block(selected.id)
        _ = try await fixture.controller.bootstrap()

        let result = try await fixture.controller.requestSinglePackage(selected.id)

        XCTAssertEqual(result, .started(packageIDs: [selected.id]))
        XCTAssertEqual(try fixture.journalStore.load()?.packages.map(\.id), [selected.id])
        assertControllerTrue(await eventually {
            await fixture.installHarness.packageIDs() == [selected.id]
        })

        await fixture.installHarness.release(selected.id)
        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().installationState
                == .completed(installedPackageIDs: [selected.id])
        })
        assertControllerTrue(await eventually {
            let snapshot = await fixture.controller.snapshot()
            return !snapshot.pendingPaidPackageIDs.contains(selected.id)
                && snapshot.currentInstalledPackageIDs.contains(selected.id)
        })
    }

    func testSingleIDNoOperationsAreExplicitAndNeverCreateAQueue() async throws {
        let current = Self.paidPackages[0]
        let nonLaunchID: PackageID = "deep-dive-constantinople"
        let fixture = try makeFixture(
            initialIndex: Self.installedIndex(for: [current]),
            knownNonLaunchPackageIDs: [nonLaunchID]
        )
        defer { fixture.removeTemporaryFiles() }
        _ = try await fixture.controller.bootstrap()

        let essential = try await fixture.controller.requestSinglePackage(
            LaunchContent.essentialPackageID
        )
        let alreadyCurrent = try await fixture.controller.requestSinglePackage(current.id)
        let nonLaunch = try await fixture.controller.requestSinglePackage(nonLaunchID)
        let unknown = try await fixture.controller.requestSinglePackage("missing-package")

        XCTAssertEqual(essential, .noOperation(reason: .essentialPackage))
        XCTAssertEqual(alreadyCurrent, .noOperation(reason: .alreadyCurrent))
        XCTAssertEqual(nonLaunch, .noOperation(reason: .nonLaunchPackage))
        XCTAssertEqual(unknown, .noOperation(reason: .unknownPackage))
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])
        XCTAssertEqual(try fixture.journalStore.load(), nil)
    }

    func testSingleRequestRereadsAnIndexThatChangedAfterBootstrap() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        let package = Self.paidPackages[0]
        _ = try await fixture.controller.bootstrap()
        _ = try await fixture.installedIndexStore.activate(package)

        let result = try await fixture.controller.requestSinglePackage(package.id)

        XCTAssertEqual(result, .noOperation(reason: .alreadyCurrent))
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])
        XCTAssertEqual(try fixture.journalStore.load(), nil)
        let refreshed = await fixture.controller.snapshot()
        XCTAssertFalse(refreshed.pendingPaidPackageIDs.contains(package.id))
    }

    func testDownloadAllUsesCanonicalOrderThenRefreshesToAnEmptyPlan() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        _ = try await fixture.controller.bootstrap()

        let result = try await fixture.controller.requestDownloadAll()

        XCTAssertEqual(result, .started(packageIDs: Self.paidPackages.map(\.id)))
        assertControllerTrue(await eventually {
            await fixture.installHarness.packageIDs() == Self.paidPackages.map(\.id)
        })
        assertControllerTrue(await eventually {
            let snapshot = await fixture.controller.snapshot()
            return snapshot.pendingPaidPackageIDs.isEmpty
                && snapshot.remainingMaximumInstalledBytes == 0
                && snapshot.installationState
                    == .completed(installedPackageIDs: Self.paidPackages.map(\.id))
        })
        XCTAssertEqual(try fixture.journalStore.load()?.intent, .completed)
        XCTAssertEqual(
            try fixture.journalStore.load()?.packages.map(\.id),
            Self.paidPackages.map(\.id)
        )
    }

    func testOfflineCellularAndExpensiveBlocksHaveNoQueueSideEffect() async throws {
        let cases: [(DownloadNetworkContext, ExperiencePreferences,
                     DownloadInitiationBlockReason)] = [
            (.init(basis: .offline), .standard, .offline),
            (.init(basis: .cellular), .standard, .cellularDownloadsDisabled),
            // The system monitor maps an expensive Wi-Fi or wired path to the
            // cellular basis before the controller sees it.
            (.init(basis: .cellular, isConstrained: true), .standard,
             .cellularDownloadsDisabled),
            (.unknown, .standard, .unknownNetwork),
        ]

        for (network, preferences, expectedReason) in cases {
            let fixture = try makeFixture(networkContext: network, preferences: preferences)
            defer { fixture.removeTemporaryFiles() }
            _ = try await fixture.controller.bootstrap()

            let result = try await fixture.controller.requestDownloadAll()

            XCTAssertEqual(result, .blocked(reason: expectedReason))
            assertControllerEqual(await fixture.installHarness.packageIDs(), [])
            XCTAssertEqual(try fixture.journalStore.load(), nil)
            assertControllerEqual(await fixture.installedIndexStore.loadCount(), 3)
        }
    }

    func testCurrentPreferencesAndLowDataContextAreReadImmediatelyBeforeExplicitStart()
        async throws
    {
        let fixture = try makeFixture(
            networkContext: .init(basis: .cellular, isConstrained: true),
            preferences: .standard
        )
        defer { fixture.removeTemporaryFiles() }
        await fixture.installHarness.block(Self.paidPackages[0].id)
        _ = try await fixture.controller.bootstrap()

        let blocked = try await fixture.controller.requestDownloadAll()
        await fixture.preferencesSource.set(ExperiencePreferences(
            cellularDownloadsEnabled: true
        ))
        let started = try await fixture.controller.requestDownloadAll()

        XCTAssertEqual(blocked, .blocked(reason: .cellularDownloadsDisabled))
        XCTAssertEqual(started, .started(packageIDs: Self.paidPackages.map(\.id)))
        XCTAssertEqual(fixture.networkProvider.readCount, 2)
        assertControllerEqual(await fixture.preferencesSource.readCount(), 4)

        await fixture.installHarness.release(Self.paidPackages[0].id)
        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().installationState
                == .completed(installedPackageIDs: Self.paidPackages.map(\.id))
        })

        let lowDataWiFi = try makeFixture(
            networkContext: .init(basis: .wifi, isConstrained: true)
        )
        defer { lowDataWiFi.removeTemporaryFiles() }
        _ = try await lowDataWiFi.controller.bootstrap()
        let explicit = try await lowDataWiFi.controller.requestSinglePackage(
            Self.paidPackages[0].id
        )
        XCTAssertEqual(explicit, .started(packageIDs: [Self.paidPackages[0].id]))
    }

    func testConcurrentNewRequestsCannotBypassAlreadyRunningInstaller() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        await fixture.installHarness.block(Self.paidPackages[0].id)
        _ = try await fixture.controller.bootstrap()

        async let first = fixture.controller.requestDownloadAll()
        async let second = fixture.controller.requestDownloadAll()
        let results = try await [first, second]

        XCTAssertEqual(
            results.filter {
                if case .started = $0 { return true }
                return false
            }.count,
            1
        )
        XCTAssertEqual(
            results.filter {
                $0 == .installerRejected(reason: .alreadyRunning)
                    || $0 == .installerRejected(reason: .unresolvedQueue)
            }.count,
            1
        )
        XCTAssertEqual(try fixture.journalStore.load()?.packages, Self.paidPackages)

        await fixture.installHarness.release(Self.paidPackages[0].id)
        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().installationState
                == .completed(installedPackageIDs: Self.paidPackages.map(\.id))
        })
    }

    func testPauseFinishesCurrentPackageAndResumeIgnoresNewRequestNetworkPolicy() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        await fixture.installHarness.block(Self.paidPackages[0].id)
        _ = try await fixture.controller.bootstrap()
        _ = try await fixture.controller.requestDownloadAll()
        assertControllerTrue(await eventually {
            await fixture.installHarness.packageIDs() == [Self.paidPackages[0].id]
        })

        try await fixture.controller.requestPauseAfterCurrentPackage()
        fixture.networkProvider.set(.init(basis: .offline))
        await fixture.installHarness.release(Self.paidPackages[0].id)

        assertControllerTrue(await eventually {
            let snapshot = await fixture.controller.snapshot()
            return snapshot.installationState == .paused(
                nextPackageID: Self.paidPackages[1].id,
                completedPackageIDs: [Self.paidPackages[0].id],
                totalPackageCount: Self.paidPackages.count
            ) && !snapshot.pendingPaidPackageIDs.contains(Self.paidPackages[0].id)
        })
        let networkReadsBeforeResume = fixture.networkProvider.readCount
        let preferenceReadsBeforeResume = await fixture.preferencesSource.readCount()

        try await fixture.controller.resumeQueue()

        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().installationState
                == .completed(installedPackageIDs: Self.paidPackages.map(\.id))
        })
        XCTAssertEqual(fixture.networkProvider.readCount, networkReadsBeforeResume)
        assertControllerEqual(
            await fixture.preferencesSource.readCount(),
            preferenceReadsBeforeResume
        )
    }

    func testStickyFailureRefreshesPlanAndRetryUsesExistingQueue() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        await fixture.installHarness.failNext(Self.paidPackages[1].id)
        _ = try await fixture.controller.bootstrap()
        _ = try await fixture.controller.requestDownloadAll()

        assertControllerTrue(await eventually {
            if case .failed = await fixture.controller.snapshot().installationState {
                return true
            }
            return false
        })
        XCTAssertEqual(try fixture.journalStore.load()?.intent, .failed)
        assertControllerEqual(
            await fixture.controller.snapshot().pendingPaidPackageIDs,
            Array(Self.paidPackages.dropFirst()).map(\.id)
        )

        fixture.networkProvider.set(.init(basis: .offline))
        let networkReads = fixture.networkProvider.readCount
        try await fixture.controller.retryFailedPackage()

        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().installationState
                == .completed(installedPackageIDs: Self.paidPackages.map(\.id))
        })
        assertControllerEqual(
            await fixture.installHarness.packageIDs(),
            Array(Self.paidPackages.prefix(2)).map(\.id)
                + Array(Self.paidPackages.dropFirst()).map(\.id)
        )
        XCTAssertEqual(fixture.networkProvider.readCount, networkReads)
    }

    func testRemoveFailedDropsOnlyQueueHeadThenPlanKeepsItPending() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        await fixture.installHarness.failNext(Self.paidPackages[0].id)
        _ = try await fixture.controller.bootstrap()
        _ = try await fixture.controller.requestDownloadAll()
        assertControllerTrue(await eventually {
            if case .failed = await fixture.controller.snapshot().installationState {
                return true
            }
            return false
        })

        try await fixture.controller.removeFailedPackage()

        assertControllerTrue(await eventually {
            let snapshot = await fixture.controller.snapshot()
            return snapshot.installationState == .completed(
                installedPackageIDs: Array(Self.paidPackages.dropFirst()).map(\.id)
            ) && snapshot.pendingPaidPackageIDs == [Self.paidPackages[0].id]
        })
        assertControllerEqual(
            await fixture.installHarness.packageIDs(),
            Self.paidPackages.map(\.id)
        )
        XCTAssertEqual(
            try fixture.journalStore.load()?.packages.map(\.id),
            Array(Self.paidPackages.dropFirst()).map(\.id)
        )
    }

    func testColdRunningJournalRequiresExplicitResumeEvenWhenNetworkIsOffline() async throws {
        let packages = Array(Self.paidPackages.prefix(2))
        let fixture = try makeFixture(networkContext: .init(basis: .offline)) { store in
            try store.save(PackageBatchQueueJournal(
                intent: .running,
                packages: packages,
                completedPackageIDs: []
            ))
        }
        defer { fixture.removeTemporaryFiles() }

        let snapshot = try await fixture.controller.bootstrap()

        XCTAssertEqual(snapshot.installationState, .awaitingExplicitRestore(
            nextPackageID: packages[0].id,
            completedPackageIDs: [],
            totalPackageCount: packages.count
        ))
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])
        try await fixture.controller.resumeQueue()
        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().installationState
                == .completed(installedPackageIDs: packages.map(\.id))
        })
        XCTAssertEqual(fixture.networkProvider.readCount, 0)
        assertControllerEqual(await fixture.preferencesSource.readCount(), 0)
    }

    func testColdPausedJournalRemainsPausedUntilExplicitResume() async throws {
        let packages = Array(Self.paidPackages.prefix(2))
        let firstInstalled = Self.installedIndex(for: [packages[0]])
        let fixture = try makeFixture(
            initialIndex: firstInstalled,
            networkContext: .init(basis: .offline)
        ) { store in
            try store.save(PackageBatchQueueJournal(
                intent: .paused,
                packages: packages,
                completedPackageIDs: [packages[0].id]
            ))
        }
        defer { fixture.removeTemporaryFiles() }

        let snapshot = try await fixture.controller.bootstrap()

        XCTAssertEqual(snapshot.installationState, .paused(
            nextPackageID: packages[1].id,
            completedPackageIDs: [packages[0].id],
            totalPackageCount: packages.count
        ))
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])
        try await fixture.controller.resumeQueue()
        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().installationState
                == .completed(installedPackageIDs: packages.map(\.id))
        })
        assertControllerEqual(
            await fixture.installHarness.packageIDs(),
            [packages[1].id]
        )
        XCTAssertEqual(fixture.networkProvider.readCount, 0)
    }

    func testColdFailedJournalRestoresStickyHeadAndRetryDoesNotRecheckNetwork() async throws {
        let packages = Array(Self.paidPackages.prefix(2))
        let failure = PackageBatchFailure(domain: "test.cold", code: 41)
        let fixture = try makeFixture(networkContext: .init(basis: .offline)) { store in
            try store.save(PackageBatchQueueJournal(
                intent: .failed,
                packages: packages,
                completedPackageIDs: [],
                failedPackageID: packages[0].id,
                failure: failure
            ))
        }
        defer { fixture.removeTemporaryFiles() }

        let snapshot = try await fixture.controller.bootstrap()

        XCTAssertEqual(snapshot.installationState, .failed(
            packageID: packages[0].id,
            completedPackageIDs: [],
            failure: failure
        ))
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])
        try await fixture.controller.retryFailedPackage()
        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().installationState
                == .completed(installedPackageIDs: packages.map(\.id))
        })
        XCTAssertEqual(fixture.networkProvider.readCount, 0)
    }

    func testLegacyJournalSpecsMigrateByPackageIDAndStillRequireExplicitResume() async throws {
        let currentPackages = [Self.paidPackages[0], Self.paidPackages[2]]
        let legacyPackages = currentPackages.map { package in
            ContentPackageSpec(
                id: package.id,
                version: .init(major: 0, minor: 9),
                chapterIDs: Array(package.chapterIDs.reversed()),
                maximumInstalledBytes: package.maximumInstalledBytes - 1,
                minimumRuntime: .init(major: 0),
                isEssentialInstall: package.isEssentialInstall
            )
        }
        let fixture = try makeFixture { store in
            try store.save(PackageBatchQueueJournal(
                intent: .running,
                packages: legacyPackages,
                completedPackageIDs: []
            ))
        }
        defer { fixture.removeTemporaryFiles() }

        let snapshot = try await fixture.controller.bootstrap()

        XCTAssertEqual(snapshot.installationState, .awaitingExplicitRestore(
            nextPackageID: currentPackages[0].id,
            completedPackageIDs: [],
            totalPackageCount: currentPackages.count
        ))
        XCTAssertEqual(try fixture.journalStore.load()?.packages, currentPackages)
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])

        try await fixture.controller.resumeQueue()

        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().installationState
                == .completed(installedPackageIDs: currentPackages.map(\.id))
        })
        assertControllerEqual(
            await fixture.installHarness.installedPackages(),
            currentPackages
        )
    }

    func testUnknownOrRemovedJournalPackageSurfacesStaleStateWithoutStarting() async throws {
        let retiredPackage = ContentPackageSpec(
            id: "retired-paid-pack",
            version: .init(major: 1),
            chapterIDs: ["retired-chapter"],
            maximumInstalledBytes: 1,
            minimumRuntime: .init(major: 1),
            isEssentialInstall: false
        )
        let fixture = try makeFixture { store in
            try store.save(PackageBatchQueueJournal(
                intent: .running,
                packages: [retiredPackage],
                completedPackageIDs: []
            ))
        }
        defer { fixture.removeTemporaryFiles() }

        let snapshot = try await fixture.controller.bootstrap()

        XCTAssertEqual(snapshot.installationState, .staleJournal(
            reason: .unknownOrRemovedPackageIDs([retiredPackage.id])
        ))
        XCTAssertEqual(try fixture.journalStore.load()?.packages, [retiredPackage])
        try await fixture.controller.resumeQueue()
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])

        try await fixture.controller.discardStaleQueue()

        let clearedSnapshot = await fixture.controller.snapshot()
        XCTAssertEqual(clearedSnapshot.installationState, .idle)
        XCTAssertEqual(try fixture.journalStore.load()?.intent, .completed)
        XCTAssertEqual(try fixture.journalStore.load()?.packages, [])
        let restarted = try await fixture.controller.requestSinglePackage(
            Self.paidPackages[0].id
        )
        XCTAssertEqual(restarted, .started(packageIDs: [Self.paidPackages[0].id]))
        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().currentInstalledPackageIDs
                .contains(Self.paidPackages[0].id)
        })
    }

    func testMisorderedJournalSurfacesStaleStateWithoutRewritingIntent() async throws {
        let misordered = [Self.paidPackages[1], Self.paidPackages[0]]
        let fixture = try makeFixture { store in
            try store.save(PackageBatchQueueJournal(
                intent: .running,
                packages: misordered,
                completedPackageIDs: []
            ))
        }
        defer { fixture.removeTemporaryFiles() }

        let snapshot = try await fixture.controller.bootstrap()

        XCTAssertEqual(snapshot.installationState, .staleJournal(
            reason: .nonCanonicalPackageOrder(misordered.map(\.id))
        ))
        XCTAssertEqual(try fixture.journalStore.load()?.packages, misordered)
        try await fixture.controller.resumeQueue()
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])
    }

    func testPreferenceMutationDuringAwaitIsObservedBeforeNetworkAndBlocksStart() async throws {
        let fixture = try makeFixture(
            networkContext: .init(basis: .cellular),
            preferences: ExperiencePreferences(cellularDownloadsEnabled: true)
        )
        defer { fixture.removeTemporaryFiles() }
        _ = try await fixture.controller.bootstrap()
        await fixture.preferencesSource.blockLoad(1)

        let request = Task {
            try await fixture.controller.requestDownloadAll()
        }
        assertControllerTrue(await eventually {
            await fixture.preferencesSource.isLoadBlocked(1)
        })
        await fixture.preferencesSource.set(.standard)
        await fixture.preferencesSource.releaseLoad(1)

        assertControllerEqual(
            try await request.value,
            .blocked(reason: .cellularDownloadsDisabled)
        )
        XCTAssertEqual(fixture.networkProvider.readCount, 1)
        assertControllerTrue(await fixture.preferencesSource.readCount() >= 3)
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])
        XCTAssertEqual(try fixture.journalStore.load(), nil)
    }

    func testIndexMutationDuringAwaitPreventsRedundantStart() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        let package = Self.paidPackages[0]
        _ = try await fixture.controller.bootstrap()
        await fixture.installedIndexStore.blockLoad(2)

        let request = Task {
            try await fixture.controller.requestSinglePackage(package.id)
        }
        assertControllerTrue(await eventually {
            await fixture.installedIndexStore.isLoadBlocked(2)
        })
        _ = try await fixture.installedIndexStore.activate(package)
        await fixture.installedIndexStore.releaseLoad(2)

        assertControllerEqual(
            try await request.value,
            .noOperation(reason: .alreadyCurrent)
        )
        XCTAssertEqual(fixture.networkProvider.readCount, 0)
        assertControllerEqual(await fixture.installHarness.packageIDs(), [])
        XCTAssertEqual(try fixture.journalStore.load(), nil)
        assertControllerTrue(await fixture.installedIndexStore.loadCount() >= 4)
    }

    func testOlderRefreshCannotOverwriteNewerInstalledIndexResult() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        let first = Self.paidPackages[0]
        let second = Self.paidPackages[1]
        await fixture.installHarness.block(first.id)
        _ = try await fixture.controller.bootstrap()
        _ = try await fixture.controller.requestSinglePackage(first.id)
        await fixture.installedIndexStore.blockLoad(4)

        await fixture.installHarness.release(first.id)
        assertControllerTrue(await eventually {
            await fixture.installedIndexStore.isLoadBlocked(4)
        })
        _ = try await fixture.installedIndexStore.activate(second)

        assertControllerEqual(
            try await fixture.controller.requestSinglePackage(second.id),
            .noOperation(reason: .alreadyCurrent)
        )
        var snapshot = await fixture.controller.snapshot()
        XCTAssertTrue(snapshot.currentInstalledPackageIDs.contains(first.id))
        XCTAssertTrue(snapshot.currentInstalledPackageIDs.contains(second.id))

        await fixture.installedIndexStore.releaseLoad(4)
        assertControllerTrue(await eventually {
            !(await fixture.installedIndexStore.isLoadBlocked(4))
        })
        for _ in 0 ..< 100 { await Task.yield() }
        snapshot = await fixture.controller.snapshot()
        XCTAssertTrue(snapshot.currentInstalledPackageIDs.contains(first.id))
        XCTAssertTrue(snapshot.currentInstalledPackageIDs.contains(second.id))
        XCTAssertFalse(snapshot.pendingPaidPackageIDs.contains(second.id))
    }

    func testTerminalRefreshFailureIsMachineReadableAndClearsAfterFreshSuccess() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        let package = Self.paidPackages[0]
        await fixture.installHarness.block(package.id)
        _ = try await fixture.controller.bootstrap()
        _ = try await fixture.controller.requestSinglePackage(package.id)
        await fixture.installedIndexStore.failLoad(4)

        await fixture.installHarness.release(package.id)

        let expectedFailure = PackageBatchFailure(
            domain: ControllerIndexLoadError.errorDomain,
            code: ControllerIndexLoadError.unavailable.errorCode
        )
        assertControllerTrue(await eventually {
            let snapshot = await fixture.controller.snapshot()
            return snapshot.installationState
                == .completed(installedPackageIDs: [package.id])
                && snapshot.refreshFailure == expectedFailure
        })
        var snapshot = await fixture.controller.snapshot()
        XCTAssertTrue(snapshot.pendingPaidPackageIDs.contains(package.id))

        snapshot = try await fixture.controller.refresh()
        XCTAssertNil(snapshot.refreshFailure)
        XCTAssertFalse(snapshot.pendingPaidPackageIDs.contains(package.id))
    }

    func testConcurrentBootstrapCallsShareOneRestoreFlight() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }
        await fixture.installedIndexStore.blockLoad(1)

        let first = Task { try await fixture.controller.bootstrap() }
        let second = Task { try await fixture.controller.bootstrap() }
        assertControllerTrue(await eventually {
            await fixture.installedIndexStore.isLoadBlocked(1)
        })
        for _ in 0 ..< 100 { await Task.yield() }
        assertControllerEqual(await fixture.installedIndexStore.loadCount(), 1)

        await fixture.installedIndexStore.releaseLoad(1)
        let snapshots = try await [first.value, second.value]

        XCTAssertEqual(snapshots[0], snapshots[1])
        XCTAssertEqual(snapshots[0].bootstrapState, .ready)
        assertControllerEqual(await fixture.installedIndexStore.loadCount(), 1)
        XCTAssertEqual(try fixture.journalStore.load(), nil)
    }

    func testInstallerAndSystemTransferStreamsFormOneControllerSnapshot() async throws {
        let transferEmitter = ControllerTransferEmitter()
        let fixture = try makeFixture(transferEmitter: transferEmitter)
        defer { fixture.removeTemporaryFiles() }
        let package = Self.paidPackages[0]
        await fixture.installHarness.block(package.id)
        _ = try await fixture.controller.bootstrap()
        _ = try await fixture.controller.requestSinglePackage(package.id)
        assertControllerTrue(await eventually { transferEmitter.hasSubscriber(for: package.id) })

        transferEmitter.emit(
            .downloading(completedUnitCount: 25, totalUnitCount: 100),
            for: package.id
        )

        assertControllerTrue(await eventually {
            let snapshot = await fixture.controller.snapshot()
            return snapshot.installationState == .installing(
                packageID: package.id,
                completedPackageIDs: [],
                totalPackageCount: 1
            ) && snapshot.systemTransferState == .downloading(
                packageID: package.id,
                completedUnitCount: 25,
                totalUnitCount: 100
            )
        })
        await fixture.installHarness.release(package.id)
        assertControllerTrue(await eventually {
            let snapshot = await fixture.controller.snapshot()
            return snapshot.installationState
                == .completed(installedPackageIDs: [package.id])
                && snapshot.systemTransferState == .idle
        })
    }

    func testNextPackageAndTerminalSnapshotCannotRetainPriorTransferProgress() async throws {
        let transferEmitter = ControllerTransferEmitter()
        let fixture = try makeFixture(transferEmitter: transferEmitter)
        defer { fixture.removeTemporaryFiles() }
        let packages = Array(Self.paidPackages.prefix(2))
        await fixture.installHarness.block(packages[0].id)
        await fixture.installHarness.block(packages[1].id)
        _ = try await fixture.controller.bootstrap()
        _ = try await fixture.controller.requestDownloadAll()
        assertControllerTrue(await eventually {
            transferEmitter.hasSubscriber(for: packages[0].id)
        })
        transferEmitter.emit(
            .downloading(completedUnitCount: 70, totalUnitCount: 100),
            for: packages[0].id
        )
        assertControllerTrue(await eventually {
            await fixture.controller.snapshot().systemTransferState == .downloading(
                packageID: packages[0].id,
                completedUnitCount: 70,
                totalUnitCount: 100
            )
        })

        await fixture.installHarness.release(packages[0].id)
        assertControllerTrue(await eventually {
            let snapshot = await fixture.controller.snapshot()
            return snapshot.installationState == .installing(
                packageID: packages[1].id,
                completedPackageIDs: [packages[0].id],
                totalPackageCount: Self.paidPackages.count
            ) && snapshot.systemTransferState == .idle
        })
        transferEmitter.emit(
            .downloading(completedUnitCount: 99, totalUnitCount: 100),
            for: packages[0].id
        )
        for _ in 0 ..< 100 { await Task.yield() }
        assertControllerEqual(await fixture.controller.snapshot().systemTransferState, .idle)

        await fixture.installHarness.release(packages[1].id)
        assertControllerTrue(await eventually {
            let snapshot = await fixture.controller.snapshot()
            return snapshot.installationState
                == .completed(installedPackageIDs: Self.paidPackages.map(\.id))
                && snapshot.systemTransferState == .idle
        })
    }

    func testRequestsBeforeBootstrapFailWithoutReadingPolicyInputs() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryFiles() }

        do {
            _ = try await fixture.controller.requestDownloadAll()
            XCTFail("Expected bootstrap requirement")
        } catch {
            XCTAssertEqual(error as? DownloadControllerError, .bootstrapRequired)
        }

        XCTAssertEqual(fixture.networkProvider.readCount, 0)
        assertControllerEqual(await fixture.preferencesSource.readCount(), 0)
        assertControllerEqual(await fixture.installedIndexStore.loadCount(), 0)
        XCTAssertEqual(try fixture.journalStore.load(), nil)
    }

    private static let paidPackages: [ContentPackageSpec] = {
        let packageByID = Dictionary(
            uniqueKeysWithValues: LaunchContent.collectionManifest.packages.map { ($0.id, $0) }
        )
        return Array(LaunchContent.packageIDsInDeliveryOrder.dropFirst()).compactMap {
            packageByID[$0]
        }
    }()

    private static func installedIndex(
        for packages: [ContentPackageSpec]
    ) -> InstalledPackageIndex {
        let generations = packages.enumerated().map { offset, package in
            InstalledPackageGeneration(
                generationID: "\(package.id.rawValue)-test-\(offset + 1)",
                packageID: package.id,
                packageVersion: package.version,
                manifestDigest: String(repeating: "a", count: 64),
                relativePath: "generations/\(package.id.rawValue)-test-\(offset + 1)",
                activationSequence: UInt64(offset + 1)
            )
        }
        return InstalledPackageIndex(
            nextActivationSequence: UInt64(generations.count + 1),
            generations: generations,
            activeGenerationByPackage: Dictionary(
                uniqueKeysWithValues: generations.map { ($0.packageID, $0.generationID) }
            )
        )
    }

    private func makeFixture(
        initialIndex: InstalledPackageIndex = .empty,
        networkContext: DownloadNetworkContext = .init(basis: .wifi),
        preferences: ExperiencePreferences = .standard,
        knownNonLaunchPackageIDs: Set<PackageID> = [],
        transferEmitter: ControllerTransferEmitter? = nil,
        journalSetup: ((PackageBatchQueueJournalStore) throws -> Void)? = nil
    ) throws -> ControllerFixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "download-controller-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let journalStore = try PackageBatchQueueJournalStore(
            directoryURL: root.appending(path: "queue", directoryHint: .isDirectory)
        )
        try journalSetup?(journalStore)
        let indexStore = ControllerInstalledIndexStore(initialIndex)
        let preferencesSource = ControllerPreferencesSource(preferences)
        let networkProvider = ControllerNetworkProvider(networkContext)
        let installHarness = ControllerInstallHarness(indexStore: indexStore)
        let transferUpdates: PackageBatchInstaller.TransferUpdates?
        if let transferEmitter {
            transferUpdates = { packageID in
                transferEmitter.stream(for: packageID)
            }
        } else {
            transferUpdates = nil
        }
        let installer = PackageBatchInstaller(
            installOperation: { package in
                try await installHarness.install(package)
            },
            transferUpdates: transferUpdates,
            journalStore: journalStore
        )
        let controller = DownloadController(
            installer: installer,
            networkBasisProvider: networkProvider,
            installedIndexProvider: {
                try await indexStore.load()
            },
            preferencesProvider: {
                await preferencesSource.load()
            },
            knownNonLaunchPackageIDs: knownNonLaunchPackageIDs
        )
        return ControllerFixture(
            rootURL: root,
            controller: controller,
            installer: installer,
            journalStore: journalStore,
            installedIndexStore: indexStore,
            preferencesSource: preferencesSource,
            networkProvider: networkProvider,
            installHarness: installHarness
        )
    }

    private func eventually(
        timeout: Duration = .seconds(5),
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        // Controller observations cross independent installer and controller
        // tasks. Parallel XCTest workers may consume an arbitrary number of
        // scheduler turns before both hops run, so bound elapsed time instead.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        repeat {
            if await condition() { return true }
            await Task.yield()
        } while clock.now < deadline
        return await condition()
    }
}

private struct ControllerFixture: @unchecked Sendable {
    let rootURL: URL
    let controller: DownloadController
    let installer: PackageBatchInstaller
    let journalStore: PackageBatchQueueJournalStore
    let installedIndexStore: ControllerInstalledIndexStore
    let preferencesSource: ControllerPreferencesSource
    let networkProvider: ControllerNetworkProvider
    let installHarness: ControllerInstallHarness

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private actor ControllerInstalledIndexStore {
    private var index: InstalledPackageIndex
    private var reads = 0
    private var loadsToBlock: Set<Int> = []
    private var blockedLoads: Set<Int> = []
    private var loadContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var loadsToFail: Set<Int> = []

    init(_ index: InstalledPackageIndex) {
        self.index = index
    }

    func load() async throws -> InstalledPackageIndex {
        reads += 1
        let read = reads
        let captured = index
        if loadsToBlock.remove(read) != nil {
            blockedLoads.insert(read)
            await withCheckedContinuation { continuation in
                loadContinuations[read] = continuation
            }
            blockedLoads.remove(read)
        }
        if loadsToFail.remove(read) != nil {
            throw ControllerIndexLoadError.unavailable
        }
        try captured.validate()
        return captured
    }

    func activate(_ package: ContentPackageSpec) throws -> ActivatedPackage {
        let sequence = index.nextActivationSequence
        let generationID = "\(package.id.rawValue)-controller-\(sequence)"
        let generation = InstalledPackageGeneration(
            generationID: generationID,
            packageID: package.id,
            packageVersion: package.version,
            manifestDigest: String(repeating: "b", count: 64),
            relativePath: "generations/\(generationID)",
            activationSequence: sequence
        )
        try index.recordActivation(generation)
        return ActivatedPackage(
            generation: generation,
            packageURL: URL(fileURLWithPath: "/tmp/\(generationID)", isDirectory: true)
        )
    }

    func loadCount() -> Int { reads }

    func blockLoad(_ read: Int) {
        loadsToBlock.insert(read)
    }

    func isLoadBlocked(_ read: Int) -> Bool {
        blockedLoads.contains(read)
    }

    func releaseLoad(_ read: Int) {
        loadContinuations.removeValue(forKey: read)?.resume()
    }

    func failLoad(_ read: Int) {
        loadsToFail.insert(read)
    }
}

private enum ControllerIndexLoadError: Error, CustomNSError {
    case unavailable

    static let errorDomain = "DownloadControllerTests.IndexLoad"
    var errorCode: Int { 73 }
}

private enum ControllerInstallError: Error {
    case rejected
}

private actor ControllerInstallHarness {
    private let indexStore: ControllerInstalledIndexStore
    private var calls: [ContentPackageSpec] = []
    private var blocked: Set<PackageID> = []
    private var released: Set<PackageID> = []
    private var continuations: [PackageID: CheckedContinuation<Void, Never>] = [:]
    private var remainingFailures: [PackageID: Int] = [:]

    init(indexStore: ControllerInstalledIndexStore) {
        self.indexStore = indexStore
    }

    func install(_ package: ContentPackageSpec) async throws -> ActivatedPackage {
        calls.append(package)
        if let remaining = remainingFailures[package.id], remaining > 0 {
            remainingFailures[package.id] = remaining - 1
            throw ControllerInstallError.rejected
        }
        if blocked.contains(package.id), !released.contains(package.id) {
            await withCheckedContinuation { continuation in
                continuations[package.id] = continuation
            }
        }
        return try await indexStore.activate(package)
    }

    func block(_ packageID: PackageID) {
        blocked.insert(packageID)
    }

    func release(_ packageID: PackageID) {
        released.insert(packageID)
        continuations.removeValue(forKey: packageID)?.resume()
    }

    func failNext(_ packageID: PackageID) {
        remainingFailures[packageID, default: 0] += 1
    }

    func packageIDs() -> [PackageID] { calls.map(\.id) }
    func installedPackages() -> [ContentPackageSpec] { calls }
}

private actor ControllerPreferencesSource {
    private var preferences: ExperiencePreferences
    private var reads = 0
    private var loadsToBlock: Set<Int> = []
    private var blockedLoads: Set<Int> = []
    private var loadContinuations: [Int: CheckedContinuation<Void, Never>] = [:]

    init(_ preferences: ExperiencePreferences) {
        self.preferences = preferences
    }

    func load() async -> ExperiencePreferences {
        reads += 1
        let read = reads
        let captured = preferences
        if loadsToBlock.remove(read) != nil {
            blockedLoads.insert(read)
            await withCheckedContinuation { continuation in
                loadContinuations[read] = continuation
            }
            blockedLoads.remove(read)
        }
        return captured
    }

    func set(_ preferences: ExperiencePreferences) {
        self.preferences = preferences
    }

    func readCount() -> Int { reads }

    func blockLoad(_ read: Int) {
        loadsToBlock.insert(read)
    }

    func isLoadBlocked(_ read: Int) -> Bool {
        blockedLoads.contains(read)
    }

    func releaseLoad(_ read: Int) {
        loadContinuations.removeValue(forKey: read)?.resume()
    }
}

private final class ControllerNetworkProvider:
    DownloadNetworkBasisProviding,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var context: DownloadNetworkContext
    private var reads = 0

    init(_ context: DownloadNetworkContext) {
        self.context = context
    }

    var readCount: Int {
        lock.withLock { reads }
    }

    func set(_ context: DownloadNetworkContext) {
        lock.withLock { self.context = context }
    }

    func currentNetworkBasis() -> DownloadNetworkBasis {
        lock.withLock {
            reads += 1
            return context.basis
        }
    }

    func currentNetworkContext() -> DownloadNetworkContext {
        lock.withLock {
            reads += 1
            return context
        }
    }
}

private final class ControllerTransferEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [PackageID: AsyncStream<AssetPackTransferStatus>.Continuation] = [:]

    func stream(for packageID: PackageID) -> AsyncStream<AssetPackTransferStatus> {
        AsyncStream { continuation in
            lock.withLock { continuations[packageID] = continuation }
        }
    }

    func hasSubscriber(for packageID: PackageID) -> Bool {
        lock.withLock { continuations[packageID] != nil }
    }

    func emit(_ status: AssetPackTransferStatus, for packageID: PackageID) {
        lock.withLock { continuations[packageID] }?.yield(status)
    }
}

private func assertControllerTrue(
    _ value: Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(value, message(), file: file, line: line)
}

private func assertControllerEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual, expected, message(), file: file, line: line)
}
