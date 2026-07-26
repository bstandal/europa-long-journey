import assert from "node:assert/strict";
import test from "node:test";

import {
  longhouseResponsiveAudioPaths,
  validateLonghouseResponsiveAudio,
  validateLonghouseResponsiveAudioSources,
} from "../src/longhouse-responsive-audio.mjs";

let validation;
const fullValidation = () => {
  validation ??= validateLonghouseResponsiveAudio();
  return validation;
};

test("the Longhouse symbolic and procedural sources validate without rendering", async () => {
  assert.deepEqual(await validateLonghouseResponsiveAudioSources(), {
    scoreSourceID: "longhouse-responsive-score-v1",
    soundscapeSourceID: "longhouse-responsive-soundscape-v1",
    regionCount: 5,
  });
});

test("the Longhouse responsive program is receipt-bound, deterministic and non-shipping", async () => {
  const result = await fullValidation();
  assert.equal(result.work.id, "longhouse-responsive-audio-v1");
  assert.equal(result.work.status, "PROVISIONAL_NON_SHIPPING");
  assert.equal(result.work.shippingState, "PROHIBITED");
  assert.equal(result.work.scope.beatID, "beat-first-farmers-raise-longhouse");
  assert.equal(result.receipt.reproducibility, "PASS_SECOND_COMPLETE_OFFLINE_RENDER");
  assert.equal(result.receipt.outputs.length, 75);
  assert.equal(result.work.audioAssetMetadata.length, 15);
  assert.match(result.workObjectSHA256, /^[a-f0-9]{64}$/u);
  assert.match(result.receiptSHA256, /^[a-f0-9]{64}$/u);
  assert.ok(longhouseResponsiveAudioPaths.cacheRoot.endsWith("longhouse-responsive-v1"));
  assert.equal(result.work.gates.artisticApproval, "OPEN");
  assert.equal(result.work.gates.editorApproval, "OPEN");
  assert.equal(result.work.gates.shippingApproval, "PROHIBITED");
});

test("Longhouse state beds retain one sample position and carry no narration or timed haptics", async () => {
  const { work } = await fullValidation();
  assert.deepEqual(
    work.responsiveProgram.interactionBeds.map(({ phase, timelineID }) => ({ phase, timelineID })),
    [
      { phase: "waiting", timelineID: "longhouse-waiting-bed-v1" },
      { phase: "engaged", timelineID: "longhouse-engaged-bed-v1" },
      { phase: "resistance", timelineID: "longhouse-resistance-bed-v1" },
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
  assert.deepEqual(work.hapticProgram.activeLonghouseSemantics, ["contact", "resistance", "seal"]);
  assert.equal(
    work.hapticProgram.runtimeBindings.find(({ semantic }) => semantic === "seal")
      ?.durableCommitRequired,
    true,
  );
  assert.ok(work.narrationSlots.every(({ shippingBlock, status }) =>
    shippingBlock && status === "MISSING_EDITOR_SELECTED_NARRATION_MASTER"));
});
