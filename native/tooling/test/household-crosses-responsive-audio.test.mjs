import assert from "node:assert/strict";
import test from "node:test";

import {
  householdCrossesResponsiveAudioPaths,
  validateHouseholdCrossesResponsiveAudio,
  validateHouseholdCrossesResponsiveAudioSources,
} from "../src/household-crosses-responsive-audio.mjs";

let validation;
const fullValidation = () => {
  validation ??= validateHouseholdCrossesResponsiveAudio();
  return validation;
};

test("the Household Crosses symbolic and procedural sources validate without rendering", async () => {
  assert.deepEqual(await validateHouseholdCrossesResponsiveAudioSources(), {
    scoreSourceID: "household-crosses-responsive-score-v1",
    soundscapeSourceID: "household-crosses-responsive-soundscape-v1",
    regionCount: 5,
  });
});

test("the Household Crosses responsive program is receipt-bound, deterministic and non-shipping", async () => {
  const result = await fullValidation();
  assert.equal(result.work.id, "household-crosses-responsive-audio-v1");
  assert.equal(result.work.status, "PROVISIONAL_NON_SHIPPING");
  assert.equal(result.work.shippingState, "PROHIBITED");
  assert.equal(result.work.scope.arcID, "first-farmers-arc-01");
  assert.equal(result.work.scope.beatID, "beat-first-farmers-household-crosses");
  assert.equal(
    result.work.scope.interactionID,
    "interaction-first-farmers-a-household-crosses",
  );
  assert.equal(result.receipt.reproducibility, "PASS_SECOND_COMPLETE_OFFLINE_RENDER");
  assert.equal(result.receipt.outputs.length, 75);
  assert.equal(result.work.audioAssetMetadata.length, 15);
  assert.match(result.workObjectSHA256, /^[a-f0-9]{64}$/u);
  assert.match(result.receiptSHA256, /^[a-f0-9]{64}$/u);
  assert.ok(householdCrossesResponsiveAudioPaths.cacheRoot.endsWith("household-crosses-responsive-v1"));
  assert.equal(result.work.gates.artisticApproval, "OPEN");
  assert.equal(result.work.gates.editorApproval, "OPEN");
  assert.equal(result.work.gates.shippingApproval, "PROHIBITED");
});

test("Household Crosses state beds retain one sample position and carry no narration or timed haptics", async () => {
  const { work } = await fullValidation();
  assert.deepEqual(
    work.responsiveProgram.interactionBeds.map(({ phase, timelineID }) => ({ phase, timelineID })),
    [
      { phase: "waiting", timelineID: "household-crosses-waiting-bed-v1" },
      { phase: "engaged", timelineID: "household-crosses-engaged-bed-v1" },
      { phase: "resistance", timelineID: "household-crosses-resistance-bed-v1" },
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
  assert.deepEqual(work.hapticProgram.activeHouseholdCrossesSemantics, ["contact", "drag", "seal"]);
  assert.deepEqual(work.hapticProgram.runtimeBindings, [
    { trigger: "trace-origin-contact", semantic: "contact", durableCommitRequired: false },
    { trigger: "trace-intermediate-anchor-accepted", semantic: "contact", durableCommitRequired: false },
    { trigger: "trace-viable-movement-throttled", semantic: "drag", durableCommitRequired: false },
    { trigger: "trace-destination-durable-commit", semantic: "seal", durableCommitRequired: true },
  ]);
  assert.equal(work.hapticProgram.destinationPreliminaryContact, "FORBIDDEN");
  assert.equal(work.hapticProgram.resistanceSemantic, "FORBIDDEN");
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
        timelineID: "household-crosses-approach-v1",
        requiredAssetPath: "audio/first-farmers/household-crosses-responsive-v1/approach/narration-selected-master-required.wav",
        segmentIDs: ["ff-crossing-01", "ff-crossing-02"],
      },
      {
        timelineID: "household-crosses-consequence-v1",
        requiredAssetPath: "audio/first-farmers/household-crosses-responsive-v1/consequence/narration-selected-master-required.wav",
        segmentIDs: ["ff-system-01", "ff-system-02"],
      },
    ],
  );
  assert.deepEqual(work.causalBinding, {
    controlID: "household-route-progress",
    originAnchorID: "western-anatolia",
    stages: [
      { id: "aegean-islands", requiredAmount: 0.333333 },
      { id: "thessaly", requiredAmount: 0.666667 },
      { id: "danube-corridor", requiredAmount: 1 },
    ],
    completionEffectID: "effect-first-farmers-a-household-crosses",
    packageTraceID: "route-aegean-danube",
    persistentTraceID: "trace-european-farming-belt",
    audioStageAccumulation: "PHASE_LEVEL_ONLY_VISUAL_REDUCER_OWNS_LATCHED_ANCHORS",
  });
  assert.deepEqual(
    work.authoredSilence.map(({ timelineID, startSample, durationSamples }) => ({
      timelineID, startSample, durationSamples,
    })),
    [
      { timelineID: "household-crosses-approach-v1", startSample: 2_652_000, durationSamples: 132_000 },
      { timelineID: "household-crosses-waiting-bed-v1", startSample: 710_400, durationSamples: 9_600 },
      { timelineID: "household-crosses-engaged-bed-v1", startSample: 350_400, durationSamples: 7_680 },
      { timelineID: "household-crosses-resistance-bed-v1", startSample: 554_400, durationSamples: 9_600 },
      { timelineID: "household-crosses-consequence-v1", startSample: 744_000, durationSamples: 216_000 },
    ],
  );
  assert.deepEqual(work.editorialBlocks, []);
  assert.equal(work.gates.narrationF5SowingSeason, "PASS_EDITOR_REPAIR_BOUND_TO_FROZEN_TEXT");
  assert.deepEqual(work.acousticBoundaries.soundscapeProhibitedClaims, [
    "sail, mast, rigging or wind propulsion",
    "specific paddle, oar, rowing action or cadence",
    "plank, keel, deck, nail or metal-fitting construction",
    "storm or heroic ocean",
    "species calls, bells, tack, gallop or stampede",
    "human speech, chant or crowd",
    "procedural tones represented as documented waves or historical evidence",
  ]);
  assert.equal(work.gates.shippingApproval, "PROHIBITED");
});
