import Foundation
@testable import JourneyContent
import XCTest

@testable import ContentKit

final class ContentRepositoryTests: XCTestCase {
    func testCanonicalPackagesAreRevalidatedAndIndexedInLaunchOrder() throws {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let paid = JourneyContentFixtures.package("paid-pack-01")
        XCTAssertNoThrow(try essential.validate())
        XCTAssertNoThrow(try paid.validate())

        let repository = try ContentRepository(packagePayloads: [paid, essential])

        XCTAssertEqual(
            repository.availablePackageIDs,
            ["essential-free-v1", "paid-pack-01"]
        )
        XCTAssertEqual(
            repository.availableChapterIDs,
            [
                "first-farmers",
                "steppe-comes-west",
                "bronze-europe",
                "greece-and-the-citizen",
                "europe-holds-the-line",
                "european-world",
            ]
        )
        let chapter = try XCTUnwrap(repository.chapter("first-farmers"))
        XCTAssertEqual(chapter.title.launchEnglish, "The First Farmers")
        XCTAssertEqual(repository.packageID(for: chapter.id), "essential-free-v1")
        XCTAssertEqual(repository.contentVersion(for: chapter.id), .init(major: 1))

        let arc = try XCTUnwrap(repository.arc("first-farmers-arc-one"))
        let beat = try XCTUnwrap(repository.beat("first-farmers-beat-two"))
        XCTAssertEqual(arc.beats[1], beat)
        XCTAssertEqual(
            repository.location(of: arc.id),
            ArcContentLocation(chapterID: chapter.id, arcIndex: 0)
        )
        XCTAssertEqual(
            repository.location(of: beat.id),
            BeatContentLocation(
                chapterID: chapter.id,
                arcID: arc.id,
                arcIndex: 0,
                beatIndex: 1
            )
        )
        let scene = try XCTUnwrap(repository.scene(beat.sceneID))
        XCTAssertEqual(
            repository.accessibility(scene.accessibilityID)?.id,
            scene.accessibilityID
        )
        let interaction = try XCTUnwrap(beat.interaction)
        XCTAssertEqual(repository.interaction(interaction.id), interaction)

        let timeline = try XCTUnwrap(repository.audioTimeline("timeline-paid-pack-01"))
        XCTAssertEqual(
            repository.audioTimeline(containing: "sound-paid-pack-01"),
            timeline
        )
        XCTAssertEqual(repository.audioTimelineIDs(for: beat.id), [])
        XCTAssertNil(repository.chapter("rome-gathers-europe"))
    }

    func testVerifiedPackagesUseTheSameFailClosedIndexBoundary() throws {
        let payload = JourneyContentFixtures.package("essential-free-v1")
        let verified = VerifiedContentPackage(
            manifest: JourneyContentFixtures.signedManifest(for: payload),
            payload: payload
        )
        let repository = try ContentRepository(verifiedPackages: [verified])

        XCTAssertEqual(repository.availablePackageIDs, ["essential-free-v1"])
        XCTAssertEqual(repository.availableChapterIDs.count, 3)
        XCTAssertEqual(repository.worldSeed, payload.worldSeed)
    }

    func testProductionTrustDomainsAssembleBundledEssentialAndVerifiedDownloads() throws {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let paid = JourneyContentFixtures.package("paid-pack-01")
        let verifiedPaid = VerifiedContentPackage(
            manifest: JourneyContentFixtures.signedManifest(for: paid),
            payload: paid
        )

        let repository = try ContentRepository(
            bundledEssentialPayload: essential,
            verifiedPackages: [verifiedPaid]
        )

        XCTAssertEqual(
            repository.availablePackageIDs,
            ["essential-free-v1", "paid-pack-01"]
        )
        XCTAssertEqual(repository.availableChapterIDs.count, 6)
    }

    func testProductionTrustDomainsCannotShadowOrSubstituteEssentialPackage() throws {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let paid = JourneyContentFixtures.package("paid-pack-01")

        XCTAssertThrowsError(
            try ContentRepository(
                bundledEssentialPayload: paid,
                verifiedPackages: []
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .bundledEssentialPackageMismatch(actual: "paid-pack-01")
            )
        }

        let verifiedEssential = VerifiedContentPackage(
            manifest: JourneyContentFixtures.signedManifest(for: essential),
            payload: essential
        )
        XCTAssertThrowsError(
            try ContentRepository(
                bundledEssentialPayload: essential,
                verifiedPackages: [verifiedEssential]
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .downloadedEssentialPackageForbidden("essential-free-v1")
            )
        }
    }

    func testRepositoryRequiresTheExactGeneratedLaunchManifest() throws {
        let canonical = LaunchContent.collectionManifest
        let altered = CollectionManifest(
            schemaVersion: canonical.schemaVersion,
            collectionID: canonical.collectionID,
            locale: canonical.locale,
            product: ProductMetadata(
                franchiseName: canonical.product.franchiseName,
                workTitle: "Altered work title"
            ),
            chapters: canonical.chapters,
            packages: canonical.packages,
            entitlements: canonical.entitlements
        )

        XCTAssertThrowsError(
            try ContentRepository(
                manifest: altered,
                packagePayloads: [JourneyContentFixtures.package("essential-free-v1")]
            )
        ) { error in
            XCTAssertEqual(error as? ContentRepositoryError, .launchManifestMismatch)
        }
    }

    func testRepositoryRequiresOneCompleteEssentialPackage() throws {
        XCTAssertThrowsError(try ContentRepository(packagePayloads: [])) { error in
            XCTAssertEqual(error as? ContentRepositoryError, .emptyPackageSet)
        }

        XCTAssertThrowsError(
            try ContentRepository(
                packagePayloads: [JourneyContentFixtures.package("paid-pack-01")]
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .missingEssentialPackage("essential-free-v1")
            )
        }
    }

    func testRepositoryRejectsUnknownAndDuplicatePackages() throws {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let unknown = JourneyContentFixtures.replacing(
            essential,
            packageID: "unknown-package"
        )
        XCTAssertThrowsError(
            try ContentRepository(packagePayloads: [unknown])
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .unknownPackage("unknown-package")
            )
        }

        XCTAssertThrowsError(
            try ContentRepository(packagePayloads: [essential, essential])
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .duplicatePackage("essential-free-v1")
            )
        }
    }

    func testRepositoryRejectsChapterSequenceAndCatalogCopyDrift() throws {
        let reversed = JourneyContentFixtures.package(
            "essential-free-v1",
            reverseChapterOrder: true
        )
        XCTAssertThrowsError(
            try ContentRepository(packagePayloads: [reversed])
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .chapterOwnershipMismatch(packageID: "essential-free-v1")
            )
        }

        let altered = JourneyContentFixtures.package(
            "essential-free-v1",
            alteredTitleFor: "first-farmers"
        )
        XCTAssertThrowsError(
            try ContentRepository(packagePayloads: [altered])
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .catalogChapterMismatch(chapterID: "first-farmers")
            )
        }
    }

    func testRepositoryRejectsPayloadSchemaAndWorldSeedDrift() throws {
        let wrongSchema = JourneyContentFixtures.package(
            "essential-free-v1",
            schemaVersion: SchemaVersion(major: 2)
        )
        XCTAssertThrowsError(
            try ContentRepository(packagePayloads: [wrongSchema])
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .packageSchemaMismatch(
                    packageID: "essential-free-v1",
                    expected: SchemaVersion(major: 1),
                    actual: SchemaVersion(major: 2)
                )
            )
        }

        let alteredSeed = WorldSeedSpec(
            nodes: [
                WorldNodeBlueprint(
                    id: "seed-node",
                    kind: .landscape,
                    form: "seeded",
                    position: NormalizedPoint(x: 0.5, y: 0.5)
                ),
            ],
            traces: []
        )
        XCTAssertThrowsError(
            try ContentRepository(
                packagePayloads: [
                    JourneyContentFixtures.package("essential-free-v1"),
                    JourneyContentFixtures.package(
                        "paid-pack-01",
                        worldSeed: alteredSeed
                    ),
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .worldSeedMismatch(packageID: "paid-pack-01")
            )
        }
    }

    func testVerifiedPackageMetadataMustMatchTheCurrentCatalog() throws {
        let payload = JourneyContentFixtures.package("essential-free-v1")
        let mismatches: [(SignedPackageManifest, ContentRepositoryError)] = [
            (
                JourneyContentFixtures.signedManifest(
                    for: payload,
                    packageVersion: SchemaVersion(major: 2)
                ),
                .packageVersionMismatch(
                    packageID: payload.packageID,
                    expected: SchemaVersion(major: 1),
                    actual: SchemaVersion(major: 2)
                )
            ),
            (
                JourneyContentFixtures.signedManifest(
                    for: payload,
                    schemaVersion: SchemaVersion(major: 2)
                ),
                .packageSchemaMismatch(
                    packageID: payload.packageID,
                    expected: SchemaVersion(major: 1),
                    actual: SchemaVersion(major: 2)
                )
            ),
            (
                JourneyContentFixtures.signedManifest(
                    for: payload,
                    minimumRuntime: SchemaVersion(major: 2)
                ),
                .packageRuntimeMismatch(
                    packageID: payload.packageID,
                    expected: SchemaVersion(major: 1),
                    actual: SchemaVersion(major: 2)
                )
            ),
        ]

        for (manifest, expectedError) in mismatches {
            let verified = VerifiedContentPackage(manifest: manifest, payload: payload)
            XCTAssertThrowsError(
                try ContentRepository(verifiedPackages: [verified])
            ) { error in
                XCTAssertEqual(error as? ContentRepositoryError, expectedError)
            }
        }
    }

    func testEveryGlobalRuntimeIdentifierRejectsCrossPackageCollision() throws {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let firstChapter = essential.chapters[0]
        let firstArc = firstChapter.arcs[0]
        let firstBeat = firstArc.beats[0]
        let interactionBeat = firstArc.beats[1]
        let collisionCases: [(String, JourneyContentIdentifierOverrides)] = [
            ("arc", .init(arcID: firstArc.id)),
            ("beat", .init(beatID: firstBeat.id)),
            ("scene", .init(sceneID: firstBeat.sceneID)),
            ("interaction", .init(interactionID: interactionBeat.interaction!.id)),
            ("audio-timeline", .init(timelineID: essential.audioTimelines[0].id)),
            ("audio-cue", .init(cueID: essential.audioTimelines[0].events[0].cueID)),
            (
                "accessibility",
                .init(accessibilityID: interactionBeat.interaction!.accessibilityID)
            ),
            ("world-effect", .init(effectID: firstChapter.completionEffects[0].id)),
        ]

        for (expectedNamespace, overrides) in collisionCases {
            let paid = JourneyContentFixtures.package(
                "paid-pack-01",
                firstChapterOverrides: overrides
            )
            XCTAssertThrowsError(
                try ContentRepository(packagePayloads: [essential, paid]),
                "Expected a collision in \(expectedNamespace)"
            ) { error in
                guard case let .duplicateIdentifier(namespace, _, first, second)
                    = error as? ContentRepositoryError else {
                    return XCTFail("Unexpected error for \(expectedNamespace): \(error)")
                }
                XCTAssertEqual(namespace, expectedNamespace)
                XCTAssertEqual(first, "essential-free-v1")
                XCTAssertEqual(second, "paid-pack-01")
            }
        }
    }

    func testPackagesMustComposeOneDeterministicCumulativeWorld() throws {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let paid = JourneyContentFixtures.package("paid-pack-01")
        let original = paid.chapters[0]
        let conflicting = ChapterSpec(
            schemaVersion: original.schemaVersion,
            id: original.id,
            title: original.title,
            period: original.period,
            arcs: original.arcs,
            completionEffects: [
                WorldEffect(
                    id: "effect-conflicting-world-node",
                    mutation: .revealNode(
                        WorldNodeBlueprint(
                            id: "node-complete-first-farmers",
                            kind: .landscape,
                            form: "a-conflicting-form",
                            position: NormalizedPoint(x: 0.5, y: 0.5)
                        )
                    )
                ),
            ]
        )
        let alteredPaid = JourneyContentFixtures.replacing(
            paid,
            chapters: [conflicting] + paid.chapters.dropFirst()
        )
        XCTAssertNoThrow(try alteredPaid.validate())

        XCTAssertThrowsError(
            try ContentRepository(packagePayloads: [essential, alteredPaid])
        ) { error in
            guard case let .invalidCumulativeWorld(reason)
                = error as? ContentRepositoryError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("node-complete-first-farmers"))
        }
    }
}
