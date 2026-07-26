#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { validateHarvestFixture } from "./validate-harvest-fixture.mjs";
import { validateReconstructionApproval } from "./validate-reconstruction-approval.mjs";
import { validateHarvestEditorReview } from "./validate-harvest-editor-review.mjs";

const phase1Root = path.dirname(fileURLToPath(import.meta.url));
const nativeRoot = path.dirname(phase1Root);
const repositoryRoot = path.dirname(nativeRoot);
const blueprintRoot = path.join(nativeRoot, "blueprint");

const readJSON = async (filePath) => JSON.parse(await readFile(filePath, "utf8"));
const blueprintJSON = (name) => readJSON(path.join(blueprintRoot, name));
const stableID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const expectedGrammars = ["allocate", "assemble", "pressure", "trace", "transform"];

const [lab, selection, approval, catalog, matrix, mapping, world, delivery] = await Promise.all([
  readJSON(path.join(phase1Root, "experience-lab.json")),
  readJSON(path.join(nativeRoot, "design/phase1/harvest/selection.json")),
  blueprintJSON("editor-approval.json"),
  blueprintJSON("chapter-catalog.json"),
  blueprintJSON("arc-matrix.json"),
  blueprintJSON("interaction-mapping.json"),
  blueprintJSON("world-traces.json"),
  blueprintJSON("delivery-plan.json"),
]);

assert.equal(lab.schemaVersion, 1, "unsupported Phase 1 laboratory schema");
assert.equal(lab.status, "LOCKED_IMPLEMENTATION_SET", "experience laboratory is not locked");
assert.equal(approval.status, lab.requiresPhase0Status, "Phase 0 approval does not satisfy the laboratory gate");
assert.deepEqual([...lab.requiredGrammars].sort(), expectedGrammars, "laboratory grammar declaration drifted");
assert.equal(lab.scenes.length, 5, "the laboratory requires exactly one scene per grammar");

const essentialPackage = delivery.packages.find(({ packageID }) => packageID === lab.packageID);
assert.ok(essentialPackage?.isEssentialInstall, "laboratory must belong to the essential package");
const freeChapterIDs = catalog.chapters.filter(({ freeAtLaunch }) => freeAtLaunch).map(({ contentID }) => contentID).sort();
assert.deepEqual([...essentialPackage.chapterIDs].sort(), freeChapterIDs, "essential package and free catalog disagree");

const mappingByInteraction = new Map(mapping.items.map((item) => [item.nativeInteractionID, item]));
const matrixByChapter = new Map(matrix.chapters.map((chapter) => [chapter.contentID, chapter]));
const tracesByID = new Map(world.traces.map((trace) => [trace.traceID, trace]));
const allEffectIDs = new Set(world.traces.flatMap((trace) => trace.arcEffects.map((effect) => effect.effectID)));
const seenSceneIDs = new Set();
const seenBeatIDs = new Set();
const seenInteractions = new Set();

for (const scene of lab.scenes) {
  for (const [field, value] of [
    ["labSceneID", scene.labSceneID],
    ["beatID", scene.beatID],
    ["contentID", scene.contentID],
    ["arcID", scene.arcID],
    ["movementID", scene.movementID],
    ["nativeInteractionID", scene.nativeInteractionID],
    ["worldTraceID", scene.worldTraceID],
    ["worldEffectID", scene.worldEffectID],
  ]) {
    assert.match(value, stableID, `${scene.labSceneID}.${field} is not a stable ID`);
  }
  assert.notEqual(scene.beatID, "UNASSIGNED", `${scene.labSceneID} requires an authored laboratory beat`);
  assert.ok(seenSceneIDs.add(scene.labSceneID), `duplicate laboratory scene ${scene.labSceneID}`);
  assert.ok(seenBeatIDs.add(scene.beatID), `duplicate laboratory beat ${scene.beatID}`);
  assert.ok(seenInteractions.add(scene.nativeInteractionID), `duplicate laboratory interaction ${scene.nativeInteractionID}`);
  assert.ok(freeChapterIDs.includes(scene.contentID), `${scene.labSceneID} is outside the free triad`);
  assert.ok(scene.purpose?.trim(), `${scene.labSceneID} requires a concrete purpose`);

  const interaction = mappingByInteraction.get(scene.nativeInteractionID);
  assert.ok(interaction, `${scene.labSceneID} references a missing interaction`);
  assert.equal(interaction.nativeRole, "principal", `${scene.labSceneID} must exercise a principal interaction`);
  assert.equal(interaction.chapterID, scene.contentID, `${scene.labSceneID} chapter drifted`);
  assert.equal(interaction.arcID, scene.arcID, `${scene.labSceneID} arc drifted`);
  assert.equal(interaction.movementID, scene.movementID, `${scene.labSceneID} movement drifted`);
  assert.equal(interaction.nativeGrammar, scene.grammar, `${scene.labSceneID} grammar drifted`);
  assert.equal(interaction.disposition, scene.sourceDisposition, `${scene.labSceneID} disposition drifted`);
  assert.equal(interaction.worldTraceID, scene.worldTraceID, `${scene.labSceneID} world trace drifted`);
  assert.equal(interaction.worldEffectID, scene.worldEffectID, `${scene.labSceneID} world effect drifted`);

  const chapter = matrixByChapter.get(scene.contentID);
  const arc = chapter?.arcs.find(({ arcID }) => arcID === scene.arcID);
  assert.ok(arc, `${scene.labSceneID} references a missing approved arc`);
  assert.ok(arc.movementIDs.includes(scene.movementID), `${scene.labSceneID} movement is outside its arc`);
  assert.ok(arc.principalNativeInteractionIDs.includes(scene.nativeInteractionID), `${scene.labSceneID} interaction is outside its arc`);
  assert.ok(arc.worldEffectIDs.includes(scene.worldEffectID), `${scene.labSceneID} effect is outside its arc`);

  const trace = tracesByID.get(scene.worldTraceID);
  assert.ok(trace, `${scene.labSceneID} references a missing world trace`);
  const effect = trace.arcEffects.find(({ effectID }) => effectID === scene.worldEffectID);
  assert.ok(effect, `${scene.labSceneID} effect is not attached to its world trace`);
  assert.equal(effect.nativeInteractionID, scene.nativeInteractionID, `${scene.labSceneID} effect belongs to another interaction`);
  for (const seedEffectID of scene.seedEffectIDs ?? []) {
    assert.ok(allEffectIDs.has(seedEffectID), `${scene.labSceneID} seed effect ${seedEffectID} is missing`);
  }
}

assert.deepEqual([...new Set(lab.scenes.map(({ grammar }) => grammar))].sort(), expectedGrammars, "laboratory does not cover each grammar exactly once");
assert.deepEqual([...new Set(lab.scenes.map(({ contentID }) => contentID))].sort(), freeChapterIDs, "laboratory must use all three free chapters");

assert.equal(selection.status, "SELECTED_BY_EDITOR_IN_CHIEF", "Harvest visual lacks editor selection");
assert.equal(selection.role, "NON_SHIPPING_VISUAL_TARGET", "selected visual must remain non-shipping");
assert.equal(selection.shippingState, "PROHIBITED_UNTIL_REBUILT_AND_APPROVED", "selected visual became shippable without approval");
const selectedScene = lab.scenes.find(({ selectedVisual }) => selectedVisual);
assert.ok(selectedScene, "laboratory has no selected visual binding");
assert.equal(selectedScene.selectedVisual, "native/design/phase1/harvest/selection.json", "selected visual path drifted");
for (const field of ["contentID", "arcID", "movementID", "nativeInteractionID"]) {
  assert.equal(selection[field], selectedScene[field], `selected visual ${field} does not match the laboratory scene`);
}
assert.ok(selection.lockedComposition.length >= 5, "selected visual lacks locked composition anatomy");
assert.ok(selection.requiredProductionCorrections.length >= 6, "selected visual lacks production corrections");

const visualPath = path.resolve(repositoryRoot, selection.visualPath);
const allowedVisualRoot = `${path.join(nativeRoot, "design", "phase1")}${path.sep}`;
assert.ok(visualPath.startsWith(allowedVisualRoot), "selected visual escaped the backstage design tree");
const visualBytes = await readFile(visualPath);
assert.equal(createHash("sha256").update(visualBytes).digest("hex"), selection.visualSHA256, "selected visual bytes drifted");
assert.deepEqual([...visualBytes.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10], "selected visual is not a PNG");
assert.equal(visualBytes.readUInt32BE(16), selection.pixelWidth, "selected visual width drifted");
assert.equal(visualBytes.readUInt32BE(20), selection.pixelHeight, "selected visual height drifted");

await validateHarvestFixture();
await validateReconstructionApproval({ repositoryRoot });
await validateHarvestEditorReview({ repositoryRoot });

process.stdout.write(`Phase 1 laboratory locked: ${lab.scenes.length} scenes, ${expectedGrammars.length} grammars, ${freeChapterIDs.length} free chapters, selected visual ${selection.visualSHA256}.\n`);
