import ContentDelivery
@testable import ContentKit
import CryptoKit
import Foundation
@testable import JourneyContent
import XCTest

final class VerifiedJourneyRepositoryAuthorityTests: XCTestCase {
    func testBootstrapReverifiesActiveGenerationAndRelaunchBuildsSameRepository() async throws {
        let key = P256.Signing.PrivateKey()
        let paid = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "active"
        )
        defer { try? FileManager.default.removeItem(at: paid.root) }
        let generation = generation(for: paid, sequence: 1)
        let durable = authority(
            active: [paid.packageID: (generation, paid.root)],
            retained: [:]
        )

        let first = try makeAuthority(
            durable: durable,
            publicKey: key.publicKey.x963Representation
        )
        let firstSnapshot = try await first.refresh()
        XCTAssertEqual(
            firstSnapshot.repository.availablePackageIDs,
            ["essential-free-v1", "paid-pack-01"]
        )
        XCTAssertEqual(
            firstSnapshot.packageRootURL(for: "paid-pack-01"),
            paid.root.standardizedFileURL
        )
        XCTAssertEqual(
            firstSnapshot.verifiedPackage(for: "essential-free-v1")?.manifest.packageID,
            "essential-free-v1"
        )
        XCTAssertEqual(
            firstSnapshot.verifiedPackage(for: "paid-pack-01")?.manifest.manifestDigest,
            paid.manifest.manifestDigest
        )

        let relaunched = try makeAuthority(
            durable: durable,
            publicKey: key.publicKey.x963Representation
        )
        let relaunchedSnapshot = try await relaunched.refresh()
        XCTAssertEqual(
            relaunchedSnapshot.repository.availablePackageIDs,
            firstSnapshot.repository.availablePackageIDs
        )
        XCTAssertNotNil(relaunchedSnapshot.repository.chapter("steppe-comes-west"))
    }

    func testDamagedActiveGenerationRollsBackOnlyAfterPreviousGenerationVerifies() async throws {
        let key = P256.Signing.PrivateKey()
        let active = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "active"
        )
        let previous = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "previous"
        )
        defer {
            try? FileManager.default.removeItem(at: active.root)
            try? FileManager.default.removeItem(at: previous.root)
        }
        try Data("changed-after-activation".utf8).write(
            to: active.payloadURL,
            options: .atomic
        )
        let previousGeneration = generation(for: previous, sequence: 1)
        let activeGeneration = generation(for: active, sequence: 2)
        let durable = authority(
            active: [active.packageID: (activeGeneration, active.root)],
            retained: [active.packageID: (previousGeneration, previous.root)]
        )
        let rollback = RollbackRecorder(result: ActivatedPackage(
            generation: previousGeneration,
            packageURL: previous.root.standardizedFileURL
        ))
        let subject = try makeAuthority(
            durable: durable,
            publicKey: key.publicKey.x963Representation,
            exactRollback: { packageID, _, _ in
                .rolledBack(try await rollback.perform(packageID))
            }
        )

        let snapshot = try await subject.refresh()

        let rollbackPackageIDs = await rollback.packageIDs
        XCTAssertEqual(rollbackPackageIDs, ["paid-pack-01"])
        XCTAssertEqual(snapshot.repairedPackageIDs, ["paid-pack-01"])
        XCTAssertEqual(
            snapshot.reconciledInstalledIndex.activeGeneration(for: "paid-pack-01")?
                .generationID,
            previousGeneration.generationID
        )
        XCTAssertNotNil(snapshot.repository.chapter("steppe-comes-west"))
        XCTAssertEqual(
            snapshot.packageRootURL(for: "paid-pack-01"),
            previous.root.standardizedFileURL
        )
    }

    func testConcurrentActivationMakesVerifiedPredecessorRollbackAStaleNoOp()
        async throws
    {
        let key = P256.Signing.PrivateKey()
        let active = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "concurrent-active"
        )
        let previous = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "concurrent-previous"
        )
        let concurrent = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "concurrent-new-authority"
        )
        defer {
            try? FileManager.default.removeItem(at: active.root)
            try? FileManager.default.removeItem(at: previous.root)
            try? FileManager.default.removeItem(at: concurrent.root)
        }
        try Data("tampered-active".utf8).write(
            to: active.payloadURL,
            options: .atomic
        )
        let previousGeneration = generation(for: previous, sequence: 1)
        let activeGeneration = generation(for: active, sequence: 2)
        let concurrentGeneration = generation(for: concurrent, sequence: 3)
        let source = MutableAuthoritySource(authority: authority(
            active: [active.packageID: (activeGeneration, active.root)],
            retained: [active.packageID: (previousGeneration, previous.root)]
        ))
        let concurrentAuthority = authority(
            active: [
                concurrent.packageID: (
                    concurrentGeneration,
                    concurrent.root
                ),
            ],
            retained: [:]
        )
        let mutations = RecoveryMutationRecorder()
        let subject = try makeAuthority(
            provider: { try await source.load() },
            publicKey: key.publicKey.x963Representation,
            exactRollback: { packageID, current, predecessor in
                await mutations.recordRollback(
                    packageID,
                    current,
                    predecessor
                )
                await source.set(authority: concurrentAuthority)
                return .staleAuthority
            }
        )

        let snapshot = try await subject.refresh()

        let durable = try await source.load()
        let rollbacks = await mutations.rollbacks
        let rollback = try XCTUnwrap(rollbacks.first)
        XCTAssertEqual(rollback.0, active.packageID)
        XCTAssertEqual(rollback.1, activeGeneration)
        XCTAssertEqual(rollback.2, previousGeneration)
        XCTAssertEqual(
            durable.index.activeGeneration(for: active.packageID),
            concurrentGeneration
        )
        XCTAssertEqual(snapshot.repairedPackageIDs, [])
        XCTAssertEqual(snapshot.unavailableCurrentPackageIDs, [active.packageID])
        XCTAssertNil(snapshot.verifiedPackage(for: active.packageID))
    }

    func testOneUnrepairablePackageBecomesPendingWithoutTakingDownAnotherPackage() async throws {
        let key = P256.Signing.PrivateKey()
        let damaged = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "damaged"
        )
        let valid = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-02"),
            privateKey: key,
            suffix: "valid"
        )
        defer {
            try? FileManager.default.removeItem(at: damaged.root)
            try? FileManager.default.removeItem(at: valid.root)
        }
        try Data("tampered".utf8).write(to: damaged.payloadURL, options: .atomic)
        let durable = authority(
            active: [
                damaged.packageID: (generation(for: damaged, sequence: 1), damaged.root),
                valid.packageID: (generation(for: valid, sequence: 2), valid.root),
            ],
            retained: [:]
        )
        let rollback = RollbackRecorder(error: PackageActivationError.noRollbackGeneration(
            damaged.packageID.rawValue
        ))
        let subject = try makeAuthority(
            durable: durable,
            publicKey: key.publicKey.x963Representation,
            exactRollback: { packageID, _, _ in
                .rolledBack(try await rollback.perform(packageID))
            }
        )

        let snapshot = try await subject.refresh()

        XCTAssertEqual(
            snapshot.repository.availablePackageIDs,
            ["essential-free-v1", "paid-pack-02"]
        )
        XCTAssertEqual(snapshot.unavailableCurrentPackageIDs, ["paid-pack-01"])
        XCTAssertNil(
            snapshot.reconciledInstalledIndex.activeGeneration(for: "paid-pack-01")
        )
        XCTAssertNotNil(
            snapshot.reconciledInstalledIndex.activeGeneration(for: "paid-pack-02")
        )
        XCTAssertNil(snapshot.repository.chapter("steppe-comes-west"))
        XCTAssertNotNil(snapshot.repository.chapter("rome-gathers-europe"))
        XCTAssertNil(snapshot.verifiedPackage(for: "paid-pack-01"))
        XCTAssertNotNil(snapshot.verifiedPackage(for: "paid-pack-02"))
    }

    func testFutureDurableAuthorityInvalidatesPaidRuntimeButLeavesEssentialAvailable() async throws {
        let key = P256.Signing.PrivateKey()
        let paid = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "active"
        )
        defer { try? FileManager.default.removeItem(at: paid.root) }
        let generation = generation(for: paid, sequence: 1)
        let source = MutableAuthoritySource(authority: authority(
            active: [paid.packageID: (generation, paid.root)],
            retained: [:]
        ))
        let subject = try makeAuthority(
            provider: { try await source.load() },
            publicKey: key.publicKey.x963Representation
        )
        let firstSnapshot = try await subject.refresh()
        XCTAssertEqual(
            firstSnapshot.repository.availablePackageIDs,
            ["essential-free-v1", "paid-pack-01"]
        )

        await source.fail(with: .requiresNewerApp(
            InstalledPackageIndex.currentFormatVersion + 1
        ))
        do {
            _ = try await subject.refresh()
            XCTFail("Future authority must fail closed")
        } catch {
            XCTAssertEqual(
                error as? InstalledPackageIndexError,
                .requiresNewerApp(InstalledPackageIndex.currentFormatVersion + 1)
            )
        }

        let invalidated = await subject.snapshot()
        XCTAssertEqual(
            invalidated.repository.availablePackageIDs,
            ["essential-free-v1"]
        )
        XCTAssertEqual(invalidated.reconciledInstalledIndex, .empty)
    }

    func testStaleAssetFailureCannotMutateANewerDurableGeneration() async throws {
        let key = P256.Signing.PrivateKey()
        let paid = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "stale-report"
        )
        defer { try? FileManager.default.removeItem(at: paid.root) }
        let oldGeneration = generation(for: paid, sequence: 1)
        let newerGeneration = InstalledPackageGeneration(
            generationID: "managed-paid-pack-01-newer",
            packageID: paid.packageID,
            packageVersion: paid.manifest.packageVersion,
            manifestDigest: paid.manifest.manifestDigest,
            relativePath: "generations/managed-paid-pack-01-newer",
            activationSequence: 2
        )
        let source = MutableAuthoritySource(authority: authority(
            active: [paid.packageID: (oldGeneration, paid.root)],
            retained: [:]
        ))
        let mutations = RecoveryMutationRecorder()
        let subject = try makeAuthority(
            provider: { try await source.load() },
            publicKey: key.publicKey.x963Representation,
            exactRollback: { packageID, active, previous in
                await mutations.recordRollback(packageID, active, previous)
                return .staleAuthority
            },
            deactivate: { packageID, active in
                await mutations.recordDeactivation(packageID, active)
                return .staleAuthority
            }
        )
        let snapshot = try await subject.refresh()
        let reportAuthority = try XCTUnwrap(
            snapshot.assetFailureAuthority(for: paid.packageID)
        )
        await source.set(authority: authority(
            active: [paid.packageID: (newerGeneration, paid.root)],
            retained: [:]
        ))

        let outcome = await subject.reportAssetFailure(
            packageID: paid.packageID,
            expectedAuthority: reportAuthority
        )

        let rollbackCount = await mutations.rollbackCount
        let deactivationCount = await mutations.deactivationCount
        let durableAfterStale = try await source.load()
        XCTAssertEqual(outcome, .ignoredStaleReport)
        XCTAssertEqual(rollbackCount, 0)
        XCTAssertEqual(deactivationCount, 0)
        XCTAssertEqual(durableAfterStale.index.activeGeneration(
            for: paid.packageID
        ), newerGeneration)
    }

    func testFutureAndDivergentAuthorityLeaveSnapshotAndDurableStateUntouched()
        async throws
    {
        let key = P256.Signing.PrivateKey()
        let paid = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "future-report"
        )
        defer { try? FileManager.default.removeItem(at: paid.root) }
        let active = generation(for: paid, sequence: 1)
        let failures: [InstalledPackageIndexError] = [
            .requiresNewerApp(InstalledPackageIndex.currentFormatVersion + 1),
            .corruptIndex,
        ]
        for failure in failures {
            let source = MutableAuthoritySource(authority: authority(
                active: [paid.packageID: (active, paid.root)],
                retained: [:]
            ))
            let mutations = RecoveryMutationRecorder()
            let subject = try makeAuthority(
                provider: { try await source.load() },
                publicKey: key.publicKey.x963Representation,
                exactRollback: { packageID, current, previous in
                    await mutations.recordRollback(packageID, current, previous)
                    return .staleAuthority
                },
                deactivate: { packageID, current in
                    await mutations.recordDeactivation(packageID, current)
                    return .staleAuthority
                }
            )
            let snapshot = try await subject.refresh()
            let reportAuthority = try XCTUnwrap(
                snapshot.assetFailureAuthority(for: paid.packageID)
            )
            await source.fail(with: failure)

            let outcome = await subject.reportAssetFailure(
                packageID: paid.packageID,
                expectedAuthority: reportAuthority
            )

            let current = await subject.snapshot()
            let rollbackCount = await mutations.rollbackCount
            let deactivationCount = await mutations.deactivationCount
            XCTAssertEqual(outcome, .ignoredDurableAuthority)
            XCTAssertEqual(current.revision, snapshot.revision)
            XCTAssertEqual(
                current.repository.availablePackageIDs,
                snapshot.repository.availablePackageIDs
            )
            XCTAssertEqual(rollbackCount, 0)
            XCTAssertEqual(deactivationCount, 0)
        }
    }

    func testEssentialAssetFailureRequiresReinstallWithoutCallingMutationHooks()
        async throws
    {
        let key = P256.Signing.PrivateKey()
        let mutations = RecoveryMutationRecorder()
        let subject = try makeAuthority(
            durable: RetainedPackageAuthority(index: .empty, locationsByPackage: [:]),
            publicKey: key.publicKey.x963Representation,
            exactRollback: { packageID, current, previous in
                await mutations.recordRollback(packageID, current, previous)
                return .staleAuthority
            },
            deactivate: { packageID, current in
                await mutations.recordDeactivation(packageID, current)
                return .staleAuthority
            }
        )
        let snapshot = await subject.snapshot()
        let reportAuthority = try XCTUnwrap(snapshot.assetFailureAuthority(
            for: LaunchContent.essentialPackageID
        ))

        let outcome = await subject.reportAssetFailure(
            packageID: LaunchContent.essentialPackageID,
            expectedAuthority: reportAuthority
        )

        let rollbackCount = await mutations.rollbackCount
        let deactivationCount = await mutations.deactivationCount
        XCTAssertEqual(outcome, .essentialRequiresReinstallOrUpdate)
        XCTAssertEqual(rollbackCount, 0)
        XCTAssertEqual(deactivationCount, 0)
    }

    func testPaidFailureWithoutPredecessorQuarantinesDurablyAndKeepsOtherPackage()
        async throws
    {
        let key = P256.Signing.PrivateKey()
        let root = FileManager.default.temporaryDirectory.appending(
            path: "journey-quarantine-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let failed = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "failed-current"
        )
        let unrelated = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-02"),
            privateKey: key,
            suffix: "unrelated-current"
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: failed.root)
            try? FileManager.default.removeItem(at: unrelated.root)
        }
        let activator = try PackageActivator(rootURL: root)
        let failedActivation = try await activate(
            failed,
            with: activator,
            publicKey: key.publicKey.x963Representation
        )
        let unrelatedActivation = try await activate(
            unrelated,
            with: activator,
            publicKey: key.publicKey.x963Representation
        )
        let subject = try makeAuthority(
            provider: { try await activator.retainedPackageAuthority() },
            publicKey: key.publicKey.x963Representation,
            exactRollback: { packageID, current, previous in
                try await activator.rollback(
                    packageID: packageID,
                    expectedActiveGeneration: current,
                    expectedPreviousGeneration: previous
                )
            },
            deactivate: { packageID, current in
                try await activator.deactivate(
                    packageID: packageID,
                    expectedActiveGeneration: current
                )
            }
        )
        let before = try await subject.refresh()
        let reportAuthority = try XCTUnwrap(
            before.assetFailureAuthority(for: failed.packageID)
        )

        let outcome = await subject.reportAssetFailure(
            packageID: failed.packageID,
            expectedAuthority: reportAuthority
        )

        XCTAssertEqual(outcome, .quarantined(failedActivation.generation))
        let after = await subject.snapshot()
        XCTAssertNil(after.repository.chapter("steppe-comes-west"))
        XCTAssertNotNil(after.repository.chapter("rome-gathers-europe"))
        XCTAssertNil(after.reconciledInstalledIndex.activeGeneration(
            for: failed.packageID
        ))
        XCTAssertEqual(after.reconciledInstalledIndex.activeGeneration(
            for: unrelated.packageID
        ), unrelatedActivation.generation)
        let durable = try await activator.installedIndex()
        XCTAssertNil(durable.activeGeneration(for: failed.packageID))
        XCTAssertEqual(durable.activeGeneration(for: unrelated.packageID),
                       unrelatedActivation.generation)
        XCTAssertTrue(durable.generations.contains(failedActivation.generation))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: failedActivation.packageURL.path
        ))
        XCTAssertEqual(
            try canonicalIndexState(
                at: root.appending(path: "index/installed-index-a.json")
            ),
            try canonicalIndexState(
                at: root.appending(path: "index/installed-index-b.json")
            )
        )
        XCTAssertTrue(try LaunchDownloadPlan(installedIndex: durable).packages
            .contains(where: { $0.id == failed.packageID }))

        let relaunchedActivator = try PackageActivator(rootURL: root)
        let relaunched = try makeAuthority(
            provider: {
                try await relaunchedActivator.retainedPackageAuthority()
            },
            publicKey: key.publicKey.x963Representation,
            exactRollback: { packageID, current, previous in
                try await relaunchedActivator.rollback(
                    packageID: packageID,
                    expectedActiveGeneration: current,
                    expectedPreviousGeneration: previous
                )
            },
            deactivate: { packageID, current in
                try await relaunchedActivator.deactivate(
                    packageID: packageID,
                    expectedActiveGeneration: current
                )
            }
        )
        let cold = try await relaunched.refresh()
        XCTAssertNil(cold.verifiedPackage(for: failed.packageID))
        XCTAssertNotNil(cold.verifiedPackage(for: unrelated.packageID))
        XCTAssertTrue(try LaunchDownloadPlan(
            installedIndex: cold.reconciledInstalledIndex
        ).packages.contains(where: { $0.id == failed.packageID }))
    }

    func testAssetFailureFullVerifiesImmediatePredecessorBeforeExactRollback()
        async throws
    {
        let key = P256.Signing.PrivateKey()
        let root = FileManager.default.temporaryDirectory.appending(
            path: "journey-rollback-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let previous = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "rollback-generation"
        )
        let current = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "rollback-generation"
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: previous.root)
            try? FileManager.default.removeItem(at: current.root)
        }
        let activator = try PackageActivator(rootURL: root)
        let previousActivation = try await activate(
            previous,
            with: activator,
            publicKey: key.publicKey.x963Representation
        )
        let currentActivation = try await activate(
            current,
            with: activator,
            publicKey: key.publicKey.x963Representation
        )
        let subject = try makeRecoveryAuthority(
            activator: activator,
            publicKey: key.publicKey.x963Representation
        )
        let before = try await subject.refresh()
        let reportAuthority = try XCTUnwrap(
            before.assetFailureAuthority(for: current.packageID)
        )
        try overwriteSameSize(
            at: currentActivation.packageURL.appending(path: "assets/lazy.bin")
        )

        let outcome = await subject.reportAssetFailure(
            packageID: current.packageID,
            expectedAuthority: reportAuthority
        )

        let durable = try await activator.installedIndex()
        let after = await subject.snapshot()
        XCTAssertEqual(outcome, .rolledBack(to: previousActivation.generation))
        XCTAssertEqual(durable.activeGeneration(
            for: current.packageID
        ), previousActivation.generation)
        XCTAssertEqual(after.packageRootURL(
            for: current.packageID
        ), previousActivation.packageURL)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: previousActivation.packageURL.path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: currentActivation.packageURL.path
        ))
    }

    func testCorruptImmediatePredecessorIsNeverActivatedAndCurrentIsQuarantined()
        async throws
    {
        let key = P256.Signing.PrivateKey()
        let root = FileManager.default.temporaryDirectory.appending(
            path: "journey-corrupt-predecessor-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let previous = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "quarantine-generation"
        )
        let current = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "quarantine-generation"
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: previous.root)
            try? FileManager.default.removeItem(at: current.root)
        }
        let activator = try PackageActivator(rootURL: root)
        let previousActivation = try await activate(
            previous,
            with: activator,
            publicKey: key.publicKey.x963Representation
        )
        let currentActivation = try await activate(
            current,
            with: activator,
            publicKey: key.publicKey.x963Representation
        )
        try overwriteSameSize(
            at: previousActivation.packageURL.appending(path: "assets/lazy.bin")
        )
        let subject = try makeRecoveryAuthority(
            activator: activator,
            publicKey: key.publicKey.x963Representation
        )
        let before = try await subject.refresh()
        let reportAuthority = try XCTUnwrap(
            before.assetFailureAuthority(for: current.packageID)
        )

        let outcome = await subject.reportAssetFailure(
            packageID: current.packageID,
            expectedAuthority: reportAuthority
        )

        XCTAssertEqual(outcome, .quarantined(currentActivation.generation))
        let durable = try await activator.installedIndex()
        XCTAssertNil(durable.activeGeneration(for: current.packageID))
        XCTAssertNotEqual(durable.activeGeneration(for: current.packageID),
                          previousActivation.generation)
        XCTAssertTrue(durable.generations.contains(previousActivation.generation))
        XCTAssertTrue(durable.generations.contains(currentActivation.generation))
        let after = await subject.snapshot()
        XCTAssertNil(after.verifiedPackage(for: current.packageID))
    }

    func testSaveMigrationReversionByteVerifiesAndSelectsExactPriorSnapshotGeneration()
        async throws
    {
        let key = P256.Signing.PrivateKey()
        let currentVersion = try XCTUnwrap(
            LaunchContent.collectionManifest.packages.first {
                $0.id == PackageID("paid-pack-01")
            }
        ).version
        let previousVersion = SchemaVersion(major: 0, minor: 9)
        let previous = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "migration-previous-v1",
            packageVersion: previousVersion
        )
        let current = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "migration-current-v1",
            packageVersion: currentVersion
        )
        defer {
            try? FileManager.default.removeItem(at: previous.root)
            try? FileManager.default.removeItem(at: current.root)
        }
        let previousGeneration = generation(for: previous, sequence: 1)
        let currentGeneration = generation(for: current, sequence: 2)
        let source = MutableAuthoritySource(authority: authority(
            active: [current.packageID: (currentGeneration, current.root)],
            retained: [previous.packageID: (previousGeneration, previous.root)]
        ))
        let revertedAuthority = authority(
            active: [previous.packageID: (previousGeneration, previous.root)],
            retained: [current.packageID: (currentGeneration, current.root)]
        )
        let mutations = RecoveryMutationRecorder()
        let subject = try makeAuthority(
            provider: { try await source.load() },
            publicKey: key.publicKey.x963Representation,
            exactRollback: { packageID, active, prior in
                await mutations.recordRollback(packageID, active, prior)
                await source.set(authority: revertedAuthority)
                return .rolledBack(ActivatedPackage(
                    generation: previousGeneration,
                    packageURL: previous.root
                ))
            }
        )
        let before = try await subject.refresh()
        XCTAssertEqual(
            before.verifiedPackage(for: current.packageID)?
                .manifest.packageVersion,
            currentVersion
        )

        let reverted = try await subject.revertSaveMigrationAuthorityChange(
            packageID: previous.packageID,
            expectedCurrent: currentGeneration,
            expectedPrevious: previousGeneration
        )

        let rollbackCount = await mutations.rollbackCount
        XCTAssertEqual(rollbackCount, 1)
        XCTAssertEqual(
            reverted?.reconciledInstalledIndex.activeGeneration(
                for: previous.packageID
            ),
            previousGeneration
        )
        XCTAssertEqual(
            reverted?.verifiedPackage(for: previous.packageID)?
                .manifest.manifestDigest,
            previous.manifest.manifestDigest
        )
        XCTAssertEqual(
            reverted?.verifiedPackage(for: previous.packageID)?
                .manifest.packageVersion,
            previousVersion
        )
        XCTAssertNotNil(
            reverted?.repository.chapter("steppe-comes-west")
        )
    }

    func testSaveMigrationReversionDeactivatesExactNewPackageWithoutPredecessor()
        async throws
    {
        let key = P256.Signing.PrivateKey()
        let current = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "migration-added"
        )
        defer { try? FileManager.default.removeItem(at: current.root) }
        let currentGeneration = generation(for: current, sequence: 1)
        let source = MutableAuthoritySource(authority: authority(
            active: [current.packageID: (currentGeneration, current.root)],
            retained: [:]
        ))
        let mutations = RecoveryMutationRecorder()
        let subject = try makeAuthority(
            provider: { try await source.load() },
            publicKey: key.publicKey.x963Representation,
            deactivate: { packageID, active in
                await mutations.recordDeactivation(packageID, active)
                await source.set(authority: RetainedPackageAuthority(
                    index: InstalledPackageIndex(
                        nextActivationSequence: 2,
                        generations: [currentGeneration],
                        activeGenerationByPackage: [:]
                    ),
                    locationsByPackage: [:]
                ))
                return .deactivated(active)
            }
        )
        _ = try await subject.refresh()

        let reverted = try await subject.revertSaveMigrationAuthorityChange(
            packageID: current.packageID,
            expectedCurrent: currentGeneration,
            expectedPrevious: nil
        )

        let deactivationCount = await mutations.deactivationCount
        XCTAssertEqual(deactivationCount, 1)
        XCTAssertNil(reverted?.reconciledInstalledIndex.activeGeneration(
            for: current.packageID
        ))
        XCTAssertNil(reverted?.verifiedPackage(for: current.packageID))
    }

    func testRollbackSuppressesRefreshWhichCapturedSupersededGenerationBeforeCAS()
        async throws
    {
        let key = P256.Signing.PrivateKey()
        let currentVersion = try XCTUnwrap(
            LaunchContent.collectionManifest.packages.first {
                $0.id == PackageID("paid-pack-01")
            }
        ).version
        let previousVersion = SchemaVersion(major: 0, minor: 9)
        let previous = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "race-rollback-previous",
            packageVersion: previousVersion
        )
        let current = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "race-rollback-current",
            packageVersion: currentVersion
        )
        defer {
            try? FileManager.default.removeItem(at: previous.root)
            try? FileManager.default.removeItem(at: current.root)
        }
        let previousGeneration = generation(for: previous, sequence: 1)
        let currentGeneration = generation(for: current, sequence: 2)
        let initial = authority(
            active: [
                current.packageID: (currentGeneration, current.root),
            ],
            retained: [
                previous.packageID: (previousGeneration, previous.root),
            ]
        )
        let rolledBack = authority(
            active: [
                previous.packageID: (previousGeneration, previous.root),
            ],
            retained: [
                current.packageID: (currentGeneration, current.root),
            ]
        )
        let source = GatedMutableJourneyAuthoritySource(authority: initial)
        let mutationGate = JourneyAuthorityRefreshGate()
        let staleReadGate = JourneyAuthorityRefreshGate()
        let freshReadGate = JourneyAuthorityRefreshGate()
        let subject = try makeAuthority(
            provider: { try await source.load() },
            publicKey: key.publicKey.x963Representation,
            exactRollback: { packageID, expectedCurrent, expectedPrevious in
                await mutationGate.enterAndWait()
                guard await source.replaceAuthority(
                    expectedActive: expectedCurrent,
                    with: rolledBack,
                    armNextRead: freshReadGate
                ) else {
                    return .staleAuthority
                }
                return .rolledBack(ActivatedPackage(
                    generation: expectedPrevious,
                    packageURL: previous.root
                ))
            }
        )
        let before = try await subject.refresh()
        XCTAssertEqual(
            before.reconciledInstalledIndex.activeGeneration(
                for: current.packageID
            ),
            currentGeneration
        )
        let updates = await subject.snapshotUpdates()
        var updateIterator = updates.makeAsyncIterator()
        let observedBefore = await updateIterator.next()
        XCTAssertEqual(
            observedBefore?.reconciledInstalledIndex
                .activeGeneration(for: current.packageID),
            currentGeneration
        )

        let reversion = Task {
            try await subject.revertSaveMigrationAuthorityChange(
                packageID: current.packageID,
                expectedCurrent: currentGeneration,
                expectedPrevious: previousGeneration
            )
        }
        await mutationGate.waitUntilEntered()
        await source.armNextRead(staleReadGate)
        let staleRefresh = Task { try await subject.refresh() }
        await staleReadGate.waitUntilEntered()

        await mutationGate.open()
        await freshReadGate.waitUntilEntered()
        let withdrawnUpdate = await updateIterator.next()
        let withdrawn = try XCTUnwrap(withdrawnUpdate)
        XCTAssertNil(withdrawn.reconciledInstalledIndex.activeGeneration(
            for: current.packageID
        ))
        XCTAssertNil(withdrawn.verifiedPackage(for: current.packageID))

        // Cancellation cannot force an already-captured provider read to
        // disappear. Let that v2 candidate complete while the mandatory v1
        // rebuild remains gated, and prove it cannot escape or republish.
        await staleReadGate.open()
        let staleCaller = try await staleRefresh.value
        XCTAssertNil(staleCaller.reconciledInstalledIndex.activeGeneration(
            for: current.packageID
        ))
        XCTAssertNil(staleCaller.verifiedPackage(for: current.packageID))
        let duringFreshRebuild = await subject.snapshot()
        XCTAssertNil(duringFreshRebuild.reconciledInstalledIndex
            .activeGeneration(for: current.packageID))

        await freshReadGate.open()
        let reverted = try await reversion.value
        XCTAssertEqual(
            reverted?.reconciledInstalledIndex.activeGeneration(
                for: current.packageID
            ),
            previousGeneration
        )
        XCTAssertEqual(
            reverted?.verifiedPackage(for: current.packageID)?
                .manifest.packageVersion,
            previousVersion
        )
        let restoredUpdate = await updateIterator.next()
        let restored = try XCTUnwrap(restoredUpdate)
        XCTAssertEqual(
            restored.reconciledInstalledIndex.activeGeneration(
                for: current.packageID
            ),
            previousGeneration
        )
    }

    func testDeactivationSuppressesRefreshWhichCapturedGenerationBeforeCAS()
        async throws
    {
        let key = P256.Signing.PrivateKey()
        let current = try makeSignedPackage(
            payload: JourneyContentFixtures.package("paid-pack-01"),
            privateKey: key,
            suffix: "race-deactivation-current"
        )
        defer { try? FileManager.default.removeItem(at: current.root) }
        let currentGeneration = generation(for: current, sequence: 1)
        let initial = authority(
            active: [
                current.packageID: (currentGeneration, current.root),
            ],
            retained: [:]
        )
        let deactivated = RetainedPackageAuthority(
            index: InstalledPackageIndex(
                nextActivationSequence: 2,
                generations: [currentGeneration],
                activeGenerationByPackage: [:]
            ),
            locationsByPackage: [:]
        )
        let source = GatedMutableJourneyAuthoritySource(authority: initial)
        let mutationGate = JourneyAuthorityRefreshGate()
        let staleReadGate = JourneyAuthorityRefreshGate()
        let freshReadGate = JourneyAuthorityRefreshGate()
        let subject = try makeAuthority(
            provider: { try await source.load() },
            publicKey: key.publicKey.x963Representation,
            deactivate: { _, expectedCurrent in
                await mutationGate.enterAndWait()
                guard await source.replaceAuthority(
                    expectedActive: expectedCurrent,
                    with: deactivated,
                    armNextRead: freshReadGate
                ) else {
                    return .staleAuthority
                }
                return .deactivated(expectedCurrent)
            }
        )
        _ = try await subject.refresh()
        let updates = await subject.snapshotUpdates()
        var updateIterator = updates.makeAsyncIterator()
        let observedBefore = await updateIterator.next()
        XCTAssertEqual(
            observedBefore?.reconciledInstalledIndex
                .activeGeneration(for: current.packageID),
            currentGeneration
        )

        let reversion = Task {
            try await subject.revertSaveMigrationAuthorityChange(
                packageID: current.packageID,
                expectedCurrent: currentGeneration,
                expectedPrevious: nil
            )
        }
        await mutationGate.waitUntilEntered()
        await source.armNextRead(staleReadGate)
        let staleRefresh = Task { try await subject.refresh() }
        await staleReadGate.waitUntilEntered()

        await mutationGate.open()
        await freshReadGate.waitUntilEntered()
        let withdrawnUpdate = await updateIterator.next()
        let withdrawn = try XCTUnwrap(withdrawnUpdate)
        XCTAssertNil(withdrawn.reconciledInstalledIndex.activeGeneration(
            for: current.packageID
        ))

        await staleReadGate.open()
        let staleCaller = try await staleRefresh.value
        XCTAssertNil(staleCaller.reconciledInstalledIndex.activeGeneration(
            for: current.packageID
        ))
        XCTAssertNil(staleCaller.verifiedPackage(for: current.packageID))
        let duringFreshRebuild = await subject.snapshot()
        XCTAssertNil(duringFreshRebuild.reconciledInstalledIndex
            .activeGeneration(for: current.packageID))

        await freshReadGate.open()
        let reverted = try await reversion.value
        XCTAssertNil(reverted?.reconciledInstalledIndex.activeGeneration(
            for: current.packageID
        ))
        XCTAssertNil(reverted?.verifiedPackage(for: current.packageID))
        let rebuiltUpdate = await updateIterator.next()
        let rebuilt = try XCTUnwrap(rebuiltUpdate)
        XCTAssertNil(rebuilt.reconciledInstalledIndex.activeGeneration(
            for: current.packageID
        ))
    }

    private func makeRecoveryAuthority(
        activator: PackageActivator,
        publicKey: Data
    ) throws -> VerifiedJourneyRepositoryAuthority {
        try makeAuthority(
            provider: { try await activator.retainedPackageAuthority() },
            publicKey: publicKey,
            exactRollback: { packageID, current, previous in
                try await activator.rollback(
                    packageID: packageID,
                    expectedActiveGeneration: current,
                    expectedPreviousGeneration: previous
                )
            },
            deactivate: { packageID, current in
                try await activator.deactivate(
                    packageID: packageID,
                    expectedActiveGeneration: current
                )
            }
        )
    }

    private func activate(
        _ package: SignedTestPackage,
        with activator: PackageActivator,
        publicKey: Data
    ) async throws -> ActivatedPackage {
        let staging = try await activator.makeStagingDirectory()
        for child in try FileManager.default.contentsOfDirectory(
            at: package.root,
            includingPropertiesForKeys: nil
        ) {
            try FileManager.default.copyItem(
                at: child,
                to: staging.appending(path: child.lastPathComponent)
            )
        }
        let expected = try XCTUnwrap(
            LaunchContent.collectionManifest.packages.first {
                $0.id == package.packageID
            }
        )
        return try await activator.activate(
            stagedPackageURL: staging,
            expectedPackage: expected,
            trustedPublicKeys: ["test-launch-key": publicKey],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1)
        )
    }

    private func overwriteSameSize(at url: URL) throws {
        var bytes = try Data(contentsOf: url)
        guard !bytes.isEmpty else {
            throw PackageVerificationError.fileSizeMismatch(url.lastPathComponent)
        }
        bytes[bytes.startIndex] ^= 0xff
        try bytes.write(to: url, options: .atomic)
    }

    private func canonicalIndexState(at url: URL) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let envelope = try XCTUnwrap(object as? [String: Any])
        let index = try XCTUnwrap(envelope["index"])
        return try JSONSerialization.data(
            withJSONObject: index,
            options: [.sortedKeys]
        )
    }

    private func makeAuthority(
        durable: RetainedPackageAuthority,
        publicKey: Data,
        exactRollback: @escaping VerifiedJourneyRepositoryAuthority.ExactRollback = {
            _, _, _ in .staleAuthority
        },
        deactivate: @escaping VerifiedJourneyRepositoryAuthority.Deactivate = {
            _, _ in .staleAuthority
        }
    ) throws -> VerifiedJourneyRepositoryAuthority {
        try makeAuthority(
            provider: { durable },
            publicKey: publicKey,
            exactRollback: exactRollback,
            deactivate: deactivate
        )
    }

    private func makeAuthority(
        provider: @escaping VerifiedJourneyRepositoryAuthority.AuthorityProvider,
        publicKey: Data,
        exactRollback: @escaping VerifiedJourneyRepositoryAuthority.ExactRollback = {
            _, _, _ in .staleAuthority
        },
        deactivate: @escaping VerifiedJourneyRepositoryAuthority.Deactivate = {
            _, _ in .staleAuthority
        }
    ) throws -> VerifiedJourneyRepositoryAuthority {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let essentialSpec = try XCTUnwrap(
            LaunchContent.collectionManifest.packages.first {
                $0.id == LaunchContent.essentialPackageID
            }
        )
        let verifiedEssential = VerifiedContentPackage(
            manifest: SignedPackageManifest(
                packageID: essentialSpec.id,
                packageVersion: essentialSpec.version,
                schemaVersion: essential.schemaVersion,
                minimumRuntime: essentialSpec.minimumRuntime,
                files: [],
                manifestDigest: String(repeating: "a", count: 64),
                signature: PackageSignature(
                    algorithm: ContentPackageVerifier.signatureAlgorithm,
                    keyID: "test-launch-key",
                    value: "AA=="
                )
            ),
            payload: essential
        )
        return try VerifiedJourneyRepositoryAuthority(
            bundledEssentialPackage: verifiedEssential,
            bundledEssentialRootURL: URL(fileURLWithPath: "/signed-app-bundle/JourneyContent"),
            trustedPublicKeys: ["test-launch-key": publicKey],
            authorityProvider: provider,
            exactRollback: exactRollback,
            deactivate: deactivate
        )
    }

    private func authority(
        active: [PackageID: (InstalledPackageGeneration, URL)],
        retained: [PackageID: (InstalledPackageGeneration, URL)]
    ) -> RetainedPackageAuthority {
        let generations = (active.values.map(\.0) + retained.values.map(\.0)).sorted {
            $0.activationSequence < $1.activationSequence
        }
        let index = InstalledPackageIndex(
            nextActivationSequence: (generations.map(\.activationSequence).max() ?? 0) + 1,
            generations: generations,
            activeGenerationByPackage: active.mapValues(\.0.generationID)
        )
        var locations: [PackageID: RetainedPackageLocations] = [:]
        for (packageID, value) in active {
            let prior = retained[packageID]
            locations[packageID] = RetainedPackageLocations(
                activeGeneration: value.0,
                activePackage: ActivatedPackage(
                    generation: value.0,
                    packageURL: value.1.standardizedFileURL
                ),
                previousGeneration: prior?.0,
                previousPackage: prior.map {
                    ActivatedPackage(
                        generation: $0.0,
                        packageURL: $0.1.standardizedFileURL
                    )
                }
            )
        }
        return RetainedPackageAuthority(index: index, locationsByPackage: locations)
    }

    private func generation(
        for package: SignedTestPackage,
        sequence: UInt64
    ) -> InstalledPackageGeneration {
        InstalledPackageGeneration(
            generationID: "managed-\(package.packageID.rawValue)-\(package.suffix)",
            packageID: package.packageID,
            packageVersion: package.manifest.packageVersion,
            manifestDigest: package.manifest.manifestDigest,
            relativePath: "generations/managed-\(package.packageID.rawValue)-\(package.suffix)",
            activationSequence: sequence
        )
    }

    private func makeSignedPackage(
        payload: ContentPackagePayload,
        privateKey: P256.Signing.PrivateKey,
        suffix: String,
        packageVersion: SchemaVersion? = nil
    ) throws -> SignedTestPackage {
        let expected = try XCTUnwrap(
            LaunchContent.collectionManifest.packages.first { $0.id == payload.packageID }
        )
        let root = FileManager.default.temporaryDirectory.appending(
            path: "journey-authority-\(payload.packageID.rawValue)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let payloadURL = root.appending(path: "content/payload.json")
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payloadData = try ContentDocumentDecoder.encodePackage(payload)
        try payloadData.write(to: payloadURL)
        let assetURL = root.appending(path: "assets/lazy.bin")
        try FileManager.default.createDirectory(
            at: assetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let assetData = Data("lazy-asset-\(suffix)".utf8)
        try assetData.write(to: assetURL)
        let files = [
            PackageFileRecord(
                path: "assets/lazy.bin",
                bytes: Int64(assetData.count),
                sha256: SHA256.hash(data: assetData).map {
                    String(format: "%02x", $0)
                }.joined()
            ),
            PackageFileRecord(
                path: "content/payload.json",
                bytes: Int64(payloadData.count),
                sha256: SHA256.hash(data: payloadData).map {
                    String(format: "%02x", $0)
                }.joined()
            ),
        ]
        let unsigned = SignedPackageManifest(
            packageID: payload.packageID,
            packageVersion: packageVersion ?? expected.version,
            schemaVersion: payload.schemaVersion,
            minimumRuntime: expected.minimumRuntime,
            files: files,
            manifestDigest: String(repeating: "0", count: 64),
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "test-launch-key",
                value: "AA=="
            )
        )
        let digest = try ContentPackageVerifier.manifestDigest(for: unsigned)
        let signature = try privateKey.signature(for: Data(digest.utf8))
        let manifest = SignedPackageManifest(
            packageID: unsigned.packageID,
            packageVersion: unsigned.packageVersion,
            schemaVersion: unsigned.schemaVersion,
            minimumRuntime: unsigned.minimumRuntime,
            files: unsigned.files,
            manifestDigest: digest,
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "test-launch-key",
                value: signature.derRepresentation.base64EncodedString()
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(
            to: root.appending(path: ContentPackageVerifier.manifestFileName),
            options: .atomic
        )
        return SignedTestPackage(
            packageID: payload.packageID,
            suffix: suffix,
            root: root.standardizedFileURL,
            payloadURL: payloadURL,
            assetURL: assetURL,
            manifest: manifest
        )
    }

}

private struct SignedTestPackage {
    let packageID: PackageID
    let suffix: String
    let root: URL
    let payloadURL: URL
    let assetURL: URL
    let manifest: SignedPackageManifest
}

private actor RollbackRecorder {
    private let result: ActivatedPackage?
    private let error: (any Error)?
    private(set) var packageIDs: [PackageID] = []

    init(result: ActivatedPackage) {
        self.result = result
        error = nil
    }

    init(error: any Error) {
        result = nil
        self.error = error
    }

    func perform(_ packageID: PackageID) throws -> ActivatedPackage {
        packageIDs.append(packageID)
        if let error { throw error }
        return result!
    }
}

private actor MutableAuthoritySource {
    private var authority: RetainedPackageAuthority
    private var failure: InstalledPackageIndexError?

    init(authority: RetainedPackageAuthority) {
        self.authority = authority
    }

    func load() throws -> RetainedPackageAuthority {
        if let failure { throw failure }
        return authority
    }

    func fail(with error: InstalledPackageIndexError) {
        failure = error
    }

    func set(authority: RetainedPackageAuthority) {
        self.authority = authority
        failure = nil
    }
}

private actor GatedMutableJourneyAuthoritySource {
    private var authority: RetainedPackageAuthority
    private var nextReadGate: JourneyAuthorityRefreshGate?

    init(authority: RetainedPackageAuthority) {
        self.authority = authority
    }

    func armNextRead(_ gate: JourneyAuthorityRefreshGate) {
        nextReadGate = gate
    }

    func load() async throws -> RetainedPackageAuthority {
        let captured = authority
        let gate = nextReadGate
        nextReadGate = nil
        if let gate {
            await gate.enterAndWait()
        }
        return captured
    }

    func replaceAuthority(
        expectedActive: InstalledPackageGeneration,
        with replacement: RetainedPackageAuthority,
        armNextRead gate: JourneyAuthorityRefreshGate
    ) -> Bool {
        guard authority.index.activeGeneration(
            for: expectedActive.packageID
        ) == expectedActive else {
            return false
        }
        authority = replacement
        nextReadGate = gate
        return true
    }
}

private actor JourneyAuthorityRefreshGate {
    private var entered = false
    private var isOpen = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var openContinuation: CheckedContinuation<Void, Never>?

    func enterAndWait() async {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        guard !isOpen else { return }
        await withCheckedContinuation { openContinuation = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func open() {
        isOpen = true
        openContinuation?.resume()
        openContinuation = nil
    }
}

private actor RecoveryMutationRecorder {
    private(set) var rollbacks: [
        (PackageID, InstalledPackageGeneration, InstalledPackageGeneration)
    ] = []
    private(set) var deactivations: [(PackageID, InstalledPackageGeneration)] = []

    var rollbackCount: Int { rollbacks.count }
    var deactivationCount: Int { deactivations.count }

    func recordRollback(
        _ packageID: PackageID,
        _ current: InstalledPackageGeneration,
        _ previous: InstalledPackageGeneration
    ) {
        rollbacks.append((packageID, current, previous))
    }

    func recordDeactivation(
        _ packageID: PackageID,
        _ current: InstalledPackageGeneration
    ) {
        deactivations.append((packageID, current))
    }
}
