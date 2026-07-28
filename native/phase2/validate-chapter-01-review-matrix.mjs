import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

const matrixRelativePath = "native/phase2/runtime-fixture/chapter-01-review-matrix.json";

const expectedWorldBeats = new Map([
  ["review-world-iron-gates-danube", [
    "beat-first-farmers-river-world",
    "beat-first-farmers-inhabited-frontier",
    "beat-first-farmers-gorge-contact",
    "beat-first-farmers-three-records",
    "beat-first-farmers-frontier-consequence",
  ]],
  ["review-world-aegean-crossing", ["beat-first-farmers-household-crosses"]],
  ["review-world-thessaly-first-field", [
    "beat-first-farmers-living-system",
    "beat-first-farmers-european-ground",
  ]],
  ["review-world-harvest-store", [
    "beat-first-farmers-harvest-allocation",
    "beat-first-farmers-stored-future",
  ]],
  ["review-world-longhouse-settlement", [
    "beat-first-farmers-raise-longhouse",
    "beat-first-farmers-plot-remains",
    "beat-first-farmers-paternal-lines",
    "beat-first-farmers-more-mouths",
    "beat-first-farmers-growth-breaks",
  ]],
  ["review-world-european-farming-belt", [
    "beat-first-farmers-continent-remade",
    "beat-first-farmers-before-steppe",
  ]],
]);

const stableID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

function interactionStateIDs(interaction) {
  if (interaction.grammar === "trace") return interaction.anchors.map(({ id }) => id);
  if (interaction.grammar === "transform") return interaction.stages.map(({ id }) => id);
  if (interaction.grammar === "assemble") {
    return interaction.components.map(({ id }) => `${id}-placed`);
  }
  if (interaction.grammar === "allocate") return ["unallocated", "allocating", "committed"];
  return [];
}

export async function validateChapter01ReviewMatrix({ repositoryRoot, matrix } = {}) {
  assert.ok(repositoryRoot, "Chapter 01 review-matrix validation requires the repository root");
  const root = path.resolve(repositoryRoot);
  const matrixPath = path.resolve(root, matrixRelativePath);
  const record = matrix ?? JSON.parse(await readFile(matrixPath, "utf8"));

  assert.equal(record.schemaVersion, 1, "Chapter 01 review matrix schema drifted");
  assert.equal(record.matrixID, "chapter-01-review-matrix-v1", "Chapter 01 review matrix ID drifted");
  assert.equal(record.milestone, "CHAPTER_01_REVIEW_READY", "Chapter 01 review milestone drifted");
  assert.equal(record.status, "NON_SHIPPING_REVIEW", "Chapter 01 matrix escaped its review boundary");
  assert.equal(record.shippingAllowed, false, "Chapter 01 review worlds cannot ship");
  assert.equal(record.chapterID, "first-farmers", "Chapter 01 matrix changed chapter");
  assert.equal(record.publicContentSchemaMutation, false, "Review-world mapping cannot enter public content");
  assert.equal(record.sourceDraft.path,
    "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json");

  const draftPath = path.resolve(root, record.sourceDraft.path);
  const draftBytes = await readFile(draftPath);
  assert.equal(sha256(draftBytes), record.sourceDraft.sha256, "Chapter 01 review matrix draft hash drifted");
  const draft = JSON.parse(draftBytes.toString("utf8"));
  assert.equal(draft.status, "CHAPTER_01_REVIEW_TEXT_FROZEN", "Review matrix requires the frozen manuscript");

  assert.deepEqual(record.portraitContract.layers, [
    "background",
    "inhabited-material-midground",
    "foreground",
    "mechanism-light",
  ], "Every review world must use the shared four-layer grammar");
  assert.deepEqual(record.portraitContract.transparentOverlayLayers, [
    "inhabited-material-midground",
    "foreground",
    "mechanism-light",
  ], "Review depth layers must be transparent overlays, not cloned plates");
  assert.equal(record.portraitContract.orientation, "portrait");
  assert.equal(record.portraitContract.overscanRequired, true);
  assert.deepEqual(record.portraitContract.masterCanvasPixels, {
    width: 1179,
    height: 2556,
  }, "Review matrix must declare the real portrait-master raster size");
  assert.equal(record.portraitContract.authoredOverscanFraction, 0.15,
    "Review matrix must declare the authored 15 percent overscan");
  assert.deepEqual(record.portraitContract.baselineSourceRect, {
    x: 0.15,
    y: 0.15,
    width: 0.7,
    height: 0.7,
  }, "Review matrix crop must consume the declared overscan exactly");
  assert.ok(
    record.portraitContract.masterCanvasPixels.width
      / record.portraitContract.masterCanvasPixels.height < 1,
    "Review master must remain portrait",
  );
  assert.ok(record.portraitContract.minimumEffectiveTargetPoints >= 44,
    "Chapter 01 review targets must be at least 44 points");
  assert.equal(record.portraitContract.reduceMotionUsesStaticConsequenceComposition, true);

  assert.equal(record.worlds.length, 6, "Chapter 01 review requires exactly six shared worlds");
  const worldIDs = record.worlds.map(({ id }) => id);
  assert.deepEqual(worldIDs, [...expectedWorldBeats.keys()], "Chapter 01 shared-world order drifted");
  assert.equal(new Set(worldIDs).size, 6, "Chapter 01 review world IDs are not unique");
  const worldsByID = new Map(record.worlds.map((world) => [world.id, world]));
  for (const world of record.worlds) {
    assert.match(world.id, stableID, "Review world has an unstable ID");
    assert.ok(world.title.trim(), `Review world ${world.id} has no title`);
    assert.ok(!world.sourceAsset.startsWith("content/public/"),
      `Review world ${world.id} points into public content`);
    const sourcePath = path.resolve(root, world.sourceAsset);
    assert.ok(sourcePath.startsWith(`${root}${path.sep}`),
      `Review world ${world.id} source escaped the repository`);
    await readFile(sourcePath);
    assert.match(world.sourceStatus, /NOT_(?:PRODUCTION_MASTER|SHIPPING_APPROVED)/u,
      `Review world ${world.id} overclaims its source`);
    assert.ok(Array.isArray(world.interactionStateIDs) && world.interactionStateIDs.length > 0,
      `Review world ${world.id} has no authored states`);
    assert.equal(new Set(world.interactionStateIDs).size, world.interactionStateIDs.length,
      `Review world ${world.id} repeats a state`);
    assert.match(world.reduceMotion.compositionID, stableID,
      `Review world ${world.id} has no stable Reduce Motion composition`);
    assert.ok(world.reduceMotion.consequenceStateIDs.length > 0,
      `Review world ${world.id} loses its consequence under Reduce Motion`);
    assert.ok(world.reduceMotion.consequenceStateIDs.every((stateID) =>
      world.interactionStateIDs.includes(stateID)),
    `Review world ${world.id} has a Reduce Motion state outside its authored states`);
  }

  const draftBeats = draft.arcs.flatMap(({ beats }) => beats);
  assert.equal(record.beats.length, 17, "Chapter 01 review requires exactly 17 beat bindings");
  assert.deepEqual(record.beats.map(({ beatID }) => beatID), draftBeats.map(({ beatID }) => beatID),
    "Chapter 01 review beat order drifted");
  assert.deepEqual(record.beats.map(({ sceneID }) => sceneID), draftBeats.map(({ sceneID }) => sceneID),
    "Chapter 01 review scene and restore anchors drifted");
  assert.equal(new Set(record.beats.map(({ beatID }) => beatID)).size, 17,
    "Chapter 01 review beat IDs are not unique");
  assert.equal(new Set(record.beats.map(({ sceneID }) => sceneID)).size, 17,
    "Chapter 01 review scene IDs are not unique");

  for (const binding of record.beats) {
    assert.ok(worldsByID.has(binding.worldID), `Beat ${binding.beatID} uses an unknown review world`);
    assert.match(binding.cameraVariant, stableID, `Beat ${binding.beatID} has an unstable camera variant`);
    assert.match(binding.lightVariant, stableID, `Beat ${binding.beatID} has an unstable light variant`);
    assert.match(binding.stateVariant, stableID, `Beat ${binding.beatID} has an unstable state variant`);
    assert.ok(worldsByID.get(binding.worldID).interactionStateIDs.includes(binding.stateVariant),
      `Beat ${binding.beatID} uses a state outside its review world`);
  }
  for (const [worldID, expectedBeatIDs] of expectedWorldBeats) {
    assert.deepEqual(record.beats.filter((beat) => beat.worldID === worldID).map(({ beatID }) => beatID),
      expectedBeatIDs, `Chapter 01 review-world membership drifted: ${worldID}`);
  }

  for (const beat of draftBeats.filter(({ interaction }) => interaction)) {
    const binding = record.beats.find(({ beatID }) => beatID === beat.beatID);
    const world = worldsByID.get(binding.worldID);
    const missingStates = interactionStateIDs(beat.interaction)
      .filter((stateID) => !world.interactionStateIDs.includes(stateID));
    assert.deepEqual(missingStates, [],
      `Review world ${world.id} is missing interaction states for ${beat.interaction.id}`);
  }

  assert.ok(!Object.hasOwn(draft, "worlds"), "Backstage review worlds leaked into the chapter draft");
  return record;
}

if (process.argv[1]
    && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  const repositoryRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
  await validateChapter01ReviewMatrix({ repositoryRoot });
  process.stdout.write("Chapter 01 six-world non-shipping review matrix validated.\n");
}
