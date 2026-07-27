import ContentKit
@testable import DramaticAudio
import ExperiencePreferences
import Foundation
import XCTest
#if os(iOS)
import AVFAudio
#endif

final class ExperienceAudioRoutingPolicyTests: XCTestCase {
    func testStandardPreferencesRouteEveryAuthoredRoleAndBothHapticPaths() {
        let policy = ExperienceAudioRoutingPolicy(preferences: .standard)

        XCTAssertEqual(policy.routing(for: .narration), .audible)
        XCTAssertEqual(policy.routing(for: .score), .audible)
        XCTAssertEqual(policy.routing(for: .soundscape), .audible)
        XCTAssertEqual(policy.routing(for: .spatialDetail), .audible)
        XCTAssertEqual(policy.routing(for: .silence), .timingOnly)
        XCTAssertTrue(policy.timelineHapticsAreEnabled)
        XCTAssertTrue(policy.semanticHapticsAreEnabled)
    }

    func testEachPreferenceControlsOnlyItsAuthoredOutputBoundary() {
        let narrationOff = ExperienceAudioRoutingPolicy(preferences: ExperiencePreferences(
            narrationEnabled: false
        ))
        XCTAssertEqual(narrationOff.routing(for: .narration), .muted)
        XCTAssertEqual(narrationOff.routing(for: .score), .audible)
        XCTAssertEqual(narrationOff.routing(for: .soundscape), .audible)
        XCTAssertEqual(narrationOff.routing(for: .spatialDetail), .audible)

        let scoreOff = ExperienceAudioRoutingPolicy(preferences: ExperiencePreferences(
            scoreEnabled: false
        ))
        XCTAssertEqual(scoreOff.routing(for: .narration), .audible)
        XCTAssertEqual(scoreOff.routing(for: .score), .muted)
        XCTAssertEqual(scoreOff.routing(for: .soundscape), .audible)
        XCTAssertEqual(scoreOff.routing(for: .spatialDetail), .audible)

        let soundscapeOff = ExperienceAudioRoutingPolicy(preferences: ExperiencePreferences(
            soundscapeEnabled: false
        ))
        XCTAssertEqual(soundscapeOff.routing(for: .narration), .audible)
        XCTAssertEqual(soundscapeOff.routing(for: .score), .audible)
        XCTAssertEqual(soundscapeOff.routing(for: .soundscape), .muted)
        XCTAssertEqual(soundscapeOff.routing(for: .spatialDetail), .muted)

        let hapticsOff = ExperienceAudioRoutingPolicy(preferences: ExperiencePreferences(
            hapticsEnabled: false
        ))
        XCTAssertFalse(hapticsOff.timelineHapticsAreEnabled)
        XCTAssertFalse(hapticsOff.semanticHapticsAreEnabled)
        XCTAssertEqual(hapticsOff.routing(for: .narration), .audible)
        XCTAssertEqual(hapticsOff.routing(for: .score), .audible)
        XCTAssertEqual(hapticsOff.routing(for: .soundscape), .audible)
        XCTAssertEqual(hapticsOff.routing(for: .spatialDetail), .audible)
    }

    func testMutedRolesUseZeroMixerVolumeWhileSilenceHasNoMixer() {
        let policy = ExperienceAudioRoutingPolicy(preferences: ExperiencePreferences(
            narrationEnabled: false,
            scoreEnabled: false,
            soundscapeEnabled: false
        ))

        XCTAssertEqual(policy.mixerOutputVolume(for: .narration), 0)
        XCTAssertEqual(policy.mixerOutputVolume(for: .score), 0)
        XCTAssertEqual(policy.mixerOutputVolume(for: .soundscape), 0)
        XCTAssertEqual(policy.mixerOutputVolume(for: .spatialDetail), 0)
        XCTAssertNil(policy.mixerOutputVolume(for: .silence))
    }

    func testDownloadPreferencesCannotChangeDramaticRouting() {
        let baseline = ExperienceAudioRoutingPolicy(preferences: .standard)
        let downloadChoices = ExperienceAudioRoutingPolicy(preferences: ExperiencePreferences(
            cellularDownloadsEnabled: true,
            automaticDeepDiveDownloadsEnabled: true
        ))

        XCTAssertEqual(downloadChoices, baseline)
    }

    func testEveryPreferenceCombinationLeavesTimelineTimingAndAuthoredEventsIntact() throws {
        let timeline = Self.timeline()
        let plan = try TimelinePlaybackPlanner.makePlan(
            timeline: timeline,
            cursorSample: 6_000,
            assetMetadata: Self.metadata
        )

        for mask in 0 ..< 16 {
            let preferences = ExperiencePreferences(
                narrationEnabled: mask & 1 != 0,
                scoreEnabled: mask & 2 != 0,
                soundscapeEnabled: mask & 4 != 0,
                hapticsEnabled: mask & 8 != 0
            )
            let policy = ExperienceAudioRoutingPolicy(preferences: preferences)

            XCTAssertEqual(plan.timelineID, timeline.id)
            XCTAssertEqual(plan.cursorSample, 6_000)
            XCTAssertEqual(plan.endSample, 48_000)
            XCTAssertEqual(plan.remainingSamples, 42_000)
            XCTAssertEqual(plan.audioSlices.count, 4)
            XCTAssertEqual(plan.haptics.count, 1)
            XCTAssertEqual(policy.routing(for: .silence), .timingOnly)
        }
    }

    func testSampleAccurateGainKernelCarriesOneRampAcrossUnequalRenderQuanta() {
        var kernel = SampleAccurateGainKernel(initialGain: 0.1)
        kernel.beginRamp(to: 0.3, durationSamples: 9_600)
        var rendered: [Float] = []
        for quantum in [127, 4_096, 1, 3_000, 2_377] {
            for _ in 0 ..< quantum {
                rendered.append(kernel.consumeGain())
            }
        }

        XCTAssertEqual(rendered.count, 9_601)
        XCTAssertEqual(rendered[0], 0.1, accuracy: 0.000_001)
        XCTAssertEqual(rendered[4_800], 0.2, accuracy: 0.000_05)
        XCTAssertLessThan(rendered[9_599], 0.3)
        XCTAssertEqual(rendered[9_600], 0.3, accuracy: 0.000_001)
        XCTAssertEqual(kernel.rampFramesRemaining, 0)
        XCTAssertEqual(kernel.currentGain, 0.3, accuracy: 0.000_001)
    }

    func testSampleAccurateGainKernelHardGateOwnsBoundaryAndFollowingSamples() {
        var kernel = SampleAccurateGainKernel(initialGain: 1)
        XCTAssertEqual(kernel.consumeGain(), 1)
        kernel.setImmediate(0)
        let postBoundary = (0 ... 12).map { _ in kernel.consumeGain() }

        XCTAssertEqual(postBoundary[0], 0)
        XCTAssertEqual(postBoundary[1], 0)
        XCTAssertEqual(postBoundary[12], 0)
    }

    fileprivate static func timeline() -> AudioTimeline {
        AudioTimeline(
            id: "preference-routing",
            sampleRate: 48_000,
            events: [
                event(id: "narration", role: .narration, path: "narration.caf"),
                event(id: "score", role: .score, path: "score.caf"),
                event(id: "soundscape", role: .soundscape, path: "soundscape.caf"),
                event(id: "detail", role: .spatialDetail, path: "detail.caf"),
                AudioEvent(
                    cueID: "silence",
                    role: .silence,
                    startSample: 24_000,
                    durationSamples: 24_000,
                    assetPath: nil,
                    gain: 0
                ),
            ],
            haptics: [
                HapticEvent(
                    sample: 12_000,
                    kind: .contact,
                    intensity: 0.4,
                    sharpness: 0.5
                ),
            ]
        )
    }

    private static func event(
        id: AudioCueID,
        role: AudioTrackRole,
        path: String
    ) -> AudioEvent {
        AudioEvent(
            cueID: id,
            role: role,
            startSample: 0,
            durationSamples: 24_000,
            assetPath: path,
            gain: 1,
            narrationBinding: role == .narration
                ? NarrationCueBinding(
                    manuscriptSegmentID: "preference-routing-narration",
                    manuscriptSegmentSHA256: String(repeating: "a", count: 64),
                    scope: NarrationCueScope(
                        chapterID: "first-farmers",
                        arcID: "fields-that-must-endure",
                        beatID: "harvest-allocation"
                    )
                )
                : nil
        )
    }

    private static let metadata: [String: AudioAssetMetadata] = [
        "narration.caf": .init(
            path: "narration.caf",
            sampleRate: 48_000,
            frameCount: 24_000,
            channelCount: 1
        ),
        "score.caf": .init(
            path: "score.caf",
            sampleRate: 48_000,
            frameCount: 24_000,
            channelCount: 2
        ),
        "soundscape.caf": .init(
            path: "soundscape.caf",
            sampleRate: 48_000,
            frameCount: 24_000,
            channelCount: 2
        ),
        "detail.caf": .init(
            path: "detail.caf",
            sampleRate: 48_000,
            frameCount: 24_000,
            channelCount: 1
        ),
    ]
}

#if os(iOS)
final class NativeExperiencePreferenceRoutingTests: XCTestCase {
    @MainActor
    func testTransportGateUsesExactInitialBudgetAndResumeRejectsOldEpoch()
        async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("durability.caf"),
            channelCount: 2,
            frameCount: 24_000,
            constantAmplitude: 0.5
        )
        let timeline = oneShotTimeline(
            id: "durability-budget",
            path: "durability.caf",
            durationSamples: 24_000,
            includesHaptic: false
        )
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: oneShotTransportPlan(timeline: timeline),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        XCTAssertTrue(
            transport.everyPreparedGainNodeUsesDurabilityGateForTesting
        )

        try transport.play()
        let firstBinding = try transport.activeAudioCursorBinding()
        XCTAssertEqual(firstBinding.renderedGraphSampleRate, 48_000)
        XCTAssertNil(firstBinding.scheduledMappingGeneration)
        let initialCapture = try await Task.detached {
            try firstBinding.feed.capture()
        }.value
        XCTAssertEqual(initialCapture.snapshot.timelineID, timeline.id)
        XCTAssertEqual(initialCapture.snapshot.cursorSample, 0)
        XCTAssertEqual(initialCapture.renderedGraphSample, 0)
        XCTAssertEqual(
            initialCapture.mappingGeneration,
            firstBinding.currentMappingGeneration
        )
        XCTAssertFalse(
            firstBinding.gateToken.authorizeAudio(
                throughRenderedGraphSample: 11_999
            )
        )
        XCTAssertTrue(
            firstBinding.gateToken.authorizeAudio(
                throughRenderedGraphSample: 12_000
            )
        )

        let permitted = try transport.renderOfflineSamplesForTesting(12_000)
        XCTAssertTrue(permitted.joined().contains { abs($0) > 0.01 })
        let drained = try transport.renderOfflineSamplesForTesting(4_096)
        XCTAssertTrue(
            drained.joined().suffix(512).allSatisfy {
                abs($0) < 0.000_001
            }
        )
        XCTAssertFalse(
            firstBinding.gateToken.authorizeAudio(
                throughRenderedGraphSample: 24_000
            )
        )

        _ = try transport.pause()
        XCTAssertFalse(
            firstBinding.gateToken.claimCapture(
                atRenderedGraphSample: 12_000
            )
        )
        do {
            _ = try await Task.detached {
                try firstBinding.feed.capture()
            }.value
            XCTFail("A stopped epoch retained a cursor feed")
        } catch let error as NativeAudioCursorFeedError {
            XCTAssertEqual(error, .unavailable)
        }

        try transport.resume()
        let resumedBinding = try transport.activeAudioCursorBinding()
        XCTAssertGreaterThan(
            resumedBinding.gateToken.epoch,
            firstBinding.gateToken.epoch
        )
        XCTAssertFalse(
            firstBinding.gateToken.authorizeAudio(
                throughRenderedGraphSample: 48_000
            )
        )
        XCTAssertTrue(
            resumedBinding.gateToken.authorizeAudio(
                throughRenderedGraphSample: 36_000
            )
        )
        transport.stop()
    }

    @MainActor
    func testInPlaceAndReplacementTransitionsKeepOneDurabilityEpoch()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in [
            "waiting-score.caf", "engaged-score.caf", "river.caf", "work.caf",
        ] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800,
                constantAmplitude: 0.2
            )
        }
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let waiting = causalTimeline(phase: .waiting)
        let engaged = causalTimeline(phase: .engaged)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: waiting,
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        try transport.play()
        let initial = try transport.activeAudioCursorBinding()

        _ = try transport.transitionResponsiveAudio(
            to: causalTransportPlan(
                timeline: waiting,
                phase: .waiting,
                completedStageCount: 1,
                workGain: 0.4,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver,
            validateBeforeCommit: { _ in }
        )
        let inPlace = try transport.activeAudioCursorBinding()
        XCTAssertEqual(inPlace.gateToken.epoch, initial.gateToken.epoch)
        XCTAssertNotEqual(
            inPlace.currentMappingGeneration,
            initial.currentMappingGeneration
        )
        XCTAssertNil(inPlace.scheduledMappingGeneration)

        _ = try transport.transitionResponsiveAudio(
            to: causalTransportPlan(
                timeline: engaged,
                phase: .engaged,
                completedStageCount: 1,
                workGain: 0.4,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver,
            validateBeforeCommit: { _ in }
        )
        let replacement = try transport.activeAudioCursorBinding()
        XCTAssertEqual(replacement.gateToken.epoch, initial.gateToken.epoch)
        XCTAssertEqual(
            replacement.currentMappingGeneration,
            inPlace.currentMappingGeneration
        )
        XCTAssertNotNil(replacement.scheduledMappingGeneration)
        XCTAssertTrue(
            transport.everyPreparedGainNodeUsesDurabilityGateForTesting
        )
        transport.stop()
    }

    @MainActor
    func testAutomaticSuccessorMappingIsPublishedBeforePhysicalBoundary()
        async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["approach.caf", "waiting.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800,
                constantAmplitude: 0.2
            )
        }
        let approach = oneShotTimeline(
            id: "raw-feed-approach",
            path: "approach.caf",
            durationSamples: 4_800,
            includesHaptic: false
        )
        let waiting = oneShotTimeline(
            id: "raw-feed-waiting",
            path: "waiting.caf",
            durationSamples: 4_800,
            includesHaptic: false
        )
        let successor = ResponsiveAudioTimelineTransportPlan(
            timeline: waiting,
            cursorSample: 0,
            loopIteration: 0,
            repetition: .loop(iteration: 0, durationSamples: 4_800),
            causalMix: nil
        )
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: ResponsiveAudioTimelineTransportPlan(
                timeline: approach,
                cursorSample: 4_799,
                loopIteration: 0,
                repetition: .once,
                causalMix: nil
            ),
            resolver: resolver
        )
        try transport.configureAutomaticBoundary(
            successorPlan: successor,
            resolver: resolver,
            handler: { _ in }
        )
        try transport.play()

        let binding = try transport.activeAudioCursorBinding()
        let successorGeneration = try XCTUnwrap(
            binding.scheduledMappingGeneration
        )
        let before = try await Task.detached {
            try binding.feed.capture()
        }.value
        XCTAssertEqual(before.snapshot.timelineID, approach.id)
        XCTAssertEqual(before.snapshot.cursorSample, 4_799)
        XCTAssertEqual(before.mappingGeneration, binding.currentMappingGeneration)

        let boundary = try XCTUnwrap(
            transport.automaticCursorBoundaryForTesting
        )
        transport.publishRenderClockAnchorForTesting(
            graphSampleEnd: boundary,
            hostTimeAtGraphSampleEnd: nil
        )
        let crossed = try await Task.detached {
            try binding.feed.capture()
        }.value
        XCTAssertEqual(crossed.renderedGraphSample, boundary)
        XCTAssertEqual(crossed.snapshot.timelineID, waiting.id)
        XCTAssertEqual(crossed.snapshot.cursorSample, 0)
        XCTAssertEqual(crossed.snapshot.loopIteration, 0)
        XCTAssertEqual(crossed.mappingGeneration, successorGeneration)
        // No MainActor promotion was needed to obtain the physical mapping.
        XCTAssertEqual(transport.preparedPlanForTesting?.timelineID, approach.id)
        XCTAssertTrue(
            transport.everyPreparedGainNodeUsesDurabilityGateForTesting
        )
        transport.stop()
    }

    @MainActor
    func testReplacementAndAutomaticCompletionKeepEveryQueuedCursorMapping()
        async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["interaction.caf", "consequence.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800,
                constantAmplitude: 0.2
            )
        }
        let interaction = oneShotTimeline(
            id: "queued-interaction",
            path: "interaction.caf",
            includesHaptic: false
        )
        let consequence = oneShotTimeline(
            id: "queued-consequence",
            path: "consequence.caf",
            includesHaptic: false
        )
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: ResponsiveAudioTimelineTransportPlan(
                timeline: interaction,
                cursorSample: 0,
                loopIteration: 0,
                repetition: .loop(iteration: 0, durationSamples: 4_800),
                causalMix: nil
            ),
            resolver: resolver
        )
        try transport.play()
        _ = try transport.transitionResponsiveAudio(
            to: oneShotTransportPlan(timeline: consequence),
            resolver: resolver,
            validateBeforeCommit: { _ in }
        )
        try transport.configureAutomaticBoundary(
            successorPlan: nil,
            resolver: resolver,
            handler: { _ in }
        )

        let binding = try transport.activeAudioCursorBinding()
        XCTAssertEqual(binding.mappingDescriptors.count, 3)
        XCTAssertEqual(binding.scheduledMappingGenerations.count, 2)
        let descriptors = binding.mappingDescriptors
        XCTAssertEqual(
            descriptors.map(\.snapshotAtBoundary.timelineID),
            [interaction.id, consequence.id, consequence.id]
        )
        XCTAssertTrue(descriptors[0].snapshotAtBoundary.isPlaying)
        XCTAssertTrue(descriptors[1].snapshotAtBoundary.isPlaying)
        XCTAssertFalse(descriptors[2].snapshotAtBoundary.isPlaying)
        XCTAssertEqual(descriptors[1].snapshotAtBoundary.cursorSample, 0)
        XCTAssertEqual(descriptors[2].snapshotAtBoundary.cursorSample, 4_800)

        let before = try await Task.detached {
            try binding.feed.capture()
        }.value
        XCTAssertEqual(before.snapshot.timelineID, interaction.id)

        transport.publishRenderClockAnchorForTesting(
            graphSampleEnd: descriptors[1].graphBoundarySample,
            hostTimeAtGraphSampleEnd: nil
        )
        let consequenceCapture = try await Task.detached {
            try binding.feed.capture()
        }.value
        XCTAssertEqual(consequenceCapture.snapshot.timelineID, consequence.id)
        XCTAssertEqual(consequenceCapture.snapshot.cursorSample, 0)
        XCTAssertTrue(consequenceCapture.snapshot.isPlaying)
        XCTAssertEqual(
            consequenceCapture.mappingGeneration,
            descriptors[1].generation
        )

        transport.publishRenderClockAnchorForTesting(
            graphSampleEnd: descriptors[2].graphBoundarySample,
            hostTimeAtGraphSampleEnd: nil
        )
        let completed = try await Task.detached {
            try binding.feed.capture()
        }.value
        XCTAssertEqual(completed.snapshot.timelineID, consequence.id)
        XCTAssertEqual(completed.snapshot.cursorSample, 4_800)
        XCTAssertFalse(completed.snapshot.isPlaying)
        XCTAssertEqual(completed.mappingGeneration, descriptors[2].generation)
        transport.stop()
    }

    func testSampleAccurateGainAudioUnitPassesMonoAndStereoAtAuthoredGain() throws {
        for channelCount: AVAudioChannelCount in [1, 2] {
            let gainNode = try makeStandaloneGainNode(
                channelCount: channelCount,
                initialGain: 0.5
            )
            defer { gainNode.audioUnit.deallocateRenderResources() }
            let buffer = try makeRenderBuffer(
                channelCount: channelCount,
                frameCapacity: 64
            )
            let result = invokeGainRender(
                gainNode.audioUnit,
                buffer: buffer,
                frameCount: 64,
                pullInputBlock: fillingPullInput(value: 1)
            )

            XCTAssertEqual(result.status, noErr)
            let channels = try XCTUnwrap(buffer.floatChannelData)
            for channel in 0 ..< Int(channelCount) {
                for frame in 0 ..< 64 {
                    XCTAssertEqual(channels[channel][frame], 0.5, accuracy: 0.000_001)
                }
            }
        }
    }

    func testSampleAccurateGainAudioUnitUsesLatestTargetAtSharedBoundary() throws {
        let gainNode = try makeStandaloneGainNode(
            channelCount: 1,
            initialGain: 0
        )
        defer { gainNode.audioUnit.deallocateRenderResources() }
        let buffer = try makeRenderBuffer(
            channelCount: 1,
            frameCapacity: 512
        )
        let first = makeRenderEvent(
            type: .parameterRamp,
            duration: 480,
            address: 0,
            value: 0.35,
            sample: 0
        )
        let latest = makeRenderEvent(
            type: .parameterRamp,
            duration: 480,
            address: 0,
            value: 0.8,
            sample: 0
        )
        defer {
            first.deinitialize(count: 1)
            first.deallocate()
            latest.deinitialize(count: 1)
            latest.deallocate()
        }
        first.pointee.parameter.next = latest

        let result = invokeGainRender(
            gainNode.audioUnit,
            buffer: buffer,
            frameCount: 512,
            event: UnsafePointer(first),
            pullInputBlock: fillingPullInput(value: 1)
        )
        XCTAssertEqual(result.status, noErr)
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        XCTAssertEqual(samples[0], 0, accuracy: 0)
        XCTAssertEqual(samples[480], 0.8, accuracy: 0.000_001)
        XCTAssertEqual(samples[511], 0.8, accuracy: 0.000_001)
    }

    func testSampleAccurateGainAudioUnitFailsClosedBeforeKernelMutation() throws {
        let gainNode = try makeStandaloneGainNode(
            channelCount: 2,
            initialGain: 1
        )
        defer { gainNode.audioUnit.deallocateRenderResources() }
        let buffer = try makeRenderBuffer(channelCount: 2, frameCapacity: 32)

        fillRenderBuffer(buffer, value: 1)
        let noConnection = invokeGainRender(
            gainNode.audioUnit,
            buffer: buffer,
            frameCount: 32,
            pullInputBlock: nil
        )
        XCTAssertEqual(noConnection.status, kAudioUnitErr_NoConnection)
        assertRenderBufferIsSilent(buffer, frameCount: 32)

        fillRenderBuffer(buffer, value: 1)
        let pullFailureStatus: OSStatus = -7_777
        let pullFailure = invokeGainRender(
            gainNode.audioUnit,
            buffer: buffer,
            frameCount: 32,
            pullInputBlock: { _, _, _, _, _ in pullFailureStatus }
        )
        XCTAssertEqual(pullFailure.status, pullFailureStatus)
        assertRenderBufferIsSilent(buffer, frameCount: 32)

        fillRenderBuffer(buffer, value: 1)
        let shortBuffer = invokeGainRender(
            gainNode.audioUnit,
            buffer: buffer,
            frameCount: 32,
            pullInputBlock: { _, _, _, _, outputData in
                let buffers = UnsafeMutableAudioBufferListPointer(outputData)
                for index in buffers.indices {
                    buffers[index].mDataByteSize = 31 * UInt32(MemoryLayout<Float>.size)
                }
                return noErr
            }
        )
        XCTAssertEqual(shortBuffer.status, kAudioUnitErr_InvalidPropertyValue)
        assertRenderBufferIsSilent(buffer, frameCount: 31)

        for invalidEvent in [
            makeRenderEvent(type: .parameterRamp, duration: 1, address: 0, value: .nan),
            makeRenderEvent(type: .parameterRamp, duration: 1, address: 0, value: -0.001),
            makeRenderEvent(type: .parameterRamp, duration: 1, address: 0, value: 4.001),
            makeRenderEvent(type: .parameterRamp, duration: 1, address: 99, value: 1),
            makeRenderEvent(type: .parameterRamp, duration: 0, address: 0, value: 1),
            makeRenderEvent(type: .parameter, duration: 1, address: 0, value: 1),
            makeRenderEvent(type: .parameter, duration: 0, address: 0, value: 1, sample: 32),
            makeRenderEvent(type: .MIDI, duration: 0, address: 0, value: 1),
        ] {
            defer {
                invalidEvent.deinitialize(count: 1)
                invalidEvent.deallocate()
            }
            var pullWasCalled = false
            fillRenderBuffer(buffer, value: 1)
            let rejected = invokeGainRender(
                gainNode.audioUnit,
                buffer: buffer,
                frameCount: 32,
                event: UnsafePointer(invalidEvent),
                pullInputBlock: { _, _, _, _, _ in
                    pullWasCalled = true
                    return noErr
                }
            )
            XCTAssertEqual(rejected.status, kAudioUnitErr_InvalidParameter)
            XCTAssertFalse(pullWasCalled)
            assertRenderBufferIsSilent(buffer, frameCount: 32)
        }

        var invalidTimestamp = AudioTimeStamp()
        invalidTimestamp.mSampleTime = .nan
        invalidTimestamp.mFlags = .sampleTimeValid
        var timestampPullWasCalled = false
        fillRenderBuffer(buffer, value: 1)
        let rejectedTimestamp = invokeGainRender(
            gainNode.audioUnit,
            buffer: buffer,
            frameCount: 32,
            timestamp: invalidTimestamp,
            pullInputBlock: { _, _, _, _, _ in
                timestampPullWasCalled = true
                return noErr
            }
        )
        XCTAssertEqual(rejectedTimestamp.status, kAudioUnitErr_InvalidPropertyValue)
        XCTAssertFalse(timestampPullWasCalled)
        assertRenderBufferIsSilent(buffer, frameCount: 32)

        fillRenderBuffer(buffer, value: 0)
        let validFollowUp = invokeGainRender(
            gainNode.audioUnit,
            buffer: buffer,
            frameCount: 32,
            pullInputBlock: fillingPullInput(value: 1)
        )
        XCTAssertEqual(validFollowUp.status, noErr)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0 ..< 2 {
            for frame in 0 ..< 32 {
                XCTAssertEqual(channels[channel][frame], 1, accuracy: 0)
            }
        }

        XCTAssertThrowsError(
            try SampleAccurateGainNode.make(initialGain: .nan)
        )
        XCTAssertThrowsError(
            try SampleAccurateGainNode.make(initialGain: 4.001)
        )
    }

    @MainActor
    func testMutedRoleStillRequiresItsOfflineAsset() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = ExperiencePreferences(
            narrationEnabled: false,
            scoreEnabled: false,
            soundscapeEnabled: false
        )
        let transport = NativeTimelineTransport(preferences: preferences)
        let timeline = AudioTimeline(
            id: "missing-muted-asset",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "narration",
                    role: .narration,
                    startSample: 0,
                    durationSamples: 24_000,
                    assetPath: "missing-narration.caf",
                    gain: 1,
                    narrationBinding: NarrationCueBinding(
                        manuscriptSegmentID: "muted-narration",
                        manuscriptSegmentSHA256: String(repeating: "b", count: 64),
                        scope: NarrationCueScope(
                            chapterID: "first-farmers",
                            arcID: "fields-that-must-endure",
                            beatID: "harvest-allocation"
                        )
                    )
                ),
            ],
            haptics: []
        )

        XCTAssertThrowsError(
            try transport.prepare(
                timeline: timeline,
                cursorSample: 0,
                resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
            )
        ) { error in
            XCTAssertEqual(
                error as? OfflineAudioAssetResolutionError,
                .missingFile("missing-narration.caf")
            )
        }
        XCTAssertEqual(transport.state, .idle)
    }

    @MainActor
    func testRuntimePreferenceChangesOnlyMuteOutputsAcrossPreparedPlayingAndPaused() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioAssets(to: directory)
        let allOff = ExperiencePreferences(
            narrationEnabled: false,
            scoreEnabled: false,
            soundscapeEnabled: false,
            hapticsEnabled: false
        )
        let transport = NativeTimelineTransport(preferences: allOff)

        transport.applyPreferences(allOff)
        XCTAssertEqual(transport.state, .idle)
        try transport.prepare(
            timeline: ExperienceAudioRoutingPolicyTests.timeline(),
            cursorSample: 6_000,
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )

        let mutedPreparedSnapshot = transport.snapshot()
        let preparedPlan = try XCTUnwrap(transport.preparedPlanForTesting)
        XCTAssertEqual(transport.state, .prepared)
        XCTAssertEqual(preparedPlan.cursorSample, 6_000)
        XCTAssertEqual(preparedPlan.endSample, 48_000)
        XCTAssertEqual(preparedPlan.audioSlices.count, 4)
        XCTAssertEqual(preparedPlan.haptics.count, 1)
        for role in [
            AudioTrackRole.narration,
            .score,
            .soundscape,
            .spatialDetail,
        ] {
            XCTAssertNil(transport.mixerOutputVolumeForTesting(role))
        }

        transport.applyPreferences(.standard)
        XCTAssertEqual(transport.state, .prepared)
        XCTAssertEqual(transport.snapshot(), mutedPreparedSnapshot)
        XCTAssertEqual(
            transport.routingPolicy,
            ExperienceAudioRoutingPolicy(preferences: .standard)
        )

        do {
            try transport.play()
        } catch {
            transport.stop()
            throw XCTSkip("Simulator audio engine unavailable: \(error)")
        }
        XCTAssertEqual(transport.state, .playing)
        assertMixerVolumes(transport, narration: 1, score: 1, soundscape: 1, detail: 1)
        let beforePlayingChange = transport.snapshot()

        transport.applyPreferences(allOff)
        let afterPlayingChange = transport.snapshot()
        XCTAssertEqual(transport.state, .playing)
        XCTAssertEqual(afterPlayingChange.timelineID, beforePlayingChange.timelineID)
        XCTAssertTrue(afterPlayingChange.isPlaying)
        XCTAssertGreaterThanOrEqual(
            afterPlayingChange.cursorSample,
            beforePlayingChange.cursorSample
        )
        XCTAssertEqual(transport.preparedPlanForTesting?.endSample, 48_000)
        assertMixerVolumes(transport, narration: 0, score: 0, soundscape: 0, detail: 0)

        let paused = try transport.pause()
        XCTAssertEqual(transport.state, .paused)
        XCTAssertFalse(paused.isPlaying)
        transport.applyPreferences(.standard)
        XCTAssertEqual(transport.state, .paused)
        XCTAssertEqual(transport.snapshot(), paused)
        XCTAssertEqual(transport.preparedPlanForTesting?.endSample, 48_000)
        assertMixerVolumes(transport, narration: 1, score: 1, soundscape: 1, detail: 1)
        transport.stop()
    }

    @MainActor
    func testPhaseOnlyInteractionBedLoopsEveryAudibleRolePastFirstBoundary() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["waiting-score.caf", "river.caf", "work.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let timeline = causalTimeline(phase: .waiting)
        let transport = NativeTimelineTransport()
        try transport.prepareResponsiveAudio(
            plan: ResponsiveAudioTimelineTransportPlan(
                timeline: timeline,
                cursorSample: 0,
                loopIteration: 0,
                repetition: .loop(iteration: 0, durationSamples: 4_800),
                causalMix: nil
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )

        let cueIDs = [
            AudioCueID("waiting-score"),
            AudioCueID("waiting-river"),
            AudioCueID("waiting-work"),
        ]
        for cueID in cueIDs {
            XCTAssertNil(transport.conventionalLoopBufferCountForTesting(cueID))
        }

        // Phase-only interaction programs use this same transport path. Their
        // score, soundscape and spatial detail must all remain scheduled after
        // the first interaction-bed boundary.
        try transport.play()
        for cueID in cueIDs {
            XCTAssertEqual(
                transport.conventionalLoopBufferCountForTesting(cueID),
                1
            )
        }
        usleep(420_000)
        XCTAssertGreaterThanOrEqual(transport.snapshot().loopIteration, 2)
        for cueID in cueIDs {
            XCTAssertEqual(
                transport.conventionalPlayerIsPlayingForTesting(cueID),
                true
            )
        }
        transport.stop()
    }

    @MainActor
    func testManualRenderClockAdvancesOnlyByFramesActuallyRendered() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["waiting-score.caf", "river.caf", "work.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let timeline = causalTimeline(phase: .waiting)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: timeline,
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        try transport.play()

        usleep(120_000)
        XCTAssertEqual(transport.snapshot().cursorSample, 0)
        XCTAssertEqual(transport.snapshot().loopIteration, 0)

        _ = try transport.renderOfflineSamplesForTesting(1_234)
        XCTAssertEqual(transport.snapshot().cursorSample, 1_234)
        XCTAssertEqual(transport.snapshot().loopIteration, 0)

        _ = try transport.renderOfflineSamplesForTesting(4_000)
        XCTAssertEqual(transport.snapshot().cursorSample, 434)
        XCTAssertEqual(transport.snapshot().loopIteration, 1)

        let interrupted = try transport.pauseForInterruption()
        usleep(120_000)
        XCTAssertEqual(transport.snapshot(), interrupted)
        XCTAssertFalse(transport.engineIsRunningForTesting)
        transport.stop()
    }

    @MainActor
    func testHapticStartFailureRollsBackToOneCleanPreparedGraphAndRetryRenders() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["waiting-score.caf", "river.caf", "work.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let timeline = causalTimeline(phase: .waiting)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: timeline,
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        XCTAssertNotNil(transport.commonPlayerIdentityForTesting("river"))
        transport.injectHapticStartFailureForTesting()

        XCTAssertThrowsError(try transport.play())
        XCTAssertEqual(transport.state, .prepared)
        XCTAssertFalse(transport.engineIsRunningForTesting)
        XCTAssertEqual(transport.playingNodeCountForTesting, 0)
        XCTAssertEqual(transport.snapshot().cursorSample, 0)
        XCTAssertNil(transport.commonPlayerIdentityForTesting("river"))
        XCTAssertNil(transport.commonPlayerScheduleCountForTesting("river"))

        try transport.play()
        XCTAssertNotNil(transport.commonPlayerIdentityForTesting("river"))
        XCTAssertEqual(transport.commonPlayerScheduleCountForTesting("river"), 1)
        _ = try transport.renderOfflineSamplesForTesting(64)
        XCTAssertEqual(transport.snapshot().cursorSample, 64)
        XCTAssertGreaterThan(transport.playingNodeCountForTesting, 0)
        transport.stop()
    }

    @MainActor
    func testPhasePreflightFailuresLeaveActiveGraphUntouchedAndRetryIsSampleAtomic() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in [
            "waiting-score.caf", "engaged-score.caf", "river.caf", "work.caf",
        ] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let resolver = CountingAudioResolver(root: directory)
        let waiting = causalTimeline(phase: .waiting)
        let engaged = causalTimeline(phase: .engaged)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: waiting,
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        try transport.play()
        _ = try transport.renderOfflineSamplesForTesting(512)
        let before = transport.snapshot()
        let riverIdentity = transport.commonPlayerIdentityForTesting("river")
        let workIdentity = transport.commonPlayerIdentityForTesting("work")
        let scoreIdentity = transport.conventionalPlayerIdentityForTesting(
            "waiting-score"
        )
        let requested = causalTransportPlan(
            timeline: engaged,
            phase: .engaged,
            completedStageCount: 1,
            workGain: 0.35,
            cursorSample: before.cursorSample,
            loopIteration: before.loopIteration
        )

        resolver.failingPaths = ["engaged-score.caf"]
        XCTAssertThrowsError(
            try transport.transitionResponsiveAudio(to: requested, resolver: resolver)
        )
        assertActiveGraphUnchanged(
            transport,
            snapshot: before,
            riverIdentity: riverIdentity,
            workIdentity: workIdentity,
            scoreIdentity: scoreIdentity
        )

        resolver.failingPaths = []
        transport.injectGainUnitInstantiationFailureForTesting()
        XCTAssertThrowsError(
            try transport.transitionResponsiveAudio(to: requested, resolver: resolver)
        )
        assertActiveGraphUnchanged(
            transport,
            snapshot: before,
            riverIdentity: riverIdentity,
            workIdentity: workIdentity,
            scoreIdentity: scoreIdentity
        )

        transport.injectConventionalAttachFailureForTesting("engaged-score")
        XCTAssertThrowsError(
            try transport.transitionResponsiveAudio(to: requested, resolver: resolver)
        )
        assertActiveGraphUnchanged(
            transport,
            snapshot: before,
            riverIdentity: riverIdentity,
            workIdentity: workIdentity,
            scoreIdentity: scoreIdentity
        )

        enum GuardFailure: Error, Equatable {
            case rejected
        }
        XCTAssertThrowsError(
            try transport.transitionResponsiveAudio(
                to: requested,
                resolver: resolver,
                validateBeforeCommit: { _ in
                    throw GuardFailure.rejected
                }
            )
        ) { error in
            XCTAssertEqual(error as? GuardFailure, .rejected)
        }
        assertActiveGraphUnchanged(
            transport,
            snapshot: before,
            riverIdentity: riverIdentity,
            workIdentity: workIdentity,
            scoreIdentity: scoreIdentity
        )
        XCTAssertEqual(transport.pendingPhysicalTransitionCountForTesting, 0)

        let transitioned = try transport.transitionResponsiveAudio(
            to: requested,
            resolver: resolver
        )
        XCTAssertEqual(transitioned.cursorSample, before.cursorSample)
        XCTAssertEqual(
            transport.conventionalMuteSampleForTesting("waiting-score"),
            transport.transitionBoundaryForTesting
        )
        XCTAssertEqual(
            transport.conventionalStartSampleForTesting("engaged-score"),
            transport.transitionBoundaryForTesting
        )
        XCTAssertEqual(transport.commonPlayerIdentityForTesting("river"), riverIdentity)
        XCTAssertEqual(transport.commonPlayerIdentityForTesting("work"), workIdentity)
        transport.stop()
    }

    @MainActor
    func testPhaseTransitionReportsOnlyRenderedCursorAndPausedResumeRetriesAtomically() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in [
            "waiting-score.caf", "engaged-score.caf", "river.caf", "work.caf",
        ] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: causalTimeline(phase: .waiting),
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        try transport.play()

        let transitioned = try transport.transitionResponsiveAudio(
            to: causalTransportPlan(
                timeline: causalTimeline(phase: .engaged),
                phase: .engaged,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        XCTAssertEqual(transitioned.timelineID, "native-engaged-bed")
        XCTAssertEqual(transitioned.cursorSample, 0)
        XCTAssertEqual(transport.snapshot().cursorSample, 0)
        XCTAssertEqual(transport.pendingPhysicalTransitionCountForTesting, 1)

        _ = try transport.renderOfflineSamplesForTesting(64)
        XCTAssertEqual(transport.snapshot().cursorSample, 64)
        let paused = try transport.pause()
        XCTAssertEqual(paused.timelineID, "native-engaged-bed")
        XCTAssertEqual(paused.cursorSample, 64)
        XCTAssertEqual(transport.state, .paused)
        XCTAssertEqual(transport.pendingPhysicalTransitionCountForTesting, 0)

        transport.injectConventionalAttachFailureForTesting("engaged-score")
        XCTAssertThrowsError(try transport.play())
        XCTAssertEqual(transport.state, .paused)
        XCTAssertEqual(transport.snapshot(), paused)

        try transport.play()
        _ = try transport.renderOfflineSamplesForTesting(32)
        XCTAssertEqual(
            transport.renderedSampleOffsetForTesting,
            32,
            "end=\(transport.renderedGraphSampleEndForTesting) base=\(transport.renderClockBaseGraphSampleForTesting)"
        )
        XCTAssertEqual(transport.snapshot().cursorSample, 96)
        transport.stop()
    }

    @MainActor
    func testConsequenceHoldsCursorAtZeroUntilBoundaryAndPauseKeepsIntent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in [
            "waiting-score.caf", "river.caf", "work.caf", "consequence.caf",
        ] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let consequence = AudioTimeline(
            id: "native-consequence",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "consequence-score",
                    role: .score,
                    startSample: 0,
                    durationSamples: 4_800,
                    assetPath: "consequence.caf",
                    gain: 0.5
                ),
            ],
            haptics: []
        )
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: causalTimeline(phase: .waiting),
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        try transport.play()

        let transitioned = try transport.transitionResponsiveAudio(
            to: ResponsiveAudioTimelineTransportPlan(
                timeline: consequence,
                cursorSample: 0,
                loopIteration: 0,
                repetition: .once,
                causalMix: nil
            ),
            resolver: resolver
        )
        XCTAssertEqual(transitioned.timelineID, consequence.id)
        XCTAssertEqual(transitioned.cursorSample, 0)
        _ = try transport.renderOfflineSamplesForTesting(64)
        XCTAssertEqual(transport.snapshot().cursorSample, 0)

        let paused = try transport.pause()
        XCTAssertEqual(paused.timelineID, consequence.id)
        XCTAssertEqual(paused.cursorSample, 0)
        XCTAssertEqual(transport.state, .paused)
        try transport.play()
        _ = try transport.renderOfflineSamplesForTesting(32)
        XCTAssertEqual(
            transport.renderedSampleOffsetForTesting,
            32,
            "end=\(transport.renderedGraphSampleEndForTesting) base=\(transport.renderClockBaseGraphSampleForTesting)"
        )
        XCTAssertEqual(transport.snapshot().cursorSample, 32)
        transport.stop()
    }

    @MainActor
    func testRapidPhaseReplacementReusesOneBoundaryAndFailedReplacementPreservesPendingGraph() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in [
            "waiting-score.caf", "engaged-score.caf", "river.caf", "work.caf",
        ] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let waiting = causalTimeline(phase: .waiting)
        let engaged = causalTimeline(phase: .engaged)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: waiting,
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        let baselineAttachedNodes = transport.attachedNodeCountForTesting
        try transport.play()

        _ = try transport.transitionResponsiveAudio(
            to: causalTransportPlan(
                timeline: engaged,
                phase: .engaged,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        let firstBoundary = try XCTUnwrap(
            transport.transitionBoundaryForTesting
        )
        let pendingEngagedIdentity = try XCTUnwrap(
            transport.conventionalPlayerIdentityForTesting("engaged-score")
        )
        XCTAssertEqual(firstBoundary, 128)
        XCTAssertEqual(transport.snapshot().cursorSample, 0)

        transport.injectConventionalAttachFailureForTesting("waiting-score")
        XCTAssertThrowsError(
            try transport.transitionResponsiveAudio(
                to: causalTransportPlan(
                    timeline: waiting,
                    phase: .waiting,
                    completedStageCount: 0,
                    workGain: 0,
                    cursorSample: 0,
                    loopIteration: 0
                ),
                resolver: resolver
            )
        )
        XCTAssertEqual(
            transport.conventionalPlayerIdentityForTesting("engaged-score"),
            pendingEngagedIdentity
        )
        XCTAssertEqual(transport.transitionBoundaryForTesting, firstBoundary)
        XCTAssertEqual(transport.pendingPhysicalTransitionCountForTesting, 1)

        _ = try transport.transitionResponsiveAudio(
            to: causalTransportPlan(
                timeline: waiting,
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        XCTAssertNil(
            transport.conventionalPlayerIdentityForTesting("engaged-score")
        )
        XCTAssertEqual(transport.transitionBoundaryForTesting, firstBoundary)

        _ = try transport.renderOfflineSamplesForTesting(64)
        XCTAssertEqual(transport.snapshot().cursorSample, 64)
        _ = try transport.transitionResponsiveAudio(
            to: causalTransportPlan(
                timeline: engaged,
                phase: .engaged,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 64,
                loopIteration: 0
            ),
            resolver: resolver
        )
        XCTAssertEqual(transport.transitionBoundaryForTesting, firstBoundary)
        XCTAssertEqual(transport.snapshot().cursorSample, 64)

        _ = try transport.renderOfflineSamplesForTesting(64)
        XCTAssertEqual(transport.snapshot().cursorSample, 128)
        XCTAssertEqual(transport.pendingPhysicalTransitionCountForTesting, 0)
        XCTAssertEqual(transport.retiredSliceCountForTesting, 0)
        XCTAssertEqual(transport.retiredCommonLayerCountForTesting, 0)
        XCTAssertLessThanOrEqual(transport.retainedLoopBufferCountForTesting, 2)
        XCTAssertEqual(transport.attachedNodeCountForTesting, baselineAttachedNodes)
        transport.stop()
    }

    @MainActor
    func testOneHundredRenderedPhaseTransitionsKeepRetiredGraphAndBuffersBounded() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in [
            "waiting-score.caf", "engaged-score.caf", "river.caf", "work.caf",
        ] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let waiting = causalTimeline(phase: .waiting)
        let engaged = causalTimeline(phase: .engaged)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: waiting,
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        let baselineAttachedNodes = transport.attachedNodeCountForTesting
        try transport.play()

        for index in 0 ..< 100 {
            let phase: ResponsiveInteractionAudioPhase = index.isMultiple(of: 2)
                ? .engaged
                : .waiting
            let timeline = phase == .engaged ? engaged : waiting
            let before = transport.snapshot()
            _ = try transport.transitionResponsiveAudio(
                to: causalTransportPlan(
                    timeline: timeline,
                    phase: phase,
                    completedStageCount: 0,
                    workGain: 0,
                    cursorSample: before.cursorSample,
                    loopIteration: before.loopIteration
                ),
                resolver: resolver
            )
            XCTAssertEqual(transport.pendingPhysicalTransitionCountForTesting, 1)
            XCTAssertLessThanOrEqual(transport.retiredSliceCountForTesting, 1)
            XCTAssertLessThanOrEqual(transport.retainedLoopBufferCountForTesting, 4)

            _ = try transport.renderOfflineSamplesForTesting(128)
            _ = transport.snapshot()
            XCTAssertEqual(transport.pendingPhysicalTransitionCountForTesting, 0)
            XCTAssertEqual(transport.retiredSliceCountForTesting, 0)
            XCTAssertEqual(transport.retiredCommonLayerCountForTesting, 0)
            XCTAssertGreaterThan(transport.retainedLoopBufferCountForTesting, 0)
            XCTAssertLessThanOrEqual(transport.retainedLoopBufferCountForTesting, 2)
            XCTAssertEqual(
                transport.attachedNodeCountForTesting,
                baselineAttachedNodes
            )
        }
        transport.stop()
    }

    @MainActor
    func testRenderThreadClockSurvivesUnavailableRealtimeNodeLookupWithoutSnapshot() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in [
            "waiting-score.caf", "river.caf", "work.caf",
        ] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let transport = NativeTimelineTransport()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: causalTimeline(phase: .waiting),
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        try transport.play()
        usleep(220_000)
        let renderedWithoutSnapshot = transport.renderedSampleOffsetForTesting
        XCTAssertGreaterThan(renderedWithoutSnapshot, 0)

        transport.setRenderTimeLookupUnavailableForTesting(true)
        let paused = try transport.pauseForRouteChange()
        let absolutePaused = Int64(paused.loopIteration) * 4_800
            + paused.cursorSample
        XCTAssertGreaterThanOrEqual(absolutePaused, renderedWithoutSnapshot)
        XCTAssertEqual(transport.state, .paused)

        transport.setRenderTimeLookupUnavailableForTesting(false)
        try transport.resume()
        usleep(160_000)
        let interrupted = try transport.pauseForInterruption()
        let absoluteInterrupted = Int64(interrupted.loopIteration) * 4_800
            + interrupted.cursorSample
        XCTAssertGreaterThan(absoluteInterrupted, absolutePaused)
        transport.stop()
    }

    @MainActor
    func testOnePendingBoundaryCoalescesStagePhaseAndConsequenceQueues() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in [
            "waiting-score.caf", "engaged-score.caf", "river.caf", "work.caf",
            "consequence.caf",
        ] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let waiting = causalTimeline(phase: .waiting)
        let engaged = causalTimeline(phase: .engaged)
        let consequence = AudioTimeline(
            id: "coalesced-consequence",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "consequence-score",
                    role: .score,
                    startSample: 0,
                    durationSamples: 4_800,
                    assetPath: "consequence.caf",
                    gain: 0.5
                ),
            ],
            haptics: []
        )
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: waiting,
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        try transport.play()

        _ = try transport.transitionResponsiveAudio(
            to: causalTransportPlan(
                timeline: waiting,
                phase: .waiting,
                completedStageCount: 1,
                workGain: 0.35,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        let boundary = try XCTUnwrap(transport.transitionBoundaryForTesting)
        XCTAssertEqual(transport.causalRampScheduleCountForTesting("work"), 1)

        _ = try transport.transitionResponsiveAudio(
            to: causalTransportPlan(
                timeline: engaged,
                phase: .engaged,
                completedStageCount: 1,
                workGain: 0.35,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        XCTAssertEqual(transport.transitionBoundaryForTesting, boundary)
        let engagedIdentity = try XCTUnwrap(
            transport.conventionalPlayerIdentityForTesting("engaged-score")
        )

        _ = try transport.transitionResponsiveAudio(
            to: causalTransportPlan(
                timeline: engaged,
                phase: .engaged,
                completedStageCount: 2,
                workGain: 0.8,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        XCTAssertEqual(transport.transitionBoundaryForTesting, boundary)
        XCTAssertEqual(
            transport.conventionalPlayerIdentityForTesting("engaged-score"),
            engagedIdentity
        )
        XCTAssertEqual(transport.causalTargetGainForTesting("work"), 0.8)
        XCTAssertEqual(transport.causalRampScheduleCountForTesting("work"), 2)

        let transitioned = try transport.transitionResponsiveAudio(
            to: ResponsiveAudioTimelineTransportPlan(
                timeline: consequence,
                cursorSample: 0,
                loopIteration: 0,
                repetition: .once,
                causalMix: nil
            ),
            resolver: resolver
        )
        XCTAssertEqual(transitioned.timelineID, consequence.id)
        XCTAssertEqual(transitioned.cursorSample, 0)
        XCTAssertEqual(transport.transitionBoundaryForTesting, boundary)
        XCTAssertNil(
            transport.conventionalPlayerIdentityForTesting("engaged-score")
        )
        XCTAssertEqual(transport.pendingPhysicalTransitionCountForTesting, 1)

        _ = try transport.renderOfflineSamplesForTesting(64)
        XCTAssertEqual(transport.snapshot().cursorSample, 0)
        _ = try transport.renderOfflineSamplesForTesting(64)
        XCTAssertEqual(transport.snapshot().cursorSample, 0)
        XCTAssertEqual(transport.pendingPhysicalTransitionCountForTesting, 0)
        XCTAssertEqual(transport.retiredSliceCountForTesting, 0)
        XCTAssertEqual(transport.retiredCommonLayerCountForTesting, 0)
        _ = try transport.renderOfflineSamplesForTesting(32)
        XCTAssertEqual(transport.snapshot().cursorSample, 32)
        transport.stop()
    }

    @MainActor
    func testManualImpulseHandoffHasNoGapOverlapOrMaterialClockSlip() throws {
        let waiting = causalTimeline(phase: .waiting)
        let engaged = causalTimeline(phase: .engaged)
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        func renderHandoff(
            name: String,
            waitingAmplitude: Float,
            engagedAmplitude: Float,
            materialAmplitude: Float
        ) throws -> (output: [[Float]], oldPreboundaryPeak: Float) {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            for (path, amplitude, impulseSample) in [
                ("engaged-score.caf", engagedAmplitude, 1_060),
                ("river.caf", materialAmplitude, 1_100),
            ] {
                try writeAudioFile(
                    to: directory.appendingPathComponent(path),
                    channelCount: 2,
                    frameCount: 4_800,
                    impulses: amplitude == 0 ? [:] : [impulseSample: amplitude]
                )
            }
            try writeAudioFile(
                to: directory.appendingPathComponent("waiting-score.caf"),
                channelCount: 2,
                frameCount: 4_800,
                impulses: waitingAmplitude == 0
                    ? [:]
                    : [
                        600: waitingAmplitude,
                        1_028: waitingAmplitude,
                        1_029: waitingAmplitude,
                        1_040: waitingAmplitude,
                    ]
            )
            try writeAudioFile(
                to: directory.appendingPathComponent("work.caf"),
                channelCount: 2,
                frameCount: 4_800
            )
            let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
            let transport = NativeTimelineTransport()
            try transport.enableManualRenderingForTesting()
            try transport.prepareResponsiveAudio(
                plan: causalTransportPlan(
                    timeline: waiting,
                    phase: .waiting,
                    completedStageCount: 0,
                    workGain: 0,
                    cursorSample: 0,
                    loopIteration: 0
                ),
                resolver: resolver
            )
            try transport.play()
            let preroll = try transport.renderOfflineSamplesForTesting(900)
            let oldPreboundaryPeak = preroll[0].map { abs($0) }.max() ?? 0
            _ = try transport.transitionResponsiveAudio(
                to: causalTransportPlan(
                    timeline: engaged,
                    phase: .engaged,
                    completedStageCount: 0,
                    workGain: 0,
                    cursorSample: 900,
                    loopIteration: 0
                ),
                resolver: resolver
            )
            _ = try transport.renderOfflineSamplesForTesting(128)
            let result = try transport.renderOfflineSamplesForTesting(128)
            transport.stop()
            return (result, oldPreboundaryPeak)
        }

        let audibleOldToNew = try renderHandoff(
            name: "audible-old-new",
            waitingAmplitude: 0.50,
            engagedAmplitude: 0.50,
            materialAmplitude: 0.25
        )
        let silentOldToNew = try renderHandoff(
            name: "silent-old-new",
            waitingAmplitude: 0,
            engagedAmplitude: 0.50,
            materialAmplitude: 0.25
        )
        let materialOnly = try renderHandoff(
            name: "material-only",
            waitingAmplitude: 0,
            engagedAmplitude: 0,
            materialAmplitude: 0.25
        )

        XCTAssertGreaterThan(audibleOldToNew.oldPreboundaryPeak, 0.1)
        let leakage = zip(
            audibleOldToNew.output[0],
            silentOldToNew.output[0]
        )
            .enumerated()
            .compactMap { index, pair in
                abs(pair.0 - pair.1) > 0.000_01 ? index : nil
            }
        XCTAssertTrue(leakage.isEmpty)

        XCTAssertEqual(audibleOldToNew.output.count, silentOldToNew.output.count)
        for channel in audibleOldToNew.output.indices {
            XCTAssertEqual(
                audibleOldToNew.output[channel].count,
                silentOldToNew.output[channel].count
            )
            for sample in audibleOldToNew.output[channel].indices {
                XCTAssertEqual(
                    audibleOldToNew.output[channel][sample],
                    silentOldToNew.output[channel][sample],
                    accuracy: 0.000_01,
                    "the old phase leaked past boundary at channel \(channel), sample \(sample)"
                )
            }
            let newScore = zip(
                silentOldToNew.output[channel],
                materialOnly.output[channel]
            ).map { abs($0 - $1) }
            let material = materialOnly.output[channel].map { abs($0) }
            let scorePeak = try XCTUnwrap(
                newScore.indices.max { newScore[$0] < newScore[$1] }
            )
            let materialPeak = try XCTUnwrap(
                material.indices.max { material[$0] < material[$1] }
            )
            XCTAssertGreaterThan(newScore[scorePeak], 0.1)
            XCTAssertGreaterThan(material[materialPeak], 0.1)
            XCTAssertEqual(materialPeak - scorePeak, 40)
        }
    }

    @MainActor
    func testSevenLayerStageTransitionUsesNoIOAndOneExplicitRampBoundary() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layerIDs = (0 ..< 7).map {
            ResponsiveAudioMaterialLayerID("material-\($0 + 1)")
        }
        let paths = layerIDs.map { "\($0.rawValue).caf" }
        try writeAudioFile(
            to: directory.appendingPathComponent("stage-score.caf"),
            channelCount: 2,
            frameCount: 48_000
        )
        for path in paths {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 48_000,
                constantAmplitude: 0.01
            )
        }
        let timeline = AudioTimeline(
            id: "seven-layer-stage-bed",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "stage-score",
                    role: .score,
                    startSample: 0,
                    durationSamples: 48_000,
                    assetPath: "stage-score.caf",
                    gain: 0.5
                ),
            ] + zip(layerIDs, paths).map { layerID, path in
                AudioEvent(
                    cueID: AudioCueID("waiting-\(layerID.rawValue)"),
                    role: .soundscape,
                    startSample: 0,
                    durationSamples: 48_000,
                    assetPath: path,
                    gain: 0.1
                )
            },
            haptics: []
        )
        func plan(gainOffset: Double) -> ResponsiveAudioTimelineTransportPlan {
            ResponsiveAudioTimelineTransportPlan(
                timeline: timeline,
                cursorSample: 0,
                loopIteration: 0,
                repetition: .loop(iteration: 0, durationSamples: 48_000),
                causalMix: ResponsiveAudioCausalMixPlaybackPlan(
                    completedStageCount: gainOffset == 0 ? 0 : 1,
                    rampDurationSamples: 9_600,
                    layers: zip(layerIDs, paths).enumerated().map {
                        index, pair in
                        ResponsiveAudioCausalLayerPlaybackTarget(
                            layerID: pair.0,
                            cueID: AudioCueID("waiting-\(pair.0.rawValue)"),
                            role: .soundscape,
                            assetPath: pair.1,
                            startSample: 0,
                            durationSamples: 48_000,
                            targetGain: 0.1 + gainOffset + Double(index) * 0.01
                        )
                    }
                )
            )
        }

        let resolver = CountingAudioResolver(root: directory)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(plan: plan(gainOffset: 0), resolver: resolver)
        try transport.play()
        XCTAssertTrue(
            try transport.activeAudioCursorBinding().gateToken.authorizeAudio(
                throughRenderedGraphSample: 20_000
            )
        )
        let preroll = try transport.renderOfflineSamplesForTesting(2_048)
        let prerollChannel = try XCTUnwrap(preroll.first)
        let stableInitialAmplitude = prerollChannel
            .suffix(128)
            .map { abs($0) }
            .reduce(0, +) / 128
        resolver.callCount = 0
        resolver.failingPaths = Set(["stage-score.caf"] + paths)

        _ = try transport.transitionResponsiveAudio(
            to: plan(gainOffset: 0.2),
            resolver: resolver
        )
        let transitionLead = try transport.renderOfflineSamplesForTesting(128)
        let transitionLeadChannel = try XCTUnwrap(transitionLead.first)
        let transitionLeadAmplitude = transitionLeadChannel
            .map { abs($0) }
            .reduce(0, +) / Float(transitionLeadChannel.count)
        let rampOutput = try transport.renderOfflineSamplesForTesting(10_112)
        let rampChannel = try XCTUnwrap(rampOutput.first)
        func meanAmplitude(_ range: Range<Int>) -> Float {
            rampChannel[range]
                .map { abs($0) }
                .reduce(0, +) / Float(range.count)
        }
        let earlyAmplitude = meanAmplitude(0 ..< 128)
        let midpointAmplitude = meanAmplitude(4_736 ..< 4_864)
        let lateAmplitude = meanAmplitude(9_472 ..< 9_600)
        let stableFinalAmplitude = meanAmplitude(9_984 ..< 10_112)

        XCTAssertEqual(resolver.callCount, 0)
        let boundary = try XCTUnwrap(transport.transitionBoundaryForTesting)
        XCTAssertNotEqual(boundary, AUEventSampleTimeImmediate)
        let starts = try layerIDs.map {
            try XCTUnwrap(transport.causalRampStartSampleForTesting($0))
        }
        XCTAssertEqual(
            transitionLeadAmplitude,
            stableInitialAmplitude,
            accuracy: 0.000_5
        )
        XCTAssertEqual(Set(starts), [boundary])
        for layerID in layerIDs {
            XCTAssertEqual(
                transport.causalRampDurationForTesting(layerID),
                9_600
            )
            XCTAssertEqual(
                transport.causalRampScheduleCountForTesting(layerID),
                1
            )
        }
        XCTAssertEqual(earlyAmplitude, stableInitialAmplitude, accuracy: 0.000_5)
        XCTAssertGreaterThan(midpointAmplitude, earlyAmplitude)
        XCTAssertLessThan(midpointAmplitude, lateAmplitude)
        XCTAssertEqual(
            midpointAmplitude,
            (stableInitialAmplitude + stableFinalAmplitude) / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(lateAmplitude, stableFinalAmplitude, accuracy: 0.000_5)
        XCTAssertEqual(stableInitialAmplitude, 0.009_1, accuracy: 0.000_5)
        XCTAssertEqual(stableFinalAmplitude, 0.023_1, accuracy: 0.000_5)
        transport.stop()
    }

    @MainActor
    func testConsequenceHapticPreflightFailurePreservesInteractionAndRetrySucceeds() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in [
            "waiting-score.caf", "river.caf", "work.caf", "consequence.caf",
        ] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let waiting = causalTimeline(phase: .waiting)
        let consequence = AudioTimeline(
            id: "native-consequence",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "consequence-score",
                    role: .score,
                    startSample: 0,
                    durationSamples: 4_800,
                    assetPath: "consequence.caf",
                    gain: 0.5
                ),
            ],
            haptics: [
                HapticEvent(
                    sample: 100,
                    kind: .seal,
                    intensity: 0.7,
                    sharpness: 0.4
                ),
            ]
        )
        let consequencePlan = ResponsiveAudioTimelineTransportPlan(
            timeline: consequence,
            cursorSample: 0,
            loopIteration: 0,
            repetition: .once,
            causalMix: nil
        )
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: waiting,
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        try transport.play()
        _ = try transport.renderOfflineSamplesForTesting(128)
        let before = transport.snapshot()
        let riverIdentity = transport.commonPlayerIdentityForTesting("river")
        let scoreIdentity = transport.conventionalPlayerIdentityForTesting(
            "waiting-score"
        )
        transport.injectHapticPreparationFailureForTesting()

        XCTAssertThrowsError(
            try transport.transitionResponsiveAudio(
                to: consequencePlan,
                resolver: resolver
            )
        )
        XCTAssertEqual(transport.snapshot(), before)
        XCTAssertEqual(transport.commonPlayerIdentityForTesting("river"), riverIdentity)
        XCTAssertEqual(
            transport.conventionalPlayerIdentityForTesting("waiting-score"),
            scoreIdentity
        )
        XCTAssertEqual(transport.state, .playing)

        transport.injectHapticStartFailureForTesting()
        XCTAssertThrowsError(
            try transport.transitionResponsiveAudio(
                to: consequencePlan,
                resolver: resolver
            )
        )
        XCTAssertEqual(transport.snapshot(), before)
        XCTAssertEqual(transport.commonPlayerIdentityForTesting("river"), riverIdentity)
        XCTAssertEqual(
            transport.conventionalPlayerIdentityForTesting("waiting-score"),
            scoreIdentity
        )
        XCTAssertEqual(transport.state, .playing)

        let transitioned = try transport.transitionResponsiveAudio(
            to: consequencePlan,
            resolver: resolver
        )
        XCTAssertEqual(transitioned.timelineID, consequence.id)
        XCTAssertEqual(transitioned.cursorSample, 0)
        XCTAssertTrue(transitioned.isPlaying)
        XCTAssertNil(transport.commonPlayerIdentityForTesting("river"))
        _ = try transport.renderOfflineSamplesForTesting(192)
        XCTAssertEqual(transport.snapshot().cursorSample, 64)
        transport.stop()
    }

    @MainActor
    func testCausalCommonPlayersAndPhaseScoreRemainContinuousAcrossLoopAndTransition() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in [
            "waiting-score.caf", "engaged-score.caf", "river.caf", "work.caf",
        ] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let waiting = causalTimeline(phase: .waiting)
        let engaged = causalTimeline(phase: .engaged)
        let transport = NativeTimelineTransport()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: waiting,
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: resolver
        )
        XCTAssertNil(transport.commonPlayerIdentityForTesting("river"))
        XCTAssertNil(transport.commonPlayerIdentityForTesting("work"))
        XCTAssertNil(
            transport.conventionalLoopBufferCountForTesting("waiting-score")
        )

        // This is a release gate rather than a conditional skip: if the local
        // simulator cannot run the actual AVAudioEngine loop, the causal-mix
        // program remains failed rather than claiming continuity.
        try transport.play()
        let riverIdentity = try XCTUnwrap(
            transport.commonPlayerIdentityForTesting("river")
        )
        let workIdentity = try XCTUnwrap(
            transport.commonPlayerIdentityForTesting("work")
        )
        XCTAssertEqual(transport.commonPlayerScheduleCountForTesting("river"), 1)
        XCTAssertEqual(
            transport.conventionalLoopBufferCountForTesting("waiting-score"),
            1
        )
        usleep(420_000)
        let beyondTwoLoops = transport.snapshot()
        XCTAssertGreaterThanOrEqual(beyondTwoLoops.loopIteration, 2)
        XCTAssertEqual(
            transport.commonPlayerIsPlayingForTesting("river"),
            true
        )
        XCTAssertEqual(
            transport.conventionalPlayerIsPlayingForTesting("waiting-score"),
            true
        )

        let waitingScoreIdentity = try XCTUnwrap(
            transport.conventionalPlayerIdentityForTesting("waiting-score")
        )
        let transitioned = try transport.transitionResponsiveAudio(
            to: causalTransportPlan(
                timeline: engaged,
                phase: .engaged,
                completedStageCount: 1,
                workGain: 0.35,
                cursorSample: beyondTwoLoops.cursorSample,
                loopIteration: beyondTwoLoops.loopIteration
            ),
            resolver: resolver
        )
        XCTAssertGreaterThanOrEqual(
            transitioned.loopIteration,
            beyondTwoLoops.loopIteration
        )
        XCTAssertEqual(
            transport.commonPlayerIdentityForTesting("river"),
            riverIdentity
        )
        XCTAssertEqual(
            transport.commonPlayerIdentityForTesting("work"),
            workIdentity
        )
        XCTAssertEqual(transport.commonPlayerScheduleCountForTesting("river"), 1)
        XCTAssertEqual(transport.causalTargetGainForTesting("work"), 0.35)
        XCTAssertEqual(transport.causalRampDurationForTesting("work"), 480)
        XCTAssertEqual(transport.causalRampScheduleCountForTesting("work"), 1)
        XCTAssertNotEqual(
            transport.conventionalPlayerIdentityForTesting("engaged-score"),
            waitingScoreIdentity
        )
        XCTAssertEqual(
            transport.conventionalLoopBufferCountForTesting("engaged-score"),
            2
        )
        XCTAssertEqual(
            transport.conventionalPlayerIsPlayingForTesting("engaged-score"),
            true
        )
        transport.stop()

        let restored = NativeTimelineTransport()
        try restored.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: engaged,
                phase: .engaged,
                completedStageCount: 2,
                workGain: 0.55,
                cursorSample: 2_000,
                loopIteration: 5
            ),
            resolver: resolver
        )
        XCTAssertEqual(
            restored.snapshot(),
            NativeTimelineTransportSnapshot(
                timelineID: engaged.id,
                cursorSample: 2_000,
                loopIteration: 5,
                isPlaying: false
            )
        )
        XCTAssertNil(restored.causalTargetGainForTesting("work"))
        XCTAssertNil(restored.commonPlayerScheduleCountForTesting("river"))
        try restored.play()
        XCTAssertEqual(restored.causalTargetGainForTesting("work"), 0.55)
        XCTAssertEqual(restored.commonPlayerScheduleCountForTesting("river"), 2)
        XCTAssertEqual(
            restored.conventionalLoopBufferCountForTesting("engaged-score"),
            2
        )
        restored.stop()
    }

    @MainActor
    func testSemanticHapticPreferenceCanChangeWithoutPlayingHistoricalAction() {
        let off = ExperiencePreferences(hapticsEnabled: false)
        let transport = NativeSemanticHapticTransport(preferences: off)

        XCTAssertFalse(transport.routingPolicy.semanticHapticsAreEnabled)
        transport.play(.seal)
        XCTAssertFalse(transport.routingPolicy.semanticHapticsAreEnabled)

        transport.applyPreferences(.standard)
        XCTAssertTrue(transport.routingPolicy.semanticHapticsAreEnabled)
        transport.applyPreferences(off)
        XCTAssertFalse(transport.routingPolicy.semanticHapticsAreEnabled)
    }

    private func makeStandaloneGainNode(
        channelCount: AVAudioChannelCount,
        initialGain: AUValue
    ) throws -> SampleAccurateGainNode {
        let gainNode = try SampleAccurateGainNode.make(initialGain: initialGain)
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: channelCount,
            interleaved: false
        ))
        try gainNode.audioUnit.inputBusses[0].setFormat(format)
        try gainNode.audioUnit.outputBusses[0].setFormat(format)
        try gainNode.audioUnit.allocateRenderResources()
        return gainNode
    }

    private func makeRenderBuffer(
        channelCount: AVAudioChannelCount,
        frameCapacity: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: channelCount,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        ))
        buffer.frameLength = frameCapacity
        return buffer
    }

    private func fillingPullInput(value: Float) -> AURenderPullInputBlock {
        { _, _, frameCount, _, outputData in
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            for index in buffers.indices {
                guard let data = buffers[index].mData else {
                    return kAudioUnitErr_InvalidPropertyValue
                }
                data.assumingMemoryBound(to: Float.self).initialize(
                    repeating: value,
                    count: Int(frameCount)
                )
                buffers[index].mDataByteSize = frameCount
                    * UInt32(MemoryLayout<Float>.size)
            }
            return noErr
        }
    }

    private func fillRenderBuffer(
        _ buffer: AVAudioPCMBuffer,
        value: Float
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            buffer.mutableAudioBufferList
        )
        for index in buffers.indices {
            if let data = buffers[index].mData {
                data.assumingMemoryBound(to: Float.self).initialize(
                    repeating: value,
                    count: Int(buffer.frameLength)
                )
            }
            buffers[index].mDataByteSize = buffer.frameLength
                * UInt32(MemoryLayout<Float>.size)
        }
    }

    private func assertRenderBufferIsSilent(
        _ buffer: AVAudioPCMBuffer,
        frameCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let channels = buffer.floatChannelData else {
            XCTFail("missing float channels", file: file, line: line)
            return
        }
        for channel in 0 ..< Int(buffer.format.channelCount) {
            for frame in 0 ..< frameCount {
                XCTAssertEqual(
                    channels[channel][frame],
                    0,
                    accuracy: 0,
                    file: file,
                    line: line
                )
            }
        }
    }

    private func makeRenderEvent(
        type: AURenderEventType,
        duration: AUAudioFrameCount,
        address: AUParameterAddress,
        value: AUValue,
        sample: AUEventSampleTime = 0
    ) -> UnsafeMutablePointer<AURenderEvent> {
        let event = UnsafeMutablePointer<AURenderEvent>.allocate(capacity: 1)
        event.initialize(to: AURenderEvent())
        event.pointee.parameter.next = nil
        event.pointee.parameter.eventSampleTime = sample
        event.pointee.parameter.eventType = type
        event.pointee.parameter.rampDurationSampleFrames = duration
        event.pointee.parameter.parameterAddress = address
        event.pointee.parameter.value = value
        return event
    }

    private func invokeGainRender(
        _ audioUnit: SampleAccurateGainAudioUnit,
        buffer: AVAudioPCMBuffer,
        frameCount: AUAudioFrameCount,
        timestamp suppliedTimestamp: AudioTimeStamp? = nil,
        event: UnsafePointer<AURenderEvent>? = nil,
        pullInputBlock: AURenderPullInputBlock?
    ) -> (status: OSStatus, flags: AudioUnitRenderActionFlags) {
        var timestamp = suppliedTimestamp ?? AudioTimeStamp()
        if suppliedTimestamp == nil {
            timestamp.mSampleTime = 0
            timestamp.mFlags = .sampleTimeValid
        }
        var flags: AudioUnitRenderActionFlags = []
        let status = withUnsafeMutablePointer(to: &flags) { flagsPointer in
            withUnsafePointer(to: &timestamp) { timestampPointer in
                audioUnit.internalRenderBlock(
                    flagsPointer,
                    timestampPointer,
                    frameCount,
                    0,
                    buffer.mutableAudioBufferList,
                    event,
                    pullInputBlock
                )
            }
        }
        return (status, flags)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "native-audio-preferences-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeAudioAssets(to directory: URL) throws {
        try writeAudioFile(
            to: directory.appendingPathComponent("narration.caf"),
            channelCount: 1
        )
        try writeAudioFile(
            to: directory.appendingPathComponent("score.caf"),
            channelCount: 2
        )
        try writeAudioFile(
            to: directory.appendingPathComponent("soundscape.caf"),
            channelCount: 2
        )
        try writeAudioFile(
            to: directory.appendingPathComponent("detail.caf"),
            channelCount: 1
        )
    }

    private func writeAudioFile(
        to url: URL,
        channelCount: AVAudioChannelCount,
        frameCount: AVAudioFrameCount = 24_000,
        impulses: [Int: Float] = [:],
        constantAmplitude: Float = 0
    ) throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: channelCount,
            interleaved: false
        ))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount
        if let channels = buffer.floatChannelData {
            for channel in 0 ..< Int(channelCount) {
                channels[channel].initialize(
                    repeating: constantAmplitude,
                    count: Int(frameCount)
                )
                for (sample, amplitude) in impulses
                    where sample >= 0 && sample < Int(frameCount) {
                    channels[channel][sample] = amplitude
                }
            }
        }
        try file.write(from: buffer)
    }

    @MainActor
    private func assertActiveGraphUnchanged(
        _ transport: NativeTimelineTransport,
        snapshot: NativeTimelineTransportSnapshot,
        riverIdentity: ObjectIdentifier?,
        workIdentity: ObjectIdentifier?,
        scoreIdentity: ObjectIdentifier?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(transport.snapshot(), snapshot, file: file, line: line)
        XCTAssertEqual(
            transport.commonPlayerIdentityForTesting("river"),
            riverIdentity,
            file: file,
            line: line
        )
        XCTAssertEqual(
            transport.commonPlayerIdentityForTesting("work"),
            workIdentity,
            file: file,
            line: line
        )
        XCTAssertEqual(
            transport.conventionalPlayerIdentityForTesting("waiting-score"),
            scoreIdentity,
            file: file,
            line: line
        )
        XCTAssertEqual(
            transport.causalTargetGainForTesting("work"),
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(transport.state, .playing, file: file, line: line)
        XCTAssertEqual(
            transport.conventionalPlayerIsPlayingForTesting("waiting-score"),
            true,
            file: file,
            line: line
        )
    }

    @MainActor
    func testPauseQuiescesRenderThreadBeforeReadingFinalCursor() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["waiting-score.caf", "river.caf", "work.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: causalTimeline(phase: .waiting),
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        try transport.play()
        transport.setRenderedSampleOffsetOverrideForTesting(64)
        var barrierWasReached = false
        transport.setPauseQuiescenceHookForTesting {
            XCTAssertFalse(transport.engineIsRunningForTesting)
            barrierWasReached = true
            // Deterministically models the last in-flight render quantum
            // publishing only after engine.stop() has joined the render thread.
            transport.setRenderedSampleOffsetOverrideForTesting(192)
        }

        let paused = try transport.pause()

        XCTAssertTrue(barrierWasReached)
        XCTAssertEqual(paused.cursorSample, 192)
        XCTAssertEqual(paused.loopIteration, 0)
        XCTAssertFalse(paused.isPlaying)
        transport.setPauseQuiescenceHookForTesting(nil)
        transport.setRenderedSampleOffsetOverrideForTesting(nil)
        transport.stop()
    }

    func testRenderClockPublishesOneCoherent48kHostAnchorAcross441RouteDomain() {
        let storage = NativeRenderClockStorage()
        let sourceStart = mach_absolute_time()
        let sourceFrameCount: Int64 = 480
        let sourceRate = 48_000.0
        let outputFrameCount: Int64 = 441
        let outputRate = 44_100.0
        XCTAssertEqual(
            Double(sourceFrameCount) / sourceRate,
            Double(outputFrameCount) / outputRate,
            accuracy: 0.000_000_1
        )
        let hostEnd = sourceStart + AVAudioTime.hostTime(
            forSeconds: Double(sourceFrameCount) / sourceRate
        )

        storage.record(
            sourceFrameCount,
            hostTimeAtGraphSampleEnd: hostEnd
        )

        XCTAssertEqual(
            storage.loadCoherentAnchor(),
            NativeRenderClockAnchor(
                graphSampleEnd: 480,
                hostTimeAtGraphSampleEnd: hostEnd
            )
        )
    }

    func testRenderClockStalledWriterFailsClosedWithoutSpinning() {
        let storage = NativeRenderClockStorage()
        storage.record(128, hostTimeAtGraphSampleEnd: 456)
        storage.stallPublicationForTesting()

        XCTAssertNil(storage.loadCoherentAnchor(maximumAttempts: 4))
    }

    func testOutgoingTailRequiresAClockSampleStrictlyBeyondFadeEnd() {
        var gate = NativeOutgoingTailCompletionGate(
            fadeEndGraphSample: 608,
            stallBudgetNanoseconds: 1_000,
            initialGraphSampleEnd: 128,
            initialMonotonicNanoseconds: 10
        )

        XCTAssertEqual(
            gate.observe(
                ResponsiveAudioOutgoingTailRenderObservation(
                    graphSampleEnd: 608,
                    engineIsRunning: true
                ),
                monotonicNanoseconds: 20
            ),
            .pending
        )
        XCTAssertEqual(
            gate.observe(
                ResponsiveAudioOutgoingTailRenderObservation(
                    graphSampleEnd: 609,
                    engineIsRunning: true
                ),
                monotonicNanoseconds: 21
            ),
            .finish(.renderClockConfirmed)
        )
    }

    func testOutgoingTailGateDistinguishesStoppedAndStalledRenderClocks() {
        var stopped = NativeOutgoingTailCompletionGate(
            fadeEndGraphSample: 608,
            stallBudgetNanoseconds: 1_000,
            initialGraphSampleEnd: 128,
            initialMonotonicNanoseconds: 10
        )
        XCTAssertEqual(
            stopped.observe(
                ResponsiveAudioOutgoingTailRenderObservation(
                    graphSampleEnd: 256,
                    engineIsRunning: false
                ),
                monotonicNanoseconds: 20
            ),
            .finish(.renderClockStopped)
        )

        var stalled = NativeOutgoingTailCompletionGate(
            fadeEndGraphSample: 608,
            stallBudgetNanoseconds: 1_000,
            initialGraphSampleEnd: 128,
            initialMonotonicNanoseconds: 10
        )
        XCTAssertEqual(
            stalled.observe(
                ResponsiveAudioOutgoingTailRenderObservation(
                    graphSampleEnd: 256,
                    engineIsRunning: true
                ),
                monotonicNanoseconds: 999
            ),
            .pending
        )
        XCTAssertEqual(
            stalled.observe(
                ResponsiveAudioOutgoingTailRenderObservation(
                    graphSampleEnd: 256,
                    engineIsRunning: true
                ),
                monotonicNanoseconds: 1_998
            ),
            .pending
        )
        XCTAssertEqual(
            stalled.observe(
                ResponsiveAudioOutgoingTailRenderObservation(
                    graphSampleEnd: 256,
                    engineIsRunning: true
                ),
                monotonicNanoseconds: 1_999
            ),
            .finish(.renderClockStalled)
        )
    }

    func testHapticRecoveryKeepsOnlyConservativelyFuturePulses() throws {
        let haptics = [
            ScheduledHaptic(
                timelineStartOffset: 599,
                semantic: .contact,
                intensity: 0.4,
                sharpness: 0.2
            ),
            ScheduledHaptic(
                timelineStartOffset: 700,
                semantic: .drag,
                intensity: 0.5,
                sharpness: 0.3
            ),
            ScheduledHaptic(
                timelineStartOffset: 799,
                semantic: .seal,
                intensity: 0.8,
                sharpness: 0.7
            ),
            ScheduledHaptic(
                timelineStartOffset: 800,
                semantic: .break,
                intensity: 1,
                sharpness: 1
            ),
        ]
        let pulses = [
            NativeTimelineHapticPulseSchedule(
                haptic: haptics[0],
                absoluteGraphSample: 1_599,
                scheduledHostTime: 3_000
            ),
            NativeTimelineHapticPulseSchedule(
                haptic: haptics[1],
                absoluteGraphSample: 1_700,
                scheduledHostTime: 1_000
            ),
            NativeTimelineHapticPulseSchedule(
                haptic: haptics[2],
                absoluteGraphSample: 1_799,
                scheduledHostTime: 3_000
            ),
            NativeTimelineHapticPulseSchedule(
                haptic: haptics[3],
                absoluteGraphSample: 1_800,
                scheduledHostTime: 3_000
            ),
        ]
        let plan = try XCTUnwrap(
            NativeTimelineHapticRecoveryPlanner.makeRecoveryPlan(
                pulseSchedule: pulses,
                anchor: NativeRenderClockAnchor(
                    graphSampleEnd: 1_500,
                    hostTimeAtGraphSampleEnd: 500
                ),
                observedHostTime: 1_000,
                sampleRate: 48_000,
                scheduledStopBoundary: NativeTimelineHapticBoundary(
                    graphSample: 1_800,
                    hostTime: nil,
                    sampleRate: 48_000
                ),
                minimumLeadSamples: 100
            )
        )

        XCTAssertEqual(plan.boundary.graphSample, 1_600)
        XCTAssertEqual(plan.haptics, [
            ScheduledHaptic(
                timelineStartOffset: 199,
                semantic: .seal,
                intensity: 0.8,
                sharpness: 0.7
            ),
        ])
        XCTAssertEqual(plan.pulseSchedule.map(\.absoluteGraphSample), [1_799])
        XCTAssertGreaterThan(
            try XCTUnwrap(plan.pulseSchedule.first?.scheduledHostTime),
            try XCTUnwrap(plan.boundary.hostTime)
        )
    }

    func testInitialHapticScheduleMapsEveryPulseIntoGraphAndHostTime() throws {
        let boundary = NativeTimelineHapticBoundary(
            graphSample: 2_000,
            hostTime: 10_000,
            sampleRate: 48_000
        )
        let haptic = ScheduledHaptic(
            timelineStartOffset: 480,
            semantic: .resistance,
            intensity: 0.7,
            sharpness: 0.4
        )
        let schedule = try NativeTimelineHapticRecoveryPlanner
            .initialPulseSchedule(haptics: [haptic], boundary: boundary)

        XCTAssertEqual(schedule.map(\.absoluteGraphSample), [2_480])
        XCTAssertEqual(
            schedule.first?.scheduledHostTime,
            10_000 + AVAudioTime.hostTime(forSeconds: 0.01)
        )
    }

    func testHapticCallbackFenceRejectsResetAndStoppedCallbacksAfterInvalidation() {
        let fence = NativeTimelineHapticCallbackFence()
        let reset = fence.issue()
        XCTAssertTrue(fence.isCurrent(reset))

        let stopped = fence.issue()
        XCTAssertFalse(fence.isCurrent(reset))
        XCTAssertTrue(fence.isCurrent(stopped))

        fence.invalidate()
        XCTAssertFalse(fence.isCurrent(stopped))
    }

    @MainActor
    func testHapticOwnershipStopsOldAndStartsCandidateAtOneGraphBoundary() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["a.caf", "b.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let scheduler = RecordingTimelineHapticScheduler()
        let transport = NativeTimelineTransport(hapticScheduler: scheduler)
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: oneShotTransportPlan(
                timeline: oneShotTimeline(id: "haptic-a", path: "a.caf")
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        try transport.play()
        _ = try transport.renderOfflineSamplesForTesting(64)

        scheduler.failNextScheduledStop = true
        XCTAssertThrowsError(
            try transport.transitionResponsiveAudio(
                to: oneShotTransportPlan(
                    timeline: oneShotTimeline(id: "haptic-b", path: "b.caf")
                ),
                resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
            )
        )
        XCTAssertEqual(transport.pendingPhysicalTransitionCountForTesting, 0)
        XCTAssertTrue(scheduler.events.contains(.stoppedImmediately(2)))

        _ = try transport.transitionResponsiveAudio(
            to: oneShotTransportPlan(
                timeline: oneShotTimeline(id: "haptic-b", path: "b.caf")
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        let boundary = NativeTimelineHapticBoundary(
            graphSample: 192,
            hostTime: nil,
            sampleRate: 48_000
        )
        XCTAssertTrue(scheduler.events.contains(.started(3, boundary, true)))
        XCTAssertTrue(scheduler.events.contains(.scheduledStop(1, boundary)))

        // No snapshot or other transport API is needed for the physical
        // haptic ownership change to be scheduled at the audio boundary.
        _ = try transport.renderOfflineSamplesForTesting(128)
        transport.stop()
    }

    @MainActor
    func testPendingHapticReceivesPreferencesAndFailureIsolatesOnlyCandidate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["a.caf", "b.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let scheduler = RecordingTimelineHapticScheduler()
        let transport = NativeTimelineTransport(hapticScheduler: scheduler)
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: oneShotTransportPlan(
                timeline: oneShotTimeline(id: "preference-a", path: "a.caf")
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        try transport.play()
        _ = try transport.transitionResponsiveAudio(
            to: oneShotTransportPlan(
                timeline: oneShotTimeline(id: "preference-b", path: "b.caf")
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        let off = ExperiencePreferences(hapticsEnabled: false)
        transport.applyPreferences(off)
        XCTAssertTrue(scheduler.events.contains(.enabled(1, false)))
        XCTAssertTrue(scheduler.events.contains(.enabled(2, false)))

        scheduler.failEnabledPlaybackIDs = [2]
        transport.applyPreferences(.standard)
        XCTAssertTrue(scheduler.events.contains(.enabled(1, true)))
        XCTAssertTrue(scheduler.events.contains(.stoppedImmediately(2)))
        XCTAssertTrue(transport.hapticsAreAvailable)

        _ = try transport.renderOfflineSamplesForTesting(128)
        _ = transport.snapshot()
        XCTAssertFalse(transport.hapticsAreAvailable)
        transport.stop()
    }

    @MainActor
    func testColdPlayAndRouteResumeBuildOnlyAgainstActivatedActualRoute() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["waiting-score.caf", "river.caf", "work.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800
            )
        }
        let leaser = RecordingAudioSessionLeaser(scriptedFormats: [
            NativeAudioRouteFormat(
                sessionSampleRate: 44_100,
                outputSampleRate: 44_100
            ),
            NativeAudioRouteFormat(
                sessionSampleRate: 48_000,
                outputSampleRate: 48_000
            ),
        ])
        let transport = NativeTimelineTransport(
            hapticScheduler: RecordingTimelineHapticScheduler(),
            audioSessionLeaser: leaser
        )
        try transport.prepareResponsiveAudio(
            plan: causalTransportPlan(
                timeline: causalTimeline(phase: .waiting),
                phase: .waiting,
                completedStageCount: 0,
                workGain: 0,
                cursorSample: 0,
                loopIteration: 0
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        XCTAssertNil(transport.graphRouteFormatAtLastRebuildForTesting)

        leaser.failNextAcquire = true
        XCTAssertThrowsError(try transport.play())
        XCTAssertEqual(transport.state, .prepared)
        XCTAssertEqual(transport.snapshot().cursorSample, 0)
        XCTAssertEqual(leaser.activeLeaseCount, 0)

        do {
            try transport.play()
        } catch {
            transport.stop()
            throw XCTSkip("Simulator audio engine unavailable: \(error)")
        }
        XCTAssertEqual(
            transport.graphRouteFormatAtLastRebuildForTesting?.outputSampleRate,
            44_100
        )
        usleep(80_000)
        let paused = try transport.pauseForRouteChange()
        XCTAssertEqual(leaser.activeLeaseCount, 0)
        XCTAssertEqual(leaser.finalDeactivationCount, 1)

        leaser.failNextAcquire = true
        XCTAssertThrowsError(try transport.resume())
        XCTAssertEqual(transport.state, .paused)
        XCTAssertEqual(transport.snapshot(), paused)
        XCTAssertEqual(leaser.activeLeaseCount, 0)

        try transport.resume()
        XCTAssertEqual(
            transport.graphRouteFormatAtLastRebuildForTesting?.outputSampleRate,
            48_000
        )
        transport.stop()
        XCTAssertEqual(leaser.activeLeaseCount, 0)
        XCTAssertEqual(leaser.finalDeactivationCount, 2)
    }

    @MainActor
    func testPostActivationRouteFormatFailureLeavesNoSessionOwner() throws {
        let session = RecordingSystemAudioSessionController(sampleRate: 48_000)
        let coordinator = SystemNativeAudioSessionLeaseCoordinator(
            sessionController: session,
            outputSampleRate: { _ in 0 }
        )

        XCTAssertThrowsError(
            try coordinator.acquire(
                preferredSampleRate: 48_000,
                engine: AVAudioEngine()
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeTimelineTransportError,
                .renderClockUnavailable
            )
        }
        XCTAssertEqual(session.configurationCount, 1)
        XCTAssertEqual(session.activationCount, 1)
        XCTAssertEqual(session.deactivationCount, 1)
        XCTAssertEqual(coordinator.leaseCountForTesting, 0)
    }

    @MainActor
    func testOverlappingSystemLeasesConfigureOnceAndDeactivateAfterFinalOwner() throws {
        let session = RecordingSystemAudioSessionController(sampleRate: 48_000)
        let coordinator = SystemNativeAudioSessionLeaseCoordinator(
            sessionController: session,
            outputSampleRate: { _ in 48_000 }
        )
        let first = try coordinator.acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        )
        let second = try coordinator.acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        )

        XCTAssertEqual(session.configurationCount, 1)
        XCTAssertEqual(session.activationCount, 1)
        XCTAssertEqual(session.deactivationCount, 0)
        XCTAssertEqual(coordinator.leaseCountForTesting, 2)

        first.release()
        XCTAssertEqual(coordinator.leaseCountForTesting, 1)
        XCTAssertEqual(session.deactivationCount, 0)

        second.release()
        XCTAssertEqual(coordinator.leaseCountForTesting, 0)
        XCTAssertEqual(session.deactivationCount, 1)
    }

    @MainActor
    func testOverlappingSystemLeaseRejectsIncompatibleRateWithoutReconfiguration() throws {
        let session = RecordingSystemAudioSessionController(sampleRate: 48_000)
        let coordinator = SystemNativeAudioSessionLeaseCoordinator(
            sessionController: session,
            outputSampleRate: { _ in 48_000 }
        )
        let owner = try coordinator.acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        )

        XCTAssertThrowsError(try coordinator.acquire(
            preferredSampleRate: 44_100,
            engine: AVAudioEngine()
        ))
        XCTAssertEqual(session.configurationCount, 1)
        XCTAssertEqual(session.activationCount, 1)
        XCTAssertEqual(session.deactivationCount, 0)
        XCTAssertEqual(coordinator.leaseCountForTesting, 1)

        owner.release()
        XCTAssertEqual(session.deactivationCount, 1)
    }

    @MainActor
    func testSystemLeaseRollsBackConfigurationAndActivationFailures() {
        let configurationFailure = RecordingSystemAudioSessionController(
            sampleRate: 48_000
        )
        configurationFailure.configurationFailuresRemaining = 1
        let configurationCoordinator = SystemNativeAudioSessionLeaseCoordinator(
            sessionController: configurationFailure,
            outputSampleRate: { _ in 48_000 }
        )

        XCTAssertThrowsError(try configurationCoordinator.acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        ))
        XCTAssertEqual(configurationFailure.events, [
            .configure(48_000),
            .deactivate,
        ])
        XCTAssertEqual(configurationCoordinator.leaseCountForTesting, 0)
        XCTAssertFalse(configurationCoordinator.cleanupIsRequiredForTesting)

        let activationFailure = RecordingSystemAudioSessionController(
            sampleRate: 48_000
        )
        activationFailure.activationFailuresRemaining = 1
        let activationCoordinator = SystemNativeAudioSessionLeaseCoordinator(
            sessionController: activationFailure,
            outputSampleRate: { _ in 48_000 }
        )

        XCTAssertThrowsError(try activationCoordinator.acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        ))
        XCTAssertEqual(activationFailure.events, [
            .configure(48_000),
            .activate,
            .deactivate,
        ])
        XCTAssertEqual(activationCoordinator.leaseCountForTesting, 0)
        XCTAssertFalse(activationCoordinator.cleanupIsRequiredForTesting)
    }

    @MainActor
    func testSystemLeaseBlocksReconfigurationUntilFailedRollbackIsClean() throws {
        let session = RecordingSystemAudioSessionController(sampleRate: 48_000)
        session.activationFailuresRemaining = 1
        session.deactivationFailuresRemaining = 2
        let coordinator = SystemNativeAudioSessionLeaseCoordinator(
            sessionController: session,
            outputSampleRate: { _ in 48_000 }
        )

        XCTAssertThrowsError(try coordinator.acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        ))
        XCTAssertTrue(coordinator.cleanupIsRequiredForTesting)
        XCTAssertEqual(session.configurationCount, 1)

        XCTAssertThrowsError(try coordinator.acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        ))
        XCTAssertTrue(coordinator.cleanupIsRequiredForTesting)
        XCTAssertEqual(session.configurationCount, 1)

        let recovered = try coordinator.acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        )
        XCTAssertFalse(coordinator.cleanupIsRequiredForTesting)
        XCTAssertEqual(session.configurationCount, 2)
        XCTAssertEqual(coordinator.leaseCountForTesting, 1)
        recovered.release()
        XCTAssertEqual(coordinator.leaseCountForTesting, 0)
    }

    @MainActor
    func testSystemLeaseReleaseIsIdempotentAndDeinitIsAReleaseFallback() throws {
        let session = RecordingSystemAudioSessionController(sampleRate: 48_000)
        let coordinator = SystemNativeAudioSessionLeaseCoordinator(
            sessionController: session,
            outputSampleRate: { _ in 48_000 }
        )
        var abandoned: (any NativeAudioSessionLease)? = try coordinator.acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        )
        XCTAssertEqual(abandoned?.routeFormat.outputSampleRate, 48_000)
        abandoned = nil
        XCTAssertEqual(coordinator.leaseCountForTesting, 0)
        XCTAssertEqual(session.deactivationCount, 1)

        let explicit = try coordinator.acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        )
        explicit.release()
        explicit.release()
        XCTAssertEqual(coordinator.leaseCountForTesting, 0)
        XCTAssertEqual(session.deactivationCount, 2)
    }

    @MainActor
    func testSystemLeaseKeepsCoordinatorAliveUntilRelease() throws {
        let session = RecordingSystemAudioSessionController(sampleRate: 48_000)
        var coordinator: SystemNativeAudioSessionLeaseCoordinator? =
            SystemNativeAudioSessionLeaseCoordinator(
                sessionController: session,
                outputSampleRate: { _ in 48_000 }
            )
        weak let retainedCoordinator = coordinator
        let lease = try XCTUnwrap(coordinator).acquire(
            preferredSampleRate: 48_000,
            engine: AVAudioEngine()
        )
        coordinator = nil

        XCTAssertNotNil(retainedCoordinator)
        lease.release()
        XCTAssertNil(retainedCoordinator)
        XCTAssertEqual(session.deactivationCount, 1)
    }

    @MainActor
    func testTransportDeinitReleasesItsActiveAudioSessionLease() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("deinit.caf"),
            channelCount: 2,
            frameCount: 4_800
        )
        let leaser = RecordingAudioSessionLeaser()
        var transport: NativeTimelineTransport? = NativeTimelineTransport(
            hapticScheduler: RecordingTimelineHapticScheduler(),
            audioSessionLeaser: leaser
        )
        try transport?.prepareResponsiveAudio(
            plan: oneShotTransportPlan(
                timeline: oneShotTimeline(
                    id: "transport-deinit",
                    path: "deinit.caf",
                    includesHaptic: false
                )
            ),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        do {
            try transport?.play()
        } catch {
            transport?.stop()
            throw XCTSkip("Simulator audio engine unavailable: \(error)")
        }
        XCTAssertEqual(leaser.activeLeaseCount, 1)

        transport = nil
        XCTAssertEqual(leaser.activeLeaseCount, 0)
        XCTAssertEqual(leaser.finalDeactivationCount, 1)
    }

    @MainActor
    func testBoundedOutgoingTailUsesAuthoredFadeAtCursorZeroMiddleAndNearEnd() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("tail.caf"),
            channelCount: 2,
            frameCount: 9_600,
            constantAmplitude: 0.2
        )
        let timeline = oneShotTimeline(
            id: "bounded-tail",
            path: "tail.caf",
            durationSamples: 9_600,
            includesHaptic: false
        )
        for cursor in [Int64(0), 2_400, 8_400] {
            let transport = NativeTimelineTransport()
            try transport.enableManualRenderingForTesting()
            try transport.prepareResponsiveAudio(
                plan: ResponsiveAudioTimelineTransportPlan(
                    timeline: timeline,
                    cursorSample: cursor,
                    loopIteration: 0,
                    repetition: .once,
                    causalMix: nil
                ),
                resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
            )
            try transport.play()
            let tail = try XCTUnwrap(
                transport.relinquishOutgoingAudio(
                    exitPolicy: .boundedFade(durationSamples: 480)
                )
            )
            XCTAssertEqual(tail.fadeBoundarySample, 128)
            XCTAssertEqual(tail.fadeDurationSamples, 480)
            XCTAssertEqual(
                transport.conventionalFadeForTesting("score")?.start,
                128
            )
            XCTAssertEqual(
                transport.conventionalFadeForTesting("score")?.duration,
                480
            )
            let output = try transport.renderOfflineSamplesForTesting(736)
            let channel = try XCTUnwrap(output.first)
            XCTAssertEqual(channel[120], 0.2, accuracy: 0.005)
            let audibleRampStart = try XCTUnwrap(
                channel.indices.dropFirst(128).first { channel[$0] < 0.199 }
            )
            XCTAssertGreaterThanOrEqual(audibleRampStart, 128)
            XCTAssertEqual(
                channel[audibleRampStart + 240],
                0.1,
                accuracy: 0.01
            )
            XCTAssertEqual(
                channel[audibleRampStart + 480],
                0,
                accuracy: 0.001
            )
            XCTAssertEqual(channel[700], 0, accuracy: 0.001)
            XCTAssertTrue(tail.isFinished)
            XCTAssertEqual(tail.finishReason, .renderClockConfirmed)
            XCTAssertFalse(transport.engineIsRunningForTesting)
        }
    }

    @MainActor
    func testOutgoingTailHapticFailureDoesNotExpandDurabilityAuthority()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("haptic-tail.caf"),
            channelCount: 2,
            frameCount: 48_000,
            constantAmplitude: 0.2
        )
        let scheduler = RecordingTimelineHapticScheduler()
        let transport = NativeTimelineTransport(hapticScheduler: scheduler)
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: oneShotTransportPlan(timeline: oneShotTimeline(
                id: "haptic-tail-failure",
                path: "haptic-tail.caf",
                durationSamples: 48_000,
                includesHaptic: true
            )),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        try transport.play()
        _ = try transport.renderOfflineSamplesForTesting(64)

        scheduler.failNextScheduledStop = true
        XCTAssertThrowsError(
            try transport.relinquishOutgoingAudio(
                exitPolicy: .boundedFade(durationSamples: 24_000)
            )
        ) { error in
            XCTAssertTrue(error is RecordingTimelineHapticScheduler.Failure)
        }
        XCTAssertEqual(transport.state, .playing)
        XCTAssertTrue(transport.engineIsRunningForTesting)
        XCTAssertNil(transport.conventionalFadeForTesting("score"))

        // The failed handoff must not inherit the requested 24k-sample tail.
        // Only the original 12k durability prefix remains audible.
        let permitted = try transport.renderOfflineSamplesForTesting(11_936)
        XCTAssertTrue(permitted.joined().contains { abs($0) > 0.01 })
        let denied = try transport.renderOfflineSamplesForTesting(4_096)
        XCTAssertTrue(denied.joined().allSatisfy { abs($0) < 0.000_001 })
        transport.stop()
    }

    @MainActor
    func testRelinquishPreparationFailureLeavesRunningGraphForCallerCleanup()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("injected-tail.caf"),
            channelCount: 2,
            frameCount: 48_000,
            constantAmplitude: 0.2
        )
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: oneShotTransportPlan(timeline: oneShotTimeline(
                id: "injected-tail-preparation",
                path: "injected-tail.caf",
                durationSamples: 48_000,
                includesHaptic: false
            )),
            resolver: PackageRootAudioAssetResolver(
                packageRootURL: directory
            )
        )
        try transport.play()
        let binding = try transport.activeAudioCursorBinding()
        transport.armRelinquishPreparationFaultForTesting {
            throw NativeTimelineTransportInjectedFailure.hapticPreparation
        }

        XCTAssertThrowsError(
            try transport.relinquishOutgoingAudio(
                exitPolicy: .boundedFade(durationSamples: 24_000)
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeTimelineTransportInjectedFailure,
                .hapticPreparation
            )
        }
        XCTAssertEqual(transport.state, .playing)
        XCTAssertTrue(transport.engineIsRunningForTesting)
        XCTAssertNil(transport.conventionalFadeForTesting("score"))

        transport.stop()
        XCTAssertEqual(transport.state, .idle)
        XCTAssertFalse(transport.engineIsRunningForTesting)
        XCTAssertFalse(binding.gateToken.authorizeAudio(
            throughRenderedGraphSample: 48_000
        ))
    }

    @MainActor
    func testOutgoingTailAuthorizationFailureStopsTransportFailClosed()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("closed-tail.caf"),
            channelCount: 2,
            frameCount: 48_000,
            constantAmplitude: 0.2
        )
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: oneShotTransportPlan(timeline: oneShotTimeline(
                id: "closed-tail-authorization",
                path: "closed-tail.caf",
                durationSamples: 48_000,
                includesHaptic: false
            )),
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory)
        )
        try transport.play()
        let binding = try transport.activeAudioCursorBinding()
        _ = try transport.renderOfflineSamplesForTesting(12_000)
        _ = try transport.renderOfflineSamplesForTesting(4_096)

        XCTAssertThrowsError(
            try transport.relinquishOutgoingAudio(
                exitPolicy: .boundedFade(durationSamples: 24_000)
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeTimelineTransportError,
                .renderClockUnavailable
            )
        }
        XCTAssertEqual(transport.state, .idle)
        XCTAssertFalse(transport.engineIsRunningForTesting)
        XCTAssertNil(transport.preparedPlanForTesting)
        XCTAssertFalse(binding.gateToken.claimCapture(
            atRenderedGraphSample: 16_096
        ))
        XCTAssertFalse(binding.gateToken.authorizeAudio(
            throughRenderedGraphSample: 48_000
        ))
        XCTAssertThrowsError(try transport.activeAudioCursorBinding())
    }

    func testAutomaticBoundaryMonitorUsesExactRenderedSampleAfterHostHint() {
        var pollState = NativeAutomaticBoundaryMonitorPollState()
        let boundary: Int64 = 1_000

        XCTAssertEqual(
            pollState.observe(
                renderedGraphSample: boundary - 1,
                boundaryGraphSample: boundary
            ),
            .sleep(nanoseconds: 2_000_000)
        )
        for _ in 0 ..< 24 {
            guard case .sleep = pollState.observe(
                renderedGraphSample: boundary - 1,
                boundaryGraphSample: boundary
            ) else {
                return XCTFail("A host-time hint promoted unrendered history")
            }
        }
        XCTAssertEqual(
            pollState.observe(
                renderedGraphSample: boundary,
                boundaryGraphSample: boundary
            ),
            .boundaryCrossed
        )
    }

    @MainActor
    func testAutomaticBoundaryMonitorRejectsPausedStoppedAndOldEpochOwnership()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("monitor-owner.caf"),
            channelCount: 2,
            frameCount: 4_800,
            constantAmplitude: 0.2
        )
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: oneShotTransportPlan(timeline: oneShotTimeline(
                id: "monitor-owner",
                path: "monitor-owner.caf",
                durationSamples: 4_800,
                includesHaptic: false
            )),
            resolver: resolver
        )
        var events: [ResponsiveAudioAutomaticBoundaryEvent] = []
        try transport.configureAutomaticBoundary(
            successorPlan: nil,
            resolver: resolver,
            handler: { events.append($0) }
        )
        try transport.play()
        let firstGeneration = transport.automaticBoundaryGenerationForTesting
        let firstEpoch = try transport.activeAudioCursorBinding()
            .gateToken.epoch
        let firstBoundary = try XCTUnwrap(
            transport.automaticCursorBoundaryForTesting
        )
        XCTAssertTrue(transport.automaticBoundaryMonitorOwnsForTesting(
            generation: firstGeneration,
            durabilityEpoch: firstEpoch,
            boundaryGraphSample: firstBoundary
        ))

        _ = try transport.pause()
        XCTAssertFalse(transport.automaticBoundaryMonitorOwnsForTesting(
            generation: firstGeneration,
            durabilityEpoch: firstEpoch,
            boundaryGraphSample: firstBoundary
        ))

        try transport.resume()
        let resumedGeneration = transport.automaticBoundaryGenerationForTesting
        let resumedEpoch = try transport.activeAudioCursorBinding()
            .gateToken.epoch
        let resumedBoundary = try XCTUnwrap(
            transport.automaticCursorBoundaryForTesting
        )
        XCTAssertFalse(transport.automaticBoundaryMonitorOwnsForTesting(
            generation: resumedGeneration,
            durabilityEpoch: firstEpoch,
            boundaryGraphSample: resumedBoundary
        ))
        XCTAssertTrue(transport.automaticBoundaryMonitorOwnsForTesting(
            generation: resumedGeneration,
            durabilityEpoch: resumedEpoch,
            boundaryGraphSample: resumedBoundary
        ))

        transport.stop()
        XCTAssertFalse(transport.automaticBoundaryMonitorOwnsForTesting(
            generation: resumedGeneration,
            durabilityEpoch: resumedEpoch,
            boundaryGraphSample: resumedBoundary
        ))
        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testStalledAutomaticBoundaryHasBoundedWakeupsAndFailsClosed()
        throws {
        var pollState = NativeAutomaticBoundaryMonitorPollState()
        var delays: [UInt64] = []
        var reachedStallLimit = false
        for _ in 0 ..< 100 {
            switch pollState.observe(
                renderedGraphSample: 100,
                boundaryGraphSample: 4_800
            ) {
            case let .sleep(nanoseconds):
                delays.append(nanoseconds)
            case .stallLimitReached:
                reachedStallLimit = true
            case .boundaryCrossed:
                XCTFail("A stalled render crossed the boundary")
            }
            if reachedStallLimit { break }
        }
        XCTAssertTrue(reachedStallLimit)
        XCTAssertLessThanOrEqual(delays.count, 48)
        XCTAssertEqual(
            delays.reduce(0, +),
            NativeAutomaticBoundaryMonitorPollState
                .maximumNoProgressNanoseconds
        )
        XCTAssertTrue(delays.prefix(
            NativeAutomaticBoundaryMonitorPollState.precisePollCount
        ).allSatisfy {
            $0 == NativeAutomaticBoundaryMonitorPollState
                .preciseIntervalNanoseconds
        })
        XCTAssertTrue(delays.allSatisfy {
            $0 <= NativeAutomaticBoundaryMonitorPollState
                .maximumIntervalNanoseconds
        })

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("monitor-stall.caf"),
            channelCount: 2,
            frameCount: 4_800,
            constantAmplitude: 0.2
        )
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: oneShotTransportPlan(timeline: oneShotTimeline(
                id: "monitor-stall",
                path: "monitor-stall.caf",
                durationSamples: 4_800,
                includesHaptic: false
            )),
            resolver: resolver
        )
        var events: [ResponsiveAudioAutomaticBoundaryEvent] = []
        try transport.configureAutomaticBoundary(
            successorPlan: nil,
            resolver: resolver,
            handler: { events.append($0) }
        )
        try transport.play()
        let binding = try transport.activeAudioCursorBinding()
        let generation = transport.automaticBoundaryGenerationForTesting
        let boundary = try XCTUnwrap(
            transport.automaticCursorBoundaryForTesting
        )

        transport.failClosedAutomaticBoundaryMonitorForTesting(
            generation: generation,
            durabilityEpoch: binding.gateToken.epoch,
            boundaryGraphSample: boundary
        )
        XCTAssertEqual(transport.state, .idle)
        XCTAssertFalse(transport.engineIsRunningForTesting)
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(binding.gateToken.authorizeAudio(
            throughRenderedGraphSample: 48_000
        ))
    }

    @MainActor
    func testAutomaticSixtySecondApproachStartsFifteenSecondWaitingAtItsOwnSampleZero() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("approach-tail.caf"),
            channelCount: 2,
            frameCount: 256,
            constantAmplitude: 0.25
        )
        try writeAudioFile(
            to: directory.appendingPathComponent("waiting-head.caf"),
            channelCount: 2,
            frameCount: 256,
            constantAmplitude: -0.75
        )
        let approachDuration: Int64 = 60 * 48_000
        let waitingDuration: Int64 = 15 * 48_000
        let approach = AudioTimeline(
            id: "shipping-approach",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "approach-tail",
                    role: .score,
                    startSample: approachDuration - 256,
                    durationSamples: 256,
                    assetPath: "approach-tail.caf",
                    gain: 1
                ),
            ],
            haptics: []
        )
        let waiting = AudioTimeline(
            id: "shipping-waiting",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "waiting-head",
                    role: .score,
                    startSample: 0,
                    durationSamples: 256,
                    assetPath: "waiting-head.caf",
                    gain: 1
                ),
                AudioEvent(
                    cueID: "waiting-silence",
                    role: .silence,
                    startSample: 256,
                    durationSamples: waitingDuration - 256,
                    assetPath: nil,
                    gain: 0
                ),
            ],
            haptics: []
        )
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: ResponsiveAudioTimelineTransportPlan(
                timeline: approach,
                cursorSample: approachDuration - 256,
                loopIteration: 0,
                repetition: .once,
                causalMix: nil
            ),
            resolver: resolver
        )
        var events: [ResponsiveAudioAutomaticBoundaryEvent] = []
        try transport.configureAutomaticBoundary(
            successorPlan: ResponsiveAudioTimelineTransportPlan(
                timeline: waiting,
                cursorSample: 0,
                loopIteration: 0,
                repetition: .loop(
                    iteration: 0,
                    durationSamples: waitingDuration
                ),
                causalMix: nil
            ),
            resolver: resolver,
            handler: { events.append($0) }
        )

        try transport.play()
        let stagedNodeCount = transport.stagedAutomaticNodeCountForTesting
        XCTAssertGreaterThan(stagedNodeCount, 0)
        let output = try transport.renderOfflineSamplesForTesting(512)

        let channel = try XCTUnwrap(output.first)
        let firstApproachSample = try XCTUnwrap(
            channel.indices.first { channel[$0] > 0.1 }
        )
        let firstWaitingSample = try XCTUnwrap(
            channel.indices.first { channel[$0] < -0.1 }
        )
        // AVAudioEngine may add the same fixed graph latency to both staged
        // branches. Their authored clocks must still meet with no added or
        // missing sample: waiting sample zero follows the 256-sample tail.
        XCTAssertEqual(firstWaitingSample - firstApproachSample, 256)
        XCTAssertLessThan(channel[firstWaitingSample + 16], -0.1)
        guard case let .successorStarted(boundarySnapshot) = try XCTUnwrap(
            events.first
        ) else {
            return XCTFail("Expected the physical waiting boundary")
        }
        XCTAssertEqual(boundarySnapshot.timelineID, waiting.id)
        XCTAssertEqual(boundarySnapshot.cursorSample, 0)
        XCTAssertEqual(boundarySnapshot.loopIteration, 0)
        XCTAssertTrue(boundarySnapshot.isPlaying)
        XCTAssertEqual(transport.snapshot().timelineID, waiting.id)
        XCTAssertEqual(transport.snapshot().cursorSample, 256)

        let attachedAfterBoundary = transport.attachedNodeCountForTesting
        transport.setRenderedSampleOffsetOverrideForTesting(30 * 60 * 48_000)
        let afterThirtyMinutes = transport.snapshot()
        XCTAssertEqual(afterThirtyMinutes.timelineID, waiting.id)
        XCTAssertEqual(transport.attachedNodeCountForTesting, attachedAfterBoundary)
        XCTAssertEqual(transport.stagedAutomaticNodeCountForTesting, 0)
        transport.setRenderedSampleOffsetOverrideForTesting(nil)
        transport.stop()
    }

    @MainActor
    func testAutomaticBoundaryGenerationRejectsPrePauseCallbackAndCheckpointCannotCross() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["approach.caf", "waiting.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800,
                constantAmplitude: 0.2
            )
        }
        let approach = oneShotTimeline(
            id: "generation-approach",
            path: "approach.caf",
            durationSamples: 4_800,
            includesHaptic: false
        )
        let waiting = AudioTimeline(
            id: "generation-waiting",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "waiting",
                    role: .score,
                    startSample: 0,
                    durationSamples: 4_800,
                    assetPath: "waiting.caf",
                    gain: 1
                ),
            ],
            haptics: []
        )
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let transport = NativeTimelineTransport()
        try transport.enableManualRenderingForTesting()
        try transport.prepareResponsiveAudio(
            plan: ResponsiveAudioTimelineTransportPlan(
                timeline: approach,
                cursorSample: 4_799,
                loopIteration: 0,
                repetition: .once,
                causalMix: nil
            ),
            resolver: resolver
        )
        var events: [ResponsiveAudioAutomaticBoundaryEvent] = []
        try transport.configureAutomaticBoundary(
            successorPlan: ResponsiveAudioTimelineTransportPlan(
                timeline: waiting,
                cursorSample: 0,
                loopIteration: 0,
                repetition: .loop(iteration: 0, durationSamples: 4_800),
                causalMix: nil
            ),
            resolver: resolver,
            handler: { events.append($0) }
        )
        try transport.play()
        let frozenGeneration = transport.automaticBoundaryGenerationForTesting
        transport.promoteAutomaticBoundaryForTesting(
            generation: frozenGeneration
        )
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(transport.snapshot().timelineID, approach.id)
        transport.setRenderedSampleOffsetOverrideForTesting(1)
        XCTAssertEqual(transport.snapshot().cursorSample, 4_799)
        transport.setRenderedSampleOffsetOverrideForTesting(nil)
        let staleGeneration = transport.automaticBoundaryGenerationForTesting
        _ = try transport.pause()
        try transport.resume()

        transport.promoteAutomaticBoundaryForTesting(
            generation: staleGeneration
        )
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(transport.snapshot().timelineID, approach.id)

        _ = try transport.renderOfflineSamplesForTesting(1)
        guard case let .successorStarted(snapshot) = try XCTUnwrap(events.first) else {
            return XCTFail("Expected the resumed generation to own the boundary")
        }
        XCTAssertEqual(snapshot.timelineID, waiting.id)
        XCTAssertEqual(snapshot.cursorSample, 0)
        transport.stop()
    }

    @MainActor
    func testDurabilitySnapshotPromotesCrossedBoundaryBeforeOldAuthorityCanVerify() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["approach.caf", "bed.caf"] {
            try writeAudioFile(
                to: directory.appendingPathComponent(path),
                channelCount: 2,
                frameCount: 4_800,
                constantAmplitude: 0.2
            )
        }

        let approach = oneShotTimeline(
            id: "snapshot-boundary-approach",
            path: "approach.caf",
            durationSamples: 4_800,
            includesHaptic: false
        )
        let interactionBeds = ResponsiveInteractionAudioPhase.allCases.map { phase in
            ResponsiveInteractionAudioBedSpec(
                phase: phase,
                timelineID: AudioTimelineID("snapshot-boundary-\(phase.rawValue)"),
                layerStates: ResponsiveAudioLayerStateSelection(
                    scoreStateID: "snapshot-boundary-\(phase.rawValue)-score",
                    soundscapeStateID: nil
                )
            )
        }
        let bedTimelines = interactionBeds.map { bed in
            AudioTimeline(
                id: bed.timelineID,
                sampleRate: 48_000,
                events: [
                    AudioEvent(
                        cueID: AudioCueID("\(bed.phase.rawValue)-bed"),
                        role: .score,
                        startSample: 0,
                        durationSamples: 4_800,
                        assetPath: "bed.caf",
                        gain: 1
                    ),
                ],
                haptics: []
            )
        }
        let consequence = oneShotTimeline(
            id: "snapshot-boundary-consequence",
            path: "approach.caf",
            durationSamples: 4_800,
            includesHaptic: false
        )
        let program = ResponsiveAudioProgramSpec(
            id: "snapshot-boundary-program",
            scope: ResponsiveAudioProgramScope(
                chapterID: "first-farmers",
                arcID: "fields-that-must-endure",
                beatID: "snapshot-boundary-beat",
                interactionID: "snapshot-boundary-interaction"
            ),
            approachTimelineID: approach.id,
            interactionBeds: interactionBeds,
            consequenceTimelineID: consequence.id,
            exitPolicy: .boundedFade(durationSamples: 480)
        )
        let transport = NativeTimelineTransport(
            hapticScheduler: RecordingTimelineHapticScheduler(),
            audioSessionLeaser: RecordingAudioSessionLeaser()
        )
        let controller = try ResponsiveAudioProgramController(
            program: program,
            timelines: [approach] + bedTimelines + [consequence],
            transport: transport,
            resolver: PackageRootAudioAssetResolver(packageRootURL: directory),
            restoring: ResponsiveAudioProgramSnapshot(
                programID: program.id,
                stage: .approach,
                interactionPhase: nil,
                timelineID: approach.id,
                cursorSample: 4_799,
                loopIteration: 0,
                durableCompletionSequence: nil
            )
        )
        let durableApproach = controller.runtime.snapshot()
        var ordering: [String] = []
        var deliveredBoundary: ResponsiveAudioProgramSnapshot?
        controller.setAutomaticBoundaryActionHandler { action in
            guard case let .setResponsiveAudioSnapshot(snapshot) = action else {
                return
            }
            ordering.append("boundary")
            deliveredBoundary = snapshot
        }

        try controller.play()
        let boundaryGraphSample = transport.renderClockBaseGraphSampleForTesting + 1
        transport.publishRenderClockAnchorForTesting(
            graphSampleEnd: boundaryGraphSample,
            hostTimeAtGraphSampleEnd: nil
        )

        let capture = try controller.checkpointForDurability(
            constrainedTo: durableApproach
        )
        ordering.append("capture-returned")

        XCTAssertEqual(ordering, ["boundary", "capture-returned"])
        guard case let .awaitingDurableAuthority(projectedOldSnapshot) = capture else {
            transport.stop()
            return XCTFail("A physically crossed boundary cannot refresh old authority")
        }
        XCTAssertEqual(projectedOldSnapshot.stage, .approach)
        XCTAssertEqual(projectedOldSnapshot.cursorSample, 4_799)
        XCTAssertEqual(deliveredBoundary?.stage, .interaction)
        XCTAssertEqual(deliveredBoundary?.interactionPhase, .waiting)
        XCTAssertEqual(deliveredBoundary?.cursorSample, 0)
        XCTAssertEqual(controller.runtime.stage, .interaction)
        XCTAssertEqual(transport.snapshot().timelineID, interactionBeds[0].timelineID)
        transport.stop()
    }

    @MainActor
    func testAutomaticConsequenceWaitsForFullSilenceAndHapticSentinelThenQuiesces() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("consequence.caf"),
            channelCount: 2,
            frameCount: 64,
            constantAmplitude: 0.2
        )
        let consequence = AudioTimeline(
            id: "sentinel-consequence",
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "consequence",
                    role: .score,
                    startSample: 0,
                    durationSamples: 64,
                    assetPath: "consequence.caf",
                    gain: 1
                ),
                AudioEvent(
                    cueID: "authored-tail-silence",
                    role: .silence,
                    startSample: 64,
                    durationSamples: 128,
                    assetPath: nil,
                    gain: 0
                ),
            ],
            haptics: [
                HapticEvent(
                    sample: 256,
                    kind: .seal,
                    intensity: 0.6,
                    sharpness: 0.4
                ),
            ]
        )
        let scheduler = RecordingTimelineHapticScheduler()
        let transport = NativeTimelineTransport(hapticScheduler: scheduler)
        try transport.enableManualRenderingForTesting()
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        try transport.prepareResponsiveAudio(
            plan: oneShotTransportPlan(timeline: consequence),
            resolver: resolver
        )
        var events: [ResponsiveAudioAutomaticBoundaryEvent] = []
        try transport.configureAutomaticBoundary(
            successorPlan: nil,
            resolver: resolver,
            handler: { events.append($0) }
        )
        try transport.play()

        _ = try transport.renderOfflineSamplesForTesting(192)
        XCTAssertEqual(transport.state, .playing)
        XCTAssertTrue(events.isEmpty)
        _ = try transport.renderOfflineSamplesForTesting(64)

        guard case let .completed(snapshot) = try XCTUnwrap(events.first) else {
            return XCTFail("Expected exact consequence completion")
        }
        XCTAssertEqual(snapshot.cursorSample, 256)
        XCTAssertFalse(snapshot.isPlaying)
        XCTAssertEqual(transport.state, .completed)
        XCTAssertFalse(transport.engineIsRunningForTesting)
        XCTAssertFalse(transport.hapticsAreAvailable)
        XCTAssertTrue(scheduler.events.contains(.stoppedImmediately(1)))
        transport.stop()
    }

    @MainActor
    func testAudioSessionLeaseStaysActiveAcrossOutgoingTailAndNextTransport() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeAudioFile(
            to: directory.appendingPathComponent("overlap.caf"),
            channelCount: 2,
            frameCount: 4_800,
            constantAmplitude: 0.2
        )
        let timeline = oneShotTimeline(
            id: "lease-overlap",
            path: "overlap.caf",
            includesHaptic: false
        )
        let resolver = PackageRootAudioAssetResolver(packageRootURL: directory)
        let leaser = RecordingAudioSessionLeaser()
        let outgoing = NativeTimelineTransport(
            hapticScheduler: RecordingTimelineHapticScheduler(),
            audioSessionLeaser: leaser
        )
        let incoming = NativeTimelineTransport(
            hapticScheduler: RecordingTimelineHapticScheduler(),
            audioSessionLeaser: leaser
        )
        try outgoing.prepareResponsiveAudio(
            plan: oneShotTransportPlan(timeline: timeline),
            resolver: resolver
        )
        try incoming.prepareResponsiveAudio(
            plan: oneShotTransportPlan(timeline: timeline),
            resolver: resolver
        )
        do {
            try outgoing.play()
            guard let tail = try outgoing.relinquishOutgoingAudio(
                exitPolicy: .boundedFade(durationSamples: 480_000)
            ) else {
                throw NativeTimelineTransportError.renderClockUnavailable
            }
            try incoming.play()
            XCTAssertEqual(leaser.activeLeaseCount, 2)

            tail.stopImmediately()
            XCTAssertEqual(tail.finishReason, .explicitStop)
            XCTAssertEqual(leaser.activeLeaseCount, 1)
            XCTAssertEqual(leaser.finalDeactivationCount, 0)

            incoming.stop()
            XCTAssertEqual(leaser.activeLeaseCount, 0)
            XCTAssertEqual(leaser.finalDeactivationCount, 1)
        } catch {
            outgoing.stop()
            incoming.stop()
            throw XCTSkip("Simulator audio engine unavailable: \(error)")
        }
    }

    private func oneShotTimeline(
        id: AudioTimelineID,
        path: String,
        durationSamples: Int64 = 4_800,
        includesHaptic: Bool = true
    ) -> AudioTimeline {
        AudioTimeline(
            id: id,
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: "score",
                    role: .score,
                    startSample: 0,
                    durationSamples: durationSamples,
                    assetPath: path,
                    gain: 1
                ),
            ],
            haptics: includesHaptic ? [
                HapticEvent(
                    sample: min(100, durationSamples - 1),
                    kind: .contact,
                    intensity: 0.5,
                    sharpness: 0.5
                ),
            ] : []
        )
    }

    private func oneShotTransportPlan(
        timeline: AudioTimeline
    ) -> ResponsiveAudioTimelineTransportPlan {
        ResponsiveAudioTimelineTransportPlan(
            timeline: timeline,
            cursorSample: 0,
            loopIteration: 0,
            repetition: .once,
            causalMix: nil
        )
    }

    private func causalTimeline(
        phase: ResponsiveInteractionAudioPhase
    ) -> AudioTimeline {
        AudioTimeline(
            id: AudioTimelineID("native-\(phase.rawValue)-bed"),
            sampleRate: 48_000,
            events: [
                AudioEvent(
                    cueID: AudioCueID("\(phase.rawValue)-score"),
                    role: .score,
                    startSample: 0,
                    durationSamples: 4_800,
                    assetPath: "\(phase.rawValue)-score.caf",
                    gain: 0.5
                ),
                AudioEvent(
                    cueID: AudioCueID("\(phase.rawValue)-river"),
                    role: .soundscape,
                    startSample: 0,
                    durationSamples: 4_800,
                    assetPath: "river.caf",
                    gain: 0.8
                ),
                AudioEvent(
                    cueID: AudioCueID("\(phase.rawValue)-work"),
                    role: .spatialDetail,
                    startSample: 0,
                    durationSamples: 4_800,
                    assetPath: "work.caf",
                    gain: 0
                ),
            ],
            haptics: []
        )
    }

    private func causalTransportPlan(
        timeline: AudioTimeline,
        phase: ResponsiveInteractionAudioPhase,
        completedStageCount: Int,
        workGain: Double,
        cursorSample: Int64,
        loopIteration: UInt64
    ) -> ResponsiveAudioTimelineTransportPlan {
        ResponsiveAudioTimelineTransportPlan(
            timeline: timeline,
            cursorSample: cursorSample,
            loopIteration: loopIteration,
            repetition: .loop(iteration: loopIteration, durationSamples: 4_800),
            causalMix: ResponsiveAudioCausalMixPlaybackPlan(
                completedStageCount: completedStageCount,
                rampDurationSamples: 480,
                layers: [
                    ResponsiveAudioCausalLayerPlaybackTarget(
                        layerID: "river",
                        cueID: AudioCueID("\(phase.rawValue)-river"),
                        role: .soundscape,
                        assetPath: "river.caf",
                        startSample: 0,
                        durationSamples: 4_800,
                        targetGain: 0.8
                    ),
                    ResponsiveAudioCausalLayerPlaybackTarget(
                        layerID: "work",
                        cueID: AudioCueID("\(phase.rawValue)-work"),
                        role: .spatialDetail,
                        assetPath: "work.caf",
                        startSample: 0,
                        durationSamples: 4_800,
                        targetGain: workGain
                    ),
                ]
            )
        )
    }

    @MainActor
    private func assertMixerVolumes(
        _ transport: NativeTimelineTransport,
        narration: Float,
        score: Float,
        soundscape: Float,
        detail: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            transport.mixerOutputVolumeForTesting(.narration),
            narration,
            file: file,
            line: line
        )
        XCTAssertEqual(
            transport.mixerOutputVolumeForTesting(.score),
            score,
            file: file,
            line: line
        )
        XCTAssertEqual(
            transport.mixerOutputVolumeForTesting(.soundscape),
            soundscape,
            file: file,
            line: line
        )
        XCTAssertEqual(
            transport.mixerOutputVolumeForTesting(.spatialDetail),
            detail,
            file: file,
            line: line
        )
    }
}

private final class CountingAudioResolver: OfflineAudioAssetResolving,
    @unchecked Sendable {
    let root: URL
    var failingPaths: Set<String> = []
    var callCount = 0

    init(root: URL) {
        self.root = root
    }

    func url(for packageRelativePath: String) throws -> URL {
        callCount += 1
        if failingPaths.contains(packageRelativePath) {
            throw OfflineAudioAssetResolutionError.missingFile(packageRelativePath)
        }
        return root.appendingPathComponent(packageRelativePath)
    }
}

@MainActor
private final class RecordingTimelineHapticScheduler:
    NativeTimelineHapticScheduling {
    final class Playback: NativeTimelineHapticPlayback {
        let id: Int

        init(id: Int) {
            self.id = id
        }
    }

    enum Event: Equatable {
        case prepared(Int)
        case started(Int, NativeTimelineHapticBoundary, Bool)
        case scheduledStop(Int, NativeTimelineHapticBoundary)
        case stoppedImmediately(Int)
        case enabled(Int, Bool)
    }

    enum Failure: Error {
        case injected
    }

    private(set) var events: [Event] = []
    var failNextScheduledStop = false
    var failEnabledPlaybackIDs: Set<Int> = []
    private var nextID = 1

    func prepare(
        haptics: [ScheduledHaptic],
        sampleRate _: Int
    ) throws -> (any NativeTimelineHapticPlayback)? {
        guard !haptics.isEmpty else { return nil }
        let playback = Playback(id: nextID)
        nextID += 1
        events.append(.prepared(playback.id))
        return playback
    }

    func start(
        _ playback: any NativeTimelineHapticPlayback,
        context: NativeTimelineHapticRuntimeContext,
        enabled: Bool
    ) throws {
        let playback = try requirePlayback(playback)
        events.append(.started(playback.id, context.boundary, enabled))
        events.append(.enabled(playback.id, enabled))
    }

    func scheduleStop(
        _ playback: any NativeTimelineHapticPlayback,
        at boundary: NativeTimelineHapticBoundary
    ) throws {
        if failNextScheduledStop {
            failNextScheduledStop = false
            throw Failure.injected
        }
        let playback = try requirePlayback(playback)
        events.append(.scheduledStop(playback.id, boundary))
    }

    func stopImmediately(_ playback: any NativeTimelineHapticPlayback) {
        guard let playback = playback as? Playback else { return }
        events.append(.stoppedImmediately(playback.id))
    }

    func setEnabled(
        _ enabled: Bool,
        for playback: any NativeTimelineHapticPlayback
    ) throws {
        let playback = try requirePlayback(playback)
        if failEnabledPlaybackIDs.contains(playback.id) {
            throw Failure.injected
        }
        events.append(.enabled(playback.id, enabled))
    }

    private func requirePlayback(
        _ playback: any NativeTimelineHapticPlayback
    ) throws -> Playback {
        guard let playback = playback as? Playback else {
            throw Failure.injected
        }
        return playback
    }
}

@MainActor
private final class RecordingAudioSessionLeaser: NativeAudioSessionLeasing {
    enum Failure: Error {
        case injected
    }

    private final class Lease: NativeAudioSessionLease {
        let routeFormat: NativeAudioRouteFormat
        private weak var owner: RecordingAudioSessionLeaser?
        private var released = false

        init(
            routeFormat: NativeAudioRouteFormat,
            owner: RecordingAudioSessionLeaser
        ) {
            self.routeFormat = routeFormat
            self.owner = owner
        }

        func release() {
            guard !released else { return }
            released = true
            owner?.releaseOne()
        }
    }

    var scriptedFormats: [NativeAudioRouteFormat]
    var failNextAcquire = false
    private(set) var acquireCount = 0
    private(set) var releaseCount = 0
    private(set) var activeLeaseCount = 0
    private(set) var finalDeactivationCount = 0

    init(
        scriptedFormats: [NativeAudioRouteFormat] = [
            NativeAudioRouteFormat(
                sessionSampleRate: 48_000,
                outputSampleRate: 48_000
            ),
        ]
    ) {
        self.scriptedFormats = scriptedFormats
    }

    func acquire(
        preferredSampleRate _: Double,
        engine _: AVAudioEngine
    ) throws -> any NativeAudioSessionLease {
        if failNextAcquire {
            failNextAcquire = false
            throw Failure.injected
        }
        let index = min(acquireCount, max(0, scriptedFormats.count - 1))
        let format = scriptedFormats[index]
        acquireCount += 1
        activeLeaseCount += 1
        return Lease(routeFormat: format, owner: self)
    }

    private func releaseOne() {
        guard activeLeaseCount > 0 else { return }
        activeLeaseCount -= 1
        releaseCount += 1
        if activeLeaseCount == 0 {
            finalDeactivationCount += 1
        }
    }
}

@MainActor
private final class RecordingSystemAudioSessionController:
    NativeSystemAudioSessionControlling {
    enum Event: Equatable {
        case configure(Double)
        case activate
        case deactivate
    }

    enum Failure: Error {
        case injected
    }

    var sampleRate: Double
    var configurationFailuresRemaining = 0
    var activationFailuresRemaining = 0
    var deactivationFailuresRemaining = 0
    private(set) var configurationCount = 0
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    private(set) var events: [Event] = []

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func configureForPlayback(preferredSampleRate: Double) throws {
        configurationCount += 1
        events.append(.configure(preferredSampleRate))
        if configurationFailuresRemaining > 0 {
            configurationFailuresRemaining -= 1
            throw Failure.injected
        }
    }

    func activate() throws {
        activationCount += 1
        events.append(.activate)
        if activationFailuresRemaining > 0 {
            activationFailuresRemaining -= 1
            throw Failure.injected
        }
    }

    func deactivateNotifyingOthers() throws {
        deactivationCount += 1
        events.append(.deactivate)
        if deactivationFailuresRemaining > 0 {
            deactivationFailuresRemaining -= 1
            throw Failure.injected
        }
    }
}
#endif
