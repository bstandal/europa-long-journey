import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { validateHarvestLocalComposite } from "./validate-harvest-local-composite.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const editPath = path.join(
  repositoryRoot,
  "native/design/phase1/harvest/production-master-candidate-v21.metadata.json",
);
const compositePath = path.join(
  repositoryRoot,
  "native/design/phase1/harvest/production-master-candidate-v22.metadata.json",
);
const fullResolutionPath = path.join(
  repositoryRoot,
  "native/design/phase1/harvest/production-master-candidate-v23.metadata.json",
);
const canvasNormalizedPath = path.join(
  repositoryRoot,
  "native/design/phase1/harvest/production-master-candidate-v24.metadata.json",
);
const materialCorrectedPath = path.join(
  repositoryRoot,
  "native/design/phase1/harvest/production-master-candidate-v25.metadata.json",
);
const garmentCorrectedPath = path.join(
  repositoryRoot,
  "native/design/phase1/harvest/production-master-candidate-v26.metadata.json",
);
const [
  edit,
  composite,
  fullResolution,
  canvasNormalized,
  materialCorrected,
  garmentCorrected,
] = await Promise.all([
  readFile(editPath, "utf8").then(JSON.parse),
  readFile(compositePath, "utf8").then(JSON.parse),
  readFile(fullResolutionPath, "utf8").then(JSON.parse),
  readFile(canvasNormalizedPath, "utf8").then(JSON.parse),
  readFile(materialCorrectedPath, "utf8").then(JSON.parse),
  readFile(garmentCorrectedPath, "utf8").then(JSON.parse),
]);

test("validates the byte-bound local Harvest edit and its pixel-isolated composite", async () => {
  const result = await validateHarvestLocalComposite({ repositoryRoot });
  assert.equal(result.status, "NON_SHIPPING_LOCAL_CORRECTION_REFERENCE");
  assert.equal(result.outputSHA256, composite.output.sha256);
  assert.equal(result.isolationRegions, 4);
  assert.equal(
    result.fullResolutionStatus,
    "NON_SHIPPING_FULL_RESOLUTION_LOCAL_CORRECTION_CANDIDATE",
  );
  assert.equal(result.fullResolutionOutputSHA256, fullResolution.output.sha256);
  assert.equal(result.fullResolutionIsolationRegions, 4);
  assert.equal(
    result.canvasNormalizedStatus,
    "NON_SHIPPING_CANVAS_NORMALIZED_PRODUCTION_CANDIDATE",
  );
  assert.equal(result.canvasNormalizedOutputSHA256, canvasNormalized.output.sha256);
  assert.equal(
    result.materialCorrectedStatus,
    "NON_SHIPPING_EXACT_CANVAS_MATERIAL_CORRECTION_CANDIDATE",
  );
  assert.equal(result.materialCorrectedOutputSHA256, materialCorrected.output.sha256);
  assert.equal(result.materialCorrectedIsolationRegions, 4);
  assert.equal(
    result.garmentCorrectedStatus,
    "NON_SHIPPING_LOCAL_HISTORICAL_GARMENT_CORRECTION_CANDIDATE",
  );
  assert.equal(result.garmentCorrectedOutputSHA256, garmentCorrected.output.sha256);
  assert.equal(result.garmentCorrectedIsolationRegions, 3);
});

test("rejects a direct edit or composite that claims shipping authority", async () => {
  const unsafeEdit = structuredClone(edit);
  unsafeEdit.shippingAllowed = true;
  await assert.rejects(
    validateHarvestLocalComposite({
      repositoryRoot,
      editMetadata: unsafeEdit,
      compositeMetadata: composite,
    }),
    /v21 must remain a rejected, non-shipping direct edit/u,
  );

  const unsafeComposite = structuredClone(composite);
  unsafeComposite.status = "PRODUCTION_MASTER";
  await assert.rejects(
    validateHarvestLocalComposite({
      repositoryRoot,
      editMetadata: edit,
      compositeMetadata: unsafeComposite,
    }),
    /v22 must remain a non-shipping local correction reference/u,
  );

  const unsafeFullResolution = structuredClone(fullResolution);
  unsafeFullResolution.audit.productionMasterResult = "PASS";
  await assert.rejects(
    validateHarvestLocalComposite({
      repositoryRoot,
      editMetadata: edit,
      compositeMetadata: composite,
      fullResolutionMetadata: unsafeFullResolution,
    }),
    /v23 cannot claim production-master authority/u,
  );

  const unsafeCanvas = structuredClone(canvasNormalized);
  unsafeCanvas.audit.layerDAGAuthority = "GRANTED";
  await assert.rejects(
    validateHarvestLocalComposite({
      repositoryRoot,
      editMetadata: edit,
      compositeMetadata: composite,
      fullResolutionMetadata: fullResolution,
      canvasNormalizedMetadata: unsafeCanvas,
    }),
    /v24 cannot grant production-master or layer-DAG authority/u,
  );

  const unsafeMaterial = structuredClone(materialCorrected);
  unsafeMaterial.shippingAllowed = true;
  await assert.rejects(
    validateHarvestLocalComposite({
      repositoryRoot,
      editMetadata: edit,
      compositeMetadata: composite,
      fullResolutionMetadata: fullResolution,
      canvasNormalizedMetadata: canvasNormalized,
      materialCorrectedMetadata: unsafeMaterial,
    }),
    /v25 must remain a non-shipping material-correction candidate/u,
  );

  const unsafeGarment = structuredClone(garmentCorrected);
  unsafeGarment.audit.layerDAGAuthority = "GRANTED";
  await assert.rejects(
    validateHarvestLocalComposite({
      repositoryRoot,
      editMetadata: edit,
      compositeMetadata: composite,
      fullResolutionMetadata: fullResolution,
      canvasNormalizedMetadata: canvasNormalized,
      materialCorrectedMetadata: materialCorrected,
      garmentCorrectedMetadata: unsafeGarment,
    }),
    /v26 cannot grant production-master or layer-DAG authority/u,
  );
});

test("rejects drift in the full-resolution composite before its isolation is trusted", async () => {
  const drifted = structuredClone(fullResolution);
  drifted.output.sha256 = "0".repeat(64);
  await assert.rejects(
    validateHarvestLocalComposite({
      repositoryRoot,
      editMetadata: edit,
      compositeMetadata: composite,
      fullResolutionMetadata: drifted,
    }),
    /v23 output: bytes drifted/u,
  );
});

test("rejects drift in any bound candidate bytes before isolation is trusted", async () => {
  const drifted = structuredClone(composite);
  drifted.output.sha256 = "0".repeat(64);
  await assert.rejects(
    validateHarvestLocalComposite({
      repositoryRoot,
      editMetadata: edit,
      compositeMetadata: drifted,
    }),
    /v22 output: bytes drifted/u,
  );
});

test("rejects drift in the exact v26 parent chain before garment isolation is trusted", async () => {
  const drifted = structuredClone(garmentCorrected);
  drifted.parent.sha256 = "0".repeat(64);
  await assert.rejects(
    validateHarvestLocalComposite({
      repositoryRoot,
      garmentCorrectedMetadata: drifted,
    }),
    /v26 parent: bytes drifted/u,
  );
});
