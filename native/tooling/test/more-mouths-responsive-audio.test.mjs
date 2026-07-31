import assert from "node:assert/strict";
import test from "node:test";

import {
  moreMouthsResponsiveAudioPaths,
  validateMoreMouthsResponsiveAudio,
  validateMoreMouthsResponsiveAudioSources,
} from "../src/more-mouths-responsive-audio.mjs";

let validation;
const fullValidation = () => {
  validation ??= validateMoreMouthsResponsiveAudio();
  return validation;
};

test("the More Mouths symbolic and procedural sources validate without rendering", async () => {
  assert.deepEqual(await validateMoreMouthsResponsiveAudioSources(), {
    scoreSourceID: "more-mouths-responsive-score-v1",
    soundscapeSourceID: "more-mouths-responsive-soundscape-v1",
    regionCount: 5,
  });
});

test("the More Mouths responsive program is receipt-bound, deterministic and non-shipping", async () => {
  const result = await fullValidation();
  assert.equal(result.work.id, "more-mouths-responsive-audio-v1");
  assert.equal(result.work.status, "PROVISIONAL_NON_SHIPPING");
  assert.equal(result.work.shippingState, "PROHIBITED");
  assert.equal(result.work.scope.arcID, "first-farmers-arc-03");
  assert.equal(result.work.scope.beatID, "beat-first-farmers-more-mouths");
  assert.equal(
    result.work.scope.interactionID,
    "interaction-first-farmers-more-mouths-more-land",
  );
  assert.equal(result.receipt.reproducibility, "PASS_SECOND_COMPLETE_OFFLINE_RENDER");
  assert.equal(result.receipt.outputs.length, 75);
  assert.equal(result.work.audioAssetMetadata.length, 15);
  assert.match(result.workObjectSHA256, /^[a-f0-9]{64}$/u);
  assert.match(result.receiptSHA256, /^[a-f0-9]{64}$/u);
  assert.ok(moreMouthsResponsiveAudioPaths.cacheRoot.endsWith("more-mouths-responsive-v1"));
  assert.equal(result.work.gates.artisticApproval, "OPEN");
  assert.equal(result.work.gates.editorApproval, "OPEN");
  assert.equal(result.work.gates.shippingApproval, "PROHIBITED");
});

test("More Mouths state beds retain one sample position and carry no narration or timed haptics", async () => {
  const { work } = await fullValidation();
  assert.deepEqual(
    work.responsiveProgram.interactionBeds.map(({ phase, timelineID }) => ({ phase, timelineID })),
    [
      { phase: "waiting", timelineID: "more-mouths-waiting-bed-v1" },
      { phase: "engaged", timelineID: "more-mouths-engaged-bed-v1" },
      { phase: "resistance", timelineID: "more-mouths-resistance-bed-v1" },
    ],
  );
  const beds = work.responsiveProgram.interactionBeds.map(({ timelineID }) =>
    work.timelines.find(({ id }) => id === timelineID));
  assert.deepEqual(new Set(beds.map((timeline) =>
    Math.max(...timeline.events.map(({ startSample, durationSamples }) => startSample + durationSamples)))),
  new Set([720_000]));
  assert.ok(beds.every((timeline) =>
    timeline.haptics.length === 0
      && timeline.events.every(({ role }) => role !== "narration")));
  assert.deepEqual(work.hapticProgram.activeMoreMouthsSemantics, ["drag", "break", "seal"]);
  assert.deepEqual(work.hapticProgram.runtimeBindings, [
    { trigger: "transform-drag", semantic: "drag", durableCommitRequired: false },
    { trigger: "causal-threshold-crossed", semantic: "break", durableCommitRequired: false },
    { trigger: "durable-completion", semantic: "seal", durableCommitRequired: true },
  ]);
  assert.equal(
    work.hapticProgram.runtimeBindings.find(({ semantic }) => semantic === "seal")
      ?.durableCommitRequired,
    true,
  );
  assert.ok(work.narrationSlots.every(({ shippingBlock, status }) =>
    shippingBlock && status === "MISSING_EDITOR_SELECTED_NARRATION_MASTER"));
  assert.deepEqual(
    work.narrationSlots.map(({ timelineID, requiredAssetPath, segments }) => ({
      timelineID,
      requiredAssetPath,
      segmentIDs: segments.map(({ manuscriptSegmentID }) => manuscriptSegmentID),
    })),
    [
      {
        timelineID: "more-mouths-approach-v1",
        requiredAssetPath: "audio/first-farmers/more-mouths-responsive-v1/approach/narration-selected-master-required.wav",
        segmentIDs: ["ff-growth-01", "ff-growth-02"],
      },
      {
        timelineID: "more-mouths-consequence-v1",
        requiredAssetPath: "audio/first-farmers/more-mouths-responsive-v1/consequence/narration-selected-master-required.wav",
        segmentIDs: ["ff-contraction-01", "ff-contraction-02"],
      },
    ],
  );
  assert.deepEqual(work.causalBinding, {
    controlID: "settlement-pressure",
    stages: [
      { id: "new-hearths", requiredAmount: 0.32 },
      { id: "field-edges", requiredAmount: 0.66 },
      { id: "herd-lanes-and-daughters", requiredAmount: 1 },
    ],
    completionEffectID: "effect-first-farmers-more-mouths-more-land",
    persistentTraceID: "trace-european-farming-belt",
    audioStageAccumulation: "PHASE_LEVEL_ONLY_UNTIL_RUNTIME_SUPPORTS_LATCHED_THRESHOLD_MIXES",
  });
});
