import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import {
  requireChapter01ReviewComposition,
  requireRepresentativeFirstFarmersResponsiveAudio,
  validateChapter01ReviewMatrix,
  validateChapter01ReviewNarrationManifest,
  validateChapter01ReviewRasterAssets,
  validateChapter01ReviewTransitionManifest,
  validateFirstFarmersResponsiveAudioCandidateReceipt,
} from "./build-runtime-fixture.mjs";
import { requireResponsiveAudioDecodedBufferBudget } from "../../tooling/src/compile.mjs";

const execFileAsync = promisify(execFile);
const fixtureRoot = path.dirname(fileURLToPath(import.meta.url));
const buildScript = path.join(fixtureRoot, "build-runtime-fixture.mjs");
const generatedRoots = [
  "source",
  "compiled",
  "backstage",
  "vertical-slice-development-trust-receipt.json",
  "fixture-lineage.json",
];

async function filesUnder(candidate) {
  const entries = await readdir(candidate, { withFileTypes: true }).catch(() => []);
  if (entries.length === 0) return [candidate];
  const files = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const child = path.join(candidate, entry.name);
    if (entry.isDirectory()) files.push(...await filesUnder(child));
    else if (entry.isFile()) files.push(child);
  }
  return files;
}

async function snapshot() {
  const files = [];
  for (const relative of generatedRoots) {
    files.push(...await filesUnder(path.join(fixtureRoot, relative)));
  }
  return Object.fromEntries(await Promise.all(files.sort().map(async (file) => {
    const bytes = await readFile(file);
    return [
      path.relative(fixtureRoot, file).split(path.sep).join("/"),
      createHash("sha256").update(bytes).digest("hex"),
    ];
  })));
}

function receiptMaterial(value) {
  const bytes = Buffer.from(`${JSON.stringify(value, null, 2)}\n`, "utf8");
  const digest = createHash("sha256").update(bytes).digest("hex");
  return { bytes, sidecar: `${digest}  render-receipt.json\n` };
}

test("responsive audio candidate authority fails closed", async () => {
  const receiptPath = path.join(
    fixtureRoot,
    "../../audio/score-soundscape/distribution-coding-v1/render-receipt.json",
  );
  const [bytes, sidecar] = await Promise.all([
    readFile(receiptPath),
    readFile(`${receiptPath}.sha256`, "utf8"),
  ]);
  const receipt = JSON.parse(bytes);
  const validated = validateFirstFarmersResponsiveAudioCandidateReceipt(
    receipt,
    bytes,
    sidecar,
  );
  assert.equal(validated.bySourcePath.size, 91);
  assert.equal(validated.candidatePaths.length, 91);
  assert.equal(validated.encodedBytes, 85_479_069);

  for (const mutation of [
    (candidate) => { candidate.outputs.pop(); },
    (candidate) => { candidate.shippingState = "APPROVED"; },
    (candidate) => { candidate.gates.physicalIPhoneEnergy = "PASS"; },
    (candidate) => {
      candidate.outputs[0].candidateRelativePath = "../escaped.m4a";
    },
  ]) {
    const candidate = structuredClone(receipt);
    mutation(candidate);
    const material = receiptMaterial(candidate);
    assert.throws(
      () => validateFirstFarmersResponsiveAudioCandidateReceipt(
        candidate,
        material.bytes,
        material.sidecar,
      ),
    );
  }
});

test("Chapter 01 review matrix fails closed", async () => {
  const matrix = JSON.parse(await readFile(
    path.join(fixtureRoot, "chapter-01-review-matrix.json"),
    "utf8",
  ));
  const validated = validateChapter01ReviewMatrix(matrix);
  assert.equal(validated.worldsByID.size, 6);
  assert.equal(validated.beatsByID.size, 17);
  assert.equal(validated.worldIDBySceneID.size, 17);
  for (const mutation of [
    (candidate) => { candidate.shippingAllowed = true; },
    (candidate) => { candidate.worlds.pop(); },
    (candidate) => { candidate.beats[0].worldID = "review-world-missing"; },
    (candidate) => { candidate.portraitContract.minimumEffectiveTargetPoints = 43; },
    (candidate) => { candidate.portraitContract.masterCanvasPixels.width = 393; },
    (candidate) => { candidate.portraitContract.baselineSourceRect.width = 1; },
    (candidate) => { candidate.portraitContract.transparentOverlayLayers.pop(); },
  ]) {
    const candidate = structuredClone(matrix);
    mutation(candidate);
    assert.throws(() => validateChapter01ReviewMatrix(candidate));
  }
});

test("Chapter 01 review transitions fail closed", async () => {
  const manifest = JSON.parse(await readFile(
    path.join(
      fixtureRoot,
      "../../audio/score-soundscape/chapter-01-review-transitions-v1/manifest.json",
    ),
    "utf8",
  ));
  const validated = validateChapter01ReviewTransitionManifest(manifest);
  assert.equal(validated.byTransitionID.size, 3);
  for (const mutation of [
    (candidate) => { candidate.shippingUsePermitted = true; },
    (candidate) => { candidate.transitions.pop(); },
    (candidate) => { candidate.transitions[0].audio.path = "../escaped.m4a"; },
    (candidate) => { candidate.transitions[1].audio.durationFrames = 0; },
  ]) {
    const candidate = structuredClone(manifest);
    mutation(candidate);
    assert.throws(() => validateChapter01ReviewTransitionManifest(candidate));
  }
});

test("runtime fixture generator is byte-for-byte reproducible", async () => {
  await execFileAsync(process.execPath, [buildScript]);
  const first = await snapshot();
  await execFileAsync(process.execPath, [buildScript]);
  const second = await snapshot();
  assert.deepEqual(second, first);
  const authority = JSON.parse(await readFile(
    path.join(fixtureRoot, "backstage/projection-authority.json"),
    "utf8",
  ));
  assert.equal(
    authority.status,
    "CODEX_PROVISIONAL_NON_SHIPPING_BLUEPRINT_PROJECTION",
  );
  assert.equal(authority.authority, "codex-local-production");
  assert.equal(Object.hasOwn(authority, "decisionReference"), false);
  const lineage = JSON.parse(await readFile(
    path.join(fixtureRoot, "fixture-lineage.json"),
    "utf8",
  ));
  assert.equal(
    lineage.status,
    "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_FIXTURE",
  );
  assert.equal(
    lineage.visualSourceStatus,
    "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_INPUT",
  );
  assert.equal(
    lineage.authorityShape,
    "CHAPTER_01_REVIEW_CANDIDATE_PLUS_EXISTING_SUPPORT_LABS",
  );
  assert.equal(lineage.milestone, "CHAPTER_01_REVIEW_READY");
  assert.equal(lineage.milestoneStatus, "CANDIDATE_PENDING_REVIEW_GATES");
  assert.deepEqual(lineage.chapterIDs, [
    "first-farmers",
    "europe-holds-the-line",
    "european-world",
  ]);
  const experienceLab = JSON.parse(await readFile(
    path.join(fixtureRoot, "../../phase1/experience-lab.json"),
    "utf8",
  ));
  assert.equal(experienceLab.status, "LOCKED_IMPLEMENTATION_SET");
  assert.deepEqual(
    lineage.labSceneIDs,
    experienceLab.scenes.map(({ labSceneID }) => labSceneID),
  );
  assert.deepEqual(
    lineage.interactionIDs,
    experienceLab.scenes.map(({ nativeInteractionID }) => nativeInteractionID),
  );
  assert.deepEqual(lineage.requiredGrammars, experienceLab.requiredGrammars);
  assert.equal(lineage.visualSources.length, 8);
  assert.equal(
    lineage.visualSources.filter(({ worldID }) => worldID).length,
    6,
  );
  assert.equal(
    new Set(lineage.visualSources.map(({ assetStemID }) => assetStemID)).size,
    8,
  );
  assert.equal(lineage.audioDerivations.length, 2);
  assert.equal(new Set(lineage.audioDerivations.map(({ sceneID }) => sceneID)).size, 2);
  assert.deepEqual(lineage.fullChapterProjection, {
    contentID: "first-farmers",
    arcCount: 3,
    beatCount: 17,
    interactionCount: 6,
    sceneCount: 17,
    accessibilityCount: 17,
    worldCount: 6,
    narrationCueCount: 37,
    audioTimelineCount: 47,
    transitionCount: 3,
    narrationState: "PROVISIONAL_NON_SHIPPING_REVIEW",
  });

  const payload = JSON.parse(await readFile(
    path.join(
      fixtureRoot,
      "source/chapters/vertical-slice-development-v1.json",
    ),
    "utf8",
  ));
  const beats = payload.chapters.flatMap(({ arcs }) => arcs)
    .flatMap(({ beats }) => beats);
  assert.equal(beats.length, 19);
  assert.equal(payload.scenes.length, 20);
  assert.equal(payload.responsiveAudioPrograms.length, 8);
  assert.ok(payload.responsiveAudioPrograms.every(({ exitPolicy }) =>
    exitPolicy?.kind === "bounded-fade"
      && exitPolicy.durationSamples === 9_600));
  assert.equal(payload.audioTimelines.length, 57);
  const firstFarmersChapter = payload.chapters.find(({ id }) =>
    id === "first-farmers");
  const firstFarmersMainTimelineIDs = new Set(
    firstFarmersChapter.arcs.flatMap(({ beats }) =>
      beats.map(({ id }) => `audio-${id}`)),
  );
  const timelineByID = new Map(payload.audioTimelines.map((timeline) => [
    timeline.id,
    timeline,
  ]));
  let narratedBedCueCount = 0;
  let transitionCueCount = 0;
  const narratedBedGainByRole = new Map([
    ["score", 0.26],
    ["soundscape", 0.38],
    ["spatialDetail", 0.34],
  ]);
  for (const timelineID of firstFarmersMainTimelineIDs) {
    const timeline = timelineByID.get(timelineID);
    assert.ok(timeline, `${timelineID}: projected main timeline is missing`);
    for (const event of timeline.events) {
      if (event.role === "narration") {
        assert.equal(event.gain, 1, `${event.cueID}: narration gain drifted`);
      } else if (event.cueID.startsWith("transition-")) {
        transitionCueCount += 1;
        assert.equal(
          event.gain,
          0.32,
          `${event.cueID}: stacked transition must remain below narration`,
        );
      } else {
        narratedBedCueCount += 1;
        assert.equal(
          event.gain,
          narratedBedGainByRole.get(event.role),
          `${event.cueID}: narrated bed gain drifted`,
        );
      }
    }
  }
  assert.equal(narratedBedCueCount, 17 * 3);
  assert.equal(transitionCueCount, 3);
  const responsiveAudio = requireRepresentativeFirstFarmersResponsiveAudio(payload);
  assert.deepEqual(responsiveAudio.programIDs, [
    "household-crosses-responsive-audio-v1",
    "harvest-responsive-audio-v1",
    "three-records-responsive-audio-v1",
    "longhouse-responsive-audio-v1",
    "more-mouths-responsive-audio-v1",
    "continent-remade-responsive-audio-v1",
  ]);
  assert.equal(responsiveAudio.timelineIDs.length, 30);
  assert.equal(responsiveAudio.assetPaths.length, 91);
  const generatedPayload = JSON.parse(await readFile(
    path.join(
      fixtureRoot,
      "../generated/first-farmers.content-package.json",
    ),
    "utf8",
  ));
  const generatedTimelineByID = new Map(
    generatedPayload.audioTimelines.map((timeline) => [timeline.id, timeline]),
  );
  for (const timelineID of responsiveAudio.timelineIDs) {
    assert.deepEqual(
      timelineByID.get(timelineID).events.map(({ cueID, gain }) => ({ cueID, gain })),
      generatedTimelineByID.get(timelineID).events
        .map(({ cueID, gain }) => ({ cueID, gain })),
      `${timelineID}: narrated-bed trim must not alter responsive interaction gains`,
    );
  }
  assert.deepEqual(responsiveAudio.decodedBufferEstimate, {
    steady: {
      bytes: 97_920_000,
      programID: "three-records-responsive-audio-v1",
      timelineID: "three-records-waiting-bed-v1",
    },
    transition: {
      bytes: 115_200_000,
      programID: "three-records-responsive-audio-v1",
      timelineIDs: Array(3).fill("three-records-waiting-bed-v1"),
    },
  });
  assert.deepEqual(
    requireResponsiveAudioDecodedBufferBudget(
      payload,
      97_920_000,
      115_200_000,
    ),
    responsiveAudio.decodedBufferEstimate,
  );
  assert.throws(
    () => requireResponsiveAudioDecodedBufferBudget(
      payload,
      97_919_999,
      200_000_000,
    ),
    /steady 97920000 bytes/u,
  );
  assert.throws(
    () => requireResponsiveAudioDecodedBufferBudget(
      payload,
      100_000_000,
      115_199_999,
    ),
    /transition 115200000 bytes/u,
  );
  assert.equal(
    payload.responsiveAudioPrograms.find(
      ({ id }) => id === "three-records-responsive-audio-v1",
    ).causalMix.layers.length,
    7,
  );
  assert.deepEqual(
    payload.responsiveAudioPrograms.find(
      ({ id }) => id === "more-mouths-responsive-audio-v1",
    )?.scope,
    {
      chapterID: "first-farmers",
      arcID: "first-farmers-arc-03",
      beatID: "beat-first-farmers-more-mouths",
      interactionID: "interaction-first-farmers-more-mouths-more-land",
    },
  );
  const firstFarmers = payload.chapters.find(({ id }) => id === "first-farmers");
  const firstFarmersBeats = firstFarmers.arcs.flatMap(({ beats }) => beats);
  assert.equal(firstFarmers.arcs.length, 3);
  assert.equal(firstFarmersBeats.length, 17);
  assert.equal(firstFarmersBeats.filter(({ interaction }) => interaction).length, 6);
  assert.equal(
    new Set(firstFarmersBeats.flatMap(({ narrationCueIDs }) =>
      narrationCueIDs)).size,
    37,
  );
  const reviewMatrix = JSON.parse(await readFile(
    path.join(fixtureRoot, "chapter-01-review-matrix.json"),
    "utf8",
  ));
  const reviewWorldIndex = validateChapter01ReviewMatrix(reviewMatrix);
  const rasterMasters = await validateChapter01ReviewRasterAssets(
    reviewWorldIndex,
    { root: path.join(fixtureRoot, "source"), requireFullDerivationSet: false },
  );
  assert.deepEqual(rasterMasters.masterCanvasPixels, {
    width: 1179,
    height: 2556,
  });
  assert.equal(rasterMasters.authoredOverscanFraction, 0.15);
  assert.deepEqual(rasterMasters.baselineSourceRect, {
    x: 0.15,
    y: 0.15,
    width: 0.7,
    height: 0.7,
  });
  assert.equal(rasterMasters.worlds.length, 6);
  for (const world of rasterMasters.worlds) {
    assert.deepEqual(
      world.semanticLayers.map(({ suffix }) => suffix),
      ["background", "midground", "foreground", "mechanism-light"],
    );
    assert.equal(
      new Set(world.semanticLayers.map(({ sha256 }) => sha256)).size,
      4,
    );
    assert.ok(world.semanticLayers.slice(1).every(({ colorType, alphaRange }) =>
      colorType === 6
        && alphaRange.minimum === 0
        && alphaRange.maximum === 255));
  }
  assert.deepEqual(
    requireChapter01ReviewComposition(payload, reviewMatrix),
    {
      arcCount: 3,
      beatCount: 17,
      interactionCount: 6,
      worldCount: 6,
      narrationCueCount: 37,
      timelineCount: 47,
      transitionCount: 3,
    },
  );
  const reviewBeatByID = new Map(reviewMatrix.beats.map((beat) => [beat.beatID, beat]));
  const reviewWorldByID = new Map(reviewMatrix.worlds.map((world) => [world.id, world]));
  for (const beat of firstFarmersBeats) {
    const scene = payload.scenes.find(({ id }) => id === beat.sceneID);
    const binding = reviewBeatByID.get(beat.id);
    const world = reviewWorldByID.get(binding.worldID);
    assert.deepEqual(scene.sceneCanvas.canvas, { width: 1179, height: 2556 });
    assert.deepEqual(
      scene.reduceMotionComposition.canvas,
      { width: 1179, height: 2556 },
    );
    const staticUnderlay = scene.reduceMotionComposition.strata.find(
      ({ kind }) => kind === "staticPlate",
    );
    if (beat.interaction) {
      assert.equal(
        staticUnderlay.assetPath,
        `assets/${binding.worldID}-reduce-motion-state-before.png`,
      );
      const stateLayerIDs = scene.layers
        .filter(({ stateVariants }) => stateVariants.length > 0)
        .map(({ id }) => id);
      const reduceMotionStateLayerIDs = scene.reduceMotionComposition.strata
        .filter(({ kind }) => kind === "stateOverlay")
        .map(({ layerID }) => layerID);
      assert.ok(stateLayerIDs.every((id) => reduceMotionStateLayerIDs.includes(id)));
    } else {
      const stateIndex = world.interactionStateIDs.indexOf(binding.stateVariant);
      const stateProgress = stateIndex / (world.interactionStateIDs.length - 1);
      const suffix = stateProgress <= 0.25
        ? "state-before"
        : stateProgress >= 0.75
          ? "state-completed"
          : "state-active";
      assert.equal(
        scene.layers.find(({ id }) => id === "review-state-consequence")
          ?.assetPath,
        `assets/${binding.worldID}-${suffix}.png`,
      );
      assert.equal(
        staticUnderlay.assetPath,
        `assets/${binding.worldID}-reduce-motion-${suffix}.png`,
      );
    }
  }
  const moreMouths = firstFarmersBeats.find(
    ({ id }) => id === "beat-first-farmers-more-mouths",
  );
  assert.equal(moreMouths?.sceneID, "scene-first-farmers-settlement-growth");
  assert.equal(
    moreMouths?.interaction?.accessibilityID,
    "accessibility-beat-first-farmers-more-mouths",
  );
  assert.deepEqual(moreMouths?.interaction?.configuration?.stages, [
    { id: "new-hearths", controlID: "settlement-pressure", requiredAmount: 0.32 },
    { id: "field-edges", controlID: "settlement-pressure", requiredAmount: 0.66 },
    {
      id: "herd-lanes-and-daughters",
      controlID: "settlement-pressure",
      requiredAmount: 1,
    },
  ]);
  const moreMouthsScene = payload.scenes.find(
    ({ id }) => id === "scene-first-farmers-settlement-growth",
  );
  assert.equal(
    moreMouthsScene?.accessibilityID,
    "accessibility-beat-first-farmers-more-mouths",
  );
  assert.deepEqual(
    moreMouthsScene?.interactionVisualBinding?.configuration?.stages.map(
      ({ stageID }) => stageID,
    ),
    ["new-hearths", "field-edges", "herd-lanes-and-daughters"],
  );
  assert.deepEqual(
    moreMouthsScene?.interactionTargets.map(({ interactionTargetID }) =>
      interactionTargetID),
    [
      "stage-new-hearths-target",
      "stage-field-edges-target",
      "stage-herd-lanes-and-daughters-target",
    ],
  );
  const moreMouthsAccessibility = payload.accessibility.find(
    ({ id }) => id === "accessibility-beat-first-farmers-more-mouths",
  );
  assert.deepEqual(
    moreMouthsAccessibility?.elements
      .filter(({ role }) => role === "adjustable")
      .map(({ id, actions }) => ({ id, token: actions[0]?.token })),
    [
      {
        id: "transform-new-hearths",
        token: {
          command: "advance-transform",
          targetID: "new-hearths",
          step: 0.32,
        },
      },
      {
        id: "transform-field-edges",
        token: {
          command: "advance-transform",
          targetID: "field-edges",
          step: 0.66,
        },
      },
      {
        id: "transform-herd-lanes-and-daughters",
        token: {
          command: "advance-transform",
          targetID: "herd-lanes-and-daughters",
          step: 1,
        },
      },
    ],
  );
  const technicalAssetStemID = "lab-first-farmers-land-transformation";
  const stateAssetStemID = "review-world-longhouse-settlement";
  const stageMaskPaths = [
    `assets/${technicalAssetStemID}-stage-new-hearths-alpha.png`,
    `assets/${technicalAssetStemID}-stage-field-edges-alpha.png`,
    `assets/${technicalAssetStemID}-stage-herd-lanes-and-daughters-alpha.png`,
  ];
  const stageLayers = moreMouthsScene.layers.filter(({ id }) =>
    id.startsWith("stage-"));
  assert.deepEqual(
    stageLayers.map(({ masks }) => masks.alphaMaskAssetPath),
    stageMaskPaths,
  );
  assert.equal(new Set(stageMaskPaths).size, 3);
  for (const [index, layer] of stageLayers.entries()) {
    assert.equal(
      layer.assetPath,
      `assets/${stateAssetStemID}-state-before.png`,
    );
    assert.deepEqual(
      layer.stateVariants.map(({ id, assetPath, masks }) => ({
        id,
        assetPath,
        alphaMaskAssetPath: masks.alphaMaskAssetPath,
      })),
      [
        {
          id: "before",
          assetPath: `assets/${stateAssetStemID}-state-before.png`,
          alphaMaskAssetPath: stageMaskPaths[index],
        },
        {
          id: "active",
          assetPath: `assets/${stateAssetStemID}-state-active.png`,
          alphaMaskAssetPath: stageMaskPaths[index],
        },
        {
          id: "completed",
          assetPath: `assets/${stateAssetStemID}-state-completed.png`,
          alphaMaskAssetPath: stageMaskPaths[index],
        },
      ],
    );
  }
  for (const [layerID, suffix] of [
    ["far-landscape", "background"],
    ["inhabited-world", "midground"],
    ["foreground-occlusion", "foreground"],
    ["mechanism-light", "mechanism-light"],
  ]) {
    const layer = moreMouthsScene.layers.find(({ id }) => id === layerID);
    assert.equal(layer?.assetPath, `assets/${stateAssetStemID}-${suffix}.png`);
  }
  assert.deepEqual(
    moreMouthsScene.reduceMotionComposition.strata,
    [
      {
        id: "static-underlay",
        kind: "staticPlate",
        assetPath: `assets/${stateAssetStemID}-reduce-motion-state-before.png`,
      },
      {
        id: "stage-new-hearths-state",
        kind: "stateOverlay",
        layerID: "stage-new-hearths",
      },
      {
        id: "stage-field-edges-state",
        kind: "stateOverlay",
        layerID: "stage-field-edges",
      },
      {
        id: "stage-herd-lanes-and-daughters-state",
        kind: "stateOverlay",
        layerID: "stage-herd-lanes-and-daughters",
      },
      {
        id: "static-foreground",
        kind: "staticPlate",
        assetPath: `assets/${stateAssetStemID}-reduce-motion-foreground.png`,
      },
      {
        id: "static-mechanism-light",
        kind: "staticPlate",
        assetPath: `assets/${stateAssetStemID}-reduce-motion-mechanism-light.png`,
      },
    ],
  );
  assert.deepEqual(lineage.moreMouthsTechnicalLiveSlice, {
    status: "CODEX_PROVISIONAL_NON_SHIPPING_CAUSAL_STATE_PROOF",
    shippingState: "PROHIBITED",
    beatID: "beat-first-farmers-more-mouths",
    sceneID: "scene-first-farmers-settlement-growth",
    accessibilityID: "accessibility-beat-first-farmers-more-mouths",
    interactionID: "interaction-first-farmers-more-mouths-more-land",
    technicalAssetStemID,
    stateAssetStemID,
    semanticLayers: lineage.moreMouthsTechnicalLiveSlice.semanticLayers,
    stageMasks: lineage.moreMouthsTechnicalLiveSlice.stageMasks,
    statePurpose:
      "VERIFY_VISIBLE_ORDERED_TRANSFORM_RESPONSE_AND_PERSISTENCE_ON_DEVICE",
    productionArtAuthority: "NONE",
    claimsExcluded: [
      "production art",
      "historical visual finish",
      "artistic approval",
      "shipping asset approval",
    ],
  });
  assert.deepEqual(
    lineage.moreMouthsTechnicalLiveSlice.semanticLayers.map(
      ({ suffix, packageAssetPath }) => ({ suffix, packageAssetPath }),
    ),
    [
      "background",
      "midground",
      "foreground",
      "mechanism-light",
    ].map((suffix) => ({
      suffix,
      packageAssetPath: `assets/${stateAssetStemID}-${suffix}.png`,
    })),
  );
  assert.equal(new Set(
    lineage.moreMouthsTechnicalLiveSlice.semanticLayers.map(({ sha256 }) => sha256),
  ).size, 4);
  assert.deepEqual(
    lineage.moreMouthsTechnicalLiveSlice.stageMasks.map(
      ({ stageID, pixelBounds, packageAssetPath }) => ({
        stageID,
        pixelBounds,
        packageAssetPath,
      }),
    ),
    [
      {
        stageID: "new-hearths",
        pixelBounds: { x: 92, y: 350, width: 82, height: 170 },
        packageAssetPath: stageMaskPaths[0],
      },
      {
        stageID: "field-edges",
        pixelBounds: { x: 157, y: 318, width: 92, height: 240 },
        packageAssetPath: stageMaskPaths[1],
      },
      {
        stageID: "herd-lanes-and-daughters",
        pixelBounds: { x: 223, y: 285, width: 105, height: 310 },
        packageAssetPath: stageMaskPaths[2],
      },
    ],
  );
  assert.equal(
    new Set(lineage.moreMouthsTechnicalLiveSlice.stageMasks.map(({ sha256 }) =>
      sha256)).size,
    3,
  );
  assert.deepEqual(
    [...new Set(beats.flatMap(({ interaction }) => interaction ? [interaction.grammar] : []))].sort(),
    [...experienceLab.requiredGrammars].sort(),
  );
  for (const expected of experienceLab.scenes) {
    const beat = expected.contentID === "first-farmers"
      ? beats.find(({ interaction }) =>
        interaction?.id === expected.nativeInteractionID)
      : beats.find(({ id }) => id === expected.beatID);
    const expectedSceneID = beat?.sceneID ?? expected.labSceneID;
    const scene = payload.scenes.find(({ id }) => id === expectedSceneID);
    assert.equal(beat?.sceneID, expectedSceneID);
    assert.equal(beat?.interaction?.id, expected.nativeInteractionID);
    assert.equal(beat?.interaction?.grammar, expected.grammar);
    assert.deepEqual(
      beat?.interaction?.completionEffects?.map(({ id }) => id),
      [expected.worldEffectID],
    );
    assert.equal(scene?.interactionVisualBinding?.grammar, expected.grammar);
  }
  const proof = payload.scenes.find(
    ({ id }) => id === "lab-first-farmers-harvest-v26-parallax-proof",
  );
  assert.ok(proof);
  assert.equal(beats.some(({ sceneID }) => sceneID === proof.id), false);
  assert.equal(Object.hasOwn(proof, "interactionVisualBinding"), false);
  assert.deepEqual(proof.interactionTargets, []);
  assert.deepEqual(proof.atmosphere, []);
  assert.deepEqual(
    proof.layers.map(({ id }) => id),
    ["diagnostic-underlay", "people", "grain", "foreground"],
  );
  assert.deepEqual(
    proof.layers.map(({ order }) => order),
    [0, 1, 2, 3],
  );
  assert.deepEqual(
    proof.layers.flatMap(({ stateVariants }) => stateVariants),
    [],
  );
  assert.deepEqual(
    proof.layers.slice(1).map(({ masks }) => masks.alphaMaskAssetPath),
    [
      "assets/harvest-v26-parallax-alpha-people.png",
      "assets/harvest-v26-parallax-alpha-grain.png",
      "assets/harvest-v26-parallax-alpha-foreground.png",
    ],
  );
  assert.deepEqual(proof.reduceMotionComposition.strata, [{
    id: "frozen-static-crop",
    kind: "staticPlate",
    assetPath: "assets/harvest-v26-parallax-reduce-motion-static.png",
  }]);
  assert.equal(
    lineage.runtimeVisualProof.status,
    "CODEX_PROVISIONAL_NON_SHIPPING_V26_PARTIAL_PASS_RUNTIME_PROOF",
  );
  assert.equal(lineage.runtimeVisualProof.shippingState, "PROHIBITED");
  assert.deepEqual(
    lineage.runtimeVisualProof.passedScope,
    ["people", "grain", "foreground"],
  );
  assert.deepEqual(
    lineage.runtimeVisualProof.alphaMasksBackToFront.map(({ sha256 }) => sha256),
    [
      "eb60fffa4ad4bd8a87ebe7165117423a7d6a7baa7c57e873cd9a37671cf4bc59",
      "972e9e1f867c9d8e178c7ed1b38b4629b7175c609a30f1ac11d8014f68d810a6",
      "8f6332a7ee341e6075c05493e37f5fae68fa5950eef55a0b3727fce659542b58",
    ],
  );
  assert.equal(
    lineage.runtimeVisualProof.reduceMotionStatic.sha256,
    "64bb283bbd37e66502fef198d508af8618f6032fa6edac9558bcb34e7c6199a8",
  );
  assert.equal(
    new Set(
      payload.audioTimelines.flatMap(({ events }) => events)
        .filter(({ role }) => role !== "silence")
        .map(({ assetPath }) => assetPath),
    ).size,
    133,
  );
  const narrationManifest = JSON.parse(await readFile(
    path.join(
      fixtureRoot,
      "../../audio/narration/review/chapter-01/manifest.json",
    ),
    "utf8",
  ));
  const validatedNarration = validateChapter01ReviewNarrationManifest(
    narrationManifest,
  );
  assert.equal(validatedNarration.byCueID.size, 37);
  const transitionManifest = JSON.parse(await readFile(
    path.join(
      fixtureRoot,
      "../../audio/score-soundscape/chapter-01-review-transitions-v1/manifest.json",
    ),
    "utf8",
  ));
  const validatedTransitions = validateChapter01ReviewTransitionManifest(
    transitionManifest,
  );
  assert.equal(validatedTransitions.byTransitionID.size, 3);
  assert.equal(lineage.chapter01Review.status, "NON_SHIPPING_REVIEW");
  assert.equal(lineage.chapter01Review.shippingState, "PROHIBITED");
  assert.equal(
    lineage.chapter01Review.milestoneStatus,
    "CANDIDATE_PENDING_REVIEW_GATES",
  );
  assert.equal(lineage.chapter01Review.worldIDs.length, 6);
  assert.equal(lineage.chapter01Review.beatBindings.length, 17);
  assert.deepEqual(lineage.chapter01Review.rasterMasters.masterCanvasPixels, {
    width: 1179,
    height: 2556,
  });
  assert.equal(lineage.chapter01Review.rasterMasters.worlds.length, 6);
  assert.ok(lineage.chapter01Review.rasterMasters.worlds.every(({ semanticLayers }) =>
    semanticLayers.length === 4
      && new Set(semanticLayers.map(({ sha256 }) => sha256)).size === 4));
  assert.equal(lineage.chapter01Review.narration.cueCount, 37);
  assert.equal(lineage.chapter01Review.narration.cues.length, 37);
  assert.equal(lineage.chapter01Review.transitions.transitionCount, 3);
  assert.equal(lineage.chapter01Review.transitions.items.length, 3);
  assert.equal(
    lineage.chapter01Review.narration.combinedBindingSHA256,
    "1e07b4bc34a95f2326856e2962c80e76f1bff68b05eba027c093f48978e84c6f",
  );
  assert.equal(lineage.responsiveAudioCandidate.status, "PROVISIONAL_NON_SHIPPING");
  assert.equal(lineage.responsiveAudioCandidate.shippingState, "PROHIBITED");
  assert.equal(lineage.responsiveAudioCandidate.candidateAssetCount, 91);
  assert.equal(lineage.responsiveAudioCandidate.candidateEncodedBytes, 85_479_069);
  assert.equal(lineage.responsiveAudioCandidate.timelineCount, 30);
  assert.deepEqual(
    lineage.responsiveAudioCandidate.decodedBufferEstimate,
    responsiveAudio.decodedBufferEstimate,
  );
  assert.equal(lineage.responsiveAudioCandidate.audioApproval, "OPEN");
  assert.equal(lineage.responsiveAudioCandidate.editorApproval, "OPEN");
  assert.equal(lineage.responsiveAudioCandidate.physicalIPhonePlayback, "OPEN");
  assert.equal(lineage.responsiveAudioCandidate.physicalIPhoneEnergy, "OPEN");
  assert.equal(lineage.responsiveAudioCandidate.shippingApproval, "PROHIBITED");
  assert.equal(lineage.responsiveAudioCandidate.fixtureUse, "NON_SHIPPING_LIVE_TEST_ONLY");

  const candidateReceipt = JSON.parse(await readFile(
    path.join(
      fixtureRoot,
      "../../audio/score-soundscape/distribution-coding-v1/render-receipt.json",
    ),
    "utf8",
  ));
  const manifest = JSON.parse(await readFile(
    path.join(
      fixtureRoot,
      "compiled/vertical-slice-development-v1.runtimefixture/package-manifest.json",
    ),
    "utf8",
  ));
  const manifestByPath = new Map(manifest.files.map((record) => [record.path, record]));
  for (const assetPath of [
    ...[
      "background",
      "midground",
      "foreground",
      "mechanism-light",
      "reduce-motion-state-before",
      "reduce-motion-foreground",
      "reduce-motion-mechanism-light",
    ].map((suffix) => `assets/${stateAssetStemID}-${suffix}.png`),
    ...stageMaskPaths,
  ]) {
    assert.ok(manifestByPath.has(assetPath), assetPath);
  }
  assert.equal(candidateReceipt.outputs.length, 91);
  assert.deepEqual(
    responsiveAudio.assetPaths,
    candidateReceipt.outputs.map(({ candidateRelativePath }) =>
      candidateRelativePath).sort(),
  );
  for (const output of candidateReceipt.outputs) {
    assert.deepEqual(manifestByPath.get(output.candidateRelativePath), {
      path: output.candidateRelativePath,
      bytes: output.bytes,
      sha256: output.sha256,
    });
  }
  for (const cue of narrationManifest.cues) {
    const packagePath =
      `audio/first-farmers/review-narration/${path.basename(cue.repositoryPath)}`;
    assert.deepEqual(manifestByPath.get(packagePath), {
      path: packagePath,
      bytes: cue.bytes,
      sha256: cue.sha256,
    });
  }
  for (const transition of transitionManifest.transitions) {
    const packagePath =
      `audio/first-farmers/review-transitions/${path.basename(transition.audio.path)}`;
    assert.deepEqual(manifestByPath.get(packagePath), {
      path: packagePath,
      bytes: transition.audio.bytes,
      sha256: transition.audio.sha256,
    });
  }
  const missingProgram = structuredClone(payload);
  missingProgram.responsiveAudioPrograms = missingProgram.responsiveAudioPrograms
    .filter(({ id }) => id !== "three-records-responsive-audio-v1");
  assert.throws(
    () => requireRepresentativeFirstFarmersResponsiveAudio(missingProgram),
    /six authored First Farmers programs/u,
  );
  const decodedBoundDrift = structuredClone(payload);
  for (const timeline of decodedBoundDrift.audioTimelines) {
    if (!/^three-records-(waiting|engaged|resistance)-bed-v1$/u.test(timeline.id)) {
      continue;
    }
    for (const event of timeline.events) event.durationSamples -= 1;
  }
  assert.throws(
    () => requireRepresentativeFirstFarmersResponsiveAudio(decodedBoundDrift),
    /decoded-buffer bounds drifted/u,
  );
  assert.ok(lineage.claimsExcluded.includes("editor approval"));
  assert.ok(lineage.claimsExcluded.includes("production visual approval"));
  for (const claim of [
    "clean-plate approval",
    "complete layer DAG",
    "state-variant approval",
    "production-master approval",
    "complete-scene approval",
    "artistic approval",
    "shipping asset approval",
  ]) {
    assert.ok(lineage.claimsExcluded.includes(claim), claim);
  }
});
