import CryptoKit
@testable import ContentKit
@testable import DramaticAudio
import Foundation
import XCTest

final class ManifestBoundAudioAssetResolverTests: XCTestCase {
    func testResolverInitializationDefersAudioBytesAndFirstUseRejectsTampering() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var tampered = fixture.authoredBytes
        tampered[tampered.startIndex] ^= 0xFF
        try tampered.write(to: fixture.audioURL, options: .atomic)

        // Construction binds the verifier-created manifest and timeline only;
        // it deliberately does not hash a large audio master at cold launch.
        let resolver = try ManifestBoundAudioAssetResolver(
            verifiedPackage: fixture.verifiedPackage,
            activatedPackageRoot: fixture.root
        )

        XCTAssertThrowsError(try resolver.url(for: fixture.audioPath)) { error in
            XCTAssertEqual(
                error as? OfflineAudioAssetResolutionError,
                .manifestDigestMismatch(fixture.audioPath)
            )
        }
    }

    func testRepeatedSliceResolutionHashesUnchangedAudioOnlyOnce() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let resolver = try ManifestBoundAudioAssetResolver(
            verifiedPackage: fixture.verifiedPackage,
            activatedPackageRoot: fixture.root
        )

        XCTAssertEqual(
            try resolver.url(for: fixture.audioPath),
            fixture.audioURL.resolvingSymlinksInPath().standardizedFileURL
        )
        _ = try resolver.url(for: fixture.audioPath)
        _ = try resolver.url(for: fixture.audioPath)
        XCTAssertEqual(resolver.fullHashCountForTesting(fixture.audioPath), 1)

        XCTAssertThrowsError(try resolver.url(for: "audio/not-authored.caf")) { error in
            XCTAssertEqual(
                error as? OfflineAudioAssetResolutionError,
                .assetNotDeclaredByAudioTimeline("audio/not-authored.caf")
            )
        }
    }

    func testDetachedPrewarmCompletesBeforeTransportLookupAndAvoidsMainActorRehash() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let resolver = try ManifestBoundAudioAssetResolver(
            verifiedPackage: fixture.verifiedPackage,
            activatedPackageRoot: fixture.root
        )

        try await OfflineAudioAssetPrewarmer.prewarm(
            paths: [fixture.audioPath, fixture.audioPath],
            resolver: resolver
        )
        XCTAssertEqual(resolver.fullHashCountForTesting(fixture.audioPath), 1)

        // ResponsiveAudioProgramController/NativeTimelineTransport performs
        // this lookup on the main actor only after prewarm has returned.
        _ = try resolver.url(for: fixture.audioPath)
        XCTAssertEqual(resolver.fullHashCountForTesting(fixture.audioPath), 1)
    }

    func testCancelledStalePrewarmNeverReachesItsBindingPoint() async throws {
        let staleResolver = CancellationBlockingAudioResolver()
        let recorder = AudioBindingRecorder()
        let stale = Task {
            try await OfflineAudioAssetPrewarmer.prewarm(
                paths: ["audio/stale.caf"],
                resolver: staleResolver
            )
            await recorder.record("stale")
        }
        XCTAssertEqual(
            staleResolver.entered.wait(timeout: .now() + 2),
            .success
        )

        stale.cancel()
        do {
            try await stale.value
            XCTFail("A replaced prewarm must not reach its binding point")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        try await OfflineAudioAssetPrewarmer.prewarm(
            paths: ["audio/current.caf"],
            resolver: ImmediateAudioResolver()
        )
        await recorder.record("current")
        let bindings = await recorder.values()
        XCTAssertEqual(bindings, ["current"])
    }

    func testSameSizeReplacementWithChangedIdentityForcesFreshHashAndFails() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let resolver = try ManifestBoundAudioAssetResolver(
            verifiedPackage: fixture.verifiedPackage,
            activatedPackageRoot: fixture.root
        )
        _ = try resolver.url(for: fixture.audioPath)
        XCTAssertEqual(resolver.fullHashCountForTesting(fixture.audioPath), 1)

        var replacement = fixture.authoredBytes
        replacement[replacement.startIndex] ^= 0xFF
        try replacement.write(to: fixture.audioURL, options: .atomic)

        XCTAssertThrowsError(try resolver.url(for: fixture.audioPath)) { error in
            XCTAssertEqual(
                error as? OfflineAudioAssetResolutionError,
                .manifestDigestMismatch(fixture.audioPath)
            )
        }
        XCTAssertEqual(resolver.fullHashCountForTesting(fixture.audioPath), 2)
    }

    private struct Fixture {
        let root: URL
        let audioURL: URL
        let audioPath: String
        let authoredBytes: Data
        let verifiedPackage: VerifiedContentPackage
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "manifest-bound-audio-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let audioPath = "audio/authored-master.caf"
        let audioURL = root.appending(path: audioPath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: audioURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let authoredBytes = Data(repeating: 0x4D, count: 2 * 1_048_576)
        try authoredBytes.write(to: audioURL)

        let version = SchemaVersion(major: 1)
        let packageID: PackageID = "audio-runtime-test"
        let manifest = SignedPackageManifest(
            packageID: packageID,
            packageVersion: version,
            schemaVersion: version,
            minimumRuntime: version,
            files: [
                PackageFileRecord(
                    path: audioPath,
                    bytes: Int64(authoredBytes.count),
                    sha256: SHA256.hash(data: authoredBytes)
                        .map { String(format: "%02x", $0) }
                        .joined()
                ),
            ],
            manifestDigest: String(repeating: "a", count: 64),
            signature: PackageSignature(
                algorithm: ContentPackageVerifier.signatureAlgorithm,
                keyID: "test-key",
                value: "AA=="
            )
        )
        let timeline = AudioTimeline(
            id: "authored-audio",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "soundscape",
                    role: .soundscape,
                    startSample: 0,
                    durationSamples: 48_000,
                    assetPath: audioPath,
                    gain: 1
                ),
            ],
            haptics: []
        )
        let payload = ContentPackagePayload(
            schemaVersion: version,
            packageID: packageID,
            worldSeed: WorldSeedSpec(nodes: [], traces: []),
            chapters: [],
            scenes: [],
            audioTimelines: [timeline],
            accessibility: []
        )
        return Fixture(
            root: root,
            audioURL: audioURL,
            audioPath: audioPath,
            authoredBytes: authoredBytes,
            verifiedPackage: VerifiedContentPackage(
                manifest: manifest,
                payload: payload,
                verificationScope: .runtimeAdmission
            )
        )
    }
}

private final class CancellationBlockingAudioResolver: @unchecked Sendable,
    OfflineAudioAssetResolving
{
    let entered = DispatchSemaphore(value: 0)

    func url(for packageRelativePath: String) throws -> URL {
        entered.signal()
        while true {
            try Task.checkCancellation()
            Thread.sleep(forTimeInterval: 0.001)
        }
    }
}

private struct ImmediateAudioResolver: OfflineAudioAssetResolving {
    func url(for packageRelativePath: String) throws -> URL {
        URL(fileURLWithPath: "/tmp").appending(path: packageRelativePath)
    }
}

private actor AudioBindingRecorder {
    private var recorded: [String] = []

    func record(_ value: String) {
        recorded.append(value)
    }

    func values() -> [String] { recorded }
}
