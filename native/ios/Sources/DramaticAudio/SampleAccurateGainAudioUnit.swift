import AVFAudio
import AudioToolbox
import Darwin
import Foundation
import Synchronization

/// The render-thread state for one linear gain. A ramp consumes exactly its
/// authored number of samples even when the host splits rendering into
/// differently sized quanta.
struct SampleAccurateGainKernel: Sendable {
    private(set) var currentGain: AUValue
    private(set) var rampTarget: AUValue
    private(set) var rampIncrement: AUValue = 0
    private(set) var rampFramesRemaining: UInt64 = 0
    private(set) var appliedImmediateGeneration: UInt32 = 0

    init(initialGain: AUValue) {
        currentGain = initialGain
        rampTarget = initialGain
    }

    mutating func setImmediate(_ value: AUValue) {
        currentGain = value
        rampTarget = value
        rampIncrement = 0
        rampFramesRemaining = 0
    }

    mutating func applyRequestedImmediate(
        _ value: AUValue,
        generation: UInt32
    ) {
        guard generation != appliedImmediateGeneration else { return }
        setImmediate(value)
        appliedImmediateGeneration = generation
    }

    mutating func beginRamp(
        to value: AUValue,
        durationSamples: AUAudioFrameCount
    ) {
        guard durationSamples > 0 else {
            setImmediate(value)
            return
        }
        rampTarget = value
        rampFramesRemaining = UInt64(durationSamples)
        rampIncrement = (value - currentGain) / AUValue(durationSamples)
    }

    /// Returns the gain for the current sample, then advances one sample.
    mutating func consumeGain() -> AUValue {
        let result = currentGain
        guard rampFramesRemaining > 0 else { return result }
        currentGain += rampIncrement
        rampFramesRemaining -= 1
        if rampFramesRemaining == 0 {
            currentGain = rampTarget
            rampIncrement = 0
        }
        return result
    }
}

#if os(iOS)
private final class SampleAccurateGainRenderStorage: @unchecked Sendable {
    let kernel: UnsafeMutablePointer<SampleAccurateGainKernel>
    let requestedImmediate = Atomic<UInt64>(UInt64(AUValue(1).bitPattern))
    let maximumFrameCount = Atomic<UInt32>(4_096)
    let expectedChannelCount = Atomic<UInt32>(2)

    init() {
        kernel = .allocate(capacity: 1)
        kernel.initialize(to: SampleAccurateGainKernel(initialGain: 1))
    }

    deinit {
        kernel.deinitialize(count: 1)
        kernel.deallocate()
    }

    func requestImmediateValue(_ value: AUValue) {
        var original = requestedImmediate.load(ordering: .acquiring)
        while true {
            let generation = UInt32(truncatingIfNeeded: original >> 32) &+ 1
            let desired = (UInt64(generation) << 32) | UInt64(value.bitPattern)
            let result = requestedImmediate.compareExchange(
                expected: original,
                desired: desired,
                ordering: .acquiringAndReleasing
            )
            if result.exchanged { return }
            original = result.original
        }
    }

    func requestedImmediateSnapshot() -> (generation: UInt32, value: AUValue) {
        let packed = requestedImmediate.load(ordering: .acquiring)
        return (
            generation: UInt32(truncatingIfNeeded: packed >> 32),
            value: AUValue(bitPattern: UInt32(truncatingIfNeeded: packed))
        )
    }
}

@inline(__always)
private func silenceAudioBufferList(
    _ outputData: UnsafeMutablePointer<AudioBufferList>,
    frameCount: AUAudioFrameCount,
    actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>
) {
    let buffers = UnsafeMutableAudioBufferListPointer(outputData)
    for index in buffers.indices {
        guard let data = buffers[index].mData else { continue }
        let sampleCount = Int(frameCount).multipliedReportingOverflow(
            by: max(1, Int(buffers[index].mNumberChannels))
        )
        let byteCount = sampleCount.partialValue.multipliedReportingOverflow(
            by: MemoryLayout<Float>.size
        )
        let safeBytes = sampleCount.overflow || byteCount.overflow
            ? 0
            : min(Int(buffers[index].mDataByteSize), byteCount.partialValue)
        memset(
            data,
            0,
            safeBytes
        )
    }
    actionFlags.pointee.insert(.unitRenderAction_OutputIsSilence)
}

@objc(LWSampleAccurateGainAudioUnit)
final class SampleAccurateGainAudioUnit: AUAudioUnit {
    static let gainAddress: AUParameterAddress = 0

    private var inputBusStorage: AUAudioUnitBus!
    private var outputBusStorage: AUAudioUnitBus!
    private var inputBusArrayStorage: AUAudioUnitBusArray!
    private var outputBusArrayStorage: AUAudioUnitBusArray!
    private var gainParameterStorage: AUParameter!
    private let renderStorage = SampleAccurateGainRenderStorage()

    override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        try super.init(
            componentDescription: componentDescription,
            options: options
        )
        guard let defaultFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ) else {
            throw SampleAccurateGainNodeError.couldNotCreateDefaultFormat
        }
        inputBusStorage = try AUAudioUnitBus(format: defaultFormat)
        outputBusStorage = try AUAudioUnitBus(format: defaultFormat)
        inputBusStorage.maximumChannelCount = 2
        outputBusStorage.maximumChannelCount = 2
        inputBusArrayStorage = AUAudioUnitBusArray(
            audioUnit: self,
            busType: .input,
            busses: [inputBusStorage]
        )
        outputBusArrayStorage = AUAudioUnitBusArray(
            audioUnit: self,
            busType: .output,
            busses: [outputBusStorage]
        )

        gainParameterStorage = AUParameterTree.createParameter(
            withIdentifier: "gain",
            name: "Gain",
            address: Self.gainAddress,
            min: 0,
            max: 4,
            unit: .linearGain,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        let tree = AUParameterTree.createTree(
            withChildren: [gainParameterStorage]
        )
        let storage = renderStorage
        tree.implementorValueObserver = { _, value in
            storage.requestImmediateValue(value)
        }
        tree.implementorValueProvider = { _ in
            // Runtime automation is authoritative inside the render kernel.
            // Host queries intentionally expose only the last immediate value;
            // no transport decision reads AUParameter.value during playback.
            storage.requestedImmediateSnapshot().value
        }
        parameterTree = tree
        gainParameterStorage.value = 1
    }

    override var inputBusses: AUAudioUnitBusArray {
        inputBusArrayStorage
    }

    override var outputBusses: AUAudioUnitBusArray {
        outputBusArrayStorage
    }

    override func shouldChange(
        to format: AVAudioFormat,
        for bus: AUAudioUnitBus
    ) -> Bool {
        !renderResourcesAllocated
            && format.commonFormat == .pcmFormatFloat32
            && !format.isInterleaved
            && (format.channelCount == 1 || format.channelCount == 2)
    }

    override func allocateRenderResources() throws {
        guard inputBusStorage.format == outputBusStorage.format else {
            throw SampleAccurateGainNodeError.inputOutputFormatMismatch
        }
        try super.allocateRenderResources()
        renderStorage.maximumFrameCount.store(
            maximumFramesToRender,
            ordering: .releasing
        )
        renderStorage.expectedChannelCount.store(
            outputBusStorage.format.channelCount,
            ordering: .releasing
        )
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let storage = renderStorage
        let kernel = storage.kernel
        return {
            actionFlags,
            timestamp,
            frameCount,
            _,
            outputData,
            realtimeEventListHead,
            pullInputBlock in
            let time = timestamp.pointee
            let maximumFrameCount = storage.maximumFrameCount.load(
                ordering: .acquiring
            )
            guard time.mFlags.contains(.sampleTimeValid),
                  time.mSampleTime.isFinite,
                  let renderStartSample = AUEventSampleTime(
                      exactly: time.mSampleTime
                  ),
                  frameCount > 0,
                  frameCount <= maximumFrameCount else {
                silenceAudioBufferList(
                    outputData,
                    frameCount: frameCount,
                    actionFlags: actionFlags
                )
                return frameCount > maximumFrameCount
                    ? kAudioUnitErr_TooManyFramesToProcess
                    : kAudioUnitErr_InvalidPropertyValue
            }
            // Validate the complete event list before changing one sample so
            // invalid automation cannot advance the upstream render graph.
            let renderEnd = renderStartSample.addingReportingOverflow(
                AUEventSampleTime(frameCount)
            )
            guard !renderEnd.overflow else {
                silenceAudioBufferList(
                    outputData,
                    frameCount: frameCount,
                    actionFlags: actionFlags
                )
                return kAudioUnitErr_InvalidPropertyValue
            }
            var validationEvent = realtimeEventListHead
            var previousEventSample = renderStartSample
            while let currentEvent = validationEvent {
                let header = currentEvent.pointee.head
                let parameterEvent = currentEvent.pointee.parameter
                let eventShapeIsValid = (
                    header.eventType == .parameter
                        && parameterEvent.rampDurationSampleFrames == 0
                ) || (
                    header.eventType == .parameterRamp
                        && parameterEvent.rampDurationSampleFrames > 0
                )
                guard eventShapeIsValid,
                      parameterEvent.parameterAddress == Self.gainAddress,
                      parameterEvent.value.isFinite,
                      parameterEvent.value >= 0,
                      parameterEvent.value <= 4,
                      header.eventSampleTime >= renderStartSample,
                      header.eventSampleTime < renderEnd.partialValue,
                      header.eventSampleTime >= previousEventSample else {
                    silenceAudioBufferList(
                        outputData,
                        frameCount: frameCount,
                        actionFlags: actionFlags
                    )
                    return kAudioUnitErr_InvalidParameter
                }
                previousEventSample = header.eventSampleTime
                if let next = header.next {
                    validationEvent = UnsafePointer(next)
                } else {
                    validationEvent = nil
                }
            }

            let requestedImmediate = storage.requestedImmediateSnapshot()
            guard requestedImmediate.value.isFinite,
                  requestedImmediate.value >= 0,
                  requestedImmediate.value <= 4 else {
                silenceAudioBufferList(
                    outputData,
                    frameCount: frameCount,
                    actionFlags: actionFlags
                )
                return kAudioUnitErr_InvalidParameter
            }

            guard let pullInputBlock else {
                silenceAudioBufferList(
                    outputData,
                    frameCount: frameCount,
                    actionFlags: actionFlags
                )
                return kAudioUnitErr_NoConnection
            }
            let pullStatus = pullInputBlock(
                actionFlags,
                timestamp,
                frameCount,
                0,
                outputData
            )
            guard pullStatus == noErr else {
                silenceAudioBufferList(
                    outputData,
                    frameCount: frameCount,
                    actionFlags: actionFlags
                )
                return pullStatus
            }

            let expectedChannelCount = Int(
                storage.expectedChannelCount.load(ordering: .acquiring)
            )
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            let requiredBytes = Int(frameCount) * MemoryLayout<Float>.size
            guard buffers.count == expectedChannelCount else {
                silenceAudioBufferList(
                    outputData,
                    frameCount: frameCount,
                    actionFlags: actionFlags
                )
                return kAudioUnitErr_InvalidPropertyValue
            }
            for index in buffers.indices {
                guard buffers[index].mNumberChannels == 1,
                      buffers[index].mData != nil,
                      Int(buffers[index].mDataByteSize) >= requiredBytes else {
                    silenceAudioBufferList(
                        outputData,
                        frameCount: frameCount,
                        actionFlags: actionFlags
                    )
                    return kAudioUnitErr_InvalidPropertyValue
                }
            }

            kernel.pointee.applyRequestedImmediate(
                requestedImmediate.value,
                generation: requestedImmediate.generation
            )

            var event = realtimeEventListHead
            for frame in 0 ..< Int(frameCount) {
                let absoluteSample = renderStartSample + AUEventSampleTime(frame)
                while let currentEvent = event,
                      currentEvent.pointee.head.eventSampleTime <= absoluteSample {
                    let header = currentEvent.pointee.head
                    let parameterEvent = currentEvent.pointee.parameter
                    if header.eventType == .parameterRamp {
                        kernel.pointee.beginRamp(
                            to: parameterEvent.value,
                            durationSamples: parameterEvent.rampDurationSampleFrames
                        )
                    } else {
                        kernel.pointee.setImmediate(parameterEvent.value)
                    }
                    if let next = header.next {
                        event = UnsafePointer(next)
                    } else {
                        event = nil
                    }
                }

                let gain = kernel.pointee.consumeGain()
                for bufferIndex in buffers.indices {
                    let data = buffers[bufferIndex].mData!
                    let samples = data.assumingMemoryBound(to: Float.self)
                    samples[frame] *= gain
                }
            }
            return noErr
        }
    }
}

enum SampleAccurateGainNodeError: Error, Equatable {
    case couldNotCreateDefaultFormat
    case inputOutputFormatMismatch
    case invalidInitialGain
    case componentInstantiationFailed
}

struct SampleAccurateGainNode {
    let node: AVAudioUnitEffect
    let audioUnit: SampleAccurateGainAudioUnit
    let gainParameter: AUParameter

    private static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x4C_57_47_4E, // LWGN
        componentManufacturer: 0x54_4C_57_53, // TLWS
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private static let registration: Void = {
        AUAudioUnit.registerSubclass(
            SampleAccurateGainAudioUnit.self,
            as: componentDescription,
            name: "The Long West: Sample Gain",
            version: 0x0001_0000
        )
    }()

    static func make(initialGain: AUValue) throws -> Self {
        guard initialGain.isFinite,
              initialGain >= 0,
              initialGain <= 4 else {
            throw SampleAccurateGainNodeError.invalidInitialGain
        }
        _ = registration
        let node = AVAudioUnitEffect(
            audioComponentDescription: componentDescription
        )
        guard let audioUnit = node.auAudioUnit as? SampleAccurateGainAudioUnit,
              let gainParameter = audioUnit.parameterTree?.parameter(
                  withAddress: SampleAccurateGainAudioUnit.gainAddress
              ) else {
            throw SampleAccurateGainNodeError.componentInstantiationFailed
        }
        gainParameter.value = initialGain
        return Self(
            node: node,
            audioUnit: audioUnit,
            gainParameter: gainParameter
        )
    }
}
#endif
