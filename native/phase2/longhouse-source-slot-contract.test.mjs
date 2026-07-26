import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import {
  manifestIntegrityMaterial,
  verifyPackageManifest,
} from "../tooling/src/compile.mjs";
import { verticalSliceDevelopmentPublicKey } from
  "../tooling/src/deterministic-development-signing.mjs";

const repositoryRoot = path.resolve(import.meta.dirname, "../..");
const productionPayloadPath = path.join(
  repositoryRoot,
  "native/phase2/generated/first-farmers.content-package.json",
);
const payloadReceiptPath = path.join(
  repositoryRoot,
  "native/phase2/generated/first-farmers.payload-receipt.json",
);
const generatorPath = path.join(
  repositoryRoot,
  "native/phase2/generate-first-farmers-payload.mjs",
);
const interactionContractPath = path.join(
  repositoryRoot,
  "native/design/phase1/longhouse/interaction-production-contract.json",
);
const fixtureRoot = path.join(repositoryRoot, "native/phase2/runtime-fixture");
const fixtureSourcePath = path.join(
  fixtureRoot,
  "source/chapters/vertical-slice-development-v1.json",
);
const compiledRoot = path.join(
  fixtureRoot,
  "compiled/vertical-slice-development-v1.runtimefixture",
);
const fixtureCompiledPath = path.join(
  compiledRoot,
  "chapters/vertical-slice-development-v1.json",
);
const fixtureManifestPath = path.join(compiledRoot, "package-manifest.json");
const fixtureReceiptPath = path.join(
  fixtureRoot,
  "vertical-slice-development-trust-receipt.json",
);
const fixtureLineagePath = path.join(fixtureRoot, "fixture-lineage.json");
const projectionAuthorityPath = path.join(
  fixtureRoot,
  "backstage/projection-authority.json",
);

const expectedComponents = ["posts", "hearth", "storage", "roof"];
const developmentKeyID = "vertical-slice-development-key-v1";

async function readJSON(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function sceneWithID(document, sceneID) {
  const scene = document.scenes.find(({ id }) => id === sceneID);
  assert.ok(scene, `missing Longhouse scene ${sceneID}`);
  return scene;
}

function bounds(pathPoints) {
  const xs = pathPoints.map(({ x }) => x);
  const ys = pathPoints.map(({ y }) => y);
  return {
    x: Math.min(...xs),
    y: Math.min(...ys),
    width: Math.max(...xs) - Math.min(...xs),
    height: Math.max(...ys) - Math.min(...ys),
  };
}

function center(rect) {
  return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
}

function assertRectEqual(actual, expected, message) {
  for (const key of ["x", "y", "width", "height"]) {
    assert.ok(
      Math.abs(actual[key] - expected[key]) < 1e-9,
      `${message}.${key} drifted`,
    );
  }
}

function assertLonghouseSourceSlotContract(scene, authority) {
  assert.equal(scene.interactionVisualBinding.grammar, "assemble");
  assert.equal(
    scene.interactionVisualBinding.configuration.interactionID,
    "interaction-first-farmers-the-house-outlives",
  );

  const targetByID = new Map(scene.interactionTargets.map((target) => [
    target.interactionTargetID,
    target,
  ]));
  assert.equal(targetByID.size, scene.interactionTargets.length, "target IDs must be unique");

  const components = scene.interactionVisualBinding.configuration.components;
  assert.deepEqual(components.map(({ componentID }) => componentID), expectedComponents);
  assert.equal(scene.interactionTargets.length, expectedComponents.length * 2);
  assert.equal(authority.shippingAllowed, false);
  assert.equal(authority.productionArtworkAuthority, false);
  assert.equal(
    authority.geometryAuthority,
    "TECHNICAL_FIXTURE_ONLY_REPLACE_WITH_REGISTERED_PRODUCTION_TARGETS",
  );
  assert.deepEqual(authority.components.map(({ componentID }) => componentID), expectedComponents);

  const crop = scene.sceneCanvas.viewportCrops.find(({ id }) => id === "baseline-393x852");
  assert.ok(crop, "baseline portrait crop required");

  const allBindingTargetIDs = [];
  for (const component of components) {
    assert.equal(Object.hasOwn(component, "interactionTargetID"), false);
    assert.equal(typeof component.sourceInteractionTargetID, "string");
    assert.equal(typeof component.slotInteractionTargetID, "string");
    assert.notEqual(component.sourceInteractionTargetID, component.slotInteractionTargetID);
    allBindingTargetIDs.push(
      component.sourceInteractionTargetID,
      component.slotInteractionTargetID,
    );

    const sourceTarget = targetByID.get(component.sourceInteractionTargetID);
    const slotTarget = targetByID.get(component.slotInteractionTargetID);
    assert.ok(sourceTarget, `missing source target for ${component.componentID}`);
    assert.ok(slotTarget, `missing slot target for ${component.componentID}`);
    assert.equal(sourceTarget.layerID, component.layerID);
    assert.equal(slotTarget.layerID, component.layerID);

    const sourceBounds = bounds(sourceTarget.hitRegion.path);
    const slotBounds = bounds(slotTarget.hitRegion.path);
    const authored = authority.components.find(
      ({ componentID }) => componentID === component.componentID,
    );
    assert.ok(authored);
    assert.equal(authored.layerID, component.layerID);
    assert.equal(authored.sourceInteractionTargetID, component.sourceInteractionTargetID);
    assert.equal(authored.slotInteractionTargetID, component.slotInteractionTargetID);
    assertRectEqual(sourceBounds, authored.sourceHitRegion, component.componentID);
    assertRectEqual(slotBounds, authored.slotHitRegion, component.componentID);
    const sourceCenter = center(sourceBounds);
    const slotCenter = center(slotBounds);
    assert.ok(
      Math.hypot(sourceCenter.x - slotCenter.x, sourceCenter.y - slotCenter.y) >= 0.2,
      `${component.componentID} source and slot must be materially separate`,
    );

    for (const targetBounds of [sourceBounds, slotBounds]) {
      const widthPoints = targetBounds.width / crop.sourceRect.width
        * crop.viewport.widthPoints;
      const heightPoints = targetBounds.height / crop.sourceRect.height
        * crop.viewport.heightPoints;
      assert.ok(widthPoints >= 44, `${component.componentID} target width below 44 points`);
      assert.ok(heightPoints >= 44, `${component.componentID} target height below 44 points`);
    }
  }

  assert.equal(new Set(allBindingTargetIDs).size, allBindingTargetIDs.length);
  assert.deepEqual(new Set(allBindingTargetIDs), new Set(targetByID.keys()));
}

test("production Longhouse projection has distinct material sources and bearing slots", async () => {
  const [payload, contract] = await Promise.all([
    readJSON(productionPayloadPath),
    readJSON(interactionContractPath),
  ]);
  assertLonghouseSourceSlotContract(
    sceneWithID(payload, "scene-first-farmers-longhouse-assembly"),
    contract.runtimeVisualBinding,
  );

  const payloadBytes = await readFile(productionPayloadPath);
  const receipt = await readJSON(payloadReceiptPath);
  assert.equal(receipt.payloadSHA256, sha256(payloadBytes));
  assert.equal(receipt.shippingState, "PROHIBITED");
});

test("runtime source and signed development fixture carry the same Longhouse projection", async () => {
  const [source, compiled, contract] = await Promise.all([
    readJSON(fixtureSourcePath),
    readJSON(fixtureCompiledPath),
    readJSON(interactionContractPath),
  ]);
  const sourceScene = sceneWithID(source, "lab-first-farmers-house-assembly");
  const compiledScene = sceneWithID(compiled, "lab-first-farmers-house-assembly");
  assertLonghouseSourceSlotContract(sourceScene, contract.runtimeVisualBinding);
  assert.deepEqual(compiledScene, sourceScene);
});

test("targeted fixture integrity metadata binds the migrated chapter bytes", async () => {
  const [
    manifest,
    receipt,
    lineage,
    authority,
    authorityBytes,
    chapterBytes,
    chapterStat,
    payloadBytes,
  ] = await Promise.all([
    readJSON(fixtureManifestPath),
    readJSON(fixtureReceiptPath),
    readJSON(fixtureLineagePath),
    readJSON(projectionAuthorityPath),
    readFile(projectionAuthorityPath),
    readFile(fixtureCompiledPath),
    stat(fixtureCompiledPath),
    readFile(productionPayloadPath),
  ]);
  const chapterSHA256 = sha256(chapterBytes);
  const record = manifest.files.find(
    ({ path: relative }) => relative === "chapters/vertical-slice-development-v1.json",
  );
  assert.deepEqual(record, {
    path: "chapters/vertical-slice-development-v1.json",
    bytes: chapterStat.size,
    sha256: chapterSHA256,
  });
  assert.equal(
    manifest.manifestDigest,
    sha256(Buffer.from(manifestIntegrityMaterial(manifest), "utf8")),
  );
  verifyPackageManifest(
    manifest,
    verticalSliceDevelopmentPublicKey(),
    developmentKeyID,
  );
  assert.equal(receipt.manifestDigest, manifest.manifestDigest);
  assert.equal(receipt.shippingState, "PROHIBITED");
  assert.equal(receipt.projectionAuthoritySHA256, sha256(authorityBytes));
  assert.equal(authority.payloadSHA256, chapterSHA256);
  assert.equal(authority.shippingState, "PROHIBITED");
  assert.equal(lineage.manifestDigest, manifest.manifestDigest);
  assert.equal(lineage.payloadSHA256, chapterSHA256);
  assert.equal(lineage.sourcePayload.bytes, payloadBytes.byteLength);
  assert.equal(lineage.sourcePayload.sha256, sha256(payloadBytes));
  assert.deepEqual(
    lineage.compiledFiles.find(
      ({ path: relative }) => relative === "chapters/vertical-slice-development-v1.json",
    ),
    record,
  );
});

test("Longhouse generator branch emits the source-slot schema and no legacy binding", async () => {
  const generator = await readFile(generatorPath, "utf8");
  const branchStart = generator.indexOf('if (interaction.grammar === "assemble")');
  const branchEnd = generator.indexOf('if (interaction.grammar === "transform")', branchStart);
  assert.ok(branchStart >= 0 && branchEnd > branchStart);
  const assembleBranch = generator.slice(branchStart, branchEnd);
  assert.match(assembleBranch, /sourceInteractionTargetID/);
  assert.match(assembleBranch, /slotInteractionTargetID/);
  assert.doesNotMatch(assembleBranch, /components\.push\(\{[\s\S]*?\n\s*interactionTargetID,/);
});
