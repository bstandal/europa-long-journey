@testable import ContentKit
import Foundation
@testable import JourneyContent
import XCTest

final class FutureReleaseContentRepositoryTests: XCTestCase {
    func testVerifiedFutureReleaseBecomesAnIsolatedOfflineRepository() throws {
        let payload = JourneyContentFixtures.futurePackage()
        let release = makeRelease(for: payload)
        let verified = VerifiedContentPackage(
            manifest: JourneyContentFixtures.signedManifest(
                for: payload,
                packageVersion: release.version,
                minimumRuntime: release.minimumRuntime
            ),
            payload: payload
        )

        let repository = try ContentRepository(
            trustedFutureRelease: release,
            verifiedPackage: verified,
            expectedWorldSeed: payload.worldSeed
        )

        XCTAssertEqual(repository.availablePackageIDs, [release.packageID])
        XCTAssertEqual(repository.availableChapterIDs, release.chapterIDs)
        XCTAssertEqual(repository.worldSeed, payload.worldSeed)
        XCTAssertEqual(
            repository.contentVersion(for: "alpha-deep-dive"),
            release.version
        )
        let chapter = try XCTUnwrap(
            repository.chapter(ChapterID("alpha-deep-dive"))
        )
        let beat = try XCTUnwrap(chapter.arcs.first?.beats.first)
        XCTAssertEqual(repository.scene(beat.sceneID)?.id, beat.sceneID)
        XCTAssertEqual(
            repository.responsiveAudioProgram(for: beat.interaction!.id)?.scope.beatID,
            beat.id
        )
    }

    func testFutureReleaseRequiresTheCanonicalLivingWorldSeed() throws {
        let payload = JourneyContentFixtures.futurePackage()
        let release = makeRelease(for: payload)
        let verified = verifiedPackage(payload: payload, release: release)
        let differentSeed = WorldSeedSpec(
            nodes: [
                WorldNodeBlueprint(
                    id: "different-seed-node",
                    kind: .landscape,
                    form: "different",
                    position: NormalizedPoint(x: 0.5, y: 0.5)
                ),
            ],
            traces: []
        )

        XCTAssertThrowsError(
            try ContentRepository(
                trustedFutureRelease: release,
                verifiedPackage: verified,
                expectedWorldSeed: differentSeed
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .worldSeedMismatch(packageID: payload.packageID)
            )
        }
    }

    func testFutureReleaseCannotReuseLockedLaunchChapterOrPackageIdentity() throws {
        let chapterCollision = JourneyContentFixtures.futurePackage(
            chapterID: "first-farmers"
        )
        let chapterRelease = makeRelease(for: chapterCollision)
        XCTAssertThrowsError(
            try ContentRepository(
                trustedFutureRelease: chapterRelease,
                verifiedPackage: verifiedPackage(
                    payload: chapterCollision,
                    release: chapterRelease
                ),
                expectedWorldSeed: chapterCollision.worldSeed
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .futureReleaseLaunchCollision(
                    namespace: "chapter",
                    identifier: "first-farmers"
                )
            )
        }

        let packageCollision = JourneyContentFixtures.futurePackage(
            packageID: "paid-pack-01"
        )
        let packageRelease = makeRelease(for: packageCollision)
        XCTAssertThrowsError(
            try ContentRepository(
                trustedFutureRelease: packageRelease,
                verifiedPackage: verifiedPackage(
                    payload: packageCollision,
                    release: packageRelease
                ),
                expectedWorldSeed: packageCollision.worldSeed
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .futureReleaseLaunchCollision(
                    namespace: "package",
                    identifier: "paid-pack-01"
                )
            )
        }
    }

    func testFutureReleaseWorldEffectsUseTheirGloballyUniqueChapterNamespace()
        throws
    {
        let payload = JourneyContentFixtures.futurePackage()
        let chapter = payload.chapters[0]
        let unownedEffect = WorldEffect(
            id: "effect-first-farmers-collision",
            mutation: chapter.completionEffects[0].mutation
        )
        let alteredChapter = ChapterSpec(
            schemaVersion: chapter.schemaVersion,
            id: chapter.id,
            title: chapter.title,
            period: chapter.period,
            arcs: chapter.arcs,
            completionEffects: [unownedEffect]
        )
        let altered = JourneyContentFixtures.replacing(
            payload,
            chapters: [alteredChapter]
        )
        let release = makeRelease(for: altered)

        XCTAssertThrowsError(
            try ContentRepository(
                trustedFutureRelease: release,
                verifiedPackage: verifiedPackage(
                    payload: altered,
                    release: release
                ),
                expectedWorldSeed: altered.worldSeed
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .invalidFutureRelease(
                    "world-effect effect-first-farmers-collision must use owning chapter namespace effect-alpha-deep-dive-"
                )
            )
        }
    }

    func testFutureReleaseWorldEffectNamespaceRequiresAStableLocalSuffix()
        throws
    {
        let payload = JourneyContentFixtures.futurePackage()
        let chapter = payload.chapters[0]
        let emptyLocalIdentity = WorldEffect(
            id: "effect-alpha-deep-dive-",
            mutation: chapter.completionEffects[0].mutation
        )
        let alteredChapter = ChapterSpec(
            schemaVersion: chapter.schemaVersion,
            id: chapter.id,
            title: chapter.title,
            period: chapter.period,
            arcs: chapter.arcs,
            completionEffects: [emptyLocalIdentity]
        )
        let altered = JourneyContentFixtures.replacing(
            payload,
            chapters: [alteredChapter]
        )
        let release = makeRelease(for: altered)

        XCTAssertThrowsError(
            try ContentRepository(
                trustedFutureRelease: release,
                verifiedPackage: verifiedPackage(
                    payload: altered,
                    release: release
                ),
                expectedWorldSeed: altered.worldSeed
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .invalidFutureRelease(
                    "world-effect effect-alpha-deep-dive- must use owning chapter namespace effect-alpha-deep-dive-"
                )
            )
        }
    }

    func testFutureReleaseRechecksSignedVersionAndRuntimeAgainstRelease() throws {
        let payload = JourneyContentFixtures.futurePackage()
        let release = makeRelease(for: payload)
        let wrongVersion = SchemaVersion(major: 2)
        let wrongVersionPackage = VerifiedContentPackage(
            manifest: JourneyContentFixtures.signedManifest(
                for: payload,
                packageVersion: wrongVersion,
                minimumRuntime: release.minimumRuntime
            ),
            payload: payload
        )

        XCTAssertThrowsError(
            try ContentRepository(
                trustedFutureRelease: release,
                verifiedPackage: wrongVersionPackage,
                expectedWorldSeed: payload.worldSeed
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .packageVersionMismatch(
                    packageID: payload.packageID,
                    expected: release.version,
                    actual: wrongVersion
                )
            )
        }

        let wrongRuntime = SchemaVersion(major: 2)
        let wrongRuntimePackage = VerifiedContentPackage(
            manifest: JourneyContentFixtures.signedManifest(
                for: payload,
                packageVersion: release.version,
                minimumRuntime: wrongRuntime
            ),
            payload: payload
        )
        XCTAssertThrowsError(
            try ContentRepository(
                trustedFutureRelease: release,
                verifiedPackage: wrongRuntimePackage,
                expectedWorldSeed: payload.worldSeed
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .packageRuntimeMismatch(
                    packageID: payload.packageID,
                    expected: release.minimumRuntime,
                    actual: wrongRuntime
                )
            )
        }
    }

    private func makeRelease(for payload: ContentPackagePayload) -> Release {
        Release(
            id: "release-alpha-deep-dive-v1",
            contentID: payload.chapters[0].id.rawValue,
            packageID: payload.packageID,
            version: SchemaVersion(major: 1, minor: 2),
            chapterIDs: payload.chapters.map(\.id),
            maximumInstalledBytes: 420_000_000,
            publishedAtUnixMillis: 1_800_000_000_000,
            minimumRuntime: SchemaVersion(major: 1)
        )
    }

    private func verifiedPackage(
        payload: ContentPackagePayload,
        release: Release
    ) -> VerifiedContentPackage {
        VerifiedContentPackage(
            manifest: JourneyContentFixtures.signedManifest(
                for: payload,
                packageVersion: release.version,
                minimumRuntime: release.minimumRuntime
            ),
            payload: payload
        )
    }
}
