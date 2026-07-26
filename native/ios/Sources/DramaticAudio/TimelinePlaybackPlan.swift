import ContentKit
import Foundation

public struct AudioAssetMetadata: Equatable, Sendable {
    public let path: String
    public let sampleRate: Int
    public let frameCount: Int64
    public let channelCount: Int

    public init(
        path: String,
        sampleRate: Int,
        frameCount: Int64,
        channelCount: Int
    ) {
        self.path = path
        self.sampleRate = sampleRate
        self.frameCount = frameCount
        self.channelCount = channelCount
    }
}

public struct ScheduledAudioSlice: Equatable, Sendable {
    public let cueID: AudioCueID
    public let role: AudioTrackRole
    public let assetPath: String
    public let assetStartFrame: Int64
    public let frameCount: Int64
    public let timelineStartOffset: Int64
    public let gain: Double

    public init(
        cueID: AudioCueID,
        role: AudioTrackRole,
        assetPath: String,
        assetStartFrame: Int64,
        frameCount: Int64,
        timelineStartOffset: Int64,
        gain: Double
    ) {
        self.cueID = cueID
        self.role = role
        self.assetPath = assetPath
        self.assetStartFrame = assetStartFrame
        self.frameCount = frameCount
        self.timelineStartOffset = timelineStartOffset
        self.gain = gain
    }
}

public struct ScheduledHaptic: Equatable, Sendable {
    public let timelineStartOffset: Int64
    public let semantic: HapticSemantic
    public let intensity: Double
    public let sharpness: Double

    public init(
        timelineStartOffset: Int64,
        semantic: HapticSemantic,
        intensity: Double,
        sharpness: Double
    ) {
        self.timelineStartOffset = timelineStartOffset
        self.semantic = semantic
        self.intensity = intensity
        self.sharpness = sharpness
    }
}

public struct TimelinePlaybackPlan: Equatable, Sendable {
    public let timelineID: AudioTimelineID
    public let sampleRate: Int
    public let cursorSample: Int64
    public let endSample: Int64
    public let audioSlices: [ScheduledAudioSlice]
    public let haptics: [ScheduledHaptic]

    public var remainingSamples: Int64 { max(0, endSample - cursorSample) }

    public init(
        timelineID: AudioTimelineID,
        sampleRate: Int,
        cursorSample: Int64,
        endSample: Int64,
        audioSlices: [ScheduledAudioSlice],
        haptics: [ScheduledHaptic]
    ) {
        self.timelineID = timelineID
        self.sampleRate = sampleRate
        self.cursorSample = cursorSample
        self.endSample = endSample
        self.audioSlices = audioSlices
        self.haptics = haptics
    }
}

public enum TimelinePlaybackPlanningError: Error, Equatable, Sendable {
    case invalidTimeline(String)
    case invalidCursor(Int64)
    case timelineRangeOverflow(AudioCueID)
    case missingAsset(String)
    case unexpectedAssetForSilence(AudioCueID)
    case unsupportedSampleRate(path: String, expected: Int, actual: Int)
    case insufficientFrames(path: String, required: Int64, actual: Int64)
    case invalidChannelCount(path: String, role: AudioTrackRole, actual: Int)
    case invalidGain(AudioCueID)
    case sliceTooLong(AudioCueID)
}

public enum TimelinePlaybackPlanner {
    public static func makePlan(
        timeline: AudioTimeline,
        cursorSample: Int64,
        assetMetadata: [String: AudioAssetMetadata]
    ) throws -> TimelinePlaybackPlan {
        do {
            try timeline.validate()
        } catch {
            throw TimelinePlaybackPlanningError.invalidTimeline(String(describing: error))
        }
        guard cursorSample >= 0 else {
            throw TimelinePlaybackPlanningError.invalidCursor(cursorSample)
        }

        var endSample: Int64 = 0
        var slices: [ScheduledAudioSlice] = []
        for event in timeline.events {
            let (eventEnd, overflow) = event.startSample.addingReportingOverflow(event.durationSamples)
            guard !overflow else {
                throw TimelinePlaybackPlanningError.timelineRangeOverflow(event.cueID)
            }
            endSample = max(endSample, eventEnd)

            if event.role == .silence {
                guard event.assetPath == nil else {
                    throw TimelinePlaybackPlanningError.unexpectedAssetForSilence(event.cueID)
                }
                continue
            }
            guard let assetPath = event.assetPath,
                  let metadata = assetMetadata[assetPath] else {
                throw TimelinePlaybackPlanningError.missingAsset(event.assetPath ?? "")
            }
            guard metadata.path == assetPath else {
                throw TimelinePlaybackPlanningError.missingAsset(assetPath)
            }
            guard metadata.sampleRate == timeline.sampleRate else {
                throw TimelinePlaybackPlanningError.unsupportedSampleRate(
                    path: assetPath,
                    expected: timeline.sampleRate,
                    actual: metadata.sampleRate
                )
            }
            guard metadata.frameCount >= event.durationSamples else {
                throw TimelinePlaybackPlanningError.insufficientFrames(
                    path: assetPath,
                    required: event.durationSamples,
                    actual: metadata.frameCount
                )
            }
            try validateChannels(metadata, role: event.role)
            guard event.gain >= 0, event.gain <= 4 else {
                throw TimelinePlaybackPlanningError.invalidGain(event.cueID)
            }
            guard eventEnd > cursorSample else { continue }

            let elapsedWithinEvent = max(0, cursorSample - event.startSample)
            let remainingFrames = event.durationSamples - elapsedWithinEvent
            guard remainingFrames <= Int64(UInt32.max) else {
                throw TimelinePlaybackPlanningError.sliceTooLong(event.cueID)
            }
            slices.append(ScheduledAudioSlice(
                cueID: event.cueID,
                role: event.role,
                assetPath: assetPath,
                assetStartFrame: elapsedWithinEvent,
                frameCount: remainingFrames,
                timelineStartOffset: max(0, event.startSample - cursorSample),
                gain: event.gain
            ))
        }

        var scheduledHaptics: [ScheduledHaptic] = []
        for haptic in timeline.haptics {
            endSample = max(endSample, haptic.sample)
            guard haptic.sample >= cursorSample else { continue }
            scheduledHaptics.append(ScheduledHaptic(
                timelineStartOffset: haptic.sample - cursorSample,
                semantic: haptic.kind,
                intensity: haptic.intensity,
                sharpness: haptic.sharpness
            ))
        }

        slices.sort {
            if $0.timelineStartOffset != $1.timelineStartOffset {
                return $0.timelineStartOffset < $1.timelineStartOffset
            }
            return $0.cueID < $1.cueID
        }
        scheduledHaptics.sort {
            if $0.timelineStartOffset != $1.timelineStartOffset {
                return $0.timelineStartOffset < $1.timelineStartOffset
            }
            return $0.semantic.rawValue < $1.semantic.rawValue
        }
        return TimelinePlaybackPlan(
            timelineID: timeline.id,
            sampleRate: timeline.sampleRate,
            cursorSample: min(cursorSample, endSample),
            endSample: endSample,
            audioSlices: slices,
            haptics: scheduledHaptics
        )
    }

    private static func validateChannels(
        _ metadata: AudioAssetMetadata,
        role: AudioTrackRole
    ) throws {
        let valid: Bool = switch role {
        case .narration:
            metadata.channelCount == 1
        case .score, .soundscape:
            metadata.channelCount == 2
        case .spatialDetail:
            (1 ... 2).contains(metadata.channelCount)
        case .silence:
            false
        }
        guard valid else {
            throw TimelinePlaybackPlanningError.invalidChannelCount(
                path: metadata.path,
                role: role,
                actual: metadata.channelCount
            )
        }
    }
}
