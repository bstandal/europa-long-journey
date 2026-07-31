import AVFAudio
import AudioToolbox
@testable import DramaticAudio
import Foundation
import XCTest

final class NativeAudioDurabilityGateTests: XCTestCase {
    func testFortyEightKilohertzBindingHasTwelveThousandSampleBudget()
        throws {
        let gate = NativeAudioDurabilityGate()
        let token = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 0
        )
        let binding = try ActiveAudioCursorBinding(
            renderedGraphSampleRate: 48_000,
            feed: ActiveAudioCursorFeed { throw UnusedCaptureError() },
            gate: token
        )

        XCTAssertEqual(binding.maximumUndurableGraphSampleCount, 12_000)
        XCTAssertEqual(
            ActiveAudioCursorBinding.maximumUndurableDurationNanoseconds,
            250_000_000
        )
    }

    func testExactBoundaryLatchesAndRejectsLateCaptureAndAuthorization()
        throws {
        let gate = NativeAudioDurabilityGate()
        let token = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 16
        )

        XCTAssertEqual(
            gate.audibleFrameCount(
                fromRenderedGraphSample: 0,
                frameCount: 16
            ),
            16
        )
        XCTAssertFalse(token.claimCapture(atRenderedGraphSample: 16))
        XCTAssertFalse(token.authorizeAudio(throughRenderedGraphSample: 32))
        XCTAssertTrue(token.transportWillStop())
        XCTAssertTrue(token.transportDidStop())
    }

    func testRenderAuthorizeCASRaceHasOnlyLegalOutcomes() throws {
        let queue = DispatchQueue(
            label: "native-audio-durability-gate-race",
            attributes: .concurrent
        )
        for _ in 0 ..< 200 {
            let gate = NativeAudioDurabilityGate()
            let token = try gate.resetWhileTransportStopped(
                atRenderedGraphSample: 100
            )
            let start = DispatchSemaphore(value: 0)
            let done = DispatchGroup()
            let result = GateRaceResult()

            done.enter()
            queue.async {
                start.wait()
                result.setAuthorization(
                    token.authorizeAudio(throughRenderedGraphSample: 200)
                )
                done.leave()
            }
            done.enter()
            queue.async {
                start.wait()
                result.setAudibleFrames(gate.audibleFrameCount(
                    fromRenderedGraphSample: 90,
                    frameCount: 20
                ))
                done.leave()
            }
            start.signal()
            start.signal()
            XCTAssertEqual(done.wait(timeout: .now() + 1), .success)

            let outcome = result.snapshot()
            XCTAssertTrue(
                (outcome.authorization == true
                    && outcome.audibleFrames == 20)
                    || (outcome.authorization == false
                        && outcome.audibleFrames == 10),
                "Illegal CAS outcome: \(outcome)"
            )
        }
    }

    func testOldEpochCannotAuthorizeOrStopRunningSuccessor() throws {
        let gate = NativeAudioDurabilityGate()
        let old = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 100
        )
        XCTAssertEqual(
            gate.audibleFrameCount(
                fromRenderedGraphSample: 0,
                frameCount: 1
            ),
            1
        )
        XCTAssertTrue(old.transportWillStop())
        XCTAssertTrue(old.transportDidStop())

        let current = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 50
        )
        XCTAssertEqual(
            gate.audibleFrameCount(
                fromRenderedGraphSample: 0,
                frameCount: 1
            ),
            1
        )
        XCTAssertFalse(old.authorizeAudio(throughRenderedGraphSample: 1_000))
        XCTAssertFalse(old.claimCapture(atRenderedGraphSample: 0))
        XCTAssertFalse(old.transportDidStop())
        XCTAssertThrowsError(
            try gate.resetWhileTransportStopped(atRenderedGraphSample: 0)
        ) { error in
            XCTAssertEqual(
                error as? NativeAudioDurabilityGate.ResetError,
                .transportIsRunning
            )
        }
        XCTAssertTrue(current.authorizeAudio(throughRenderedGraphSample: 60))
        XCTAssertTrue(current.transportWillStop())
        XCTAssertTrue(current.transportDidStop())
        _ = try gate.resetWhileTransportStopped(atRenderedGraphSample: 0)
    }

    func testStoppedEpochStaysInactiveDuringPreRollUntilNextReset() throws {
        let gate = NativeAudioDurabilityGate()
        let old = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 100
        )
        XCTAssertEqual(
            gate.audibleFrameCount(
                fromRenderedGraphSample: 0,
                frameCount: 1
            ),
            1
        )
        XCTAssertTrue(old.transportWillStop())
        XCTAssertTrue(old.transportDidStop())

        // AVAudioEngine may pull connected units after start but before the
        // transport has calculated the next scheduled graph sample. Those
        // pre-roll pulls must stay silent and must not revive the old epoch.
        XCTAssertEqual(
            gate.audibleFrameCount(
                fromRenderedGraphSample: 101,
                frameCount: 16
            ),
            0
        )
        XCTAssertFalse(old.claimCapture(atRenderedGraphSample: 100))
        XCTAssertFalse(old.authorizeAudio(throughRenderedGraphSample: 200))

        let current = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 300
        )
        XCTAssertGreaterThan(current.epoch, old.epoch)
        XCTAssertEqual(
            gate.audibleFrameCount(
                fromRenderedGraphSample: 250,
                frameCount: 64
            ),
            50
        )
        XCTAssertTrue(current.transportWillStop())
        XCTAssertTrue(current.transportDidStop())
    }

    func testWillStopRejectsWorkerAuthorityWhileRenderKeepsExactPrefix()
        throws {
        let gate = NativeAudioDurabilityGate()
        let token = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 100
        )
        XCTAssertTrue(token.claimCapture(atRenderedGraphSample: 50))
        XCTAssertTrue(token.authorizeAudio(throughRenderedGraphSample: 120))

        XCTAssertTrue(token.transportWillStop())
        XCTAssertFalse(token.claimCapture(atRenderedGraphSample: 60))
        XCTAssertFalse(token.authorizeAudio(throughRenderedGraphSample: 140))
        XCTAssertEqual(
            gate.audibleFrameCount(
                fromRenderedGraphSample: 110,
                frameCount: 20
            ),
            10
        )
        XCTAssertTrue(token.transportDidStop())
    }

    func testTerminalTailSealsWorkerAndKeepsLargerExistingCutoff() throws {
        let gate = NativeAudioDurabilityGate()
        let token = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 100
        )

        // The authored tail finishes inside the initial durability budget.
        // Terminal authorization must succeed without racing an unsafe cutoff
        // contraction against an in-flight render callback.
        XCTAssertTrue(token.authorizeTerminalTail(
            fromRenderedGraphSample: 40,
            throughRenderedGraphSample: 80
        ))
        XCTAssertFalse(token.claimCapture(atRenderedGraphSample: 50))
        XCTAssertFalse(token.authorizeAudio(throughRenderedGraphSample: 200))
        XCTAssertFalse(token.authorizeTerminalTail(
            fromRenderedGraphSample: 50,
            throughRenderedGraphSample: 90
        ))
        XCTAssertEqual(
            gate.audibleFrameCount(
                fromRenderedGraphSample: 90,
                frameCount: 20
            ),
            10
        )
        XCTAssertTrue(token.transportWillStop())
        XCTAssertTrue(token.transportDidStop())
    }

    func testClosedRenderBoundaryRejectsTerminalTailAuthorization() throws {
        let gate = NativeAudioDurabilityGate()
        let token = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 100
        )

        XCTAssertEqual(
            gate.audibleFrameCount(
                fromRenderedGraphSample: 90,
                frameCount: 20
            ),
            10
        )
        XCTAssertFalse(token.authorizeTerminalTail(
            fromRenderedGraphSample: 90,
            throughRenderedGraphSample: 200
        ))
        XCTAssertFalse(token.claimCapture(atRenderedGraphSample: 90))
        XCTAssertFalse(token.authorizeAudio(throughRenderedGraphSample: 200))
        XCTAssertTrue(token.transportWillStop())
        XCTAssertTrue(token.transportDidStop())
    }

#if os(iOS)
    func testSequentialMonoAndStereoBusesKeepSamePartial4096FramePrefix()
        throws {
        let gate = NativeAudioDurabilityGate()
        let token = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 1_000
        )
        let mono = try makeGainNode(
            channelCount: 1,
            initialGain: 1,
            durabilityGate: gate
        )
        let stereo = try makeGainNode(
            channelCount: 2,
            initialGain: 1,
            durabilityGate: gate
        )
        defer {
            mono.audioUnit.deallocateRenderResources()
            stereo.audioUnit.deallocateRenderResources()
        }
        let monoBuffer = try makeBuffer(channelCount: 1, capacity: 4_096)
        let stereoBuffer = try makeBuffer(channelCount: 2, capacity: 4_096)
        let monoPull = PullProbe(value: 1)
        let stereoPull = PullProbe(value: 1)

        let monoResult = invoke(
            mono.audioUnit.internalRenderBlock,
            buffer: monoBuffer,
            frameCount: 4_096,
            startSample: 0,
            pullInputBlock: monoPull.block
        )
        let stereoResult = invoke(
            stereo.audioUnit.internalRenderBlock,
            buffer: stereoBuffer,
            frameCount: 4_096,
            startSample: 0,
            pullInputBlock: stereoPull.block
        )

        XCTAssertEqual(monoResult.status, noErr)
        XCTAssertEqual(stereoResult.status, noErr)
        XCTAssertFalse(monoResult.flags.contains(.unitRenderAction_OutputIsSilence))
        XCTAssertFalse(stereoResult.flags.contains(.unitRenderAction_OutputIsSilence))
        XCTAssertEqual(monoPull.frameCounts, [4_096])
        XCTAssertEqual(stereoPull.frameCounts, [4_096])
        assertPrefix(
            monoBuffer,
            frameCount: 4_096,
            audibleFrames: 1_000,
            audibleValue: 1
        )
        assertPrefix(
            stereoBuffer,
            frameCount: 4_096,
            audibleFrames: 1_000,
            audibleValue: 1
        )

        let silent = invoke(
            mono.audioUnit.internalRenderBlock,
            buffer: monoBuffer,
            frameCount: 16,
            startSample: 1_000,
            pullInputBlock: monoPull.block
        )
        XCTAssertEqual(silent.status, noErr)
        XCTAssertTrue(silent.flags.contains(.unitRenderAction_OutputIsSilence))
        XCTAssertEqual(monoPull.frameCounts, [4_096, 16])
        assertPrefix(
            monoBuffer,
            frameCount: 16,
            audibleFrames: 0,
            audibleValue: 1
        )
        XCTAssertTrue(token.transportWillStop())
        XCTAssertTrue(token.transportDidStop())
    }

    func testCapturedRenderBlockUsesNewEpochWithoutAUReplacement() throws {
        let gate = NativeAudioDurabilityGate()
        let old = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 8
        )
        let gainNode = try makeGainNode(
            channelCount: 1,
            initialGain: 1,
            durabilityGate: gate
        )
        defer { gainNode.audioUnit.deallocateRenderResources() }
        let renderBlock = gainNode.audioUnit.internalRenderBlock
        let buffer = try makeBuffer(channelCount: 1, capacity: 16)
        let pull = PullProbe(value: 1)

        XCTAssertEqual(
            invoke(
                renderBlock,
                buffer: buffer,
                frameCount: 16,
                startSample: 0,
                pullInputBlock: pull.block
            ).status,
            noErr
        )
        assertPrefix(
            buffer,
            frameCount: 16,
            audibleFrames: 8,
            audibleValue: 1
        )
        XCTAssertTrue(old.transportWillStop())
        XCTAssertTrue(old.transportDidStop())

        let current = try gate.resetWhileTransportStopped(
            atRenderedGraphSample: 12
        )
        XCTAssertFalse(old.authorizeAudio(throughRenderedGraphSample: 1_000))
        XCTAssertFalse(old.transportDidStop())
        XCTAssertEqual(
            invoke(
                renderBlock,
                buffer: buffer,
                frameCount: 16,
                startSample: 0,
                pullInputBlock: pull.block
            ).status,
            noErr
        )
        assertPrefix(
            buffer,
            frameCount: 16,
            audibleFrames: 12,
            audibleValue: 1
        )
        XCTAssertEqual(pull.frameCounts, [16, 16])
        XCTAssertTrue(current.transportWillStop())
        XCTAssertTrue(current.transportDidStop())
    }

    func testNilGatePreservesExistingGainBehavior() throws {
        let gainNode = try makeGainNode(
            channelCount: 2,
            initialGain: 0.5,
            durabilityGate: nil
        )
        defer { gainNode.audioUnit.deallocateRenderResources() }
        let buffer = try makeBuffer(channelCount: 2, capacity: 257)
        let pull = PullProbe(value: 0.8)

        let result = invoke(
            gainNode.audioUnit.internalRenderBlock,
            buffer: buffer,
            frameCount: 257,
            startSample: 41,
            pullInputBlock: pull.block
        )

        XCTAssertEqual(result.status, noErr)
        XCTAssertFalse(result.flags.contains(.unitRenderAction_OutputIsSilence))
        XCTAssertEqual(pull.frameCounts, [257])
        assertPrefix(
            buffer,
            frameCount: 257,
            audibleFrames: 257,
            audibleValue: 0.4
        )
    }

    func testAudioUnitRejectsGateConfigurationAfterResourceAllocation()
        throws {
        let gainNode = try makeGainNode(
            channelCount: 1,
            initialGain: 1,
            durabilityGate: nil
        )
        defer { gainNode.audioUnit.deallocateRenderResources() }

        XCTAssertThrowsError(
            try gainNode.audioUnit.configureDurabilityGate(
                NativeAudioDurabilityGate()
            )
        ) { error in
            XCTAssertEqual(
                error as? SampleAccurateGainNodeError,
                .durabilityGateRequiresUnallocatedRenderResources
            )
        }
    }

    private func makeGainNode(
        channelCount: AVAudioChannelCount,
        initialGain: AUValue,
        durabilityGate: NativeAudioDurabilityGate?
    ) throws -> SampleAccurateGainNode {
        let gainNode = try SampleAccurateGainNode.make(
            initialGain: initialGain,
            durabilityGate: durabilityGate
        )
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: channelCount,
            interleaved: false
        ))
        try gainNode.audioUnit.inputBusses[0].setFormat(format)
        try gainNode.audioUnit.outputBusses[0].setFormat(format)
        gainNode.audioUnit.maximumFramesToRender = 4_096
        try gainNode.audioUnit.allocateRenderResources()
        return gainNode
    }

    private func makeBuffer(
        channelCount: AVAudioChannelCount,
        capacity: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: channelCount,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: capacity
        ))
        buffer.frameLength = capacity
        return buffer
    }

    private func invoke(
        _ renderBlock: AUInternalRenderBlock,
        buffer: AVAudioPCMBuffer,
        frameCount: AUAudioFrameCount,
        startSample: AUEventSampleTime,
        pullInputBlock: AURenderPullInputBlock?
    ) -> (status: OSStatus, flags: AudioUnitRenderActionFlags) {
        var timestamp = AudioTimeStamp()
        timestamp.mSampleTime = Double(startSample)
        timestamp.mFlags = .sampleTimeValid
        var flags: AudioUnitRenderActionFlags = []
        let status = withUnsafeMutablePointer(to: &flags) { flagsPointer in
            withUnsafePointer(to: &timestamp) { timestampPointer in
                renderBlock(
                    flagsPointer,
                    timestampPointer,
                    frameCount,
                    0,
                    buffer.mutableAudioBufferList,
                    nil,
                    pullInputBlock
                )
            }
        }
        return (status, flags)
    }

    private func assertPrefix(
        _ buffer: AVAudioPCMBuffer,
        frameCount: Int,
        audibleFrames: Int,
        audibleValue: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let channels = buffer.floatChannelData else {
            XCTFail("Missing float channels", file: file, line: line)
            return
        }
        for channel in 0 ..< Int(buffer.format.channelCount) {
            for frame in 0 ..< frameCount {
                XCTAssertEqual(
                    channels[channel][frame],
                    frame < audibleFrames ? audibleValue : 0,
                    accuracy: 0.000_001,
                    file: file,
                    line: line
                )
            }
        }
    }
#endif
}

private struct UnusedCaptureError: Error {}

private final class GateRaceResult: @unchecked Sendable {
    private let lock = NSLock()
    private var authorization: Bool?
    private var audibleFrames: UInt32?

    func setAuthorization(_ value: Bool) {
        lock.lock()
        authorization = value
        lock.unlock()
    }

    func setAudibleFrames(_ value: UInt32) {
        lock.lock()
        audibleFrames = value
        lock.unlock()
    }

    func snapshot() -> (authorization: Bool?, audibleFrames: UInt32?) {
        lock.lock()
        defer { lock.unlock() }
        return (authorization, audibleFrames)
    }
}

#if os(iOS)
private final class PullProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let value: Float
    private var frames: [AUAudioFrameCount] = []

    init(value: Float) {
        self.value = value
    }

    var frameCounts: [AUAudioFrameCount] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    lazy var block: AURenderPullInputBlock = { [self] _, _, frameCount, _, data in
        lock.lock()
        frames.append(frameCount)
        lock.unlock()
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        for index in buffers.indices {
            guard let samples = buffers[index].mData?
                .assumingMemoryBound(to: Float.self) else {
                return kAudioUnitErr_InvalidPropertyValue
            }
            samples.initialize(repeating: value, count: Int(frameCount))
            buffers[index].mDataByteSize = frameCount
                * UInt32(MemoryLayout<Float>.size)
        }
        return noErr
    }
}
#endif
