import Foundation

public enum PerformanceCaptureClass: String, Codable, Equatable, Sendable {
    case physicalDevice = "PHYSICAL_DEVICE"
    case nonDevice = "NON_DEVICE"
}

/// A raw capture is deliberately never a physical-gate pass. The separate
/// physical-device evaluator owns budget decisions after it has verified the
/// complete paired-run protocol and retained traces.
public enum PerformanceGateClassification: String, Codable, Equatable, Sendable {
    case deviceRawMeasurementsOnly = "DEVICE_RAW_MEASUREMENTS_ONLY"
    case nonDevice = "NON_DEVICE"
}

/// Local captures stop at Metal command-buffer and GPU completion. They do not
/// observe scan-out or prove display presentation.
public enum PerformanceLocalTimingScope: String, Codable, Equatable, Sendable {
    case commandBufferAndGPUCompletionProxyOnly =
        "COMMAND_BUFFER_AND_GPU_COMPLETION_PROXY_ONLY"
}

public enum PerformanceBuildConfiguration: String, Codable, Equatable, Sendable {
    case debug = "DEBUG"
    case release = "RELEASE"
}

public struct PerformanceCaptureRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let protocolID: String
    public let runID: String
    public let attemptID: String
    public let repetition: Int
    public let rawTraceRetentionRequired: Bool

    public init(
        schemaVersion: Int = 1,
        protocolID: String,
        runID: String,
        attemptID: String,
        repetition: Int,
        rawTraceRetentionRequired: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.protocolID = protocolID
        self.runID = runID
        self.attemptID = attemptID
        self.repetition = repetition
        self.rawTraceRetentionRequired = rawTraceRetentionRequired
    }
}

public struct PerformancePlatformIdentity: Codable, Equatable, Sendable {
    public let captureClass: PerformanceCaptureClass
    public let hardwareModel: String
    public let operatingSystem: String
    public let buildConfiguration: PerformanceBuildConfiguration

    public init(
        captureClass: PerformanceCaptureClass,
        hardwareModel: String,
        operatingSystem: String,
        buildConfiguration: PerformanceBuildConfiguration
    ) {
        self.captureClass = captureClass
        self.hardwareModel = hardwareModel
        self.operatingSystem = operatingSystem
        self.buildConfiguration = buildConfiguration
    }
}

public struct PerformancePackageIdentity: Codable, Equatable, Sendable {
    public let packageID: String
    public let manifestSHA256: String

    public init(packageID: String, manifestSHA256: String) {
        self.packageID = packageID
        self.manifestSHA256 = manifestSHA256
    }
}

public struct PerformanceFrameToken: Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public struct PerformanceActionToken: Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public enum PerformanceActionSource: String, Codable, Equatable, Sendable {
    case touch = "TOUCH"
    case voiceOver = "VOICE_OVER"
}

public struct FrameCommandBufferCompletionProxyMeasurement:
    Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let frameID: UInt64
    public let sceneID: String
    public let commandBufferCommitRequestedNanosecondsSinceProcessStart: UInt64
    public let commandBufferScheduledCallbackNanosecondsSinceProcessStart: UInt64
    public let commandBufferCompletedCallbackNanosecondsSinceProcessStart: UInt64
    public let commitRequestToScheduledCallbackNanoseconds: UInt64
    public let commitRequestToCompletedCallbackNanoseconds: UInt64
    public let previousCommandBufferCompletionCallbackIntervalNanoseconds: UInt64?
    public let gpuStartHostTimeNanoseconds: UInt64?
    public let gpuEndHostTimeNanoseconds: UInt64?
    public let gpuExecutionNanoseconds: UInt64?

    public init(
        sequence: UInt64,
        frameID: UInt64,
        sceneID: String,
        commandBufferCommitRequestedNanosecondsSinceProcessStart: UInt64,
        commandBufferScheduledCallbackNanosecondsSinceProcessStart: UInt64,
        commandBufferCompletedCallbackNanosecondsSinceProcessStart: UInt64,
        commitRequestToScheduledCallbackNanoseconds: UInt64,
        commitRequestToCompletedCallbackNanoseconds: UInt64,
        previousCommandBufferCompletionCallbackIntervalNanoseconds: UInt64?,
        gpuStartHostTimeNanoseconds: UInt64?,
        gpuEndHostTimeNanoseconds: UInt64?,
        gpuExecutionNanoseconds: UInt64?
    ) {
        self.sequence = sequence
        self.frameID = frameID
        self.sceneID = sceneID
        self.commandBufferCommitRequestedNanosecondsSinceProcessStart =
            commandBufferCommitRequestedNanosecondsSinceProcessStart
        self.commandBufferScheduledCallbackNanosecondsSinceProcessStart =
            commandBufferScheduledCallbackNanosecondsSinceProcessStart
        self.commandBufferCompletedCallbackNanosecondsSinceProcessStart =
            commandBufferCompletedCallbackNanosecondsSinceProcessStart
        self.commitRequestToScheduledCallbackNanoseconds =
            commitRequestToScheduledCallbackNanoseconds
        self.commitRequestToCompletedCallbackNanoseconds =
            commitRequestToCompletedCallbackNanoseconds
        self.previousCommandBufferCompletionCallbackIntervalNanoseconds =
            previousCommandBufferCompletionCallbackIntervalNanoseconds
        self.gpuStartHostTimeNanoseconds = gpuStartHostTimeNanoseconds
        self.gpuEndHostTimeNanoseconds = gpuEndHostTimeNanoseconds
        self.gpuExecutionNanoseconds = gpuExecutionNanoseconds
    }
}

public struct InteractionCommandBufferCompletionProxyMeasurement:
    Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let actionID: UInt64
    public let source: PerformanceActionSource
    public let actionName: String
    public let beganNanosecondsSinceProcessStart: UInt64
    public let firstCommandBufferCompletedCallbackNanosecondsSinceProcessStart: UInt64
    public let actionToCommandBufferCompletedCallbackNanoseconds: UInt64
    public let completedFrameID: UInt64

    public init(
        sequence: UInt64,
        actionID: UInt64,
        source: PerformanceActionSource,
        actionName: String,
        beganNanosecondsSinceProcessStart: UInt64,
        firstCommandBufferCompletedCallbackNanosecondsSinceProcessStart: UInt64,
        actionToCommandBufferCompletedCallbackNanoseconds: UInt64,
        completedFrameID: UInt64
    ) {
        self.sequence = sequence
        self.actionID = actionID
        self.source = source
        self.actionName = actionName
        self.beganNanosecondsSinceProcessStart = beganNanosecondsSinceProcessStart
        self.firstCommandBufferCompletedCallbackNanosecondsSinceProcessStart =
            firstCommandBufferCompletedCallbackNanosecondsSinceProcessStart
        self.actionToCommandBufferCompletedCallbackNanoseconds =
            actionToCommandBufferCompletedCallbackNanoseconds
        self.completedFrameID = completedFrameID
    }
}

public enum PhysicalFootprintTrigger: String, Codable, Equatable, Sendable {
    case captureStart = "CAPTURE_START"
    case commandBufferCompletionCadence = "COMMAND_BUFFER_COMPLETION_CADENCE"
    case thermalTransition = "THERMAL_TRANSITION"
    case explicitCheckpoint = "EXPLICIT_CHECKPOINT"
}

public struct PhysicalFootprintMeasurement: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let nanosecondsSinceProcessStart: UInt64
    public let physicalFootprintBytes: UInt64
    public let trigger: PhysicalFootprintTrigger

    public init(
        sequence: UInt64,
        nanosecondsSinceProcessStart: UInt64,
        physicalFootprintBytes: UInt64,
        trigger: PhysicalFootprintTrigger
    ) {
        self.sequence = sequence
        self.nanosecondsSinceProcessStart = nanosecondsSinceProcessStart
        self.physicalFootprintBytes = physicalFootprintBytes
        self.trigger = trigger
    }
}

public enum RecordedThermalState: String, Codable, Equatable, Sendable {
    case nominal = "NOMINAL"
    case fair = "FAIR"
    case serious = "SERIOUS"
    case critical = "CRITICAL"
    case unavailable = "UNAVAILABLE"
}

public struct ThermalTransitionMeasurement: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let nanosecondsSinceProcessStart: UInt64
    public let from: RecordedThermalState?
    public let to: RecordedThermalState

    public init(
        sequence: UInt64,
        nanosecondsSinceProcessStart: UInt64,
        from: RecordedThermalState?,
        to: RecordedThermalState
    ) {
        self.sequence = sequence
        self.nanosecondsSinceProcessStart = nanosecondsSinceProcessStart
        self.from = from
        self.to = to
    }
}

public enum AudioCursorCheckpointKind: String, Codable, Equatable, Sendable {
    case prepared = "PREPARED"
    case play = "PLAY"
    case controlledPause = "CONTROLLED_PAUSE"
    case interruptionPause = "INTERRUPTION_PAUSE"
    case routeChangePause = "ROUTE_CHANGE_PAUSE"
    case snapshot = "SNAPSHOT"
    case restoration = "RESTORATION"
    case completed = "COMPLETED"
}

public struct AudioCursorCheckpoint: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let nanosecondsSinceProcessStart: UInt64
    public let timelineID: String
    public let sampleRate: Int
    public let cursorSample: Int64
    public let kind: AudioCursorCheckpointKind

    public init(
        sequence: UInt64,
        nanosecondsSinceProcessStart: UInt64,
        timelineID: String,
        sampleRate: Int,
        cursorSample: Int64,
        kind: AudioCursorCheckpointKind
    ) {
        self.sequence = sequence
        self.nanosecondsSinceProcessStart = nanosecondsSinceProcessStart
        self.timelineID = timelineID
        self.sampleRate = sampleRate
        self.cursorSample = cursorSample
        self.kind = kind
    }
}

public struct LaunchTimingMeasurements: Codable, Equatable, Sendable {
    public let restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart: UInt64?
    public let firstActionReadyNanosecondsSinceProcessStart: UInt64?
    public let firstActionReceivedNanosecondsSinceProcessStart: UInt64?

    public init(
        restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart: UInt64?,
        firstActionReadyNanosecondsSinceProcessStart: UInt64?,
        firstActionReceivedNanosecondsSinceProcessStart: UInt64?
    ) {
        self.restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart =
            restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart
        self.firstActionReadyNanosecondsSinceProcessStart = firstActionReadyNanosecondsSinceProcessStart
        self.firstActionReceivedNanosecondsSinceProcessStart = firstActionReceivedNanosecondsSinceProcessStart
    }
}

public enum PerformanceInstrumentationFailureCode: String, Codable, Equatable, Sendable {
    case eventCapacityExceeded = "EVENT_CAPACITY_EXCEEDED"
    case physicalFootprintUnavailable = "PHYSICAL_FOOTPRINT_UNAVAILABLE"
    case invalidAudioCheckpoint = "INVALID_AUDIO_CHECKPOINT"
    case packageIdentityConflict = "PACKAGE_IDENTITY_CONFLICT"
    case unresolvedCommandBufferFrame = "UNRESOLVED_COMMAND_BUFFER_FRAME"
    case unresolvedInteractionCompletionProxy =
        "UNRESOLVED_INTERACTION_COMPLETION_PROXY"
    case commandBufferCallbackOrderViolation =
        "COMMAND_BUFFER_CALLBACK_ORDER_VIOLATION"
    case invalidGPUTiming = "INVALID_GPU_TIMING"
}

public struct PerformanceInstrumentationFailure: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let nanosecondsSinceProcessStart: UInt64
    public let code: PerformanceInstrumentationFailureCode

    public init(
        sequence: UInt64,
        nanosecondsSinceProcessStart: UInt64,
        code: PerformanceInstrumentationFailureCode
    ) {
        self.sequence = sequence
        self.nanosecondsSinceProcessStart = nanosecondsSinceProcessStart
        self.code = code
    }
}

public struct PhysicalPerformanceReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let protocolID: String
    public let runID: String
    public let attemptID: String
    public let repetition: Int
    public let gateClassification: PerformanceGateClassification
    public let localTimingScope: PerformanceLocalTimingScope
    public let platform: PerformancePlatformIdentity
    public let appBuildHashKind: String
    public let appBuildSHA256: String
    public let packages: [PerformancePackageIdentity]
    public let processStartMonotonicNanosecondsSinceBoot: UInt64
    public let launch: LaunchTimingMeasurements
    public let frameCommandBufferCompletionProxies:
        [FrameCommandBufferCompletionProxyMeasurement]
    public let interactionCommandBufferCompletionProxies:
        [InteractionCommandBufferCompletionProxyMeasurement]
    public let physicalFootprint: [PhysicalFootprintMeasurement]
    public let thermalTransitions: [ThermalTransitionMeasurement]
    public let audioCursorCheckpoints: [AudioCursorCheckpoint]
    public let instrumentationFailures: [PerformanceInstrumentationFailure]
    public let rawTraceRetentionRequired: Bool

    public init(
        schemaVersion: Int = 1,
        protocolID: String,
        runID: String,
        attemptID: String,
        repetition: Int,
        gateClassification: PerformanceGateClassification,
        localTimingScope: PerformanceLocalTimingScope =
            .commandBufferAndGPUCompletionProxyOnly,
        platform: PerformancePlatformIdentity,
        appBuildHashKind: String,
        appBuildSHA256: String,
        packages: [PerformancePackageIdentity],
        processStartMonotonicNanosecondsSinceBoot: UInt64,
        launch: LaunchTimingMeasurements,
        frameCommandBufferCompletionProxies:
            [FrameCommandBufferCompletionProxyMeasurement],
        interactionCommandBufferCompletionProxies:
            [InteractionCommandBufferCompletionProxyMeasurement],
        physicalFootprint: [PhysicalFootprintMeasurement],
        thermalTransitions: [ThermalTransitionMeasurement],
        audioCursorCheckpoints: [AudioCursorCheckpoint],
        instrumentationFailures: [PerformanceInstrumentationFailure],
        rawTraceRetentionRequired: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.protocolID = protocolID
        self.runID = runID
        self.attemptID = attemptID
        self.repetition = repetition
        self.gateClassification = gateClassification
        self.localTimingScope = localTimingScope
        self.platform = platform
        self.appBuildHashKind = appBuildHashKind
        self.appBuildSHA256 = appBuildSHA256
        self.packages = packages
        self.processStartMonotonicNanosecondsSinceBoot = processStartMonotonicNanosecondsSinceBoot
        self.launch = launch
        self.frameCommandBufferCompletionProxies = frameCommandBufferCompletionProxies
        self.interactionCommandBufferCompletionProxies =
            interactionCommandBufferCompletionProxies
        self.physicalFootprint = physicalFootprint
        self.thermalTransitions = thermalTransitions
        self.audioCursorCheckpoints = audioCursorCheckpoints
        self.instrumentationFailures = instrumentationFailures
        self.rawTraceRetentionRequired = rawTraceRetentionRequired
    }
}

public enum PerformanceInstrumentationError: Error, Equatable, Sendable {
    case invalidCaptureRequest(String)
    case invalidReport(String)
    case appBundleUnavailable
    case appBuildHashFailed
    case reportWriteFailed
    case captureNotActive
}
