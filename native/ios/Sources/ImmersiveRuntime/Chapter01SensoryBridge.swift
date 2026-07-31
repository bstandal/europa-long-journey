import Foundation

#if canImport(AVFAudio)
import AVFAudio
#endif

#if os(iOS)
import CoreHaptics
#endif

/// Physical meanings used by Chapter 01. These are deliberately narrower
/// than the chapter's visual event vocabulary: a camera transition, for
/// example, must never manufacture a haptic pulse.
public enum Chapter01PhysicalHaptic: String, CaseIterable, Codable, Sendable {
    case contact
    case resistance
    case materialBreak
    case seal
    case transfer
}

public enum Chapter01HapticPulseKind: String, Codable, Sendable {
    case transient
    case continuous
}

public struct Chapter01HapticPulse: Codable, Equatable, Sendable {
    public let kind: Chapter01HapticPulseKind
    public let relativeTime: TimeInterval
    public let duration: TimeInterval
    public let intensity: Float
    public let sharpness: Float

    public init(
        kind: Chapter01HapticPulseKind,
        relativeTime: TimeInterval,
        duration: TimeInterval = 0,
        intensity: Float,
        sharpness: Float
    ) {
        self.kind = kind
        self.relativeTime = relativeTime
        self.duration = duration
        self.intensity = intensity
        self.sharpness = sharpness
    }
}

/// A small authored vocabulary. It gives contact, resistance, breakage and
/// sealing distinct physical signatures without turning haptics into a second
/// progress system.
public enum Chapter01HapticProfile {
    public static func pulses(for semantic: Chapter01PhysicalHaptic) -> [Chapter01HapticPulse] {
        switch semantic {
        case .contact:
            [
                .init(
                    kind: .transient,
                    relativeTime: 0,
                    intensity: 0.32,
                    sharpness: 0.56
                ),
            ]
        case .resistance:
            [
                .init(
                    kind: .continuous,
                    relativeTime: 0,
                    duration: 0.085,
                    intensity: 0.56,
                    sharpness: 0.14
                ),
            ]
        case .materialBreak:
            [
                .init(
                    kind: .transient,
                    relativeTime: 0,
                    intensity: 0.70,
                    sharpness: 0.20
                ),
                .init(
                    kind: .transient,
                    relativeTime: 0.048,
                    intensity: 0.84,
                    sharpness: 0.80
                ),
            ]
        case .seal:
            [
                .init(
                    kind: .transient,
                    relativeTime: 0,
                    intensity: 0.66,
                    sharpness: 0.28
                ),
                .init(
                    kind: .transient,
                    relativeTime: 0.072,
                    intensity: 0.36,
                    sharpness: 0.16
                ),
            ]
        case .transfer:
            [
                .init(
                    kind: .transient,
                    relativeTime: 0,
                    intensity: 0.27,
                    sharpness: 0.40
                ),
                .init(
                    kind: .transient,
                    relativeTime: 0.040,
                    intensity: 0.39,
                    sharpness: 0.48
                ),
            ]
        }
    }
}

public struct Chapter01AuthoredSampleKey: Hashable, Sendable {
    public let sequence: Chapter01Sequence
    public let event: Chapter01SensoryEvent

    public init(sequence: Chapter01Sequence, event: Chapter01SensoryEvent) {
        self.sequence = sequence
        self.event = event
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sequence.rawValue == rhs.sequence.rawValue
            && lhs.event.rawValue == rhs.event.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sequence.rawValue)
        hasher.combine(event.rawValue)
    }
}

/// A binding to a short authored cue inside an already verified offline
/// package. Narration is intentionally outside this bridge and remains under
/// the sample-accurate narration authority.
public struct Chapter01AuthoredSampleBinding: Equatable, Sendable {
    public let key: Chapter01AuthoredSampleKey
    public let packageRelativePath: String
    public let gain: Float
    public let maximumDuration: TimeInterval

    public init(
        sequence: Chapter01Sequence,
        event: Chapter01SensoryEvent,
        packageRelativePath: String,
        gain: Float = 1,
        maximumDuration: TimeInterval = 4
    ) {
        key = Chapter01AuthoredSampleKey(sequence: sequence, event: event)
        self.packageRelativePath = packageRelativePath
        self.gain = gain
        self.maximumDuration = maximumDuration
    }
}

public enum Chapter01SampleCatalogError: Error, Equatable, Sendable {
    case duplicateBinding(Chapter01AuthoredSampleKey)
    case unsafePath(String)
    case invalidGain(String)
    case invalidMaximumDuration(String)
}

public struct Chapter01AuthoredSampleCatalog: Sendable {
    private let bindings: [Chapter01AuthoredSampleKey: Chapter01AuthoredSampleBinding]

    public init(bindings: [Chapter01AuthoredSampleBinding]) throws {
        var indexed: [Chapter01AuthoredSampleKey: Chapter01AuthoredSampleBinding] = [:]
        for binding in bindings {
            guard Self.pathIsSafe(binding.packageRelativePath) else {
                throw Chapter01SampleCatalogError.unsafePath(binding.packageRelativePath)
            }
            guard binding.gain.isFinite, (0 ... 1).contains(binding.gain) else {
                throw Chapter01SampleCatalogError.invalidGain(binding.packageRelativePath)
            }
            guard binding.maximumDuration.isFinite,
                  binding.maximumDuration > 0,
                  binding.maximumDuration <= 4 else {
                throw Chapter01SampleCatalogError.invalidMaximumDuration(
                    binding.packageRelativePath
                )
            }
            guard indexed.updateValue(binding, forKey: binding.key) == nil else {
                throw Chapter01SampleCatalogError.duplicateBinding(binding.key)
            }
        }
        self.bindings = indexed
    }

    public func binding(
        for sequence: Chapter01Sequence,
        event: Chapter01SensoryEvent
    ) -> Chapter01AuthoredSampleBinding? {
        bindings[Chapter01AuthoredSampleKey(sequence: sequence, event: event)]
    }

    private static func pathIsSafe(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty
            && !path.hasPrefix("/")
            && !path.contains("\\")
            && !path.contains("://")
            && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

public enum Chapter01OfflineSampleResolutionError: Error, Equatable, Sendable {
    case invalidPackageRoot
    case undeclaredPath(String)
    case pathEscapedPackage(String)
    case missingOrInvalidFile(String)
}

/// Resolves only explicitly declared regular files inside an offline package.
/// The package verifier remains responsible for signatures and digests; this
/// resolver repeats the path-containment check immediately before playback.
public struct Chapter01OfflineSampleResolver: Sendable {
    public let packageRootURL: URL
    private let declaredPaths: Set<String>
    private let authoritativeResolver: (@Sendable (String) throws -> URL)?

    public init(packageRootURL: URL, declaredPaths: Set<String>) throws {
        try self.init(
            packageRootURL: packageRootURL,
            declaredPaths: declaredPaths,
            authoritativeResolver: nil
        )
    }

    /// Wraps the app's manifest-bound resolver without coupling this renderer
    /// module to the audio package. Its digest/identity check runs first; this
    /// type then repeats package containment and regular-file checks.
    public init(
        packageRootURL: URL,
        declaredPaths: Set<String>,
        authoritativeResolver: @escaping @Sendable (String) throws -> URL
    ) throws {
        try self.init(
            packageRootURL: packageRootURL,
            declaredPaths: declaredPaths,
            authoritativeResolver: Optional(authoritativeResolver)
        )
    }

    private init(
        packageRootURL: URL,
        declaredPaths: Set<String>,
        authoritativeResolver: (@Sendable (String) throws -> URL)?
    ) throws {
        guard packageRootURL.isFileURL else {
            throw Chapter01OfflineSampleResolutionError.invalidPackageRoot
        }
        let canonicalRoot = packageRootURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: canonicalRoot.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw Chapter01OfflineSampleResolutionError.invalidPackageRoot
        }
        self.packageRootURL = canonicalRoot
        self.declaredPaths = declaredPaths
        self.authoritativeResolver = authoritativeResolver
    }

    public func url(for packageRelativePath: String) throws -> URL {
        guard declaredPaths.contains(packageRelativePath) else {
            throw Chapter01OfflineSampleResolutionError.undeclaredPath(packageRelativePath)
        }
        let resolved = try authoritativeResolver?(packageRelativePath)
            ?? packageRootURL.appending(
                path: packageRelativePath,
                directoryHint: .notDirectory
            )
        let candidate = resolved
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard candidate.path.hasPrefix(packageRootURL.path + "/") else {
            throw Chapter01OfflineSampleResolutionError.pathEscapedPackage(
                packageRelativePath
            )
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: candidate.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            throw Chapter01OfflineSampleResolutionError.missingOrInvalidFile(
                packageRelativePath
            )
        }
        return candidate
    }
}

public enum Chapter01AuthoredAudioChannel: String, CaseIterable, Sendable {
    case environment
    case mechanism
    case transition
    case narration
}

@MainActor
public protocol Chapter01AuthoredSamplePlaying: AnyObject {
    func play(
        url: URL,
        gain: Float,
        maximumDuration: TimeInterval
    ) throws
    func playProgram(
        url: URL,
        gain: Float,
        maximumDuration: TimeInterval,
        channel: Chapter01AuthoredAudioChannel
    ) throws
    func playLoop(
        url: URL,
        gain: Float,
        channel: Chapter01AuthoredAudioChannel
    ) throws
    func playNarration(
        url: URL,
        gain: Float,
        startSampleFrame: Int64,
        sampleRate: Int,
        channel: Chapter01AuthoredAudioChannel
    ) throws
    func stop(channel: Chapter01AuthoredAudioChannel)
    func stopAll()
}

public extension Chapter01AuthoredSamplePlaying {
    func playProgram(
        url: URL,
        gain: Float,
        maximumDuration: TimeInterval,
        channel _: Chapter01AuthoredAudioChannel
    ) throws {
        try play(url: url, gain: gain, maximumDuration: maximumDuration)
    }

    func playLoop(
        url: URL,
        gain: Float,
        channel _: Chapter01AuthoredAudioChannel
    ) throws {
        try play(url: url, gain: gain, maximumDuration: 4)
    }

    func playNarration(
        url: URL,
        gain: Float,
        startSampleFrame _: Int64,
        sampleRate _: Int,
        channel _: Chapter01AuthoredAudioChannel
    ) throws {
        try play(url: url, gain: gain, maximumDuration: 15)
    }

    func stop(channel _: Chapter01AuthoredAudioChannel) {
        stopAll()
    }
}

#if canImport(AVFAudio)
public enum Chapter01NativeSamplePlayerError: Error, Equatable, Sendable {
    case playbackRejected(URL)
}

@MainActor
public final class Chapter01NativeSamplePlayer: Chapter01AuthoredSamplePlaying {
    private struct ActivePlayback {
        let identifier: UUID
        let player: AVAudioPlayer
        let stopTask: Task<Void, Never>?
    }

    private var oneShots: [UUID: ActivePlayback] = [:]
    private var channels: [Chapter01AuthoredAudioChannel: ActivePlayback] = [:]

    public init() {}

    public func play(
        url: URL,
        gain: Float,
        maximumDuration: TimeInterval
    ) throws {
        let identifier = UUID()
        let player = try preparedPlayer(url: url, gain: gain, loops: 0)
        guard player.play() else {
            throw Chapter01NativeSamplePlayerError.playbackRejected(url)
        }

        let boundedDuration = min(player.duration, maximumDuration)
        let stopTask = Task { @MainActor [weak self, weak player] in
            try? await Task.sleep(for: .seconds(boundedDuration))
            guard !Task.isCancelled else { return }
            player?.stop()
            self?.oneShots[identifier] = nil
        }
        oneShots[identifier] = ActivePlayback(
            identifier: identifier,
            player: player,
            stopTask: stopTask
        )
    }

    public func playProgram(
        url: URL,
        gain: Float,
        maximumDuration: TimeInterval,
        channel: Chapter01AuthoredAudioChannel
    ) throws {
        stop(channel: channel)
        let identifier = UUID()
        let player = try preparedPlayer(url: url, gain: gain, loops: 0)
        guard player.play() else {
            throw Chapter01NativeSamplePlayerError.playbackRejected(url)
        }
        let boundedDuration = min(player.duration, maximumDuration)
        let stopTask = Task { @MainActor [weak self, weak player] in
            try? await Task.sleep(for: .seconds(boundedDuration))
            guard !Task.isCancelled,
                  self?.channels[channel]?.identifier == identifier else { return }
            player?.stop()
            self?.channels[channel] = nil
        }
        channels[channel] = ActivePlayback(
            identifier: identifier,
            player: player,
            stopTask: stopTask
        )
    }

    public func playLoop(
        url: URL,
        gain: Float,
        channel: Chapter01AuthoredAudioChannel
    ) throws {
        if let existing = channels[channel],
           existing.player.url?.standardizedFileURL == url.standardizedFileURL,
           existing.player.isPlaying {
            existing.player.volume = gain
            return
        }
        stop(channel: channel)
        let identifier = UUID()
        let player = try preparedPlayer(url: url, gain: gain, loops: -1)
        guard player.play() else {
            throw Chapter01NativeSamplePlayerError.playbackRejected(url)
        }
        channels[channel] = ActivePlayback(
            identifier: identifier,
            player: player,
            stopTask: nil
        )
    }

    public func playNarration(
        url: URL,
        gain: Float,
        startSampleFrame: Int64,
        sampleRate: Int,
        channel: Chapter01AuthoredAudioChannel
    ) throws {
        stop(channel: channel)
        let identifier = UUID()
        let player = try preparedPlayer(url: url, gain: gain, loops: 0)

        // AVAudioPlayer seeks in seconds. The persisted 48 kHz frame cursor is
        // deterministic package authority; physical decoder/output alignment
        // remains an explicit iPhone quality gate rather than a false claim of
        // sample-perfect hardware scheduling.
        player.currentTime = Double(max(startSampleFrame, 0))
            / Double(max(sampleRate, 1))
        guard player.play() else {
            throw Chapter01NativeSamplePlayerError.playbackRejected(url)
        }
        channels[channel] = ActivePlayback(
            identifier: identifier,
            player: player,
            stopTask: nil
        )
    }

    public func stop(channel: Chapter01AuthoredAudioChannel) {
        guard let playback = channels.removeValue(forKey: channel) else { return }
        playback.stopTask?.cancel()
        playback.player.stop()
    }

    public func stopAll() {
        for playback in oneShots.values {
            playback.stopTask?.cancel()
            playback.player.stop()
        }
        oneShots.removeAll(keepingCapacity: true)
        for playback in channels.values {
            playback.stopTask?.cancel()
            playback.player.stop()
        }
        channels.removeAll(keepingCapacity: true)
    }

    private func preparedPlayer(
        url: URL,
        gain: Float,
        loops: Int
    ) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(contentsOf: url)
        player.volume = gain
        player.numberOfLoops = loops
        player.prepareToPlay()
        return player
    }

}
#endif

struct Chapter01PackageNarrationProgram: Equatable, Sendable {
    let cueID: String
    let beatID: String
    let packageRelativePath: String
    let durationSampleFrames: Int64
}

enum Chapter01PackageAudioProgram {
    static let sampleRate = 48_000
    static let narrationCheckpointFrames: Int64 = 12_000

    static let narrationPrograms: [Chapter01PackageNarrationProgram] =
        Chapter01ImmersivePayloadFactory.runtimeNarrationBindings.map {
            Chapter01PackageNarrationProgram(
                cueID: $0.cueID,
                beatID: $0.beatID,
                packageRelativePath: $0.packageRelativePath,
                durationSampleFrames: $0.durationSampleFrames
            )
        }

    static func narration(
        forBeatID beatID: String
    ) -> Chapter01PackageNarrationProgram? {
        narrationPrograms.first { $0.beatID == beatID }
    }

    static func environmentPath(for cell: Chapter01WorldCell) -> String {
        let number: Int
        switch cell {
        case .aegeanPassage: number = 1
        case .thessalianHousehold: number = 2
        case .ironGates: number = 3
        case .longhouseGround: number = 4
        case .settlementLandscape: number = 5
        }
        return "immersive/first-farmers/audio/environment-\(twoDigits(number)).m4a"
    }

    static func mechanismPath(for sequence: Chapter01Sequence) -> String {
        "immersive/first-farmers/audio/mechanism-\(twoDigits(sequence.rawValue + 1)).m4a"
    }

    static func transitionPath(for sequence: Chapter01Sequence) -> String {
        "immersive/first-farmers/audio/transition-\(twoDigits(sequence.rawValue + 1)).m4a"
    }

    private static func twoDigits(_ number: Int) -> String {
        String(format: "%02d", number)
    }
}

@MainActor
public final class Chapter01SensoryBridge {
    public var authoredSamplesAreEnabled = true {
        didSet {
            if authoredSamplesAreEnabled {
                restoreDesiredAuthoredAudio()
            } else {
                suspendAuthoredAudio()
            }
        }
    }
    public var physicalHapticsAreEnabled = true {
        didSet {
            if !physicalHapticsAreEnabled { stopHapticEngine() }
        }
    }

    private let catalog: Chapter01AuthoredSampleCatalog?
    private let resolver: Chapter01OfflineSampleResolver?
    private let samplePlayer: (any Chapter01AuthoredSamplePlaying)?
    private let narrationClockIsAutomatic: Bool
    private var lastConsumedGeneration: UInt64?
    private var lastHapticEmission: [Chapter01PhysicalHaptic: UInt64] = [:]
    private var lifecycleIsSuspended = false
    private var activeEnvironmentCell: Chapter01WorldCell?
    private var activeNarrationBeatID: String?
    private var narrationCursor: Int64 = 0
    private var narrationDuration: Int64 = 0
    private var narrationClockTask: Task<Void, Never>?

    private struct DesiredAudioState {
        let cell: Chapter01WorldCell
        let beatID: String
        var narrationSampleCursor: Int64
        let preciseInputIsActive: Bool
        let onNarrationCheckpoint: @MainActor (String, Int64) -> Void
    }

    private var desiredAudio: DesiredAudioState?

#if os(iOS)
    private var hapticEngine: CHHapticEngine?
#endif

    public init(
        catalog: Chapter01AuthoredSampleCatalog? = nil,
        resolver: Chapter01OfflineSampleResolver? = nil,
        samplePlayer: (any Chapter01AuthoredSamplePlaying)? = nil,
        narrationClockIsAutomatic: Bool = true
    ) {
        self.catalog = catalog
        self.resolver = resolver
        self.narrationClockIsAutomatic = narrationClockIsAutomatic
#if canImport(AVFAudio)
        self.samplePlayer = samplePlayer ?? Chapter01NativeSamplePlayer()
#else
        self.samplePlayer = samplePlayer
#endif
    }

    /// Projects package-backed audio from durable chapter authority. The
    /// environment follows the current cell, while provisional narration is
    /// keyed only by the ten locked V2 beat IDs. No transcript enters the UI
    /// through this runtime surface.
    public func synchronizeExperience(
        cell: Chapter01WorldCell,
        beatID: String,
        narrationSampleCursor: Int64,
        preciseInputIsActive: Bool,
        onNarrationCheckpoint: @escaping @MainActor (String, Int64) -> Void
    ) {
        let previousBeatID = desiredAudio?.beatID
        let beatChanged = previousBeatID != beatID
        let admittedCursor: Int64
        if !beatChanged, activeNarrationBeatID == beatID {
            admittedCursor = max(narrationCursor, narrationSampleCursor)
        } else {
            admittedCursor = max(narrationSampleCursor, 0)
        }
        desiredAudio = DesiredAudioState(
            cell: cell,
            beatID: beatID,
            narrationSampleCursor: admittedCursor,
            preciseInputIsActive: preciseInputIsActive,
            onNarrationCheckpoint: onNarrationCheckpoint
        )

        if beatChanged {
            stopNarration(checkpoint: true)
        }
        restoreDesiredAuthoredAudio()
    }

    /// Consumes one controller generation exactly once. It reads the event
    /// after the domain reducer has accepted the action, so sensory feedback
    /// can never create or complete historical state.
    public func consume(
        event: Chapter01SensoryEvent?,
        generation: UInt64,
        sequence: Chapter01Sequence
    ) {
        guard lastConsumedGeneration != generation else { return }
        lastConsumedGeneration = generation
        guard let event, !lifecycleIsSuspended else { return }

        if let semantic = Self.hapticSemantic(for: event) {
            playPhysical(semantic)
        }
        playAuthoredSample(event: event, sequence: sequence)
    }

    /// Used by the world projection only when a rendered material truly
    /// breaks. It has no path back into the reducer.
    public func playPhysical(_ semantic: Chapter01PhysicalHaptic) {
        guard physicalHapticsAreEnabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if let previous = lastHapticEmission[semantic],
           now >= previous,
           now - previous < Self.minimumHapticInterval(for: semantic) {
            return
        }
        lastHapticEmission[semantic] = now

#if os(iOS)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine: CHHapticEngine
            if let hapticEngine {
                engine = hapticEngine
            } else {
                let created = try CHHapticEngine()
                created.playsHapticsOnly = true
                created.stoppedHandler = { [weak self] _ in
                    Task { @MainActor [weak self] in self?.hapticEngine = nil }
                }
                created.resetHandler = { [weak self] in
                    Task { @MainActor [weak self] in self?.hapticEngine = nil }
                }
                hapticEngine = created
                engine = created
            }
            try engine.start()
            let events = Chapter01HapticProfile.pulses(for: semantic).map { pulse in
                CHHapticEvent(
                    eventType: pulse.kind == .transient
                        ? .hapticTransient
                        : .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: pulse.intensity
                        ),
                        CHHapticEventParameter(
                            parameterID: .hapticSharpness,
                            value: pulse.sharpness
                        ),
                    ],
                    relativeTime: pulse.relativeTime,
                    duration: pulse.duration
                )
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            stopHapticEngine()
        }
#endif
    }

    public func quiesceForSuspension() {
        lifecycleIsSuspended = true
        stopNarration(checkpoint: true)
        samplePlayer?.stopAll()
        activeEnvironmentCell = nil
        stopHapticEngine()
        lastHapticEmission.removeAll(keepingCapacity: true)
    }

    public func resumeAfterSuspension() {
        lifecycleIsSuspended = false
        lastHapticEmission.removeAll(keepingCapacity: true)
        restoreDesiredAuthoredAudio()
    }

    public func stop() {
        stopNarration(checkpoint: true)
        samplePlayer?.stopAll()
        activeEnvironmentCell = nil
        desiredAudio = nil
        lifecycleIsSuspended = true
        stopHapticEngine()
        lastHapticEmission.removeAll(keepingCapacity: true)
    }

    /// Deterministic 48 kHz advancement. Tests call this directly; production
    /// invokes it every 250 ms and persists the resulting integer frame.
    func advanceNarrationClock(sampleFrames: Int64) {
        guard sampleFrames > 0,
              let beatID = activeNarrationBeatID,
              narrationDuration > 0,
              var desiredAudio,
              desiredAudio.beatID == beatID else { return }
        narrationCursor = min(
            narrationCursor + sampleFrames,
            narrationDuration
        )
        desiredAudio.narrationSampleCursor = narrationCursor
        self.desiredAudio = desiredAudio
        desiredAudio.onNarrationCheckpoint(beatID, narrationCursor)
        if narrationCursor >= narrationDuration {
            stopNarration(checkpoint: false)
        }
    }

    private func playAuthoredSample(
        event: Chapter01SensoryEvent,
        sequence: Chapter01Sequence
    ) {
        let authoritativePath = event == .transition
            ? Chapter01PackageAudioProgram.transitionPath(for: sequence)
            : Chapter01PackageAudioProgram.mechanismPath(for: sequence)
        guard authoredSamplesAreEnabled,
              let binding = catalog?.binding(for: sequence, event: event),
              binding.packageRelativePath == authoritativePath,
              let resolver,
              let samplePlayer,
              let url = try? resolver.url(for: binding.packageRelativePath) else {
            return
        }
        try? samplePlayer.playProgram(
            url: url,
            gain: binding.gain,
            maximumDuration: binding.maximumDuration,
            channel: event == .transition ? .transition : .mechanism
        )
    }

    private func restoreDesiredAuthoredAudio() {
        guard authoredSamplesAreEnabled,
              !lifecycleIsSuspended,
              let desiredAudio,
              let resolver,
              let samplePlayer else { return }

        if activeEnvironmentCell != desiredAudio.cell {
            samplePlayer.stop(channel: .environment)
            activeEnvironmentCell = nil
            let path = Chapter01PackageAudioProgram.environmentPath(
                for: desiredAudio.cell
            )
            if let url = try? resolver.url(for: path) {
                do {
                    try samplePlayer.playLoop(
                        url: url,
                        gain: 0.46,
                        channel: .environment
                    )
                    activeEnvironmentCell = desiredAudio.cell
                } catch {
                    activeEnvironmentCell = nil
                }
            }
        }

        guard activeNarrationBeatID == nil,
              !desiredAudio.preciseInputIsActive,
              let narration = Chapter01PackageAudioProgram.narration(
                  forBeatID: desiredAudio.beatID
              ) else { return }
        let cursor = min(
            max(desiredAudio.narrationSampleCursor, 0),
            narration.durationSampleFrames
        )
        guard cursor < narration.durationSampleFrames,
              let url = try? resolver.url(for: narration.packageRelativePath) else {
            return
        }
        do {
            try samplePlayer.playNarration(
                url: url,
                gain: 0.96,
                startSampleFrame: cursor,
                sampleRate: Chapter01PackageAudioProgram.sampleRate,
                channel: .narration
            )
        } catch {
            return
        }
        activeNarrationBeatID = narration.beatID
        narrationCursor = cursor
        narrationDuration = narration.durationSampleFrames
        scheduleNarrationClockIfNeeded()
    }

    private func scheduleNarrationClockIfNeeded() {
        guard narrationClockIsAutomatic,
              narrationClockTask == nil,
              activeNarrationBeatID != nil else { return }
        narrationClockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.advanceNarrationClock(
                    sampleFrames: Chapter01PackageAudioProgram
                        .narrationCheckpointFrames
                )
            }
        }
    }

    private func stopNarration(checkpoint: Bool) {
        narrationClockTask?.cancel()
        narrationClockTask = nil
        if checkpoint,
           let beatID = activeNarrationBeatID,
           let desiredAudio,
           desiredAudio.beatID == beatID {
            desiredAudio.onNarrationCheckpoint(beatID, narrationCursor)
        }
        samplePlayer?.stop(channel: .narration)
        activeNarrationBeatID = nil
        narrationDuration = 0
    }

    private func suspendAuthoredAudio() {
        stopNarration(checkpoint: true)
        samplePlayer?.stopAll()
        activeEnvironmentCell = nil
    }

    private func stopHapticEngine() {
#if os(iOS)
        hapticEngine?.stop()
        hapticEngine = nil
#endif
    }

    private static func hapticSemantic(
        for event: Chapter01SensoryEvent
    ) -> Chapter01PhysicalHaptic? {
        switch event {
        case .contact, .threshold:
            .contact
        case .resistance:
            .resistance
        case .transfer:
            .transfer
        case .seal:
            .seal
        case .transition:
            nil
        }
    }

    private static func minimumHapticInterval(
        for semantic: Chapter01PhysicalHaptic
    ) -> UInt64 {
        switch semantic {
        case .contact, .transfer:
            75_000_000
        case .resistance:
            120_000_000
        case .materialBreak, .seal:
            180_000_000
        }
    }
}
