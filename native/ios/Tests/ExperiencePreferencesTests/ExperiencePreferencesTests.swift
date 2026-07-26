import Foundation
import XCTest
@testable import ExperiencePreferences

final class ExperiencePreferencesTests: XCTestCase {
    func testStableDefaultsRequireExplicitNarrationPlayback() throws {
        let preferences = ExperiencePreferences.standard

        XCTAssertEqual(preferences.schemaVersion, 1)
        XCTAssertTrue(preferences.narrationEnabled)
        XCTAssertEqual(preferences.narrationPlaybackPolicy, .explicitUserActionOnly)
        XCTAssertTrue(preferences.scoreEnabled)
        XCTAssertTrue(preferences.soundscapeEnabled)
        XCTAssertTrue(preferences.hapticsEnabled)
        XCTAssertFalse(preferences.cellularDownloadsEnabled)
        XCTAssertFalse(preferences.automaticDeepDiveDownloadsEnabled)
        XCTAssertNoThrow(try preferences.validate())
    }

    func testDocumentHasNoAutoplayOrDuplicatedSystemAccessibilityChoices() throws {
        let data = try JSONEncoder().encode(ExperiencePreferences.standard)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), [
            "automaticDeepDiveDownloadsEnabled",
            "cellularDownloadsEnabled",
            "hapticsEnabled",
            "narrationEnabled",
            "narrationPlaybackPolicy",
            "schemaVersion",
            "scoreEnabled",
            "soundscapeEnabled",
        ])
        XCTAssertEqual(object["narrationPlaybackPolicy"] as? String, "explicitUserActionOnly")
        XCTAssertNil(object["autoplay"])
        XCTAssertNil(object["dynamicType"])
        XCTAssertNil(object["reduceMotion"])
        XCTAssertNil(object["increaseContrast"])
        XCTAssertNil(object["increasedContrast"])
    }

    func testMissingFileReturnsDefaultsWithoutCreatingState() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)

        let result = try await store.load()

        XCTAssertEqual(result.preferences, .standard)
        XCTAssertEqual(result.origin, .defaultsBecauseFileIsMissing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.preferencesFileURL.path))
    }

    func testSaveAndLoadRoundTripEveryChoice() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stored = ExperiencePreferences(
            narrationEnabled: false,
            scoreEnabled: false,
            soundscapeEnabled: false,
            hapticsEnabled: false,
            cellularDownloadsEnabled: true,
            automaticDeepDiveDownloadsEnabled: true
        )
        let store = try ExperiencePreferencesStore(directoryURL: directory)

        try await store.save(stored)
        let reopened = try ExperiencePreferencesStore(directoryURL: directory)
        let result = try await reopened.load()

        XCTAssertEqual(result.preferences, stored)
        XCTAssertEqual(result.origin, .stored)
        XCTAssertEqual(result.preferences.narrationPlaybackPolicy, .explicitUserActionOnly)
    }

    func testVersionZeroMigratesAtomicallyAndDefaultsNewDownloadChoiceOff() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)
        let legacy = try jsonData([
            "schemaVersion": 0,
            "narrationEnabled": false,
            "scoreEnabled": true,
            "soundscapeEnabled": false,
            "hapticsEnabled": true,
            "cellularDownloadsEnabled": true,
        ])
        try legacy.write(to: store.preferencesFileURL, options: .atomic)

        let result = try await store.load()

        XCTAssertEqual(result.origin, .migrated(fromSchemaVersion: 0))
        XCTAssertEqual(result.preferences, ExperiencePreferences(
            narrationEnabled: false,
            scoreEnabled: true,
            soundscapeEnabled: false,
            hapticsEnabled: true,
            cellularDownloadsEnabled: true,
            automaticDeepDiveDownloadsEnabled: false
        ))
        let rewritten = try JSONDecoder().decode(
            ExperiencePreferences.self,
            from: Data(contentsOf: store.preferencesFileURL)
        )
        XCTAssertEqual(rewritten, result.preferences)
        XCTAssertEqual(rewritten.schemaVersion, ExperiencePreferences.currentSchemaVersion)
        XCTAssertEqual(rewritten.narrationPlaybackPolicy, .explicitUserActionOnly)
    }

    func testFailedMigrationLeavesVersionZeroDocumentUntouched() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(
            directoryURL: directory,
            writer: SelectiveFailingWriter(failure: .canonical)
        )
        let legacy = try jsonData([
            "schemaVersion": 0,
            "narrationEnabled": true,
            "scoreEnabled": false,
            "soundscapeEnabled": true,
            "hapticsEnabled": false,
            "cellularDownloadsEnabled": false,
        ])
        try legacy.write(to: store.preferencesFileURL, options: .atomic)

        do {
            _ = try await store.load()
            XCTFail("Injected migration write should fail")
        } catch {
            XCTAssertEqual(error as? TestWriteError, .injected)
        }

        XCTAssertEqual(try Data(contentsOf: store.preferencesFileURL), legacy)
    }

    func testCorruptFileIsPreservedByteForByteBeforeDefaultsReplaceIt() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)
        let corrupt = Data([0x00, 0x7B, 0xFF, 0x0A, 0x01])
        try corrupt.write(to: store.preferencesFileURL, options: .atomic)

        let result = try await store.load()
        let preservedURL = try recoveredURL(from: result.origin)

        XCTAssertEqual(result.preferences, .standard)
        XCTAssertEqual(try Data(contentsOf: preservedURL), corrupt)
        XCTAssertEqual(
            try JSONDecoder().decode(
                ExperiencePreferences.self,
                from: Data(contentsOf: store.preferencesFileURL)
            ),
            .standard
        )

        let second = try await store.load()
        XCTAssertEqual(second.origin, .stored)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: store.preservedFilesDirectoryURL,
                includingPropertiesForKeys: nil
            ).count,
            1
        )
    }

    func testAutoplayPolicyInStoredJSONIsRejectedAndPreservedAsCorruption() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)
        let autoplay = try currentDocument(
            schemaVersion: 1,
            narrationPlaybackPolicy: "autoplay"
        )
        try autoplay.write(to: store.preferencesFileURL, options: .atomic)

        let result = try await store.load()
        let preservedURL = try recoveredURL(from: result.origin)

        XCTAssertEqual(result.preferences.narrationPlaybackPolicy, .explicitUserActionOnly)
        XCTAssertEqual(try Data(contentsOf: preservedURL), autoplay)
    }

    func testFutureSchemaReturnsSafeDefaultsPreservesBytesAndLeavesCanonicalUntouched() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)
        let future = try jsonData([
            "schemaVersion": 99,
            "futureMeaning": ["unknown", "must-survive"],
        ])
        try future.write(to: store.preferencesFileURL, options: .atomic)

        let result = try await store.load()
        let protected = try protectedFuture(from: result.origin)

        XCTAssertEqual(result.preferences, .standard)
        XCTAssertEqual(protected.version, 99)
        XCTAssertEqual(try Data(contentsOf: protected.url), future)
        XCTAssertEqual(try Data(contentsOf: store.preferencesFileURL), future)

        do {
            try await store.save(ExperiencePreferences(scoreEnabled: false))
            XCTFail("A future-schema canonical document must block writes")
        } catch {
            XCTAssertEqual(
                error as? ExperiencePreferencesStoreError,
                .futureSchemaWriteBlocked(99)
            )
        }
        XCTAssertEqual(try Data(contentsOf: store.preferencesFileURL), future)
    }

    func testRepeatedFutureLoadsReuseOneIdenticalPreservedCopy() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)
        let future = try jsonData(["schemaVersion": 5, "opaque": "retained"])
        try future.write(to: store.preferencesFileURL, options: .atomic)

        let first = try protectedFuture(from: (try await store.load()).origin)
        let second = try protectedFuture(from: (try await store.load()).origin)

        XCTAssertEqual(first.version, 5)
        XCTAssertEqual(first.url, second.url)
        XCTAssertEqual(try Data(contentsOf: first.url), future)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: store.preservedFilesDirectoryURL,
                includingPropertiesForKeys: nil
            ).count,
            1
        )
    }

    func testSaveDetectsFutureSchemaWithoutPriorLoad() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)
        let future = try jsonData(["schemaVersion": 2, "newSetting": true])
        try future.write(to: store.preferencesFileURL, options: .atomic)

        do {
            try await store.save(ExperiencePreferences(scoreEnabled: false))
            XCTFail("Save must inspect an existing canonical document")
        } catch {
            XCTAssertEqual(
                error as? ExperiencePreferencesStoreError,
                .futureSchemaWriteBlocked(2)
            )
        }

        XCTAssertEqual(try Data(contentsOf: store.preferencesFileURL), future)
        let files = try FileManager.default.contentsOfDirectory(
            at: store.preservedFilesDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(files.first)), future)
    }

    func testReloadingSupportedCanonicalDocumentClearsFutureWriteBlock() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)
        let future = try jsonData(["schemaVersion": 12])
        try future.write(to: store.preferencesFileURL, options: .atomic)
        _ = try await store.load()

        let supported = ExperiencePreferences(scoreEnabled: false)
        try JSONEncoder().encode(supported).write(
            to: store.preferencesFileURL,
            options: .atomic
        )
        let reloaded = try await store.load()
        XCTAssertEqual(reloaded.preferences, supported)

        let replacement = ExperiencePreferences(hapticsEnabled: false)
        try await store.save(replacement)
        let final = try await store.load()
        XCTAssertEqual(final.preferences, replacement)
    }

    func testUnsupportedModelCannotBeSaved() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)
        let unsupported = try JSONDecoder().decode(
            ExperiencePreferences.self,
            from: currentDocument(schemaVersion: 7)
        )

        do {
            try await store.save(unsupported)
            XCTFail("A model from an unsupported schema must not be written")
        } catch {
            XCTAssertEqual(
                error as? ExperiencePreferencesValidationError,
                .unsupportedSchemaVersion(7)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.preferencesFileURL.path))
    }

    func testFailedAtomicReplacementLeavesPriorValidDocumentUntouched() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = ExperiencePreferences(scoreEnabled: false)
        let initialStore = try ExperiencePreferencesStore(directoryURL: directory)
        try await initialStore.save(original)
        let originalBytes = try Data(contentsOf: initialStore.preferencesFileURL)

        let failingStore = try ExperiencePreferencesStore(
            directoryURL: directory,
            writer: SelectiveFailingWriter(failure: .canonical)
        )
        do {
            try await failingStore.save(ExperiencePreferences(hapticsEnabled: false))
            XCTFail("Injected write failure should escape")
        } catch {
            XCTAssertEqual(error as? TestWriteError, .injected)
        }

        XCTAssertEqual(try Data(contentsOf: failingStore.preferencesFileURL), originalBytes)
        let reopened = try ExperiencePreferencesStore(directoryURL: directory)
        let result = try await reopened.load()
        XCTAssertEqual(result.preferences, original)
    }

    func testSaveOverCorruptCanonicalPreservesItBeforeWritingRequestedState() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)
        let corrupt = Data("corrupt-before-explicit-save".utf8)
        try corrupt.write(to: store.preferencesFileURL, options: .atomic)
        let requested = ExperiencePreferences(soundscapeEnabled: false)

        try await store.save(requested)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.preferences, requested)
        let preserved = try FileManager.default.contentsOfDirectory(
            at: store.preservedFilesDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(preserved.first)), corrupt)
    }

    func testPreservationFailureNeverReplacesCorruptCanonicalFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(
            directoryURL: directory,
            writer: SelectiveFailingWriter(failure: .preserved)
        )
        let corrupt = Data("broken-document".utf8)
        try corrupt.write(to: store.preferencesFileURL, options: .atomic)

        do {
            _ = try await store.load()
            XCTFail("Recovery must stop if preservation fails")
        } catch {
            XCTAssertEqual(error as? TestWriteError, .injected)
        }

        XCTAssertEqual(try Data(contentsOf: store.preferencesFileURL), corrupt)
        let preserved = try FileManager.default.contentsOfDirectory(
            at: store.preservedFilesDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(preserved.isEmpty)
    }

    func testDefaultWriteFailureKeepsCorruptionAndItsPreservedCopy() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(
            directoryURL: directory,
            writer: SelectiveFailingWriter(failure: .canonical)
        )
        let corrupt = Data("still-broken".utf8)
        try corrupt.write(to: store.preferencesFileURL, options: .atomic)

        do {
            _ = try await store.load()
            XCTFail("Injected defaults write should fail")
        } catch {
            XCTAssertEqual(error as? TestWriteError, .injected)
        }

        XCTAssertEqual(try Data(contentsOf: store.preferencesFileURL), corrupt)
        let preserved = try FileManager.default.contentsOfDirectory(
            at: store.preservedFilesDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(preserved.first)), corrupt)
    }

    func testPreservationCollisionStopsRecoveryWithoutChangingEitherFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let future = try jsonData(["schemaVersion": 22, "opaque": "future"])
        let firstStore = try ExperiencePreferencesStore(directoryURL: directory)
        try future.write(to: firstStore.preferencesFileURL, options: .atomic)
        let firstResult = try await firstStore.load()
        let protected = try protectedFuture(from: firstResult.origin)
        let collision = Data("different-bytes".utf8)
        try collision.write(to: protected.url, options: .atomic)

        let reopened = try ExperiencePreferencesStore(directoryURL: directory)
        do {
            _ = try await reopened.load()
            XCTFail("Digest path containing other bytes must not be reused")
        } catch {
            XCTAssertEqual(
                error as? ExperiencePreferencesStoreError,
                .preservationCollision(protected.url)
            )
        }

        XCTAssertEqual(try Data(contentsOf: reopened.preferencesFileURL), future)
        XCTAssertEqual(try Data(contentsOf: protected.url), collision)
    }

    func testConcurrentSavesRemainACompleteDecodableDocument() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ExperiencePreferencesStore(directoryURL: directory)
        let candidates = (0 ..< 48).map { index in
            ExperiencePreferences(
                narrationEnabled: index.isMultiple(of: 2),
                scoreEnabled: index.isMultiple(of: 3),
                soundscapeEnabled: index.isMultiple(of: 5),
                hapticsEnabled: index.isMultiple(of: 7),
                cellularDownloadsEnabled: index.isMultiple(of: 11),
                automaticDeepDiveDownloadsEnabled: index.isMultiple(of: 13)
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for candidate in candidates {
                group.addTask {
                    try await store.save(candidate)
                }
            }
            try await group.waitForAll()
        }

        let decoded = try JSONDecoder().decode(
            ExperiencePreferences.self,
            from: Data(contentsOf: store.preferencesFileURL)
        )
        XCTAssertTrue(candidates.contains(decoded))
        XCTAssertNoThrow(try decoded.validate())
        XCTAssertEqual(decoded.narrationPlaybackPolicy, .explicitUserActionOnly)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "experience-preferences-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func currentDocument(
        schemaVersion: Int,
        narrationPlaybackPolicy: String = "explicitUserActionOnly"
    ) throws -> Data {
        try jsonData([
            "schemaVersion": schemaVersion,
            "narrationEnabled": true,
            "narrationPlaybackPolicy": narrationPlaybackPolicy,
            "scoreEnabled": true,
            "soundscapeEnabled": true,
            "hapticsEnabled": true,
            "cellularDownloadsEnabled": false,
            "automaticDeepDiveDownloadsEnabled": false,
        ])
    }

    private func recoveredURL(from origin: ExperiencePreferencesLoadOrigin) throws -> URL {
        guard case let .recoveredFromCorruptFile(url) = origin else {
            throw TestExpectationError.unexpectedOrigin
        }
        return url
    }

    private func protectedFuture(
        from origin: ExperiencePreferencesLoadOrigin
    ) throws -> (version: Int, url: URL) {
        guard case let .defaultsProtectedFromFutureSchema(version, url) = origin else {
            throw TestExpectationError.unexpectedOrigin
        }
        return (version, url)
    }
}

private enum TestExpectationError: Error {
    case unexpectedOrigin
}

private enum TestWriteError: Error, Equatable {
    case injected
}

private struct SelectiveFailingWriter: ExperiencePreferencesAtomicWriting {
    enum Failure: Equatable, Sendable {
        case canonical
        case preserved
    }

    let failure: Failure

    func writeAtomically(_ data: Data, to url: URL) throws {
        let isPreserved = url.pathComponents.contains("PreservedExperiencePreferences")
        if (failure == .preserved && isPreserved)
            || (failure == .canonical && !isPreserved) {
            throw TestWriteError.injected
        }
        try data.write(to: url, options: .atomic)
    }
}
