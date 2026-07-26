import assert from "node:assert/strict";
import test from "node:test";
import {
  harvestResponsiveAudioPaths,
  validateHarvestResponsiveAudio,
} from "../src/harvest-responsive-audio.mjs";

test("the provisional Harvest responsive work object is fully receipt-bound and non-shipping", async () => {
  const result = await validateHarvestResponsiveAudio();
  assert.equal(result.work.status, "PROVISIONAL_NON_SHIPPING");
  assert.equal(result.work.shippingState, "PROHIBITED");
  assert.equal(result.receipt.reproducibility, "PASS_SECOND_COMPLETE_OFFLINE_RENDER");
  assert.equal(result.receipt.outputs.length, 75);
  assert.equal(result.work.audioAssetMetadata.length, 15);
  const inputByID = new Map(result.receipt.productionInputs.map((input) => [input.id, input]));
  const requiredRuntimeInputs = [
    ["responsive-audio-program-runtime", "native/ios/Sources/DramaticAudio/ResponsiveAudioProgramRuntime.swift"],
    ["responsive-audio-program-controller", "native/ios/Sources/DramaticAudio/ResponsiveAudioProgramController.swift"],
    ["responsive-audio-timeline-planner", "native/ios/Sources/DramaticAudio/TimelinePlaybackPlan.swift"],
    ["responsive-audio-transport-contract", "native/ios/Sources/DramaticAudio/OfflineAudioAssetResolver.swift"],
    ["native-timeline-transport", "native/ios/Sources/DramaticAudio/NativeTimelineTransport.swift"],
    ["experience-audio-routing-policy", "native/ios/Sources/DramaticAudio/ExperienceAudioRoutingPolicy.swift"],
    ["experience-preferences-contract", "native/ios/Sources/ExperiencePreferences/ExperiencePreferences.swift"],
    ["durable-audio-completion-runtime", "native/ios/Sources/DramaticAudio/DurableInteractionAudioCompletion.swift"],
    ["semantic-haptic-runtime", "native/ios/Sources/DramaticAudio/SemanticHapticTransport.swift"],
  ];
  for (const [id, expectedPath] of requiredRuntimeInputs) {
    assert.equal(inputByID.get(id)?.path, expectedPath);
    assert.match(inputByID.get(id)?.sha256 ?? "", /^[a-f0-9]{64}$/u);
  }
  assert.match(result.workObjectSHA256, /^[a-f0-9]{64}$/u);
  assert.match(result.receiptSHA256, /^[a-f0-9]{64}$/u);
  assert.ok(harvestResponsiveAudioPaths.cacheRoot.endsWith("harvest-responsive-v1"));
});

test("Harvest phase beds are sample-identical and never loop narration or timed haptics", async () => {
  const { work } = await validateHarvestResponsiveAudio();
  const beds = work.responsiveProgram.interactionBeds.map(({ timelineID }) =>
    work.timelines.find(({ id }) => id === timelineID));
  assert.deepEqual(beds.map(({ id }) => id), [
    "harvest-waiting-bed-v1",
    "harvest-engaged-bed-v1",
    "harvest-resistance-bed-v1",
  ]);
  assert.deepEqual(new Set(beds.map((timeline) =>
    Math.max(...timeline.events.map(({ startSample, durationSamples }) => startSample + durationSamples)))),
  new Set([720_000]));
  assert.ok(beds.every((timeline) =>
    timeline.haptics.length === 0
      && timeline.events.every(({ role }) => role !== "narration")));
});
