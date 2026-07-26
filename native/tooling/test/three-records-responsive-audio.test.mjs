import assert from "node:assert/strict";
import test from "node:test";

import {
  threeRecordsResponsiveAudioPaths,
  validateThreeRecordsResponsiveAudio,
  validateThreeRecordsResponsiveAudioSources,
} from "../src/three-records-responsive-audio.mjs";

let validation;
const fullValidation = () => {
  validation ??= validateThreeRecordsResponsiveAudio();
  return validation;
};

test("the Three Records symbolic and procedural sources validate without rendering", async () => {
  assert.deepEqual(await validateThreeRecordsResponsiveAudioSources(), {
    scoreSourceID: "three-records-responsive-score-v1",
    soundscapeSourceID: "three-records-responsive-soundscape-v1",
    regionCount: 5,
  });
});

test("the Three Records work object is deterministic, receipt-bound and non-shipping", async () => {
  const result = await fullValidation();
  assert.equal(result.work.id, "three-records-responsive-audio-v1");
  assert.equal(result.work.status, "PROVISIONAL_NON_SHIPPING");
  assert.equal(result.work.shippingState, "PROHIBITED");
  assert.deepEqual(result.work.scope, {
    chapterID: "first-farmers",
    arcID: "first-farmers-arc-02",
    beatID: "beat-first-farmers-three-records",
    interactionID: "interaction-first-farmers-at-the-iron-gates",
  });
  assert.equal(result.receipt.reproducibility, "PASS_SECOND_COMPLETE_OFFLINE_RENDER");
  assert.equal(result.receipt.outputs.length, 65);
  assert.equal(result.work.audioAssetMetadata.length, 16);
  assert.match(result.workObjectSHA256, /^[a-f0-9]{64}$/u);
  assert.match(result.receiptSHA256, /^[a-f0-9]{64}$/u);
  assert.ok(threeRecordsResponsiveAudioPaths.cacheRoot.endsWith("three-records-responsive-v1"));
  assert.equal(result.work.gates.artisticApproval, "OPEN");
  assert.equal(result.work.gates.editorApproval, "OPEN");
  assert.equal(result.work.gates.shippingApproval, "PROHIBITED");
});

test("all interaction phases reuse seven exact material assets and expose monotonic causal states", async () => {
  const { work } = await fullValidation();
  const mix = work.responsiveProgram.causalMix;
  const layerIDs = [
    "gorge-current",
    "river-gear",
    "landing-work",
    "settlement-hearths",
    "carried-grain",
    "domestic-herd",
    "household-voices",
  ];
  assert.equal(mix.rampDurationSamples, 9_600);
  assert.deepEqual(mix.layers.map(({ id }) => id), layerIDs);
  assert.deepEqual(mix.states.map(({ completedStageCount }) => completedStageCount), [0, 1, 2, 3]);
  assert.deepEqual(
    mix.states.map(({ layerGains }) => layerGains.map(({ gain }) => gain)),
    [
      [0.82, 0, 0, 0, 0, 0, 0],
      [0.82, 0.32, 0.28, 0.18, 0, 0, 0.14],
      [0.82, 0.42, 0.38, 0.28, 0.3, 0.24, 0.34],
      [0.82, 0.48, 0.44, 0.34, 0.4, 0.32, 0.42],
    ],
  );
  for (const [index, state] of mix.states.entries()) {
    assert.deepEqual(state.layerGains.map(({ layerID }) => layerID), layerIDs);
    if (index > 0) {
      state.layerGains.forEach(({ gain }, gainIndex) => {
        assert.ok(gain >= mix.states[index - 1].layerGains[gainIndex].gain);
      });
    }
  }
  for (const layer of mix.layers) {
    const expectedPath = `audio/first-farmers/three-records-responsive-v1/interaction/shared/${layer.id}.wav`;
    assert.equal(layer.assetPath, expectedPath);
    for (const phase of ["waiting", "engaged", "resistance"]) {
      assert.equal(layer.cueIDs[phase], `${phase}-${layer.id}`);
      const bed = work.responsiveProgram.interactionBeds.find((item) => item.phase === phase);
      const timeline = work.timelines.find((item) => item.id === bed.timelineID);
      const event = timeline.events.find((item) => item.cueID === layer.cueIDs[phase]);
      assert.equal(event.assetPath, expectedPath);
      assert.equal(event.startSample, 0);
      assert.equal(event.durationSamples, 720_000);
    }
  }
});

test("Three Records keeps quiet source-scoped and narration and haptics fail closed", async () => {
  const { work } = await fullValidation();
  assert.ok(work.timelines.every((timeline) =>
    timeline.haptics.length === 0
      && timeline.events.every(({ role }) => !["silence", "narration", "haptic"].includes(role))));
  assert.deepEqual(
    work.authoredQuiet.map(({ timelineID, startSample, durationSamples }) => ({
      timelineID, startSample, durationSamples,
    })),
    [
      { timelineID: "three-records-approach-v1", startSample: 0, durationSamples: 96_000 },
      { timelineID: "three-records-waiting-bed-v1", startSample: 710_400, durationSamples: 9_600 },
      { timelineID: "three-records-engaged-bed-v1", startSample: 710_400, durationSamples: 9_600 },
      { timelineID: "three-records-resistance-bed-v1", startSample: 710_400, durationSamples: 9_600 },
      { timelineID: "three-records-consequence-v1", startSample: 0, durationSamples: 144_000 },
    ],
  );
  assert.ok(work.authoredQuiet.every(({ scope, preservedCueIDs }) =>
    scope === "SOURCE_BOUND_QUIET_NOT_GLOBAL_TIMELINE_SILENCE" && preservedCueIDs.length === 1));
  assert.deepEqual(work.hapticProgram.activeThreeRecordsSemantics, ["drag", "break", "seal"]);
  assert.deepEqual(work.hapticProgram.runtimeBindings, [
    { trigger: "transform-drag", semantic: "drag", durableCommitRequired: false },
    { trigger: "causal-threshold-crossed", completedStageCounts: [1, 2, 3], semantic: "break", durableCommitRequired: false },
    { trigger: "durable-completion", semantic: "seal", durableCommitRequired: true },
  ]);
  assert.deepEqual(work.narrationSlots.map(({ segments }) => segments.map(({ manuscriptSegmentID }) => manuscriptSegmentID)), [
    ["ff-records-01", "ff-records-02"],
    ["ff-frontier-consequence-01", "ff-frontier-consequence-02"],
  ]);
  assert.ok(work.narrationSlots.every(({ shippingBlock, status }) =>
    shippingBlock && status === "MISSING_EDITOR_SELECTED_NARRATION_MASTER"));
  assert.equal(work.gates.scopedAuthoredQuiet, "PASS_RIVER_REMAINS_SAMPLE_CONTINUOUS");
  assert.equal(work.gates.shippingApproval, "PROHIBITED");
});
