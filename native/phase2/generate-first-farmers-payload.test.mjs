import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { validateContentPackagePayload } from "../tooling/src/validate.mjs";
import { projectedPayloadDocuments } from "./generate-first-farmers-payload.mjs";

const phase2Root = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(phase2Root, "../..");
const generatedRoot = path.join(phase2Root, "generated");

const payloadPath = path.join(generatedRoot, "first-farmers.content-package.json");
const requirementsPath = path.join(
  generatedRoot,
  "first-farmers.asset-requirements.json",
);
const receiptPath = path.join(generatedRoot, "first-farmers.payload-receipt.json");
const draftPath = path.join(
  phase2Root,
  "editor-review/first-farmers/first-farmers-native-draft-v1.json",
);
const harvestFixturePath = path.join(
  repositoryRoot,
  "native/phase1/fixtures/harvest-option-1.scene.json",
);
const longhouseWorkObjectPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/longhouse-responsive-v1/longhouse-responsive-work-object.json",
);
const continentRemadeWorkObjectPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/continent-remade-responsive-v1/continent-remade-responsive-work-object.json",
);
const moreMouthsWorkObjectPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/more-mouths-responsive-v1/more-mouths-responsive-work-object.json",
);
const householdCrossesWorkObjectPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/household-crosses-responsive-v1/household-crosses-responsive-work-object.json",
);
const threeRecordsWorkObjectPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/three-records-responsive-v1/three-records-responsive-work-object.json",
);

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const readJSON = async (file) => JSON.parse(await readFile(file, "utf8"));

function collectAssetPaths(value, output = []) {
  if (Array.isArray(value)) {
    value.forEach((item) => collectAssetPaths(item, output));
    return output;
  }
  if (!value || typeof value !== "object") return output;
  for (const [key, item] of Object.entries(value)) {
    if (key.toLowerCase().endsWith("assetpath") && typeof item === "string") {
      output.push(item);
    } else {
      collectAssetPaths(item, output);
    }
  }
  return output;
}

function deepKeys(value, output = []) {
  if (Array.isArray(value)) {
    value.forEach((item) => deepKeys(item, output));
    return output;
  }
  if (!value || typeof value !== "object") return output;
  for (const [key, item] of Object.entries(value)) {
    output.push(key.toLowerCase());
    deepKeys(item, output);
  }
  return output;
}

test("payload generator is deterministic and the canonical validator accepts its exact bytes", async () => {
  const projected = await projectedPayloadDocuments();
  const [payloadBytes, requirementBytes, receiptBytes] = await Promise.all([
    readFile(payloadPath),
    readFile(requirementsPath),
    readFile(receiptPath),
  ]);
  assert.deepEqual(payloadBytes, Buffer.from(projected.payloadBytes));
  assert.deepEqual(requirementBytes, Buffer.from(projected.assetRequirementBytes));
  assert.deepEqual(receiptBytes, Buffer.from(projected.receiptBytes));

  const payload = JSON.parse(payloadBytes);
  const receipt = JSON.parse(receiptBytes);
  assert.deepEqual(validateContentPackagePayload(payload), []);
  assert.ok(payload.responsiveAudioPrograms.every(({ exitPolicy }) =>
    exitPolicy?.kind === "bounded-fade"
      && exitPolicy.durationSamples === 9_600));
  assert.equal(receipt.status, "NON_SHIPPING_DEVELOPMENT_PAYLOAD_PROJECTION");
  assert.equal(receipt.shippingState, "PROHIBITED");
  assert.equal(receipt.payloadSHA256, sha256(payloadBytes));
  assert.equal(receipt.assetRequirementsSHA256, sha256(requirementBytes));
  assert.deepEqual(receipt.counts, {
    chapters: 1,
    arcs: 3,
    beats: 17,
    scenes: 17,
    interactions: 6,
    runtimeVisualBindings: 6,
    audioTimelines: 47,
    responsiveAudioPrograms: 6,
    provisionalResponsiveAudioPrograms: 6,
    placeholderResponsiveAudioPrograms: 0,
    narrationCues: 37,
    nonNarrationAudioCues: 181,
    hapticEvents: 19,
    accessibilitySpecs: 17,
    assetRequirements: 766,
  });
  assert.ok(receipt.claimsExcluded.includes("shipping approval"));
  assert.ok(receipt.claimsExcluded.includes("physical-device proof"));
  assert.ok(receipt.claimsExcluded.includes("finished responsive audio programs"));
  assert.equal(
    receipt.wireProof.interactiveAudioState,
    "SIX_PROVISIONAL_AUTHORED_PROGRAMS_WIRED_WITH_ZERO_REQUIREMENT_PLACEHOLDERS",
  );
});

test("Raise the House remains receipt-bound in the fully authored six-program projection", async () => {
  const [payload, longhouseWorkObject, requirements] = await Promise.all([
    readJSON(payloadPath),
    readJSON(longhouseWorkObjectPath),
    readJSON(requirementsPath),
  ]);
  const program = payload.responsiveAudioPrograms.find(({ scope }) =>
    scope.beatID === "beat-first-farmers-raise-longhouse");
  assert.deepEqual(program, longhouseWorkObject.responsiveProgram);
  assert.equal(program.id, "longhouse-responsive-audio-v1");
  assert.equal(program.interactionBeds.some(({ layerStates }) =>
    Object.values(layerStates).some((value) => value.startsWith("placeholder-"))), false);
  const remainingPlaceholders = payload.responsiveAudioPrograms.filter((candidate) =>
    candidate.interactionBeds.some(({ layerStates }) =>
      Object.values(layerStates).some((value) => value.startsWith("placeholder-"))));
  assert.deepEqual(remainingPlaceholders, []);

  const timelineIDs = new Set([
    program.approachTimelineID,
    ...program.interactionBeds.map(({ timelineID }) => timelineID),
    program.consequenceTimelineID,
  ]);
  const projectedTimelines = payload.audioTimelines.filter(({ id }) => timelineIDs.has(id));
  assert.equal(projectedTimelines.length, 5);
  assert.ok(projectedTimelines.every(({ events, haptics }) =>
    haptics.length === 0
      && events.some(({ role }) => role === "silence")
      && events.every(({ role }) => role !== "narration")));

  const longhouseRequirements = requirements.requirements.filter(({ sourceContract }) =>
    sourceContract === "LONGHOUSE_RESPONSIVE_AUDIO_WORK_OBJECT");
  assert.equal(longhouseRequirements.length, 15);
  assert.ok(longhouseRequirements.every(({ assetPath }) =>
    assetPath.startsWith("audio/first-farmers/longhouse-responsive-v1/")));
});

test("A Continent Remade replaces its placeholder with a source-bound authored Transform program", async () => {
  const [payload, workObject, requirements] = await Promise.all([
    readJSON(payloadPath),
    readJSON(continentRemadeWorkObjectPath),
    readJSON(requirementsPath),
  ]);
  const program = payload.responsiveAudioPrograms.find(({ scope }) =>
    scope.beatID === "beat-first-farmers-continent-remade");
  assert.deepEqual(program, workObject.responsiveProgram);
  assert.equal(program.id, "continent-remade-responsive-audio-v1");
  assert.deepEqual(program.scope, {
    chapterID: "first-farmers",
    arcID: "first-farmers-arc-03",
    beatID: "beat-first-farmers-continent-remade",
    interactionID: "interaction-first-farmers-a-continent-remade",
  });
  assert.equal(program.interactionBeds.some(({ layerStates }) =>
    Object.values(layerStates).some((value) => value.startsWith("placeholder-"))), false);

  const timelineIDs = new Set([
    program.approachTimelineID,
    ...program.interactionBeds.map(({ timelineID }) => timelineID),
    program.consequenceTimelineID,
  ]);
  const projectedTimelines = payload.audioTimelines.filter(({ id }) => timelineIDs.has(id));
  assert.equal(projectedTimelines.length, 5);
  assert.ok(projectedTimelines.every(({ events, haptics }) =>
    haptics.length === 0
      && events.some(({ role }) => role === "silence")
      && events.every(({ role }) => role !== "narration")));

  const authoredRequirements = requirements.requirements.filter(({ sourceContract }) =>
    sourceContract === "CONTINENT_REMADE_RESPONSIVE_AUDIO_WORK_OBJECT");
  assert.equal(authoredRequirements.length, 15);
  assert.ok(authoredRequirements.every(({ assetPath }) =>
    assetPath.startsWith("audio/first-farmers/continent-remade-responsive-v1/")));
});

test("More Mouths replaces its placeholder with the herd-bound settlement Transform program", async () => {
  const [payload, workObject, requirements] = await Promise.all([
    readJSON(payloadPath),
    readJSON(moreMouthsWorkObjectPath),
    readJSON(requirementsPath),
  ]);
  const program = payload.responsiveAudioPrograms.find(({ scope }) =>
    scope.beatID === "beat-first-farmers-more-mouths");
  assert.deepEqual(program, workObject.responsiveProgram);
  assert.equal(program.id, "more-mouths-responsive-audio-v1");
  assert.deepEqual(program.scope, {
    chapterID: "first-farmers",
    arcID: "first-farmers-arc-03",
    beatID: "beat-first-farmers-more-mouths",
    interactionID: "interaction-first-farmers-more-mouths-more-land",
  });
  assert.equal(program.interactionBeds.some(({ layerStates }) =>
    Object.values(layerStates).some((value) => value.startsWith("placeholder-"))), false);

  const timelineIDs = new Set([
    program.approachTimelineID,
    ...program.interactionBeds.map(({ timelineID }) => timelineID),
    program.consequenceTimelineID,
  ]);
  const projectedTimelines = payload.audioTimelines.filter(({ id }) => timelineIDs.has(id));
  assert.equal(projectedTimelines.length, 5);
  assert.ok(projectedTimelines.every(({ events, haptics }) =>
    haptics.length === 0
      && events.some(({ role }) => role === "silence")
      && events.every(({ role }) => role !== "narration")));

  const authoredRequirements = requirements.requirements.filter(({ sourceContract }) =>
    sourceContract === "MORE_MOUTHS_RESPONSIVE_AUDIO_WORK_OBJECT");
  assert.equal(authoredRequirements.length, 15);
  assert.ok(authoredRequirements.every(({ assetPath }) =>
    assetPath.startsWith("audio/first-farmers/more-mouths-responsive-v1/")));
});

test("Household Crosses replaces its placeholder with the source-bound crossing program", async () => {
  const [payload, workObject, requirements] = await Promise.all([
    readJSON(payloadPath),
    readJSON(householdCrossesWorkObjectPath),
    readJSON(requirementsPath),
  ]);
  const program = payload.responsiveAudioPrograms.find(({ scope }) =>
    scope.beatID === "beat-first-farmers-household-crosses");
  assert.deepEqual(program, workObject.responsiveProgram);
  assert.equal(program.id, "household-crosses-responsive-audio-v1");
  assert.deepEqual(program.scope, {
    chapterID: "first-farmers",
    arcID: "first-farmers-arc-01",
    beatID: "beat-first-farmers-household-crosses",
    interactionID: "interaction-first-farmers-a-household-crosses",
  });
  assert.equal(program.interactionBeds.some(({ layerStates }) =>
    Object.values(layerStates).some((value) => value.startsWith("placeholder-"))), false);

  const timelineIDs = new Set([
    program.approachTimelineID,
    ...program.interactionBeds.map(({ timelineID }) => timelineID),
    program.consequenceTimelineID,
  ]);
  const projectedTimelines = payload.audioTimelines.filter(({ id }) => timelineIDs.has(id));
  assert.equal(projectedTimelines.length, 5);
  assert.ok(projectedTimelines.every(({ events, haptics }) =>
    haptics.length === 0
      && events.some(({ role }) => role === "silence")
      && events.every(({ role }) => role !== "narration")));

  const authoredRequirements = requirements.requirements.filter(({ sourceContract }) =>
    sourceContract === "HOUSEHOLD_CROSSES_RESPONSIVE_AUDIO_WORK_OBJECT");
  assert.equal(authoredRequirements.length, 15);
  assert.ok(authoredRequirements.every(({ assetPath }) =>
    assetPath.startsWith("audio/first-farmers/household-crosses-responsive-v1/")));
});

test("Three Records projects its common-player causal mix without backstage production fields", async () => {
  const [payload, workObject, requirements] = await Promise.all([
    readJSON(payloadPath),
    readJSON(threeRecordsWorkObjectPath),
    readJSON(requirementsPath),
  ]);
  const program = payload.responsiveAudioPrograms.find(({ scope }) =>
    scope.beatID === "beat-first-farmers-three-records");
  assert.equal(program.id, "three-records-responsive-audio-v1");
  assert.deepEqual(program.scope, {
    chapterID: "first-farmers",
    arcID: "first-farmers-arc-02",
    beatID: "beat-first-farmers-three-records",
    interactionID: "interaction-first-farmers-at-the-iron-gates",
  });

  const expectedCausalMix = structuredClone(workObject.responsiveProgram.causalMix);
  for (const layer of expectedCausalMix.layers) {
    for (const phase of ["waiting", "engaged", "resistance"]) {
      layer.cueIDs[phase] = `${workObject.id}-${layer.cueIDs[phase]}`;
    }
  }
  assert.deepEqual(program.causalMix, expectedCausalMix);
  assert.deepEqual(
    program.causalMix.states.map(({ completedStageCount }) => completedStageCount),
    [0, 1, 2, 3],
  );
  assert.deepEqual(
    program.causalMix.states.map(({ layerGains }) => layerGains.map(({ gain }) => gain)),
    [
      [0.82, 0, 0, 0, 0, 0, 0],
      [0.82, 0.32, 0.28, 0.18, 0, 0, 0.14],
      [0.82, 0.42, 0.38, 0.28, 0.3, 0.24, 0.34],
      [0.82, 0.48, 0.44, 0.34, 0.4, 0.32, 0.42],
    ],
  );
  const publicMixKeys = new Set(deepKeys(program.causalMix));
  for (const backstageKey of [
    "schemaversion",
    "gainunit",
    "transportstatus",
    "stateid",
    "stageid",
    "consequencestate",
    "monotonicrule",
  ]) {
    assert.equal(publicMixKeys.has(backstageKey), false, `Backstage causal-mix field leaked: ${backstageKey}`);
  }

  const timelineIDs = new Set([
    program.approachTimelineID,
    ...program.interactionBeds.map(({ timelineID }) => timelineID),
    program.consequenceTimelineID,
  ]);
  const projectedTimelines = payload.audioTimelines.filter(({ id }) => timelineIDs.has(id));
  assert.equal(projectedTimelines.length, 5);
  assert.ok(projectedTimelines.every(({ events, haptics }) =>
    haptics.length === 0
      && events.every(({ role }) => role !== "narration" && role !== "silence")));
  const projectedAudioPaths = new Set(collectAssetPaths(projectedTimelines));
  assert.equal(projectedAudioPaths.size, 16);
  assert.ok([...projectedAudioPaths].every((assetPath) =>
    assetPath.startsWith("audio/first-farmers/three-records-responsive-v1/")));

  for (const layer of program.causalMix.layers) {
    for (const [phase, cueID] of Object.entries(layer.cueIDs)) {
      const bed = program.interactionBeds.find((candidate) => candidate.phase === phase);
      const timeline = projectedTimelines.find(({ id }) => id === bed.timelineID);
      const event = timeline.events.find((candidate) => candidate.cueID === cueID);
      assert.equal(event.assetPath, layer.assetPath);
      assert.equal(event.startSample, 0);
      assert.equal(event.durationSamples, 720_000);
    }
  }

  const authoredRequirements = requirements.requirements.filter(({ sourceContract }) =>
    sourceContract === "THREE_RECORDS_RESPONSIVE_AUDIO_WORK_OBJECT");
  assert.equal(authoredRequirements.length, 16);
  assert.deepEqual(
    new Set(authoredRequirements.map(({ assetPath }) => assetPath)),
    projectedAudioPaths,
  );
});

test("all seventeen scenes, thirty-seven manuscript cues and accessibility specs bind one exact chapter", async () => {
  const [payload, draft] = await Promise.all([
    readJSON(payloadPath),
    readJSON(draftPath),
  ]);
  const scopedBeats = draft.arcs.flatMap((arc) => arc.beats.map((beat) => ({
    arcID: arc.arcID,
    beat,
  })));
  const sceneByID = new Map(payload.scenes.map((scene) => [scene.id, scene]));
  const accessibilityByID = new Map(payload.accessibility.map((item) => [item.id, item]));
  const eventByCueID = new Map(
    payload.audioTimelines.flatMap(({ events }) => events)
      .filter(({ role }) => role === "narration")
      .map((event) => [event.cueID, event]),
  );

  assert.equal(sceneByID.size, 17);
  assert.equal(accessibilityByID.size, 17);
  assert.equal(eventByCueID.size, 37);
  for (const { arcID, beat } of scopedBeats) {
    const scene = sceneByID.get(beat.sceneID);
    const accessibilityID = `accessibility-${beat.beatID}`;
    assert.ok(scene, `Missing scene ${beat.sceneID}`);
    assert.equal(scene.accessibilityID, accessibilityID);
    assert.ok(accessibilityByID.has(accessibilityID));
    for (const segment of beat.narrative.segments) {
      const cueID = `narration-${segment.id}`;
      const event = eventByCueID.get(cueID);
      assert.ok(event, `Missing narration cue ${cueID}`);
      assert.deepEqual(event.narrationBinding.scope, {
        chapterID: "first-farmers",
        arcID,
        beatID: beat.beatID,
      });
      assert.equal(event.narrationBinding.manuscriptSegmentID, segment.id);
      assert.equal(event.narrationBinding.manuscriptSegmentSHA256, sha256(segment.text));
    }
    if (beat.interaction) {
      assert.equal(scene.interactionVisualBinding.grammar, beat.interaction.grammar);
      assert.equal(
        scene.interactionVisualBinding.configuration.interactionID,
        beat.interaction.id,
      );
      assert.ok(scene.interactionTargets.length > 0);
    } else {
      assert.equal(scene.interactionVisualBinding, undefined);
      assert.deepEqual(scene.interactionTargets, []);
    }
  }
});

test("Harvest reuses the Phase 1 SceneSpec and every other asset path is an explicit future requirement", async () => {
  const [payload, fixture, requirements] = await Promise.all([
    readJSON(payloadPath),
    readJSON(harvestFixturePath),
    readJSON(requirementsPath),
  ]);
  const harvest = payload.scenes.find(({ id }) => id === fixture.scene.id);
  const expectedHarvest = structuredClone(fixture.scene);
  expectedHarvest.accessibilityID = "accessibility-beat-first-farmers-harvest-allocation";
  assert.deepEqual(harvest, expectedHarvest);

  const harvestPaths = new Set(collectAssetPaths(fixture.scene));
  const payloadPaths = [...new Set(collectAssetPaths(payload))].sort();
  assert.deepEqual(
    requirements.requirements.map(({ assetPath }) => assetPath),
    payloadPaths,
  );
  assert.equal(requirements.status, "NON_SHIPPING_FUTURE_ASSET_REQUIREMENTS");
  assert.equal(requirements.shippingState, "PROHIBITED");
  assert.equal(
    requirements.activationRule,
    "EVERY_PATH_MUST_BE_REPLACED_BY_A_VERIFIED_PACKAGE_ASSET_AND_EVERY_INTERACTIVE_BEAT_MUST_BIND_A_PRODUCTION_AUTHORED_VALIDATED_RESPONSIVE_AUDIO_PROGRAM_BEFORE_COMPILATION",
  );
  for (const requirement of requirements.requirements) {
    assert.equal(requirement.state, "FUTURE_PRODUCTION_ASSET_NOT_PRESENT");
    assert.ok(!requirement.assetPath.startsWith("/"));
    assert.ok(!requirement.assetPath.includes(".."));
    if (harvestPaths.has(requirement.assetPath)) {
      assert.equal(requirement.sourceContract, "HARVEST_PHASE1_CONTRACT");
    } else if (requirement.sourceContract === "HARVEST_RESPONSIVE_AUDIO_WORK_OBJECT") {
      assert.ok(requirement.assetPath.startsWith("audio/first-farmers/harvest-responsive-v1/"));
    } else if (requirement.sourceContract === "LONGHOUSE_RESPONSIVE_AUDIO_WORK_OBJECT") {
      assert.ok(requirement.assetPath.startsWith("audio/first-farmers/longhouse-responsive-v1/"));
    } else if (requirement.sourceContract === "CONTINENT_REMADE_RESPONSIVE_AUDIO_WORK_OBJECT") {
      assert.ok(requirement.assetPath.startsWith("audio/first-farmers/continent-remade-responsive-v1/"));
    } else if (requirement.sourceContract === "MORE_MOUTHS_RESPONSIVE_AUDIO_WORK_OBJECT") {
      assert.ok(requirement.assetPath.startsWith("audio/first-farmers/more-mouths-responsive-v1/"));
    } else if (requirement.sourceContract === "HOUSEHOLD_CROSSES_RESPONSIVE_AUDIO_WORK_OBJECT") {
      assert.ok(requirement.assetPath.startsWith("audio/first-farmers/household-crosses-responsive-v1/"));
    } else if (requirement.sourceContract === "THREE_RECORDS_RESPONSIVE_AUDIO_WORK_OBJECT") {
      assert.ok(requirement.assetPath.startsWith("audio/first-farmers/three-records-responsive-v1/"));
    } else {
      assert.equal(requirement.sourceContract, "FIRST_FARMERS_PAYLOAD_PROJECTION");
      assert.ok(requirement.assetPath.startsWith("requirements/first-farmers/"));
    }
  }
});

test("canonical payload contains no backstage apparatus or academic regression", async () => {
  const payload = await readJSON(payloadPath);
  const forbiddenKeys = new Set([
    "sourceids",
    "sources",
    "evidence",
    "confidence",
    "historiography",
    "counterarguments",
    "methodology",
    "verifierfindings",
    "claimregister",
    "citations",
    "status",
    "shippingstate",
  ]);
  for (const key of deepKeys(payload)) {
    assert.equal(forbiddenKeys.has(key), false, `Backstage field leaked: ${key}`);
  }
  const publicText = JSON.stringify(payload).toLowerCase();
  for (const forbiddenPhrase of [
    "scholars debate",
    "historians disagree",
    "the picture is complex",
    "this account is contested",
    "from another perspective",
    "it is important to note",
  ]) {
    assert.equal(
      publicText.includes(forbiddenPhrase),
      false,
      `Academic regression leaked: ${forbiddenPhrase}`,
    );
  }
});

test("package validation fails closed on missing visual binding, narration drift, unsafe asset and backstage field", async () => {
  const canonical = await readJSON(payloadPath);

  const missingBinding = structuredClone(canonical);
  delete missingBinding.scenes.find(({ interactionVisualBinding }) => interactionVisualBinding)
    .interactionVisualBinding;
  assert.ok(
    validateContentPackagePayload(missingBinding)
      .some((issue) => issue.includes("requires an authored visual binding")),
  );

  const narrationDrift = structuredClone(canonical);
  const narration = narrationDrift.audioTimelines.flatMap(({ events }) => events)
    .find(({ role }) => role === "narration");
  narration.narrationBinding.manuscriptSegmentSHA256 = "0".repeat(64);
  assert.ok(
    validateContentPackagePayload(narrationDrift)
      .some((issue) => issue.includes("does not match editor-approved English manuscript bytes")),
  );

  const unsafeAsset = structuredClone(canonical);
  unsafeAsset.scenes[0].layers[0].assetPath = "../outside.heif";
  assert.ok(
    validateContentPackagePayload(unsafeAsset)
      .some((issue) => issue.includes("package-relative asset path required")),
  );

  const backstageLeak = structuredClone(canonical);
  backstageLeak.evidence = { status: "must-never-ship" };
  assert.ok(
    validateContentPackagePayload(backstageLeak)
      .some((issue) => issue.includes("evidence: unknown public field")),
  );

  const missingResponsiveProgram = structuredClone(canonical);
  missingResponsiveProgram.responsiveAudioPrograms.pop();
  assert.ok(
    validateContentPackagePayload(missingResponsiveProgram)
      .some((issue) => issue.includes("every interaction requires exactly one program")),
  );

  const wrongResponsiveScope = structuredClone(canonical);
  wrongResponsiveScope.responsiveAudioPrograms[0].scope.beatID = "wrong-beat";
  assert.ok(
    validateContentPackagePayload(wrongResponsiveScope)
      .some((issue) => issue.includes("every interaction requires exactly one program")),
  );

  const narrationInLoop = structuredClone(canonical);
  const waitingID = narrationInLoop.responsiveAudioPrograms[0]
    .interactionBeds.find(({ phase }) => phase === "waiting").timelineID;
  const waitingTimeline = narrationInLoop.audioTimelines.find(({ id }) => id === waitingID);
  waitingTimeline.events.push(structuredClone(
    narrationInLoop.audioTimelines.flatMap(({ events }) => events)
      .find(({ role }) => role === "narration"),
  ));
  waitingTimeline.events.at(-1).cueID = "illegal-loop-narration";
  assert.ok(
    validateContentPackagePayload(narrationInLoop)
      .some((issue) => issue.includes("indefinite interaction bed cannot contain narration")),
  );
});
