@testable import ContentDelivery
import ContentKit
import ContentKitTestSupport
import CryptoKit
import Foundation
import XCTest

final class ContentDeliveryTests: XCTestCase {
    func testVerifiedStagingBecomesActiveOnlyAfterIndexCommit() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let verifier = FakeVerifier()
        let activator = try PackageActivator(
            rootURL: root,
            verifier: verifier,
            generationID: { "generation-one" }
        )
        let staging = try await activator.makeStagingDirectory()
        try Data("verified package".utf8).write(to: staging.appending(path: "payload.bin"))

        let activated = try await activator.activate(
            stagedPackageURL: staging,
            expectedPackage: Self.package(version: .init(major: 1)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: activated.packageURL.path))
        let active = try await activator.activePackage(for: "paid-pack-01")
        let installed = try await activator.installedIndex()
        XCTAssertEqual(active, activated)
        XCTAssertEqual(installed.generations.count, 1)
    }

    func testVerificationFailureLeavesExistingGenerationActiveAndStagingUnpublished() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let verifier = FakeVerifier()
        let first = try PackageActivator(
            rootURL: root,
            verifier: verifier,
            generationID: { "generation-one" }
        )
        let firstStaging = try await first.makeStagingDirectory()
        try Data("first".utf8).write(to: firstStaging.appending(path: "payload.bin"))
        let original = try await first.activate(
            stagedPackageURL: firstStaging,
            expectedPackage: Self.package(version: .init(major: 1)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let failing = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(error: .rejected),
            generationID: { "generation-two" }
        )
        let rejectedStaging = try await failing.makeStagingDirectory()
        try Data("corrupt".utf8).write(to: rejectedStaging.appending(path: "payload.bin"))
        do {
            _ = try await failing.activate(
                stagedPackageURL: rejectedStaging,
                expectedPackage: Self.package(version: .init(major: 2)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("verification must fail closed")
        } catch {
            XCTAssertEqual(error as? FakeVerificationError, .rejected)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: rejectedStaging.path))
        let activeAfterFailure = try await failing.activePackage(for: "paid-pack-01")
        let indexAfterFailure = try await failing.installedIndex()
        XCTAssertEqual(activeAfterFailure, original)
        XCTAssertEqual(indexAfterFailure.generations.count, 1)
    }

    func testActivationRejectsDifferentBytesUnderTheSamePackageVersion() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-one", "generation-two"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )
        let specification = Self.package(version: .init(major: 1))
        let firstStaging = try await activator.makeStagingDirectory()
        try Data("first manifest bytes".utf8).write(
            to: firstStaging.appending(path: "payload.bin")
        )
        let original = try await activator.activate(
            stagedPackageURL: firstStaging,
            expectedPackage: specification,
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let conflictingStaging = try await activator.makeStagingDirectory()
        try Data("different bytes without a version change".utf8).write(
            to: conflictingStaging.appending(path: "payload.bin")
        )
        do {
            _ = try await activator.activate(
                stagedPackageURL: conflictingStaging,
                expectedPackage: specification,
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("Different package bytes require a new content version")
        } catch {
            XCTAssertEqual(
                error as? PackageActivationError,
                .sameVersionManifestMismatch("paid-pack-01", .init(major: 1))
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: conflictingStaging.path)
        )
        let activeAfterConflict = try await activator.activePackage(
            for: "paid-pack-01"
        )
        XCTAssertEqual(activeAfterConflict, original)
    }

    func testNormalActivationCannotRegressTheActivePackageVersion() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-two", "generation-one"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )
        let currentStaging = try await activator.makeStagingDirectory()
        try Data("version two".utf8).write(
            to: currentStaging.appending(path: "payload.bin")
        )
        let current = try await activator.activate(
            stagedPackageURL: currentStaging,
            expectedPackage: Self.package(version: .init(major: 2)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let olderStaging = try await activator.makeStagingDirectory()
        try Data("version one".utf8).write(
            to: olderStaging.appending(path: "payload.bin")
        )
        do {
            _ = try await activator.activate(
                stagedPackageURL: olderStaging,
                expectedPackage: Self.package(version: .init(major: 1)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("A downgrade must use the exact rollback authority")
        } catch {
            XCTAssertEqual(
                error as? PackageActivationError,
                .packageVersionRegression(
                    packageID: "paid-pack-01",
                    active: .init(major: 2),
                    candidate: .init(major: 1)
                )
            )
        }
        let activeAfterRegression = try await activator.activePackage(
            for: "paid-pack-01"
        )
        XCTAssertEqual(activeAfterRegression, current)
    }

    func testDeactivatedGenerationStillBlocksSameVersionDifferentBytes()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-one", "generation-two"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )
        let firstStaging = try await activator.makeStagingDirectory()
        try Data("retained-version-one".utf8).write(
            to: firstStaging.appending(path: "payload.bin")
        )
        let retained = try await activator.activate(
            stagedPackageURL: firstStaging,
            expectedPackage: Self.package(version: .init(major: 1)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )
        let deactivation = try await activator.deactivate(
            packageID: retained.generation.packageID,
            expectedActiveGeneration: retained.generation
        )
        XCTAssertEqual(deactivation, .deactivated(retained.generation))

        let conflictingStaging = try await activator.makeStagingDirectory()
        try Data("different-retained-v1".utf8).write(
            to: conflictingStaging.appending(path: "payload.bin")
        )
        do {
            _ = try await activator.activate(
                stagedPackageURL: conflictingStaging,
                expectedPackage: Self.package(version: .init(major: 1)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("Deactivation cannot erase same-version byte authority")
        } catch {
            XCTAssertEqual(
                error as? PackageActivationError,
                .sameVersionManifestMismatch(
                    "paid-pack-01",
                    .init(major: 1)
                )
            )
        }
        let index = try await activator.installedIndex()
        XCTAssertNil(index.activeGeneration(for: "paid-pack-01"))
        XCTAssertEqual(index.generations, [retained.generation])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: retained.packageURL.path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: conflictingStaging.path
        ))
    }

    func testDeactivatedHigherVersionStillBlocksNormalRegression()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-two", "generation-one"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )
        let currentStaging = try await activator.makeStagingDirectory()
        try Data("retained-version-two".utf8).write(
            to: currentStaging.appending(path: "payload.bin")
        )
        let retained = try await activator.activate(
            stagedPackageURL: currentStaging,
            expectedPackage: Self.package(version: .init(major: 2)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )
        _ = try await activator.deactivate(
            packageID: retained.generation.packageID,
            expectedActiveGeneration: retained.generation
        )

        let olderStaging = try await activator.makeStagingDirectory()
        try Data("candidate-version-one".utf8).write(
            to: olderStaging.appending(path: "payload.bin")
        )
        do {
            _ = try await activator.activate(
                stagedPackageURL: olderStaging,
                expectedPackage: Self.package(version: .init(major: 1)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("A retained generation remains downgrade authority")
        } catch {
            XCTAssertEqual(
                error as? PackageActivationError,
                .packageVersionRegression(
                    packageID: "paid-pack-01",
                    active: .init(major: 2),
                    candidate: .init(major: 1)
                )
            )
        }
        let index = try await activator.installedIndex()
        XCTAssertNil(index.activeGeneration(for: "paid-pack-01"))
        XCTAssertEqual(index.generations, [retained.generation])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: retained.packageURL.path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: olderStaging.path
        ))
    }

    func testRollbackChangesOnlyAtomicIndexPointerAndRetainsBothImmutableGenerations() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-one", "generation-two"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )

        let firstStaging = try await activator.makeStagingDirectory()
        try Data("first".utf8).write(to: firstStaging.appending(path: "payload.bin"))
        let first = try await activator.activate(
            stagedPackageURL: firstStaging,
            expectedPackage: Self.package(version: .init(major: 1)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let secondStaging = try await activator.makeStagingDirectory()
        try Data("second".utf8).write(to: secondStaging.appending(path: "payload.bin"))
        let second = try await activator.activate(
            stagedPackageURL: secondStaging,
            expectedPackage: Self.package(version: .init(major: 2)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let activeBeforeRollback = try await activator.activePackage(for: "paid-pack-01")
        XCTAssertEqual(activeBeforeRollback, second)
        let rolledBack = try await activator.rollback(packageID: "paid-pack-01")
        XCTAssertEqual(rolledBack, first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.packageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.packageURL.path))
        let indexAfterRollback = try await activator.installedIndex()
        XCTAssertEqual(indexAfterRollback.generations.count, 2)
        XCTAssertEqual(
            try canonicalIndexState(at: root.appending(path: "index/installed-index-a.json")),
            try canonicalIndexState(at: root.appending(path: "index/installed-index-b.json"))
        )
    }

    func testThreeActivationsRetainOnlyActiveAndImmediatePredecessorInBothSlots()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-one", "generation-two", "generation-three"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )
        var activations: [ActivatedPackage] = []
        for version in [1, 2, 3] {
            let staging = try await activator.makeStagingDirectory()
            try Data("v\(version)".utf8).write(to: staging.appending(path: "payload.bin"))
            activations.append(try await activator.activate(
                stagedPackageURL: staging,
                expectedPackage: Self.package(version: .init(major: version)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            ))
        }

        let index = try await activator.installedIndex()
        XCTAssertEqual(
            Set(index.generations.map(\.generationID)),
            Set(activations.suffix(2).map(\.generation.generationID))
        )
        let active = try await activator.activePackage(for: "paid-pack-01")
        XCTAssertEqual(active, activations[2])
        XCTAssertFalse(FileManager.default.fileExists(atPath: activations[0].packageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: activations[1].packageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: activations[2].packageURL.path))
        XCTAssertEqual(
            try canonicalIndexState(at: root.appending(path: "index/installed-index-a.json")),
            try canonicalIndexState(at: root.appending(path: "index/installed-index-b.json"))
        )
        let authority = try await activator.retainedPackageAuthority()
        XCTAssertEqual(authority.index, index)
        let retained = try XCTUnwrap(authority.locationsByPackage["paid-pack-01"])
        XCTAssertEqual(retained.activeGeneration, activations[2].generation)
        XCTAssertEqual(retained.activePackage, activations[2])
        XCTAssertEqual(retained.previousGeneration, activations[1].generation)
        XCTAssertEqual(retained.previousPackage, activations[1])

        let rolledBack = try await activator.rollback(packageID: "paid-pack-01")
        XCTAssertEqual(rolledBack, activations[1])
        XCTAssertTrue(FileManager.default.fileExists(atPath: rolledBack.packageURL.path))
        let indexAfterRollback = try await activator.installedIndex()
        XCTAssertEqual(
            indexAfterRollback.activeGeneration(for: "paid-pack-01"),
            activations[1].generation
        )
        XCTAssertEqual(
            try canonicalIndexState(at: root.appending(path: "index/installed-index-a.json")),
            try canonicalIndexState(at: root.appending(path: "index/installed-index-b.json"))
        )
    }

    func testRetainedAuthorityExposesRollbackWhenActiveDirectoryIsMissing() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-one", "generation-two"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )
        var activations: [ActivatedPackage] = []
        for version in [1, 2] {
            let staging = try await activator.makeStagingDirectory()
            try Data("v\(version)".utf8).write(to: staging.appending(path: "payload.bin"))
            activations.append(try await activator.activate(
                stagedPackageURL: staging,
                expectedPackage: Self.package(version: .init(major: version)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            ))
        }
        try FileManager.default.removeItem(at: activations[1].packageURL)

        do {
            _ = try await activator.installedIndex()
            XCTFail("the strict installed-index view must reject missing active bytes")
        } catch {
            XCTAssertEqual(
                error as? InstalledPackageIndexError,
                .missingActiveDirectory(activations[1].generation.generationID)
            )
        }

        let authority = try await activator.retainedPackageAuthority()
        let retained = try XCTUnwrap(authority.locationsByPackage["paid-pack-01"])
        XCTAssertEqual(retained.activeGeneration, activations[1].generation)
        XCTAssertNil(retained.activePackage)
        XCTAssertEqual(retained.previousGeneration, activations[0].generation)
        XCTAssertEqual(retained.previousPackage, activations[0])

        try Data("not a package directory".utf8).write(to: activations[1].packageURL)
        let damagedAuthority = try await activator.retainedPackageAuthority()
        let damagedRetained = try XCTUnwrap(
            damagedAuthority.locationsByPackage["paid-pack-01"]
        )
        XCTAssertEqual(damagedRetained.activeGeneration, activations[1].generation)
        XCTAssertNil(damagedRetained.activePackage)
        XCTAssertEqual(damagedRetained.previousPackage, activations[0])

        let rolledBack = try await activator.rollback(packageID: "paid-pack-01")
        XCTAssertEqual(rolledBack, activations[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: rolledBack.packageURL.path))
    }

    func testRetainedAuthorityRejectsActiveGenerationSymbolicLink() async throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideSentinel = outside.appending(path: "sentinel")
        try Data("outside".utf8).write(to: outsideSentinel)

        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { "generation-one" }
        )
        let staging = try await activator.makeStagingDirectory()
        try Data("active".utf8).write(to: staging.appending(path: "payload.bin"))
        let active = try await activator.activate(
            stagedPackageURL: staging,
            expectedPackage: Self.package(version: .init(major: 1)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )
        try FileManager.default.removeItem(at: active.packageURL)
        try FileManager.default.createSymbolicLink(
            at: active.packageURL,
            withDestinationURL: outside
        )

        do {
            _ = try await activator.retainedPackageAuthority()
            XCTFail("retained authority must never follow an active symbolic link")
        } catch {
            XCTAssertEqual(
                error as? PackageActivationError,
                .generationDirectoryIsSymbolicLink(active.generation.generationID)
            )
        }
        XCTAssertEqual(try Data(contentsOf: outsideSentinel), Data("outside".utf8))
    }

    func testActivationAfterRollbackRetainsTheRolledBackGenerationAsPredecessor()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-one", "generation-two", "generation-three"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )
        var firstTwo: [ActivatedPackage] = []
        for version in [1, 2] {
            let staging = try await activator.makeStagingDirectory()
            try Data("v\(version)".utf8).write(to: staging.appending(path: "payload.bin"))
            firstTwo.append(try await activator.activate(
                stagedPackageURL: staging,
                expectedPackage: Self.package(version: .init(major: version)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            ))
        }
        let rolledBack = try await activator.rollback(packageID: "paid-pack-01")
        XCTAssertEqual(rolledBack, firstTwo[0])

        let thirdStaging = try await activator.makeStagingDirectory()
        try Data("v3".utf8).write(to: thirdStaging.appending(path: "payload.bin"))
        let third = try await activator.activate(
            stagedPackageURL: thirdStaging,
            expectedPackage: Self.package(version: .init(major: 3)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let index = try await activator.installedIndex()
        XCTAssertEqual(
            Set(index.generations.map(\.generationID)),
            Set([firstTwo[0].generation.generationID, third.generation.generationID])
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstTwo[0].packageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstTwo[1].packageURL.path))
    }

    func testCommittedActivationSurvivesPostCommitMaintenanceFailure() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-one", "generation-two", "generation-three"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )
        var activations: [ActivatedPackage] = []
        for version in [1, 2] {
            let staging = try await activator.makeStagingDirectory()
            try Data("v\(version)".utf8).write(to: staging.appending(path: "payload.bin"))
            activations.append(try await activator.activate(
                stagedPackageURL: staging,
                expectedPackage: Self.package(version: .init(major: version)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            ))
        }
        // The third commit prunes generation one. Removing it first forces the
        // post-commit deletion pass to encounter a missing directory.
        try FileManager.default.removeItem(at: activations[0].packageURL)

        let staging = try await activator.makeStagingDirectory()
        try Data("v3".utf8).write(to: staging.appending(path: "payload.bin"))
        let third = try await activator.activate(
            stagedPackageURL: staging,
            expectedPackage: Self.package(version: .init(major: 3)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let active = try await activator.activePackage(for: "paid-pack-01")
        let index = try await activator.installedIndex()
        XCTAssertEqual(active, third)
        XCTAssertEqual(index.generations.count, 2)
    }

    func testColdStartAndExplicitReconciliationRemoveOnlyOwnedDirectOrphans()
        async throws
    {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideSentinel = outside.appending(path: "sentinel")
        try Data("outside".utf8).write(to: outsideSentinel)

        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { "generation-one" }
        )
        let staging = try await activator.makeStagingDirectory()
        try Data("active".utf8).write(to: staging.appending(path: "payload.bin"))
        let active = try await activator.activate(
            stagedPackageURL: staging,
            expectedPackage: Self.package(version: .init(major: 1)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let staleStaging = activator.stagingRootURL.appending(path: "incoming-stale")
        let orphan = activator.generationsRootURL.appending(
            path: "managed-paid-pack-01-crash-orphan"
        )
        let foreign = activator.generationsRootURL.appending(path: "foreign-library")
        let stagingLink = activator.stagingRootURL.appending(path: "incoming-linked")
        let generationLink = activator.generationsRootURL.appending(path: "managed-linked")
        for directory in [staleStaging, orphan, foreign] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(
            at: staleStaging.appending(path: "outside-link"),
            withDestinationURL: outside
        )
        try FileManager.default.createSymbolicLink(at: stagingLink, withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: generationLink, withDestinationURL: outside)

        let reopened = try PackageActivator(rootURL: root, verifier: FakeVerifier())
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleStaging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.packageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingLink.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: generationLink.path))
        XCTAssertEqual(try Data(contentsOf: outsideSentinel), Data("outside".utf8))

        let explicitStaging = reopened.stagingRootURL.appending(path: "incoming-explicit")
        let explicitOrphan = reopened.generationsRootURL.appending(
            path: "managed-paid-pack-01-explicit-orphan"
        )
        try FileManager.default.createDirectory(
            at: explicitStaging,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: explicitOrphan,
            withIntermediateDirectories: true
        )
        try await reopened.reconcileStorage()
        XCTAssertFalse(FileManager.default.fileExists(atPath: explicitStaging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: explicitOrphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
    }

    func testDivergentCurrentSlotsForbidColdAndExplicitDeletion() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-one", "generation-two"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )
        let firstStaging = try await activator.makeStagingDirectory()
        try Data("first".utf8).write(to: firstStaging.appending(path: "payload.bin"))
        _ = try await activator.activate(
            stagedPackageURL: firstStaging,
            expectedPackage: Self.package(version: .init(major: 1)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )
        let slotA = root.appending(path: "index/installed-index-a.json")
        let oldSlotA = try Data(contentsOf: slotA)

        let secondStaging = try await activator.makeStagingDirectory()
        try Data("second".utf8).write(to: secondStaging.appending(path: "payload.bin"))
        _ = try await activator.activate(
            stagedPackageURL: secondStaging,
            expectedPackage: Self.package(version: .init(major: 2)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )
        try oldSlotA.write(to: slotA, options: [.atomic])

        let staleStaging = activator.stagingRootURL.appending(path: "incoming-preserved")
        let orphan = activator.generationsRootURL.appending(
            path: "managed-paid-pack-01-preserved-orphan"
        )
        try FileManager.default.createDirectory(at: staleStaging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)

        let reopened = try PackageActivator(rootURL: root, verifier: FakeVerifier())
        XCTAssertTrue(FileManager.default.fileExists(atPath: staleStaging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        try await reopened.reconcileStorage()
        XCTAssertTrue(FileManager.default.fileExists(atPath: staleStaging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testNewestCorruptIndexSlotRecoversFromMirroredCompactState() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = GenerationIDs(["generation-one", "generation-two"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { ids.next() }
        )
        for version in [1, 2] {
            let staging = try await activator.makeStagingDirectory()
            try Data("v\(version)".utf8).write(to: staging.appending(path: "payload.bin"))
            _ = try await activator.activate(
                stagedPackageURL: staging,
                expectedPackage: Self.package(version: .init(major: version)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
        }

        let newestSlot = root.appending(path: "index/installed-index-b.json")
        try Data("truncated".utf8).write(to: newestSlot, options: [.atomic])

        let reopened = try PackageActivator(rootURL: root, verifier: FakeVerifier())
        let recovered = try await reopened.activePackage(for: "paid-pack-01")
        let recoveredIndex = try await reopened.installedIndex()
        XCTAssertEqual(recovered?.generation.packageVersion, SchemaVersion(major: 2))
        XCTAssertEqual(recoveredIndex.generations.count, 2)
    }

    func testFutureInstalledIndexAuthorityBlocksFallbackAndActivationWithoutOverwrite()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let activator = try PackageActivator(
            rootURL: root,
            verifier: FakeVerifier(),
            generationID: { "generation-one" }
        )
        let firstStaging = try await activator.makeStagingDirectory()
        try Data("first".utf8).write(to: firstStaging.appending(path: "payload.bin"))
        _ = try await activator.activate(
            stagedPackageURL: firstStaging,
            expectedPackage: Self.package(version: .init(major: 1)),
            trustedPublicKeys: [:],
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let slotA = root.appending(path: "index/installed-index-a.json")
        let slotB = root.appending(path: "index/installed-index-b.json")
        let originalA = try Data(contentsOf: slotA)
        let futureFormat = InstalledPackageIndex.currentFormatVersion + 1
        let futureB = try futureEnvelope(
            basedOn: originalA,
            payloadKey: "index",
            generation: 2,
            formatVersion: futureFormat
        )
        try futureB.write(to: slotB, options: [.atomic])

        do {
            _ = try await activator.installedIndex()
            XCTFail("an older app must not fall back past a newer index authority")
        } catch {
            XCTAssertEqual(
                error as? InstalledPackageIndexError,
                .requiresNewerApp(futureFormat)
            )
        }

        let blockedStaging = try await activator.makeStagingDirectory()
        try Data("blocked".utf8).write(to: blockedStaging.appending(path: "payload.bin"))
        do {
            _ = try await activator.activate(
                stagedPackageURL: blockedStaging,
                expectedPackage: Self.package(version: .init(major: 1)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("future index authority must block an older activation")
        } catch {
            XCTAssertEqual(
                error as? InstalledPackageIndexError,
                .requiresNewerApp(futureFormat)
            )
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: blockedStaging.path))
        XCTAssertEqual(try Data(contentsOf: slotA), originalA)
        XCTAssertEqual(try Data(contentsOf: slotB), futureB)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: activator.generationsRootURL,
                includingPropertiesForKeys: nil
            ).count,
            1
        )

        let futureOrphan = activator.generationsRootURL.appending(
            path: "managed-paid-pack-01-future-preserved"
        )
        try FileManager.default.createDirectory(
            at: futureOrphan,
            withIntermediateDirectories: true
        )
        try await activator.reconcileStorage()
        XCTAssertTrue(FileManager.default.fileExists(atPath: blockedStaging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: futureOrphan.path))
    }

    func testDirectoriesOutsideManagedStagingAndSymlinksAreRejected() async throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let activator = try PackageActivator(rootURL: root, verifier: FakeVerifier())

        do {
            _ = try await activator.activate(
                stagedPackageURL: outside,
                expectedPackage: Self.package(version: .init(major: 1)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("outside staging must be rejected")
        } catch {
            XCTAssertEqual(error as? PackageActivationError, .stagingDirectoryOutsideManagedRoot)
        }

        let real = try await activator.makeStagingDirectory()
        let link = activator.stagingRootURL.appending(path: "linked-package")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        do {
            _ = try await activator.activate(
                stagedPackageURL: link,
                expectedPackage: Self.package(version: .init(major: 1)),
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("symlink staging must be rejected")
        } catch {
            XCTAssertEqual(error as? PackageActivationError, .stagingDirectoryIsSymbolicLink)
        }
    }

    private static func package(version: SchemaVersion) -> ContentPackageSpec {
        ContentPackageSpec(
            id: "paid-pack-01",
            version: version,
            chapterIDs: ["steppe-comes-west"],
            maximumInstalledBytes: 750_000_000,
            minimumRuntime: .init(major: 1),
            isEssentialInstall: false
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "content-delivery-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func canonicalIndexState(at slotURL: URL) throws -> Data {
        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: slotURL)) as? [String: Any]
        )
        let index = try XCTUnwrap(envelope["index"])
        return try JSONSerialization.data(
            withJSONObject: index,
            options: [.sortedKeys, .withoutEscapingSlashes]
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
}

private enum FakeVerificationError: Error, Equatable {
    case rejected
}

private struct FakeVerifier: PackageActivationVerifying {
    let error: FakeVerificationError?

    init(error: FakeVerificationError? = nil) {
        self.error = error
    }

    func verifyPackage(
        at packageRoot: URL,
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys _: [String: Data],
        supportedSchema _: SchemaVersion,
        runtimeVersion _: SchemaVersion
    ) throws -> VerifiedActivationReceipt {
        if let error { throw error }
        let payload = try Data(contentsOf: packageRoot.appending(path: "payload.bin"))
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return VerifiedActivationReceipt(
            packageID: expectedPackage.id,
            packageVersion: expectedPackage.version,
            manifestDigest: digest
        )
    }
}

private final class GenerationIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}
