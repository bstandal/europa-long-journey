import Foundation
import os

public protocol PerformanceRecording: AnyObject, Sendable {
    func bindPackage(packageID: String, manifestSHA256: String)
    func beginAction(
        source: PerformanceActionSource,
        actionName: String
    ) -> PerformanceActionToken?
    func cancelAction(_ token: PerformanceActionToken)
    func beginFrame(
        sceneID: String,
        completionProxyActions: [PerformanceActionToken],
        marksRestoredFrameCompletionProxy: Bool
    ) -> PerformanceFrameToken?
    func recordFrameCommandBufferScheduled(_ token: PerformanceFrameToken)
    func recordFrameCommandBufferCompleted(
        _ token: PerformanceFrameToken,
        gpuStartTimeSeconds: Double?,
        gpuEndTimeSeconds: Double?
    )
    func recordFirstActionReady()
    func recordPhysicalFootprint(trigger: PhysicalFootprintTrigger)
    func recordAudioCursor(
        timelineID: String,
        sampleRate: Int,
        cursorSample: Int64,
        kind: AudioCursorCheckpointKind
    )
}

protocol PerformanceMonotonicClock: Sendable {
    func nowNanosecondsSinceBoot() -> UInt64
}

struct SystemPerformanceMonotonicClock: PerformanceMonotonicClock {
    func nowNanosecondsSinceBoot() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

protocol PhysicalFootprintSampling: Sendable {
    func physicalFootprintBytes() -> UInt64?
}

struct UnavailablePhysicalFootprintSampler: PhysicalFootprintSampling {
    func physicalFootprintBytes() -> UInt64? { nil }
}

public final class LocalPerformanceRecorder: PerformanceRecording, @unchecked Sendable {
    private struct PendingAction {
        let source: PerformanceActionSource
        let actionName: String
        let beganNanosecondsSinceBoot: UInt64
        let signpostID: OSSignpostID?
    }

    private struct PendingFrame {
        let sceneID: String
        let commandBufferCommitRequestedNanosecondsSinceBoot: UInt64
        let completionProxyActions: [PerformanceActionToken]
        let marksRestoredFrameCompletionProxy: Bool
        let signpostID: OSSignpostID?
        var commandBufferScheduledCallbackNanosecondsSinceBoot: UInt64?
        var commandBufferCompletedCallbackNanosecondsSinceBoot: UInt64?
        var gpuStartHostTimeNanoseconds: UInt64?
        var gpuEndHostTimeNanoseconds: UInt64?
    }

    private struct State {
        var nextToken: UInt64 = 1
        var nextSequence: UInt64 = 1
        var packagesByID: [String: String] = [:]
        var pendingActions: [PerformanceActionToken: PendingAction] = [:]
        var pendingFrames: [PerformanceFrameToken: PendingFrame] = [:]
        var frameCommandBufferCompletionProxies:
            [FrameCommandBufferCompletionProxyMeasurement] = []
        var interactionCommandBufferCompletionProxies:
            [InteractionCommandBufferCompletionProxyMeasurement] = []
        var physicalFootprint: [PhysicalFootprintMeasurement] = []
        var thermalTransitions: [ThermalTransitionMeasurement] = []
        var audioCursorCheckpoints: [AudioCursorCheckpoint] = []
        var failures: [PerformanceInstrumentationFailure] = []
        var restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart: UInt64?
        var firstActionReadyNanosecondsSinceProcessStart: UInt64?
        var firstActionReceivedNanosecondsSinceProcessStart: UInt64?
        var completedCommandBufferCount: UInt64 = 0
        var lastThermalState: RecordedThermalState?
        var capacityFailureRecorded = false
        var unresolvedFrameFailureRecorded = false
        var unresolvedActionFailureRecorded = false

        var recordedEventCount: Int {
            frameCommandBufferCompletionProxies.count
                + interactionCommandBufferCompletionProxies.count
                + physicalFootprint.count
                + thermalTransitions.count + audioCursorCheckpoints.count + failures.count
        }
    }

    public let request: PerformanceCaptureRequest
    public let platform: PerformancePlatformIdentity
    public let processStartMonotonicNanosecondsSinceBoot: UInt64

    private let clock: any PerformanceMonotonicClock
    private let footprintSampler: any PhysicalFootprintSampling
    private let maximumRecordedEvents: Int
    private let footprintFrameCadence: UInt64
    private let lock = NSLock()
    private let signpostLog = OSLog(
        subsystem: "com.thelongwest.journey",
        category: "PhysicalPerformance"
    )
    private var state = State()
    private var thermalObserver: NSObjectProtocol?

    public convenience init(
        request: PerformanceCaptureRequest,
        platform: PerformancePlatformIdentity,
        maximumRecordedEvents: Int = 250_000,
        footprintFrameCadence: UInt64 = 120
    ) throws {
        try self.init(
            request: request,
            platform: platform,
            clock: SystemPerformanceMonotonicClock(),
            footprintSampler: SystemPhysicalFootprintSampler(),
            maximumRecordedEvents: maximumRecordedEvents,
            footprintFrameCadence: footprintFrameCadence,
            startsThermalMonitoring: true,
            processStartNanosecondsSinceBoot: nil
        )
    }

    init(
        request: PerformanceCaptureRequest,
        platform: PerformancePlatformIdentity,
        clock: any PerformanceMonotonicClock,
        footprintSampler: any PhysicalFootprintSampling,
        maximumRecordedEvents: Int,
        footprintFrameCadence: UInt64,
        startsThermalMonitoring: Bool,
        processStartNanosecondsSinceBoot: UInt64? = nil
    ) throws {
        try PerformanceCaptureValidator.validate(request)
        guard maximumRecordedEvents >= 2, footprintFrameCadence > 0 else {
            throw PerformanceInstrumentationError.invalidCaptureRequest(
                "instrumentation capacity is invalid"
            )
        }
        self.request = request
        self.platform = platform
        self.clock = clock
        self.footprintSampler = footprintSampler
        self.maximumRecordedEvents = maximumRecordedEvents
        self.footprintFrameCadence = footprintFrameCadence
        let now = clock.nowNanosecondsSinceBoot()
        let requestedProcessStart = processStartNanosecondsSinceBoot ?? now
        guard requestedProcessStart <= now else {
            throw PerformanceInstrumentationError.invalidCaptureRequest(
                "process-start clock is in the future"
            )
        }
        processStartMonotonicNanosecondsSinceBoot = requestedProcessStart

        recordThermalState(Self.currentThermalState())
        recordPhysicalFootprint(trigger: .captureStart)
        if startsThermalMonitoring {
            thermalObserver = NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.recordThermalState(Self.currentThermalState())
                self.recordPhysicalFootprint(trigger: .thermalTransition)
            }
        }
    }

    deinit {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }

    public func bindPackage(packageID: String, manifestSHA256: String) {
        guard !packageID.isEmpty,
              PerformanceCaptureValidator.isLowercaseSHA256(manifestSHA256) else {
            recordFailure(.packageIdentityConflict)
            return
        }
        lock.withLock {
            if let existing = state.packagesByID[packageID], existing != manifestSHA256 {
                appendFailureLocked(.packageIdentityConflict)
                return
            }
            state.packagesByID[packageID] = manifestSHA256
        }
    }

    public func beginAction(
        source: PerformanceActionSource,
        actionName: String
    ) -> PerformanceActionToken? {
        guard !actionName.isEmpty else { return nil }
        let now = clock.nowNanosecondsSinceBoot()
        return lock.withLock {
            guard canAcceptPendingMeasurementLocked() else { return nil }
            let token = PerformanceActionToken(rawValue: takeTokenLocked())
            let signpostID = beginSignpostLocked(
                name: "Interaction Command Buffer Completion Proxy"
            )
            state.pendingActions[token] = PendingAction(
                source: source,
                actionName: actionName,
                beganNanosecondsSinceBoot: now,
                signpostID: signpostID
            )
            if state.firstActionReceivedNanosecondsSinceProcessStart == nil {
                state.firstActionReceivedNanosecondsSinceProcessStart = relative(now)
            }
            return token
        }
    }

    public func cancelAction(_ token: PerformanceActionToken) {
        lock.withLock {
            guard let action = state.pendingActions.removeValue(forKey: token) else { return }
            endSignpostLocked(
                name: "Interaction Command Buffer Completion Proxy",
                id: action.signpostID
            )
        }
    }

    public func beginFrame(
        sceneID: String,
        completionProxyActions: [PerformanceActionToken] = [],
        marksRestoredFrameCompletionProxy: Bool = false
    ) -> PerformanceFrameToken? {
        guard !sceneID.isEmpty else { return nil }
        let commitRequested = clock.nowNanosecondsSinceBoot()
        return lock.withLock {
            guard canAcceptPendingMeasurementLocked() else { return nil }
            let uniqueActions = Array(Set(completionProxyActions)).sorted {
                $0.rawValue < $1.rawValue
            }
            guard uniqueActions.allSatisfy({ state.pendingActions[$0] != nil }) else {
                appendFailureLocked(.unresolvedInteractionCompletionProxy)
                return nil
            }
            let token = PerformanceFrameToken(rawValue: takeTokenLocked())
            state.pendingFrames[token] = PendingFrame(
                sceneID: sceneID,
                commandBufferCommitRequestedNanosecondsSinceBoot: commitRequested,
                completionProxyActions: uniqueActions,
                marksRestoredFrameCompletionProxy: marksRestoredFrameCompletionProxy,
                signpostID: beginSignpostLocked(name: "Metal Command Buffer Completion Proxy"),
                commandBufferScheduledCallbackNanosecondsSinceBoot: nil,
                commandBufferCompletedCallbackNanosecondsSinceBoot: nil,
                gpuStartHostTimeNanoseconds: nil,
                gpuEndHostTimeNanoseconds: nil
            )
            return token
        }
    }

    public func recordFrameCommandBufferScheduled(_ token: PerformanceFrameToken) {
        let scheduled = clock.nowNanosecondsSinceBoot()
        lock.withLock {
            guard var frame = state.pendingFrames[token] else { return }
            guard frame.commandBufferScheduledCallbackNanosecondsSinceBoot == nil,
                  frame.commandBufferCompletedCallbackNanosecondsSinceBoot == nil,
                  scheduled >= frame.commandBufferCommitRequestedNanosecondsSinceBoot else {
                failPendingFrameLocked(token, code: .commandBufferCallbackOrderViolation)
                return
            }
            frame.commandBufferScheduledCallbackNanosecondsSinceBoot = scheduled
            state.pendingFrames[token] = frame
        }
    }

    public func recordFrameCommandBufferCompleted(
        _ token: PerformanceFrameToken,
        gpuStartTimeSeconds: Double?,
        gpuEndTimeSeconds: Double?
    ) {
        let completed = clock.nowNanosecondsSinceBoot()
        let gpuPair = Self.validGPUNanosecondsPair(
            startSeconds: gpuStartTimeSeconds,
            endSeconds: gpuEndTimeSeconds
        )
        let shouldSample = lock.withLock {
            guard var frame = state.pendingFrames[token] else { return false }
            guard let scheduled = frame.commandBufferScheduledCallbackNanosecondsSinceBoot,
                  frame.commandBufferCompletedCallbackNanosecondsSinceBoot == nil,
                  completed >= scheduled else {
                failPendingFrameLocked(token, code: .commandBufferCallbackOrderViolation)
                return false
            }
            if (gpuStartTimeSeconds != nil || gpuEndTimeSeconds != nil), gpuPair == nil {
                appendFailureLocked(.invalidGPUTiming)
            }
            frame.commandBufferCompletedCallbackNanosecondsSinceBoot = completed
            frame.gpuStartHostTimeNanoseconds = gpuPair?.start
            frame.gpuEndHostTimeNanoseconds = gpuPair?.end
            state.pendingFrames[token] = frame
            completeInteractionCompletionProxiesLocked(
                frame.completionProxyActions,
                frame: token,
                completed: completed
            )
            if frame.marksRestoredFrameCompletionProxy,
               state.restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart == nil {
                state.restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart =
                    relative(completed)
                os_signpost(
                    .event,
                    log: signpostLog,
                    name: "Restored Frame Command Buffer Completion Proxy"
                )
            }
            state.completedCommandBufferCount &+= 1
            endSignpostLocked(
                name: "Metal Command Buffer Completion Proxy",
                id: frame.signpostID
            )
            finalizeFrameIfCompleteLocked(token)
            return state.completedCommandBufferCount.isMultiple(of: footprintFrameCadence)
        }
        if shouldSample {
            recordPhysicalFootprint(trigger: .commandBufferCompletionCadence)
        }
    }

    public func recordFirstActionReady() {
        let now = clock.nowNanosecondsSinceBoot()
        lock.withLock {
            guard state.firstActionReadyNanosecondsSinceProcessStart == nil else { return }
            state.firstActionReadyNanosecondsSinceProcessStart = relative(now)
            os_signpost(.event, log: signpostLog, name: "First Action Ready")
        }
    }

    public func recordPhysicalFootprint(trigger: PhysicalFootprintTrigger) {
        let now = clock.nowNanosecondsSinceBoot()
        guard let bytes = footprintSampler.physicalFootprintBytes(), bytes > 0 else {
            recordFailure(.physicalFootprintUnavailable, at: now)
            return
        }
        lock.withLock {
            guard let sequence = takeSequenceLocked() else { return }
            state.physicalFootprint.append(
                PhysicalFootprintMeasurement(
                    sequence: sequence,
                    nanosecondsSinceProcessStart: relative(now),
                    physicalFootprintBytes: bytes,
                    trigger: trigger
                )
            )
        }
    }

    public func recordAudioCursor(
        timelineID: String,
        sampleRate: Int,
        cursorSample: Int64,
        kind: AudioCursorCheckpointKind
    ) {
        let now = clock.nowNanosecondsSinceBoot()
        guard !timelineID.isEmpty, sampleRate == 48_000, cursorSample >= 0 else {
            recordFailure(.invalidAudioCheckpoint, at: now)
            return
        }
        lock.withLock {
            guard let sequence = takeSequenceLocked() else { return }
            state.audioCursorCheckpoints.append(
                AudioCursorCheckpoint(
                    sequence: sequence,
                    nanosecondsSinceProcessStart: relative(now),
                    timelineID: timelineID,
                    sampleRate: sampleRate,
                    cursorSample: cursorSample,
                    kind: kind
                )
            )
        }
    }

    public func recordThermalState(_ thermalState: RecordedThermalState) {
        let now = clock.nowNanosecondsSinceBoot()
        lock.withLock {
            guard thermalState != state.lastThermalState,
                  let sequence = takeSequenceLocked() else { return }
            state.thermalTransitions.append(
                ThermalTransitionMeasurement(
                    sequence: sequence,
                    nanosecondsSinceProcessStart: relative(now),
                    from: state.lastThermalState,
                    to: thermalState
                )
            )
            state.lastThermalState = thermalState
            os_signpost(.event, log: signpostLog, name: "Thermal State Transition")
        }
    }

    func makeReport(appBuildSHA256: String) -> PhysicalPerformanceReport {
        lock.withLock {
            if !state.pendingFrames.isEmpty, !state.unresolvedFrameFailureRecorded {
                state.unresolvedFrameFailureRecorded = true
                appendFailureLocked(.unresolvedCommandBufferFrame)
            }
            if !state.pendingActions.isEmpty, !state.unresolvedActionFailureRecorded {
                state.unresolvedActionFailureRecorded = true
                appendFailureLocked(.unresolvedInteractionCompletionProxy)
            }
            let packages = state.packagesByID.map {
                PerformancePackageIdentity(packageID: $0.key, manifestSHA256: $0.value)
            }.sorted {
                if $0.packageID != $1.packageID { return $0.packageID < $1.packageID }
                return $0.manifestSHA256 < $1.manifestSHA256
            }
            let classification: PerformanceGateClassification =
                platform.captureClass == .physicalDevice
                    ? .deviceRawMeasurementsOnly : .nonDevice
            return PhysicalPerformanceReport(
                protocolID: request.protocolID,
                runID: request.runID,
                attemptID: request.attemptID,
                repetition: request.repetition,
                gateClassification: classification,
                platform: platform,
                appBuildHashKind: "APP_BUNDLE_FILE_TREE_SHA256",
                appBuildSHA256: appBuildSHA256,
                packages: packages,
                processStartMonotonicNanosecondsSinceBoot:
                    processStartMonotonicNanosecondsSinceBoot,
                launch: LaunchTimingMeasurements(
                    restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart:
                        state
                            .restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart,
                    firstActionReadyNanosecondsSinceProcessStart:
                        state.firstActionReadyNanosecondsSinceProcessStart,
                    firstActionReceivedNanosecondsSinceProcessStart:
                        state.firstActionReceivedNanosecondsSinceProcessStart
                ),
                frameCommandBufferCompletionProxies:
                    canonicalFrameCompletionProxiesLocked(),
                interactionCommandBufferCompletionProxies:
                    state.interactionCommandBufferCompletionProxies.sorted {
                        $0.sequence < $1.sequence
                    },
                physicalFootprint: state.physicalFootprint.sorted { $0.sequence < $1.sequence },
                thermalTransitions: state.thermalTransitions.sorted { $0.sequence < $1.sequence },
                audioCursorCheckpoints: state.audioCursorCheckpoints.sorted {
                    $0.sequence < $1.sequence
                },
                instrumentationFailures: state.failures.sorted { $0.sequence < $1.sequence },
                rawTraceRetentionRequired: request.rawTraceRetentionRequired
            )
        }
    }

    private func completeInteractionCompletionProxiesLocked(
        _ tokens: [PerformanceActionToken],
        frame: PerformanceFrameToken,
        completed: UInt64
    ) {
        for token in tokens {
            guard let action = state.pendingActions.removeValue(forKey: token) else {
                appendFailureLocked(.unresolvedInteractionCompletionProxy)
                continue
            }
            guard completed >= action.beganNanosecondsSinceBoot,
                  let sequence = takeSequenceLocked() else {
                appendFailureLocked(.unresolvedInteractionCompletionProxy)
                continue
            }
            state.interactionCommandBufferCompletionProxies.append(
                InteractionCommandBufferCompletionProxyMeasurement(
                    sequence: sequence,
                    actionID: token.rawValue,
                    source: action.source,
                    actionName: action.actionName,
                    beganNanosecondsSinceProcessStart: relative(
                        action.beganNanosecondsSinceBoot
                    ),
                    firstCommandBufferCompletedCallbackNanosecondsSinceProcessStart:
                        relative(completed),
                    actionToCommandBufferCompletedCallbackNanoseconds:
                        completed - action.beganNanosecondsSinceBoot,
                    completedFrameID: frame.rawValue
                )
            )
            endSignpostLocked(
                name: "Interaction Command Buffer Completion Proxy",
                id: action.signpostID
            )
        }
    }

    private func finalizeFrameIfCompleteLocked(_ token: PerformanceFrameToken) {
        guard let frame = state.pendingFrames[token],
              let scheduled = frame.commandBufferScheduledCallbackNanosecondsSinceBoot,
              let completed = frame.commandBufferCompletedCallbackNanosecondsSinceBoot,
              let sequence = takeSequenceLocked() else { return }
        state.frameCommandBufferCompletionProxies.append(
            FrameCommandBufferCompletionProxyMeasurement(
                sequence: sequence,
                frameID: token.rawValue,
                sceneID: frame.sceneID,
                commandBufferCommitRequestedNanosecondsSinceProcessStart: relative(
                    frame.commandBufferCommitRequestedNanosecondsSinceBoot
                ),
                commandBufferScheduledCallbackNanosecondsSinceProcessStart:
                    relative(scheduled),
                commandBufferCompletedCallbackNanosecondsSinceProcessStart:
                    relative(completed),
                commitRequestToScheduledCallbackNanoseconds:
                    scheduled - frame.commandBufferCommitRequestedNanosecondsSinceBoot,
                commitRequestToCompletedCallbackNanoseconds:
                    completed - frame.commandBufferCommitRequestedNanosecondsSinceBoot,
                previousCommandBufferCompletionCallbackIntervalNanoseconds: nil,
                gpuStartHostTimeNanoseconds: frame.gpuStartHostTimeNanoseconds,
                gpuEndHostTimeNanoseconds: frame.gpuEndHostTimeNanoseconds,
                gpuExecutionNanoseconds: frame.gpuStartHostTimeNanoseconds.flatMap {
                    start in frame.gpuEndHostTimeNanoseconds.map { $0 - start }
                }
            )
        )
        state.pendingFrames.removeValue(forKey: token)
    }

    private func canonicalFrameCompletionProxiesLocked()
        -> [FrameCommandBufferCompletionProxyMeasurement] {
        let ordered = state.frameCommandBufferCompletionProxies.sorted {
            if $0.commandBufferCompletedCallbackNanosecondsSinceProcessStart
                != $1.commandBufferCompletedCallbackNanosecondsSinceProcessStart {
                return $0.commandBufferCompletedCallbackNanosecondsSinceProcessStart
                    < $1.commandBufferCompletedCallbackNanosecondsSinceProcessStart
            }
            return $0.frameID < $1.frameID
        }
        var previousCompletion: UInt64?
        return ordered.map { frame in
            let interval = previousCompletion.map {
                frame.commandBufferCompletedCallbackNanosecondsSinceProcessStart - $0
            }
            previousCompletion =
                frame.commandBufferCompletedCallbackNanosecondsSinceProcessStart
            return FrameCommandBufferCompletionProxyMeasurement(
                sequence: frame.sequence,
                frameID: frame.frameID,
                sceneID: frame.sceneID,
                commandBufferCommitRequestedNanosecondsSinceProcessStart:
                    frame.commandBufferCommitRequestedNanosecondsSinceProcessStart,
                commandBufferScheduledCallbackNanosecondsSinceProcessStart:
                    frame.commandBufferScheduledCallbackNanosecondsSinceProcessStart,
                commandBufferCompletedCallbackNanosecondsSinceProcessStart:
                    frame.commandBufferCompletedCallbackNanosecondsSinceProcessStart,
                commitRequestToScheduledCallbackNanoseconds:
                    frame.commitRequestToScheduledCallbackNanoseconds,
                commitRequestToCompletedCallbackNanoseconds:
                    frame.commitRequestToCompletedCallbackNanoseconds,
                previousCommandBufferCompletionCallbackIntervalNanoseconds: interval,
                gpuStartHostTimeNanoseconds: frame.gpuStartHostTimeNanoseconds,
                gpuEndHostTimeNanoseconds: frame.gpuEndHostTimeNanoseconds,
                gpuExecutionNanoseconds: frame.gpuExecutionNanoseconds
            )
        }
    }

    private func failPendingFrameLocked(
        _ token: PerformanceFrameToken,
        code: PerformanceInstrumentationFailureCode
    ) {
        guard let frame = state.pendingFrames.removeValue(forKey: token) else { return }
        endSignpostLocked(
            name: "Metal Command Buffer Completion Proxy",
            id: frame.signpostID
        )
        for actionToken in frame.completionProxyActions {
            guard let action = state.pendingActions.removeValue(forKey: actionToken) else {
                continue
            }
            endSignpostLocked(
                name: "Interaction Command Buffer Completion Proxy",
                id: action.signpostID
            )
        }
        appendFailureLocked(code)
    }

    private func canAcceptPendingMeasurementLocked() -> Bool {
        let pending = state.pendingActions.count + state.pendingFrames.count
        if state.recordedEventCount + pending < maximumRecordedEvents - 1 { return true }
        appendCapacityFailureLocked()
        return false
    }

    private func takeSequenceLocked() -> UInt64? {
        if state.recordedEventCount < maximumRecordedEvents - 1 {
            defer { state.nextSequence &+= 1 }
            return state.nextSequence
        }
        appendCapacityFailureLocked()
        return nil
    }

    private func takeTokenLocked() -> UInt64 {
        defer { state.nextToken &+= 1 }
        return state.nextToken
    }

    private func appendCapacityFailureLocked() {
        guard !state.capacityFailureRecorded,
              state.recordedEventCount < maximumRecordedEvents else { return }
        state.capacityFailureRecorded = true
        let sequence = state.nextSequence
        state.nextSequence &+= 1
        state.failures.append(
            PerformanceInstrumentationFailure(
                sequence: sequence,
                nanosecondsSinceProcessStart: relative(clock.nowNanosecondsSinceBoot()),
                code: .eventCapacityExceeded
            )
        )
    }

    private func recordFailure(
        _ code: PerformanceInstrumentationFailureCode,
        at now: UInt64? = nil
    ) {
        lock.withLock { appendFailureLocked(code, at: now) }
    }

    private func appendFailureLocked(
        _ code: PerformanceInstrumentationFailureCode,
        at now: UInt64? = nil
    ) {
        guard let sequence = takeSequenceLocked() else { return }
        state.failures.append(
            PerformanceInstrumentationFailure(
                sequence: sequence,
                nanosecondsSinceProcessStart: relative(
                    now ?? clock.nowNanosecondsSinceBoot()
                ),
                code: code
            )
        )
    }

    private func relative(_ absolute: UInt64) -> UInt64 {
        absolute >= processStartMonotonicNanosecondsSinceBoot
            ? absolute - processStartMonotonicNanosecondsSinceBoot : 0
    }

    private func beginSignpostLocked(name: StaticString) -> OSSignpostID? {
        let id = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: name, signpostID: id)
        return id
    }

    private func endSignpostLocked(name: StaticString, id: OSSignpostID?) {
        guard let id else { return }
        os_signpost(.end, log: signpostLog, name: name, signpostID: id)
    }

    private static func nanoseconds(fromSeconds seconds: Double) -> UInt64 {
        UInt64((seconds * 1_000_000_000).rounded())
    }

    private static func validGPUNanosecondsPair(
        startSeconds: Double?,
        endSeconds: Double?
    ) -> (start: UInt64, end: UInt64)? {
        guard let startSeconds,
              let endSeconds,
              startSeconds.isFinite,
              endSeconds.isFinite,
              startSeconds > 0,
              endSeconds >= startSeconds,
              endSeconds < Double(UInt64.max) / 1_000_000_000 else {
            return nil
        }
        return (
            start: nanoseconds(fromSeconds: startSeconds),
            end: nanoseconds(fromSeconds: endSeconds)
        )
    }

    private static func currentThermalState() -> RecordedThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unavailable
        }
    }
}
