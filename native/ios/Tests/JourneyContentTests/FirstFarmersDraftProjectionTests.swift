import ContentKit
import CryptoKit
import Foundation
@testable import JourneyContent
import XCTest

final class FirstFarmersDraftProjectionTests: XCTestCase {
    func testGeneratedChapterIsAValidDeterministicNonShippingDomainProjection() throws {
        let files = try projectionFiles()
        let chapter = try JSONDecoder().decode(ChapterSpec.self, from: files.chapter)
        let seed = try JSONDecoder().decode(WorldSeedSpec.self, from: files.worldSeed)
        let receipt = try JSONDecoder().decode(ProjectionReceipt.self, from: files.receipt)

        try chapter.validate()
        try seed.validate()
        let firstReplay = try WorldReplayValidator.validate(seed: seed, chapters: [chapter])
        let secondReplay = try WorldReplayValidator.validate(seed: seed, chapters: [chapter])

        XCTAssertEqual(firstReplay, secondReplay)
        XCTAssertEqual(chapter.id, "first-farmers")
        XCTAssertEqual(chapter.arcs.map(\.id), [
            "first-farmers-arc-01",
            "first-farmers-arc-02",
            "first-farmers-arc-03",
        ])
        XCTAssertEqual(chapter.arcs.map(\.targetDurationMinutes), [9, 9, 10])
        XCTAssertEqual(chapter.arcs.flatMap(\.beats).count, 17)
        XCTAssertEqual(chapter.arcs.flatMap(\.beats).compactMap(\.interaction).count, 6)
        XCTAssertEqual(
            Set(chapter.arcs.flatMap(\.beats).flatMap(\.narrationCueIDs)).count,
            37
        )
        XCTAssertEqual(chapter.completionEffects.map(\.id), [
            "effect-first-farmers-chapter-complete",
        ])

        XCTAssertEqual(receipt.status, "NON_SHIPPING_DEVELOPMENT_PROJECTION")
        XCTAssertEqual(receipt.shippingState, "PROHIBITED")
        XCTAssertEqual(receipt.chapterSHA256, sha256(files.chapter))
        XCTAssertEqual(receipt.worldSeedSHA256, sha256(files.worldSeed))
        XCTAssertTrue(receipt.claimsExcluded.contains("editor approval"))
        XCTAssertTrue(receipt.claimsExcluded.contains("shipping approval"))
    }

    func testHarvestProjectionPreservesMinimumObligationsAndThreeFreeShares() throws {
        let chapter = try JSONDecoder().decode(
            ChapterSpec.self,
            from: projectionFiles().chapter
        )
        let interaction = try XCTUnwrap(
            chapter.arcs.flatMap(\.beats).compactMap(\.interaction).first {
                $0.id == "interaction-first-farmers-the-harvest-had-to-last"
            }
        )
        guard case let .allocate(configuration) = interaction.grammar else {
            return XCTFail("Harvest must remain Allocate")
        }
        XCTAssertEqual(configuration.totalUnits, 12)
        XCTAssertEqual(
            configuration.destinations.map { "\($0.id):\($0.minimumUnits)" },
            ["food:4", "reserve:2", "seed:3"]
        )
        XCTAssertEqual(
            configuration.totalUnits
                - configuration.destinations.reduce(0) { $0 + $1.minimumUnits },
            3
        )
    }

    func testGeneratedPublicDomainProjectionContainsNoBackstageApparatus() throws {
        let publicBytes = try projectionFiles().chapter
        let value = try XCTUnwrap(String(data: publicBytes, encoding: .utf8)).lowercased()
        for forbidden in [
            "sourceids",
            "evidence",
            "citation",
            "confidence",
            "historians disagree",
            "scholars debate",
            "this account is contested",
        ] {
            XCTAssertFalse(value.contains(forbidden), "Leaked backstage field or phrase: \(forbidden)")
        }
    }

    private func projectionFiles() throws -> (
        chapter: Data,
        worldSeed: Data,
        receipt: Data
    ) {
#if os(iOS)
        let bundle = Bundle(for: FirstFarmersDraftProjectionTests.self)
        func bundled(_ name: String) throws -> Data {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
            return try Data(contentsOf: url)
        }
        return (
            chapter: try bundled("first-farmers.chapter"),
            worldSeed: try bundled("first-farmers.world-seed"),
            receipt: try bundled("first-farmers.projection-receipt")
        )
#else
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let generated = root.appending(path: "phase2/generated")
        return (
            chapter: try Data(contentsOf: generated.appending(path: "first-farmers.chapter.json")),
            worldSeed: try Data(contentsOf: generated.appending(path: "first-farmers.world-seed.json")),
            receipt: try Data(contentsOf: generated.appending(path: "first-farmers.projection-receipt.json"))
        )
#endif
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct ProjectionReceipt: Decodable {
    let status: String
    let shippingState: String
    let chapterSHA256: String
    let worldSeedSHA256: String
    let claimsExcluded: [String]
}
