@testable import ContentDelivery
import ContentKit
import CryptoKit
import Foundation
import XCTest

final class PackageBatchInstallerTests: XCTestCase {
    func testDownloadAllInstallsEveryPackageInDeclaredOrder() async throws {
        let recorder = InstallRecorder()
        let installer = PackageBatchInstaller { package in
            await recorder.record(package.id)
            return Self.activation(for: package)
        }
        let packages = Self.packages(count: 3)

        try await installer.start(packages: packages)

        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        })
        assertResolvedEqual(await recorder.packageIDs(), packages.map(\.id))
    }

    func testImmediatePauseRequestNeverHoldsBeforeTheFirstPackageStarts() async throws {
        let gate = InstallGate()
        let packages = Self.packages(count: 2)
        let installer = PackageBatchInstaller { package in
            await gate.waitForRelease(package.id)
            return Self.activation(for: package)
        }

        try await installer.start(packages: packages)
        try await installer.requestPauseAfterCurrentPackage()

        assertResolvedTrue(await eventually { await gate.startedIDs().first == packages[0].id })
        await gate.release(packages[0].id)

        if await eventually({
            if case .paused = await installer.state() { return true }
            return false
        }) {
            try await installer.resume()
        }
        assertResolvedTrue(await eventually { await gate.startedIDs() == packages.map(\.id) })
        await gate.release(packages[1].id)
        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        })
    }

    func testPauseFinishesCurrentAtomicPackageThenHoldsTheQueue() async throws {
        let gate = InstallGate()
        let installer = PackageBatchInstaller { package in
            await gate.waitForRelease(package.id)
            return Self.activation(for: package)
        }
        let packages = Self.packages(count: 2)

        try await installer.start(packages: packages)
        assertResolvedTrue(await eventually { await gate.startedIDs() == [packages[0].id] })

        try await installer.requestPauseAfterCurrentPackage()
        assertResolvedEqual(
            await installer.state(),
            .pausingAfterCurrent(
                packageID: packages[0].id,
                completedPackageIDs: [],
                totalPackageCount: 2
            )
        )

        await gate.release(packages[0].id)
        assertResolvedTrue(await eventually {
            await installer.state() == .paused(
                nextPackageID: packages[1].id,
                completedPackageIDs: [packages[0].id],
                totalPackageCount: 2
            )
        })
        assertResolvedEqual(await gate.startedIDs(), [packages[0].id])

        try await installer.resume()
        assertResolvedTrue(await eventually { await gate.startedIDs() == packages.map(\.id) })
        await gate.release(packages[1].id)
        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        })
    }

    func testResumeBeforeCurrentFinishesRestoresInstallingState() async throws {
        let gate = InstallGate()
        let packages = Self.packages(count: 2)
        let installer = PackageBatchInstaller { package in
            await gate.waitForRelease(package.id)
            return Self.activation(for: package)
        }

        try await installer.start(packages: packages)
        assertResolvedTrue(await eventually { await gate.startedIDs() == [packages[0].id] })
        try await installer.requestPauseAfterCurrentPackage()
        try await installer.resume()

        assertResolvedEqual(
            await installer.state(),
            .installing(
                packageID: packages[0].id,
                completedPackageIDs: [],
                totalPackageCount: 2
            )
        )
        await gate.release(packages[0].id)
        assertResolvedTrue(await eventually { await gate.startedIDs() == packages.map(\.id) })
        await gate.release(packages[1].id)
        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        })
    }

    func testSystemTransferStatusIsSeparateAndSubscribedBeforeInstall() async throws {
        let gate = InstallGate()
        let events = LockedEvents()
        let transfers = TransferEmitter(events: events)
        let package = Self.packages(count: 1)[0]
        let installer = PackageBatchInstaller(
            installOperation: { package in
                events.append("install:\(package.id.rawValue)")
                await gate.waitForRelease(package.id)
                return Self.activation(for: package)
            },
            transferUpdates: { packageID in transfers.stream(for: packageID) }
        )

        try await installer.start(packages: [package])
        assertResolvedTrue(await eventually { await gate.startedIDs() == [package.id] })
        XCTAssertEqual(events.values(), [
            "subscribe:\(package.id.rawValue)",
            "install:\(package.id.rawValue)",
        ])

        transfers.emit(.began, for: package.id)
        assertResolvedTrue(await eventually {
            await installer.systemTransferState() == .began(
                packageID: package.id,
                returnedAfterObservedPause: false
            )
        })

        transfers.emit(.paused, for: package.id)
        assertResolvedTrue(await eventually {
            await installer.systemTransferState() == .paused(packageID: package.id)
        })
        assertResolvedEqual(
            await installer.state(),
            .installing(packageID: package.id, completedPackageIDs: [], totalPackageCount: 1)
        )

        transfers.emit(.began, for: package.id)
        assertResolvedTrue(await eventually {
            await installer.systemTransferState() == .began(
                packageID: package.id,
                returnedAfterObservedPause: true
            )
        })
        transfers.emit(
            .downloading(completedUnitCount: 20, totalUnitCount: 100),
            for: package.id
        )
        assertResolvedTrue(await eventually {
            await installer.systemTransferState() == .downloading(
                packageID: package.id,
                completedUnitCount: 20,
                totalUnitCount: 100
            )
        })
        transfers.emit(.finished, for: package.id)
        assertResolvedTrue(await eventually {
            await installer.systemTransferState() == .finished(packageID: package.id)
        })

        await gate.release(package.id)
        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: [package.id])
        })
        assertResolvedEqual(await installer.systemTransferState(), .idle)
    }

    func testStaleTransferUpdatesCannotCrossPackageBoundaryAndSystemFailureIsSeparate() async throws {
        let gate = InstallGate()
        let transfers = TransferEmitter(events: LockedEvents())
        let packages = Self.packages(count: 2)
        let installer = PackageBatchInstaller(
            installOperation: { package in
                await gate.waitForRelease(package.id)
                return Self.activation(for: package)
            },
            transferUpdates: { packageID in transfers.stream(for: packageID) }
        )

        try await installer.start(packages: packages)
        assertResolvedTrue(await eventually { await gate.startedIDs() == [packages[0].id] })
        transfers.emit(.began, for: packages[0].id)
        assertResolvedTrue(await eventually {
            await installer.systemTransferState() == .began(
                packageID: packages[0].id,
                returnedAfterObservedPause: false
            )
        })
        await gate.release(packages[0].id)
        assertResolvedTrue(await eventually { await gate.startedIDs() == packages.map(\.id) })
        assertResolvedEqual(await installer.systemTransferState(), .idle)

        transfers.emit(.began, for: packages[1].id)
        assertResolvedTrue(await eventually {
            await installer.systemTransferState() == .began(
                packageID: packages[1].id,
                returnedAfterObservedPause: false
            )
        })
        transfers.emit(.paused, for: packages[0].id)
        await Task.yield()
        assertResolvedEqual(
            await installer.systemTransferState(),
            .began(packageID: packages[1].id, returnedAfterObservedPause: false)
        )

        transfers.emit(.failed(domain: "BAErrorDomain", code: 17), for: packages[1].id)
        assertResolvedTrue(await eventually {
            await installer.systemTransferState() == .failed(
                packageID: packages[1].id,
                failure: .init(domain: "BAErrorDomain", code: 17)
            )
        })
        assertResolvedEqual(
            await installer.state(),
            .installing(
                packageID: packages[1].id,
                completedPackageIDs: [packages[0].id],
                totalPackageCount: 2
            )
        )

        await gate.release(packages[1].id)
        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        })
        assertResolvedEqual(await installer.systemTransferState(), .idle)
    }

    func testInstallFailureCancelsMonitoringAndNormalizesTransferStateToIdle() async throws {
        let gate = InstallGate()
        let transfers = TransferEmitter(events: LockedEvents())
        let package = Self.packages(count: 1)[0]
        let installer = PackageBatchInstaller(
            installOperation: { package in
                await gate.waitForRelease(package.id)
                throw TestInstallError.rejected
            },
            transferUpdates: { packageID in transfers.stream(for: packageID) }
        )

        try await installer.start(packages: [package])
        assertResolvedTrue(await eventually { await gate.startedIDs() == [package.id] })
        transfers.emit(
            .downloading(completedUnitCount: 55, totalUnitCount: 100),
            for: package.id
        )
        assertResolvedTrue(await eventually {
            await installer.systemTransferState() == .downloading(
                packageID: package.id,
                completedUnitCount: 55,
                totalUnitCount: 100
            )
        })

        await gate.release(package.id)

        assertResolvedTrue(await eventually {
            if case .failed(packageID: package.id, completedPackageIDs: [], failure: _)
                = await installer.state() {
                return true
            }
            return false
        })
        assertResolvedEqual(await installer.systemTransferState(), .idle)
    }

    func testFailureCannotBeBypassedAndRetryContinuesTheRetainedQueue() async throws {
        let packages = Self.packages(count: 3)
        let controller = RetryInstallController(failOnceFor: packages[1].id)
        let installer = PackageBatchInstaller { package in
            try await controller.install(package)
        }

        try await installer.start(packages: packages)
        assertResolvedTrue(await eventually {
            guard case let .failed(packageID, completed, _) = await installer.state() else {
                return false
            }
            return packageID == packages[1].id && completed == [packages[0].id]
        })

        do {
            try await installer.start(packages: [packages[2]])
            XCTFail("an unresolved failed head must not be bypassed")
        } catch {
            XCTAssertEqual(error as? PackageBatchInstallationError, .unresolvedQueue)
        }

        try await installer.retryFailed()
        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        })
        assertResolvedEqual(
            await controller.installedIDs(),
            [packages[0].id, packages[1].id, packages[1].id, packages[2].id]
        )
    }

    func testRemoveFailedDropsOnlyTheHeadAndContinuesLaterPackages() async throws {
        let packages = Self.packages(count: 3)
        let controller = RetryInstallController(alwaysFailFor: packages[1].id)
        let installer = PackageBatchInstaller { package in
            try await controller.install(package)
        }

        try await installer.start(packages: packages)
        assertResolvedTrue(await eventually {
            if case .failed(packageID: packages[1].id, completedPackageIDs: _, failure: _) = await installer.state() {
                return true
            }
            return false
        })
        try await installer.removeFailed()

        assertResolvedTrue(await eventually {
            await installer.state() == .completed(
                installedPackageIDs: [packages[0].id, packages[2].id]
            )
        })
        assertResolvedEqual(
            await controller.installedIDs(),
            [packages[0].id, packages[1].id, packages[2].id]
        )
    }

    func testPauseOnLastPackageEndsCompletedRatherThanPaused() async throws {
        let gate = InstallGate()
        let package = Self.packages(count: 1)[0]
        let installer = PackageBatchInstaller { package in
            await gate.waitForRelease(package.id)
            return Self.activation(for: package)
        }

        try await installer.start(packages: [package])
        assertResolvedTrue(await eventually { await gate.startedIDs() == [package.id] })
        try await installer.requestPauseAfterCurrentPackage()
        await gate.release(package.id)

        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: [package.id])
        })
    }

    func testPauseThenInstallFailureEndsFailedAndResumeDoesNothing() async throws {
        let gate = InstallGate()
        let packages = Self.packages(count: 2)
        let installer = PackageBatchInstaller { package in
            await gate.waitForRelease(package.id)
            throw TestInstallError.rejected
        }

        try await installer.start(packages: packages)
        assertResolvedTrue(await eventually { await gate.startedIDs() == [packages[0].id] })
        try await installer.requestPauseAfterCurrentPackage()
        await gate.release(packages[0].id)
        assertResolvedTrue(await eventually {
            if case .failed(packageID: packages[0].id, completedPackageIDs: [], failure: _) = await installer.state() {
                return true
            }
            return false
        })

        try await installer.resume()
        await Task.yield()
        assertResolvedEqual(await gate.startedIDs(), [packages[0].id])
        if case .failed = await installer.state() {
            // Expected terminal state.
        } else {
            XCTFail("resume must not reinterpret a failed queue as paused")
        }
    }

    func testDuplicatePackageIDsFailBeforeTheQueueStarts() async throws {
        let recorder = InstallRecorder()
        let installer = PackageBatchInstaller { package in
            await recorder.record(package.id)
            return Self.activation(for: package)
        }
        let package = Self.packages(count: 1)[0]

        do {
            try await installer.start(packages: [package, package])
            XCTFail("duplicate package IDs must fail closed")
        } catch {
            XCTAssertEqual(error as? PackageBatchInstallationError, .duplicatePackageID(package.id))
        }
        assertResolvedEqual(await recorder.packageIDs(), [])
        assertResolvedEqual(await installer.state(), .idle)
    }

    func testSecondStartIsRejectedWhileAnAtomicPackageIsActive() async throws {
        let gate = InstallGate()
        let packages = Self.packages(count: 1)
        let installer = PackageBatchInstaller { package in
            await gate.waitForRelease(package.id)
            return Self.activation(for: package)
        }

        try await installer.start(packages: packages)
        assertResolvedTrue(await eventually { await gate.startedIDs() == [packages[0].id] })
        do {
            try await installer.start(packages: packages)
            XCTFail("a second worker must not interleave with the active package")
        } catch {
            XCTAssertEqual(error as? PackageBatchInstallationError, .alreadyRunning)
        }

        await gate.release(packages[0].id)
        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        })
    }

    func testEmptyDownloadAllCompletesWithoutStartingAWorker() async throws {
        let installer = PackageBatchInstaller { package in Self.activation(for: package) }
        try await installer.start(packages: [])
        assertResolvedEqual(await installer.state(), .completed(installedPackageIDs: []))
    }

    static func packages(count: Int) -> [ContentPackageSpec] {
        (1 ... count).map { index in
            ContentPackageSpec(
                id: PackageID(rawValue: "paid-pack-0\(index)"),
                version: .init(major: 1),
                chapterIDs: [ChapterID(rawValue: "chapter-0\(index)")],
                maximumInstalledBytes: 750_000_000,
                minimumRuntime: .init(major: 1),
                isEssentialInstall: false
            )
        }
    }

    static func activation(for package: ContentPackageSpec) -> ActivatedPackage {
        let generation = InstalledPackageGeneration(
            generationID: "\(package.id.rawValue)-generation",
            packageID: package.id,
            packageVersion: package.version,
            manifestDigest: String(repeating: "a", count: 64),
            relativePath: "generations/\(package.id.rawValue)-generation",
            activationSequence: 1
        )
        return ActivatedPackage(
            generation: generation,
            packageURL: URL(fileURLWithPath: "/tmp/\(package.id.rawValue)-generation")
        )
    }

    func eventually(
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< 20_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }
}

final class PackageBatchLaunchDownloadPlanTests: XCTestCase {
    func testPlanUsesExactPaidOrderAndMaximumStorageBudget() throws {
        let plan = try LaunchDownloadPlan(installedIndex: .empty)
        let expectedIDs = Array(LaunchContent.packageIDsInDeliveryOrder.dropFirst())
        let expectedBudget = LaunchContent.collectionManifest.packages
            .filter { expectedIDs.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.maximumInstalledBytes }

        XCTAssertEqual(plan.packages.map(\.id), expectedIDs)
        XCTAssertFalse(plan.packages.contains(where: \.isEssentialInstall))
        XCTAssertEqual(plan.outdatedPackages, [])
        XCTAssertEqual(plan.remainingMaximumInstalledBytes, expectedBudget)
    }

    func testPlanFiltersCurrentInstalledPackagesWithoutChangingRemainingOrder() throws {
        let manifest = LaunchContent.collectionManifest
        let first = try XCTUnwrap(manifest.packages.first { $0.id == "paid-pack-01" })
        let third = try XCTUnwrap(manifest.packages.first { $0.id == "paid-pack-03" })
        let index = installedIndex(for: [first, third])

        let plan = try LaunchDownloadPlan(manifest: manifest, installedIndex: index)

        XCTAssertEqual(plan.packages.map(\.id), [
            "paid-pack-02", "paid-pack-04", "paid-pack-05",
            "paid-pack-06", "paid-pack-07",
        ])
        XCTAssertEqual(
            plan.remainingMaximumInstalledBytes,
            plan.packages.reduce(Int64(0)) { $0 + $1.maximumInstalledBytes }
        )
        XCTAssertEqual(plan.outdatedPackages, [])
    }

    func testPlanKeepsAnOutdatedActiveGenerationInTheQueue() throws {
        let manifest = LaunchContent.collectionManifest
        let package = try XCTUnwrap(manifest.packages.first { $0.id == "paid-pack-01" })
        let oldPackage = ContentPackageSpec(
            id: package.id,
            version: .init(major: 0),
            chapterIDs: package.chapterIDs,
            maximumInstalledBytes: package.maximumInstalledBytes,
            minimumRuntime: package.minimumRuntime,
            isEssentialInstall: false
        )

        let plan = try LaunchDownloadPlan(
            manifest: manifest,
            installedIndex: installedIndex(for: [oldPackage])
        )
        XCTAssertEqual(plan.packages.first?.id, package.id)
        XCTAssertEqual(plan.outdatedPackages, [
            OutdatedPackageVersion(
                packageID: package.id,
                installedVersion: oldPackage.version,
                expectedVersion: package.version
            ),
        ])
        XCTAssertEqual(plan.protectedNewerPackages, [])
    }

    func testPlanProtectsANewerActiveGenerationWithoutBudgetingADowngrade() throws {
        let manifest = LaunchContent.collectionManifest
        let package = try XCTUnwrap(manifest.packages.first { $0.id == "paid-pack-01" })
        let newerVersion = SchemaVersion(
            major: package.version.major + 1,
            minor: package.version.minor,
            patch: package.version.patch
        )
        let newerPackage = ContentPackageSpec(
            id: package.id,
            version: newerVersion,
            chapterIDs: package.chapterIDs,
            maximumInstalledBytes: package.maximumInstalledBytes,
            minimumRuntime: package.minimumRuntime,
            isEssentialInstall: false
        )

        let plan = try LaunchDownloadPlan(
            manifest: manifest,
            installedIndex: installedIndex(for: [newerPackage])
        )

        XCTAssertFalse(plan.packages.contains { $0.id == package.id })
        XCTAssertEqual(plan.outdatedPackages, [])
        XCTAssertEqual(plan.protectedNewerPackages, [
            ProtectedNewerPackageVersion(
                packageID: package.id,
                installedVersion: newerVersion,
                expectedVersion: package.version
            ),
        ])
        XCTAssertEqual(
            plan.remainingMaximumInstalledBytes,
            plan.packages.reduce(Int64(0)) { $0 + $1.maximumInstalledBytes }
        )
    }

    func testPlanHasZeroMaximumBudgetWhenEveryPaidGenerationIsCurrent() throws {
        let paidPackages = LaunchContent.collectionManifest.packages.filter {
            !$0.isEssentialInstall
        }

        let plan = try LaunchDownloadPlan(installedIndex: installedIndex(for: paidPackages))

        XCTAssertEqual(plan.packages, [])
        XCTAssertEqual(plan.outdatedPackages, [])
        XCTAssertEqual(plan.protectedNewerPackages, [])
        XCTAssertEqual(plan.remainingMaximumInstalledBytes, 0)
    }

    func testMaximumBudgetAdditionFailsClosedOnOverflow() throws {
        let packages = [
            package(id: "overflow-a", bytes: Int64.max),
            package(id: "overflow-b", bytes: 1),
        ]
        XCTAssertThrowsError(try LaunchDownloadPlan.maximumInstalledByteBudget(for: packages)) {
            XCTAssertEqual(
                $0 as? LaunchDownloadPlanError,
                .maximumInstalledByteBudgetOverflow
            )
        }
    }

    private func installedIndex(for packages: [ContentPackageSpec]) -> InstalledPackageIndex {
        let generations = packages.enumerated().map { index, package in
            InstalledPackageGeneration(
                generationID: "\(package.id.rawValue)-generation",
                packageID: package.id,
                packageVersion: package.version,
                manifestDigest: String(repeating: "a", count: 64),
                relativePath: "generations/\(package.id.rawValue)-generation",
                activationSequence: UInt64(index + 1)
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

    private func package(id: PackageID, bytes: Int64) -> ContentPackageSpec {
        ContentPackageSpec(
            id: id,
            version: .init(major: 1),
            chapterIDs: [ChapterID(rawValue: "chapter-\(id.rawValue)")],
            maximumInstalledBytes: bytes,
            minimumRuntime: .init(major: 1),
            isEssentialInstall: false
        )
    }
}

final class PackageBatchQueueJournalTests: XCTestCase {
    func testJournalFallsBackToPriorDigestCheckedAtomicSlot() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let packages = PackageBatchInstallerTests.packages(count: 2)
        let first = PackageBatchQueueJournal(
            intent: .running,
            packages: packages,
            completedPackageIDs: []
        )
        let second = PackageBatchQueueJournal(
            intent: .paused,
            packages: packages,
            completedPackageIDs: [packages[0].id]
        )
        try store.save(first)
        try store.save(second)
        try Data("corrupt".utf8).write(
            to: root.appending(path: "package-queue-b.json"),
            options: [.atomic]
        )

        XCTAssertEqual(try store.load(), first)
    }

    func testJournalRejectsNonPrefixCompletedIDs() throws {
        let store = try PackageBatchQueueJournalStore(directoryURL: temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: store.directoryURL) }
        let packages = PackageBatchInstallerTests.packages(count: 3)
        let journal = PackageBatchQueueJournal(
            intent: .running,
            packages: packages,
            completedPackageIDs: [packages[0].id, packages[2].id]
        )

        XCTAssertThrowsError(try store.save(journal)) {
            XCTAssertEqual($0 as? PackageBatchQueueJournalError, .invalidCompletedPackages)
        }
    }

    func testJournalRejectsFailureThatIsNotTheFirstIncompleteHead() throws {
        let store = try PackageBatchQueueJournalStore(directoryURL: temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: store.directoryURL) }
        let packages = PackageBatchInstallerTests.packages(count: 3)
        let journal = PackageBatchQueueJournal(
            intent: .failed,
            packages: packages,
            completedPackageIDs: [packages[0].id],
            failedPackageID: packages[2].id,
            failure: .init(domain: "test", code: 1)
        )

        XCTAssertThrowsError(try store.save(journal)) {
            XCTAssertEqual($0 as? PackageBatchQueueJournalError, .invalidFailure)
        }
    }

    func testJournalRejectsRunningIntentWhenEverythingIsComplete() throws {
        let store = try PackageBatchQueueJournalStore(directoryURL: temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: store.directoryURL) }
        let packages = PackageBatchInstallerTests.packages(count: 1)
        let journal = PackageBatchQueueJournal(
            intent: .running,
            packages: packages,
            completedPackageIDs: packages.map(\.id)
        )

        XCTAssertThrowsError(try store.save(journal)) {
            XCTAssertEqual($0 as? PackageBatchQueueJournalError, .invalidCompletion)
        }
    }

    func testJournalRejectsUnsupportedSchemaVersion() throws {
        let store = try PackageBatchQueueJournalStore(directoryURL: temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: store.directoryURL) }
        let packages = PackageBatchInstallerTests.packages(count: 1)
        let journal = PackageBatchQueueJournal(
            formatVersion: PackageBatchQueueJournal.currentFormatVersion + 1,
            intent: .running,
            packages: packages,
            completedPackageIDs: []
        )

        XCTAssertThrowsError(try store.save(journal)) {
            XCTAssertEqual(
                $0 as? PackageBatchQueueJournalError,
                .unsupportedFormat(PackageBatchQueueJournal.currentFormatVersion + 1)
            )
        }
    }

    func testFutureJournalAuthorityCannotBeLoadedSavedOrRetiredByOlderApp() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let packages = PackageBatchInstallerTests.packages(count: 1)
        let current = PackageBatchQueueJournal(
            intent: .running,
            packages: packages,
            completedPackageIDs: []
        )
        try store.save(current)
        let slotA = root.appending(path: "package-queue-a.json")
        let slotB = root.appending(path: "package-queue-b.json")
        let originalA = try Data(contentsOf: slotA)
        let futureFormat = PackageBatchQueueJournal.currentFormatVersion + 1
        let futureB = try futureEnvelope(
            basedOn: originalA,
            payloadKey: "journal",
            generation: 2,
            formatVersion: futureFormat
        )
        try futureB.write(to: slotB, options: [.atomic])

        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual(
                $0 as? PackageBatchQueueJournalError,
                .requiresNewerApp(futureFormat)
            )
        }
        XCTAssertThrowsError(try store.save(current)) {
            XCTAssertEqual(
                $0 as? PackageBatchQueueJournalError,
                .requiresNewerApp(futureFormat)
            )
        }
        XCTAssertThrowsError(try store.retireCurrentQueue()) {
            XCTAssertEqual(
                $0 as? PackageBatchQueueJournalError,
                .requiresNewerApp(futureFormat)
            )
        }
        XCTAssertEqual(try Data(contentsOf: slotA), originalA)
        XCTAssertEqual(try Data(contentsOf: slotB), futureB)

        let installer = PackageBatchInstaller(
            installOperation: { PackageBatchInstallerTests.activation(for: $0) },
            journalStore: store
        )
        try await installer.restoreQueue(
            installedIndex: .empty,
            canonicalPackages: packages
        )
        assertResolvedEqual(
            await installer.state(),
            .staleJournal(reason: .requiresNewerApp(formatVersion: futureFormat))
        )
        do {
            try await installer.discardStaleJournal()
            XCTFail("an older app must not retire a future queue authority")
        } catch {
            XCTAssertEqual(
                error as? PackageBatchInstallationError,
                .newerPackageVersionRequiresNewerApp
            )
        }
        XCTAssertEqual(try Data(contentsOf: slotB), futureB)
    }

    func testColdStartCannotOverwriteAnUnresolvedFailedJournal() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let packages = PackageBatchInstallerTests.packages(count: 3)
        try store.save(PackageBatchQueueJournal(
            intent: .failed,
            packages: packages,
            completedPackageIDs: [packages[0].id],
            failedPackageID: packages[1].id,
            failure: .init(domain: "test", code: 1)
        ))
        let installer = PackageBatchInstaller(
            installOperation: { PackageBatchInstallerTests.activation(for: $0) },
            journalStore: store
        )

        do {
            try await installer.start(packages: [packages[2]])
            XCTFail("cold start must restore or resolve the journal before replacing it")
        } catch {
            XCTAssertEqual(error as? PackageBatchInstallationError, .unresolvedQueue)
        }
    }

    func testDiscardStaleJournalWritesDurableEmptyTombstoneAndPreservesFutureStarts()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let canonical = PackageBatchInstallerTests.packages(count: 1)
        let retired = ContentPackageSpec(
            id: "retired-package",
            version: .init(major: 1),
            chapterIDs: ["retired-chapter"],
            maximumInstalledBytes: 1,
            minimumRuntime: .init(major: 1),
            isEssentialInstall: false
        )
        try store.save(PackageBatchQueueJournal(
            intent: .running,
            packages: [retired],
            completedPackageIDs: []
        ))
        let originalSlotA = try Data(contentsOf: root.appending(path: "package-queue-a.json"))
        let recorder = InstallRecorder()
        let installer = PackageBatchInstaller(
            installOperation: { package in
                await recorder.record(package.id)
                return PackageBatchInstallerTests.activation(for: package)
            },
            journalStore: store
        )
        try await installer.restoreQueue(
            installedIndex: .empty,
            canonicalPackages: canonical
        )
        assertResolvedEqual(
            await installer.state(),
            .staleJournal(reason: .unknownOrRemovedPackageIDs([retired.id]))
        )

        try await installer.discardStaleJournal()

        assertResolvedEqual(await installer.state(), .idle)
        let tombstone = try XCTUnwrap(store.load())
        XCTAssertEqual(tombstone.intent, .completed)
        XCTAssertEqual(tombstone.packages, [])
        XCTAssertEqual(tombstone.completedPackageIDs, [])
        let retiredDirectories = try FileManager.default.contentsOfDirectory(
            at: store.retiredQueuesDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(retiredDirectories.count, 1)
        XCTAssertEqual(
            try Data(contentsOf: retiredDirectories[0].appending(path: "package-queue-a.json")),
            originalSlotA
        )

        try await installer.start(packages: canonical)
        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: canonical.map(\.id))
        })
        assertResolvedEqual(await recorder.packageIDs(), canonical.map(\.id))
    }

    func testDiscardStaleJournalRejectsEveryNonStaleState() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = PackageBatchInstaller(
            installOperation: { PackageBatchInstallerTests.activation(for: $0) },
            journalStore: try PackageBatchQueueJournalStore(directoryURL: root)
        )

        do {
            try await installer.discardStaleJournal()
            XCTFail("Only a surfaced stale queue may be discarded")
        } catch {
            XCTAssertEqual(error as? PackageBatchInstallationError, .noStaleJournal)
        }
    }

    func testCorruptJournalIsPreservedThenRetiredWithoutBlockingFutureStarts()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let slotA = root.appending(path: "package-queue-a.json")
        let slotB = root.appending(path: "package-queue-b.json")
        let corruptA = Data("corrupt-a".utf8)
        let corruptB = Data("corrupt-b".utf8)
        try corruptA.write(to: slotA, options: [.atomic])
        try corruptB.write(to: slotB, options: [.atomic])
        let packages = PackageBatchInstallerTests.packages(count: 1)
        let recorder = InstallRecorder()
        let installer = PackageBatchInstaller(
            installOperation: { package in
                await recorder.record(package.id)
                return PackageBatchInstallerTests.activation(for: package)
            },
            journalStore: store
        )

        try await installer.restoreQueue(
            installedIndex: .empty,
            canonicalPackages: packages
        )
        assertResolvedEqual(
            await installer.state(),
            .staleJournal(reason: .corruptJournal)
        )

        try await installer.discardStaleJournal()

        assertResolvedEqual(await installer.state(), .idle)
        let retiredDirectories = try FileManager.default.contentsOfDirectory(
            at: store.retiredQueuesDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(retiredDirectories.count, 1)
        XCTAssertEqual(
            try Data(contentsOf: retiredDirectories[0].appending(path: slotA.lastPathComponent)),
            corruptA
        )
        XCTAssertEqual(
            try Data(contentsOf: retiredDirectories[0].appending(path: slotB.lastPathComponent)),
            corruptB
        )
        let tombstone = try XCTUnwrap(store.load())
        XCTAssertEqual(tombstone.intent, .completed)
        XCTAssertEqual(tombstone.packages, [])

        try await installer.start(packages: packages)
        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        })
        assertResolvedEqual(await recorder.packageIDs(), packages.map(\.id))
    }

    func testRunningJournalReconcilesActivePrefixButRequiresExplicitResume() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let packages = PackageBatchInstallerTests.packages(count: 2)
        try store.save(PackageBatchQueueJournal(
            intent: .running,
            packages: packages,
            completedPackageIDs: []
        ))
        let recorder = InstallRecorder()
        let installer = PackageBatchInstaller(
            installOperation: { package in
                await recorder.record(package.id)
                return PackageBatchInstallerTests.activation(for: package)
            },
            journalStore: store
        )

        try await installer.restoreQueue(
            installedIndex: installedIndex(for: [packages[0]]),
            canonicalPackages: packages,
            policy: .requireExplicitResume
        )

        assertResolvedEqual(
            await installer.state(),
            .awaitingExplicitRestore(
                nextPackageID: packages[1].id,
                completedPackageIDs: [packages[0].id],
                totalPackageCount: 2
            )
        )
        assertResolvedEqual(await recorder.packageIDs(), [])
        try await installer.resume()
        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        })
        assertResolvedEqual(await recorder.packageIDs(), [packages[1].id])
        XCTAssertEqual(try store.load()?.intent, .completed)
    }

    func testRestoreProtectsNewerActiveGenerationWithoutWritingOrDowngrading() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let packages = PackageBatchInstallerTests.packages(count: 2)
        let journal = PackageBatchQueueJournal(
            intent: .running,
            packages: packages,
            completedPackageIDs: []
        )
        try store.save(journal)
        let slotA = root.appending(path: "package-queue-a.json")
        let originalSlotA = try Data(contentsOf: slotA)
        let expected = packages[0]
        let newer = ContentPackageSpec(
            id: expected.id,
            version: SchemaVersion(
                major: expected.version.major + 1,
                minor: expected.version.minor,
                patch: expected.version.patch
            ),
            chapterIDs: expected.chapterIDs,
            maximumInstalledBytes: expected.maximumInstalledBytes,
            minimumRuntime: expected.minimumRuntime,
            isEssentialInstall: expected.isEssentialInstall
        )
        let recorder = InstallRecorder()
        let installer = PackageBatchInstaller(
            installOperation: { package in
                await recorder.record(package.id)
                return PackageBatchInstallerTests.activation(for: package)
            },
            journalStore: store
        )

        try await installer.restoreQueue(
            installedIndex: installedIndex(for: [newer]),
            canonicalPackages: packages,
            policy: .resumeRunning
        )

        assertResolvedEqual(
            await installer.state(),
            .staleJournal(reason: .protectedNewerPackageVersions([expected.id]))
        )
        assertResolvedEqual(await recorder.packageIDs(), [])
        XCTAssertEqual(try store.load(), journal)
        XCTAssertEqual(try Data(contentsOf: slotA), originalSlotA)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appending(path: "package-queue-b.json").path
            )
        )

        do {
            try await installer.discardStaleJournal()
            XCTFail("A runtime that cannot interpret newer content must preserve its queue")
        } catch {
            XCTAssertEqual(
                error as? PackageBatchInstallationError,
                .newerPackageVersionRequiresNewerApp
            )
        }
        XCTAssertEqual(try store.load(), journal)
    }

    func testPausedJournalRemainsPausedEvenUnderResumeRunningPolicy() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let packages = PackageBatchInstallerTests.packages(count: 2)
        try store.save(PackageBatchQueueJournal(
            intent: .paused,
            packages: packages,
            completedPackageIDs: [packages[0].id]
        ))
        let recorder = InstallRecorder()
        let installer = PackageBatchInstaller(
            installOperation: { package in
                await recorder.record(package.id)
                return PackageBatchInstallerTests.activation(for: package)
            },
            journalStore: store
        )

        try await installer.restoreQueue(
            installedIndex: installedIndex(for: [packages[0]]),
            canonicalPackages: packages,
            policy: .resumeRunning
        )

        assertResolvedEqual(
            await installer.state(),
            .paused(
                nextPackageID: packages[1].id,
                completedPackageIDs: [packages[0].id],
                totalPackageCount: 2
            )
        )
        await Task.yield()
        assertResolvedEqual(await recorder.packageIDs(), [])
    }

    func testResumeRunningPolicyExplicitlyRestartsRunningJournal() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let packages = PackageBatchInstallerTests.packages(count: 1)
        try store.save(PackageBatchQueueJournal(
            intent: .running,
            packages: packages,
            completedPackageIDs: []
        ))
        let recorder = InstallRecorder()
        let installer = PackageBatchInstaller(
            installOperation: { package in
                await recorder.record(package.id)
                return PackageBatchInstallerTests.activation(for: package)
            },
            journalStore: store
        )

        try await installer.restoreQueue(
            installedIndex: .empty,
            canonicalPackages: packages,
            policy: .resumeRunning
        )

        assertResolvedTrue(await eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        })
        assertResolvedEqual(await recorder.packageIDs(), packages.map(\.id))
    }

    func testMigratedRunningJournalRequiresExplicitResumeUnderResumeRunningPolicy() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let current = PackageBatchInstallerTests.packages(count: 1)
        let package = current[0]
        let legacy = ContentPackageSpec(
            id: package.id,
            version: .init(major: 0, minor: 9),
            chapterIDs: package.chapterIDs,
            maximumInstalledBytes: package.maximumInstalledBytes - 1,
            minimumRuntime: .init(major: 0),
            isEssentialInstall: false
        )
        try store.save(PackageBatchQueueJournal(
            intent: .running,
            packages: [legacy],
            completedPackageIDs: []
        ))
        let recorder = InstallRecorder()
        let installer = PackageBatchInstaller(
            installOperation: { package in
                await recorder.record(package.id)
                return PackageBatchInstallerTests.activation(for: package)
            },
            journalStore: store
        )

        try await installer.restoreQueue(
            installedIndex: .empty,
            canonicalPackages: current,
            policy: .resumeRunning
        )

        assertResolvedEqual(
            await installer.state(),
            .awaitingExplicitRestore(
                nextPackageID: package.id,
                completedPackageIDs: [],
                totalPackageCount: 1
            )
        )
        assertResolvedEqual(await recorder.packageIDs(), [])
        XCTAssertEqual(try store.load()?.packages, current)
    }

    func testRestoreUsesOnlyContiguousActivePrefix() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PackageBatchQueueJournalStore(directoryURL: root)
        let packages = PackageBatchInstallerTests.packages(count: 3)
        try store.save(PackageBatchQueueJournal(
            intent: .running,
            packages: packages,
            completedPackageIDs: []
        ))
        let installer = PackageBatchInstaller(
            installOperation: { PackageBatchInstallerTests.activation(for: $0) },
            journalStore: store
        )

        try await installer.restoreQueue(
            installedIndex: installedIndex(for: [packages[0], packages[2]]),
            canonicalPackages: packages
        )

        assertResolvedEqual(
            await installer.state(),
            .awaitingExplicitRestore(
                nextPackageID: packages[1].id,
                completedPackageIDs: [packages[0].id],
                totalPackageCount: 3
            )
        )
    }

    private func installedIndex(for packages: [ContentPackageSpec]) -> InstalledPackageIndex {
        let generations = packages.enumerated().map { index, package in
            InstalledPackageGeneration(
                generationID: "\(package.id.rawValue)-generation",
                packageID: package.id,
                packageVersion: package.version,
                manifestDigest: String(repeating: "a", count: 64),
                relativePath: "generations/\(package.id.rawValue)-generation",
                activationSequence: UInt64(index + 1)
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

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "package-batch-journal-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func futureEnvelope(
        basedOn currentData: Data,
        payloadKey: String,
        generation: UInt64,
        formatVersion: Int
    ) throws -> Data {
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        var payload = try XCTUnwrap(root[payloadKey] as? [String: Any])
        payload["formatVersion"] = formatVersion
        root["generation"] = generation
        root[payloadKey] = payload
        let material: [String: Any] = [
            "envelopeFormatVersion": try XCTUnwrap(root["envelopeFormatVersion"]),
            "generation": generation,
            payloadKey: payload,
        ]
        let canonicalMaterial = try JSONSerialization.data(
            withJSONObject: material,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        root["digest"] = SHA256.hash(data: canonicalMaterial)
            .map { String(format: "%02x", $0) }
            .joined()
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func eventually(
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< 20_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }
}

private enum TestInstallError: Error {
    case rejected
}

private actor InstallRecorder {
    private var values: [PackageID] = []

    func record(_ packageID: PackageID) { values.append(packageID) }
    func packageIDs() -> [PackageID] { values }
}

private actor InstallGate {
    private var started: [PackageID] = []
    private var continuations: [PackageID: CheckedContinuation<Void, Never>] = [:]

    func waitForRelease(_ packageID: PackageID) async {
        started.append(packageID)
        await withCheckedContinuation { continuation in
            continuations[packageID] = continuation
        }
    }

    func release(_ packageID: PackageID) {
        continuations.removeValue(forKey: packageID)?.resume()
    }

    func startedIDs() -> [PackageID] { started }
}

private actor RetryInstallController {
    private let failOnceFor: PackageID?
    private let alwaysFailFor: PackageID?
    private var didFailOnce = false
    private var attempts: [PackageID] = []

    init(failOnceFor: PackageID) {
        self.failOnceFor = failOnceFor
        alwaysFailFor = nil
    }

    init(alwaysFailFor: PackageID) {
        failOnceFor = nil
        self.alwaysFailFor = alwaysFailFor
    }

    func install(_ package: ContentPackageSpec) throws -> ActivatedPackage {
        attempts.append(package.id)
        if package.id == alwaysFailFor {
            throw TestInstallError.rejected
        }
        if package.id == failOnceFor, !didFailOnce {
            didFailOnce = true
            throw TestInstallError.rejected
        }
        return PackageBatchInstallerTests.activation(for: package)
    }

    func installedIDs() -> [PackageID] { attempts }
}

private final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }

    func values() -> [String] {
        lock.withLock { storage }
    }
}

private final class TransferEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private let events: LockedEvents
    private var continuations: [PackageID: AsyncStream<AssetPackTransferStatus>.Continuation] = [:]

    init(events: LockedEvents) {
        self.events = events
    }

    func stream(for packageID: PackageID) -> AsyncStream<AssetPackTransferStatus> {
        events.append("subscribe:\(packageID.rawValue)")
        return AsyncStream { continuation in
            lock.withLock { continuations[packageID] = continuation }
        }
    }

    func emit(_ status: AssetPackTransferStatus, for packageID: PackageID) {
        let continuation = lock.withLock { continuations[packageID] }
        continuation?.yield(status)
    }
}

/// XCTest's autoclosures cannot contain `await`; these helpers receive values
/// after actor hops and preserve the originating source location.
private func assertResolvedTrue(
    _ expression: Bool,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if !expression {
        XCTFail(message, file: file, line: line)
    }
}

private func assertResolvedEqual<T: Equatable>(
    _ expression1: T,
    _ expression2: T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(expression1, expression2, message, file: file, line: line)
}
