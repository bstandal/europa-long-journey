import Foundation
@testable import QualityInstrumentation
import XCTest

final class QualityInstrumentationTests: XCTestCase {
    private let digestA = String(repeating: "a", count: 64)
    private let digestB = String(repeating: "b", count: 64)

    func testSimulatorCaptureIsCanonicalAndAlwaysNonDevice() throws {
        let clock = TestClock(now: 1_000_000_000)
        let recorder = try makeRecorder(clock: clock)
        recorder.bindPackage(packageID: "essential-launch-v1", manifestSHA256: digestB)
        recorder.recordFirstActionReady()

        clock.now = 1_005_000_000
        let action = try XCTUnwrap(
            recorder.beginAction(source: .voiceOver, actionName: "semantic-increment")
        )
        clock.now = 1_010_000_000
        let first = try XCTUnwrap(
            recorder.beginFrame(
                sceneID: "harvest-scene",
                completionProxyActions: [action],
                marksRestoredFrameCompletionProxy: true
            )
        )
        clock.now = 1_020_000_000
        let second = try XCTUnwrap(
            recorder.beginFrame(
                sceneID: "harvest-scene",
                completionProxyActions: [],
                marksRestoredFrameCompletionProxy: false
            )
        )

        // Scheduling callbacks may interleave across frames, but each frame's
        // completed callback must follow its own scheduled callback.
        clock.now = 1_025_000_000
        recorder.recordFrameCommandBufferScheduled(second)
        clock.now = 1_026_000_000
        recorder.recordFrameCommandBufferScheduled(first)
        clock.now = 1_030_000_000
        recorder.recordFrameCommandBufferCompleted(
            first,
            gpuStartTimeSeconds: 1.015,
            gpuEndTimeSeconds: 1.025
        )
        clock.now = 1_040_000_000
        recorder.recordFrameCommandBufferCompleted(
            second,
            gpuStartTimeSeconds: 1.025,
            gpuEndTimeSeconds: 1.035
        )
        recorder.recordAudioCursor(
            timelineID: "harvest-timeline",
            sampleRate: 48_000,
            cursorSample: 96_000,
            kind: .controlledPause
        )

        let report = recorder.makeReport(appBuildSHA256: digestA)
        XCTAssertEqual(report.gateClassification, .nonDevice)
        XCTAssertEqual(
            report.localTimingScope,
            .commandBufferAndGPUCompletionProxyOnly
        )
        XCTAssertEqual(report.platform.captureClass, .nonDevice)
        XCTAssertEqual(report.captureEndedNanosecondsSinceProcessStart, 40_000_000)
        XCTAssertEqual(
            report.frameCommandBufferCompletionProxies.map(\.frameID),
            [first.rawValue, second.rawValue]
        )
        let firstFrame = report.frameCommandBufferCompletionProxies[0]
        let secondFrame = report.frameCommandBufferCompletionProxies[1]
        XCTAssertEqual(
            firstFrame.commandBufferCommitRequestedNanosecondsSinceProcessStart,
            10_000_000
        )
        XCTAssertEqual(
            firstFrame.commandBufferScheduledCallbackNanosecondsSinceProcessStart,
            26_000_000
        )
        XCTAssertEqual(
            firstFrame.commandBufferCompletedCallbackNanosecondsSinceProcessStart,
            30_000_000
        )
        XCTAssertEqual(
            firstFrame.commitRequestToScheduledCallbackNanoseconds,
            16_000_000
        )
        XCTAssertEqual(
            firstFrame.commitRequestToCompletedCallbackNanoseconds,
            20_000_000
        )
        XCTAssertEqual(firstFrame.gpuExecutionNanoseconds, 10_000_000)
        XCTAssertNil(
            firstFrame.previousCommandBufferCompletionCallbackIntervalNanoseconds
        )
        XCTAssertEqual(
            secondFrame.previousCommandBufferCompletionCallbackIntervalNanoseconds,
            10_000_000
        )
        XCTAssertEqual(
            report.interactionCommandBufferCompletionProxies.single?.source,
            .voiceOver
        )
        XCTAssertEqual(
            report.interactionCommandBufferCompletionProxies.single?
                .actionToCommandBufferCompletedCallbackNanoseconds,
            25_000_000
        )
        XCTAssertEqual(
            report.launch
                .restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart,
            30_000_000
        )
        XCTAssertNoThrow(try PerformanceCaptureValidator.validate(report))

        let firstEncoding = try PerformanceReportCodec.encodeCanonical(report)
        let secondEncoding = try PerformanceReportCodec.encodeCanonical(report)
        XCTAssertEqual(firstEncoding, secondEncoding)
        XCTAssertEqual(
            try PerformanceReportCodec.decodeAndValidate(firstEncoding),
            report
        )
        let encodedText = try XCTUnwrap(String(data: firstEncoding, encoding: .utf8))
            .lowercased()
        XCTAssertFalse(encodedText.contains("visible"))
        XCTAssertFalse(encodedText.contains("presented"))
        XCTAssertFalse(encodedText.contains("\"gateclassification\" : \"pass\""))
    }

    func testCompletedCallbackBeforeScheduledCallbackFailsClosed() throws {
        let clock = TestClock(now: 1_500_000_000)
        let recorder = try makeRecorder(clock: clock)
        recorder.bindPackage(packageID: "essential-launch-v1", manifestSHA256: digestB)
        clock.now = 1_505_000_000
        let action = try XCTUnwrap(
            recorder.beginAction(source: .touch, actionName: "allocate-grain")
        )
        clock.now = 1_510_000_000
        let frame = try XCTUnwrap(
            recorder.beginFrame(
                sceneID: "harvest-scene",
                completionProxyActions: [action],
                marksRestoredFrameCompletionProxy: false
            )
        )

        clock.now = 1_520_000_000
        recorder.recordFrameCommandBufferCompleted(
            frame,
            gpuStartTimeSeconds: 1.511,
            gpuEndTimeSeconds: 1.519
        )
        clock.now = 1_530_000_000
        recorder.recordFrameCommandBufferScheduled(frame)

        let report = recorder.makeReport(appBuildSHA256: digestA)
        XCTAssertTrue(report.frameCommandBufferCompletionProxies.isEmpty)
        XCTAssertTrue(report.interactionCommandBufferCompletionProxies.isEmpty)
        XCTAssertEqual(
            report.instrumentationFailures.map(\.code),
            [.commandBufferCallbackOrderViolation]
        )
    }

    func testRepeatedReportGenerationDoesNotAppendUnresolvedFailures() throws {
        let recorder = try makeRecorder(clock: TestClock(now: 2_000_000_000))
        recorder.bindPackage(packageID: "essential-launch-v1", manifestSHA256: digestB)
        _ = recorder.beginAction(source: .touch, actionName: "trace")
        _ = recorder.beginFrame(
            sceneID: "harvest-scene",
            completionProxyActions: [],
            marksRestoredFrameCompletionProxy: false
        )

        let first = recorder.makeReport(appBuildSHA256: digestA)
        let second = recorder.makeReport(appBuildSHA256: digestA)
        XCTAssertEqual(first.instrumentationFailures, second.instrumentationFailures)
        XCTAssertEqual(
            first.instrumentationFailures.map(\.code),
            [.unresolvedCommandBufferFrame, .unresolvedInteractionCompletionProxy]
        )
    }

    func testPhysicalDebugCaptureCannotMasqueradeAsDeviceEvidence() throws {
        let clock = TestClock(now: 3_000_000_000)
        let recorder = try LocalPerformanceRecorder(
            request: request,
            platform: PerformancePlatformIdentity(
                captureClass: .physicalDevice,
                hardwareModel: "iPhone17,1",
                operatingSystem: "iOS 26.4",
                buildConfiguration: .debug
            ),
            clock: clock,
            footprintSampler: TestFootprintSampler(bytes: 128 * 1_024 * 1_024),
            maximumRecordedEvents: 100,
            footprintFrameCadence: 2,
            startsThermalMonitoring: false
        )
        recorder.bindPackage(packageID: "essential-launch-v1", manifestSHA256: digestB)
        let report = recorder.makeReport(appBuildSHA256: digestA)
        XCTAssertEqual(report.gateClassification, .deviceRawMeasurementsOnly)
        XCTAssertThrowsError(try PerformanceCaptureValidator.validate(report))
    }

    func testAudioCheckpointFailsClosedOutsideAuthored48kHz() throws {
        let recorder = try makeRecorder(clock: TestClock(now: 4_000_000_000))
        recorder.bindPackage(packageID: "essential-launch-v1", manifestSHA256: digestB)
        recorder.recordAudioCursor(
            timelineID: "harvest-timeline",
            sampleRate: 44_100,
            cursorSample: 12,
            kind: .snapshot
        )
        let report = recorder.makeReport(appBuildSHA256: digestA)
        XCTAssertTrue(report.audioCursorCheckpoints.isEmpty)
        XCTAssertEqual(report.instrumentationFailures.last?.code, .invalidAudioCheckpoint)
    }

    func testStrictCaptureRequestRejectsUnknownFields() throws {
        let valid = Data(
            #"{"schemaVersion":1,"protocolID":"port1-physical-device-v1","runID":"cold-restore","attemptID":"cold-restore-r01","repetition":1,"rawTraceRetentionRequired":true}"#.utf8
        )
        XCTAssertNoThrow(try PerformanceCaptureRequestCodec.decodeStrict(valid))
        let unknown = Data(
            #"{"schemaVersion":1,"protocolID":"port1-physical-device-v1","runID":"cold-restore","attemptID":"cold-restore-r01","repetition":1,"rawTraceRetentionRequired":true,"claimsPass":true}"#.utf8
        )
        XCTAssertThrowsError(try PerformanceCaptureRequestCodec.decodeStrict(unknown))
    }

    func testReportCodecRejectsUnknownNestedFields() throws {
        let clock = TestClock(now: 4_500_000_000)
        let recorder = try makeRecorder(clock: clock)
        recorder.bindPackage(packageID: "essential-launch-v1", manifestSHA256: digestB)
        clock.now = 4_500_000_001
        let bytes = try PerformanceReportCodec.encodeCanonical(
            recorder.makeReport(appBuildSHA256: digestA)
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        var platform = try XCTUnwrap(object["platform"] as? [String: Any])
        platform["deviceGatePassed"] = true
        object["platform"] = platform
        let drifted = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try PerformanceReportCodec.decodeAndValidate(drifted))
    }

    func testExporterWritesHashBoundDeterministicBackstageFiles() throws {
        let clock = TestClock(now: 5_000_000_000)
        let recorder = try makeRecorder(clock: clock)
        recorder.bindPackage(packageID: "essential-launch-v1", manifestSHA256: digestB)
        clock.now = 5_000_000_001
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quality-instrumentation-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let appBundle = root.appendingPathComponent("LongWestJourney.app", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)
        try Data("signed-app-bytes".utf8).write(
            to: appBundle.appendingPathComponent("LongWestJourney")
        )

        let receipt = try PerformanceReportExporter.export(
            recorder: recorder,
            appBundleURL: appBundle,
            reportDirectory: root,
            hasher: TestAppBuildHasher(digest: digestA)
        )
        XCTAssertEqual(receipt.gateClassification, .nonDevice)
        XCTAssertTrue(PerformanceCaptureValidator.isLowercaseSHA256(receipt.reportSHA256))
        let reportData = try Data(
            contentsOf: root.appendingPathComponent(receipt.reportFileName)
        )
        let report = try PerformanceReportCodec.decodeAndValidate(reportData)
        XCTAssertEqual(report.appBuildSHA256, digestA)
        XCTAssertEqual(report.packages.single?.manifestSHA256, digestB)
    }

    func testCanonicalAppBundleHashCoversEveryNestedBuildByte() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "app-build-hash-\(UUID().uuidString).app",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let framework = root.appendingPathComponent("Frameworks", isDirectory: true)
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try Data("executable-v1".utf8).write(to: root.appendingPathComponent("LongWestJourney"))
        let nested = framework.appendingPathComponent("SceneRuntime.framework")
        try Data("framework-v1".utf8).write(to: nested)

        let hasher = CanonicalAppBundleHasher()
        let first = try hasher.sha256(ofAppBundleAt: root)
        let repeated = try hasher.sha256(ofAppBundleAt: root)
        XCTAssertEqual(first, repeated)
        XCTAssertTrue(PerformanceCaptureValidator.isLowercaseSHA256(first))

        try Data("framework-v2".utf8).write(to: nested, options: .atomic)
        let changed = try hasher.sha256(ofAppBundleAt: root)
        XCTAssertNotEqual(first, changed)
    }

    func testCompleteFirstFarmersPhysicalRunIsAnAcceptedCaptureIdentity() {
        let chapterRun = PerformanceCaptureRequest(
            protocolID: "port1-physical-device-v1",
            runID: "first-farmers-sustained",
            attemptID: "first-farmers-sustained-r01",
            repetition: 1,
            rawTraceRetentionRequired: true
        )

        XCTAssertNoThrow(try PerformanceCaptureValidator.validate(chapterRun))
    }

    private var request: PerformanceCaptureRequest {
        PerformanceCaptureRequest(
            protocolID: "port1-physical-device-v1",
            runID: "interaction-latency",
            attemptID: "interaction-latency-r01",
            repetition: 1,
            rawTraceRetentionRequired: true
        )
    }

    private func makeRecorder(clock: TestClock) throws -> LocalPerformanceRecorder {
        try LocalPerformanceRecorder(
            request: request,
            platform: PerformancePlatformIdentity(
                captureClass: .nonDevice,
                hardwareModel: "arm64-simulator",
                operatingSystem: "iOS Simulator 26.4",
                buildConfiguration: .debug
            ),
            clock: clock,
            footprintSampler: TestFootprintSampler(bytes: 128 * 1_024 * 1_024),
            maximumRecordedEvents: 100,
            footprintFrameCadence: 2,
            startsThermalMonitoring: false
        )
    }
}

private final class TestClock: PerformanceMonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: UInt64

    init(now: UInt64) {
        storage = now
    }

    var now: UInt64 {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    func nowNanosecondsSinceBoot() -> UInt64 { now }
}

private struct TestFootprintSampler: PhysicalFootprintSampling {
    let bytes: UInt64
    func physicalFootprintBytes() -> UInt64? { bytes }
}

private struct TestAppBuildHasher: AppBuildHashing {
    let digest: String
    func sha256(ofAppBundleAt _: URL) throws -> String { digest }
}

private extension Array {
    var single: Element? { count == 1 ? self[0] : nil }
}
