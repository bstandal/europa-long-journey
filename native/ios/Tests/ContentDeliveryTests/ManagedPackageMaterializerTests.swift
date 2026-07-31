@testable import ContentDelivery
import ContentKit
import ContentKitTestSupport
import CryptoKit
import Foundation
import System
import XCTest

final class ManagedPackageMaterializerTests: XCTestCase {
    func testAppleHostedInventoryIsMaterializedThenAtomicallyActivated() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let payload = Data("managed payload".utf8)
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
                try ManagedAssetPackLayout.filePath(
                    for: package.id,
                    packageRelativePath: "payload.bin"
                ): payload,
            ]
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier(),
            generationID: { "managed-generation-one" }
        )
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        let activated = try await materializer.downloadAndActivate(
            expectedPackage: package,
            trustedPublicKeys: Self.trustedPublicKeys,
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        XCTAssertEqual(provider.ensuredPackageIDs, [package.id])
        XCTAssertEqual(provider.requiredLatestVersions, [true])
        XCTAssertEqual(
            provider.openedRequests,
            [
                .init(
                    packageID: package.id,
                    path: try ManagedAssetPackLayout.manifestPath(for: package.id)
                ),
                .init(
                    packageID: package.id,
                    path: try ManagedAssetPackLayout.filePath(
                        for: package.id,
                        packageRelativePath: "payload.bin"
                    )
                ),
                .init(
                    packageID: package.id,
                    path: try ManagedAssetPackLayout.manifestPath(for: package.id)
                ),
            ]
        )
        XCTAssertEqual(provider.localStatusRequests, [package.id])
        XCTAssertEqual(provider.removeRequests, [package.id])
        XCTAssertTrue(
            try pendingCleanupDigests(in: materializer.cleanupAuthorityDirectoryURL).isEmpty
        )
        XCTAssertEqual(
            try Data(contentsOf: activated.packageURL.appending(path: "payload.bin")),
            payload
        )
        let activePackage = try await activator.activePackage(for: package.id)
        XCTAssertEqual(activePackage, activated)
    }

    func testRemovalFailureLeavesDurableIntentAndBootstrapRetryClearsIt() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let payload = Data("managed payload".utf8)
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let files = [
            try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
            try ManagedAssetPackLayout.filePath(
                for: package.id,
                packageRelativePath: "payload.bin"
            ): payload,
        ]
        let failingProvider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: files,
            removeOutcomes: [.failBeforeRemoval]
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier(),
            generationID: { "managed-generation-one" }
        )
        let firstMaterializer = ManagedPackageMaterializer(
            provider: failingProvider,
            activator: activator
        )

        let activated = try await firstMaterializer.downloadAndActivate(
            expectedPackage: package,
            trustedPublicKeys: Self.trustedPublicKeys,
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        XCTAssertEqual(failingProvider.removeRequests, [package.id])
        XCTAssertEqual(
            try pendingCleanupDigests(in: firstMaterializer.cleanupAuthorityDirectoryURL),
            [rawSHA256(manifest)]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: activated.packageURL.path))

        let retryProvider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: files
        )
        let reopened = ManagedPackageMaterializer(
            provider: retryProvider,
            activator: activator
        )
        try await reopened.retryPendingCleanup()

        XCTAssertEqual(retryProvider.removeRequests, [package.id])
        XCTAssertTrue(
            try pendingCleanupDigests(in: reopened.cleanupAuthorityDirectoryURL).isEmpty
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: activated.packageURL.path))
    }

    func testRemovalCompletedBeforeFailureIsRetiredAsAbsentOnRetry() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let payload = Data("managed payload".utf8)
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
                try ManagedAssetPackLayout.filePath(
                    for: package.id,
                    packageRelativePath: "payload.bin"
                ): payload,
            ],
            removeOutcomes: [.failAfterRemoval]
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier(),
            generationID: { "managed-generation-one" }
        )
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        let activated = try await materializer.downloadAndActivate(
            expectedPackage: package,
            trustedPublicKeys: Self.trustedPublicKeys,
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )
        XCTAssertEqual(provider.removeRequests, [package.id])
        XCTAssertEqual(
            try pendingCleanupDigests(in: materializer.cleanupAuthorityDirectoryURL),
            [rawSHA256(manifest)]
        )

        try await materializer.retryPendingCleanup()

        XCTAssertEqual(provider.removeRequests, [package.id])
        XCTAssertTrue(
            try pendingCleanupDigests(in: materializer.cleanupAuthorityDirectoryURL).isEmpty
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: activated.packageURL.path))
    }

    func testPendingCleanupRetriesBeforeANewDownloadAttempt() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let payload = Data("managed payload".utf8)
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let files = [
            try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
            try ManagedAssetPackLayout.filePath(
                for: package.id,
                packageRelativePath: "payload.bin"
            ): payload,
        ]
        let firstProvider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: files,
            removeOutcomes: [.failBeforeRemoval]
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier(),
            generationID: { "managed-generation-one" }
        )
        let firstMaterializer = ManagedPackageMaterializer(
            provider: firstProvider,
            activator: activator
        )
        let activated = try await firstMaterializer.downloadAndActivate(
            expectedPackage: package,
            trustedPublicKeys: Self.trustedPublicKeys,
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let unavailableProvider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: files,
            ensureError: .downloadUnavailable
        )
        let reopened = ManagedPackageMaterializer(
            provider: unavailableProvider,
            activator: activator
        )
        do {
            _ = try await reopened.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("the injected new download must fail")
        } catch {
            XCTAssertEqual(error as? FakeManagedAssetPackError, .downloadUnavailable)
        }

        XCTAssertEqual(unavailableProvider.removeRequests, [package.id])
        XCTAssertEqual(unavailableProvider.ensuredPackageIDs, [package.id])
        XCTAssertTrue(
            try pendingCleanupDigests(in: reopened.cleanupAuthorityDirectoryURL).isEmpty
        )
        let stillActive = try await activator.activePackage(for: package.id)
        XCTAssertEqual(stillActive, activated)
    }

    func testStaleIntentCannotRemoveAChangedLocalManifest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let oldPayload = Data("old payload".utf8)
        let oldManifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: oldPayload)]
        )
        let oldProvider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): oldManifest,
                try ManagedAssetPackLayout.filePath(
                    for: package.id,
                    packageRelativePath: "payload.bin"
                ): oldPayload,
            ],
            removeOutcomes: [.failBeforeRemoval]
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier(),
            generationID: { "managed-generation-one" }
        )
        let firstMaterializer = ManagedPackageMaterializer(
            provider: oldProvider,
            activator: activator
        )
        let activated = try await firstMaterializer.downloadAndActivate(
            expectedPackage: package,
            trustedPublicKeys: Self.trustedPublicKeys,
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        let newPayload = Data("newer payload".utf8)
        let newManifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: newPayload)]
        )
        XCTAssertNotEqual(rawSHA256(oldManifest), rawSHA256(newManifest))
        let newerProvider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): newManifest,
            ]
        )
        let reopened = ManagedPackageMaterializer(
            provider: newerProvider,
            activator: activator
        )
        try await reopened.retryPendingCleanup()

        XCTAssertTrue(newerProvider.removeRequests.isEmpty)
        XCTAssertTrue(
            try pendingCleanupDigests(in: reopened.cleanupAuthorityDirectoryURL).isEmpty
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: activated.packageURL.path))
    }

    func testCorruptCleanupAuthorityIsPreservedWithoutBlockingCommittedActivation()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let payload = Data("managed payload".utf8)
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
                try ManagedAssetPackLayout.filePath(
                    for: package.id,
                    packageRelativePath: "payload.bin"
                ): payload,
            ]
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier(),
            generationID: { "managed-generation-one" }
        )
        let cleanupDirectory = root.appending(path: "managed-asset-cleanup")
        try FileManager.default.createDirectory(
            at: cleanupDirectory,
            withIntermediateDirectories: false
        )
        let slotA = cleanupDirectory.appending(path: "asset-pack-cleanup-a.json")
        let corruptBytes = Data("truncated".utf8)
        try corruptBytes.write(to: slotA, options: [.atomic])
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        let activated = try await materializer.downloadAndActivate(
            expectedPackage: package,
            trustedPublicKeys: Self.trustedPublicKeys,
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: activated.packageURL.path))
        XCTAssertTrue(provider.removeRequests.isEmpty)
        XCTAssertEqual(try Data(contentsOf: slotA), corruptBytes)
        do {
            try await materializer.retryPendingCleanup()
            XCTFail("corrupt cleanup authority must remain fail-closed")
        } catch {
            XCTAssertEqual(
                error as? ManagedAssetPackCleanupError,
                .corruptAuthority
            )
        }
        XCTAssertEqual(try Data(contentsOf: slotA), corruptBytes)
    }

    func testFutureCleanupAuthorityIsPreservedWithoutRemovalOrOverwrite() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let payload = Data("managed payload".utf8)
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
                try ManagedAssetPackLayout.filePath(
                    for: package.id,
                    packageRelativePath: "payload.bin"
                ): payload,
            ]
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier(),
            generationID: { "managed-generation-one" }
        )
        let cleanupDirectory = root.appending(path: "managed-asset-cleanup")
        try FileManager.default.createDirectory(
            at: cleanupDirectory,
            withIntermediateDirectories: false
        )
        let slotA = cleanupDirectory.appending(path: "asset-pack-cleanup-a.json")
        let futureBytes = try futureCleanupEnvelope(formatVersion: 2)
        try futureBytes.write(to: slotA, options: [.atomic])
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        let activated = try await materializer.downloadAndActivate(
            expectedPackage: package,
            trustedPublicKeys: Self.trustedPublicKeys,
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: activated.packageURL.path))
        XCTAssertTrue(provider.removeRequests.isEmpty)
        XCTAssertEqual(try Data(contentsOf: slotA), futureBytes)
        do {
            try await materializer.retryPendingCleanup()
            XCTFail("future cleanup authority must block this runtime")
        } catch {
            XCTAssertEqual(
                error as? ManagedAssetPackCleanupError,
                .requiresNewerApp(2)
            )
        }
        XCTAssertEqual(try Data(contentsOf: slotA), futureBytes)
    }

    func testCleanupAuthorityNeverFollowsSymlinksOrTouchesForeignFiles() async throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideSentinel = outside.appending(path: "outside-sentinel")
        try Data("outside".utf8).write(to: outsideSentinel)

        let package = Self.package()
        let payload = Data("managed payload".utf8)
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
                try ManagedAssetPackLayout.filePath(
                    for: package.id,
                    packageRelativePath: "payload.bin"
                ): payload,
            ]
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier(),
            generationID: { "managed-generation-one" }
        )
        let cleanupDirectory = root.appending(path: "managed-asset-cleanup")
        try FileManager.default.createDirectory(
            at: cleanupDirectory,
            withIntermediateDirectories: false
        )
        let foreign = cleanupDirectory.appending(path: "foreign-state")
        try Data("foreign".utf8).write(to: foreign)
        let slotA = cleanupDirectory.appending(path: "asset-pack-cleanup-a.json")
        try FileManager.default.createSymbolicLink(at: slotA, withDestinationURL: outsideSentinel)
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        let activated = try await materializer.downloadAndActivate(
            expectedPackage: package,
            trustedPublicKeys: Self.trustedPublicKeys,
            supportedSchema: .init(major: 1),
            runtimeVersion: .init(major: 1)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: activated.packageURL.path))
        XCTAssertTrue(provider.removeRequests.isEmpty)
        XCTAssertEqual(try Data(contentsOf: outsideSentinel), Data("outside".utf8))
        XCTAssertEqual(try Data(contentsOf: foreign), Data("foreign".utf8))
        do {
            try await materializer.retryPendingCleanup()
            XCTFail("a symlink cannot become cleanup authority")
        } catch {
            XCTAssertEqual(
                error as? ManagedAssetPackCleanupError,
                .unsafeAuthorityStorage(slotA.path)
            )
        }
        XCTAssertEqual(try Data(contentsOf: outsideSentinel), Data("outside".utf8))
        XCTAssertEqual(try Data(contentsOf: foreign), Data("foreign".utf8))
    }

    func testAppleCacheCleanupNeverTouchesActiveOrRollbackPrivateGenerations() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let payload = Data("managed payload".utf8)
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
                try ManagedAssetPackLayout.filePath(
                    for: package.id,
                    packageRelativePath: "payload.bin"
                ): payload,
            ]
        )
        let generationIDs = CleanupGenerationIDs(["generation-one", "generation-two"])
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier(),
            generationID: { generationIDs.next() }
        )
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)
        var activations: [ActivatedPackage] = []
        for _ in 0 ..< 2 {
            activations.append(try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            ))
        }

        XCTAssertEqual(provider.removeRequests, [package.id, package.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: activations[0].packageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: activations[1].packageURL.path))
        let rolledBack = try await activator.rollback(packageID: package.id)
        XCTAssertEqual(rolledBack, activations[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: rolledBack.packageURL.path))
    }

    func testUnsafeManifestPathIsRejectedBeforeAnyPayloadCopy() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let unsafeManifest = try Self.manifestDataWithoutValidation(
            package: package,
            records: [PackageFileRecord(
                path: "../escape.bin",
                bytes: 1,
                sha256: String(repeating: "a", count: 64)
            )]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): unsafeManifest,
            ]
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier()
        )
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("unsafe inventory must fail before copying payload files")
        } catch {
            XCTAssertEqual(error as? PackageVerificationError, .unsafePath("../escape.bin"))
        }

        XCTAssertEqual(provider.openedRequests.count, 1)
        let activePackage = try await activator.activePackage(for: package.id)
        XCTAssertNil(activePackage)
        let stagingContents = try FileManager.default.contentsOfDirectory(
            at: activator.stagingRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(stagingContents.isEmpty)
    }

    func testDownloadFailureDoesNotCreateStagingOrChangeInstalledIndex() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [:],
            ensureError: .downloadUnavailable
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier()
        )
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("download failure must stop before staging")
        } catch {
            XCTAssertEqual(error as? FakeManagedAssetPackError, .downloadUnavailable)
        }

        let activePackage = try await activator.activePackage(for: package.id)
        let installedIndex = try await activator.installedIndex()
        XCTAssertNil(activePackage)
        XCTAssertEqual(installedIndex, .empty)
        let stagingContents = try FileManager.default.contentsOfDirectory(
            at: activator.stagingRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(stagingContents.isEmpty)
    }

    func testInsufficientPostDownloadCapacityStopsBeforeReadingOrStaging() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let required = package.maximumInstalledBytes
            + ManagedPackageMaterializer.stagingSafetyReserveBytes
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [:]
        )
        let activator = try PackageActivator(
            rootURL: root,
            verifier: MaterializationVerifier()
        )
        let materializer = ManagedPackageMaterializer(
            provider: provider,
            activator: activator,
            storageCapacityProvider: FixedManagedPackageStorageCapacityProvider(
                availableBytes: required - 1
            )
        )

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("insufficient private-copy capacity must stop before staging")
        } catch {
            XCTAssertEqual(
                error as? ManagedPackageMaterializationError,
                .insufficientStorage(available: required - 1, required: required)
            )
            let bridged = error as NSError
            XCTAssertEqual(
                bridged.domain,
                ManagedPackageMaterializationError.errorDomain
            )
            XCTAssertEqual(
                bridged.code,
                ManagedPackageMaterializationError.insufficientStorageErrorCode
            )
            XCTAssertTrue(
                PackageBatchFailure(domain: bridged.domain, code: bridged.code)
                    .isInsufficientStorage
            )
        }

        XCTAssertEqual(provider.ensuredPackageIDs, [package.id])
        XCTAssertTrue(provider.openedRequests.isEmpty)
        XCTAssertTrue(try stagingContents(for: activator).isEmpty)
        let installedIndex = try await activator.installedIndex()
        XCTAssertEqual(installedIndex, .empty)
    }

    func testFilesystemOutOfSpaceFailureUsesTheSameStoragePresentation() {
        let failure = PackageBatchFailure(
            domain: NSPOSIXErrorDomain,
            code: Int(POSIXErrorCode.ENOSPC.rawValue)
        )

        XCTAssertTrue(failure.isInsufficientStorage)
        XCTAssertFalse(
            PackageBatchFailure(domain: NSPOSIXErrorDomain, code: 5)
                .isInsufficientStorage
        )
    }

    func testManifestIdentityDriftIsRejectedBeforePayloadCopy() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = Self.package()
        let foreign = ContentPackageSpec(
            id: "paid-pack-02",
            version: expected.version,
            chapterIDs: expected.chapterIDs,
            maximumInstalledBytes: expected.maximumInstalledBytes,
            minimumRuntime: expected.minimumRuntime,
            isEssentialInstall: false
        )
        let payload = Data("foreign".utf8)
        let manifest = try Self.manifestData(
            package: foreign,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: expected.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: expected.id): manifest,
            ]
        )
        let activator = try PackageActivator(rootURL: root, verifier: MaterializationVerifier())
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: expected,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("a pack cannot substitute another package identity")
        } catch {
            XCTAssertEqual(
                error as? PackageVerificationError,
                .packageSpecMismatch("package ID changed")
            )
        }
        XCTAssertEqual(provider.openedRequests.count, 1)
    }

    func testManifestReadStopsAtFourMiBBoundary() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let manifestPath = try ManagedAssetPackLayout.manifestPath(for: package.id)
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                manifestPath: Data(
                    repeating: 0x7B,
                    count: ManagedPackageMaterializer.maximumManifestBytes + 8_192
                ),
            ]
        )
        let activator = try PackageActivator(rootURL: root, verifier: MaterializationVerifier())
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("an oversized managed manifest must fail before decoding or staging")
        } catch {
            XCTAssertEqual(
                error as? ManagedPackageMaterializationError,
                .manifestTooLarge(
                    actual: ManagedPackageMaterializer.maximumManifestBytes + 1,
                    maximum: ManagedPackageMaterializer.maximumManifestBytes
                )
            )
        }

        XCTAssertEqual(provider.openedRequests, [.init(packageID: package.id, path: manifestPath)])
        XCTAssertTrue(try stagingContents(for: activator).isEmpty)
    }

    func testDeclaredByteBudgetIsRejectedBeforeStagingOrPayloadRead() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let provisionalPackage = Self.package()
        let payload = Data("declared payload".utf8)
        let manifest = try Self.manifestData(
            package: provisionalPackage,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let maximumBytes = Int64(manifest.count + payload.count - 1)
        let package = Self.package(maximumInstalledBytes: maximumBytes)
        let manifestPath = try ManagedAssetPackLayout.manifestPath(for: package.id)
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [manifestPath: manifest]
        )
        let activator = try PackageActivator(rootURL: root, verifier: MaterializationVerifier())
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("declared package bytes over budget must fail before staging")
        } catch {
            XCTAssertEqual(
                error as? PackageVerificationError,
                .installedByteBudgetExceeded(
                    actual: Int64(manifest.count + payload.count),
                    maximum: maximumBytes
                )
            )
        }

        XCTAssertEqual(provider.openedRequests, [.init(packageID: package.id, path: manifestPath)])
        XCTAssertTrue(try stagingContents(for: activator).isEmpty)
    }

    func testStreamedPayloadMustMatchDeclaredSize() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let declaredPayload = Data([0x01, 0x02])
        let deliveredPayload = Data([0x01, 0x02, 0x03])
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: declaredPayload)]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
                try ManagedAssetPackLayout.filePath(
                    for: package.id,
                    packageRelativePath: "payload.bin"
                ): deliveredPayload,
            ]
        )
        let activator = try PackageActivator(rootURL: root, verifier: MaterializationVerifier())
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("a streamed payload cannot exceed its signed size")
        } catch {
            XCTAssertEqual(error as? PackageVerificationError, .fileSizeMismatch("payload.bin"))
        }

        XCTAssertTrue(try stagingContents(for: activator).isEmpty)
    }

    func testStreamedPayloadMustMatchSignedDigest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let declaredPayload = Data([0x01, 0x02, 0x03])
        let deliveredPayload = Data([0x03, 0x02, 0x01])
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: declaredPayload)]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
                try ManagedAssetPackLayout.filePath(
                    for: package.id,
                    packageRelativePath: "payload.bin"
                ): deliveredPayload,
            ]
        )
        let activator = try PackageActivator(rootURL: root, verifier: MaterializationVerifier())
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("a streamed payload cannot differ from its signed digest")
        } catch {
            XCTAssertEqual(error as? PackageVerificationError, .fileDigestMismatch("payload.bin"))
        }

        XCTAssertTrue(try stagingContents(for: activator).isEmpty)
    }

    func testStreamedBytesCannotCrossAggregatePackageCeiling() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let provisionalPackage = Self.package()
        let declaredPayload = Data([0x01, 0x02])
        let deliveredPayload = Data([0x01, 0x02, 0x03])
        let manifest = try Self.manifestData(
            package: provisionalPackage,
            records: [Self.record(path: "payload.bin", data: declaredPayload)]
        )
        let maximumBytes = Int64(manifest.count + declaredPayload.count)
        let package = Self.package(maximumInstalledBytes: maximumBytes)
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): manifest,
                try ManagedAssetPackLayout.filePath(
                    for: package.id,
                    packageRelativePath: "payload.bin"
                ): deliveredPayload,
            ]
        )
        let activator = try PackageActivator(rootURL: root, verifier: MaterializationVerifier())
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("delivered bytes cannot cross the package ceiling")
        } catch {
            XCTAssertEqual(
                error as? PackageVerificationError,
                .installedByteBudgetExceeded(
                    actual: Int64(manifest.count + deliveredPayload.count),
                    maximum: maximumBytes
                )
            )
        }

        XCTAssertTrue(try stagingContents(for: activator).isEmpty)
    }

    func testUntrustedManifestNeverOpensPayloadOrCreatesStaging() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let payload = Data("signed by an untrusted key".utf8)
        let manifestPath = try ManagedAssetPackLayout.manifestPath(for: package.id)
        let payloadPath = try ManagedAssetPackLayout.filePath(
            for: package.id,
            packageRelativePath: "payload.bin"
        )
        let manifest = try Self.manifestData(
            package: package,
            records: [Self.record(path: "payload.bin", data: payload)]
        )
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [manifestPath: manifest, payloadPath: payload]
        )
        let activator = try PackageActivator(rootURL: root, verifier: MaterializationVerifier())
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: [:],
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1)
            )
            XCTFail("an untrusted manifest must fail before payload materialization")
        } catch {
            XCTAssertEqual(
                error as? PackageVerificationError,
                .untrustedSigningKey("test-key")
            )
        }

        XCTAssertEqual(provider.openedRequests, [.init(packageID: package.id, path: manifestPath)])
        XCTAssertTrue(try stagingContents(for: activator).isEmpty)
        let activePackage = try await activator.activePackage(for: package.id)
        XCTAssertNil(activePackage)
    }

    func testRequireLatestVersionPolicyIsForwardedExactly() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = Self.package()
        let provider = FakeManagedAssetPackProvider(
            packageID: package.id,
            files: [
                try ManagedAssetPackLayout.manifestPath(for: package.id): Data("not-json".utf8),
            ]
        )
        let activator = try PackageActivator(rootURL: root, verifier: MaterializationVerifier())
        let materializer = ManagedPackageMaterializer(provider: provider, activator: activator)

        do {
            _ = try await materializer.downloadAndActivate(
                expectedPackage: package,
                trustedPublicKeys: Self.trustedPublicKeys,
                supportedSchema: .init(major: 1),
                runtimeVersion: .init(major: 1),
                requireLatestVersion: false
            )
            XCTFail("the malformed manifest must stop materialization")
        } catch {
            XCTAssertEqual(
                error as? PackageVerificationError,
                .malformedManifest("invalid JSON")
            )
        }

        XCTAssertEqual(provider.requiredLatestVersions, [false])
    }

    private static func package(
        maximumInstalledBytes: Int64 = 750_000_000
    ) -> ContentPackageSpec {
        ContentPackageSpec(
            id: "paid-pack-01",
            version: .init(major: 1),
            chapterIDs: ["steppe-comes-west"],
            maximumInstalledBytes: maximumInstalledBytes,
            minimumRuntime: .init(major: 1),
            isEssentialInstall: false
        )
    }

    private static func record(path: String, data: Data) -> PackageFileRecord {
        PackageFileRecord(
            path: path,
            bytes: Int64(data.count),
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private static func manifestData(
        package: ContentPackageSpec,
        records: [PackageFileRecord]
    ) throws -> Data {
        let draft = manifest(
            package: package,
            records: records,
            digest: String(repeating: "0", count: 64),
            signatureValue: "AA=="
        )
        let digest = try ContentPackageVerifier.manifestDigest(for: draft)
        let signature = try signingKey.signature(for: Data(digest.utf8))
        return try encoder.encode(manifest(
            package: package,
            records: records,
            digest: digest,
            signatureValue: signature.derRepresentation.base64EncodedString()
        ))
    }

    private static func manifestDataWithoutValidation(
        package: ContentPackageSpec,
        records: [PackageFileRecord]
    ) throws -> Data {
        try encoder.encode(manifest(
            package: package,
            records: records,
            digest: String(repeating: "a", count: 64),
            signatureValue: "AA=="
        ))
    }

    private static func manifest(
        package: ContentPackageSpec,
        records: [PackageFileRecord],
        digest: String,
        signatureValue: String
    ) -> SignedPackageManifest {
        SignedPackageManifest(
            packageID: package.id,
            packageVersion: package.version,
            schemaVersion: .init(major: 1),
            minimumRuntime: package.minimumRuntime,
            files: records,
            manifestDigest: digest,
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "test-key",
                value: signatureValue
            )
        )
    }

    private static let signingKey = P256.Signing.PrivateKey()
    private static let trustedPublicKeys = [
        "test-key": signingKey.publicKey.x963Representation,
    ]

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "managed-materializer-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func stagingContents(for activator: PackageActivator) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: activator.stagingRootURL,
            includingPropertiesForKeys: nil
        )
    }

    private func pendingCleanupDigests(in directoryURL: URL) throws -> [String] {
        var newest: (generation: UInt64, digests: [String])?
        for name in ["asset-pack-cleanup-a.json", "asset-pack-cleanup-b.json"] {
            let url = directoryURL.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path),
                  let root = try JSONSerialization.jsonObject(
                      with: Data(contentsOf: url)
                  ) as? [String: Any],
                  let generationNumber = root["generation"] as? NSNumber,
                  let authority = root["authority"] as? [String: Any],
                  let intents = authority["intents"] as? [[String: Any]] else {
                continue
            }
            let candidate = (
                generation: generationNumber.uint64Value,
                digests: intents.compactMap { $0["rawManifestSHA256"] as? String }
            )
            if newest == nil || candidate.generation > newest!.generation {
                newest = candidate
            }
        }
        return newest?.digests ?? []
    }

    private func futureCleanupEnvelope(
        generation: UInt64 = 1,
        formatVersion: Int
    ) throws -> Data {
        let authority: [String: Any] = [
            "formatVersion": formatVersion,
            "intents": [],
        ]
        let material: [String: Any] = [
            "envelopeFormatVersion": 1,
            "generation": generation,
            "authority": authority,
        ]
        let canonical = try JSONSerialization.data(
            withJSONObject: material,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let digest = SHA256.hash(data: canonical)
            .map { String(format: "%02x", $0) }
            .joined()
        var envelope = material
        envelope["digest"] = digest
        return try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func rawSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum FakeManagedAssetPackError: Error, Equatable {
    case downloadUnavailable
    case missingFile(packageID: String, path: String)
    case removalUnavailable
    case removalResultIndeterminate
}

private struct FixedManagedPackageStorageCapacityProvider:
    ManagedPackageStorageCapacityProviding
{
    let availableBytes: Int64?

    func availableCapacityForImportantUsage(at _: URL) throws -> Int64? {
        availableBytes
    }
}

private final class CleanupGenerationIDs: @unchecked Sendable {
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

private final class FakeManagedAssetPackProvider: @unchecked Sendable, ManagedAssetPackProviding {
    struct Request: Equatable, Sendable {
        let packageID: PackageID
        let path: String
    }

    private struct FileKey: Hashable {
        let packageID: PackageID
        let path: String
    }

    private let files: [FileKey: Data]
    private let ensureError: FakeManagedAssetPackError?
    private var removeOutcomes: [RemoveOutcome]
    private let temporaryRoot: URL
    private let lock = NSLock()
    private var _ensuredPackageIDs: [PackageID] = []
    private var _requiredLatestVersions: [Bool] = []
    private var _openedRequests: [Request] = []
    private var _localStatus: ManagedAssetPackLocalStatus
    private var _localStatusRequests: [PackageID] = []
    private var _removeRequests: [PackageID] = []

    enum RemoveOutcome: Sendable {
        case success
        case failBeforeRemoval
        case failAfterRemoval
    }

    var ensuredPackageIDs: [PackageID] {
        locked { _ensuredPackageIDs }
    }

    var requiredLatestVersions: [Bool] {
        locked { _requiredLatestVersions }
    }

    var openedRequests: [Request] {
        locked { _openedRequests }
    }

    var localStatusRequests: [PackageID] {
        locked { _localStatusRequests }
    }

    var removeRequests: [PackageID] {
        locked { _removeRequests }
    }

    init(
        packageID: PackageID,
        files: [String: Data],
        ensureError: FakeManagedAssetPackError? = nil,
        localStatus: ManagedAssetPackLocalStatus = .downloaded,
        removeOutcomes: [RemoveOutcome] = []
    ) {
        self.files = Dictionary(uniqueKeysWithValues: files.map {
            (FileKey(packageID: packageID, path: $0.key), $0.value)
        })
        self.ensureError = ensureError
        _localStatus = localStatus
        self.removeOutcomes = removeOutcomes
        temporaryRoot = FileManager.default.temporaryDirectory.appending(
            path: "fake-managed-pack-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try! FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func ensureLocalAvailability(
        of packageID: PackageID,
        requireLatestVersion: Bool
    ) async throws {
        locked {
            _ensuredPackageIDs.append(packageID)
            _requiredLatestVersions.append(requireLatestVersion)
            if ensureError == nil { _localStatus = .downloaded }
        }
        if let ensureError { throw ensureError }
    }

    func descriptor(
        at assetPackRelativePath: String,
        in packageID: PackageID
    ) throws -> FileDescriptor {
        let request = Request(packageID: packageID, path: assetPackRelativePath)
        let data = locked { () -> Data? in
            _openedRequests.append(request)
            return files[FileKey(packageID: packageID, path: assetPackRelativePath)]
        }
        guard let data else {
            throw FakeManagedAssetPackError.missingFile(
                packageID: packageID.rawValue,
                path: assetPackRelativePath
            )
        }
        let fileURL = temporaryRoot.appending(
            path: UUID().uuidString,
            directoryHint: .notDirectory
        )
        try data.write(to: fileURL, options: [.atomic])
        return try FileDescriptor.open(FilePath(fileURL.path), .readOnly)
    }

    func localStatus(of packageID: PackageID) async throws -> ManagedAssetPackLocalStatus {
        locked {
            _localStatusRequests.append(packageID)
            return _localStatus
        }
    }

    func removeLocalAssetPack(_ packageID: PackageID) async throws {
        let outcome = locked { () -> RemoveOutcome in
            _removeRequests.append(packageID)
            return removeOutcomes.isEmpty ? .success : removeOutcomes.removeFirst()
        }
        switch outcome {
        case .success:
            locked { _localStatus = .absent }
        case .failBeforeRemoval:
            throw FakeManagedAssetPackError.removalUnavailable
        case .failAfterRemoval:
            locked { _localStatus = .absent }
            throw FakeManagedAssetPackError.removalResultIndeterminate
        }
    }

    func simulateLocalAbsence() {
        locked { _localStatus = .absent }
    }

    func statusUpdates(for _: PackageID) -> AsyncStream<AssetPackTransferStatus> {
        AsyncStream { continuation in continuation.finish() }
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private struct MaterializationVerifier: PackageActivationVerifying {
    func verifyPackage(
        at packageRoot: URL,
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys _: [String: Data],
        supportedSchema _: SchemaVersion,
        runtimeVersion _: SchemaVersion
    ) throws -> VerifiedActivationReceipt {
        let payload = try Data(contentsOf: packageRoot.appending(path: "payload.bin"))
        return VerifiedActivationReceipt(
            packageID: expectedPackage.id,
            packageVersion: expectedPackage.version,
            manifestDigest: SHA256.hash(data: payload)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }
}
