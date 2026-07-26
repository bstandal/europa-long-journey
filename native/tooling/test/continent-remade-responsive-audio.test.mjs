import assert from "node:assert/strict";
import test from "node:test";

import {
  continentRemadeResponsiveAudioPaths,
  validateContinentRemadeResponsiveAudio,
  validateContinentRemadeResponsiveAudioSources,
} from "../src/continent-remade-responsive-audio.mjs";

let validation;
const fullValidation = () => {
  validation ??= validateContinentRemadeResponsiveAudio();
  return validation;
};

test("the Continent Remade symbolic and procedural sources validate without rendering", async () => {
  assert.deepEqual(await validateContinentRemadeResponsiveAudioSources(), {
    scoreSourceID: "continent-remade-responsive-score-v1",
    soundscapeSourceID: "continent-remade-responsive-soundscape-v1",
    regionCount: 5,
  });
});

test("the Continent Remade responsive program is receipt-bound, deterministic and non-shipping", async () => {
  const result = await fullValidation();
  assert.equal(result.work.id, "continent-remade-responsive-audio-v1");
  assert.equal(result.work.status, "PROVISIONAL_NON_SHIPPING");
  assert.equal(result.work.shippingState, "PROHIBITED");
  assert.equal(result.work.scope.arcID, "first-farmers-arc-03");
  assert.equal(result.work.scope.beatID, "beat-first-farmers-continent-remade");
  assert.equal(
    result.work.scope.interactionID,
    "interaction-first-farmers-a-continent-remade",
  );
  assert.equal(result.receipt.reproducibility, "PASS_SECOND_COMPLETE_OFFLINE_RENDER");
  assert.equal(result.receipt.outputs.length, 75);
  assert.equal(result.work.audioAssetMetadata.length, 15);
  assert.match(result.workObjectSHA256, /^[a-f0-9]{64}$/u);
  assert.match(result.receiptSHA256, /^[a-f0-9]{64}$/u);
  assert.ok(continentRemadeResponsiveAudioPaths.cacheRoot.endsWith("continent-remade-responsive-v1"));
  assert.equal(result.work.gates.artisticApproval, "OPEN");
  assert.equal(result.work.gates.editorApproval, "OPEN");
  assert.equal(result.work.gates.shippingApproval, "PROHIBITED");
});

test("Continent Remade state beds retain one sample position and carry no narration or timed haptics", async () => {
  const { work } = await fullValidation();
  assert.deepEqual(
    work.responsiveProgram.interactionBeds.map(({ phase, timelineID }) => ({ phase, timelineID })),
    [
      { phase: "waiting", timelineID: "continent-remade-waiting-bed-v1" },
      { phase: "engaged", timelineID: "continent-remade-engaged-bed-v1" },
      { phase: "resistance", timelineID: "continent-remade-resistance-bed-v1" },
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
  assert.deepEqual(work.hapticProgram.activeContinentRemadeSemantics, ["drag", "break", "seal"]);
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
        timelineID: "continent-remade-approach-v1",
        requiredAssetPath: "audio/first-farmers/continent-remade-responsive-v1/approach/narration-selected-master-required.wav",
        segmentIDs: ["ff-continent-01", "ff-continent-02"],
      },
      {
        timelineID: "continent-remade-consequence-v1",
        requiredAssetPath: "audio/first-farmers/continent-remade-responsive-v1/consequence/narration-selected-master-required.wav",
        segmentIDs: ["ff-ending-01", "ff-ending-02"],
      },
    ],
  );
});
