import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import {
  requireRepresentativeFirstFarmersResponsiveAudio,
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
    "FULL_FIRST_FARMERS_LIVE_TEST_PLUS_FIVE_GRAMMAR_LAB_WITH_UNREFERENCED_V26_PARTIAL_PASS_PROOF",
  );
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
  assert.equal(lineage.visualSources.length, 19);
  assert.equal(new Set(lineage.visualSources.map(({ sceneID }) => sceneID)).size, 19);
  assert.equal(lineage.audioDerivations.length, 2);
  assert.equal(new Set(lineage.audioDerivations.map(({ sceneID }) => sceneID)).size, 2);
  assert.deepEqual(lineage.fullChapterProjection, {
    contentID: "first-farmers",
    arcCount: 3,
    beatCount: 17,
    interactionCount: 6,
    sceneCount: 17,
    accessibilityCount: 17,
    narrationState: "EXCLUDED_PENDING_EDITOR_APPROVAL",
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
  assert.equal(payload.audioTimelines.length, 40);
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
  assert.equal(firstFarmersBeats.every(({ narrationCueIDs }) => narrationCueIDs.length === 0), true);
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
  const transparentTechnicalPlate =
    `assets/${technicalAssetStemID}-technical-transparent.png`;
  const transparentReduceMotionPlate =
    `assets/${technicalAssetStemID}-technical-reduce-motion-foreground.png`;
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
      `assets/${technicalAssetStemID}-base.png`,
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
          assetPath: `assets/${technicalAssetStemID}-base.png`,
          alphaMaskAssetPath: stageMaskPaths[index],
        },
        {
          id: "active",
          assetPath: `assets/${technicalAssetStemID}-state-active.png`,
          alphaMaskAssetPath: stageMaskPaths[index],
        },
        {
          id: "completed",
          assetPath: `assets/${technicalAssetStemID}-state-completed.png`,
          alphaMaskAssetPath: stageMaskPaths[index],
        },
      ],
    );
  }
  for (const layerID of [
    "inhabited-world",
    "foreground-occlusion",
    "mechanism-light",
  ]) {
    const layer = moreMouthsScene.layers.find(({ id }) => id === layerID);
    assert.equal(layer?.assetPath, transparentTechnicalPlate);
    assert.deepEqual(layer?.masks, {});
  }
  assert.deepEqual(
    moreMouthsScene.reduceMotionComposition.strata,
    [
      {
        id: "static-underlay",
        kind: "staticPlate",
        assetPath: `assets/${technicalAssetStemID}-reduce-motion-underlay.png`,
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
        assetPath: transparentReduceMotionPlate,
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
    transparentOcclusionPlate:
      lineage.moreMouthsTechnicalLiveSlice.transparentOcclusionPlate,
    transparentReduceMotionForeground:
      lineage.moreMouthsTechnicalLiveSlice.transparentReduceMotionForeground,
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
  assert.equal(
    lineage.moreMouthsTechnicalLiveSlice.transparentOcclusionPlate
      .packageAssetPath,
    transparentTechnicalPlate,
  );
  assert.equal(
    lineage.moreMouthsTechnicalLiveSlice.transparentReduceMotionForeground
      .packageAssetPath,
    transparentReduceMotionPlate,
  );
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
    const canonicalMoreMouths = expected.nativeInteractionID
      === "interaction-first-farmers-more-mouths-more-land";
    const expectedBeatID = canonicalMoreMouths
      ? "beat-first-farmers-more-mouths"
      : expected.beatID;
    const expectedSceneID = canonicalMoreMouths
      ? "scene-first-farmers-settlement-growth"
      : expected.labSceneID;
    const beat = beats.find(({ id }) => id === expectedBeatID);
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
    93,
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
    transparentTechnicalPlate,
    transparentReduceMotionPlate,
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
