import ContentDelivery
@testable import ContentKit
import Foundation
@testable import JourneyContent
import XCTest

final class VerifiedFutureReleaseRepositoryAuthorityTests: XCTestCase {
    func testBootstrapReconstructsPlayableContentFromOnlyRetainedLocalAuthority() async throws {
        let fixture = makeFixture()
        let provider = CountingFutureReleaseAuthorityProvider(
            releases: [fixture.release],
            authority: fixture.authority
        )
        let subject = makeSubject(fixture: fixture, provider: provider)

        let snapshot = try await subject.bootstrap()

        XCTAssertEqual(snapshot.revision, 1)
        XCTAssertEqual(snapshot.unavailableInstalledPackageIDs, [])
        let content = try XCTUnwrap(snapshot.content(for: fixture.release.id))
        XCTAssertEqual(content.release, fixture.release)
        XCTAssertEqual(content.installedGeneration, fixture.generation)
        XCTAssertEqual(
            content.repository.availableChapterIDs,
            fixture.release.chapterIDs
        )
        let counts = await provider.counts()
        XCTAssertEqual(counts.releaseReads, 1)
        XCTAssertEqual(counts.authorityReads, 1)
    }

    func testConcurrentRefreshesShareOneAuthorityReadAndOnePublishedRevision() async throws {
        let fixture = makeFixture()
        let gate = FutureReleaseRefreshGate()
        let provider = CountingFutureReleaseAuthorityProvider(
            releases: [fixture.release],
            authority: fixture.authority,
            gate: gate
        )
        let subject = makeSubject(fixture: fixture, provider: provider)

        async let first = subject.refresh()
        await gate.waitUntilEntered()
        async let second = subject.refresh()
        await gate.open()

        let snapshots = try await [first, second]
        XCTAssertEqual(snapshots.map(\.revision), [1, 1])
        let published = await subject.snapshot()
        XCTAssertEqual(published.revision, 1)
        let counts = await provider.counts()
        XCTAssertEqual(counts.releaseReads, 1)
        XCTAssertEqual(counts.authorityReads, 1)
    }

    func testMismatchedGenerationRemainsUnavailableAndNeverBecomesAddressable() async throws {
        let fixture = makeFixture(generationVersion: SchemaVersion(major: 2))
        let provider = CountingFutureReleaseAuthorityProvider(
            releases: [fixture.release],
            authority: fixture.authority
        )
        let subject = makeSubject(fixture: fixture, provider: provider)

        let snapshot = try await subject.bootstrap()

        XCTAssertNil(snapshot.content(for: fixture.release.id))
        XCTAssertEqual(
            snapshot.unavailableInstalledPackageIDs,
            [fixture.release.packageID]
        )
    }

    func testActivePackageWithoutRetainedContractFailsClosed() async throws {
        let fixture = makeFixture()
        let provider = CountingFutureReleaseAuthorityProvider(
            releases: [],
            authority: fixture.authority
        )
        let subject = makeSubject(fixture: fixture, provider: provider)

        do {
            _ = try await subject.bootstrap()
            XCTFail("Expected the unbound active package to fail closed")
        } catch {
            XCTAssertEqual(
                error as? VerifiedFutureReleaseRepositoryAuthorityError,
                .activePackageWithoutRetainedContract(fixture.release.packageID)
            )
        }
        let retained = await subject.snapshot()
        XCTAssertEqual(retained.revision, 0)
    }

    func testExactLazyAssetFailureQuarantinesGenerationAndWithdrawsRoute()
        async throws
    {
        let fixture = makeFixture()
        let provider = CountingFutureReleaseAuthorityProvider(
            releases: [fixture.release],
            authority: fixture.authority
        )
        let subject = VerifiedFutureReleaseRepositoryAuthority(
            expectedWorldSeed: fixture.payload.worldSeed,
            trustedPublicKeys: ["test-only": Data(repeating: 7, count: 65)],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1),
            releaseContractProvider: { try await provider.readReleases() },
            packageAuthorityProvider: { try await provider.readAuthority() },
            deactivate: { packageID, generation in
                await provider.deactivate(
                    packageID: packageID,
                    expectedGeneration: generation
                )
            },
            packageAdmission: { _, package, _, _, _ in
                guard package.id == fixture.release.packageID,
                      package.version == fixture.release.version else {
                    throw PackageVerificationError.packageIdentityMismatch
                }
                return fixture.verifiedPackage
            }
        )
        let before = try await subject.bootstrap()
        let report = try XCTUnwrap(
            before.chapterRuntimeAuthority(for: fixture.release.id)?
                .assetFailureAuthority(for: fixture.release.packageID)
        )

        let outcome = await subject.reportAssetFailure(
            releaseID: fixture.release.id,
            expectedAuthority: report
        )

        XCTAssertEqual(outcome, .quarantined(fixture.generation))
        let after = await subject.snapshot()
        XCTAssertEqual(after.revision, before.revision + 2)
        XCTAssertNil(after.content(for: fixture.release.id))
        XCTAssertEqual(
            after.unavailableInstalledPackageIDs,
            [fixture.release.packageID]
        )
        let durable = try await provider.readAuthority()
        XCTAssertNil(durable.index.activeGeneration(
            for: fixture.release.packageID
        ))
        XCTAssertTrue(durable.index.generations.contains(fixture.generation))
    }

    func testQuarantineInvalidatesPreDeactivationRefreshAndNeverReturnsItsStaleRoute()
        async throws
    {
        let fixture = makeFixture()
        let staleAuthorityGate = FutureReleaseRefreshGate(
            initiallyArmed: false
        )
        let provider = CountingFutureReleaseAuthorityProvider(
            releases: [fixture.release],
            authority: fixture.authority,
            authorityGate: staleAuthorityGate
        )
        let subject = VerifiedFutureReleaseRepositoryAuthority(
            expectedWorldSeed: fixture.payload.worldSeed,
            trustedPublicKeys: ["test-only": Data(repeating: 7, count: 65)],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1),
            releaseContractProvider: { try await provider.readReleases() },
            packageAuthorityProvider: { try await provider.readAuthority() },
            deactivate: { packageID, generation in
                await provider.deactivate(
                    packageID: packageID,
                    expectedGeneration: generation
                )
            },
            packageAdmission: { _, package, _, _, _ in
                guard package.id == fixture.release.packageID,
                      package.version == fixture.release.version else {
                    throw PackageVerificationError.packageIdentityMismatch
                }
                return fixture.verifiedPackage
            }
        )
        let before = try await subject.bootstrap()
        let report = try XCTUnwrap(
            before.chapterRuntimeAuthority(for: fixture.release.id)?
                .assetFailureAuthority(for: fixture.release.packageID)
        )

        await staleAuthorityGate.arm()
        let staleRefresh = Task { try await subject.refresh() }
        await staleAuthorityGate.waitUntilEntered()

        let outcome = await subject.reportAssetFailure(
            releaseID: fixture.release.id,
            expectedAuthority: report
        )
        XCTAssertEqual(outcome, .quarantined(fixture.generation))
        let quarantined = await subject.snapshot()
        XCTAssertNil(quarantined.content(for: fixture.release.id))
        XCTAssertEqual(
            quarantined.unavailableInstalledPackageIDs,
            [fixture.release.packageID]
        )

        await staleAuthorityGate.open()
        let staleCallerResult = try await staleRefresh.value
        XCTAssertEqual(staleCallerResult.revision, quarantined.revision)
        XCTAssertNil(staleCallerResult.content(for: fixture.release.id))
        let final = await subject.snapshot()
        XCTAssertEqual(final.revision, quarantined.revision)
        XCTAssertNil(final.content(for: fixture.release.id))
    }

    func testSaveMigrationReversionSelectsOnlyTheExactVerifiedPriorGeneration()
        async throws
    {
        let fixture = makeFixture()
        let previousVersion = SchemaVersion(major: 1, minor: 1)
        let previousVerifiedPackage = VerifiedContentPackage(
            manifest: JourneyContentFixtures.signedManifest(
                for: fixture.payload,
                packageVersion: previousVersion,
                minimumRuntime: fixture.release.minimumRuntime
            ),
            payload: fixture.payload
        )
        let previous = InstalledPackageGeneration(
            generationID: "managed-deep-dive-alpha-v1-previous",
            packageID: fixture.release.packageID,
            packageVersion: previousVersion,
            manifestDigest:
                previousVerifiedPackage.manifest.manifestDigest,
            relativePath: "generations/managed-deep-dive-alpha-v1-previous",
            activationSequence: 1
        )
        let current = InstalledPackageGeneration(
            generationID: "managed-deep-dive-alpha-v1-current",
            packageID: fixture.release.packageID,
            packageVersion: fixture.release.version,
            manifestDigest: fixture.verifiedPackage.manifest.manifestDigest,
            relativePath: "generations/managed-deep-dive-alpha-v1-current",
            activationSequence: 2
        )
        let previousPackage = ActivatedPackage(
            generation: previous,
            packageURL: URL(fileURLWithPath: "/tmp/future-previous")
        )
        let currentPackage = ActivatedPackage(
            generation: current,
            packageURL: URL(fileURLWithPath: "/tmp/future-current")
        )
        let authority = RetainedPackageAuthority(
            index: InstalledPackageIndex(
                nextActivationSequence: 3,
                generations: [previous, current],
                activeGenerationByPackage: [
                    fixture.release.packageID: current.generationID,
                ]
            ),
            locationsByPackage: [
                fixture.release.packageID: RetainedPackageLocations(
                    activeGeneration: current,
                    activePackage: currentPackage,
                    previousGeneration: previous,
                    previousPackage: previousPackage
                ),
            ]
        )
        let provider = CountingFutureReleaseAuthorityProvider(
            releases: [fixture.release],
            authority: authority
        )
        let subject = VerifiedFutureReleaseRepositoryAuthority(
            expectedWorldSeed: fixture.payload.worldSeed,
            trustedPublicKeys: ["test-only": Data(repeating: 7, count: 65)],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1),
            releaseContractProvider: { try await provider.readReleases() },
            packageAuthorityProvider: { try await provider.readAuthority() },
            exactRollback: { packageID, active, prior in
                await provider.rollback(
                    packageID: packageID,
                    expectedCurrent: active,
                    expectedPrevious: prior
                )
            },
            packageAdmission: { _, expected, _, _, _ in
                switch expected.version {
                case fixture.release.version:
                    fixture.verifiedPackage
                case previousVersion:
                    previousVerifiedPackage
                default:
                    throw PackageVerificationError.packageIdentityMismatch
                }
            },
            completePackageVerification: { _, expected, _, _, _ in
                guard expected.version == previousVersion else {
                    throw PackageVerificationError.packageIdentityMismatch
                }
                return previousVerifiedPackage
            }
        )
        _ = try await subject.bootstrap()

        let reverted = try await subject.revertSaveMigrationAuthorityChange(
            packageID: fixture.release.packageID,
            expectedCurrent: current,
            expectedPrevious: previous
        )

        XCTAssertEqual(
            reverted?.content(for: fixture.release.id)?.installedGeneration,
            previous
        )
        XCTAssertEqual(
            reverted?.content(for: fixture.release.id)?.verifiedPackage
                .manifest.packageVersion,
            previousVersion
        )
        XCTAssertEqual(
            reverted?.content(for: fixture.release.id)?.repository
                .availableChapterIDs,
            fixture.release.chapterIDs
        )
        let durable = try await provider.readAuthority()
        XCTAssertEqual(
            durable.index.activeGeneration(
                for: fixture.release.packageID
            ),
            previous
        )
    }

    func testRollbackSuppressesRefreshWhichCapturedSupersededFutureGeneration()
        async throws
    {
        let fixture = makeContinuityRaceFixture()
        let provider = GatedFutureReleaseAuthorityProvider(
            releases: [fixture.release],
            authority: fixture.authority
        )
        let mutationGate = FutureReleaseRefreshGate()
        let staleReadGate = FutureReleaseRefreshGate()
        let freshReadGate = FutureReleaseRefreshGate()
        let subject = VerifiedFutureReleaseRepositoryAuthority(
            expectedWorldSeed: fixture.payload.worldSeed,
            trustedPublicKeys: ["test-only": Data(repeating: 7, count: 65)],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1),
            releaseContractProvider: { try await provider.readReleases() },
            packageAuthorityProvider: { try await provider.readAuthority() },
            exactRollback: { packageID, current, previous in
                await provider.rollback(
                    packageID: packageID,
                    expectedCurrent: current,
                    expectedPrevious: previous,
                    mutationGate: mutationGate,
                    freshReadGate: freshReadGate
                )
            },
            packageAdmission: { _, expected, _, _, _ in
                switch expected.version {
                case fixture.release.version:
                    fixture.currentVerifiedPackage
                case fixture.previousVersion:
                    fixture.previousVerifiedPackage
                default:
                    throw PackageVerificationError.packageIdentityMismatch
                }
            },
            completePackageVerification: { _, expected, _, _, _ in
                guard expected.version == fixture.previousVersion else {
                    throw PackageVerificationError.packageIdentityMismatch
                }
                return fixture.previousVerifiedPackage
            }
        )
        let before = try await subject.bootstrap()
        XCTAssertEqual(
            before.content(for: fixture.release.id)?.installedGeneration,
            fixture.currentGeneration
        )
        let updates = await subject.snapshotUpdates()
        var updateIterator = updates.makeAsyncIterator()
        let observedBefore = await updateIterator.next()
        XCTAssertEqual(
            observedBefore?.content(for: fixture.release.id)?
                .installedGeneration,
            fixture.currentGeneration
        )

        let reversion = Task {
            try await subject.revertSaveMigrationAuthorityChange(
                packageID: fixture.release.packageID,
                expectedCurrent: fixture.currentGeneration,
                expectedPrevious: fixture.previousGeneration
            )
        }
        await mutationGate.waitUntilEntered()
        await provider.armNextAuthorityRead(staleReadGate)
        let staleRefresh = Task { try await subject.refresh() }
        await staleReadGate.waitUntilEntered()

        await mutationGate.open()
        await freshReadGate.waitUntilEntered()
        let withdrawnUpdate = await updateIterator.next()
        let withdrawn = try XCTUnwrap(withdrawnUpdate)
        XCTAssertNil(withdrawn.content(for: fixture.release.id))
        XCTAssertEqual(
            withdrawn.unavailableInstalledPackageIDs,
            [fixture.release.packageID]
        )

        await staleReadGate.open()
        let staleCaller = try await staleRefresh.value
        XCTAssertNil(staleCaller.content(for: fixture.release.id))
        let duringFreshRebuild = await subject.snapshot()
        XCTAssertNil(duringFreshRebuild.content(for: fixture.release.id))

        await freshReadGate.open()
        let reverted = try await reversion.value
        XCTAssertEqual(
            reverted?.content(for: fixture.release.id)?.installedGeneration,
            fixture.previousGeneration
        )
        let restoredUpdate = await updateIterator.next()
        let restored = try XCTUnwrap(restoredUpdate)
        XCTAssertEqual(
            restored.content(for: fixture.release.id)?.installedGeneration,
            fixture.previousGeneration
        )
    }

    func testDeactivationSuppressesRefreshWhichCapturedFutureGeneration()
        async throws
    {
        let fixture = makeFixture()
        let provider = GatedFutureReleaseAuthorityProvider(
            releases: [fixture.release],
            authority: fixture.authority
        )
        let mutationGate = FutureReleaseRefreshGate()
        let staleReadGate = FutureReleaseRefreshGate()
        let freshReadGate = FutureReleaseRefreshGate()
        let subject = VerifiedFutureReleaseRepositoryAuthority(
            expectedWorldSeed: fixture.payload.worldSeed,
            trustedPublicKeys: ["test-only": Data(repeating: 7, count: 65)],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1),
            releaseContractProvider: { try await provider.readReleases() },
            packageAuthorityProvider: { try await provider.readAuthority() },
            deactivate: { packageID, current in
                await provider.deactivate(
                    packageID: packageID,
                    expectedGeneration: current,
                    mutationGate: mutationGate,
                    freshReadGate: freshReadGate
                )
            },
            packageAdmission: { _, expected, _, _, _ in
                guard expected.id == fixture.release.packageID,
                      expected.version == fixture.release.version else {
                    throw PackageVerificationError.packageIdentityMismatch
                }
                return fixture.verifiedPackage
            }
        )
        _ = try await subject.bootstrap()
        let updates = await subject.snapshotUpdates()
        var updateIterator = updates.makeAsyncIterator()
        let observedBefore = await updateIterator.next()
        XCTAssertEqual(
            observedBefore?.content(for: fixture.release.id)?
                .installedGeneration,
            fixture.generation
        )

        let reversion = Task {
            try await subject.revertSaveMigrationAuthorityChange(
                packageID: fixture.release.packageID,
                expectedCurrent: fixture.generation,
                expectedPrevious: nil
            )
        }
        await mutationGate.waitUntilEntered()
        await provider.armNextAuthorityRead(staleReadGate)
        let staleRefresh = Task { try await subject.refresh() }
        await staleReadGate.waitUntilEntered()

        await mutationGate.open()
        await freshReadGate.waitUntilEntered()
        let withdrawnUpdate = await updateIterator.next()
        let withdrawn = try XCTUnwrap(withdrawnUpdate)
        XCTAssertNil(withdrawn.content(for: fixture.release.id))

        await staleReadGate.open()
        let staleCaller = try await staleRefresh.value
        XCTAssertNil(staleCaller.content(for: fixture.release.id))
        let duringFreshRebuild = await subject.snapshot()
        XCTAssertNil(duringFreshRebuild.content(for: fixture.release.id))

        await freshReadGate.open()
        let reverted = try await reversion.value
        XCTAssertNil(reverted?.content(for: fixture.release.id))
        let rebuiltUpdate = await updateIterator.next()
        let rebuilt = try XCTUnwrap(rebuiltUpdate)
        XCTAssertNil(rebuilt.content(for: fixture.release.id))
        XCTAssertEqual(
            rebuilt.unavailableInstalledPackageIDs,
            [fixture.release.packageID]
        )
    }

    private func makeSubject(
        fixture: FutureReleaseAuthorityFixture,
        provider: CountingFutureReleaseAuthorityProvider
    ) -> VerifiedFutureReleaseRepositoryAuthority {
        VerifiedFutureReleaseRepositoryAuthority(
            expectedWorldSeed: fixture.payload.worldSeed,
            trustedPublicKeys: ["test-only": Data(repeating: 7, count: 65)],
            supportedSchema: SchemaVersion(major: 1),
            runtimeVersion: SchemaVersion(major: 1),
            releaseContractProvider: { try await provider.readReleases() },
            packageAuthorityProvider: { try await provider.readAuthority() },
            packageAdmission: { _, package, _, _, _ in
                guard package.id == fixture.release.packageID,
                      package.version == fixture.release.version else {
                    throw PackageVerificationError.packageIdentityMismatch
                }
                return fixture.verifiedPackage
            }
        )
    }

    private func makeFixture(
        generationVersion: SchemaVersion? = nil
    ) -> FutureReleaseAuthorityFixture {
        let payload = JourneyContentFixtures.futurePackage()
        let release = Release(
            id: "release-alpha-deep-dive-v1",
            contentID: payload.chapters[0].id.rawValue,
            packageID: payload.packageID,
            version: SchemaVersion(major: 1, minor: 2),
            chapterIDs: payload.chapters.map(\.id),
            maximumInstalledBytes: 420_000_000,
            publishedAtUnixMillis: 1_800_000_000_000,
            minimumRuntime: SchemaVersion(major: 1)
        )
        let manifest = JourneyContentFixtures.signedManifest(
            for: payload,
            packageVersion: release.version,
            minimumRuntime: release.minimumRuntime
        )
        let verifiedPackage = VerifiedContentPackage(
            manifest: manifest,
            payload: payload
        )
        let generation = InstalledPackageGeneration(
            generationID: "managed-deep-dive-alpha-v1-generation",
            packageID: release.packageID,
            packageVersion: generationVersion ?? release.version,
            manifestDigest: manifest.manifestDigest,
            relativePath: "generations/managed-deep-dive-alpha-v1-generation",
            activationSequence: 1
        )
        let root = FileManager.default.temporaryDirectory.appending(
            path: generation.generationID,
            directoryHint: .isDirectory
        )
        let active = ActivatedPackage(generation: generation, packageURL: root)
        let index = InstalledPackageIndex(
            nextActivationSequence: 2,
            generations: [generation],
            activeGenerationByPackage: [release.packageID: generation.generationID]
        )
        let authority = RetainedPackageAuthority(
            index: index,
            locationsByPackage: [
                release.packageID: RetainedPackageLocations(
                    activeGeneration: generation,
                    activePackage: active,
                    previousGeneration: nil,
                    previousPackage: nil
                ),
            ]
        )
        return FutureReleaseAuthorityFixture(
            payload: payload,
            release: release,
            verifiedPackage: verifiedPackage,
            generation: generation,
            authority: authority
        )
    }

    private func makeContinuityRaceFixture()
        -> FutureReleaseContinuityRaceFixture
    {
        let fixture = makeFixture()
        let previousVersion = SchemaVersion(major: 1, minor: 1)
        let previousVerifiedPackage = VerifiedContentPackage(
            manifest: JourneyContentFixtures.signedManifest(
                for: fixture.payload,
                packageVersion: previousVersion,
                minimumRuntime: fixture.release.minimumRuntime
            ),
            payload: fixture.payload
        )
        let previousGeneration = InstalledPackageGeneration(
            generationID: "managed-deep-dive-alpha-race-previous",
            packageID: fixture.release.packageID,
            packageVersion: previousVersion,
            manifestDigest:
                previousVerifiedPackage.manifest.manifestDigest,
            relativePath:
                "generations/managed-deep-dive-alpha-race-previous",
            activationSequence: 1
        )
        let currentGeneration = InstalledPackageGeneration(
            generationID: "managed-deep-dive-alpha-race-current",
            packageID: fixture.release.packageID,
            packageVersion: fixture.release.version,
            manifestDigest: fixture.verifiedPackage.manifest.manifestDigest,
            relativePath:
                "generations/managed-deep-dive-alpha-race-current",
            activationSequence: 2
        )
        let previousPackage = ActivatedPackage(
            generation: previousGeneration,
            packageURL: URL(fileURLWithPath: "/tmp/future-race-previous")
        )
        let currentPackage = ActivatedPackage(
            generation: currentGeneration,
            packageURL: URL(fileURLWithPath: "/tmp/future-race-current")
        )
        let authority = RetainedPackageAuthority(
            index: InstalledPackageIndex(
                nextActivationSequence: 3,
                generations: [previousGeneration, currentGeneration],
                activeGenerationByPackage: [
                    fixture.release.packageID:
                        currentGeneration.generationID,
                ]
            ),
            locationsByPackage: [
                fixture.release.packageID: RetainedPackageLocations(
                    activeGeneration: currentGeneration,
                    activePackage: currentPackage,
                    previousGeneration: previousGeneration,
                    previousPackage: previousPackage
                ),
            ]
        )
        return FutureReleaseContinuityRaceFixture(
            payload: fixture.payload,
            release: fixture.release,
            previousVersion: previousVersion,
            previousVerifiedPackage: previousVerifiedPackage,
            currentVerifiedPackage: fixture.verifiedPackage,
            previousGeneration: previousGeneration,
            currentGeneration: currentGeneration,
            authority: authority
        )
    }
}

private struct FutureReleaseAuthorityFixture: Sendable {
    let payload: ContentPackagePayload
    let release: Release
    let verifiedPackage: VerifiedContentPackage
    let generation: InstalledPackageGeneration
    let authority: RetainedPackageAuthority
}

private struct FutureReleaseContinuityRaceFixture: Sendable {
    let payload: ContentPackagePayload
    let release: Release
    let previousVersion: SchemaVersion
    let previousVerifiedPackage: VerifiedContentPackage
    let currentVerifiedPackage: VerifiedContentPackage
    let previousGeneration: InstalledPackageGeneration
    let currentGeneration: InstalledPackageGeneration
    let authority: RetainedPackageAuthority
}

private actor CountingFutureReleaseAuthorityProvider {
    private let releases: [Release]
    private var authority: RetainedPackageAuthority
    private let gate: FutureReleaseRefreshGate?
    private let authorityGate: FutureReleaseRefreshGate?
    private var releaseReadCount = 0
    private var authorityReadCount = 0

    init(
        releases: [Release],
        authority: RetainedPackageAuthority,
        gate: FutureReleaseRefreshGate? = nil,
        authorityGate: FutureReleaseRefreshGate? = nil
    ) {
        self.releases = releases
        self.authority = authority
        self.gate = gate
        self.authorityGate = authorityGate
    }

    func readReleases() async throws -> [Release] {
        releaseReadCount += 1
        if let gate { await gate.enterAndWait() }
        return releases
    }

    func readAuthority() async throws -> RetainedPackageAuthority {
        authorityReadCount += 1
        let captured = authority
        if let authorityGate { await authorityGate.enterAndWait() }
        return captured
    }

    func deactivate(
        packageID: PackageID,
        expectedGeneration: InstalledPackageGeneration
    ) -> PackageDeactivationResult {
        guard authority.index.activeGeneration(for: packageID)
                == expectedGeneration else {
            return .staleAuthority
        }
        var active = authority.index.activeGenerationByPackage
        active.removeValue(forKey: packageID)
        let index = InstalledPackageIndex(
            formatVersion: authority.index.formatVersion,
            nextActivationSequence: authority.index.nextActivationSequence,
            generations: authority.index.generations,
            activeGenerationByPackage: active
        )
        var locations = authority.locationsByPackage
        if let retained = locations[packageID] {
            locations[packageID] = RetainedPackageLocations(
                activeGeneration: nil,
                activePackage: nil,
                previousGeneration: retained.previousGeneration,
                previousPackage: retained.previousPackage
            )
        }
        authority = RetainedPackageAuthority(
            index: index,
            locationsByPackage: locations
        )
        return .deactivated(expectedGeneration)
    }

    func rollback(
        packageID: PackageID,
        expectedCurrent: InstalledPackageGeneration,
        expectedPrevious: InstalledPackageGeneration
    ) -> ExactPackageRollbackResult {
        guard authority.index.activeGeneration(for: packageID)
                == expectedCurrent,
              authority.locationsByPackage[packageID]?.previousGeneration
                == expectedPrevious,
              let previousPackage = authority.locationsByPackage[packageID]?
                .previousPackage else {
            return .staleAuthority
        }
        let index = InstalledPackageIndex(
            formatVersion: authority.index.formatVersion,
            nextActivationSequence: authority.index.nextActivationSequence,
            generations: authority.index.generations,
            activeGenerationByPackage: [
                packageID: expectedPrevious.generationID,
            ]
        )
        authority = RetainedPackageAuthority(
            index: index,
            locationsByPackage: [
                packageID: RetainedPackageLocations(
                    activeGeneration: expectedPrevious,
                    activePackage: previousPackage,
                    previousGeneration: expectedCurrent,
                    previousPackage: authority.locationsByPackage[packageID]?
                        .activePackage
                ),
            ]
        )
        return .rolledBack(previousPackage)
    }

    func counts() -> (releaseReads: Int, authorityReads: Int) {
        (releaseReadCount, authorityReadCount)
    }
}

private actor GatedFutureReleaseAuthorityProvider {
    private let releases: [Release]
    private var authority: RetainedPackageAuthority
    private var nextAuthorityReadGate: FutureReleaseRefreshGate?

    init(releases: [Release], authority: RetainedPackageAuthority) {
        self.releases = releases
        self.authority = authority
    }

    func readReleases() async throws -> [Release] {
        releases
    }

    func armNextAuthorityRead(_ gate: FutureReleaseRefreshGate) {
        nextAuthorityReadGate = gate
    }

    func readAuthority() async throws -> RetainedPackageAuthority {
        let captured = authority
        let gate = nextAuthorityReadGate
        nextAuthorityReadGate = nil
        if let gate {
            await gate.enterAndWait()
        }
        return captured
    }

    func rollback(
        packageID: PackageID,
        expectedCurrent: InstalledPackageGeneration,
        expectedPrevious: InstalledPackageGeneration,
        mutationGate: FutureReleaseRefreshGate,
        freshReadGate: FutureReleaseRefreshGate
    ) async -> ExactPackageRollbackResult {
        await mutationGate.enterAndWait()
        guard authority.index.activeGeneration(for: packageID)
                == expectedCurrent,
              authority.locationsByPackage[packageID]?.previousGeneration
                == expectedPrevious,
              let previousPackage = authority.locationsByPackage[packageID]?
                .previousPackage,
              let currentPackage = authority.locationsByPackage[packageID]?
                .activePackage else {
            return .staleAuthority
        }
        authority = RetainedPackageAuthority(
            index: InstalledPackageIndex(
                formatVersion: authority.index.formatVersion,
                nextActivationSequence:
                    authority.index.nextActivationSequence,
                generations: authority.index.generations,
                activeGenerationByPackage: [
                    packageID: expectedPrevious.generationID,
                ]
            ),
            locationsByPackage: [
                packageID: RetainedPackageLocations(
                    activeGeneration: expectedPrevious,
                    activePackage: previousPackage,
                    previousGeneration: expectedCurrent,
                    previousPackage: currentPackage
                ),
            ]
        )
        nextAuthorityReadGate = freshReadGate
        return .rolledBack(previousPackage)
    }

    func deactivate(
        packageID: PackageID,
        expectedGeneration: InstalledPackageGeneration,
        mutationGate: FutureReleaseRefreshGate,
        freshReadGate: FutureReleaseRefreshGate
    ) async -> PackageDeactivationResult {
        await mutationGate.enterAndWait()
        guard authority.index.activeGeneration(for: packageID)
                == expectedGeneration else {
            return .staleAuthority
        }
        var active = authority.index.activeGenerationByPackage
        active.removeValue(forKey: packageID)
        let retained = authority.locationsByPackage[packageID]
        authority = RetainedPackageAuthority(
            index: InstalledPackageIndex(
                formatVersion: authority.index.formatVersion,
                nextActivationSequence:
                    authority.index.nextActivationSequence,
                generations: authority.index.generations,
                activeGenerationByPackage: active
            ),
            locationsByPackage: [
                packageID: RetainedPackageLocations(
                    activeGeneration: nil,
                    activePackage: nil,
                    previousGeneration: retained?.previousGeneration,
                    previousPackage: retained?.previousPackage
                ),
            ]
        )
        nextAuthorityReadGate = freshReadGate
        return .deactivated(expectedGeneration)
    }
}

private actor FutureReleaseRefreshGate {
    private var isArmed: Bool
    private var entered = false
    private var isOpen = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var openContinuation: CheckedContinuation<Void, Never>?

    init(initiallyArmed: Bool = true) {
        isArmed = initiallyArmed
    }

    func arm() {
        isArmed = true
        entered = false
        isOpen = false
    }

    func enterAndWait() async {
        guard isArmed else { return }
        isArmed = false
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
