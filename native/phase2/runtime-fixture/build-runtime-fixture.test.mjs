import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

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
    "SINGLE_ATOMIC_FIVE_GRAMMAR_LAB_PACKAGE_WITH_UNREFERENCED_V26_PARTIAL_PASS_PROOF",
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
  assert.deepEqual(
    lineage.visualSources.map(({ labSceneID }) => labSceneID),
    lineage.labSceneIDs,
  );
  assert.deepEqual(
    lineage.audioDerivations.map(({ labSceneID }) => labSceneID),
    lineage.labSceneIDs,
  );

  const payload = JSON.parse(await readFile(
    path.join(
      fixtureRoot,
      "source/chapters/vertical-slice-development-v1.json",
    ),
    "utf8",
  ));
  const beats = payload.chapters.flatMap(({ arcs }) => arcs)
    .flatMap(({ beats }) => beats);
  assert.equal(beats.length, 5);
  assert.equal(payload.scenes.length, 6);
  assert.equal(payload.responsiveAudioPrograms.length, 5);
  assert.ok(payload.responsiveAudioPrograms.every(({ exitPolicy }) =>
    exitPolicy?.kind === "bounded-fade"
      && exitPolicy.durationSamples === 9_600));
  assert.equal(payload.audioTimelines.length, 25);
  assert.deepEqual(
    beats.map(({ interaction }) => interaction.grammar).sort(),
    [...experienceLab.requiredGrammars].sort(),
  );
  for (const expected of experienceLab.scenes) {
    const beat = beats.find(({ id }) => id === expected.beatID);
    const scene = payload.scenes.find(({ id }) => id === expected.labSceneID);
    assert.equal(beat?.sceneID, expected.labSceneID);
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
        .map(({ assetPath }) => assetPath),
    ).size,
    5,
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
