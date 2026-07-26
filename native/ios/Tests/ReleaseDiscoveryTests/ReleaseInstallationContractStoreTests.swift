@testable import ReleaseDiscovery
import ContentKit
import Foundation
import XCTest

final class ReleaseInstallationContractStoreTests: XCTestCase {
    func testPinSealsExactOfflineVerificationContractAcrossColdLaunch() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try contractStore(at: directory)
        let contract = try entry(id: "release-alpha-v1")

        XCTAssertEqual(try store.pin(contract), 2)
        let cold = try contractStore(at: directory)
        let restored = try XCTUnwrap(cold.entry(for: contract.id))
        XCTAssertEqual(restored, contract)
        XCTAssertEqual(
            try restored.release.packageSpecForVerification(),
            try contract.release.packageSpecForVerification()
        )
    }

    func testPinRejectsImmutableReleaseAndPackageBindingChanges() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try contractStore(at: directory)
        let alpha = try entry(id: "release-alpha-v1")
        try store.pin(alpha)

        var changed = try entry(id: "release-alpha-v1", worldNodeID: "world-beta")
        XCTAssertThrowsError(try store.pin(changed)) { error in
            XCTAssertEqual(
                error as? ReleaseCatalogError,
                .immutableReleaseChanged("release-alpha-v1")
            )
        }

        changed = try entry(
            id: "release-beta-v1",
            contentID: "beta-deep-dive",
            packageID: alpha.release.packageID.rawValue
        )
        XCTAssertThrowsError(try store.pin(changed)) { error in
            XCTAssertEqual(
                error as? ReleaseCatalogError,
                .duplicatePackageBinding(
                    packageID: alpha.release.packageID,
                    version: alpha.release.version
                )
            )
        }
    }

    func testNewestSlotCorruptionCannotLosePinnedContract() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try contractStore(at: directory)
        let contract = try entry(id: "release-alpha-v1")
        try store.pin(contract)

        try Data("interrupted".utf8).write(to: store.slotBURL, options: .atomic)
        XCTAssertEqual(try store.entry(for: contract.id), contract)
    }

    func testBothCorruptSlotsFailClosed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try contractStore(at: directory)
        try store.pin(try entry(id: "release-alpha-v1"))

        try Data("bad-a".utf8).write(to: store.slotAURL, options: .atomic)
        try Data("bad-b".utf8).write(to: store.slotBURL, options: .atomic)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(
                error as? ReleaseInstallationContractStoreError,
                .corruptStorage
            )
        }
    }

    func testRetirementIsSealedAgainstFallbackResurrection() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try contractStore(at: directory)
        let contract = try entry(id: "release-alpha-v1")
        try store.pin(contract)
        XCTAssertEqual(try store.retire(contract.id), 4)

        try Data("interrupted".utf8).write(to: store.slotBURL, options: .atomic)
        XCTAssertNil(try store.entry(for: contract.id))
    }

    private func entry(
        id: String,
        contentID: String = "alpha-deep-dive",
        packageID: String = "deep-dive-alpha-v1",
        worldNodeID: String = "world-alpha"
    ) throws -> ReleaseCatalogEntry {
        let release = Release(
            id: ReleaseID(id),
            contentID: contentID,
            packageID: PackageID(packageID),
            version: SchemaVersion(major: 1),
            chapterIDs: [ChapterID(contentID)],
            maximumInstalledBytes: 420_000_000,
            publishedAtUnixMillis: 1_900_000_000_000,
            minimumRuntime: SchemaVersion(major: 1)
        )
        let entry = ReleaseCatalogEntry(
            release: release,
            placement: ReleaseWorldPlacement(
                worldNodeID: WorldNodeID(worldNodeID),
                historicalTime: HistoricalTimeAnchor(astronomicalYear: 1096)
            ),
            announcement: ReleaseAnnouncement(
                title: "A road opens",
                body: "The new route is ready."
            )
        )
        try entry.validate()
        return entry
    }

    private func contractStore(
        at directory: URL
    ) throws -> ReleaseInstallationContractStore {
        try ReleaseInstallationContractStore(
            directoryURL: directory,
            keyProvider: ContractIntegrityKeyProvider()
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "release-install-contract-tests-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

private struct ContractIntegrityKeyProvider: ReleaseCacheIntegrityKeyProviding {
    func loadOrCreateKey() throws -> Data {
        Data(repeating: 0x7A, count: 32)
    }
}
