import ContentKit
import Foundation
@testable import JourneyContent
import XCTest

final class BundledEssentialContentLoaderTests: XCTestCase {
    func testCanonicalEssentialBytesOpenOneFailClosedRepository() throws {
        let payload = JourneyContentFixtures.package("essential-free-v1")
        let data = try ContentDocumentDecoder.encodePackage(payload)

        let repository = try BundledEssentialContentLoader().load(data: data)

        XCTAssertEqual(repository.availablePackageIDs, ["essential-free-v1"])
        XCTAssertEqual(
            repository.availableChapterIDs,
            ["first-farmers", "europe-holds-the-line", "european-world"]
        )
        XCTAssertEqual(repository.worldSeed, payload.worldSeed)
    }

    func testMalformedBytesFailBeforeAnyRepositoryExists() {
        XCTAssertThrowsError(
            try BundledEssentialContentLoader().load(data: Data("{}".utf8))
        ) { error in
            XCTAssertEqual(
                error as? BundledEssentialContentLoaderError,
                .invalidPayload
            )
        }
    }

    func testDecodedEssentialPayloadCanEnterMixedTrustAssembly() throws {
        let essential = JourneyContentFixtures.package("essential-free-v1")
        let data = try ContentDocumentDecoder.encodePackage(essential)
        let loader = BundledEssentialContentLoader()

        let decoded = try loader.decodePayload(data: data)
        let repository = try ContentRepository(
            bundledEssentialPayload: decoded,
            verifiedPackages: []
        )

        XCTAssertEqual(repository.availablePackageIDs, ["essential-free-v1"])
    }

    func testPaidPackageCannotMasqueradeAsBundledEssentialContent() throws {
        let payload = JourneyContentFixtures.package("paid-pack-01")
        let data = try ContentDocumentDecoder.encodePackage(payload)

        XCTAssertThrowsError(
            try BundledEssentialContentLoader().load(data: data)
        ) { error in
            XCTAssertEqual(
                error as? BundledEssentialContentLoaderError,
                .packageIdentityMismatch(
                    expected: "essential-free-v1",
                    actual: "paid-pack-01"
                )
            )
        }
    }

    func testMissingBundleResourceIsExplicitAndFailClosed() {
        let loader = BundledEssentialContentLoader(
            resourceName: "resource-that-cannot-exist",
            resourceExtension: "json",
            resourceSubdirectory: "JourneyContent"
        )

        XCTAssertThrowsError(try loader.load(from: Bundle(for: Self.self))) { error in
            XCTAssertEqual(
                error as? BundledEssentialContentLoaderError,
                .resourceMissing(
                    name: "resource-that-cannot-exist",
                    extension: "json",
                    subdirectory: "JourneyContent"
                )
            )
        }
    }

    func testRepositoryStillRejectsCatalogDriftAfterCanonicalDecode() throws {
        let altered = JourneyContentFixtures.package(
            "essential-free-v1",
            alteredTitleFor: "first-farmers"
        )
        let data = try ContentDocumentDecoder.encodePackage(altered)

        XCTAssertThrowsError(
            try BundledEssentialContentLoader().load(data: data)
        ) { error in
            XCTAssertEqual(
                error as? ContentRepositoryError,
                .catalogChapterMismatch(chapterID: "first-farmers")
            )
        }
    }
}
