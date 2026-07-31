import Foundation
import XCTest
@testable import ImmersiveRuntime

final class Chapter01SensoryBridgeTests: XCTestCase {
    func testPhysicalVocabularyHasBoundedValidPulses() {
        for semantic in Chapter01PhysicalHaptic.allCases {
            let pulses = Chapter01HapticProfile.pulses(for: semantic)
            XCTAssertFalse(pulses.isEmpty)
            XCTAssertLessThanOrEqual(pulses.count, 2)
            for pulse in pulses {
                XCTAssertTrue((0 ... 1).contains(pulse.intensity))
                XCTAssertTrue((0 ... 1).contains(pulse.sharpness))
                XCTAssertGreaterThanOrEqual(pulse.relativeTime, 0)
                XCTAssertLessThanOrEqual(pulse.relativeTime, 0.25)
                switch pulse.kind {
                case .transient:
                    XCTAssertEqual(pulse.duration, 0)
                case .continuous:
                    XCTAssertGreaterThan(pulse.duration, 0)
                    XCTAssertLessThanOrEqual(pulse.duration, 0.25)
                }
            }
        }
    }

    func testCatalogRejectsTraversalDuplicateAndLongCues() throws {
        XCTAssertThrowsError(try Chapter01AuthoredSampleCatalog(bindings: [
            binding(path: "../outside.m4a"),
        ])) { error in
            XCTAssertEqual(
                error as? Chapter01SampleCatalogError,
                .unsafePath("../outside.m4a")
            )
        }

        XCTAssertThrowsError(try Chapter01AuthoredSampleCatalog(bindings: [
            binding(path: "audio/one.m4a"),
            binding(path: "audio/two.m4a"),
        ])) { error in
            guard case .duplicateBinding = error as? Chapter01SampleCatalogError else {
                return XCTFail("Expected duplicate binding, got \(error)")
            }
        }

        XCTAssertThrowsError(try Chapter01AuthoredSampleCatalog(bindings: [
            Chapter01AuthoredSampleBinding(
                sequence: .harvestHadToLast,
                event: .seal,
                packageRelativePath: "audio/long.m4a",
                maximumDuration: 4.1
            ),
        ]))
    }

    @MainActor
    func testBridgeConsumesOneControllerGenerationOnce() throws {
        let programPath = Chapter01PackageAudioProgram.mechanismPath(
            for: .harvestHadToLast
        )
        let fixture = try TemporarySamplePackage(
            extraRelativePaths: [programPath]
        )
        let binding = binding(path: programPath)
        let catalog = try Chapter01AuthoredSampleCatalog(bindings: [binding])
        let resolver = try Chapter01OfflineSampleResolver(
            packageRootURL: fixture.rootURL,
            declaredPaths: fixture.allRelativePaths
        )
        let player = RecordingSamplePlayer()
        let bridge = Chapter01SensoryBridge(
            catalog: catalog,
            resolver: resolver,
            samplePlayer: player
        )

        bridge.consume(
            event: .seal,
            generation: 7,
            sequence: .harvestHadToLast
        )
        bridge.consume(
            event: .seal,
            generation: 7,
            sequence: .harvestHadToLast
        )

        XCTAssertEqual(player.programs.count, 1)
        XCTAssertEqual(
            player.programs.first?.url,
            fixture.rootURL.appendingPathComponent(programPath)
        )
        XCTAssertEqual(player.programs.first?.maximumDuration, 1.25)
        XCTAssertEqual(player.programs.first?.channel, .mechanism)
    }

    func testPackageAudioProgramHasFiveEnvironmentsSixProgramsAndTenLockedNarrations() {
        XCTAssertEqual(
            Set(Chapter01WorldCell.allCases.map {
                Chapter01PackageAudioProgram.environmentPath(for: $0)
            }).count,
            5
        )
        XCTAssertEqual(
            Set(Chapter01Sequence.allCases.map {
                Chapter01PackageAudioProgram.mechanismPath(for: $0)
            }).count,
            6
        )
        XCTAssertEqual(
            Set(Chapter01Sequence.allCases.map {
                Chapter01PackageAudioProgram.transitionPath(for: $0)
            }).count,
            6
        )
        XCTAssertEqual(
            Chapter01PackageAudioProgram.narrationPrograms.map(\.beatID),
            [
                "load-under-tension", "dry-bank-transfer", "three-claims",
                "winter-breach", "spring-return", "route-inland",
                "plot-crowds", "clearing-regrows", "continent-condition",
                "eastern-grass",
            ]
        )
        XCTAssertEqual(
            Chapter01PackageAudioProgram.narrationPrograms
                .map(\.durationSampleFrames),
            [528_000, 336_000, 480_000, 480_000, 288_000,
             576_000, 672_000, 528_000, 336_000, 432_000]
        )
    }

    @MainActor
    func testBridgeRejectsADeclaredCueThatDivergesFromV2ProgramAuthority() throws {
        let fixture = try TemporarySamplePackage()
        let catalog = try Chapter01AuthoredSampleCatalog(bindings: [
            binding(path: fixture.relativePath),
        ])
        let resolver = try Chapter01OfflineSampleResolver(
            packageRootURL: fixture.rootURL,
            declaredPaths: fixture.allRelativePaths
        )
        let player = RecordingSamplePlayer()
        let bridge = Chapter01SensoryBridge(
            catalog: catalog,
            resolver: resolver,
            samplePlayer: player
        )

        bridge.consume(
            event: .seal,
            generation: 1,
            sequence: .harvestHadToLast
        )

        XCTAssertTrue(player.programs.isEmpty)
    }

    @MainActor
    func testEnvironmentAndNarrationRestoreFromDurableFrameWithoutReplay() throws {
        let environment = Chapter01PackageAudioProgram.environmentPath(
            for: .aegeanPassage
        )
        let narration = try XCTUnwrap(
            Chapter01PackageAudioProgram.narration(
                forBeatID: "load-under-tension"
            )
        )
        let fixture = try TemporarySamplePackage(
            extraRelativePaths: [environment, narration.packageRelativePath]
        )
        let resolver = try Chapter01OfflineSampleResolver(
            packageRootURL: fixture.rootURL,
            declaredPaths: fixture.allRelativePaths
        )
        let player = RecordingSamplePlayer()
        let bridge = Chapter01SensoryBridge(
            resolver: resolver,
            samplePlayer: player,
            narrationClockIsAutomatic: false
        )
        var checkpoints: [(String, Int64)] = []

        bridge.synchronizeExperience(
            cell: .aegeanPassage,
            beatID: narration.beatID,
            narrationSampleCursor: 96_000,
            preciseInputIsActive: false
        ) { checkpoints.append(($0, $1)) }

        XCTAssertEqual(player.loops.map(\.url.lastPathComponent), ["environment-01.m4a"])
        XCTAssertEqual(player.narrations.count, 1)
        XCTAssertEqual(player.narrations[0].startSampleFrame, 96_000)
        XCTAssertEqual(player.narrations[0].sampleRate, 48_000)
        bridge.advanceNarrationClock(sampleFrames: 12_000)
        XCTAssertEqual(checkpoints.last?.0, narration.beatID)
        XCTAssertEqual(checkpoints.last?.1, 108_000)

        bridge.synchronizeExperience(
            cell: .aegeanPassage,
            beatID: narration.beatID,
            narrationSampleCursor: 108_000,
            preciseInputIsActive: false
        ) { checkpoints.append(($0, $1)) }
        XCTAssertEqual(player.loops.count, 1)
        XCTAssertEqual(player.narrations.count, 1)
    }

    @MainActor
    func testNarrationWaitsForPreciseInputReleaseAndResumesAfterSuspension() throws {
        let environment = Chapter01PackageAudioProgram.environmentPath(
            for: .thessalianHousehold
        )
        let narration = try XCTUnwrap(
            Chapter01PackageAudioProgram.narration(forBeatID: "three-claims")
        )
        let fixture = try TemporarySamplePackage(
            extraRelativePaths: [environment, narration.packageRelativePath]
        )
        let resolver = try Chapter01OfflineSampleResolver(
            packageRootURL: fixture.rootURL,
            declaredPaths: fixture.allRelativePaths
        )
        let player = RecordingSamplePlayer()
        let bridge = Chapter01SensoryBridge(
            resolver: resolver,
            samplePlayer: player,
            narrationClockIsAutomatic: false
        )
        var checkpoint: Int64 = 24_000

        bridge.synchronizeExperience(
            cell: .thessalianHousehold,
            beatID: narration.beatID,
            narrationSampleCursor: checkpoint,
            preciseInputIsActive: true
        ) { _, sample in checkpoint = sample }
        XCTAssertTrue(player.narrations.isEmpty)

        bridge.synchronizeExperience(
            cell: .thessalianHousehold,
            beatID: narration.beatID,
            narrationSampleCursor: checkpoint,
            preciseInputIsActive: false
        ) { _, sample in checkpoint = sample }
        XCTAssertEqual(player.narrations.map(\.startSampleFrame), [24_000])

        bridge.advanceNarrationClock(sampleFrames: 12_000)
        bridge.quiesceForSuspension()
        XCTAssertEqual(checkpoint, 36_000)
        bridge.resumeAfterSuspension()
        XCTAssertEqual(player.narrations.map(\.startSampleFrame), [24_000, 36_000])
        XCTAssertEqual(player.loops.count, 2)
    }

    @MainActor
    func testCompletedNarrationDoesNotReplay() throws {
        let narration = try XCTUnwrap(
            Chapter01PackageAudioProgram.narration(forBeatID: "eastern-grass")
        )
        let environment = Chapter01PackageAudioProgram.environmentPath(
            for: .settlementLandscape
        )
        let fixture = try TemporarySamplePackage(
            extraRelativePaths: [environment, narration.packageRelativePath]
        )
        let resolver = try Chapter01OfflineSampleResolver(
            packageRootURL: fixture.rootURL,
            declaredPaths: fixture.allRelativePaths
        )
        let player = RecordingSamplePlayer()
        let bridge = Chapter01SensoryBridge(
            resolver: resolver,
            samplePlayer: player,
            narrationClockIsAutomatic: false
        )

        bridge.synchronizeExperience(
            cell: .settlementLandscape,
            beatID: narration.beatID,
            narrationSampleCursor: narration.durationSampleFrames,
            preciseInputIsActive: false
        ) { _, _ in }
        bridge.quiesceForSuspension()
        bridge.resumeAfterSuspension()

        XCTAssertTrue(player.narrations.isEmpty)
    }

    func testResolverAdmitsOnlyDeclaredFilesInsidePackage() throws {
        let fixture = try TemporarySamplePackage()
        let resolver = try Chapter01OfflineSampleResolver(
            packageRootURL: fixture.rootURL,
            declaredPaths: [fixture.relativePath]
        )

        XCTAssertEqual(try resolver.url(for: fixture.relativePath), fixture.fileURL)
        XCTAssertThrowsError(try resolver.url(for: "audio/not-declared.m4a")) { error in
            XCTAssertEqual(
                error as? Chapter01OfflineSampleResolutionError,
                .undeclaredPath("audio/not-declared.m4a")
            )
        }
    }

    private func binding(path: String) -> Chapter01AuthoredSampleBinding {
        Chapter01AuthoredSampleBinding(
            sequence: .harvestHadToLast,
            event: .seal,
            packageRelativePath: path,
            gain: 0.7,
            maximumDuration: 1.25
        )
    }
}

@MainActor
private final class RecordingSamplePlayer: Chapter01AuthoredSamplePlaying {
    struct Play: Equatable {
        let url: URL
        let gain: Float
        let maximumDuration: TimeInterval
    }

    struct Program: Equatable {
        let url: URL
        let gain: Float
        let maximumDuration: TimeInterval
        let channel: Chapter01AuthoredAudioChannel
    }

    struct Loop: Equatable {
        let url: URL
        let gain: Float
        let channel: Chapter01AuthoredAudioChannel
    }

    struct Narration: Equatable {
        let url: URL
        let gain: Float
        let startSampleFrame: Int64
        let sampleRate: Int
        let channel: Chapter01AuthoredAudioChannel
    }

    private(set) var plays: [Play] = []
    private(set) var programs: [Program] = []
    private(set) var loops: [Loop] = []
    private(set) var narrations: [Narration] = []
    private(set) var stoppedChannels: [Chapter01AuthoredAudioChannel] = []
    private(set) var stopAllCount = 0

    func play(url: URL, gain: Float, maximumDuration: TimeInterval) throws {
        plays.append(Play(url: url, gain: gain, maximumDuration: maximumDuration))
    }

    func playProgram(
        url: URL,
        gain: Float,
        maximumDuration: TimeInterval,
        channel: Chapter01AuthoredAudioChannel
    ) throws {
        programs.append(Program(
            url: url,
            gain: gain,
            maximumDuration: maximumDuration,
            channel: channel
        ))
    }

    func playLoop(
        url: URL,
        gain: Float,
        channel: Chapter01AuthoredAudioChannel
    ) throws {
        loops.append(Loop(url: url, gain: gain, channel: channel))
    }

    func playNarration(
        url: URL,
        gain: Float,
        startSampleFrame: Int64,
        sampleRate: Int,
        channel: Chapter01AuthoredAudioChannel
    ) throws {
        narrations.append(Narration(
            url: url,
            gain: gain,
            startSampleFrame: startSampleFrame,
            sampleRate: sampleRate,
            channel: channel
        ))
    }

    func stop(channel: Chapter01AuthoredAudioChannel) {
        stoppedChannels.append(channel)
    }

    func stopAll() { stopAllCount += 1 }
}

private final class TemporarySamplePackage {
    let rootURL: URL
    let relativePath = "audio/cues/seal.m4a"
    let fileURL: URL
    let allRelativePaths: Set<String>

    init(extraRelativePaths: Set<String> = []) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter01-sensory-tests-\(UUID().uuidString)")
        fileURL = rootURL.appendingPathComponent(relativePath)
        allRelativePaths = extraRelativePaths.union([relativePath])
        for path in allRelativePaths {
            let url = rootURL.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([0x00]).write(to: url)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
