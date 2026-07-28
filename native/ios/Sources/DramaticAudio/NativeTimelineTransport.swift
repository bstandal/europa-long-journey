#if os(iOS)
import AVFAudio
import ContentKit
import CoreHaptics
import Darwin
import ExperiencePreferences
import Foundation
import QualityInstrumentation
import Synchronization

public enum NativeTimelineTransportState: Equatable, Sendable {
    case idle
    case prepared
    case playing
    case paused
    case completed
}

public enum NativeTimelineTransportError: Error, Equatable, Sendable {
    case notPrepared
    case alreadyPlaying
    case audioFileCouldNotOpen(String)
    case unsupportedAudioFormat(String)
    case hapticPatternCouldNotPrepare
    case causalMixContractViolation(String)
    case causalGainParameterUnavailable(String)
    case causalLoopBufferCouldNotPrepare(String)
    case renderClockUnavailable
    case transitionCouldNotPrepare(String)
    case manualRenderingFailed(String)
}

enum NativeTimelineTransportInjectedFailure: Error, Equatable {
    case hapticPreparation
    case hapticStart
    case gainUnitInstantiation
    case conventionalAttach(AudioCueID)
}

struct NativeRenderClockAnchor: Equatable, Sendable {
    let graphSampleEnd: Int64
    let hostTimeAtGraphSampleEnd: UInt64?
}

/// One writer (the source-node render callback) publishes sample and host
/// time as a seqlock-protected pair. A reader can therefore never combine the
/// newest graph sample with a host timestamp from an older render quantum.
final class NativeRenderClockStorage: @unchecked Sendable {
    let latestGraphSampleEnd = Atomic<Int64>(0)
    private let latestHostTimeAtGraphSampleEnd = Atomic<UInt64>(0)
    private let publicationSequence = Atomic<UInt64>(0)

    @inline(__always)
    func record(
        _ sample: Int64,
        hostTimeAtGraphSampleEnd: UInt64?
    ) {
        guard sample > latestGraphSampleEnd.load(ordering: .acquiring) else {
            return
        }
        var sequence = publicationSequence.load(ordering: .acquiring)
        if !sequence.isMultiple(of: 2) {
            sequence &+= 1
        }
        publicationSequence.store(sequence &+ 1, ordering: .releasing)
        latestHostTimeAtGraphSampleEnd.store(
            hostTimeAtGraphSampleEnd ?? 0,
            ordering: .releasing
        )
        latestGraphSampleEnd.store(sample, ordering: .releasing)
        publicationSequence.store(sequence &+ 2, ordering: .releasing)
    }

    @inline(__always)
    func loadCoherentAnchor(
        maximumAttempts: Int = 64
    ) -> NativeRenderClockAnchor? {
        guard maximumAttempts > 0 else { return nil }
        for _ in 0 ..< maximumAttempts {
            let before = publicationSequence.load(ordering: .acquiring)
            guard before.isMultiple(of: 2) else { continue }
            let sample = latestGraphSampleEnd.load(ordering: .acquiring)
            let rawHost = latestHostTimeAtGraphSampleEnd.load(ordering: .acquiring)
            let after = publicationSequence.load(ordering: .acquiring)
            guard before == after else { continue }
            return NativeRenderClockAnchor(
                graphSampleEnd: sample,
                hostTimeAtGraphSampleEnd: rawHost == 0 ? nil : rawHost
            )
        }
        return nil
    }

    func stallPublicationForTesting() {
        var sequence = publicationSequence.load(ordering: .acquiring)
        if sequence.isMultiple(of: 2) { sequence &+= 1 }
        publicationSequence.store(sequence, ordering: .releasing)
    }
}

/// Energy-bounded polling after an automatic boundary's host-time wake hint.
/// The render sample remains the sole authority: this state only selects when
/// the main actor checks it again.
struct NativeAutomaticBoundaryMonitorPollState: Sendable {
    enum Decision: Equatable, Sendable {
        case boundaryCrossed
        case sleep(nanoseconds: UInt64)
        case stallLimitReached
    }

    static let preciseIntervalNanoseconds: UInt64 = 2_000_000
    static let precisePollCount = 16
    static let maximumIntervalNanoseconds: UInt64 = 250_000_000
    /// Five seconds without one new rendered graph sample means the running
    /// graph can no longer substantiate the scheduled historical boundary.
    static let maximumNoProgressNanoseconds: UInt64 = 5_000_000_000

    private var pollCount = 0
    private var lastRenderedGraphSample: Int64?
    private var noProgressNanoseconds: UInt64 = 0

    mutating func observe(
        renderedGraphSample: Int64,
        boundaryGraphSample: Int64
    ) -> Decision {
        if renderedGraphSample >= boundaryGraphSample {
            return .boundaryCrossed
        }
        if let lastRenderedGraphSample,
           renderedGraphSample > lastRenderedGraphSample {
            noProgressNanoseconds = 0
        }
        if let lastRenderedGraphSample {
            self.lastRenderedGraphSample = max(
                lastRenderedGraphSample,
                renderedGraphSample
            )
        } else {
            lastRenderedGraphSample = renderedGraphSample
        }
        guard noProgressNanoseconds
            < Self.maximumNoProgressNanoseconds else {
            return .stallLimitReached
        }

        let preferredDelay: UInt64
        if pollCount < Self.precisePollCount {
            preferredDelay = Self.preciseIntervalNanoseconds
        } else {
            let backoffStep = min(
                pollCount - Self.precisePollCount + 1,
                7
            )
            preferredDelay = min(
                Self.preciseIntervalNanoseconds << backoffStep,
                Self.maximumIntervalNanoseconds
            )
        }
        pollCount += 1
        let remaining = Self.maximumNoProgressNanoseconds
            - noProgressNanoseconds
        let delay = min(preferredDelay, remaining)
        noProgressNanoseconds += delay
        return .sleep(nanoseconds: delay)
    }
}

public enum NativeAudioCursorFeedError: Error, Equatable, Sendable {
    case unavailable
    case renderClockUnavailable
}

/// One raw transport capture. `snapshot` and `renderedGraphSample` are derived
/// from the same source-render clock publication. `mappingGeneration` names
/// the exact logical mapping used for that projection; a consumer must not
/// interpret it through a runtime template belonging to another generation.
public struct NativeAudioCursorFeedCapture: Equatable, Sendable {
    public let snapshot: NativeTimelineTransportSnapshot
    public let renderedGraphSample: Int64
    public let mappingGeneration: UInt64

    public init(
        snapshot: NativeTimelineTransportSnapshot,
        renderedGraphSample: Int64,
        mappingGeneration: UInt64
    ) {
        self.snapshot = snapshot
        self.renderedGraphSample = renderedGraphSample
        self.mappingGeneration = mappingGeneration
    }
}

public struct NativeAudioCursorFeed: Sendable {
    public typealias Capture = @Sendable () throws
        -> NativeAudioCursorFeedCapture

    private let captureOperation: Capture

    public init(capture: @escaping Capture) {
        captureOperation = capture
    }

    public func capture() throws -> NativeAudioCursorFeedCapture {
        try captureOperation()
    }
}

public struct NativeAudioCursorMappingDescriptor: Equatable, Sendable {
    public let generation: UInt64
    public let graphBoundarySample: Int64
    public let snapshotAtBoundary: NativeTimelineTransportSnapshot

    public init(
        generation: UInt64,
        graphBoundarySample: Int64,
        snapshotAtBoundary: NativeTimelineTransportSnapshot
    ) {
        self.generation = generation
        self.graphBoundarySample = graphBoundarySample
        self.snapshotAtBoundary = snapshotAtBoundary
    }
}

/// The raw native half of active durability protection. Journey supplies the
/// generation-bound runtime projection before adapting this to an
/// `ActiveAudioCursorBinding`; the transport never reaches back to MainActor
/// from the worker feed.
public struct NativeAudioCursorBinding: Sendable {
    public let feed: NativeAudioCursorFeed
    public let gateToken: NativeAudioDurabilityGate.EpochToken
    public let renderedGraphSampleRate: Double
    public let mappingDescriptors: [NativeAudioCursorMappingDescriptor]
    public var currentMappingGeneration: UInt64 {
        mappingDescriptors[0].generation
    }
    public var scheduledMappingGenerations: [UInt64] {
        mappingDescriptors.dropFirst().map(\.generation)
    }
    public var scheduledMappingGeneration: UInt64? {
        mappingDescriptors.dropFirst().first?.generation
    }
    public var latestPublishedMappingGeneration: UInt64 {
        mappingDescriptors.map(\.generation).max() ?? currentMappingGeneration
    }

    public init(
        feed: NativeAudioCursorFeed,
        gateToken: NativeAudioDurabilityGate.EpochToken,
        renderedGraphSampleRate: Double,
        mappingDescriptors: [NativeAudioCursorMappingDescriptor]
    ) {
        precondition(!mappingDescriptors.isEmpty)
        self.feed = feed
        self.gateToken = gateToken
        self.renderedGraphSampleRate = renderedGraphSampleRate
        self.mappingDescriptors = mappingDescriptors
    }
}

private struct NativeAudioCursorFeedBasis: Sendable {
    let timelineID: AudioTimelineID
    let cursorSample: Int64
    let loopIteration: UInt64
    let repetition: ResponsiveAudioPlaybackRepetition
    let endSample: Int64
    let graphBaseSample: Int64
    let isPlaying: Bool
    let mappingGeneration: UInt64

    var descriptor: NativeAudioCursorMappingDescriptor {
        NativeAudioCursorMappingDescriptor(
            generation: mappingGeneration,
            graphBoundarySample: graphBaseSample,
            snapshotAtBoundary: capture(
                atRenderedGraphSample: graphBaseSample
            ).snapshot
        )
    }

    func capture(atRenderedGraphSample renderedGraphSample: Int64)
        -> NativeAudioCursorFeedCapture {
        let elapsedResult = renderedGraphSample.subtractingReportingOverflow(
            graphBaseSample
        )
        let elapsed = elapsedResult.overflow
            ? 0
            : max(0, elapsedResult.partialValue)
        let position: (cursor: Int64, iteration: UInt64)
        switch repetition {
        case .once:
            let advanced = cursorSample.addingReportingOverflow(elapsed)
            position = (
                advanced.overflow
                    ? endSample
                    : min(endSample, advanced.partialValue),
                0
            )
        case let .loop(_, durationSamples):
            guard durationSamples > 0 else {
                position = (cursorSample, loopIteration)
                break
            }
            let relative = UInt64(cursorSample).addingReportingOverflow(
                UInt64(elapsed)
            )
            guard !relative.overflow else {
                position = (Int64.max % durationSamples, .max)
                break
            }
            let addedIterations = relative.partialValue
                / UInt64(durationSamples)
            let advancedIteration = loopIteration.addingReportingOverflow(
                addedIterations
            )
            position = (
                Int64(relative.partialValue % UInt64(durationSamples)),
                advancedIteration.overflow
                    ? .max
                    : advancedIteration.partialValue
            )
        }
        return NativeAudioCursorFeedCapture(
            snapshot: NativeTimelineTransportSnapshot(
                timelineID: timelineID,
                cursorSample: position.cursor,
                loopIteration: position.iteration,
                isPlaying: isPlaying
            ),
            renderedGraphSample: renderedGraphSample,
            mappingGeneration: mappingGeneration
        )
    }
}

/// MainActor publishes immutable mappings. The worker takes one locked
/// publication, then reads only that publication's seqlock-protected source
/// clock. Rebuilds can therefore never pair an old plan with a new clock.
private final class NativeAudioCursorFeedStorage: @unchecked Sendable {
    private struct Publication: Sendable {
        let identity: UInt64
        let clock: NativeRenderClockStorage
        let mappings: [NativeAudioCursorFeedBasis]
    }

    private let lock = NSLock()
    private var nextIdentity: UInt64 = 0
    private var nextMappingGeneration: UInt64 = 0
    private var publication: Publication?

    func publishCurrent(
        clock: NativeRenderClockStorage,
        timelineID: AudioTimelineID,
        cursorSample: Int64,
        loopIteration: UInt64,
        repetition: ResponsiveAudioPlaybackRepetition,
        endSample: Int64,
        graphBaseSample: Int64,
        isPlaying: Bool
    ) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let generation = issueMappingGenerationLocked()
        publication = Publication(
            identity: issueIdentityLocked(),
            clock: clock,
            mappings: [NativeAudioCursorFeedBasis(
                timelineID: timelineID,
                cursorSample: cursorSample,
                loopIteration: loopIteration,
                repetition: repetition,
                endSample: endSample,
                graphBaseSample: graphBaseSample,
                isPlaying: isPlaying,
                mappingGeneration: generation
            )]
        )
        return generation
    }

    func publishScheduled(
        clock: NativeRenderClockStorage,
        timelineID: AudioTimelineID,
        cursorSample: Int64,
        loopIteration: UInt64,
        repetition: ResponsiveAudioPlaybackRepetition,
        endSample: Int64,
        graphBoundarySample: Int64,
        isPlaying: Bool
    ) throws -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard let current = publication,
              current.clock === clock,
              let currentBasis = current.mappings.first,
              graphBoundarySample > currentBasis.graphBaseSample else {
            throw NativeAudioCursorFeedError.unavailable
        }
        let generation = issueMappingGenerationLocked()
        let scheduled = NativeAudioCursorFeedBasis(
            timelineID: timelineID,
            cursorSample: cursorSample,
            loopIteration: loopIteration,
            repetition: repetition,
            endSample: endSample,
            graphBaseSample: graphBoundarySample,
            isPlaying: isPlaying,
            mappingGeneration: generation
        )
        var mappings = current.mappings.filter {
            $0.graphBaseSample != graphBoundarySample
        }
        mappings.append(scheduled)
        mappings.sort {
            if $0.graphBaseSample != $1.graphBaseSample {
                return $0.graphBaseSample < $1.graphBaseSample
            }
            return $0.mappingGeneration < $1.mappingGeneration
        }
        publication = Publication(
            identity: issueIdentityLocked(),
            clock: clock,
            mappings: mappings
        )
        return generation
    }

    func promoteScheduled(mappingGeneration: UInt64?) {
        guard let mappingGeneration else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let current = publication,
              let promotedIndex = current.mappings.firstIndex(where: {
                  $0.mappingGeneration == mappingGeneration
              }), promotedIndex > 0 else { return }
        publication = Publication(
            identity: current.identity,
            clock: current.clock,
            mappings: Array(current.mappings[promotedIndex...])
        )
    }

    func clearScheduled(mappingGeneration: UInt64?) {
        guard let mappingGeneration else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let current = publication,
              current.mappings.dropFirst().contains(where: {
                  $0.mappingGeneration == mappingGeneration
              }) else { return }
        publication = Publication(
            identity: issueIdentityLocked(),
            clock: current.clock,
            mappings: current.mappings.filter {
                $0.mappingGeneration != mappingGeneration
            }
        )
    }

    func clear() {
        lock.lock()
        publication = nil
        _ = issueIdentityLocked()
        lock.unlock()
    }

    func feed() -> NativeAudioCursorFeed {
        NativeAudioCursorFeed { [weak self] in
            guard let self else {
                throw NativeAudioCursorFeedError.unavailable
            }
            return try self.capture()
        }
    }

    func mappingDescriptors() -> [NativeAudioCursorMappingDescriptor]? {
        lock.lock()
        defer { lock.unlock() }
        guard let publication,
              !publication.mappings.isEmpty else { return nil }
        return publication.mappings.map(\.descriptor)
    }

    private func capture() throws -> NativeAudioCursorFeedCapture {
        for _ in 0 ..< 64 {
            let selected: Publication
            lock.lock()
            guard let currentPublication = publication else {
                lock.unlock()
                throw NativeAudioCursorFeedError.unavailable
            }
            selected = currentPublication
            lock.unlock()

            guard let anchor = selected.clock.loadCoherentAnchor() else {
                throw NativeAudioCursorFeedError.renderClockUnavailable
            }
            let renderedGraphSample = max(
                anchor.graphSampleEnd,
                selected.mappings[0].graphBaseSample
            )
            let basis = selected.mappings.last(where: {
                renderedGraphSample >= $0.graphBaseSample
            }) ?? selected.mappings[0]

            // Retry a publication race internally. A worker sees either one
            // coherent old mapping or one coherent new mapping, never a
            // transient capture failure merely because MainActor committed a
            // transition at the same instant.
            lock.lock()
            let isStillCurrent = publication?.identity == selected.identity
            lock.unlock()
            if isStillCurrent {
                return basis.capture(
                    atRenderedGraphSample: renderedGraphSample
                )
            }
        }
        throw NativeAudioCursorFeedError.unavailable
    }

    private func issueIdentityLocked() -> UInt64 {
        nextIdentity &+= 1
        if nextIdentity == 0 { nextIdentity = 1 }
        return nextIdentity
    }

    private func issueMappingGenerationLocked() -> UInt64 {
        nextMappingGeneration &+= 1
        if nextMappingGeneration == 0 { nextMappingGeneration = 1 }
        return nextMappingGeneration
    }
}

private func makeNativeRenderClockSource(
    format: AVAudioFormat,
    storage: NativeRenderClockStorage
) -> AVAudioSourceNode {
    AVAudioSourceNode(format: format) {
        _, timestamp, frameCount, outputData in
        let sample = timestamp.pointee.mSampleTime
        guard timestamp.pointee.mFlags.contains(.sampleTimeValid),
              sample.isFinite,
              sample >= 0,
              sample.rounded(.towardZero) == sample,
              let exactSample = Int64(exactly: sample) else {
            return kAudioUnitErr_InvalidPropertyValue
        }
        let end = exactSample.addingReportingOverflow(Int64(frameCount))
        guard !end.overflow else {
            return kAudioUnitErr_InvalidPropertyValue
        }
        let byteCount = Int(frameCount) * MemoryLayout<Float>.size
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        for index in buffers.indices {
            guard let data = buffers[index].mData,
                  Int(buffers[index].mDataByteSize) >= byteCount else {
                return kAudioUnitErr_InvalidPropertyValue
            }
            memset(data, 0, byteCount)
            buffers[index].mDataByteSize = UInt32(byteCount)
        }
        let hostTimeAtEnd: UInt64?
        if timestamp.pointee.mFlags.contains(.hostTimeValid) {
            let duration = Double(frameCount) / format.sampleRate
            let hostDuration = AVAudioTime.hostTime(forSeconds: duration)
            let endHost = timestamp.pointee.mHostTime.addingReportingOverflow(
                hostDuration
            )
            guard !endHost.overflow else {
                return kAudioUnitErr_InvalidPropertyValue
            }
            hostTimeAtEnd = endHost.partialValue
        } else {
            hostTimeAtEnd = nil
        }
        storage.record(
            end.partialValue,
            hostTimeAtGraphSampleEnd: hostTimeAtEnd
        )
        return noErr
    }
}

struct NativeAudioRouteFormat: Equatable, Sendable {
    let sessionSampleRate: Double
    let outputSampleRate: Double
}

@MainActor
protocol NativeAudioSessionLease: AnyObject {
    var routeFormat: NativeAudioRouteFormat { get }
    func release()
}

@MainActor
protocol NativeAudioSessionLeasing: AnyObject {
    func acquire(
        preferredSampleRate: Double,
        engine: AVAudioEngine
    ) throws -> any NativeAudioSessionLease
}

@MainActor
protocol NativeSystemAudioSessionControlling: AnyObject {
    var sampleRate: Double { get }
    func configureForPlayback(preferredSampleRate: Double) throws
    func activate() throws
    func deactivateNotifyingOthers() throws
}

@MainActor
private final class AVFoundationSystemAudioSessionController:
    NativeSystemAudioSessionControlling {
    private let session = AVAudioSession.sharedInstance()

    var sampleRate: Double { session.sampleRate }

    func configureForPlayback(preferredSampleRate: Double) throws {
        try session.setCategory(
            .playback,
            mode: .default,
            options: [.allowAirPlay, .allowBluetoothA2DP]
        )
        try session.setPreferredSampleRate(preferredSampleRate)
    }

    func activate() throws {
        try session.setActive(true)
    }

    func deactivateNotifyingOthers() throws {
        try session.setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }
}

@MainActor
final class SystemNativeAudioSessionLeaseCoordinator:
    NativeAudioSessionLeasing {
    static let shared = SystemNativeAudioSessionLeaseCoordinator()

    private enum SessionOwnership {
        case inactive
        case active(
            preferredSampleRate: Double,
            routeFormat: NativeAudioRouteFormat,
            leaseCount: Int
        )
        /// A mutating session operation failed and rollback could not prove
        /// that the process-wide session is inactive. No new graph may be
        /// admitted until a later deactivation succeeds.
        case cleanupRequired
    }

    private final class Lease: NativeAudioSessionLease {
        let routeFormat: NativeAudioRouteFormat
        private var coordinator: SystemNativeAudioSessionLeaseCoordinator?

        init(
            routeFormat: NativeAudioRouteFormat,
            coordinator: SystemNativeAudioSessionLeaseCoordinator
        ) {
            self.routeFormat = routeFormat
            self.coordinator = coordinator
        }

        func release() {
            guard let coordinator else { return }
            self.coordinator = nil
            coordinator.releaseOne()
        }

        isolated deinit {
            release()
        }
    }

    private let sessionController: any NativeSystemAudioSessionControlling
    private let outputSampleRate: (AVAudioEngine) -> Double
    private var ownership: SessionOwnership = .inactive
    var leaseCountForTesting: Int {
        guard case let .active(_, _, leaseCount) = ownership else { return 0 }
        return leaseCount
    }
    var cleanupIsRequiredForTesting: Bool {
        guard case .cleanupRequired = ownership else { return false }
        return true
    }

    init(
        sessionController: any NativeSystemAudioSessionControlling =
            AVFoundationSystemAudioSessionController(),
        outputSampleRate: @escaping (AVAudioEngine) -> Double = {
            $0.outputNode.inputFormat(forBus: 0).sampleRate
        }
    ) {
        self.sessionController = sessionController
        self.outputSampleRate = outputSampleRate
    }

    func acquire(
        preferredSampleRate: Double,
        engine: AVAudioEngine
    ) throws -> any NativeAudioSessionLease {
        guard preferredSampleRate.isFinite, preferredSampleRate > 0 else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        if case .cleanupRequired = ownership {
            do {
                try sessionController.deactivateNotifyingOthers()
                ownership = .inactive
            } catch {
                throw error
            }
        }

        if case let .active(activePreferredRate, activeRoute, leaseCount) = ownership {
            guard sampleRatesAreCompatible(
                preferredSampleRate,
                activePreferredRate
            ) else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            let sessionRate = sessionController.sampleRate
            let outputRate = outputSampleRate(engine)
            guard sessionRate.isFinite, sessionRate > 0,
                  outputRate.isFinite, outputRate > 0,
                  sampleRatesAreCompatible(
                      sessionRate,
                      activeRoute.sessionSampleRate
                  ), sampleRatesAreCompatible(
                      outputRate,
                      activeRoute.outputSampleRate
                  ) else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            let routeFormat = NativeAudioRouteFormat(
                sessionSampleRate: sessionRate,
                outputSampleRate: outputRate
            )
            ownership = .active(
                preferredSampleRate: activePreferredRate,
                routeFormat: activeRoute,
                leaseCount: leaseCount + 1
            )
            return Lease(routeFormat: routeFormat, coordinator: self)
        }

        do {
            try sessionController.configureForPlayback(
                preferredSampleRate: preferredSampleRate
            )
            try sessionController.activate()
            let sessionRate = sessionController.sampleRate
            let outputRate = outputSampleRate(engine)
            guard sessionRate.isFinite, sessionRate > 0,
                  outputRate.isFinite, outputRate > 0 else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            let routeFormat = NativeAudioRouteFormat(
                sessionSampleRate: sessionRate,
                outputSampleRate: outputRate
            )
            ownership = .active(
                preferredSampleRate: preferredSampleRate,
                routeFormat: routeFormat,
                leaseCount: 1
            )
            return Lease(routeFormat: routeFormat, coordinator: self)
        } catch {
            let originalError = error
            do {
                try sessionController.deactivateNotifyingOthers()
                ownership = .inactive
            } catch {
                ownership = .cleanupRequired
            }
            throw originalError
        }
    }

    private func sampleRatesAreCompatible(
        _ lhs: Double,
        _ rhs: Double
    ) -> Bool {
        abs(lhs - rhs) <= 0.5
    }

    private func releaseOne() {
        guard case let .active(preferredRate, routeFormat, leaseCount) = ownership,
              leaseCount > 0 else { return }
        guard leaseCount == 1 else {
            ownership = .active(
                preferredSampleRate: preferredRate,
                routeFormat: routeFormat,
                leaseCount: leaseCount - 1
            )
            return
        }
        ownership = .cleanupRequired
        do {
            try sessionController.deactivateNotifyingOthers()
            ownership = .inactive
        } catch {
            // Keep cleanupRequired. A later acquisition must prove that the
            // process-wide session is inactive before configuring another graph.
        }
    }
}

struct NativeTimelineHapticBoundary: Equatable, Sendable {
    let graphSample: AUEventSampleTime
    let hostTime: UInt64?
    let sampleRate: Int
}

enum NativeTimelineHapticRuntimeStatus: Equatable, Sendable {
    case available
    case requiresExplicitResume
    case exhausted
    case failedClosed
}

struct NativeTimelineHapticRuntimeContext {
    let boundary: NativeTimelineHapticBoundary
    let currentRenderAnchor: @MainActor () -> NativeRenderClockAnchor?
    let recoveryIsAuthorized: @MainActor () -> Bool
    let status: @MainActor (NativeTimelineHapticRuntimeStatus) -> Void
}

struct NativeTimelineHapticPulseSchedule: Equatable, Sendable {
    let haptic: ScheduledHaptic
    let absoluteGraphSample: Int64
    let scheduledHostTime: UInt64?
}

struct NativeTimelineHapticRecoveryPlan: Equatable, Sendable {
    let boundary: NativeTimelineHapticBoundary
    let haptics: [ScheduledHaptic]
    let pulseSchedule: [NativeTimelineHapticPulseSchedule]
}

enum NativeTimelineHapticRecoveryPlanner {
    static func initialPulseSchedule(
        haptics: [ScheduledHaptic],
        boundary: NativeTimelineHapticBoundary
    ) throws -> [NativeTimelineHapticPulseSchedule] {
        var schedule: [NativeTimelineHapticPulseSchedule] = []
        schedule.reserveCapacity(haptics.count)
        for haptic in haptics {
            let graphSample = Int64(boundary.graphSample)
                .addingReportingOverflow(haptic.timelineStartOffset)
            guard !graphSample.overflow else {
                throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
            }
            let scheduledHostTime: UInt64?
            if let boundaryHostTime = boundary.hostTime {
                scheduledHostTime = try addingHostTime(
                    addingSamples: haptic.timelineStartOffset,
                    to: boundaryHostTime,
                    sampleRate: boundary.sampleRate
                )
            } else {
                scheduledHostTime = nil
            }
            schedule.append(NativeTimelineHapticPulseSchedule(
                haptic: haptic,
                absoluteGraphSample: graphSample.partialValue,
                scheduledHostTime: scheduledHostTime
            ))
        }
        return schedule
    }

    static func makeRecoveryPlan(
        pulseSchedule: [NativeTimelineHapticPulseSchedule],
        anchor: NativeRenderClockAnchor,
        observedHostTime: UInt64,
        sampleRate: Int,
        scheduledStopBoundary: NativeTimelineHapticBoundary?,
        minimumLeadSamples: Int64? = nil
    ) throws -> NativeTimelineHapticRecoveryPlan? {
        guard sampleRate > 0,
              let anchorHostTime = anchor.hostTimeAtGraphSampleEnd else {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
        let lead = minimumLeadSamples ?? Int64(max(512, sampleRate / 10))
        let recoveryGraphSample = anchor.graphSampleEnd
            .addingReportingOverflow(lead)
        guard lead >= 0, !recoveryGraphSample.overflow else {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
        let recoveryHostTime = try addingHostTime(
            addingSamples: lead,
            to: anchorHostTime,
            sampleRate: sampleRate
        )
        let boundary = NativeTimelineHapticBoundary(
            graphSample: AUEventSampleTime(recoveryGraphSample.partialValue),
            hostTime: recoveryHostTime,
            sampleRate: sampleRate
        )
        var rebased: [ScheduledHaptic] = []
        var surviving: [NativeTimelineHapticPulseSchedule] = []
        for pulse in pulseSchedule {
            guard pulse.absoluteGraphSample >= recoveryGraphSample.partialValue,
                  pulse.scheduledHostTime.map({ $0 > observedHostTime }) ?? true,
                  scheduledStopBoundary.map({
                      pulse.absoluteGraphSample < Int64($0.graphSample)
                  }) ?? true else {
                continue
            }
            let offset = pulse.absoluteGraphSample
                .subtractingReportingOverflow(recoveryGraphSample.partialValue)
            guard !offset.overflow, offset.partialValue >= 0 else {
                throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
            }
            let haptic = ScheduledHaptic(
                timelineStartOffset: offset.partialValue,
                semantic: pulse.haptic.semantic,
                intensity: pulse.haptic.intensity,
                sharpness: pulse.haptic.sharpness
            )
            let nextHostTime = try addingHostTime(
                addingSamples: offset.partialValue,
                to: recoveryHostTime,
                sampleRate: sampleRate
            )
            rebased.append(haptic)
            surviving.append(NativeTimelineHapticPulseSchedule(
                haptic: pulse.haptic,
                absoluteGraphSample: pulse.absoluteGraphSample,
                scheduledHostTime: nextHostTime
            ))
        }
        guard !rebased.isEmpty else { return nil }
        return NativeTimelineHapticRecoveryPlan(
            boundary: boundary,
            haptics: rebased,
            pulseSchedule: surviving
        )
    }

    private static func addingHostTime(
        addingSamples samples: Int64,
        to hostTime: UInt64,
        sampleRate: Int
    ) throws -> UInt64 {
        guard samples >= 0, sampleRate > 0 else {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
        let seconds = Double(samples) / Double(sampleRate)
        let delta = AVAudioTime.hostTime(forSeconds: seconds)
        let result = hostTime.addingReportingOverflow(delta)
        guard !result.overflow else {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
        return result.partialValue
    }
}

final class NativeTimelineHapticCallbackFence: @unchecked Sendable {
    private let generation = Atomic<UInt64>(0)

    func issue() -> UInt64 {
        var original = generation.load(ordering: .acquiring)
        while true {
            let desired = original &+ 1
            let result = generation.compareExchange(
                expected: original,
                desired: desired,
                ordering: .acquiringAndReleasing
            )
            if result.exchanged { return desired }
            original = result.original
        }
    }

    func invalidate() { _ = issue() }

    func isCurrent(_ value: UInt64) -> Bool {
        generation.load(ordering: .acquiring) == value
    }
}

protocol NativeTimelineHapticPlayback: AnyObject {}

@MainActor
protocol NativeTimelineHapticScheduling: AnyObject {
    func prepare(
        haptics: [ScheduledHaptic],
        sampleRate: Int
    ) throws -> (any NativeTimelineHapticPlayback)?
    func start(
        _ playback: any NativeTimelineHapticPlayback,
        context: NativeTimelineHapticRuntimeContext,
        enabled: Bool
    ) throws
    func scheduleStop(
        _ playback: any NativeTimelineHapticPlayback,
        at boundary: NativeTimelineHapticBoundary
    ) throws
    func stopImmediately(_ playback: any NativeTimelineHapticPlayback)
    func setEnabled(
        _ enabled: Bool,
        for playback: any NativeTimelineHapticPlayback
    ) throws
}

@MainActor
private final class CoreHapticsTimelinePlayback: NativeTimelineHapticPlayback {
    private enum State {
        case prepared
        case active
        case waitingForReset
        case requiresExplicitResume
        case exhausted
        case failedClosed
        case stopped
    }

    let engine: CHHapticEngine
    let authoredHaptics: [ScheduledHaptic]
    let sampleRate: Int
    var player: (any CHHapticAdvancedPatternPlayer)?
    var pulseSchedule: [NativeTimelineHapticPulseSchedule] = []
    var scheduledStopBoundary: NativeTimelineHapticBoundary?
    var runtimeContext: NativeTimelineHapticRuntimeContext?
    var enabled = true
    private var state: State = .prepared
    private let callbackFence = NativeTimelineHapticCallbackFence()

    init(
        engine: CHHapticEngine,
        player: any CHHapticAdvancedPatternPlayer,
        haptics: [ScheduledHaptic],
        sampleRate: Int
    ) {
        self.engine = engine
        self.player = player
        authoredHaptics = haptics
        self.sampleRate = sampleRate
    }

    func installHandlers() {
        engine.resetHandler = { [weak self] in
            guard let self else { return }
            let ticket = callbackFence.issue()
            let observedHostTime = mach_absolute_time()
            Task { @MainActor [weak self] in
                guard let self, callbackFence.isCurrent(ticket) else { return }
                recoverAfterReset(observedHostTime: observedHostTime)
            }
        }
        engine.stoppedHandler = { [weak self] reason in
            guard let self else { return }
            let ticket = callbackFence.issue()
            let observedHostTime = mach_absolute_time()
            Task { @MainActor [weak self] in
                guard let self, callbackFence.isCurrent(ticket) else { return }
                handleStopped(reason, observedHostTime: observedHostTime)
            }
        }
    }

    func begin(
        context: NativeTimelineHapticRuntimeContext,
        enabled: Bool
    ) throws {
        self.runtimeContext = context
        self.enabled = enabled
        pulseSchedule = try NativeTimelineHapticRecoveryPlanner
            .initialPulseSchedule(
                haptics: authoredHaptics,
                boundary: context.boundary
            )
        guard let player else {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
        try engine.start()
        player.isMuted = !enabled
        try player.start(
            atTime: scheduledEngineTime(for: context.boundary)
        )
        state = .active
        context.status(.available)
    }

    func scheduleStop(at boundary: NativeTimelineHapticBoundary) throws {
        scheduledStopBoundary = boundary
        guard let player else { return }
        try player.stop(atTime: scheduledEngineTime(for: boundary))
    }

    func setEnabled(_ enabled: Bool) throws {
        self.enabled = enabled
        guard let player else { return }
        player.isMuted = !enabled
        try player.sendParameters(
            [
                CHHapticDynamicParameter(
                    parameterID: .hapticIntensityControl,
                    value: enabled ? 1 : 0,
                    relativeTime: 0
                ),
            ],
            atTime: CHHapticTimeImmediate
        )
    }

    func stopImmediately() {
        callbackFence.invalidate()
        state = .stopped
        engine.resetHandler = {}
        engine.stoppedHandler = { _ in }
        if let player {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
        player = nil
        engine.stop()
    }

    private func recoverAfterReset(observedHostTime: UInt64) {
        guard state != .stopped,
              state != .requiresExplicitResume,
              let runtimeContext,
              runtimeContext.recoveryIsAuthorized() else {
            return
        }
        player = nil
        do {
            for _ in 0 ..< 3 {
                guard let anchor = runtimeContext.currentRenderAnchor() else {
                    throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
                }
                guard let recovery = try NativeTimelineHapticRecoveryPlanner
                    .makeRecoveryPlan(
                        pulseSchedule: pulseSchedule,
                        anchor: anchor,
                        observedHostTime: max(
                            observedHostTime,
                            mach_absolute_time()
                        ),
                        sampleRate: sampleRate,
                        scheduledStopBoundary: scheduledStopBoundary
                    ) else {
                    engine.stop()
                    state = .exhausted
                    runtimeContext.status(.exhausted)
                    return
                }
                guard let hostTime = recovery.boundary.hostTime,
                      hostTime > mach_absolute_time() else { continue }
                try engine.start()
                let candidate = try makePlayer(haptics: recovery.haptics)
                candidate.isMuted = !enabled
                guard hostTime > mach_absolute_time() else {
                    try? candidate.stop(atTime: CHHapticTimeImmediate)
                    continue
                }
                try candidate.start(
                    atTime: scheduledEngineTime(for: recovery.boundary)
                )
                if let scheduledStopBoundary {
                    try candidate.stop(
                        atTime: scheduledEngineTime(for: scheduledStopBoundary)
                    )
                }
                player = candidate
                pulseSchedule = recovery.pulseSchedule
                state = .active
                runtimeContext.status(.available)
                return
            }
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        } catch {
            player = nil
            engine.stop()
            state = .failedClosed
            runtimeContext.status(.failedClosed)
        }
    }

    private func handleStopped(
        _ reason: CHHapticEngine.StoppedReason,
        observedHostTime: UInt64
    ) {
        guard state != .stopped, let runtimeContext else { return }
        player = nil
        switch reason {
        case .audioSessionInterrupt, .applicationSuspended:
            state = .requiresExplicitResume
            runtimeContext.status(.requiresExplicitResume)
        case .idleTimeout:
            recoverAfterReset(observedHostTime: observedHostTime)
        case .systemError:
            state = .waitingForReset
            runtimeContext.status(.failedClosed)
        default:
            state = .failedClosed
            runtimeContext.status(.failedClosed)
        }
    }

    private func makePlayer(
        haptics: [ScheduledHaptic]
    ) throws -> any CHHapticAdvancedPatternPlayer {
        let events = haptics.map { haptic in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(
                        parameterID: .hapticIntensity,
                        value: Float(haptic.intensity)
                    ),
                    CHHapticEventParameter(
                        parameterID: .hapticSharpness,
                        value: Float(haptic.sharpness)
                    ),
                ],
                relativeTime: Double(haptic.timelineStartOffset)
                    / Double(sampleRate)
            )
        }
        return try engine.makeAdvancedPlayer(
            with: CHHapticPattern(events: events, parameters: [])
        )
    }

    private func scheduledEngineTime(
        for boundary: NativeTimelineHapticBoundary
    ) -> TimeInterval {
        guard let hostTime = boundary.hostTime else {
            return CHHapticTimeImmediate
        }
        let now = mach_absolute_time()
        let remaining = hostTime > now ? hostTime - now : 0
        return engine.currentTime + AVAudioTime.seconds(forHostTime: remaining)
    }

    isolated deinit {
        stopImmediately()
    }
}

@MainActor
private final class CoreHapticsTimelineScheduler:
    NativeTimelineHapticScheduling {
    func prepare(
        haptics: [ScheduledHaptic],
        sampleRate: Int
    ) throws -> (any NativeTimelineHapticPlayback)? {
        guard !haptics.isEmpty,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return nil
        }
        do {
            let engine = try CHHapticEngine(
                audioSession: AVAudioSession.sharedInstance()
            )
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            let events = haptics.map { haptic in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: Float(haptic.intensity)
                        ),
                        CHHapticEventParameter(
                            parameterID: .hapticSharpness,
                            value: Float(haptic.sharpness)
                        ),
                    ],
                    relativeTime: Double(haptic.timelineStartOffset)
                        / Double(sampleRate)
                )
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let playback = CoreHapticsTimelinePlayback(
                engine: engine,
                player: try engine.makeAdvancedPlayer(with: pattern),
                haptics: haptics,
                sampleRate: sampleRate
            )
            playback.installHandlers()
            return playback
        } catch {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
    }

    func start(
        _ playback: any NativeTimelineHapticPlayback,
        context: NativeTimelineHapticRuntimeContext,
        enabled: Bool
    ) throws {
        guard let playback = playback as? CoreHapticsTimelinePlayback else {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
        do {
            try playback.begin(context: context, enabled: enabled)
        } catch {
            stopImmediately(playback)
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
    }

    func scheduleStop(
        _ playback: any NativeTimelineHapticPlayback,
        at boundary: NativeTimelineHapticBoundary
    ) throws {
        guard let playback = playback as? CoreHapticsTimelinePlayback else {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
        do {
            try playback.scheduleStop(at: boundary)
        } catch {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
    }

    func stopImmediately(_ playback: any NativeTimelineHapticPlayback) {
        guard let playback = playback as? CoreHapticsTimelinePlayback else {
            return
        }
        playback.stopImmediately()
    }

    func setEnabled(
        _ enabled: Bool,
        for playback: any NativeTimelineHapticPlayback
    ) throws {
        guard let playback = playback as? CoreHapticsTimelinePlayback else {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
        try playback.setEnabled(enabled)
    }
}

@MainActor
public final class NativeTimelineTransport: ResponsiveAudioTimelineTransport {
    private final class PreparedAudioSlice {
        let cueID: AudioCueID
        let role: AudioTrackRole
        let oneShotPlan: ScheduledAudioSlice?
        let file: AVAudioFile?
        var loopBuffers: [AVAudioPCMBuffer]
        let player: AVAudioPlayerNode
        let gainNode: SampleAccurateGainNode
        var startRenderSample: AUEventSampleTime?
        var muteRenderSample: AUEventSampleTime?
        var fadeRenderSample: AUEventSampleTime?
        var fadeDurationSamples: Int64?

        init(
            cueID: AudioCueID,
            role: AudioTrackRole,
            oneShotPlan: ScheduledAudioSlice?,
            file: AVAudioFile?,
            loopBuffers: [AVAudioPCMBuffer],
            player: AVAudioPlayerNode,
            gainNode: SampleAccurateGainNode
        ) {
            self.cueID = cueID
            self.role = role
            self.oneShotPlan = oneShotPlan
            self.file = file
            self.loopBuffers = loopBuffers
            self.player = player
            self.gainNode = gainNode
        }
    }

    private final class PreparedCommonLayer {
        let target: ResponsiveAudioCausalLayerPlaybackTarget
        let player: AVAudioPlayerNode
        let gainNode: SampleAccurateGainNode
        let buffers: [AVAudioPCMBuffer]
        var targetGain: Double
        var scheduleCount: Int
        var rampScheduleCount: Int
        var lastRampDurationSamples: Int64?
        var lastRampStartSample: AUEventSampleTime?

        init(
            target: ResponsiveAudioCausalLayerPlaybackTarget,
            player: AVAudioPlayerNode,
            gainNode: SampleAccurateGainNode,
            buffers: [AVAudioPCMBuffer],
            targetGain: Double,
            scheduleCount: Int,
            rampScheduleCount: Int = 0,
            lastRampDurationSamples: Int64? = nil,
            lastRampStartSample: AUEventSampleTime? = nil
        ) {
            self.target = target
            self.player = player
            self.gainNode = gainNode
            self.buffers = buffers
            self.targetGain = targetGain
            self.scheduleCount = scheduleCount
            self.rampScheduleCount = rampScheduleCount
            self.lastRampDurationSamples = lastRampDurationSamples
            self.lastRampStartSample = lastRampStartSample
        }
    }

    private struct ResolvedTimelineAssets {
        let metadata: [String: AudioAssetMetadata]
        let urls: [String: URL]
    }

    private struct TransitionBoundary {
        let graphSampleTime: AUEventSampleTime
        let startTime: AVAudioTime
        let leadSeconds: Double
        let projectedPosition: PlaybackPosition
    }

    private struct RenderClockObservation {
        let graphSampleTime: AVAudioFramePosition
        let hostTime: UInt64?
        let renderedOffset: Int64
    }

    private struct PendingPhysicalTransition {
        let graphSampleTime: AUEventSampleTime
        let startTime: AVAudioTime
        var candidateHaptics: (any NativeTimelineHapticPlayback)?
        var replacesConventionalBranch: Bool
        var cursorMappingGeneration: UInt64?
    }

    private struct AutomaticBoundaryRequest {
        let generation: UInt64
        let currentTimelineID: AudioTimelineID
        let currentAuthoredDurationSamples: Int64
        let successorPlan: ResponsiveAudioTimelineTransportPlan?
        let successorMetadata: [String: AudioAssetMetadata]
        let successorURLs: [String: URL]
        let handler: (ResponsiveAudioAutomaticBoundaryEvent) -> Void
    }

    private struct StagedAutomaticBoundary {
        let generation: UInt64
        var graphSampleTime: AUEventSampleTime
        var startTime: AVAudioTime
        var cursorMappingGeneration: UInt64?
        let successorTimelinePlan: TimelinePlaybackPlan?
        var successorSlices: [PreparedAudioSlice]
        var successorCommonLayers:
            [ResponsiveAudioMaterialLayerID: PreparedCommonLayer]
        var successorHaptics: (any NativeTimelineHapticPlayback)?
    }

    private struct CausalTargetChange {
        let layer: PreparedCommonLayer
        let targetGain: Double
    }

    private struct PlaybackPosition {
        let cursorSample: Int64
        let loopIteration: UInt64
        let loopDuration: Int64
    }

    public private(set) var state: NativeTimelineTransportState = .idle
    public private(set) var hapticsAreAvailable = false
    public private(set) var routingPolicy: ExperienceAudioRoutingPolicy

    private let engine = AVAudioEngine()
    private var timeline: AudioTimeline?
    private var plan: TimelinePlaybackPlan?
    private var responsivePlan: ResponsiveAudioTimelineTransportPlan?
    private var assetURLs: [String: URL] = [:]
    private var preparedAssetMetadata: [String: AudioAssetMetadata] = [:]
    private var assetResolver: (any OfflineAudioAssetResolving)?
    private var preparedSlices: [PreparedAudioSlice] = []
    private var retiredSlices: [PreparedAudioSlice] = []
    private var commonLayers: [ResponsiveAudioMaterialLayerID: PreparedCommonLayer] = [:]
    private var retiredCommonLayers: [PreparedCommonLayer] = []
    private var roleMixers: [String: AVAudioMixerNode] = [:]
    private var renderClockSource: AVAudioSourceNode?
    private var renderClockStorage = NativeRenderClockStorage()
    private var renderClockBaseGraphSampleTime: AVAudioFramePosition = 0
    private let audioDurabilityGate = NativeAudioDurabilityGate()
    private var audioDurabilityEpoch: NativeAudioDurabilityGate.EpochToken?
    private let audioCursorFeedStorage = NativeAudioCursorFeedStorage()
    private var pendingPhysicalTransition: PendingPhysicalTransition?
    private var needsRebuildOnPlay = false
    private var hapticPlayback: (any NativeTimelineHapticPlayback)?
    private let hapticScheduler: any NativeTimelineHapticScheduling
    private let audioSessionLeaser: any NativeAudioSessionLeasing
    private var audioSessionLease: (any NativeAudioSessionLease)?
    private var activeRouteFormat: NativeAudioRouteFormat?
    private var graphRouteFormatAtLastRebuild: NativeAudioRouteFormat?
    private var outgoingTailGeneration: UInt64 = 0
    private var activeOutgoingTailGeneration: UInt64?
    private weak var activeOutgoingTail: ResponsiveAudioOutgoingTail?
    private var automaticBoundaryGeneration: UInt64 = 0
    private var automaticBoundaryRequest: AutomaticBoundaryRequest?
    private var stagedAutomaticBoundary: StagedAutomaticBoundary?
    private var automaticBoundaryTask: Task<Void, Never>?
    private var currentGraphStartTime: AVAudioTime?
    private let performanceRecorder: (any PerformanceRecording)?

    private static let initialDurabilitySampleBudget: Int64 = 12_000

    // Narrow fault/clock controls used only by @testable native regressions.
    private var renderedSampleOffsetOverrideForTesting: Int64?
    private var pauseQuiescenceHookForTesting: (() -> Void)?
#if DEBUG
    private var pauseCompletionFaultForTesting:
        ((NativeTimelineTransportSnapshot) throws -> Void)?
    private var relinquishPreparationFaultForTesting: (() throws -> Void)?
    private var clearsRenderedSampleOffsetAfterNextPauseForTesting = false
#endif
    private var failNextHapticPreparationForTesting = false
    private var failNextHapticStartForTesting = false
    private var failNextGainUnitInstantiationForTesting = false
    private var failConventionalAttachCueForTesting: AudioCueID?
    private var lastTransitionBoundaryForTesting: AUEventSampleTime?

    public init(
        preferences: ExperiencePreferences = .standard,
        performanceRecorder: (any PerformanceRecording)? =
            PerformanceCaptureRuntime.shared.recorder
    ) {
        routingPolicy = ExperienceAudioRoutingPolicy(preferences: preferences)
        self.performanceRecorder = performanceRecorder
        hapticScheduler = CoreHapticsTimelineScheduler()
        audioSessionLeaser = SystemNativeAudioSessionLeaseCoordinator.shared
    }

    init(
        preferences: ExperiencePreferences = .standard,
        performanceRecorder: (any PerformanceRecording)? = nil,
        hapticScheduler: any NativeTimelineHapticScheduling,
        audioSessionLeaser: any NativeAudioSessionLeasing =
            SystemNativeAudioSessionLeaseCoordinator.shared
    ) {
        routingPolicy = ExperienceAudioRoutingPolicy(preferences: preferences)
        self.performanceRecorder = performanceRecorder
        self.hapticScheduler = hapticScheduler
        self.audioSessionLeaser = audioSessionLeaser
    }

    isolated deinit {
        automaticBoundaryTask?.cancel()
        beginAudioDurabilityStop()
        engine.stop()
        endAudioDurabilityEpochAfterEngineDrain()
        stopCurrentHaptics()
        audioSessionLease?.release()
        audioSessionLease = nil
    }

    /// Changes only output routing. Prepared players, the authored plan and
    /// the sample clock stay in place, so applying preferences cannot start,
    /// stop, rewind or advance historical playback.
    public func applyPreferences(_ preferences: ExperiencePreferences) {
        routingPolicy = ExperienceAudioRoutingPolicy(preferences: preferences)
        applyRoleMixerVolumes()
        guard state == .playing else { return }
        applyTimelineHapticPreferenceFailClosed()
    }

    public func prepare(
        timeline: AudioTimeline,
        cursorSample: Int64,
        resolver: any OfflineAudioAssetResolving
    ) throws {
        try prepareResponsiveAudio(
            plan: ResponsiveAudioTimelineTransportPlan(
                timeline: timeline,
                cursorSample: cursorSample,
                loopIteration: 0,
                repetition: .once,
                causalMix: nil
            ),
            resolver: resolver
        )
    }

    public func prepareResponsiveAudio(
        plan responsivePlan: ResponsiveAudioTimelineTransportPlan,
        resolver: any OfflineAudioAssetResolving
    ) throws {
        stop(clearTimeline: true)
        assetResolver = resolver
        self.responsivePlan = responsivePlan
        let timeline = responsivePlan.timeline
        var metadata: [String: AudioAssetMetadata] = [:]
        var urls: [String: URL] = [:]
        for event in timeline.events where event.role != .silence {
            guard let path = event.assetPath else {
                throw NativeTimelineTransportError.audioFileCouldNotOpen(event.cueID.rawValue)
            }
            if metadata[path] != nil { continue }
            let url = try resolver.url(for: path)
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: url)
            } catch {
                throw NativeTimelineTransportError.audioFileCouldNotOpen(path)
            }
            let sampleRate = Int(file.processingFormat.sampleRate.rounded())
            let channelCount = Int(file.processingFormat.channelCount)
            guard sampleRate > 0, file.length >= 0, channelCount > 0 else {
                throw NativeTimelineTransportError.unsupportedAudioFormat(path)
            }
            metadata[path] = AudioAssetMetadata(
                path: path,
                sampleRate: sampleRate,
                frameCount: file.length,
                channelCount: channelCount
            )
            urls[path] = url
        }

        self.timeline = timeline
        assetURLs = urls
        preparedAssetMetadata = metadata
        if engine.manualRenderingMode == .offline {
            try rebuild(at: responsivePlan.cursorSample, metadata: metadata)
            needsRebuildOnPlay = false
        } else {
            // Metadata is preflighted once, but no large loop buffer or audio
            // node is built against a provisional route. The sole realtime
            // graph build follows session activation in play().
            plan = try TimelinePlaybackPlanner.makePlan(
                timeline: timeline,
                cursorSample: responsivePlan.cursorSample,
                assetMetadata: metadata
            )
            graphRouteFormatAtLastRebuild = nil
            needsRebuildOnPlay = true
        }
        state = plan?.remainingSamples == 0 ? .completed : .prepared
        recordAudioCursor(
            kind: responsivePlan.cursorSample > 0 ? .restoration : .prepared,
            cursorSample: responsivePlan.cursorSample
        )
    }

    public func configureAutomaticBoundary(
        successorPlan: ResponsiveAudioTimelineTransportPlan?,
        resolver: any OfflineAudioAssetResolving,
        handler: @escaping (ResponsiveAudioAutomaticBoundaryEvent) -> Void
    ) throws {
        guard state == .prepared || state == .paused || state == .playing,
              let timeline,
              let plan,
              plan.remainingSamples > 0 else {
            throw NativeTimelineTransportError.notPrepared
        }
        var successorMetadata: [String: AudioAssetMetadata] = [:]
        var successorURLs: [String: URL] = [:]
        if let successorPlan {
            guard successorPlan.cursorSample == 0,
                  successorPlan.loopIteration == 0,
                  case let .loop(_, successorDuration) = successorPlan.repetition,
                  successorDuration
                    == successorPlan.timeline.authoredDurationSamples,
                  successorPlan.timeline.sampleRate == timeline.sampleRate else {
                throw NativeTimelineTransportError.transitionCouldNotPrepare(
                    "automatic successor must start its own equal-domain loop at sample zero"
                )
            }
            let resolved = try resolveMetadata(
                for: successorPlan.timeline,
                resolver: resolver
            )
            _ = try TimelinePlaybackPlanner.makePlan(
                timeline: successorPlan.timeline,
                cursorSample: 0,
                assetMetadata: resolved.metadata
            )
            successorMetadata = resolved.metadata
            successorURLs = resolved.urls
        }
        invalidateAutomaticBoundary(clearRequest: true)
        automaticBoundaryGeneration &+= 1
        automaticBoundaryRequest = AutomaticBoundaryRequest(
            generation: automaticBoundaryGeneration,
            currentTimelineID: timeline.id,
            currentAuthoredDurationSamples: timeline.authoredDurationSamples,
            successorPlan: successorPlan,
            successorMetadata: successorMetadata,
            successorURLs: successorURLs,
            handler: handler
        )
        do {
            if state == .playing {
                try stageAutomaticBoundaryCandidateIfNeeded()
                try scheduleAutomaticBoundaryFromCurrentStart()
            }
        } catch {
            invalidateAutomaticBoundary(clearRequest: true)
            throw error
        }
    }

    private func invalidateAutomaticBoundary(clearRequest: Bool) {
        automaticBoundaryTask?.cancel()
        automaticBoundaryTask = nil
        automaticBoundaryGeneration &+= 1
        teardownStagedAutomaticBoundary()
        guard !clearRequest, let request = automaticBoundaryRequest else {
            automaticBoundaryRequest = nil
            return
        }
        automaticBoundaryRequest = AutomaticBoundaryRequest(
            generation: automaticBoundaryGeneration,
            currentTimelineID: request.currentTimelineID,
            currentAuthoredDurationSamples: request.currentAuthoredDurationSamples,
            successorPlan: request.successorPlan,
            successorMetadata: request.successorMetadata,
            successorURLs: request.successorURLs,
            handler: request.handler
        )
    }

    private func teardownStagedAutomaticBoundary() {
        guard let staged = stagedAutomaticBoundary else { return }
        audioCursorFeedStorage.clearScheduled(
            mappingGeneration: staged.cursorMappingGeneration
        )
        teardownConventionalNodes(staged.successorSlices)
        teardownCommonLayers(staged.successorCommonLayers.values)
        stopPreparedHaptics(staged.successorHaptics)
        stagedAutomaticBoundary = nil
    }

    private func stageAutomaticBoundaryCandidateIfNeeded() throws {
        guard let request = automaticBoundaryRequest else { return }
        guard request.generation == automaticBoundaryGeneration,
              request.currentTimelineID == timeline?.id else {
            throw NativeTimelineTransportError.transitionCouldNotPrepare(
                "automatic boundary no longer owns the prepared timeline"
            )
        }
        teardownStagedAutomaticBoundary()
        guard let successor = request.successorPlan else {
            stagedAutomaticBoundary = StagedAutomaticBoundary(
                generation: request.generation,
                graphSampleTime: 0,
                startTime: AVAudioTime(sampleTime: 0, atRate: 48_000),
                cursorMappingGeneration: nil,
                successorTimelinePlan: nil,
                successorSlices: [],
                successorCommonLayers: [:],
                successorHaptics: nil
            )
            return
        }
        let originalMixerKeys = Set(roleMixers.keys)
        var slices: [PreparedAudioSlice] = []
        var layers: [ResponsiveAudioMaterialLayerID: PreparedCommonLayer] = [:]
        var haptics: (any NativeTimelineHapticPlayback)?
        do {
            let successorTimelinePlan = try TimelinePlaybackPlanner.makePlan(
                timeline: successor.timeline,
                cursorSample: 0,
                assetMetadata: request.successorMetadata
            )
            try ensureRoleMixers(
                for: successor.timeline.events.map(\.role)
            )
            let commonCueIDs = Set(
                successor.causalMix?.layers.map(\.cueID) ?? []
            )
            guard let resolver = assetResolver else {
                throw NativeTimelineTransportError.notPrepared
            }
            slices = try stageConventionalNodes(
                timeline: successor.timeline,
                plan: successorTimelinePlan,
                repetition: successor.repetition,
                excluding: commonCueIDs,
                resolver: resolver
            )
            if let mix = successor.causalMix {
                layers = try stageCommonLayers(
                    mix,
                    cursorSample: 0,
                    resolver: resolver
                )
            }
            haptics = try makePreparedHaptics(for: successorTimelinePlan)
            stagedAutomaticBoundary = StagedAutomaticBoundary(
                generation: request.generation,
                graphSampleTime: 0,
                startTime: AVAudioTime(
                    sampleTime: 0,
                    atRate: Double(successorTimelinePlan.sampleRate)
                ),
                cursorMappingGeneration: nil,
                successorTimelinePlan: successorTimelinePlan,
                successorSlices: slices,
                successorCommonLayers: layers,
                successorHaptics: haptics
            )
        } catch {
            teardownConventionalNodes(slices)
            teardownCommonLayers(layers.values)
            stopPreparedHaptics(haptics)
            teardownRoleMixers(createdAfter: originalMixerKeys)
            throw error
        }
    }

    private func scheduleAutomaticBoundaryFromCurrentStart() throws {
        guard let startTime = currentGraphStartTime else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        try scheduleAutomaticBoundary(
            graphStartSample: AUEventSampleTime(renderClockBaseGraphSampleTime),
            startTime: startTime
        )
    }

    private func scheduleAutomaticBoundary(
        graphStartSample: AUEventSampleTime,
        startTime: AVAudioTime
    ) throws {
        guard let request = automaticBoundaryRequest,
              var staged = stagedAutomaticBoundary,
              request.generation == staged.generation,
              request.generation == automaticBoundaryGeneration,
              let currentRequest = responsivePlan,
              let currentPlan = plan,
              request.currentTimelineID == currentRequest.timeline.id else {
            return
        }
        let remaining = request.currentAuthoredDurationSamples
            .subtractingReportingOverflow(currentRequest.cursorSample)
        guard !remaining.overflow, remaining.partialValue > 0 else {
            throw NativeTimelineTransportError.transitionCouldNotPrepare(
                "automatic boundary has no positive finite remainder"
            )
        }
        let graphBoundary = graphStartSample.addingReportingOverflow(
            remaining.partialValue
        )
        guard !graphBoundary.overflow else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        let boundaryTime = try audioTime(
            addingSamples: remaining.partialValue,
            to: startTime,
            sampleRate: currentPlan.sampleRate
        )
        staged.graphSampleTime = graphBoundary.partialValue
        staged.startTime = boundaryTime

        let cursorMappingGeneration: UInt64
        if let successor = request.successorPlan,
           let successorTimelinePlan = staged.successorTimelinePlan {
            cursorMappingGeneration = try publishScheduledAudioCursorMapping(
                request: successor.replacingPosition(
                    cursorSample: 0,
                    loopIteration: 0
                ),
                timelinePlan: successorTimelinePlan,
                graphBoundarySample: graphBoundary.partialValue
            )
        } else {
            cursorMappingGeneration = try publishScheduledAudioCursorMapping(
                request: currentRequest.replacingPosition(
                    cursorSample: request.currentAuthoredDurationSamples,
                    loopIteration: 0
                ),
                timelinePlan: currentPlan,
                graphBoundarySample: graphBoundary.partialValue,
                isPlaying: false
            )
        }
        staged.cursorMappingGeneration = cursorMappingGeneration
        // Publish the future identity before any haptic or player is allowed
        // to schedule the successor at this graph boundary.
        stagedAutomaticBoundary = staged

        let hapticBoundary = nativeHapticBoundary(
            startTime: boundaryTime,
            graphSampleTime: graphBoundary.partialValue,
            sampleRate: currentPlan.sampleRate
        )
        if let candidate = staged.successorHaptics {
            try startPreparedHaptics(candidate, at: hapticBoundary)
        }
        let currentHaptic = pendingPhysicalTransition?.replacesConventionalBranch == true
            ? pendingPhysicalTransition?.candidateHaptics
            : hapticPlayback
        if let currentHaptic {
            do {
                try hapticScheduler.scheduleStop(
                    currentHaptic,
                    at: hapticBoundary
                )
            } catch {
                stopPreparedHaptics(staged.successorHaptics)
                staged.successorHaptics = nil
                stagedAutomaticBoundary = staged
                throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
            }
        }

        if let successorTimelinePlan = staged.successorTimelinePlan {
            scheduleConventionalSlices(
                staged.successorSlices,
                plan: successorTimelinePlan,
                startTime: boundaryTime,
                renderSample: graphBoundary.partialValue
            )
            for layer in staged.successorCommonLayers.values {
                layer.player.play(at: boundaryTime)
            }
        }
        scheduleMute(for: preparedSlices, at: graphBoundary.partialValue)
        scheduleMute(for: commonLayers.values, at: graphBoundary.partialValue)
        stagedAutomaticBoundary = staged
        armAutomaticBoundaryMonitor(
            generation: request.generation,
            boundaryTime: boundaryTime,
            boundaryGraphSample: graphBoundary.partialValue
        )
    }

    private func audioTime(
        addingSamples samples: Int64,
        to startTime: AVAudioTime,
        sampleRate: Int
    ) throws -> AVAudioTime {
        guard samples >= 0, sampleRate > 0 else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        if startTime.isHostTimeValid {
            let hostDelta = AVAudioTime.hostTime(
                forSeconds: Double(samples) / Double(sampleRate)
            )
            let hostTime = startTime.hostTime.addingReportingOverflow(hostDelta)
            guard !hostTime.overflow else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            return AVAudioTime(hostTime: hostTime.partialValue)
        }
        let sampleTime = startTime.sampleTime.addingReportingOverflow(samples)
        guard !sampleTime.overflow else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        return AVAudioTime(
            sampleTime: sampleTime.partialValue,
            atRate: Double(sampleRate)
        )
    }

    private func armAutomaticBoundaryMonitor(
        generation: UInt64,
        boundaryTime: AVAudioTime,
        boundaryGraphSample: Int64
    ) {
        automaticBoundaryTask?.cancel()
        automaticBoundaryTask = nil
        guard engine.manualRenderingMode != .offline,
              boundaryTime.isHostTimeValid,
              let durabilityEpoch = audioDurabilityEpoch?.epoch else { return }
        let boundaryHostTime = boundaryTime.hostTime
        automaticBoundaryTask = Task { @MainActor [weak self] in
            guard let self,
                  self.ownsAutomaticBoundaryMonitor(
                      generation: generation,
                      durabilityEpoch: durabilityEpoch,
                      boundaryGraphSample: boundaryGraphSample
                  ) else { return }
            let now = mach_absolute_time()
            if boundaryHostTime > now {
                let nanoseconds = AVAudioTime.seconds(
                    forHostTime: boundaryHostTime - now
                ) * 1_000_000_000
                guard nanoseconds.isFinite,
                      nanoseconds > 0,
                      nanoseconds <= Double(UInt64.max) else {
                    self.failClosedAutomaticBoundaryMonitor(
                        generation: generation,
                        durabilityEpoch: durabilityEpoch,
                        boundaryGraphSample: boundaryGraphSample
                    )
                    return
                }
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(nanoseconds.rounded(.up))
                    )
                } catch {
                    return
                }
            }
            var pollState = NativeAutomaticBoundaryMonitorPollState()
            while !Task.isCancelled {
                guard self.ownsAutomaticBoundaryMonitor(
                    generation: generation,
                    durabilityEpoch: durabilityEpoch,
                    boundaryGraphSample: boundaryGraphSample
                ) else { return }
                self.promoteAutomaticBoundary(generation: generation)
                guard self.automaticBoundaryRequest?.generation
                    == generation else { return }

                let renderedGraphSample = self.renderClockStorage
                    .latestGraphSampleEnd.load(ordering: .acquiring)
                switch pollState.observe(
                    renderedGraphSample: renderedGraphSample,
                    boundaryGraphSample: boundaryGraphSample
                ) {
                case .boundaryCrossed:
                    // Promotion above reads the same monotone render clock.
                    // If it did not consume this generation, ownership was
                    // lost and no public boundary event may be invented.
                    self.promoteAutomaticBoundary(generation: generation)
                    return
                case .stallLimitReached:
                    let confirmedGraphSample = self.renderClockStorage
                        .latestGraphSampleEnd.load(ordering: .acquiring)
                    if confirmedGraphSample > renderedGraphSample {
                        // A render callback won the watchdog edge. Feed that
                        // progress back through the same policy rather than
                        // retiring a graph that has resumed.
                        switch pollState.observe(
                            renderedGraphSample: confirmedGraphSample,
                            boundaryGraphSample: boundaryGraphSample
                        ) {
                        case .boundaryCrossed:
                            self.promoteAutomaticBoundary(
                                generation: generation
                            )
                            return
                        case let .sleep(nanoseconds):
                            do {
                                try await Task.sleep(
                                    nanoseconds: nanoseconds
                                )
                            } catch {
                                return
                            }
                            continue
                        case .stallLimitReached:
                            break
                        }
                    }
                    self.failClosedAutomaticBoundaryMonitor(
                        generation: generation,
                        durabilityEpoch: durabilityEpoch,
                        boundaryGraphSample: boundaryGraphSample
                    )
                    return
                case let .sleep(nanoseconds):
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                    } catch {
                        return
                    }
                }
            }
        }
    }

    private func ownsAutomaticBoundaryMonitor(
        generation: UInt64,
        durabilityEpoch: UInt64,
        boundaryGraphSample: Int64
    ) -> Bool {
        state == .playing
            && engine.isRunning
            && currentGraphStartTime != nil
            && audioDurabilityEpoch?.epoch == durabilityEpoch
            && automaticBoundaryGeneration == generation
            && automaticBoundaryRequest?.generation == generation
            && stagedAutomaticBoundary?.generation == generation
            && stagedAutomaticBoundary?.graphSampleTime == boundaryGraphSample
    }

    private func failClosedAutomaticBoundaryMonitor(
        generation: UInt64,
        durabilityEpoch: UInt64,
        boundaryGraphSample: Int64
    ) {
        guard ownsAutomaticBoundaryMonitor(
            generation: generation,
            durabilityEpoch: durabilityEpoch,
            boundaryGraphSample: boundaryGraphSample
        ) else { return }
        // No handler is called: a stopped render clock never crossed the
        // authored sample. Retire the graph and its epoch instead of keeping a
        // muted transport and a high-frequency monitor alive indefinitely.
        stop(clearTimeline: true)
    }

    public func transitionResponsiveAudio(
        to requestedPlan: ResponsiveAudioTimelineTransportPlan,
        resolver: any OfflineAudioAssetResolving,
        validateBeforeCommit: (
            NativeTimelineTransportSnapshot
        ) throws -> Void
    ) throws -> NativeTimelineTransportSnapshot {
        promotePendingPhysicalTransitionIfNeeded()
        guard let currentRequest = responsivePlan,
              let currentTimeline = timeline,
              let currentTimelinePlan = plan else {
            throw NativeTimelineTransportError.notPrepared
        }
        invalidateAutomaticBoundary(clearRequest: true)
        let currentMix = currentRequest.causalMix
        let requestedMix = requestedPlan.causalMix
        let retainsCommonLayers = currentMix != nil && requestedMix != nil
        if let currentMix, let requestedMix {
            try validateRetainedCommonLayerContract(
                current: currentMix,
                requested: requestedMix,
                requestedRepetition: requestedPlan.repetition
            )
        } else if currentMix == nil, requestedMix != nil {
            throw NativeTimelineTransportError.transitionCouldNotPrepare(
                "a transition cannot invent a new common-player graph"
            )
        }

        let wasPlaying = state == .playing
        let previousState = state
        let timelineChanged = currentTimeline.id != requestedPlan.timeline.id

        // A stage-only target change is deliberately pure graph automation:
        // no resolver call, AVAudioFile open or conventional-node mutation.
        if !timelineChanged, retainsCommonLayers, let requestedMix {
            let observation = wasPlaying
                ? try captureRenderClockObservation()
                : nil
            let boundary: TransitionBoundary? = if let observation {
                try makeTransitionBoundary(
                    for: currentRequest,
                    sampleRate: currentTimelinePlan.sampleRate,
                    observation: observation
                )
            } else {
                nil
            }
            let changes = try validatedCausalTargetChanges(
                requestedMix,
                ramp: wasPlaying,
                startSample: boundary?.graphSampleTime
            )
            let position = observation.map {
                playbackPosition(
                    for: currentRequest,
                    renderedSamples: $0.renderedOffset
                )
            } ?? PlaybackPosition(
                cursorSample: requestedPlan.cursorSample,
                loopIteration: requestedPlan.loopIteration,
                loopDuration: currentTimeline.authoredDurationSamples
            )
            let effective = requestedPlan.replacingPosition(
                cursorSample: position.cursorSample,
                loopIteration: position.loopIteration
            )
            let authoritativeSnapshot = NativeTimelineTransportSnapshot(
                timelineID: currentTimeline.id,
                cursorSample: position.cursorSample,
                loopIteration: position.loopIteration,
                isPlaying: wasPlaying
            )
            try validateBeforeCommit(authoritativeSnapshot)
            var scheduledMappingGeneration: UInt64?
            if let boundary,
               pendingPhysicalTransition != nil {
                let projected = effective.replacingPosition(
                    cursorSample: boundary.projectedPosition.cursorSample,
                    loopIteration: boundary.projectedPosition.loopIteration
                )
                scheduledMappingGeneration =
                    try publishScheduledAudioCursorMapping(
                        request: projected,
                        timelinePlan: currentTimelinePlan,
                        graphBoundarySample: boundary.graphSampleTime
                    )
            }
            responsivePlan = effective
            if let observation, let boundary {
                rebaseRenderClock(to: observation)
                lastTransitionBoundaryForTesting = boundary.graphSampleTime
                if pendingPhysicalTransition == nil {
                    _ = publishCurrentAudioCursorMapping(
                        request: effective,
                        timelinePlan: currentTimelinePlan,
                        graphBaseSample: observation.graphSampleTime
                    )
                    pendingPhysicalTransition = PendingPhysicalTransition(
                        graphSampleTime: boundary.graphSampleTime,
                        startTime: boundary.startTime,
                        candidateHaptics: nil,
                        replacesConventionalBranch: false,
                        cursorMappingGeneration: nil
                    )
                } else {
                    pendingPhysicalTransition?.cursorMappingGeneration =
                        scheduledMappingGeneration
                }
            }
            applyCausalTargetChanges(
                changes,
                rampDurationSamples: requestedMix.rampDurationSamples,
                ramp: wasPlaying,
                startSample: boundary?.graphSampleTime
            )
            return authoritativeSnapshot
        }

        let originalMixerKeys = Set(roleMixers.keys)
        var candidateSlices: [PreparedAudioSlice] = []
        var candidateHaptics: (any NativeTimelineHapticPlayback)?
        do {
            let resolved = try resolveMetadata(
                for: requestedPlan.timeline,
                resolver: resolver
            )
            let stagingCursor: Int64 = switch requestedPlan.repetition {
            case .once: requestedPlan.cursorSample
            case .loop: 0
            }
            let stagingPlan = try TimelinePlaybackPlanner.makePlan(
                timeline: requestedPlan.timeline,
                cursorSample: stagingCursor,
                assetMetadata: resolved.metadata
            )
            candidateSlices = try stageConventionalNodes(
                timeline: requestedPlan.timeline,
                plan: stagingPlan,
                repetition: requestedPlan.repetition,
                excluding: Set(requestedMix?.layers.map(\.cueID) ?? []),
                resolver: resolver
            )
            candidateHaptics = try makePreparedHaptics(for: stagingPlan)

            let observation = wasPlaying
                ? try captureRenderClockObservation()
                : nil
            let boundary: TransitionBoundary? = if let observation {
                try makeTransitionBoundary(
                    for: currentRequest,
                    sampleRate: currentTimelinePlan.sampleRate,
                    observation: observation
                )
            } else {
                nil
            }
            let physicalPosition: PlaybackPosition
            switch requestedPlan.repetition {
            case .once:
                physicalPosition = PlaybackPosition(
                    cursorSample: requestedPlan.cursorSample,
                    loopIteration: 0,
                    loopDuration: 0
                )
            case let .loop(_, durationSamples):
                physicalPosition = boundary?.projectedPosition
                    ?? PlaybackPosition(
                        cursorSample: requestedPlan.cursorSample,
                        loopIteration: requestedPlan.loopIteration,
                        loopDuration: durationSamples
                    )
                try retargetStagedLoopBuffers(
                    candidateSlices,
                    cursorSample: physicalPosition.cursorSample
                )
            }
            let logicalPosition: PlaybackPosition
            switch requestedPlan.repetition {
            case .once:
                logicalPosition = PlaybackPosition(
                    cursorSample: requestedPlan.cursorSample,
                    loopIteration: 0,
                    loopDuration: 0
                )
            case let .loop(_, durationSamples):
                logicalPosition = observation.map {
                    playbackPosition(
                        for: currentRequest,
                        renderedSamples: $0.renderedOffset
                    )
                } ?? PlaybackPosition(
                    cursorSample: requestedPlan.cursorSample,
                    loopIteration: requestedPlan.loopIteration,
                    loopDuration: durationSamples
                )
            }
            let effectivePlan = requestedPlan.replacingPosition(
                cursorSample: logicalPosition.cursorSample,
                loopIteration: logicalPosition.loopIteration
            )
            let physicalTimelinePlan = try TimelinePlaybackPlanner.makePlan(
                timeline: requestedPlan.timeline,
                cursorSample: physicalPosition.cursorSample,
                assetMetadata: resolved.metadata
            )
            let logicalTimelinePlan = try TimelinePlaybackPlanner.makePlan(
                timeline: requestedPlan.timeline,
                cursorSample: logicalPosition.cursorSample,
                assetMetadata: resolved.metadata
            )
            let changes: [CausalTargetChange]
            if retainsCommonLayers, let requestedMix {
                changes = try validatedCausalTargetChanges(
                    requestedMix,
                    ramp: wasPlaying,
                    startSample: boundary?.graphSampleTime
                )
            } else {
                changes = []
            }

            let authoritativeSnapshot = NativeTimelineTransportSnapshot(
                timelineID: requestedPlan.timeline.id,
                cursorSample: logicalPosition.cursorSample,
                loopIteration: logicalPosition.loopIteration,
                isPlaying: wasPlaying
            )
            try validateBeforeCommit(authoritativeSnapshot)

            if wasPlaying, failNextHapticStartForTesting {
                failNextHapticStartForTesting = false
                throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
            }
            let priorPending = pendingPhysicalTransition
            if wasPlaying, let boundary {
                let hapticBoundary = nativeHapticBoundary(
                    for: boundary,
                    sampleRate: currentTimelinePlan.sampleRate
                )
                if let candidateHaptics {
                    try startPreparedHaptics(
                        candidateHaptics,
                        at: hapticBoundary
                    )
                }
                let activeStopIsAlreadyScheduled =
                    priorPending?.replacesConventionalBranch == true
                    && priorPending?.graphSampleTime == boundary.graphSampleTime
                if !activeStopIsAlreadyScheduled, let hapticPlayback {
                    do {
                        try hapticScheduler.scheduleStop(
                            hapticPlayback,
                            at: hapticBoundary
                        )
                    } catch {
                        throw NativeTimelineTransportError
                            .hapticPatternCouldNotPrepare
                    }
                }
            }

            let cursorMappingGeneration: UInt64?
            if wasPlaying, let boundary {
                let physicalMapping = requestedPlan.replacingPosition(
                    cursorSample: physicalPosition.cursorSample,
                    loopIteration: physicalPosition.loopIteration
                )
                cursorMappingGeneration =
                    try publishScheduledAudioCursorMapping(
                        request: physicalMapping,
                        timelinePlan: physicalTimelinePlan,
                        graphBoundarySample: boundary.graphSampleTime
                    )
            } else {
                cursorMappingGeneration = nil
            }

            // Commit begins here. Every operation capable of throwing has
            // completed; the old branch and runtime-visible identity have not
            // yet changed.
            if wasPlaying, let boundary {
                scheduleConventionalSlices(
                    candidateSlices,
                    plan: physicalTimelinePlan,
                    startTime: boundary.startTime,
                    renderSample: boundary.graphSampleTime
                )
                if priorPending?.replacesConventionalBranch == true {
                    teardownConventionalNodes(preparedSlices)
                } else {
                    scheduleMute(
                        for: preparedSlices,
                        at: boundary.graphSampleTime
                    )
                    retiredSlices.append(contentsOf: preparedSlices)
                }
                if !retainsCommonLayers {
                    scheduleMute(
                        for: commonLayers.values,
                        at: boundary.graphSampleTime
                    )
                    retiredCommonLayers.append(contentsOf: commonLayers.values)
                    commonLayers.removeAll()
                }
                applyCausalTargetChanges(
                    changes,
                    rampDurationSamples: requestedMix?.rampDurationSamples ?? 0,
                    ramp: true,
                    startSample: boundary.graphSampleTime
                )
                stopPreparedHaptics(priorPending?.candidateHaptics)
                pendingPhysicalTransition = PendingPhysicalTransition(
                    graphSampleTime: boundary.graphSampleTime,
                    startTime: boundary.startTime,
                    candidateHaptics: candidateHaptics,
                    replacesConventionalBranch: true,
                    cursorMappingGeneration: cursorMappingGeneration
                )
                candidateHaptics = nil
                if let observation {
                    switch requestedPlan.repetition {
                    case .loop:
                        rebaseRenderClock(to: observation)
                    case .once:
                        rebaseRenderClock(to: boundary)
                        currentGraphStartTime = boundary.startTime
                    }
                }
                lastTransitionBoundaryForTesting = boundary.graphSampleTime
            } else {
                teardownConventionalNodes(preparedSlices)
                teardownRetiredNodes()
                stopPreparedHaptics(pendingPhysicalTransition?.candidateHaptics)
                pendingPhysicalTransition = nil
                if !retainsCommonLayers {
                    for common in commonLayers.values {
                        common.player.stop()
                        engine.disconnectNodeOutput(common.player)
                        engine.disconnectNodeOutput(common.gainNode.node)
                        engine.detach(common.player)
                        engine.detach(common.gainNode.node)
                    }
                    commonLayers.removeAll()
                }
                applyCausalTargetChanges(
                    changes,
                    rampDurationSamples: requestedMix?.rampDurationSamples ?? 0,
                    ramp: false,
                    startSample: nil
                )
                resetRenderClockBase()
                stopCurrentHaptics()
                hapticPlayback = candidateHaptics
                hapticsAreAvailable = candidateHaptics != nil
                candidateHaptics = nil
            }

            preparedSlices = candidateSlices
            candidateSlices = []
            timeline = requestedPlan.timeline
            plan = logicalTimelinePlan
            responsivePlan = effectivePlan
            assetResolver = resolver
            assetURLs = resolved.urls
            preparedAssetMetadata = resolved.metadata
            needsRebuildOnPlay = wasPlaying
                ? false
                : engine.manualRenderingMode != .offline
            state = wasPlaying
                ? .playing
                : (logicalTimelinePlan.remainingSamples == 0
                    ? .completed
                    : (previousState == .paused ? .paused : .prepared))

            return authoritativeSnapshot
        } catch {
            if let candidateHaptics {
                hapticScheduler.stopImmediately(candidateHaptics)
            }
            teardownConventionalNodes(candidateSlices)
            teardownRoleMixers(createdAfter: originalMixerKeys)
            throw error
        }
    }

    private func beginAudioDurabilityEpoch(
        graphStartSample: Int64,
        request: ResponsiveAudioTimelineTransportPlan,
        timelinePlan: TimelinePlaybackPlan
    ) throws {
        let cutoff = graphStartSample.addingReportingOverflow(
            Self.initialDurabilitySampleBudget
        )
        guard graphStartSample >= 0, !cutoff.overflow else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        let token = try audioDurabilityGate.resetWhileTransportStopped(
            atRenderedGraphSample: cutoff.partialValue
        )
        audioDurabilityEpoch = token
        _ = audioCursorFeedStorage.publishCurrent(
            clock: renderClockStorage,
            timelineID: request.timeline.id,
            cursorSample: request.cursorSample,
            loopIteration: request.loopIteration,
            repetition: request.repetition,
            endSample: timelinePlan.endSample,
            graphBaseSample: graphStartSample,
            isPlaying: true
        )
    }

    private func endAudioDurabilityEpochAfterEngineDrain() {
        _ = audioDurabilityEpoch?.transportDidStop()
        audioDurabilityEpoch = nil
        audioCursorFeedStorage.clear()
    }

    private func beginAudioDurabilityStop() {
        _ = audioDurabilityEpoch?.transportWillStop()
    }

    /// `AVAudioEngine.start()` may return before the source node publishes its
    /// first live timestamp. Zero is a valid manual-render position but is not
    /// a live graph origin: scheduling from it would put the 12,000-sample
    /// durability prefix in a different sample domain from the render thread.
    /// Poll only from this control path; the real-time callback remains a
    /// lock-free atomic publisher.
    private func waitForInitialLiveRenderClockAnchor(
        after baselineGraphSample: Int64
    ) throws -> NativeRenderClockAnchor {
        let timeout = AVAudioTime.hostTime(forSeconds: 0.100)
        let startedAt = mach_absolute_time()
        let deadline = startedAt.addingReportingOverflow(timeout)
        guard !deadline.overflow else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        repeat {
            if let anchor = renderClockStorage.loadCoherentAnchor(),
               anchor.graphSampleEnd > baselineGraphSample,
               anchor.hostTimeAtGraphSampleEnd != nil {
                return anchor
            }
            usleep(250)
        } while mach_absolute_time() < deadline.partialValue
        throw NativeTimelineTransportError.renderClockUnavailable
    }

    @discardableResult
    private func publishCurrentAudioCursorMapping(
        request: ResponsiveAudioTimelineTransportPlan,
        timelinePlan: TimelinePlaybackPlan,
        graphBaseSample: Int64,
        isPlaying: Bool = true
    ) -> UInt64 {
        audioCursorFeedStorage.publishCurrent(
            clock: renderClockStorage,
            timelineID: request.timeline.id,
            cursorSample: request.cursorSample,
            loopIteration: request.loopIteration,
            repetition: request.repetition,
            endSample: timelinePlan.endSample,
            graphBaseSample: graphBaseSample,
            isPlaying: isPlaying
        )
    }

    private func publishScheduledAudioCursorMapping(
        request: ResponsiveAudioTimelineTransportPlan,
        timelinePlan: TimelinePlaybackPlan,
        graphBoundarySample: Int64,
        isPlaying: Bool = true
    ) throws -> UInt64 {
        try audioCursorFeedStorage.publishScheduled(
            clock: renderClockStorage,
            timelineID: request.timeline.id,
            cursorSample: request.cursorSample,
            loopIteration: request.loopIteration,
            repetition: request.repetition,
            endSample: timelinePlan.endSample,
            graphBoundarySample: graphBoundarySample,
            isPlaying: isPlaying
        )
    }

    public func play() throws {
        guard state == .prepared || state == .paused else {
            if state == .playing { throw NativeTimelineTransportError.alreadyPlaying }
            throw NativeTimelineTransportError.notPrepared
        }
        let entryState = state
        guard let responsivePlan, let provisionalPlan = plan else {
            throw NativeTimelineTransportError.notPrepared
        }
        let isManualRendering = engine.manualRenderingMode == .offline
        do {
            if !isManualRendering {
                // Activation may select a 44.1 kHz Bluetooth/AirPlay route
                // despite the 48 kHz preference. Build the graph that will
                // actually play only after that route is known.
                let lease = try audioSessionLeaser.acquire(
                    preferredSampleRate: Double(provisionalPlan.sampleRate),
                    engine: engine
                )
                audioSessionLease = lease
                activeRouteFormat = lease.routeFormat
                try rebuild(
                    at: responsivePlan.cursorSample,
                    metadata: preparedAssetMetadata
                )
                needsRebuildOnPlay = false
            } else if needsRebuildOnPlay {
                try rebuild(
                    at: responsivePlan.cursorSample,
                    metadata: preparedAssetMetadata
                )
                needsRebuildOnPlay = false
            }
        } catch {
            releaseAudioSessionLease()
            state = entryState
            needsRebuildOnPlay = true
            throw error
        }
        guard let plan else { throw NativeTimelineTransportError.notPrepared }
        guard plan.remainingSamples > 0 else {
            state = .completed
            recordAudioCursor(kind: .completed, cursorSample: plan.endSample)
            return
        }

        do {
            try stageAutomaticBoundaryCandidateIfNeeded()
            engine.prepare()
            let liveRenderBaseline = isManualRendering
                ? nil
                : renderClockStorage.loadCoherentAnchor()?.graphSampleEnd ?? 0
            try engine.start()
            let leadSeconds = isManualRendering ? 0 : 0.100
            let leadFrames = AVAudioFramePosition(
                (leadSeconds * Double(plan.sampleRate)).rounded()
            )
            let startTime: AVAudioTime
            let graphStartSample: AUEventSampleTime?
            if isManualRendering {
                let sample = engine.manualRenderingSampleTime
                startTime = AVAudioTime(
                    sampleTime: sample,
                    atRate: Double(plan.sampleRate)
                )
                graphStartSample = AUEventSampleTime(sample)
                renderClockBaseGraphSampleTime = sample
            } else {
                let anchor = try waitForInitialLiveRenderClockAnchor(
                    after: liveRenderBaseline ?? 0
                )
                guard let anchorHost = anchor.hostTimeAtGraphSampleEnd else {
                    throw NativeTimelineTransportError.renderClockUnavailable
                }
                let startHost = anchorHost.addingReportingOverflow(
                    AVAudioTime.hostTime(forSeconds: leadSeconds)
                )
                guard !startHost.overflow else {
                    throw NativeTimelineTransportError.renderClockUnavailable
                }
                let graphStart = anchor.graphSampleEnd.addingReportingOverflow(
                    leadFrames
                )
                guard !graphStart.overflow else {
                    throw NativeTimelineTransportError.renderClockUnavailable
                }
                startTime = AVAudioTime(hostTime: startHost.partialValue)
                graphStartSample = AUEventSampleTime(graphStart.partialValue)
                renderClockBaseGraphSampleTime = graphStart.partialValue
            }
            currentGraphStartTime = startTime
            guard let graphStartSample else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            if isManualRendering {
                renderClockStorage.record(
                    graphStartSample,
                    hostTimeAtGraphSampleEnd: nil
                )
            }
            // The epoch begins only after the exact graph origin is fixed,
            // while no player or haptic has started. Every prepared and staged
            // gain unit already points at this one stable gate object.
            try beginAudioDurabilityEpoch(
                graphStartSample: graphStartSample,
                request: responsivePlan,
                timelinePlan: plan
            )

            // Haptics is the only throwable operation after engine start and
            // therefore crosses the transaction before any audio schedule is
            // changed or any player begins rendering.
            try startHaptics(
                plan: plan,
                at: nativeHapticBoundary(
                    startTime: startTime,
                    graphSampleTime: graphStartSample,
                    sampleRate: plan.sampleRate
                )
            )
            try scheduleAutomaticBoundary(
                graphStartSample: graphStartSample,
                startTime: startTime
            )
            scheduleConventionalSlices(
                preparedSlices,
                plan: plan,
                startTime: startTime,
                renderSample: graphStartSample
            )
            for common in commonLayers.values {
                common.player.play(at: startTime)
            }
            guard isManualRendering || renderClockSource != nil else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            state = .playing
            recordAudioCursor(kind: .play, cursorSample: plan.cursorSample)
        } catch {
            rollbackFailedStartup(restoring: entryState)
            throw error
        }
    }

    private func rollbackFailedStartup(
        restoring entryState: NativeTimelineTransportState
    ) {
        beginAudioDurabilityStop()
        preparedSlices.forEach { $0.player.stop() }
        commonLayers.values.forEach { $0.player.stop() }
        engine.stop()
        endAudioDurabilityEpochAfterEngineDrain()
        invalidateAutomaticBoundary(clearRequest: false)
        currentGraphStartTime = nil
        stopCurrentHaptics()
        teardownNodes()
        releaseAudioSessionLease()
        needsRebuildOnPlay = true
        state = entryState
    }

    @discardableResult
    public func pause() throws -> NativeTimelineTransportSnapshot {
        try pause(kind: .controlledPause)
    }

    @discardableResult
    public func pause(
        for reason: ResponsiveAudioSuspensionReason
    ) throws -> NativeTimelineTransportSnapshot {
        switch reason {
        case .sceneInactive, .sceneBackground:
            try pause(kind: .controlledPause)
        case .interruption:
            try pause(kind: .interruptionPause)
        case .routeChange:
            try pause(kind: .routeChangePause)
        }
    }

    private func pause(
        kind: AudioCursorCheckpointKind
    ) throws -> NativeTimelineTransportSnapshot {
        guard state == .playing else { return makeSnapshot(recording: kind) }
        // engine.stop() is the render-thread barrier. The final source-node
        // publication must be read only after this call has returned; reading
        // before it can lose the last in-flight render quantum.
        beginAudioDurabilityStop()
        engine.stop()
        endAudioDurabilityEpochAfterEngineDrain()
        pauseQuiescenceHookForTesting?()
        promoteAutomaticBoundaryIfNeeded()
        if state == .completed {
            return makeSnapshot(recording: kind)
        }
        let position = currentPlaybackPosition()
        preparedSlices.forEach { $0.player.stop() }
        retiredSlices.forEach { $0.player.stop() }
        commonLayers.values.forEach { $0.player.stop() }
        retiredCommonLayers.forEach { $0.player.stop() }
        stopCurrentHaptics()
        stopPreparedHaptics(pendingPhysicalTransition?.candidateHaptics)
        pendingPhysicalTransition = nil
        invalidateAutomaticBoundary(clearRequest: false)
        currentGraphStartTime = nil
        releaseAudioSessionLease()
        if let currentRequest = responsivePlan {
            responsivePlan = currentRequest.replacingPosition(
                cursorSample: position.cursorSample,
                loopIteration: position.loopIteration
            )
        }
        state = plan?.remainingSamples == 0 ? .completed : .paused
        needsRebuildOnPlay = state == .paused
        let snapshot = makeSnapshot(recording: kind)
#if DEBUG
        let pauseCompletionFault = pauseCompletionFaultForTesting
        pauseCompletionFaultForTesting = nil
        if clearsRenderedSampleOffsetAfterNextPauseForTesting {
            renderedSampleOffsetOverrideForTesting = nil
            clearsRenderedSampleOffsetAfterNextPauseForTesting = false
        }
        // This seam deliberately runs only after the production pause has
        // stopped the engine, captured its final render position, released
        // the audio-session lease and published a paused transport state. It
        // models a partial boundary failure without bypassing any of that
        // state touch. Release builds contain neither the hook nor its API.
        try pauseCompletionFault?(snapshot)
#endif
        return snapshot
    }

    @discardableResult
    public func pauseForInterruption() throws -> NativeTimelineTransportSnapshot {
        try pause(kind: .interruptionPause)
    }

    @discardableResult
    public func pauseForRouteChange() throws -> NativeTimelineTransportSnapshot {
        try pause(kind: .routeChangePause)
    }

    public func relinquishOutgoingAudio(
        exitPolicy: ResponsiveAudioExitPolicy
    ) throws -> ResponsiveAudioOutgoingTail? {
        guard state == .playing,
              let responsivePlan,
              let plan else { return nil }
        invalidateAutomaticBoundary(clearRequest: true)
        try exitPolicy.validate(field: "responsiveAudioExitPolicy")
#if DEBUG
        let relinquishPreparationFault =
            relinquishPreparationFaultForTesting
        relinquishPreparationFaultForTesting = nil
        // This seam runs while the original graph, lease and finite
        // durability epoch are still live. It models any real preparation
        // error below without turning the test into a post-stop success case.
        try relinquishPreparationFault?()
#endif
        let fadeDuration = exitPolicy.boundedFadeDurationSamples
        let observation = try captureRenderClockObservation()
        let boundary = try makeTransitionBoundary(
            for: responsivePlan,
            sampleRate: plan.sampleRate,
            observation: observation
        )
        let fadeEnd = boundary.graphSampleTime.addingReportingOverflow(
            fadeDuration
        )
        guard !fadeEnd.overflow else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }

        let initialWakeHintNanoseconds: UInt64?
        if engine.manualRenderingMode == .offline {
            initialWakeHintNanoseconds = nil
        } else {
            let totalSeconds = boundary.leadSeconds
                + Double(fadeDuration) / Double(plan.sampleRate)
            let nanoseconds = totalSeconds * 1_000_000_000
            guard nanoseconds.isFinite,
                  nanoseconds >= 0,
                  nanoseconds <= Double(UInt64.max) else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            initialWakeHintNanoseconds = UInt64(nanoseconds.rounded(.up))
        }

        // Finish every throwable boundary operation before replacing worker
        // authority with the terminal tail. A haptic failure therefore leaves
        // the original durability cutoff intact and the graph retryable.
        let hapticAtFadeEnd = try nativeHapticBoundaryAtFadeEnd(
            boundary,
            durationSamples: fadeDuration,
            sampleRate: plan.sampleRate
        )
        if let pendingPhysicalTransition,
           pendingPhysicalTransition.replacesConventionalBranch {
            if let candidate = pendingPhysicalTransition.candidateHaptics {
                try hapticScheduler.scheduleStop(candidate, at: hapticAtFadeEnd)
            }
        } else if let hapticPlayback {
            try hapticScheduler.scheduleStop(hapticPlayback, at: hapticAtFadeEnd)
        }

        scheduleFade(
            for: preparedSlices,
            at: boundary.graphSampleTime,
            durationSamples: fadeDuration
        )
        // Fade automation is nonthrowing and must be visible to render before
        // a long terminal extension can expose samples beyond the old cutoff.
        scheduleFade(
            for: commonLayers.values,
            at: boundary.graphSampleTime,
            durationSamples: fadeDuration
        )
        guard let audioDurabilityEpoch,
              audioDurabilityEpoch.authorizeTerminalTail(
                  fromRenderedGraphSample: observation.graphSampleTime,
                  throughRenderedGraphSample: fadeEnd.partialValue
              ) else {
            // The render callback may close the durability boundary between
            // observation and authorization. Continuing would create a muted
            // live transport, so drain and retire this epoch before throwing.
            stop(clearTimeline: true)
            throw NativeTimelineTransportError.renderClockUnavailable
        }

        outgoingTailGeneration &+= 1
        let generation = outgoingTailGeneration
        activeOutgoingTailGeneration = generation
        let tail = ResponsiveAudioOutgoingTail(
            owner: self,
            fadeBoundarySample: Int64(boundary.graphSampleTime),
            fadeDurationSamples: fadeDuration,
            sampleRate: plan.sampleRate,
            initialWakeHintNanoseconds: initialWakeHintNanoseconds,
            fadeEndGraphSample: Int64(fadeEnd.partialValue),
            renderObservation: { [weak self] in
                guard let self else {
                    return ResponsiveAudioOutgoingTailRenderObservation(
                        graphSampleEnd: nil,
                        engineIsRunning: false
                    )
                }
                let graphSampleEnd: Int64?
                if self.engine.manualRenderingMode == .offline {
                    graphSampleEnd = self.engine.manualRenderingSampleTime
                } else {
                    graphSampleEnd = self.renderClockStorage
                        .loadCoherentAnchor()?.graphSampleEnd
                }
                return ResponsiveAudioOutgoingTailRenderObservation(
                    graphSampleEnd: graphSampleEnd,
                    engineIsRunning: self.engine.isRunning
                )
            },
            finishOperation: { [weak self] _ in
                guard self?.activeOutgoingTailGeneration == generation else {
                    return
                }
                self?.activeOutgoingTailGeneration = nil
                self?.activeOutgoingTail = nil
                self?.stop(clearTimeline: true)
            }
        )
        activeOutgoingTail = tail
        return tail
    }

    public func resume() throws {
        try play()
    }

    /// Returns a worker-safe raw clock binding for the current playback epoch.
    /// The caller must retain generation-specific runtime projection state;
    /// this feed deliberately contains no MainActor closure.
    public func activeAudioCursorBinding() throws
        -> NativeAudioCursorBinding {
        guard state == .playing,
              let audioDurabilityEpoch,
              let plan,
              let mappingDescriptors = audioCursorFeedStorage
                  .mappingDescriptors() else {
            throw NativeAudioCursorFeedError.unavailable
        }
        return NativeAudioCursorBinding(
            feed: audioCursorFeedStorage.feed(),
            gateToken: audioDurabilityEpoch,
            renderedGraphSampleRate: Double(plan.sampleRate),
            mappingDescriptors: mappingDescriptors
        )
    }

    public func snapshot() -> NativeTimelineTransportSnapshot {
        // The successor is scheduled on the render graph before the main-actor
        // monitor publishes its historical boundary. A durability checkpoint
        // may run first after the render clock crosses that sample. Promote the
        // generation-bound boundary here so that checkpoint can never label the
        // preceding finite timeline as freshly verified after successor audio
        // has already rendered.
        promoteAutomaticBoundaryIfNeeded()
        return makeSnapshot(recording: .snapshot)
    }

    private func makeSnapshot(
        recording kind: AudioCursorCheckpointKind
    ) -> NativeTimelineTransportSnapshot {
        let position = currentPlaybackPosition()
        recordAudioCursor(kind: kind, cursorSample: position.cursorSample)
        return NativeTimelineTransportSnapshot(
            timelineID: timeline?.id,
            cursorSample: position.cursorSample,
            loopIteration: position.loopIteration,
            isPlaying: state == .playing
        )
    }

    public func currentCursorSample() -> Int64 {
        currentPlaybackPosition().cursorSample
    }

    private func currentPlaybackPosition() -> PlaybackPosition {
        promotePendingPhysicalTransitionIfNeeded()
        guard let responsivePlan else {
            return PlaybackPosition(cursorSample: 0, loopIteration: 0, loopDuration: 0)
        }
        guard state == .playing else {
            let duration: Int64 = switch responsivePlan.repetition {
            case .once: 0
            case let .loop(_, durationSamples): durationSamples
            }
            return PlaybackPosition(
                cursorSample: responsivePlan.cursorSample,
                loopIteration: responsivePlan.loopIteration,
                loopDuration: duration
            )
        }
        let position = playbackPosition(
            for: responsivePlan,
            renderedSamples: renderedSampleOffset()
        )
        guard let automaticBoundaryRequest,
              automaticBoundaryRequest.currentTimelineID == timeline?.id,
              case .once = responsivePlan.repetition else {
            return position
        }
        // A generic durability checkpoint may approach the finite sentinel,
        // but only the generation-bound physical boundary callback owns the
        // stage transition. This keeps checkpoint/callback order deterministic.
        let lastFiniteSample = max(
            responsivePlan.cursorSample,
            automaticBoundaryRequest.currentAuthoredDurationSamples - 1
        )
        return PlaybackPosition(
            cursorSample: min(position.cursorSample, lastFiniteSample),
            loopIteration: 0,
            loopDuration: 0
        )
    }

    private func renderedSampleOffset() -> Int64 {
        if let renderedSampleOffsetOverrideForTesting {
            return max(0, renderedSampleOffsetOverrideForTesting)
        }
        let renderedEnd = engine.manualRenderingMode == .offline
            ? engine.manualRenderingSampleTime
            : renderClockStorage.latestGraphSampleEnd.load(ordering: .acquiring)
        let delta = renderedEnd.subtractingReportingOverflow(
            renderClockBaseGraphSampleTime
        )
        guard !delta.overflow else {
            return 0
        }
        return max(0, delta.partialValue)
    }

    private func playbackPosition(
        for request: ResponsiveAudioTimelineTransportPlan,
        renderedSamples: Int64
    ) -> PlaybackPosition {
        let baseCursor = request.cursorSample
        let baseIteration = request.loopIteration
        switch request.repetition {
        case .once:
            let sum = baseCursor.addingReportingOverflow(renderedSamples)
            return PlaybackPosition(
                cursorSample: sum.overflow
                    ? plan?.endSample ?? baseCursor
                    : min(plan?.endSample ?? sum.partialValue, sum.partialValue),
                loopIteration: 0,
                loopDuration: 0
            )
        case let .loop(_, durationSamples):
            guard durationSamples > 0 else {
                return PlaybackPosition(
                    cursorSample: baseCursor,
                    loopIteration: baseIteration,
                    loopDuration: 0
                )
            }
            let relative = UInt64(baseCursor).addingReportingOverflow(
                UInt64(renderedSamples)
            )
            guard !relative.overflow else {
                return PlaybackPosition(
                    cursorSample: Int64.max % durationSamples,
                    loopIteration: .max,
                    loopDuration: durationSamples
                )
            }
            let additionalIterations = relative.partialValue / UInt64(durationSamples)
            let nextIteration = baseIteration.addingReportingOverflow(
                additionalIterations
            )
            return PlaybackPosition(
                cursorSample: Int64(relative.partialValue % UInt64(durationSamples)),
                loopIteration: nextIteration.overflow ? .max : nextIteration.partialValue,
                loopDuration: durationSamples
            )
        }
    }

    private func makeTransitionBoundary(
        for request: ResponsiveAudioTimelineTransportPlan,
        sampleRate: Int,
        observation: RenderClockObservation
    ) throws -> TransitionBoundary {
        if let pendingPhysicalTransition,
           observation.graphSampleTime < pendingPhysicalTransition.graphSampleTime {
            let remaining = Int64(pendingPhysicalTransition.graphSampleTime)
                - observation.graphSampleTime
            let projectedFrames = observation.renderedOffset
                .addingReportingOverflow(remaining)
            guard !projectedFrames.overflow else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            return TransitionBoundary(
                graphSampleTime: pendingPhysicalTransition.graphSampleTime,
                startTime: pendingPhysicalTransition.startTime,
                leadSeconds: Double(remaining) / Double(sampleRate),
                projectedPosition: playbackPosition(
                    for: request,
                    renderedSamples: projectedFrames.partialValue
                )
            )
        }
        if pendingPhysicalTransition != nil {
            promotePendingPhysicalTransition()
        }
        let leadFrames: AVAudioFramePosition = engine.manualRenderingMode == .offline
            ? 128
            : AVAudioFramePosition(max(512, sampleRate / 10))
        let graphSample = observation.graphSampleTime.addingReportingOverflow(
            leadFrames
        )
        let projectedFrames = observation.renderedOffset
            .addingReportingOverflow(leadFrames)
        guard !graphSample.overflow, !projectedFrames.overflow else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        if engine.manualRenderingMode == .offline {
            return TransitionBoundary(
                graphSampleTime: AUEventSampleTime(graphSample.partialValue),
                startTime: AVAudioTime(
                    sampleTime: graphSample.partialValue,
                    atRate: Double(sampleRate)
                ),
                leadSeconds: Double(leadFrames) / Double(sampleRate),
                projectedPosition: playbackPosition(
                    for: request,
                    renderedSamples: projectedFrames.partialValue
                )
            )
        }
        guard let originHostTime = observation.hostTime else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        let leadSeconds = Double(leadFrames) / Double(sampleRate)
        let boundaryHostTime = originHostTime.addingReportingOverflow(
            AVAudioTime.hostTime(forSeconds: leadSeconds)
        )
        guard !boundaryHostTime.overflow else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        return TransitionBoundary(
            graphSampleTime: AUEventSampleTime(graphSample.partialValue),
            startTime: AVAudioTime(
                hostTime: boundaryHostTime.partialValue
            ),
            leadSeconds: leadSeconds,
            projectedPosition: playbackPosition(
                for: request,
                renderedSamples: projectedFrames.partialValue
            )
        )
    }

    private func nativeHapticBoundary(
        for boundary: TransitionBoundary,
        sampleRate: Int
    ) -> NativeTimelineHapticBoundary {
        nativeHapticBoundary(
            startTime: boundary.startTime,
            graphSampleTime: boundary.graphSampleTime,
            sampleRate: sampleRate
        )
    }

    private func nativeHapticBoundary(
        startTime: AVAudioTime,
        graphSampleTime: AUEventSampleTime?,
        sampleRate: Int
    ) -> NativeTimelineHapticBoundary {
        NativeTimelineHapticBoundary(
            graphSample: graphSampleTime ?? AUEventSampleTime(startTime.sampleTime),
            hostTime: startTime.isHostTimeValid ? startTime.hostTime : nil,
            sampleRate: sampleRate
        )
    }

    private func nativeHapticBoundaryAtFadeEnd(
        _ boundary: TransitionBoundary,
        durationSamples: Int64,
        sampleRate: Int
    ) throws -> NativeTimelineHapticBoundary {
        let endSample = boundary.graphSampleTime.addingReportingOverflow(
            durationSamples
        )
        guard !endSample.overflow else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        let endHostTime: UInt64?
        if boundary.startTime.isHostTimeValid {
            let hostDuration = AVAudioTime.hostTime(
                forSeconds: Double(durationSamples) / Double(sampleRate)
            )
            let endHost = boundary.startTime.hostTime.addingReportingOverflow(
                hostDuration
            )
            guard !endHost.overflow else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            endHostTime = endHost.partialValue
        } else {
            endHostTime = nil
        }
        return NativeTimelineHapticBoundary(
            graphSample: endSample.partialValue,
            hostTime: endHostTime,
            sampleRate: sampleRate
        )
    }

    private func captureRenderClockObservation() throws -> RenderClockObservation {
        let anchor: NativeRenderClockAnchor
        if engine.manualRenderingMode == .offline {
            anchor = NativeRenderClockAnchor(
                graphSampleEnd: engine.manualRenderingSampleTime,
                hostTimeAtGraphSampleEnd: nil
            )
        } else {
            guard let coherent = renderClockStorage.loadCoherentAnchor() else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            anchor = coherent
        }
        let graphSample = anchor.graphSampleEnd
        let delta = graphSample.subtractingReportingOverflow(
            renderClockBaseGraphSampleTime
        )
        guard !delta.overflow else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        let hostTime: UInt64?
        if engine.manualRenderingMode == .offline {
            hostTime = nil
        } else {
            // The source callback publishes this host time from the same
            // AudioTimeStamp as graphSampleEnd. No conversion through the
            // output node's potentially 44.1 kHz route domain is permitted.
            guard let coherentHostTime = anchor.hostTimeAtGraphSampleEnd else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            hostTime = coherentHostTime
        }
        return RenderClockObservation(
            graphSampleTime: graphSample,
            hostTime: hostTime,
            renderedOffset: max(0, delta.partialValue)
        )
    }

    private func rebaseRenderClock(to observation: RenderClockObservation) {
        renderClockBaseGraphSampleTime = observation.graphSampleTime
    }

    private func rebaseRenderClock(to boundary: TransitionBoundary) {
        renderClockBaseGraphSampleTime = AVAudioFramePosition(
            boundary.graphSampleTime
        )
    }

    private func resetRenderClockBase() {
        renderClockBaseGraphSampleTime = 0
    }

    private func promotePendingPhysicalTransitionIfNeeded() {
        guard let pendingPhysicalTransition else { return }
        let renderedEnd = engine.manualRenderingMode == .offline
            ? engine.manualRenderingSampleTime
            : renderClockStorage.latestGraphSampleEnd.load(ordering: .acquiring)
        guard renderedEnd >= pendingPhysicalTransition.graphSampleTime else {
            return
        }
        promotePendingPhysicalTransition()
    }

    private func promotePendingPhysicalTransition() {
        guard let pendingPhysicalTransition else { return }
        let cursorMappingGeneration =
            pendingPhysicalTransition.cursorMappingGeneration
        teardownRetiredNodes()
        if pendingPhysicalTransition.replacesConventionalBranch {
            stopCurrentHaptics()
            hapticPlayback = pendingPhysicalTransition.candidateHaptics
            hapticsAreAvailable = pendingPhysicalTransition.candidateHaptics != nil
            reassertCurrentHapticPreferenceFailClosed()
        }
        self.pendingPhysicalTransition = nil
        audioCursorFeedStorage.promoteScheduled(
            mappingGeneration: cursorMappingGeneration
        )
    }

    private func promoteAutomaticBoundaryIfNeeded() {
        guard let staged = stagedAutomaticBoundary else { return }
        let renderedEnd = engine.manualRenderingMode == .offline
            ? engine.manualRenderingSampleTime
            : renderClockStorage.latestGraphSampleEnd.load(ordering: .acquiring)
        guard renderedEnd >= staged.graphSampleTime else { return }
        promoteAutomaticBoundary(
            generation: staged.generation
        )
    }

    private func promoteAutomaticBoundary(
        generation: UInt64
    ) {
        guard state == .playing,
              let request = automaticBoundaryRequest,
              var staged = stagedAutomaticBoundary,
              request.generation == generation,
              staged.generation == generation,
              automaticBoundaryGeneration == generation else { return }
        let renderedEnd = engine.manualRenderingMode == .offline
            ? engine.manualRenderingSampleTime
            : renderClockStorage.latestGraphSampleEnd.load(ordering: .acquiring)
        guard renderedEnd >= staged.graphSampleTime else { return }

        let handler = request.handler
        automaticBoundaryTask?.cancel()
        automaticBoundaryTask = nil
        automaticBoundaryRequest = nil
        stagedAutomaticBoundary = nil
        automaticBoundaryGeneration &+= 1

        if let successor = request.successorPlan,
           let successorTimelinePlan = staged.successorTimelinePlan {
            teardownConventionalNodes(preparedSlices)
            teardownCommonLayers(commonLayers.values)
            teardownRetiredNodes()
            stopCurrentHaptics()
            stopPreparedHaptics(pendingPhysicalTransition?.candidateHaptics)
            pendingPhysicalTransition = nil

            preparedSlices = staged.successorSlices
            staged.successorSlices.removeAll()
            commonLayers = staged.successorCommonLayers
            staged.successorCommonLayers.removeAll()
            hapticPlayback = staged.successorHaptics
            staged.successorHaptics = nil
            hapticsAreAvailable = hapticPlayback != nil
            reassertCurrentHapticPreferenceFailClosed()

            timeline = successor.timeline
            plan = successorTimelinePlan
            responsivePlan = successor.replacingPosition(
                cursorSample: 0,
                loopIteration: 0
            )
            assetURLs = request.successorURLs
            preparedAssetMetadata = request.successorMetadata
            renderClockBaseGraphSampleTime = AVAudioFramePosition(
                staged.graphSampleTime
            )
            currentGraphStartTime = staged.startTime
            needsRebuildOnPlay = false
            state = .playing
            audioCursorFeedStorage.promoteScheduled(
                mappingGeneration: staged.cursorMappingGeneration
            )
            let snapshot = NativeTimelineTransportSnapshot(
                timelineID: successor.timeline.id,
                cursorSample: 0,
                loopIteration: 0,
                isPlaying: true
            )
            handler(.successorStarted(snapshot))
            return
        }

        let completedTimelineID = timeline?.id
        let completedSample = request.currentAuthoredDurationSamples
        if let currentRequest = responsivePlan {
            responsivePlan = currentRequest.replacingPosition(
                cursorSample: completedSample,
                loopIteration: 0
            )
        }
        beginAudioDurabilityStop()
        preparedSlices.forEach { $0.player.stop() }
        engine.stop()
        endAudioDurabilityEpochAfterEngineDrain()
        stopCurrentHaptics()
        stopPreparedHaptics(pendingPhysicalTransition?.candidateHaptics)
        pendingPhysicalTransition = nil
        releaseAudioSessionLease()
        teardownNodes()
        currentGraphStartTime = nil
        needsRebuildOnPlay = false
        state = .completed
        recordAudioCursor(kind: .completed, cursorSample: completedSample)
        handler(.completed(NativeTimelineTransportSnapshot(
            timelineID: completedTimelineID,
            cursorSample: completedSample,
            loopIteration: 0,
            isPlaying: false
        )))
    }

    private func stopPreparedHaptics(
        _ prepared: (any NativeTimelineHapticPlayback)?
    ) {
        guard let prepared else { return }
        hapticScheduler.stopImmediately(prepared)
    }

    public func stop() {
        stop(clearTimeline: true)
    }

    private func rebuild(
        at cursorSample: Int64,
        metadata suppliedMetadata: [String: AudioAssetMetadata]? = nil
    ) throws {
        guard let timeline else { throw NativeTimelineTransportError.notPrepared }
        invalidateAutomaticBoundary(clearRequest: false)
        currentGraphStartTime = nil
        teardownNodes()

        var metadata = suppliedMetadata ?? [:]
        if suppliedMetadata == nil {
            for path in assetURLs.keys.sorted() {
                let url = try freshlyVerifiedURL(for: path)
                let file: AVAudioFile
                do {
                    file = try AVAudioFile(forReading: url)
                } catch {
                    throw NativeTimelineTransportError.audioFileCouldNotOpen(path)
                }
                metadata[path] = AudioAssetMetadata(
                    path: path,
                    sampleRate: Int(file.processingFormat.sampleRate.rounded()),
                    frameCount: file.length,
                    channelCount: Int(file.processingFormat.channelCount)
                )
            }
        }
        let newPlan = try TimelinePlaybackPlanner.makePlan(
            timeline: timeline,
            cursorSample: cursorSample,
            assetMetadata: metadata
        )
        plan = newPlan
        do {
            try attachNodes(for: newPlan)
            try attachRenderClock(sampleRate: newPlan.sampleRate)
            try prepareHaptics(for: newPlan)
            graphRouteFormatAtLastRebuild = activeRouteFormat
        } catch {
            teardownNodes()
            throw error
        }
    }

    private func attachNodes(for plan: TimelinePlaybackPlan) throws {
        let commonCueIDs = Set(responsivePlan?.causalMix?.layers.map(\.cueID) ?? [])
        try ensureRoleMixers(for: plan.audioSlices.map(\.role))
        if let causalMix = responsivePlan?.causalMix {
            try attachCommonLayers(causalMix, cursorSample: plan.cursorSample)
        }
        try attachConventionalNodes(for: plan, excluding: commonCueIDs)
        applyRoleMixerVolumes()
    }

    private func attachRenderClock(sampleRate: Int) throws {
        if engine.manualRenderingMode == .offline {
            renderClockSource = nil
            renderClockStorage = NativeRenderClockStorage()
            renderClockBaseGraphSampleTime = engine.manualRenderingSampleTime
            return
        }
        guard renderClockSource == nil,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Double(sampleRate),
                  channels: 1,
                  interleaved: false
              ) else {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        let storage = NativeRenderClockStorage()
        let source = makeNativeRenderClockSource(
            format: format,
            storage: storage
        )
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        renderClockStorage = storage
        renderClockSource = source
        renderClockBaseGraphSampleTime = 0
    }

    private func attachConventionalNodes(
        for plan: TimelinePlaybackPlan,
        excluding commonCueIDs: Set<AudioCueID>
    ) throws {
        guard let timeline else {
            throw NativeTimelineTransportError.notPrepared
        }
        if case let .loop(_, durationSamples) = responsivePlan?.repetition {
            let audibleEvents = timeline.events.filter {
                $0.role != .silence && !commonCueIDs.contains($0.cueID)
            }
            try ensureRoleMixers(for: audibleEvents.map(\.role))
            for event in audibleEvents {
                guard let mixer = roleMixers[event.role.rawValue],
                      let path = event.assetPath else {
                    throw NativeTimelineTransportError.audioFileCouldNotOpen(
                        event.assetPath ?? event.cueID.rawValue
                    )
                }
                let url = try freshlyVerifiedURL(for: path)
                let file: AVAudioFile
                do {
                    file = try AVAudioFile(forReading: url)
                } catch {
                    throw NativeTimelineTransportError.audioFileCouldNotOpen(path)
                }
                let buffers = try makeTimelineLoopBuffers(
                    file: file,
                    path: path,
                    event: event,
                    loopDurationSamples: durationSamples,
                    cursorSample: plan.cursorSample
                )
                preparedSlices.append(try attachConventionalSlice(
                    cueID: event.cueID,
                    role: event.role,
                    gain: event.gain,
                    oneShotPlan: nil,
                    file: nil,
                    loopBuffers: buffers,
                    format: file.processingFormat,
                    roleMixer: mixer
                ))
            }
            return
        }

        try ensureRoleMixers(for: plan.audioSlices.map(\.role))
        for slice in plan.audioSlices where !commonCueIDs.contains(slice.cueID) {
            guard let mixer = roleMixers[slice.role.rawValue] else {
                throw NativeTimelineTransportError.audioFileCouldNotOpen(slice.assetPath)
            }
            let url = try freshlyVerifiedURL(for: slice.assetPath)
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: url)
            } catch {
                throw NativeTimelineTransportError.audioFileCouldNotOpen(slice.assetPath)
            }
            preparedSlices.append(try attachConventionalSlice(
                cueID: slice.cueID,
                role: slice.role,
                gain: slice.gain,
                oneShotPlan: slice,
                file: file,
                loopBuffers: [],
                format: file.processingFormat,
                roleMixer: mixer
            ))
        }
    }

    private func attachConventionalSlice(
        cueID: AudioCueID,
        role: AudioTrackRole,
        gain: Double,
        oneShotPlan: ScheduledAudioSlice?,
        file: AVAudioFile?,
        loopBuffers: [AVAudioPCMBuffer],
        format: AVAudioFormat,
        roleMixer: AVAudioMixerNode
    ) throws -> PreparedAudioSlice {
        let player = AVAudioPlayerNode()
        if failNextGainUnitInstantiationForTesting {
            failNextGainUnitInstantiationForTesting = false
            throw NativeTimelineTransportInjectedFailure.gainUnitInstantiation
        }
        let gainNode = try SampleAccurateGainNode.make(
            initialGain: AUValue(gain),
            durabilityGate: audioDurabilityGate
        )
        player.volume = 1
        engine.attach(player)
        engine.attach(gainNode.node)
        engine.connect(player, to: gainNode.node, format: format)
        engine.connect(gainNode.node, to: roleMixer, format: format)
        if failConventionalAttachCueForTesting == cueID {
            failConventionalAttachCueForTesting = nil
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(gainNode.node)
            engine.detach(player)
            engine.detach(gainNode.node)
            throw NativeTimelineTransportInjectedFailure.conventionalAttach(cueID)
        }
        return PreparedAudioSlice(
            cueID: cueID,
            role: role,
            oneShotPlan: oneShotPlan,
            file: file,
            loopBuffers: loopBuffers,
            player: player,
            gainNode: gainNode
        )
    }

    /// Builds and attaches a complete replacement branch while the active
    /// branch remains untouched. Every asset is resolved again immediately
    /// before its AVAudioFile is opened. A partial candidate is detached on
    /// any failure, including an injected graph-attach fault.
    private func stageConventionalNodes(
        timeline: AudioTimeline,
        plan: TimelinePlaybackPlan,
        repetition: ResponsiveAudioPlaybackRepetition,
        excluding commonCueIDs: Set<AudioCueID>,
        resolver: any OfflineAudioAssetResolving
    ) throws -> [PreparedAudioSlice] {
        let originalMixerKeys = Set(roleMixers.keys)
        var staged: [PreparedAudioSlice] = []
        do {
            if case let .loop(_, durationSamples) = repetition {
                let events = timeline.events.filter {
                    $0.role != .silence && !commonCueIDs.contains($0.cueID)
                }
                try ensureRoleMixers(for: events.map(\.role))
                for event in events {
                    guard let roleMixer = roleMixers[event.role.rawValue],
                          let path = event.assetPath else {
                        throw NativeTimelineTransportError.audioFileCouldNotOpen(
                            event.assetPath ?? event.cueID.rawValue
                        )
                    }
                    let url = try resolver.url(for: path)
                    let file: AVAudioFile
                    do {
                        file = try AVAudioFile(forReading: url)
                    } catch {
                        throw NativeTimelineTransportError.audioFileCouldNotOpen(path)
                    }
                    let buffers = try makeTimelineLoopBuffers(
                        file: file,
                        path: path,
                        event: event,
                        loopDurationSamples: durationSamples,
                        cursorSample: plan.cursorSample
                    )
                    staged.append(try attachConventionalSlice(
                        cueID: event.cueID,
                        role: event.role,
                        gain: event.gain,
                        oneShotPlan: nil,
                        file: nil,
                        loopBuffers: buffers,
                        format: file.processingFormat,
                        roleMixer: roleMixer
                    ))
                }
            } else {
                let slices = plan.audioSlices.filter {
                    !commonCueIDs.contains($0.cueID)
                }
                try ensureRoleMixers(for: slices.map(\.role))
                for slice in slices {
                    guard let roleMixer = roleMixers[slice.role.rawValue] else {
                        throw NativeTimelineTransportError.audioFileCouldNotOpen(
                            slice.assetPath
                        )
                    }
                    let url = try resolver.url(for: slice.assetPath)
                    let file: AVAudioFile
                    do {
                        file = try AVAudioFile(forReading: url)
                    } catch {
                        throw NativeTimelineTransportError.audioFileCouldNotOpen(
                            slice.assetPath
                        )
                    }
                    staged.append(try attachConventionalSlice(
                        cueID: slice.cueID,
                        role: slice.role,
                        gain: slice.gain,
                        oneShotPlan: slice,
                        file: file,
                        loopBuffers: [],
                        format: file.processingFormat,
                        roleMixer: roleMixer
                    ))
                }
            }
            applyRoleMixerVolumes()
            return staged
        } catch {
            teardownConventionalNodes(staged)
            teardownRoleMixers(createdAfter: originalMixerKeys)
            throw error
        }
    }

    private func teardownRoleMixers(createdAfter originalKeys: Set<String>) {
        for key in Set(roleMixers.keys).subtracting(originalKeys) {
            guard let mixer = roleMixers.removeValue(forKey: key) else { continue }
            engine.disconnectNodeInput(mixer)
            engine.disconnectNodeOutput(mixer)
            engine.detach(mixer)
        }
    }

    private func ensureRoleMixers(for roles: [AudioTrackRole]) throws {
        for role in roles.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard role != .silence else { continue }
            if roleMixers[role.rawValue] != nil { continue }
            let mixer = AVAudioMixerNode()
            engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: nil)
            roleMixers[role.rawValue] = mixer
        }
    }

    private func attachCommonLayers(
        _ mix: ResponsiveAudioCausalMixPlaybackPlan,
        cursorSample: Int64
    ) throws {
        guard commonLayers.isEmpty else {
            throw NativeTimelineTransportError.causalMixContractViolation(
                "common material players were already attached"
            )
        }
        guard let assetResolver else {
            throw NativeTimelineTransportError.notPrepared
        }
        commonLayers = try stageCommonLayers(
            mix,
            cursorSample: cursorSample,
            resolver: assetResolver
        )
    }

    private func stageCommonLayers(
        _ mix: ResponsiveAudioCausalMixPlaybackPlan,
        cursorSample: Int64,
        resolver: any OfflineAudioAssetResolving
    ) throws -> [ResponsiveAudioMaterialLayerID: PreparedCommonLayer] {
        var staged: [ResponsiveAudioMaterialLayerID: PreparedCommonLayer] = [:]
        do {
        for target in mix.layers {
            guard let roleMixer = roleMixers[target.role.rawValue] else {
                throw NativeTimelineTransportError.causalMixContractViolation(
                    "missing role mixer for \(target.layerID.rawValue)"
                )
            }
            let url = try resolver.url(for: target.assetPath)
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: url)
            } catch {
                throw NativeTimelineTransportError.audioFileCouldNotOpen(target.assetPath)
            }
            let (buffers, scheduleCount) = try makeLoopBuffers(
                file: file,
                path: target.assetPath,
                cursorSample: cursorSample,
                durationSamples: target.durationSamples
            )
            guard buffers.last != nil else {
                throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(
                    target.assetPath
                )
            }
            let player = AVAudioPlayerNode()
            let gainNode = try SampleAccurateGainNode.make(
                initialGain: AUValue(target.targetGain),
                durabilityGate: audioDurabilityGate
            )
            engine.attach(player)
            engine.attach(gainNode.node)
            engine.connect(player, to: gainNode.node, format: file.processingFormat)
            engine.connect(gainNode.node, to: roleMixer, format: file.processingFormat)
            let prepared = PreparedCommonLayer(
                target: target,
                player: player,
                gainNode: gainNode,
                buffers: buffers,
                targetGain: target.targetGain,
                scheduleCount: scheduleCount
            )
            scheduleCommonBuffers(prepared)
            staged[target.layerID] = prepared
        }
            return staged
        } catch {
            teardownCommonLayers(staged.values)
            throw error
        }
    }

    private func scheduleCommonBuffers(_ common: PreparedCommonLayer) {
        if common.buffers.count == 2 {
            common.player.scheduleBuffer(common.buffers[0])
        }
        if let fullLoop = common.buffers.last {
            common.player.scheduleBuffer(fullLoop, at: nil, options: [.loops])
        }
    }

    private func makeLoopBuffers(
        file: AVAudioFile,
        path: String,
        cursorSample: Int64,
        durationSamples: Int64
    ) throws -> ([AVAudioPCMBuffer], Int) {
        guard durationSamples > 0,
              durationSamples <= Int64(UInt32.max),
              cursorSample >= 0,
              cursorSample < durationSamples,
              file.length >= durationSamples else {
            throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(path)
        }
        func read(start: Int64, count: Int64) throws -> AVAudioPCMBuffer {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(count)
            ) else {
                throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(path)
            }
            file.framePosition = AVAudioFramePosition(start)
            do {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
            } catch {
                throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(path)
            }
            guard buffer.frameLength == AVAudioFrameCount(count) else {
                throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(path)
            }
            return buffer
        }
        let fullLoop = try read(start: 0, count: durationSamples)
        guard cursorSample > 0 else { return ([fullLoop], 1) }
        let tail = try read(
            start: cursorSample,
            count: durationSamples - cursorSample
        )
        return ([tail, fullLoop], 2)
    }

    private func makeTimelineLoopBuffers(
        file: AVAudioFile,
        path: String,
        event: AudioEvent,
        loopDurationSamples: Int64,
        cursorSample: Int64
    ) throws -> [AVAudioPCMBuffer] {
        let format = file.processingFormat
        guard loopDurationSamples > 0,
              loopDurationSamples <= Int64(UInt32.max),
              cursorSample >= 0,
              cursorSample < loopDurationSamples,
              event.startSample >= 0,
              event.durationSamples > 0,
              event.startSample + event.durationSamples <= loopDurationSamples,
              file.length >= event.durationSamples,
              format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved else {
            throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(path)
        }
        guard let fullTimeline = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(loopDurationSamples)
        ), let source = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(event.durationSamples)
        ) else {
            throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(path)
        }
        fullTimeline.frameLength = AVAudioFrameCount(loopDurationSamples)
        try zeroFloatBuffer(fullTimeline)
        file.framePosition = 0
        do {
            try file.read(
                into: source,
                frameCount: AVAudioFrameCount(event.durationSamples)
            )
        } catch {
            throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(path)
        }
        guard source.frameLength == AVAudioFrameCount(event.durationSamples) else {
            throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(path)
        }
        try copyFloatFrames(
            from: source,
            sourceStart: 0,
            to: fullTimeline,
            destinationStart: AVAudioFrameCount(event.startSample),
            frameCount: AVAudioFrameCount(event.durationSamples)
        )
        guard cursorSample > 0 else { return [fullTimeline] }
        let tailLength = loopDurationSamples - cursorSample
        guard let tail = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(tailLength)
        ) else {
            throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(path)
        }
        tail.frameLength = AVAudioFrameCount(tailLength)
        try copyFloatFrames(
            from: fullTimeline,
            sourceStart: AVAudioFrameCount(cursorSample),
            to: tail,
            destinationStart: 0,
            frameCount: AVAudioFrameCount(tailLength)
        )
        return [tail, fullTimeline]
    }

    private func retargetStagedLoopBuffers(
        _ slices: [PreparedAudioSlice],
        cursorSample: Int64
    ) throws {
        guard cursorSample >= 0 else {
            throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(
                "negative-transition-cursor"
            )
        }
        for slice in slices where !slice.loopBuffers.isEmpty {
            guard let fullLoop = slice.loopBuffers.last,
                  cursorSample < Int64(fullLoop.frameLength) else {
                throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(
                    slice.cueID.rawValue
                )
            }
            guard cursorSample > 0 else {
                slice.loopBuffers = [fullLoop]
                continue
            }
            let tailLength = Int64(fullLoop.frameLength) - cursorSample
            guard let tail = AVAudioPCMBuffer(
                pcmFormat: fullLoop.format,
                frameCapacity: AVAudioFrameCount(tailLength)
            ) else {
                throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(
                    slice.cueID.rawValue
                )
            }
            tail.frameLength = AVAudioFrameCount(tailLength)
            try copyFloatFrames(
                from: fullLoop,
                sourceStart: AVAudioFrameCount(cursorSample),
                to: tail,
                destinationStart: 0,
                frameCount: AVAudioFrameCount(tailLength)
            )
            slice.loopBuffers = [tail, fullLoop]
        }
    }

    private func zeroFloatBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let channels = buffer.floatChannelData else {
            throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(
                "unsupported-float-buffer"
            )
        }
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Float>.size
        for channel in 0 ..< Int(buffer.format.channelCount) {
            memset(channels[channel], 0, byteCount)
        }
    }

    private func copyFloatFrames(
        from source: AVAudioPCMBuffer,
        sourceStart: AVAudioFrameCount,
        to destination: AVAudioPCMBuffer,
        destinationStart: AVAudioFrameCount,
        frameCount: AVAudioFrameCount
    ) throws {
        guard source.format.channelCount == destination.format.channelCount,
              let sourceChannels = source.floatChannelData,
              let destinationChannels = destination.floatChannelData else {
            throw NativeTimelineTransportError.causalLoopBufferCouldNotPrepare(
                "incompatible-float-buffer"
            )
        }
        let byteCount = Int(frameCount) * MemoryLayout<Float>.size
        for channel in 0 ..< Int(source.format.channelCount) {
            memcpy(
                destinationChannels[channel].advanced(by: Int(destinationStart)),
                sourceChannels[channel].advanced(by: Int(sourceStart)),
                byteCount
            )
        }
    }

    private func validatedCausalTargetChanges(
        _ mix: ResponsiveAudioCausalMixPlaybackPlan,
        ramp: Bool,
        startSample: AUEventSampleTime?
    ) throws -> [CausalTargetChange] {
        guard mix.rampDurationSamples > 0,
              mix.rampDurationSamples <= Int64(UInt32.max),
              mix.layers.allSatisfy({
                  $0.targetGain.isFinite
                      && $0.targetGain >= 0
                      && $0.targetGain <= 4
              }) else {
            throw NativeTimelineTransportError.causalMixContractViolation(
                "causal gain automation is outside the public render range"
            )
        }
        for target in mix.layers {
            guard commonLayers[target.layerID] != nil else {
                throw NativeTimelineTransportError.causalMixContractViolation(
                    "missing retained player for \(target.layerID.rawValue)"
                )
            }
        }
        if ramp, startSample == nil {
            throw NativeTimelineTransportError.renderClockUnavailable
        }
        return mix.layers.compactMap { target in
            guard let layer = commonLayers[target.layerID],
                  target.targetGain != layer.targetGain else { return nil }
            return CausalTargetChange(
                layer: layer,
                targetGain: target.targetGain
            )
        }
    }

    private func applyCausalTargetChanges(
        _ changes: [CausalTargetChange],
        rampDurationSamples: Int64,
        ramp: Bool,
        startSample: AUEventSampleTime?
    ) {
        for change in changes {
            let layer = change.layer
            let target = AUValue(change.targetGain)
            if ramp, let startSample, rampDurationSamples > 0 {
                layer.gainNode.audioUnit.scheduleParameterBlock(
                    startSample,
                    AUAudioFrameCount(rampDurationSamples),
                    layer.gainNode.gainParameter.address,
                    target
                )
                layer.rampScheduleCount += 1
                layer.lastRampDurationSamples = rampDurationSamples
                layer.lastRampStartSample = startSample
            } else {
                layer.gainNode.gainParameter.value = target
            }
            layer.targetGain = change.targetGain
        }
    }

    private func scheduleMute(
        for slices: [PreparedAudioSlice],
        at sample: AUEventSampleTime
    ) {
        for slice in slices {
            slice.gainNode.audioUnit.scheduleParameterBlock(
                sample,
                0,
                slice.gainNode.gainParameter.address,
                0
            )
            slice.muteRenderSample = sample
        }
    }

    private func scheduleFade(
        for slices: [PreparedAudioSlice],
        at sample: AUEventSampleTime,
        durationSamples: Int64
    ) {
        for slice in slices {
            slice.gainNode.audioUnit.scheduleParameterBlock(
                sample,
                AUAudioFrameCount(durationSamples),
                slice.gainNode.gainParameter.address,
                0
            )
            slice.fadeRenderSample = sample
            slice.fadeDurationSamples = durationSamples
        }
    }

    private func scheduleMute(
        for layers: Dictionary<ResponsiveAudioMaterialLayerID, PreparedCommonLayer>.Values,
        at sample: AUEventSampleTime
    ) {
        for layer in layers {
            layer.gainNode.audioUnit.scheduleParameterBlock(
                sample,
                0,
                layer.gainNode.gainParameter.address,
                0
            )
            layer.targetGain = 0
            layer.lastRampDurationSamples = 0
            layer.lastRampStartSample = sample
        }
    }

    private func scheduleFade(
        for layers: Dictionary<ResponsiveAudioMaterialLayerID, PreparedCommonLayer>.Values,
        at sample: AUEventSampleTime,
        durationSamples: Int64
    ) {
        for layer in layers {
            layer.gainNode.audioUnit.scheduleParameterBlock(
                sample,
                AUAudioFrameCount(durationSamples),
                layer.gainNode.gainParameter.address,
                0
            )
            layer.targetGain = 0
            layer.lastRampDurationSamples = durationSamples
            layer.lastRampStartSample = sample
        }
    }

    private func validateRetainedCommonLayerContract(
        current: ResponsiveAudioCausalMixPlaybackPlan,
        requested: ResponsiveAudioCausalMixPlaybackPlan,
        requestedRepetition: ResponsiveAudioPlaybackRepetition
    ) throws {
        guard current.rampDurationSamples == requested.rampDurationSamples,
              current.layers.count == requested.layers.count,
              commonLayers.count == current.layers.count,
              case let .loop(_, durationSamples) = requestedRepetition else {
            throw NativeTimelineTransportError.causalMixContractViolation(
                "a causal transition requires one unchanged loop contract"
            )
        }
        for (old, new) in zip(current.layers, requested.layers) {
            guard old.layerID == new.layerID,
                  old.role == new.role,
                  old.assetPath == new.assetPath,
                  old.startSample == new.startSample,
                  old.durationSamples == new.durationSamples,
                  new.startSample == 0,
                  new.durationSamples == durationSamples,
                  commonLayers[new.layerID] != nil else {
                throw NativeTimelineTransportError.causalMixContractViolation(
                    "phase transition changed a retained material layer"
                )
            }
        }
    }

    private func resolveMetadata(
        for timeline: AudioTimeline,
        resolver: any OfflineAudioAssetResolving
    ) throws -> ResolvedTimelineAssets {
        var metadata: [String: AudioAssetMetadata] = [:]
        var urls: [String: URL] = [:]
        for event in timeline.events where event.role != .silence {
            guard let path = event.assetPath else {
                throw NativeTimelineTransportError.audioFileCouldNotOpen(
                    event.cueID.rawValue
                )
            }
            if metadata[path] != nil { continue }
            let url = try resolver.url(for: path)
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: url)
            } catch {
                throw NativeTimelineTransportError.audioFileCouldNotOpen(path)
            }
            metadata[path] = AudioAssetMetadata(
                path: path,
                sampleRate: Int(file.processingFormat.sampleRate.rounded()),
                frameCount: file.length,
                channelCount: Int(file.processingFormat.channelCount)
            )
            urls[path] = url
        }
        return ResolvedTimelineAssets(metadata: metadata, urls: urls)
    }

    private func scheduleConventionalSlices(
        _ slices: [PreparedAudioSlice],
        plan: TimelinePlaybackPlan,
        startTime: AVAudioTime,
        renderSample: AUEventSampleTime?
    ) {
        for prepared in slices {
            if !prepared.loopBuffers.isEmpty {
                if prepared.loopBuffers.count == 2 {
                    prepared.player.scheduleBuffer(prepared.loopBuffers[0])
                }
                if let fullLoop = prepared.loopBuffers.last {
                    prepared.player.scheduleBuffer(
                        fullLoop,
                        at: nil,
                        options: [.loops]
                    )
                }
            } else if let slice = prepared.oneShotPlan,
                      let file = prepared.file {
                let eventTime: AVAudioTime
                if startTime.isHostTimeValid {
                    let offsetSeconds = Double(slice.timelineStartOffset)
                        / Double(plan.sampleRate)
                    eventTime = AVAudioTime(
                        hostTime: startTime.hostTime
                            &+ AVAudioTime.hostTime(forSeconds: offsetSeconds)
                    )
                } else {
                    eventTime = AVAudioTime(
                        sampleTime: startTime.sampleTime
                            + AVAudioFramePosition(slice.timelineStartOffset),
                        atRate: Double(plan.sampleRate)
                    )
                }
                prepared.player.scheduleSegment(
                    file,
                    startingFrame: AVAudioFramePosition(slice.assetStartFrame),
                    frameCount: AVAudioFrameCount(slice.frameCount),
                    at: eventTime
                )
            }
            prepared.startRenderSample = renderSample
            prepared.player.play(at: startTime)
        }
    }

    private func makePreparedHaptics(
        for plan: TimelinePlaybackPlan
    ) throws -> (any NativeTimelineHapticPlayback)? {
        if failNextHapticPreparationForTesting {
            failNextHapticPreparationForTesting = false
            throw NativeTimelineTransportInjectedFailure.hapticPreparation
        }
        do {
            return try hapticScheduler.prepare(
                haptics: plan.haptics,
                sampleRate: plan.sampleRate
            )
        } catch {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
    }

    private func prepareHaptics(for plan: TimelinePlaybackPlan) throws {
        stopCurrentHaptics()
        let prepared = try makePreparedHaptics(for: plan)
        hapticPlayback = prepared
        hapticsAreAvailable = prepared != nil
    }

    private func startHaptics(
        plan _: TimelinePlaybackPlan,
        at boundary: NativeTimelineHapticBoundary
    ) throws {
        if failNextHapticStartForTesting {
            failNextHapticStartForTesting = false
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
        guard let hapticPlayback else { return }
        do {
            try hapticScheduler.start(
                hapticPlayback,
                context: hapticRuntimeContext(
                    boundary: boundary,
                    playback: hapticPlayback
                ),
                enabled: routingPolicy.timelineHapticsAreEnabled
            )
        } catch {
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
    }

    private func startPreparedHaptics(
        _ prepared: any NativeTimelineHapticPlayback,
        at boundary: NativeTimelineHapticBoundary
    ) throws {
        do {
            try hapticScheduler.start(
                prepared,
                context: hapticRuntimeContext(
                    boundary: boundary,
                    playback: prepared
                ),
                enabled: routingPolicy.timelineHapticsAreEnabled
            )
        } catch {
            hapticScheduler.stopImmediately(prepared)
            throw NativeTimelineTransportError.hapticPatternCouldNotPrepare
        }
    }

    private func hapticRuntimeContext(
        boundary: NativeTimelineHapticBoundary,
        playback: any NativeTimelineHapticPlayback
    ) -> NativeTimelineHapticRuntimeContext {
        let identity = ObjectIdentifier(playback)
        return NativeTimelineHapticRuntimeContext(
            boundary: boundary,
            currentRenderAnchor: { [weak self] in
                guard let self,
                      self.engine.manualRenderingMode != .offline else {
                    return nil
                }
                return self.renderClockStorage.loadCoherentAnchor()
            },
            recoveryIsAuthorized: { [weak self] in
                guard let self,
                      self.state == .playing,
                      self.engine.isRunning else { return false }
                return self.ownsHapticPlayback(identity)
            },
            status: { [weak self] status in
                self?.handleHapticRuntimeStatus(status, identity: identity)
            }
        )
    }

    private func ownsHapticPlayback(_ identity: ObjectIdentifier) -> Bool {
        if hapticPlayback.map(ObjectIdentifier.init) == identity { return true }
        if pendingPhysicalTransition?.candidateHaptics
            .map(ObjectIdentifier.init) == identity { return true }
        if stagedAutomaticBoundary?.successorHaptics
            .map(ObjectIdentifier.init) == identity { return true }
        return false
    }

    private func handleHapticRuntimeStatus(
        _ status: NativeTimelineHapticRuntimeStatus,
        identity: ObjectIdentifier
    ) {
        guard hapticPlayback.map(ObjectIdentifier.init) == identity else {
            return
        }
        switch status {
        case .available:
            hapticsAreAvailable = true
        case .requiresExplicitResume, .exhausted, .failedClosed:
            hapticsAreAvailable = false
        }
    }

    private func applyRoleMixerVolumes() {
        for (rawRole, mixer) in roleMixers {
            guard let role = AudioTrackRole(rawValue: rawRole),
                  let volume = routingPolicy.mixerOutputVolume(for: role) else {
                continue
            }
            mixer.outputVolume = volume
        }
    }

    /// Keeps the integrity decision adjacent to each AVAudioFile open. A URL
    /// cached during an earlier prepare/pause cycle is never treated as proof
    /// that the current file bytes still match the signed manifest.
    private func freshlyVerifiedURL(for path: String) throws -> URL {
        guard let assetResolver else {
            throw NativeTimelineTransportError.audioFileCouldNotOpen(path)
        }
        let url = try assetResolver.url(for: path)
        assetURLs[path] = url
        return url
    }

    private func applyTimelineHapticPreferenceFailClosed() {
        reassertCurrentHapticPreferenceFailClosed()
        guard var pending = pendingPhysicalTransition,
              let candidate = pending.candidateHaptics else { return }
        do {
            try hapticScheduler.setEnabled(
                routingPolicy.timelineHapticsAreEnabled,
                for: candidate
            )
        } catch {
            // A pending preference failure can silence only that future
            // branch. The current owner remains valid until the boundary.
            hapticScheduler.stopImmediately(candidate)
            pending.candidateHaptics = nil
            pendingPhysicalTransition = pending
        }
    }

    private func reassertCurrentHapticPreferenceFailClosed() {
        guard let hapticPlayback else {
            hapticsAreAvailable = false
            return
        }
        do {
            try hapticScheduler.setEnabled(
                routingPolicy.timelineHapticsAreEnabled,
                for: hapticPlayback
            )
            hapticsAreAvailable = true
        } catch {
            // The other branch (including a pending candidate) is not touched.
            hapticScheduler.stopImmediately(hapticPlayback)
            self.hapticPlayback = nil
            hapticsAreAvailable = false
        }
    }

    private func stopCurrentHaptics() {
        if let hapticPlayback {
            hapticScheduler.stopImmediately(hapticPlayback)
        }
        hapticPlayback = nil
        hapticsAreAvailable = false
    }

    private func releaseAudioSessionLease() {
        audioSessionLease?.release()
        audioSessionLease = nil
    }

    private func recordAudioCursor(
        kind: AudioCursorCheckpointKind,
        cursorSample: Int64
    ) {
        guard let timeline, let plan else { return }
        performanceRecorder?.recordAudioCursor(
            timelineID: timeline.id.rawValue,
            sampleRate: plan.sampleRate,
            cursorSample: cursorSample,
            kind: kind
        )
    }

    private func teardownNodes() {
        stopPreparedHaptics(pendingPhysicalTransition?.candidateHaptics)
        pendingPhysicalTransition = nil
        teardownConventionalNodes()
        teardownRetiredNodes()
        teardownCommonLayers(commonLayers.values)
        commonLayers.removeAll()
        if let renderClockSource {
            engine.disconnectNodeOutput(renderClockSource)
            engine.detach(renderClockSource)
        }
        renderClockSource = nil
        renderClockStorage = NativeRenderClockStorage()
        resetRenderClockBase()
        for mixer in roleMixers.values {
            engine.disconnectNodeInput(mixer)
            engine.disconnectNodeOutput(mixer)
            engine.detach(mixer)
        }
        roleMixers.removeAll()
        engine.reset()
    }

    private func teardownConventionalNodes() {
        teardownConventionalNodes(preparedSlices)
        preparedSlices.removeAll()
    }

    private func teardownConventionalNodes(_ slices: [PreparedAudioSlice]) {
        slices.forEach {
            $0.player.stop()
            engine.disconnectNodeOutput($0.player)
            engine.disconnectNodeOutput($0.gainNode.node)
            engine.detach($0.player)
            engine.detach($0.gainNode.node)
        }
    }

    private func teardownCommonLayers<S: Sequence>(
        _ layers: S
    ) where S.Element == PreparedCommonLayer {
        for layer in layers {
            layer.player.stop()
            engine.disconnectNodeOutput(layer.player)
            engine.disconnectNodeOutput(layer.gainNode.node)
            engine.detach(layer.player)
            engine.detach(layer.gainNode.node)
        }
    }

    private func teardownRetiredNodes() {
        teardownConventionalNodes(retiredSlices)
        retiredSlices.removeAll()
        teardownCommonLayers(retiredCommonLayers)
        retiredCommonLayers.removeAll()
    }

    private func stop(clearTimeline: Bool) {
        let outgoingTail = activeOutgoingTail
        activeOutgoingTail = nil
        activeOutgoingTailGeneration = nil
        outgoingTailGeneration &+= 1
        beginAudioDurabilityStop()
        outgoingTail?.stopImmediately()
        invalidateAutomaticBoundary(clearRequest: true)
        currentGraphStartTime = nil
        preparedSlices.forEach { $0.player.stop() }
        engine.stop()
        endAudioDurabilityEpochAfterEngineDrain()
        stopCurrentHaptics()
        releaseAudioSessionLease()
        teardownNodes()
        plan = nil
        if clearTimeline {
            timeline = nil
            responsivePlan = nil
            assetURLs = [:]
            preparedAssetMetadata = [:]
            assetResolver = nil
        }
        activeRouteFormat = nil
        graphRouteFormatAtLastRebuild = nil
        needsRebuildOnPlay = false
        state = .idle
    }

    var preparedPlanForTesting: TimelinePlaybackPlan? { plan }

    func commonPlayerIdentityForTesting(
        _ layerID: ResponsiveAudioMaterialLayerID
    ) -> ObjectIdentifier? {
        commonLayers[layerID].map { ObjectIdentifier($0.player) }
    }

    func commonPlayerScheduleCountForTesting(
        _ layerID: ResponsiveAudioMaterialLayerID
    ) -> Int? {
        commonLayers[layerID]?.scheduleCount
    }

    func causalTargetGainForTesting(
        _ layerID: ResponsiveAudioMaterialLayerID
    ) -> Double? {
        commonLayers[layerID]?.targetGain
    }

    func causalRampDurationForTesting(
        _ layerID: ResponsiveAudioMaterialLayerID
    ) -> Int64? {
        commonLayers[layerID]?.lastRampDurationSamples
    }

    func causalRampScheduleCountForTesting(
        _ layerID: ResponsiveAudioMaterialLayerID
    ) -> Int? {
        commonLayers[layerID]?.rampScheduleCount
    }

    func causalRampStartSampleForTesting(
        _ layerID: ResponsiveAudioMaterialLayerID
    ) -> AUEventSampleTime? {
        commonLayers[layerID]?.lastRampStartSample
    }

    func commonPlayerIsPlayingForTesting(
        _ layerID: ResponsiveAudioMaterialLayerID
    ) -> Bool? {
        commonLayers[layerID]?.player.isPlaying
    }

    func conventionalPlayerIdentityForTesting(
        _ cueID: AudioCueID
    ) -> ObjectIdentifier? {
        preparedSlices.first(where: { $0.cueID == cueID }).map {
            ObjectIdentifier($0.player)
        }
    }

    func conventionalLoopBufferCountForTesting(
        _ cueID: AudioCueID
    ) -> Int? {
        preparedSlices.first(where: { $0.cueID == cueID })?.loopBuffers.count
    }

    func conventionalPlayerIsPlayingForTesting(
        _ cueID: AudioCueID
    ) -> Bool? {
        preparedSlices.first(where: { $0.cueID == cueID })?.player.isPlaying
    }

    func conventionalStartSampleForTesting(
        _ cueID: AudioCueID
    ) -> AUEventSampleTime? {
        (preparedSlices + retiredSlices)
            .first(where: { $0.cueID == cueID })?.startRenderSample
    }

    func conventionalMuteSampleForTesting(
        _ cueID: AudioCueID
    ) -> AUEventSampleTime? {
        (preparedSlices + retiredSlices)
            .first(where: { $0.cueID == cueID })?.muteRenderSample
    }

    var transitionBoundaryForTesting: AUEventSampleTime? {
        lastTransitionBoundaryForTesting
    }

    var engineIsRunningForTesting: Bool { engine.isRunning }

    var playingNodeCountForTesting: Int {
        preparedSlices.filter(\.player.isPlaying).count
            + retiredSlices.filter(\.player.isPlaying).count
            + commonLayers.values.filter { $0.player.isPlaying }.count
            + retiredCommonLayers.filter { $0.player.isPlaying }.count
            + (renderClockSource != nil && engine.isRunning ? 1 : 0)
    }

    var retiredSliceCountForTesting: Int { retiredSlices.count }

    var retiredCommonLayerCountForTesting: Int { retiredCommonLayers.count }

    var pendingPhysicalTransitionCountForTesting: Int {
        pendingPhysicalTransition == nil ? 0 : 1
    }

    var retainedLoopBufferCountForTesting: Int {
        (preparedSlices + retiredSlices).reduce(0) {
            $0 + $1.loopBuffers.count
        }
    }

    var attachedNodeCountForTesting: Int { engine.attachedNodes.count }

    var automaticBoundaryGenerationForTesting: UInt64 {
        automaticBoundaryGeneration
    }

    var stagedAutomaticNodeCountForTesting: Int {
        guard let stagedAutomaticBoundary else { return 0 }
        return stagedAutomaticBoundary.successorSlices.count * 2
            + stagedAutomaticBoundary.successorCommonLayers.count * 2
    }

    var everyPreparedGainNodeUsesDurabilityGateForTesting: Bool {
        let gainNodes = preparedSlices.map(\.gainNode)
            + retiredSlices.map(\.gainNode)
            + Array(commonLayers.values).map(\.gainNode)
            + retiredCommonLayers.map(\.gainNode)
            + (stagedAutomaticBoundary?.successorSlices.map(\.gainNode) ?? [])
            + (stagedAutomaticBoundary.map {
                Array($0.successorCommonLayers.values).map(\.gainNode)
            } ?? [])
        return !gainNodes.isEmpty && gainNodes.allSatisfy {
            $0.durabilityGate === audioDurabilityGate
        }
    }

    var automaticCursorBoundaryForTesting: Int64? {
        stagedAutomaticBoundary.map { Int64($0.graphSampleTime) }
    }

    func automaticBoundaryMonitorOwnsForTesting(
        generation: UInt64,
        durabilityEpoch: UInt64,
        boundaryGraphSample: Int64
    ) -> Bool {
        ownsAutomaticBoundaryMonitor(
            generation: generation,
            durabilityEpoch: durabilityEpoch,
            boundaryGraphSample: boundaryGraphSample
        )
    }

    func failClosedAutomaticBoundaryMonitorForTesting(
        generation: UInt64,
        durabilityEpoch: UInt64,
        boundaryGraphSample: Int64
    ) {
        failClosedAutomaticBoundaryMonitor(
            generation: generation,
            durabilityEpoch: durabilityEpoch,
            boundaryGraphSample: boundaryGraphSample
        )
    }

    func promoteAutomaticBoundaryForTesting(generation: UInt64) {
        promoteAutomaticBoundary(generation: generation)
    }

    var renderedSampleOffsetForTesting: Int64 { renderedSampleOffset() }

    var renderedGraphSampleEndForTesting: Int64 {
        engine.manualRenderingMode == .offline
            ? engine.manualRenderingSampleTime
            : renderClockStorage.latestGraphSampleEnd.load(ordering: .acquiring)
    }

    var renderClockBaseGraphSampleForTesting: Int64 {
        renderClockBaseGraphSampleTime
    }

    var activeRouteFormatForTesting: NativeAudioRouteFormat? {
        activeRouteFormat
    }

    var graphRouteFormatAtLastRebuildForTesting: NativeAudioRouteFormat? {
        graphRouteFormatAtLastRebuild
    }

    func setPauseQuiescenceHookForTesting(
        _ hook: (() -> Void)?
    ) {
        pauseQuiescenceHookForTesting = hook
    }

#if DEBUG
    /// Gives the next real pause a deterministic later render position while
    /// leaving the production pause result successful.
    public func forceNextPauseCursorAdvanceForTesting(
        minimumRenderedSampleAdvance: Int64
    ) {
        let requestedAdvance = max(1, minimumRenderedSampleAdvance)
        let currentOffset = renderedSampleOffset()
        let advancedOffset = currentOffset.addingReportingOverflow(
            requestedAdvance
        )
        renderedSampleOffsetOverrideForTesting = advancedOffset.overflow
            ? Int64.max
            : advancedOffset.partialValue
        clearsRenderedSampleOffsetAfterNextPauseForTesting = true
    }

    /// Arms one failure after the next real playing-to-paused transition.
    /// The deterministic advance gives integration tests a later valid
    /// transport cursor which must never be mistaken for a durable fallback.
    public func armPauseCompletionFaultForTesting(
        minimumRenderedSampleAdvance: Int64,
        _ fault: @escaping (NativeTimelineTransportSnapshot) throws -> Void
    ) {
        forceNextPauseCursorAdvanceForTesting(
            minimumRenderedSampleAdvance: minimumRenderedSampleAdvance
        )
        pauseCompletionFaultForTesting = fault
    }

    /// Arms one failure before outgoing-tail preparation mutates the running
    /// graph or replaces its durability authority.
    public func armRelinquishPreparationFaultForTesting(
        _ fault: @escaping () throws -> Void
    ) {
        relinquishPreparationFaultForTesting = fault
    }
#endif

    func publishRenderClockAnchorForTesting(
        graphSampleEnd: Int64,
        hostTimeAtGraphSampleEnd: UInt64?
    ) {
        renderClockStorage.record(
            graphSampleEnd,
            hostTimeAtGraphSampleEnd: hostTimeAtGraphSampleEnd
        )
    }

    func setRenderedSampleOffsetOverrideForTesting(_ samples: Int64?) {
        renderedSampleOffsetOverrideForTesting = samples
    }

    func conventionalFadeForTesting(
        _ cueID: AudioCueID
    ) -> (start: AUEventSampleTime, duration: Int64)? {
        guard let slice = (preparedSlices + retiredSlices).first(where: {
            $0.cueID == cueID
        }), let start = slice.fadeRenderSample,
           let duration = slice.fadeDurationSamples else { return nil }
        return (start, duration)
    }

    func setRenderTimeLookupUnavailableForTesting(_ unavailable: Bool) {
        // Retained as a regression seam: source-render timestamps are now the
        // sole realtime authority, so output-node lookup availability cannot
        // affect cursor capture or transition scheduling.
        _ = unavailable
    }

    func injectHapticStartFailureForTesting() {
        failNextHapticStartForTesting = true
    }

    func injectHapticPreparationFailureForTesting() {
        failNextHapticPreparationForTesting = true
    }

    func injectConventionalAttachFailureForTesting(_ cueID: AudioCueID) {
        failConventionalAttachCueForTesting = cueID
    }

    func injectGainUnitInstantiationFailureForTesting() {
        failNextGainUnitInstantiationForTesting = true
    }

    func enableManualRenderingForTesting(
        sampleRate: Double = 48_000,
        maximumFrameCount: AVAudioFrameCount = 4_096
    ) throws {
        guard state == .idle,
              engine.manualRenderingMode == .realtime,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: 2,
                  interleaved: false
              ) else {
            throw NativeTimelineTransportError.manualRenderingFailed(
                "manual mode must be enabled before prepare"
            )
        }
        do {
            try engine.enableManualRenderingMode(
                .offline,
                format: format,
                maximumFrameCount: maximumFrameCount
            )
        } catch {
            throw NativeTimelineTransportError.manualRenderingFailed(
                "could not enable offline rendering"
            )
        }
    }

    func renderOfflineSamplesForTesting(
        _ frameCount: AVAudioFrameCount
    ) throws -> [[Float]] {
        guard engine.manualRenderingMode == .offline,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: engine.manualRenderingFormat,
                  frameCapacity: min(
                      frameCount,
                      engine.manualRenderingMaximumFrameCount
                  )
              ) else {
            throw NativeTimelineTransportError.manualRenderingFailed(
                "offline renderer is unavailable"
            )
        }
        var channels = Array(
            repeating: [Float](),
            count: Int(engine.manualRenderingFormat.channelCount)
        )
        var remaining = frameCount
        var retries = 0
        while remaining > 0 {
            let requested = min(remaining, buffer.frameCapacity)
            let status: AVAudioEngineManualRenderingStatus
            do {
                status = try engine.renderOffline(requested, to: buffer)
            } catch {
                throw NativeTimelineTransportError.manualRenderingFailed(
                    "offline render threw"
                )
            }
            switch status {
            case .success:
                guard let data = buffer.floatChannelData else {
                    throw NativeTimelineTransportError.manualRenderingFailed(
                        "offline output is not float PCM"
                    )
                }
                for channel in channels.indices {
                    channels[channel].append(
                        contentsOf: UnsafeBufferPointer(
                            start: data[channel],
                            count: Int(buffer.frameLength)
                        )
                    )
                }
                remaining -= buffer.frameLength
                retries = 0
                renderClockStorage.record(
                    engine.manualRenderingSampleTime,
                    hostTimeAtGraphSampleEnd: nil
                )
                promoteAutomaticBoundaryIfNeeded()
            case .cannotDoInCurrentContext:
                retries += 1
                guard retries < 100 else {
                    throw NativeTimelineTransportError.manualRenderingFailed(
                        "offline renderer stayed busy"
                    )
                }
            case .insufficientDataFromInputNode, .error:
                throw NativeTimelineTransportError.manualRenderingFailed(
                    "offline renderer returned \(status.rawValue)"
                )
            @unknown default:
                throw NativeTimelineTransportError.manualRenderingFailed(
                    "offline renderer returned an unknown status"
                )
            }
        }
        activeOutgoingTail?.observeRenderClockNowForTesting()
        return channels
    }

    func mixerOutputVolumeForTesting(_ role: AudioTrackRole) -> Float? {
        roleMixers[role.rawValue]?.outputVolume
    }
}

private extension ResponsiveAudioTimelineTransportPlan {
    func replacingPosition(
        cursorSample: Int64,
        loopIteration: UInt64
    ) -> ResponsiveAudioTimelineTransportPlan {
        let updatedRepetition: ResponsiveAudioPlaybackRepetition = switch repetition {
        case .once:
            .once
        case let .loop(_, durationSamples):
            .loop(iteration: loopIteration, durationSamples: durationSamples)
        }
        return ResponsiveAudioTimelineTransportPlan(
            timeline: timeline,
            cursorSample: cursorSample,
            loopIteration: loopIteration,
            repetition: updatedRepetition,
            causalMix: causalMix
        )
    }
}
#endif
