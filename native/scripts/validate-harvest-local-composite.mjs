#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execute = promisify(execFile);
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultRepositoryRoot = path.resolve(scriptDirectory, "../..");
const designRoot = "native/design/phase1/harvest";

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function pngHeader(bytes, label) {
  const signature = "89504e470d0a1a0a";
  requireCondition(
    bytes.length >= 26 && bytes.subarray(0, 8).toString("hex") === signature,
    `${label}: valid PNG required`,
  );
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
    bitDepth: bytes[24],
    colorType: bytes[25],
  };
}

async function rawFrameHash(filePath, crop) {
  const { stdout } = await execute("ffmpeg", [
    "-loglevel", "error",
    "-i", filePath,
    "-vf", `crop=${crop}`,
    "-frames:v", "1",
    "-f", "hash",
    "-hash", "sha256",
    "-",
  ]);
  const match = stdout.match(/SHA256=([a-f0-9]{64})/u);
  requireCondition(match, `ffmpeg did not return a raw-frame hash for ${filePath}`);
  return match[1];
}

export async function validateHarvestLocalComposite({
  repositoryRoot = defaultRepositoryRoot,
  editMetadata,
  compositeMetadata,
  fullResolutionMetadata,
  canvasNormalizedMetadata,
  materialCorrectedMetadata,
  garmentCorrectedMetadata,
} = {}) {
  const readJSON = async (relativePath) => JSON.parse(
    await readFile(path.join(repositoryRoot, relativePath), "utf8"),
  );
  const edit = editMetadata ?? await readJSON(
    `${designRoot}/production-master-candidate-v21.metadata.json`,
  );
  const composite = compositeMetadata ?? await readJSON(
    `${designRoot}/production-master-candidate-v22.metadata.json`,
  );
  const fullResolution = fullResolutionMetadata ?? await readJSON(
    `${designRoot}/production-master-candidate-v23.metadata.json`,
  );
  const canvasNormalized = canvasNormalizedMetadata ?? await readJSON(
    `${designRoot}/production-master-candidate-v24.metadata.json`,
  );
  const materialCorrected = materialCorrectedMetadata ?? await readJSON(
    `${designRoot}/production-master-candidate-v25.metadata.json`,
  );
  const garmentCorrected = garmentCorrectedMetadata ?? await readJSON(
    `${designRoot}/production-master-candidate-v26.metadata.json`,
  );

  requireCondition(edit.schemaVersion === 1, "v21 metadata schema drifted");
  requireCondition(
    edit.status === "REJECTED_AS_DIRECT_EDIT_ACCEPTED_AS_LOCAL_MATERIAL_SOURCE"
      && edit.shippingAllowed === false,
    "v21 must remain a rejected, non-shipping direct edit",
  );
  requireCondition(composite.schemaVersion === 1, "v22 metadata schema drifted");
  requireCondition(
    composite.status === "NON_SHIPPING_LOCAL_CORRECTION_REFERENCE"
      && composite.shippingAllowed === false,
    "v22 must remain a non-shipping local correction reference",
  );
  requireCondition(
    composite.audit.productionMasterResult === "REJECT_BELOW_DIMENSION_FLOOR",
    "v22 cannot claim production-master status",
  );
  requireCondition(fullResolution.schemaVersion === 1, "v23 metadata schema drifted");
  requireCondition(
    fullResolution.status === "NON_SHIPPING_FULL_RESOLUTION_LOCAL_CORRECTION_CANDIDATE"
      && fullResolution.shippingAllowed === false,
    "v23 must remain a non-shipping full-resolution candidate",
  );
  requireCondition(
    fullResolution.localEditSource.directEditUse
      === "REJECTED_GLOBAL_REDRAW_RETAINED_ONLY_AS_LOCAL_MATERIAL_SOURCE",
    "v23 source cannot be treated as a complete-image edit",
  );
  requireCondition(
    fullResolution.audit.productionMasterResult === "PENDING_LAYER_DAG_AND_ARTISTIC_GATE",
    "v23 cannot claim production-master authority",
  );
  requireCondition(canvasNormalized.schemaVersion === 1, "v24 metadata schema drifted");
  requireCondition(
    canvasNormalized.status === "NON_SHIPPING_CANVAS_NORMALIZED_PRODUCTION_CANDIDATE"
      && canvasNormalized.shippingAllowed === false,
    "v24 must remain a non-shipping canvas-normalized candidate",
  );
  requireCondition(
    canvasNormalized.audit.productionMasterResult === "PENDING_ARTISTIC_GATE"
      && canvasNormalized.audit.layerDAGAuthority === "NOT_GRANTED",
    "v24 cannot grant production-master or layer-DAG authority",
  );
  requireCondition(materialCorrected.schemaVersion === 1, "v25 metadata schema drifted");
  requireCondition(
    materialCorrected.status === "NON_SHIPPING_EXACT_CANVAS_MATERIAL_CORRECTION_CANDIDATE"
      && materialCorrected.shippingAllowed === false,
    "v25 must remain a non-shipping material-correction candidate",
  );
  requireCondition(
    materialCorrected.localEditSource.directEditUse
      === "REJECTED_GLOBAL_REDRAW_RETAINED_ONLY_AS_LOCAL_MATERIAL_SOURCE",
    "v25 source cannot be treated as a complete-image edit",
  );
  requireCondition(
    materialCorrected.audit.productionMasterResult === "PENDING_ARTISTIC_GATE"
      && materialCorrected.audit.layerDAGAuthority === "NOT_GRANTED",
    "v25 cannot grant production-master or layer-DAG authority",
  );
  requireCondition(garmentCorrected.schemaVersion === 1, "v26 metadata schema drifted");
  requireCondition(
    garmentCorrected.status === "NON_SHIPPING_LOCAL_HISTORICAL_GARMENT_CORRECTION_CANDIDATE"
      && garmentCorrected.shippingAllowed === false,
    "v26 must remain a non-shipping garment-correction candidate",
  );
  requireCondition(
    garmentCorrected.localEditSource.directEditUse
      === "REJECTED_GLOBAL_REDRAW_RETAINED_ONLY_AS_LOCAL_GARMENT_SOURCE",
    "v26 source cannot be treated as a complete-image edit",
  );
  requireCondition(
    garmentCorrected.audit.materialResult
      === "PASS_PROVISIONAL_F5_MODERN_GARMENT_CUE_REMOVAL"
      && garmentCorrected.audit.productionMasterResult === "PENDING_ARTISTIC_GATE"
      && garmentCorrected.audit.layerDAGAuthority === "NOT_GRANTED",
    "v26 cannot grant production-master or layer-DAG authority",
  );

  const bindings = [
    [edit.parent, "v21 parent"],
    [edit.prompt, "v21 prompt"],
    [edit.output, "v21 output"],
    [composite.parent, "v22 parent"],
    [composite.localEditSource, "v22 local edit source"],
    [composite.authorizedMask, "v22 authorized mask"],
    [composite.output, "v22 output"],
    [fullResolution.parent, "v23 parent"],
    [fullResolution.inputCrop, "v23 input crop"],
    [fullResolution.prompt, "v23 prompt"],
    [fullResolution.localEditSource, "v23 local edit source"],
    [fullResolution.authorizedMask, "v23 authorized mask"],
    [fullResolution.output, "v23 output"],
    [canvasNormalized.parent, "v24 parent"],
    [canvasNormalized.output, "v24 output"],
    [materialCorrected.parent, "v25 parent"],
    [materialCorrected.inputCrop, "v25 input crop"],
    [materialCorrected.prompt, "v25 prompt"],
    [materialCorrected.localEditSource, "v25 local edit source"],
    [materialCorrected.authorizedMask, "v25 authorized mask"],
    [materialCorrected.output, "v25 output"],
    [materialCorrected.codexPreflight, "v25 Codex preflight"],
    [garmentCorrected.parent, "v26 parent"],
    [garmentCorrected.inputCrop, "v26 input crop"],
    [garmentCorrected.prompt, "v26 prompt"],
    [garmentCorrected.localEditSource, "v26 local edit source"],
    [garmentCorrected.authorizedMask.source, "v26 authored mask source"],
    [garmentCorrected.authorizedMask.hardRaster, "v26 hard mask"],
    [garmentCorrected.authorizedMask, "v26 feathered mask"],
    [garmentCorrected.output, "v26 output"],
    [garmentCorrected.codexPreflight, "v26 Codex preflight"],
  ];
  const bytesByPath = new Map();
  for (const [binding, label] of bindings) {
    requireCondition(
      binding && typeof binding.path === "string" && /^[a-f0-9]{64}$/u.test(binding.sha256),
      `${label}: byte-bound path and SHA-256 required`,
    );
    const bytes = bytesByPath.get(binding.path)
      ?? await readFile(path.join(repositoryRoot, binding.path));
    bytesByPath.set(binding.path, bytes);
    requireCondition(sha256(bytes) === binding.sha256, `${label}: bytes drifted`);
    if (binding.bytes !== undefined) {
      requireCondition(bytes.length === binding.bytes, `${label}: byte count drifted`);
    }
  }

  requireCondition(
    edit.parent.sha256 === composite.parent.sha256,
    "v21 and v22 must share the exact v10 parent",
  );
  requireCondition(
    edit.output.sha256 === composite.localEditSource.sha256,
    "v22 local source must be the exact rejected v21 bytes",
  );

  const parentHeader = pngHeader(bytesByPath.get(composite.parent.path), "v22 parent");
  const editHeader = pngHeader(bytesByPath.get(composite.localEditSource.path), "v22 edit");
  const maskHeader = pngHeader(bytesByPath.get(composite.authorizedMask.path), "v22 mask");
  const outputHeader = pngHeader(bytesByPath.get(composite.output.path), "v22 output");
  for (const [header, label] of [
    [parentHeader, "parent"],
    [editHeader, "edit"],
    [maskHeader, "mask"],
    [outputHeader, "output"],
  ]) {
    requireCondition(
      header.width === 853 && header.height === 1844 && header.bitDepth === 8,
      `${label}: exact 853x1844 8-bit raster required`,
    );
  }
  requireCondition(maskHeader.colorType === 0, "mask must remain an 8-bit grayscale PNG");
  requireCondition(
    outputHeader.width < 1290 || outputHeader.height < 2796,
    "v22 unexpectedly meets the master floor; its status requires a new gate",
  );

  const fullParentHeader = pngHeader(bytesByPath.get(fullResolution.parent.path), "v23 parent");
  const fullInputHeader = pngHeader(bytesByPath.get(fullResolution.inputCrop.path), "v23 input crop");
  const fullEditHeader = pngHeader(bytesByPath.get(fullResolution.localEditSource.path), "v23 edit");
  const fullMaskHeader = pngHeader(bytesByPath.get(fullResolution.authorizedMask.path), "v23 mask");
  const fullOutputHeader = pngHeader(bytesByPath.get(fullResolution.output.path), "v23 output");
  for (const [header, label] of [
    [fullParentHeader, "v23 parent"],
    [fullMaskHeader, "v23 mask"],
    [fullOutputHeader, "v23 output"],
  ]) {
    requireCondition(
      header.width === 1296 && header.height === 2800 && header.bitDepth === 8,
      `${label}: exact 1296x2800 8-bit raster required`,
    );
  }
  requireCondition(
    fullInputHeader.width === 880 && fullInputHeader.height === 880 && fullInputHeader.bitDepth === 8,
    "v23 input crop: exact 880x880 8-bit raster required",
  );
  requireCondition(
    fullEditHeader.width === 1254 && fullEditHeader.height === 1254 && fullEditHeader.bitDepth === 8,
    "v23 local source: exact 1254x1254 8-bit raster required",
  );
  requireCondition(fullMaskHeader.colorType === 0, "v23 mask must remain an 8-bit grayscale PNG");
  requireCondition(
    fullResolution.parent.path === `${designRoot}/production-master-candidate-v11.png`,
    "v23 must remain bound to the full-resolution v11 parent",
  );
  requireCondition(
    fullResolution.audit.dimensionFloorResult === "PASS_1290_X_2796_FLOOR",
    "v23 dimension-floor evidence drifted",
  );
  const canvasHeader = pngHeader(bytesByPath.get(canvasNormalized.output.path), "v24 output");
  requireCondition(
    canvasHeader.width === 1290 && canvasHeader.height === 2796 && canvasHeader.bitDepth === 8,
    "v24 output: exact 1290x2796 8-bit SceneSpec canvas required",
  );
  requireCondition(
    canvasNormalized.parent.path === fullResolution.output.path
      && canvasNormalized.parent.sha256 === fullResolution.output.sha256,
    "v24 must remain bound to the exact v23 full-resolution composite",
  );
  requireCondition(
    JSON.stringify(canvasNormalized.transform.crop)
      === JSON.stringify({ x: 3, y: 2, width: 1290, height: 2796 })
      && canvasNormalized.transform.resampling === false
      && canvasNormalized.transform.upscaling === false,
    "v24 canvas-normalization transform drifted",
  );
  const materialInputHeader = pngHeader(bytesByPath.get(materialCorrected.inputCrop.path), "v25 input crop");
  const materialEditHeader = pngHeader(bytesByPath.get(materialCorrected.localEditSource.path), "v25 edit");
  const materialMaskHeader = pngHeader(bytesByPath.get(materialCorrected.authorizedMask.path), "v25 mask");
  const materialOutputHeader = pngHeader(bytesByPath.get(materialCorrected.output.path), "v25 output");
  requireCondition(
    materialInputHeader.width === 900 && materialInputHeader.height === 900 && materialInputHeader.bitDepth === 8,
    "v25 input crop: exact 900x900 8-bit raster required",
  );
  requireCondition(
    materialEditHeader.width === 1254 && materialEditHeader.height === 1254 && materialEditHeader.bitDepth === 8,
    "v25 local source: exact 1254x1254 8-bit raster required",
  );
  for (const [header, label] of [
    [materialMaskHeader, "v25 mask"],
    [materialOutputHeader, "v25 output"],
  ]) {
    requireCondition(
      header.width === 1290 && header.height === 2796 && header.bitDepth === 8,
      `${label}: exact 1290x2796 8-bit SceneSpec canvas required`,
    );
  }
  requireCondition(materialMaskHeader.colorType === 0, "v25 mask must remain an 8-bit grayscale PNG");
  requireCondition(
    materialCorrected.parent.path === canvasNormalized.output.path
      && materialCorrected.parent.sha256 === canvasNormalized.output.sha256,
    "v25 must remain bound to the exact v24 canvas-normalized parent",
  );
  requireCondition(
    materialCorrected.codexPreflight.status === "CODEX_PROVISIONAL_NON_SHIPPING_REVIEW",
    "v25 preflight cannot claim editor or shipping authority",
  );
  const garmentInputHeader = pngHeader(
    bytesByPath.get(garmentCorrected.inputCrop.path),
    "v26 input crop",
  );
  const garmentEditHeader = pngHeader(
    bytesByPath.get(garmentCorrected.localEditSource.path),
    "v26 edit",
  );
  const garmentHardMaskHeader = pngHeader(
    bytesByPath.get(garmentCorrected.authorizedMask.hardRaster.path),
    "v26 hard mask",
  );
  const garmentMaskHeader = pngHeader(
    bytesByPath.get(garmentCorrected.authorizedMask.path),
    "v26 feathered mask",
  );
  const garmentOutputHeader = pngHeader(
    bytesByPath.get(garmentCorrected.output.path),
    "v26 output",
  );
  for (const [header, label] of [
    [garmentInputHeader, "v26 input crop"],
    [garmentHardMaskHeader, "v26 hard mask"],
    [garmentMaskHeader, "v26 feathered mask"],
  ]) {
    requireCondition(
      header.width === 1290 && header.height === 1290 && header.bitDepth === 8,
      `${label}: exact 1290x1290 8-bit raster required`,
    );
  }
  requireCondition(
    garmentEditHeader.width === 1254
      && garmentEditHeader.height === 1254
      && garmentEditHeader.bitDepth === 8,
    "v26 local source: exact 1254x1254 8-bit raster required",
  );
  requireCondition(
    garmentOutputHeader.width === 1290
      && garmentOutputHeader.height === 2796
      && garmentOutputHeader.bitDepth === 8,
    "v26 output: exact 1290x2796 8-bit SceneSpec canvas required",
  );
  requireCondition(
    garmentHardMaskHeader.colorType === 0 && garmentMaskHeader.colorType === 0,
    "v26 masks must remain 8-bit grayscale PNGs",
  );
  requireCondition(
    garmentCorrected.parent.path === materialCorrected.output.path
      && garmentCorrected.parent.sha256 === materialCorrected.output.sha256,
    "v26 must remain bound to the exact v25 material-corrected parent",
  );
  requireCondition(
    garmentCorrected.codexPreflight.status === "CODEX_PROVISIONAL_NON_SHIPPING_REVIEW",
    "v26 preflight cannot claim editor or shipping authority",
  );

  const rectangle = composite.compositor.authorizedBoundingRectangle;
  requireCondition(
    JSON.stringify(rectangle) === JSON.stringify({ x: 20, y: 1010, width: 136, height: 100 }),
    "authorized local-edit rectangle drifted",
  );
  const outsideRegions = {
    above: "853:1010:0:0",
    below: "853:734:0:1110",
    left: "20:100:0:1010",
    right: "697:100:156:1010",
  };
  const parentPath = path.join(repositoryRoot, composite.parent.path);
  const outputPath = path.join(repositoryRoot, composite.output.path);
  for (const [name, crop] of Object.entries(outsideRegions)) {
    const [parentHash, outputHash] = await Promise.all([
      rawFrameHash(parentPath, crop),
      rawFrameHash(outputPath, crop),
    ]);
    requireCondition(parentHash === outputHash, `v22 changed pixels in outside region '${name}'`);
    requireCondition(
      composite.audit.outsideRegionRawFrameHashes[name] === parentHash,
      `v22 stored outside-region hash '${name}' drifted`,
    );
  }

  const fullRectangle = fullResolution.authorizedMask.nonZeroBoundingRectangle;
  requireCondition(
    JSON.stringify(fullRectangle) === JSON.stringify({ x: 30, y: 1651, width: 161, height: 125 }),
    "v23 authorized local-edit rectangle drifted",
  );
  const fullOutsideRegions = {
    above: "1296:1651:0:0",
    below: "1296:1024:0:1776",
    left: "30:125:0:1651",
    right: "1105:125:191:1651",
  };
  const fullParentPath = path.join(repositoryRoot, fullResolution.parent.path);
  const fullOutputPath = path.join(repositoryRoot, fullResolution.output.path);
  for (const [name, crop] of Object.entries(fullOutsideRegions)) {
    const [parentHash, outputHash] = await Promise.all([
      rawFrameHash(fullParentPath, crop),
      rawFrameHash(fullOutputPath, crop),
    ]);
    requireCondition(parentHash === outputHash, `v23 changed pixels in outside region '${name}'`);
    requireCondition(
      fullResolution.audit.outsideRegionRawFrameHashes[name] === parentHash,
      `v23 stored outside-region hash '${name}' drifted`,
    );
  }

  const [parentCropHash, canvasOutputHash] = await Promise.all([
    rawFrameHash(fullOutputPath, "1290:2796:3:2"),
    rawFrameHash(path.join(repositoryRoot, canvasNormalized.output.path), "1290:2796:0:0"),
  ]);
  requireCondition(parentCropHash === canvasOutputHash, "v24 pixels are not the exact declared v23 crop");
  requireCondition(
    canvasNormalized.audit.parentCropRawFrameSHA256 === parentCropHash
      && canvasNormalized.audit.outputRawFrameSHA256 === canvasOutputHash,
    "v24 stored raw-frame crop evidence drifted",
  );

  const materialRectangle = materialCorrected.authorizedMask.nonZeroBoundingRectangle;
  requireCondition(
    JSON.stringify(materialRectangle) === JSON.stringify({ x: 260, y: 2120, width: 791, height: 551 }),
    "v25 authorized grain rectangle drifted",
  );
  const materialOutsideRegions = {
    above: "1290:2120:0:0",
    below: "1290:125:0:2671",
    left: "260:551:0:2120",
    right: "239:551:1051:2120",
  };
  const materialParentPath = path.join(repositoryRoot, materialCorrected.parent.path);
  const materialOutputPath = path.join(repositoryRoot, materialCorrected.output.path);
  for (const [name, crop] of Object.entries(materialOutsideRegions)) {
    const [parentHash, outputHash] = await Promise.all([
      rawFrameHash(materialParentPath, crop),
      rawFrameHash(materialOutputPath, crop),
    ]);
    requireCondition(parentHash === outputHash, `v25 changed pixels in outside region '${name}'`);
    requireCondition(
      materialCorrected.audit.outsideRegionRawFrameHashes[name] === parentHash,
      `v25 stored outside-region hash '${name}' drifted`,
    );
  }

  const garmentOutsideRegions = {
    aboveY1180: "1290:1180:0:0",
    belowY2300: "1290:496:0:2300",
    leftX60: "60:2796:0:0",
  };
  const garmentParentPath = path.join(repositoryRoot, garmentCorrected.parent.path);
  const garmentOutputPath = path.join(repositoryRoot, garmentCorrected.output.path);
  for (const [name, crop] of Object.entries(garmentOutsideRegions)) {
    const [parentHash, outputHash] = await Promise.all([
      rawFrameHash(garmentParentPath, crop),
      rawFrameHash(garmentOutputPath, crop),
    ]);
    requireCondition(parentHash === outputHash, `v26 changed pixels in outside region '${name}'`);
    requireCondition(
      garmentCorrected.audit.outsideRegionRawFrameHashes[name] === parentHash,
      `v26 stored outside-region hash '${name}' drifted`,
    );
  }

  return {
    status: composite.status,
    outputSHA256: composite.output.sha256,
    isolationRegions: Object.keys(outsideRegions).length,
    fullResolutionStatus: fullResolution.status,
    fullResolutionOutputSHA256: fullResolution.output.sha256,
    fullResolutionIsolationRegions: Object.keys(fullOutsideRegions).length,
    canvasNormalizedStatus: canvasNormalized.status,
    canvasNormalizedOutputSHA256: canvasNormalized.output.sha256,
    materialCorrectedStatus: materialCorrected.status,
    materialCorrectedOutputSHA256: materialCorrected.output.sha256,
    materialCorrectedIsolationRegions: Object.keys(materialOutsideRegions).length,
    garmentCorrectedStatus: garmentCorrected.status,
    garmentCorrectedOutputSHA256: garmentCorrected.output.sha256,
    garmentCorrectedIsolationRegions: Object.keys(garmentOutsideRegions).length,
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  validateHarvestLocalComposite().then((result) => {
    process.stdout.write(
      `Validated Harvest v22 ${result.outputSHA256}, full-resolution v23 ${result.fullResolutionOutputSHA256}, exact-canvas v24 ${result.canvasNormalizedOutputSHA256}, material-corrected v25 ${result.materialCorrectedOutputSHA256}, and garment-corrected v26 ${result.garmentCorrectedOutputSHA256}; audited pixels remain isolated and every candidate remains non-shipping.\n`,
    );
  }).catch((error) => {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
  });
}
