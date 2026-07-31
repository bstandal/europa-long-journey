import ContentKit
import ContentKitTestSupport
import XCTest

final class FutureReleaseTests: XCTestCase {
    private func release(
        contentID: String = "first-crusade-deep-dive",
        chapterIDs: [ChapterID] = ["first-crusade-deep-dive"],
        maximumInstalledBytes: Int64 = 420_000_000
    ) -> Release {
        Release(
            id: "release-first-crusade-v1",
            contentID: contentID,
            packageID: "deep-dive-first-crusade-v1",
            version: SchemaVersion(major: 1, minor: 2, patch: 0),
            chapterIDs: chapterIDs,
            maximumInstalledBytes: maximumInstalledBytes,
            publishedAtUnixMillis: 1_800_000_000_000,
            minimumRuntime: SchemaVersion(major: 1, minor: 1, patch: 0)
        )
    }

    func testTrustedFutureReleaseDerivesExactVerificationPackageSpec() throws {
        let release = release()
        let spec = try release.packageSpecForVerification()

        XCTAssertEqual(spec.id, release.packageID)
        XCTAssertEqual(spec.version, release.version)
        XCTAssertEqual(spec.chapterIDs, release.chapterIDs)
        XCTAssertEqual(spec.maximumInstalledBytes, release.maximumInstalledBytes)
        XCTAssertEqual(spec.minimumRuntime, release.minimumRuntime)
        XCTAssertFalse(spec.isEssentialInstall)

        let encoded = try JSONEncoder().encode(release)
        let decoded = try ReleaseCatalogDecoder.decode(encoded)
        XCTAssertEqual(decoded, release)
    }

    func testFutureReleaseRejectsUnownedContentAndInvalidBudget() {
        XCTAssertThrowsError(
            try release(
                contentID: "unowned-deep-dive",
                chapterIDs: ["first-crusade-deep-dive"]
            ).packageSpecForVerification()
        )
        XCTAssertThrowsError(
            try release(maximumInstalledBytes: 0).packageSpecForVerification()
        )
        XCTAssertThrowsError(
            try release(
                chapterIDs: ["first-crusade-deep-dive", "first-crusade-deep-dive"]
            ).packageSpecForVerification()
        )
    }

    func testFutureReleaseWireModelRequiresInstalledByteBudgetAndChapterOwnership() throws {
        let encoded = try JSONEncoder().encode(release())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "maximumInstalledBytes")
        let missingBudget = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try ReleaseCatalogDecoder.decode(missingBudget))

        object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "chapterIDs")
        let missingOwnership = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try ReleaseCatalogDecoder.decode(missingOwnership))

        object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["researchNotes"] = ["must never become public catalog data"]
        let unknownPublicField = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try ReleaseCatalogDecoder.decode(unknownPublicField))

        object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var releaseVersion = try XCTUnwrap(object["version"] as? [String: Any])
        releaseVersion["label"] = "untrusted"
        object["version"] = releaseVersion
        let unknownVersionField = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try ReleaseCatalogDecoder.decode(unknownVersionField))
    }
}
