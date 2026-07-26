import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdtempSync,
  rmSync,
} from "node:fs";
import {
  copyFile,
  mkdir,
  readFile,
  stat,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { deflateSync } from "node:zlib";

const SHA256 = /^[a-f0-9]{64}$/u;
const STABLE_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
const SAFE_RELATIVE_PATH = /^(?!\/)(?!.*(?:^|\/)\.\.(?:\/|$))(?!.*\\)[a-zA-Z0-9._/-]+$/u;
const MASK_FIELDS = Object.freeze({
  alphaMaskAssetPath: "alpha",
  depthMaskAssetPath: "depth",
  lightMaskAssetPath: "light",
  occlusionMaskAssetPath: "occlusion",
});
const MASK_TYPES = new Set(["alpha", "depth", "light", "occlusion", "atmosphere", "authorization"]);
const SOURCE_KINDS = new Set(["approved-master", "provisional-master", "clean-plate", "layer-plate", "state-plate", "authored-mask"]);
const OPERATION_KINDS = new Set(["normalize-mask", "normalize-raster", "extract-layer", "encode-heif", "copy-source"]);
const FINAL_ASSET_KINDS = new Set(["scene-layer", "scene-mask", "reduce-motion-plate"]);
export const visualProductionBuildModes = Object.freeze({
  editorApproved: "EDITOR_APPROVED_PRODUCTION_MASTER",
  codexProvisional: "CODEX_PROVISIONAL_NON_SHIPPING_DEVELOPMENT",
});
export const provisionalVisualMasterStatus = "CODEX_PROVISIONAL_NON_SHIPPING_PRODUCTION_MASTER";
const provisionalDAGStatus = "CODEX_PROVISIONAL_NON_SHIPPING_INPUTS_LOCKED";
const editorApprovedDAGStatus = "PRODUCTION_INPUTS_LOCKED";
const provisionalPreflightStatus = "CODEX_PROVISIONAL_NON_SHIPPING_REVIEW";
const provisionalReceiptStatus = "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_REPRODUCTION_PASS";
const editorApprovedReceiptStatus = "TECHNICAL_REPRODUCTION_PASS_NOT_SHIPPING_APPROVAL";

export class VisualProductionError extends Error {
  constructor(issues) {
    super(issues.join("\n"));
    this.name = "VisualProductionError";
    this.issues = issues;
  }
}

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const clone = (value) => JSON.parse(JSON.stringify(value));
const hashBytes = (bytes) => createHash("sha256").update(bytes).digest("hex");

export function canonicalJSON(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (isObject(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJSON(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export const canonicalSHA256 = (value) => hashBytes(Buffer.from(canonicalJSON(value)));

function exactKeys(value, required, optional, location, issues) {
  if (!isObject(value)) {
    issues.push(`${location}: object required`);
    return false;
  }
  const requiredSet = new Set(required);
  const allowed = new Set([...required, ...optional]);
  for (const key of required) {
    if (!Object.hasOwn(value, key)) issues.push(`${location}.${key}: required`);
  }
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) issues.push(`${location}.${key}: unknown field`);
  }
  return required.every((key) => requiredSet.has(key) && Object.hasOwn(value, key));
}

function stableID(value, location, issues) {
  if (typeof value !== "string" || !STABLE_ID.test(value)) {
    issues.push(`${location}: stable lowercase ID required`);
    return false;
  }
  return true;
}

function safePath(value, location, issues) {
  if (typeof value !== "string" || !SAFE_RELATIVE_PATH.test(value)) {
    issues.push(`${location}: safe repository-relative path required`);
    return false;
  }
  return true;
}

function sha256(value, location, issues) {
  if (typeof value !== "string" || !SHA256.test(value)) {
    issues.push(`${location}: lowercase SHA-256 required`);
    return false;
  }
  return true;
}

function integer(value, location, issues, minimum = 0) {
  if (!Number.isSafeInteger(value) || value < minimum) {
    issues.push(`${location}: integer >= ${minimum} required`);
    return false;
  }
  return true;
}

function finite(value, location, issues, minimum = -Infinity, maximum = Infinity) {
  if (!Number.isFinite(value) || value < minimum || value > maximum) {
    issues.push(`${location}: finite number between ${minimum} and ${maximum} required`);
    return false;
  }
  return true;
}

function validateFrame(frame, location, issues) {
  if (!exactKeys(frame, ["x", "y", "width", "height"], [], location, issues)) return false;
  for (const key of ["x", "y", "width", "height"]) finite(frame[key], `${location}.${key}`, issues, 0, 1);
  if (frame.width <= 0 || frame.height <= 0 || frame.x + frame.width > 1 + 1e-9 || frame.y + frame.height > 1 + 1e-9) {
    issues.push(`${location}: positive normalized frame must remain inside the master canvas`);
    return false;
  }
  return true;
}

export function pixelRect(frame, canvas) {
  const x = Math.floor(frame.x * canvas.width + 1e-9);
  const y = Math.floor(frame.y * canvas.height + 1e-9);
  const right = Math.ceil((frame.x + frame.width) * canvas.width - 1e-9);
  const bottom = Math.ceil((frame.y + frame.height) * canvas.height - 1e-9);
  return { x, y, width: right - x, height: bottom - y };
}

function frameEqual(left, right) {
  return ["x", "y", "width", "height"].every((key) => Math.abs(left[key] - right[key]) < 1e-12);
}

function frameContains(container, item) {
  return item.x >= container.x - 1e-9
    && item.y >= container.y - 1e-9
    && item.x + item.width <= container.x + container.width + 1e-9
    && item.y + item.height <= container.y + container.height + 1e-9;
}

function addInventoryAsset(output, record) {
  if (output.byPath.has(record.assetPath)) {
    output.issues.push(`scene fixture: duplicate future asset path '${record.assetPath}'`);
    return;
  }
  output.byPath.set(record.assetPath, record);
  output.assets.push(record);
}

export function sceneVisualInventory(fixture) {
  const issues = [];
  const scene = fixture?.scene;
  const canvas = scene?.sceneCanvas?.canvas;
  if (!isObject(scene) || !isObject(canvas) || !Number.isSafeInteger(canvas.width) || !Number.isSafeInteger(canvas.height)) {
    throw new VisualProductionError(["scene fixture: valid SceneSpec canvas required"]);
  }
  const output = { assets: [], byPath: new Map(), issues };
  for (const layer of scene.layers ?? []) {
    const rect = pixelRect(layer.frame, canvas);
    addInventoryAsset(output, {
      assetPath: layer.assetPath,
      kind: "scene-layer",
      ownerID: layer.id,
      variantID: null,
      maskType: null,
      frame: clone(layer.frame),
      pixelRect: rect,
      order: layer.order,
      blendMode: layer.blendMode,
      opacity: layer.opacity,
    });
    for (const [field, maskType] of Object.entries(MASK_FIELDS)) {
      if (!layer.masks?.[field]) continue;
      addInventoryAsset(output, {
        assetPath: layer.masks[field],
        kind: "scene-mask",
        ownerID: layer.id,
        variantID: null,
        maskType,
        frame: clone(layer.frame),
        pixelRect: rect,
        order: layer.order,
      });
    }
    for (const variant of layer.stateVariants ?? []) {
      addInventoryAsset(output, {
        assetPath: variant.assetPath,
        kind: "scene-layer",
        ownerID: layer.id,
        variantID: variant.id,
        maskType: null,
        frame: clone(layer.frame),
        pixelRect: rect,
        order: layer.order,
        blendMode: layer.blendMode,
        opacity: layer.opacity,
      });
      for (const [field, maskType] of Object.entries(MASK_FIELDS)) {
        if (!variant.masks?.[field]) continue;
        addInventoryAsset(output, {
          assetPath: variant.masks[field],
          kind: "scene-mask",
          ownerID: layer.id,
          variantID: variant.id,
          maskType,
          frame: clone(layer.frame),
          pixelRect: rect,
          order: layer.order,
        });
      }
    }
  }
  for (const stratum of scene.reduceMotionComposition?.strata ?? []) {
    if (stratum.kind !== "staticPlate") continue;
    addInventoryAsset(output, {
      assetPath: stratum.assetPath,
      kind: "reduce-motion-plate",
      ownerID: stratum.id,
      variantID: null,
      maskType: null,
      frame: { x: 0, y: 0, width: 1, height: 1 },
      pixelRect: { x: 0, y: 0, width: canvas.width, height: canvas.height },
      order: null,
      blendMode: "normal",
      opacity: 1,
    });
  }
  if (issues.length) throw new VisualProductionError(issues);
  const counts = output.assets.reduce((result, asset) => {
    result.total += 1;
    if (asset.kind === "scene-layer" && asset.variantID === null) result.baseLayers += 1;
    else if (asset.kind === "scene-layer") result.stateFiles += 1;
    else if (asset.kind === "scene-mask" && asset.variantID === null) result.baseMasks += 1;
    else if (asset.kind === "scene-mask") result.stateFiles += 1;
    else if (asset.kind === "reduce-motion-plate") result.reduceMotionPlates += 1;
    return result;
  }, { total: 0, baseLayers: 0, baseMasks: 0, stateFiles: 0, reduceMotionPlates: 0 });
  return { ...output, canvas: clone(canvas), counts };
}

async function exactFileRecord(repositoryRoot, record, location, issues) {
  if (!safePath(record.path, `${location}.path`, issues)) return undefined;
  integer(record.bytes, `${location}.bytes`, issues, 1);
  sha256(record.sha256, `${location}.sha256`, issues);
  const resolved = path.resolve(repositoryRoot, record.path);
  if (!resolved.startsWith(`${path.resolve(repositoryRoot)}${path.sep}`)) {
    issues.push(`${location}.path: escaped repository root`);
    return undefined;
  }
  try {
    const bytes = await readFile(resolved);
    if (bytes.byteLength !== record.bytes || hashBytes(bytes) !== record.sha256) {
      issues.push(`${location}: exact bytes or SHA-256 drifted`);
    }
    return { resolved, bytes };
  } catch (error) {
    issues.push(`${location}.path: ${error.message}`);
    return undefined;
  }
}

function validateToolReferences(toolIDs, contractToolIDs, costByID, location, issues) {
  if (!Array.isArray(toolIDs) || toolIDs.length === 0) {
    issues.push(`${location}: at least one tool ID required`);
    return;
  }
  if (new Set(toolIDs).size !== toolIDs.length) issues.push(`${location}: duplicate tool ID`);
  for (const [index, toolID] of toolIDs.entries()) {
    stableID(toolID, `${location}[${index}]`, issues);
    if (!contractToolIDs.has(toolID)) issues.push(`${location}[${index}]: tool is outside the frozen visual contract`);
    const tool = costByID.get(toolID);
    if (!tool || tool.incrementalCostNOK !== 0 || tool.billingCredentialRequired !== false
        || tool.commercialUse !== "allowed" || !String(tool.version ?? "").trim()
        || !String(tool.license ?? "").trim()) {
      issues.push(`${location}[${index}]: exact zero-cost commercially cleared registry entry required`);
    }
  }
}

function validatePixelRect(rect, canvas, location, issues) {
  if (!exactKeys(rect, ["x", "y", "width", "height"], [], location, issues)) return false;
  integer(rect.x, `${location}.x`, issues);
  integer(rect.y, `${location}.y`, issues);
  integer(rect.width, `${location}.width`, issues, 1);
  integer(rect.height, `${location}.height`, issues, 1);
  if (Number.isSafeInteger(rect.x) && Number.isSafeInteger(rect.y)
      && Number.isSafeInteger(rect.width) && Number.isSafeInteger(rect.height)
      && (rect.x + rect.width > canvas.width || rect.y + rect.height > canvas.height)) {
    issues.push(`${location}: measured crop must remain inside the master canvas`);
    return false;
  }
  return true;
}

function validatePixelBounds(bounds, location, issues) {
  if (!exactKeys(bounds, ["minX", "minY", "maxX", "maxY"], [], location, issues)) return false;
  for (const key of ["minX", "minY", "maxX", "maxY"]) integer(bounds[key], `${location}.${key}`, issues);
  if (Number.isSafeInteger(bounds.minX) && Number.isSafeInteger(bounds.minY)
      && Number.isSafeInteger(bounds.maxX) && Number.isSafeInteger(bounds.maxY)
      && (bounds.maxX < bounds.minX || bounds.maxY < bounds.minY)) {
    issues.push(`${location}: inclusive maximums must not precede minimums`);
    return false;
  }
  return true;
}

async function validateMeasuredUnderlayRecipe({
  recipe,
  underlay,
  canvas,
  contractToolIDs,
  costByID,
  repositoryRoot,
  location,
  issues,
}) {
  exactKeys(recipe, [
    "status", "toolIDs", "sourceMaster", "cropPixels", "targetFileName",
    "sourceAuthority",
    "authorizationMaskSourcePath", "authorizationMaskWorkingPath",
    "subjectMask", "donorMask", "excludedOccluderMask", "usableDonorPixelCount",
    "maskPreparation", "fill",
  ], [], location, issues);
  if (recipe.status !== "MEASURED") issues.push(`${location}.status: MEASURED required for a complete recipe`);
  validateToolReferences(recipe.toolIDs, contractToolIDs, costByID, `${location}.toolIDs`, issues);
  await validateExactAncillaryFile(repositoryRoot, recipe.sourceMaster, `${location}.sourceMaster`, issues);
  await validateExactAncillaryFile(repositoryRoot, recipe.sourceAuthority, `${location}.sourceAuthority`, issues);
  validatePixelRect(recipe.cropPixels, canvas, `${location}.cropPixels`, issues);
  if (typeof recipe.targetFileName !== "string" || recipe.targetFileName.includes("/")
      || !/^[a-z0-9]+(?:-[a-z0-9]+)*\.png$/u.test(recipe.targetFileName)) {
    issues.push(`${location}.targetFileName: lowercase PNG filename required`);
  } else if (path.posix.basename(underlay.sourceLayerPlatePath) !== recipe.targetFileName) {
    issues.push(`${location}.targetFileName: must name the declared layer-plate input`);
  }
  safePath(recipe.authorizationMaskSourcePath, `${location}.authorizationMaskSourcePath`, issues);
  safePath(recipe.authorizationMaskWorkingPath, `${location}.authorizationMaskWorkingPath`, issues);
  if (recipe.authorizationMaskSourcePath === underlay.sourceLayerPlatePath
      || recipe.authorizationMaskWorkingPath === underlay.workingPath) {
    issues.push(`${location}: authorization mask paths must remain separate from raster paths`);
  }

  exactKeys(recipe.subjectMask, [
    "id", "path", "sha256", "sourceBoundsPixels", "cropLocalBoundsPixels",
  ], [], `${location}.subjectMask`, issues);
  stableID(recipe.subjectMask?.id, `${location}.subjectMask.id`, issues);
  await validateExactAncillaryFile(repositoryRoot, {
    path: recipe.subjectMask?.path,
    sha256: recipe.subjectMask?.sha256,
  }, `${location}.subjectMask`, issues);
  const sourceBoundsValid = validatePixelBounds(recipe.subjectMask?.sourceBoundsPixels, `${location}.subjectMask.sourceBoundsPixels`, issues);
  const localBoundsValid = validatePixelBounds(recipe.subjectMask?.cropLocalBoundsPixels, `${location}.subjectMask.cropLocalBoundsPixels`, issues);
  const crop = recipe.cropPixels;
  const sourceBounds = recipe.subjectMask?.sourceBoundsPixels;
  const localBounds = recipe.subjectMask?.cropLocalBoundsPixels;
  if (sourceBoundsValid && localBoundsValid && Number.isSafeInteger(crop?.x) && Number.isSafeInteger(crop?.y)) {
    if (sourceBounds.minX - crop.x !== localBounds.minX
        || sourceBounds.minY - crop.y !== localBounds.minY
        || sourceBounds.maxX - crop.x !== localBounds.maxX
        || sourceBounds.maxY - crop.y !== localBounds.maxY) {
      issues.push(`${location}.subjectMask.cropLocalBoundsPixels: must be the exact crop-local projection of source bounds`);
    }
    if (localBounds.minX < 0 || localBounds.minY < 0
        || localBounds.maxX >= crop.width || localBounds.maxY >= crop.height) {
      issues.push(`${location}.subjectMask.cropLocalBoundsPixels: measured subject must remain inside the crop`);
    }
  }

  for (const key of ["donorMask", "excludedOccluderMask"]) {
    const record = recipe[key];
    exactKeys(record, ["id", "path", "sha256"], [], `${location}.${key}`, issues);
    stableID(record?.id, `${location}.${key}.id`, issues);
    await validateExactAncillaryFile(repositoryRoot, {
      path: record?.path,
      sha256: record?.sha256,
    }, `${location}.${key}`, issues);
  }
  integer(recipe.usableDonorPixelCount, `${location}.usableDonorPixelCount`, issues, 1);
  if (Number.isSafeInteger(recipe.usableDonorPixelCount)
      && Number.isSafeInteger(crop?.width) && Number.isSafeInteger(crop?.height)
      && recipe.usableDonorPixelCount > crop.width * crop.height) {
    issues.push(`${location}.usableDonorPixelCount: cannot exceed the measured crop area`);
  }

  exactKeys(recipe.maskPreparation, [
    "closeRadiusPixels", "dilatePixels", "subtractForegroundOccluders",
  ], [], `${location}.maskPreparation`, issues);
  integer(recipe.maskPreparation?.closeRadiusPixels, `${location}.maskPreparation.closeRadiusPixels`, issues);
  integer(recipe.maskPreparation?.dilatePixels, `${location}.maskPreparation.dilatePixels`, issues);
  if (recipe.maskPreparation?.subtractForegroundOccluders !== true) {
    issues.push(`${location}.maskPreparation.subtractForegroundOccluders: must be true`);
  }

  exactKeys(recipe.fill, [
    "method", "mirrorAllowed", "rotationDegrees", "scale", "sourceBuiltSeamRingPixels",
  ], [], `${location}.fill`, issues);
  if (recipe.fill?.method !== "SOURCE_ONLY_MULTI_RESOLUTION_PATCHMATCH") {
    issues.push(`${location}.fill.method: source-only multi-resolution PatchMatch required`);
  }
  if (recipe.fill?.mirrorAllowed !== false) issues.push(`${location}.fill.mirrorAllowed: mirroring is forbidden`);
  exactKeys(recipe.fill?.rotationDegrees, ["minimum", "maximum"], [], `${location}.fill.rotationDegrees`, issues);
  finite(recipe.fill?.rotationDegrees?.minimum, `${location}.fill.rotationDegrees.minimum`, issues, -180, 180);
  finite(recipe.fill?.rotationDegrees?.maximum, `${location}.fill.rotationDegrees.maximum`, issues, -180, 180);
  if (recipe.fill?.rotationDegrees?.minimum > recipe.fill?.rotationDegrees?.maximum) {
    issues.push(`${location}.fill.rotationDegrees: minimum cannot exceed maximum`);
  }
  exactKeys(recipe.fill?.scale, ["minimum", "maximum"], [], `${location}.fill.scale`, issues);
  finite(recipe.fill?.scale?.minimum, `${location}.fill.scale.minimum`, issues, 0.01, 100);
  finite(recipe.fill?.scale?.maximum, `${location}.fill.scale.maximum`, issues, 0.01, 100);
  if (recipe.fill?.scale?.minimum > recipe.fill?.scale?.maximum) issues.push(`${location}.fill.scale: minimum cannot exceed maximum`);
  integer(recipe.fill?.sourceBuiltSeamRingPixels, `${location}.fill.sourceBuiltSeamRingPixels`, issues, 1);
}

export async function validateVisualProductionContract({
  contract,
  fixture,
  fixtureBytes,
  costRegistry,
  repositoryRoot,
  contractRepositoryPath = undefined,
}) {
  const issues = [];
  const commonContractKeys = [
    "schemaVersion", "id", "status", "sceneFixturePath", "sceneFixtureSHA256",
    "expectedSceneID", "canvas", "requiredFinalAssets", "toolchain",
    "auxiliaryMasks", "stateVariantPolicies",
    "recompositionGate", "encodingGate", "productionRules",
  ];
  if (contract.schemaVersion === 1) {
    exactKeys(contract, [...commonContractKeys, "cleanPlateCoverage"], [], "visual contract", issues);
  } else if (contract.schemaVersion === 2) {
    exactKeys(contract, [
      ...commonContractKeys,
      "disocclusionCoverageRule", "disocclusionUnderlays", "disocclusionExemptions",
    ], [], "visual contract", issues);
  } else {
    exactKeys(contract, commonContractKeys, [
      "cleanPlateCoverage", "disocclusionCoverageRule", "disocclusionUnderlays", "disocclusionExemptions",
    ], "visual contract", issues);
    issues.push("visual contract.schemaVersion: expected 1 or 2");
  }
  stableID(contract.id, "visual contract.id", issues);
  if (contract.status !== "NON_SHIPPING_PRODUCTION_CONTRACT") {
    issues.push("visual contract.status: must remain NON_SHIPPING_PRODUCTION_CONTRACT");
  }
  safePath(contract.sceneFixturePath, "visual contract.sceneFixturePath", issues);
  sha256(contract.sceneFixtureSHA256, "visual contract.sceneFixtureSHA256", issues);
  if (fixtureBytes && hashBytes(fixtureBytes) !== contract.sceneFixtureSHA256) {
    issues.push("visual contract.sceneFixtureSHA256: fixture bytes drifted");
  }
  if (fixture?.scene?.id !== contract.expectedSceneID) issues.push("visual contract.expectedSceneID: scene binding drifted");
  const inventory = sceneVisualInventory(fixture);
  if (!isObject(contract.canvas) || contract.canvas.width !== inventory.canvas.width || contract.canvas.height !== inventory.canvas.height) {
    issues.push("visual contract.canvas: must equal the SceneSpec master canvas");
  }
  exactKeys(contract.requiredFinalAssets, ["total", "baseLayers", "baseMasks", "stateFiles", "reduceMotionPlates"], [], "visual contract.requiredFinalAssets", issues);
  for (const [key, expected] of Object.entries(inventory.counts)) {
    if (contract.requiredFinalAssets?.[key] !== expected) {
      issues.push(`visual contract.requiredFinalAssets.${key}: expected ${expected}`);
    }
  }

  if (!Array.isArray(costRegistry?.entries)) issues.push("visual contract: cost registry entries are required");
  const costByID = new Map((Array.isArray(costRegistry?.entries) ? costRegistry.entries : []).map((entry) => [entry.id, entry]));
  const toolIDs = new Set();
  if (!Array.isArray(contract.toolchain) || contract.toolchain.length === 0) issues.push("visual contract.toolchain: non-empty array required");
  for (const [index, tool] of (Array.isArray(contract.toolchain) ? contract.toolchain : []).entries()) {
    const location = `visual contract.toolchain[${index}]`;
    exactKeys(tool, ["toolID", "version", "license"], [], location, issues);
    stableID(tool.toolID, `${location}.toolID`, issues);
    if (toolIDs.has(tool.toolID)) issues.push(`${location}.toolID: duplicate`);
    toolIDs.add(tool.toolID);
    const registered = costByID.get(tool.toolID);
    if (!registered || registered.version !== tool.version || registered.license !== tool.license
        || registered.incrementalCostNOK !== 0 || registered.billingCredentialRequired !== false
        || registered.commercialUse !== "allowed") {
      issues.push(`${location}: must exactly match a commercially cleared zero-cost registry entry`);
    }
  }

  const alphaLayerIDs = new Set(inventory.assets
    .filter((asset) => asset.kind === "scene-mask" && asset.maskType === "alpha" && asset.variantID === null)
    .map((asset) => asset.ownerID));
  if (contract.schemaVersion === 1) {
    const coveredLayers = [];
    const cleanPlateIDs = new Set();
    if (!Array.isArray(contract.cleanPlateCoverage) || contract.cleanPlateCoverage.length === 0) issues.push("visual contract.cleanPlateCoverage: non-empty array required");
    for (const [index, plate] of (Array.isArray(contract.cleanPlateCoverage) ? contract.cleanPlateCoverage : []).entries()) {
      const location = `visual contract.cleanPlateCoverage[${index}]`;
      exactKeys(plate, ["id", "workingPath", "frame", "coversLayerIDs"], [], location, issues);
      stableID(plate.id, `${location}.id`, issues);
      safePath(plate.workingPath, `${location}.workingPath`, issues);
      validateFrame(plate.frame, `${location}.frame`, issues);
      if (cleanPlateIDs.has(plate.id)) issues.push(`${location}.id: duplicate`);
      cleanPlateIDs.add(plate.id);
      if (!Array.isArray(plate.coversLayerIDs) || plate.coversLayerIDs.length === 0) issues.push(`${location}.coversLayerIDs: non-empty array required`);
      for (const [layerIndex, layerID] of (plate.coversLayerIDs ?? []).entries()) {
        stableID(layerID, `${location}.coversLayerIDs[${layerIndex}]`, issues);
        if (!alphaLayerIDs.has(layerID)) issues.push(`${location}.coversLayerIDs[${layerIndex}]: only alpha-separated base layers require clean coverage`);
        coveredLayers.push(layerID);
      }
    }
    if (new Set(coveredLayers).size !== coveredLayers.length) issues.push("visual contract.cleanPlateCoverage: each alpha-separated layer must be covered exactly once");
    if ([...alphaLayerIDs].some((id) => !coveredLayers.includes(id))) issues.push("visual contract.cleanPlateCoverage: incomplete disocclusion coverage");
  } else if (contract.schemaVersion === 2) {
    exactKeys(contract.disocclusionCoverageRule, [
      "eligibleLayerRule", "excludedBlendModes",
    ], [], "visual contract.disocclusionCoverageRule", issues);
    if (contract.disocclusionCoverageRule?.eligibleLayerRule !== "ALPHA_MASKED_NORMAL_BLEND") {
      issues.push("visual contract.disocclusionCoverageRule.eligibleLayerRule: ALPHA_MASKED_NORMAL_BLEND required");
    }
    if (canonicalJSON(contract.disocclusionCoverageRule?.excludedBlendModes) !== canonicalJSON(["screen"])) {
      issues.push("visual contract.disocclusionCoverageRule.excludedBlendModes: screen must be the explicit non-normal exclusion");
    }
    const baseLayersByID = new Map(inventory.assets
      .filter((asset) => asset.kind === "scene-layer" && asset.variantID === null)
      .map((asset) => [asset.ownerID, asset]));
    const eligibleLayerIDs = new Set([...alphaLayerIDs].filter((id) => baseLayersByID.get(id)?.blendMode === "normal"));
    const nonNormalAlphaLayers = [...alphaLayerIDs].filter((id) => baseLayersByID.get(id)?.blendMode !== "normal");
    for (const layerID of nonNormalAlphaLayers) {
      if (!contract.disocclusionCoverageRule?.excludedBlendModes?.includes(baseLayersByID.get(layerID)?.blendMode)) {
        issues.push(`visual contract.disocclusionCoverageRule: alpha layer '${layerID}' has an undeclared excluded blend mode`);
      }
    }

    const accountedLayerIDs = [];
    const underlayIDs = new Set();
    const sourcePaths = new Set();
    const workingPaths = new Set();
    if (!Array.isArray(contract.disocclusionUnderlays) || contract.disocclusionUnderlays.length === 0) {
      issues.push("visual contract.disocclusionUnderlays: non-empty array required");
    }
    for (const [index, underlay] of (Array.isArray(contract.disocclusionUnderlays) ? contract.disocclusionUnderlays : []).entries()) {
      const location = `visual contract.disocclusionUnderlays[${index}]`;
      exactKeys(underlay, [
        "id", "layerID", "sourceLayerPlatePath", "workingPath", "frame", "coverageMode", "recipe",
      ], [], location, issues);
      stableID(underlay.id, `${location}.id`, issues);
      stableID(underlay.layerID, `${location}.layerID`, issues);
      safePath(underlay.sourceLayerPlatePath, `${location}.sourceLayerPlatePath`, issues);
      safePath(underlay.workingPath, `${location}.workingPath`, issues);
      validateFrame(underlay.frame, `${location}.frame`, issues);
      if (underlayIDs.has(underlay.id)) issues.push(`${location}.id: duplicate`);
      underlayIDs.add(underlay.id);
      if (sourcePaths.has(underlay.sourceLayerPlatePath)) issues.push(`${location}.sourceLayerPlatePath: duplicate`);
      sourcePaths.add(underlay.sourceLayerPlatePath);
      if (workingPaths.has(underlay.workingPath)) issues.push(`${location}.workingPath: duplicate`);
      workingPaths.add(underlay.workingPath);
      if (!eligibleLayerIDs.has(underlay.layerID)) {
        issues.push(`${location}.layerID: only alpha-masked normal-blend layers require an underlay or exemption`);
      }
      const layer = baseLayersByID.get(underlay.layerID);
      if (!["RAIL_BOUNDED", "FULL_STATE_AND_RAIL"].includes(underlay.coverageMode)) {
        issues.push(`${location}.coverageMode: RAIL_BOUNDED or FULL_STATE_AND_RAIL required`);
      }
      if (underlay.layerID === "central-harvest" && underlay.coverageMode !== "FULL_STATE_AND_RAIL") {
        issues.push(`${location}.coverageMode: central-harvest requires FULL_STATE_AND_RAIL`);
      } else if (underlay.layerID !== "central-harvest" && underlay.coverageMode !== "RAIL_BOUNDED") {
        issues.push(`${location}.coverageMode: non-central underlays require RAIL_BOUNDED`);
      }
      if (!isObject(underlay.recipe)) {
        issues.push(`${location}.recipe: object required`);
      } else if (underlay.recipe.status === "PENDING_MEASUREMENT") {
        exactKeys(underlay.recipe, ["status"], [], `${location}.recipe`, issues);
        if (layer && !frameEqual(underlay.frame, layer.frame)) {
          issues.push(`${location}.frame: a pending recipe must retain the owning SceneSpec layer frame as its explicit placeholder`);
        }
      } else {
        await validateMeasuredUnderlayRecipe({
          recipe: underlay.recipe,
          underlay,
          canvas: inventory.canvas,
          contractToolIDs: toolIDs,
          costByID,
          repositoryRoot,
          location: `${location}.recipe`,
          issues,
        });
        const crop = underlay.recipe.cropPixels;
        if (Number.isSafeInteger(crop?.x) && Number.isSafeInteger(crop?.y)
            && Number.isSafeInteger(crop?.width) && Number.isSafeInteger(crop?.height)) {
          const measuredFrame = {
            x: crop.x / inventory.canvas.width,
            y: crop.y / inventory.canvas.height,
            width: crop.width / inventory.canvas.width,
            height: crop.height / inventory.canvas.height,
          };
          if (!frameEqual(underlay.frame, measuredFrame)) {
            issues.push(`${location}.frame: measured underlay frame must be derived exactly from recipe.cropPixels`);
          }
        }
      }
      accountedLayerIDs.push(underlay.layerID);
    }

    const exemptionLayerIDs = new Set();
    if (!Array.isArray(contract.disocclusionExemptions)) issues.push("visual contract.disocclusionExemptions: array required");
    for (const [index, exemption] of (Array.isArray(contract.disocclusionExemptions) ? contract.disocclusionExemptions : []).entries()) {
      const location = `visual contract.disocclusionExemptions[${index}]`;
      exactKeys(exemption, [
        "layerID", "reasonCode", "relativeMotion", "revealsBackground",
      ], [], location, issues);
      stableID(exemption.layerID, `${location}.layerID`, issues);
      if (!eligibleLayerIDs.has(exemption.layerID)) issues.push(`${location}.layerID: exemption applies only to an eligible alpha-masked normal layer`);
      if (exemptionLayerIDs.has(exemption.layerID)) issues.push(`${location}.layerID: duplicate exemption`);
      exemptionLayerIDs.add(exemption.layerID);
      if (exemption.reasonCode !== "ZERO_RELATIVE_MOTION_NO_REVEAL"
          || exemption.relativeMotion !== "ZERO" || exemption.revealsBackground !== false) {
        issues.push(`${location}: exemption requires zero relative motion and no background reveal`);
      }
      accountedLayerIDs.push(exemption.layerID);
    }
    if (new Set(accountedLayerIDs).size !== accountedLayerIDs.length) {
      issues.push("visual contract.disocclusionUnderlays: each eligible layer must be accounted for exactly once");
    }
    if ([...eligibleLayerIDs].some((id) => !accountedLayerIDs.includes(id))) {
      issues.push("visual contract.disocclusionUnderlays: incomplete alpha-normal disocclusion coverage");
    }
  }

  const auxiliaryMaskIDs = new Set();
  const atmosphereMaskCount = { rain: 0, smoke: 0 };
  if (!Array.isArray(contract.auxiliaryMasks) || contract.auxiliaryMasks.length === 0) issues.push("visual contract.auxiliaryMasks: non-empty array required");
  for (const [index, mask] of (Array.isArray(contract.auxiliaryMasks) ? contract.auxiliaryMasks : []).entries()) {
    const location = `visual contract.auxiliaryMasks[${index}]`;
    exactKeys(mask, ["id", "maskType", "workingPath", "frame", "purpose"], ["atmosphereKind"], location, issues);
    stableID(mask.id, `${location}.id`, issues);
    if (!MASK_TYPES.has(mask.maskType) || !["atmosphere", "authorization"].includes(mask.maskType)) {
      issues.push(`${location}.maskType: atmosphere or authorization required`);
    }
    safePath(mask.workingPath, `${location}.workingPath`, issues);
    validateFrame(mask.frame, `${location}.frame`, issues);
    if (typeof mask.purpose !== "string" || !mask.purpose.trim()) issues.push(`${location}.purpose: authored purpose required`);
    if (auxiliaryMaskIDs.has(mask.id)) issues.push(`${location}.id: duplicate`);
    auxiliaryMaskIDs.add(mask.id);
    if (mask.maskType === "atmosphere") {
      if (!Object.hasOwn(atmosphereMaskCount, mask.atmosphereKind)) issues.push(`${location}.atmosphereKind: rain or smoke required`);
      else atmosphereMaskCount[mask.atmosphereKind] += 1;
    } else if (Object.hasOwn(mask, "atmosphereKind")) {
      issues.push(`${location}.atmosphereKind: forbidden for authorization masks`);
    }
  }
  for (const [kind, count] of Object.entries(atmosphereMaskCount)) {
    if (count < 2) issues.push(`visual contract.auxiliaryMasks: ${kind} requires density/source and occlusion control masks`);
  }

  const stateAssets = inventory.assets.filter((asset) => asset.kind === "scene-layer" && asset.variantID !== null);
  const expectedStateKeys = new Set(stateAssets.map((asset) => `${asset.ownerID}.${asset.variantID}`));
  const actualStateKeys = new Set();
  if (!Array.isArray(contract.stateVariantPolicies)) issues.push("visual contract.stateVariantPolicies: array required");
  for (const [index, policy] of (Array.isArray(contract.stateVariantPolicies) ? contract.stateVariantPolicies : []).entries()) {
    const location = `visual contract.stateVariantPolicies[${index}]`;
    exactKeys(policy, ["layerID", "variantID", "authorizationMaskID", "allowedAlphaBounds", "maximumAuthorizedAreaFraction"], [], location, issues);
    const key = `${policy.layerID}.${policy.variantID}`;
    if (!expectedStateKeys.has(key)) issues.push(`${location}: unknown SceneSpec variant '${key}'`);
    if (actualStateKeys.has(key)) issues.push(`${location}: duplicate variant policy`);
    actualStateKeys.add(key);
    if (!auxiliaryMaskIDs.has(policy.authorizationMaskID)) issues.push(`${location}.authorizationMaskID: missing auxiliary mask`);
    const mask = contract.auxiliaryMasks?.find(({ id }) => id === policy.authorizationMaskID);
    if (mask?.maskType !== "authorization") issues.push(`${location}.authorizationMaskID: authorization mask required`);
    validateFrame(policy.allowedAlphaBounds, `${location}.allowedAlphaBounds`, issues);
    const asset = inventory.byPath.get(stateAssets.find((candidate) => `${candidate.ownerID}.${candidate.variantID}` === key)?.assetPath);
    if (asset && !frameContains(asset.frame, policy.allowedAlphaBounds)) issues.push(`${location}.allowedAlphaBounds: must remain within the owning layer frame`);
    finite(policy.maximumAuthorizedAreaFraction, `${location}.maximumAuthorizedAreaFraction`, issues, 0.001, 1);
  }
  if ([...expectedStateKeys].some((key) => !actualStateKeys.has(key))) issues.push("visual contract.stateVariantPolicies: every state variant requires an authorization mask and bounds");

  exactKeys(contract.recompositionGate, ["maxChannelError", "maxMeanAbsoluteError", "minimumExactPixelFraction", "statePixelsOutsideAuthorizationMustMatch"], [], "visual contract.recompositionGate", issues);
  integer(contract.recompositionGate?.maxChannelError, "visual contract.recompositionGate.maxChannelError", issues, 0);
  finite(contract.recompositionGate?.maxMeanAbsoluteError, "visual contract.recompositionGate.maxMeanAbsoluteError", issues, 0, 255);
  finite(contract.recompositionGate?.minimumExactPixelFraction, "visual contract.recompositionGate.minimumExactPixelFraction", issues, 0, 1);
  if (contract.recompositionGate?.statePixelsOutsideAuthorizationMustMatch !== true) {
    issues.push("visual contract.recompositionGate.statePixelsOutsideAuthorizationMustMatch: must be true");
  }
  exactKeys(contract.encodingGate, ["maxChannelError", "maxMeanAbsoluteError", "deterministicByteReplayRequired"], [], "visual contract.encodingGate", issues);
  integer(contract.encodingGate?.maxChannelError, "visual contract.encodingGate.maxChannelError", issues, 0);
  finite(contract.encodingGate?.maxMeanAbsoluteError, "visual contract.encodingGate.maxMeanAbsoluteError", issues, 0, 255);
  if (contract.encodingGate?.deterministicByteReplayRequired !== true) {
    issues.push("visual contract.encodingGate.deterministicByteReplayRequired: must be true");
  }

  exactKeys(contract.productionRules, [
    "editorApprovedMasterRequiredForShipping", "independentlyGeneratedLayersForbidden",
    "autoMasksRequireArtReview", "losslessWorkingIntermediates",
    "pipelineCannotApproveShipping", "upscalingForbidden",
    "codexProvisionalMasterMayBuildDevelopmentDAG",
    "provisionalOutputsForbiddenFromShipping",
  ], [], "visual contract.productionRules", issues);
  for (const [key, value] of Object.entries(contract.productionRules ?? {})) {
    if (value !== true) issues.push(`visual contract.productionRules.${key}: must remain true`);
  }
  if (contractRepositoryPath !== undefined) safePath(contractRepositoryPath, "visual contract repository path", issues);
  if (issues.length) throw new VisualProductionError(issues);
  return { contract, inventory, toolIDs, costByID, repositoryRoot, contractRepositoryPath };
}

function run(command, arguments_, options = {}) {
  const result = spawnSync(command, arguments_, {
    encoding: options.encoding,
    maxBuffer: options.maxBuffer ?? 128 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const stderr = Buffer.isBuffer(result.stderr) ? result.stderr.toString("utf8") : result.stderr;
    throw new Error(`${command} failed: ${stderr?.trim() || `exit ${result.status}`}`);
  }
  return result.stdout;
}

function validateInstalledToolchain(contract, costByID) {
  const issues = [];
  for (const tool of contract.toolchain) {
    let installed;
    const registryEntry = costByID.get(tool.toolID);
    if (registryEntry?.category === "model") continue;
    if (tool.toolID === "nodejs-local") installed = process.versions.node;
    else if (tool.toolID === "ffmpeg-local") {
      installed = /^ffmpeg version\s+([^\s]+)/u.exec(run("ffmpeg", ["-version"], { encoding: "utf8" }))?.[1];
    } else if (tool.toolID === "apple-sips") {
      installed = /^sips-(\S+)/u.exec(run("/usr/bin/sips", ["--version"], { encoding: "utf8" }))?.[1];
    } else if (tool.toolID === "mflux-local") {
      installed = /^mflux\s+v([^\s]+)/mu.exec(run("uv", ["tool", "list"], { encoding: "utf8" }))?.[1];
    } else {
      issues.push(`visual toolchain: no installed-version probe for '${tool.toolID}'`);
      continue;
    }
    if (installed !== tool.version) issues.push(`visual toolchain: '${tool.toolID}' installed version '${installed}' does not match '${tool.version}'`);
  }
  if (issues.length) throw new VisualProductionError(issues);
}

export function probeRaster(filePath) {
  if (/\.hei[cf]$/iu.test(filePath)) {
    const output = run("/usr/bin/sips", [
      "-g", "pixelWidth", "-g", "pixelHeight", filePath,
    ], { encoding: "utf8" });
    const width = Number(/pixelWidth:\s*(\d+)/u.exec(output)?.[1]);
    const height = Number(/pixelHeight:\s*(\d+)/u.exec(output)?.[1]);
    if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height)) {
      throw new Error(`${filePath}: sips did not report HEIF primary-image dimensions`);
    }
    return { width, height, pixelFormat: "rgba", formatName: "heic" };
  }
  const output = run("ffprobe", [
    "-v", "error", "-select_streams", "v:0",
    "-show_entries", "stream=width,height,pix_fmt:format=format_name",
    "-of", "json", filePath,
  ], { encoding: "utf8" });
  const data = JSON.parse(output);
  const stream = data.streams?.[0];
  if (!stream) throw new Error(`${filePath}: no visual stream`);
  return { width: stream.width, height: stream.height, pixelFormat: stream.pix_fmt, formatName: data.format?.format_name };
}

function decodeRaster(filePath, pixelFormat, width, height) {
  const channels = pixelFormat === "gray" ? 1 : pixelFormat === "rgb24" ? 3 : 4;
  let decodePath = filePath;
  let temporaryRoot;
  if (/\.hei[cf]$/iu.test(filePath)) {
    temporaryRoot = mkdtempSync(path.join(os.tmpdir(), "long-west-heif-primary-"));
    decodePath = path.join(temporaryRoot, "primary.png");
    run("/usr/bin/sips", [
      "-s", "format", "png", filePath, "--out", decodePath,
    ], { encoding: "utf8" });
  }
  let output;
  try {
    output = run("ffmpeg", [
      "-v", "error", "-i", decodePath, "-frames:v", "1",
      "-vf", `format=${pixelFormat}`, "-f", "rawvideo", "pipe:1",
    ]);
  } finally {
    if (temporaryRoot) rmSync(temporaryRoot, { recursive: true, force: true });
  }
  const expected = width * height * channels;
  if (output.byteLength !== expected) throw new Error(`${filePath}: expected ${expected} decoded bytes, received ${output.byteLength}`);
  return new Uint8Array(output.buffer, output.byteOffset, output.byteLength);
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.byteLength);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([typeBytes, data])));
  return Buffer.concat([length, typeBytes, data, checksum]);
}

function encodePNG(pixels, width, height, channels) {
  if (![1, 3, 4].includes(channels)) throw new Error("PNG encoder supports gray, RGB and RGBA only");
  if (pixels.byteLength !== width * height * channels) throw new Error("PNG pixel byte count does not match dimensions");
  const scanlines = Buffer.alloc(height * (1 + width * channels));
  for (let y = 0; y < height; y += 1) {
    const target = y * (1 + width * channels);
    scanlines[target] = 0;
    Buffer.from(pixels.buffer, pixels.byteOffset + y * width * channels, width * channels).copy(scanlines, target + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = channels === 1 ? 0 : channels === 3 ? 2 : 6;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(scanlines, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function cropPixels(pixels, sourceWidth, sourceHeight, channels, rect) {
  if (rect.x < 0 || rect.y < 0 || rect.x + rect.width > sourceWidth || rect.y + rect.height > sourceHeight) {
    throw new Error("crop escaped source raster");
  }
  const output = new Uint8Array(rect.width * rect.height * channels);
  for (let y = 0; y < rect.height; y += 1) {
    const sourceOffset = ((rect.y + y) * sourceWidth + rect.x) * channels;
    output.set(pixels.subarray(sourceOffset, sourceOffset + rect.width * channels), y * rect.width * channels);
  }
  return output;
}

function maskStats(pixels, width, height) {
  let minimum = 255;
  let maximum = 0;
  let sum = 0;
  let nonzero = 0;
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const value = pixels[y * width + x];
      minimum = Math.min(minimum, value);
      maximum = Math.max(maximum, value);
      sum += value;
      if (value > 0) {
        nonzero += 1;
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
      }
    }
  }
  return {
    minimum,
    maximum,
    mean: sum / pixels.byteLength,
    nonzeroFraction: nonzero / pixels.byteLength,
    nonzeroBounds: nonzero === 0 ? null : {
      x: minX / width,
      y: minY / height,
      width: (maxX + 1 - minX) / width,
      height: (maxY + 1 - minY) / height,
    },
  };
}

function applyAlpha(rgb, alpha) {
  const rgba = new Uint8Array(alpha.byteLength * 4);
  for (let index = 0; index < alpha.byteLength; index += 1) {
    rgba[index * 4] = rgb[index * 3];
    rgba[index * 4 + 1] = rgb[index * 3 + 1];
    rgba[index * 4 + 2] = rgb[index * 3 + 2];
    rgba[index * 4 + 3] = alpha[index];
  }
  return rgba;
}

function sourceRecord(source, sourceBytes) {
  return {
    id: source.id,
    kind: source.kind,
    path: source.path,
    bytes: sourceBytes.byteLength,
    sha256: hashBytes(sourceBytes),
    parents: clone(source.creation.parentHashes),
    creation: clone(source.creation),
    rights: clone(source.rights),
  };
}

function validateCreation(creation, source, costByID, contractToolIDs, location, issues) {
  exactKeys(creation, ["mode", "toolIDs", "parentHashes", "prompt", "symbolicSource", "seed", "model"], [], location, issues);
  if (!["generated", "authored", "derived"].includes(creation.mode)) issues.push(`${location}.mode: generated, authored or derived required`);
  validateToolReferences(creation.toolIDs, contractToolIDs, costByID, `${location}.toolIDs`, issues);
  if (!Array.isArray(creation.parentHashes)) issues.push(`${location}.parentHashes: array required`);
  for (const [index, parent] of (creation.parentHashes ?? []).entries()) {
    exactKeys(parent, ["sourceID", "sha256"], [], `${location}.parentHashes[${index}]`, issues);
    stableID(parent.sourceID, `${location}.parentHashes[${index}].sourceID`, issues);
    sha256(parent.sha256, `${location}.parentHashes[${index}].sha256`, issues);
  }
  if (creation.mode === "generated") {
    if (!isObject(creation.prompt)) issues.push(`${location}.prompt: exact prompt path/hash required for generated sources`);
    else {
      exactKeys(creation.prompt, ["path", "sha256"], [], `${location}.prompt`, issues);
      safePath(creation.prompt.path, `${location}.prompt.path`, issues);
      sha256(creation.prompt.sha256, `${location}.prompt.sha256`, issues);
    }
    integer(creation.seed, `${location}.seed`, issues, 0);
    if (!isObject(creation.model)) issues.push(`${location}.model: model identity and weight hash required`);
    else {
      exactKeys(creation.model, ["toolID", "version", "weights"], [], `${location}.model`, issues);
      const model = costByID.get(creation.model.toolID);
      if (!model || model.category !== "model" || model.version !== creation.model.version
          || model.incrementalCostNOK !== 0 || model.billingCredentialRequired !== false
          || model.commercialUse !== "allowed" || !String(model.license ?? "").trim()) {
        issues.push(`${location}.model: must match an exact commercially cleared zero-cost model registry entry`);
      }
      if (!Array.isArray(creation.model.weights) || creation.model.weights.length === 0) {
        issues.push(`${location}.model.weights: every loaded model-weight file requires an exact hash`);
      }
      const weightIDs = new Set();
      for (const [weightIndex, weight] of (Array.isArray(creation.model.weights) ? creation.model.weights : []).entries()) {
        const weightLocation = `${location}.model.weights[${weightIndex}]`;
        exactKeys(weight, ["id", "sha256"], [], weightLocation, issues);
        stableID(weight.id, `${weightLocation}.id`, issues);
        sha256(weight.sha256, `${weightLocation}.sha256`, issues);
        if (weightIDs.has(weight.id)) issues.push(`${weightLocation}.id: duplicate model-weight role`);
        weightIDs.add(weight.id);
      }
    }
    if (creation.symbolicSource !== null) issues.push(`${location}.symbolicSource: generated sources require null`);
  } else if (creation.mode === "authored") {
    if (!isObject(creation.symbolicSource)) issues.push(`${location}.symbolicSource: exact authored source path/hash required`);
    else {
      exactKeys(creation.symbolicSource, ["path", "sha256"], [], `${location}.symbolicSource`, issues);
      safePath(creation.symbolicSource.path, `${location}.symbolicSource.path`, issues);
      sha256(creation.symbolicSource.sha256, `${location}.symbolicSource.sha256`, issues);
    }
    if (creation.prompt !== null || creation.seed !== null || creation.model !== null) issues.push(`${location}: authored sources require null prompt, seed and model`);
  } else if (creation.prompt !== null || creation.symbolicSource !== null || creation.seed !== null || creation.model !== null) {
    issues.push(`${location}: derived sources require null prompt, symbolicSource, seed and model`);
  }
  if (source.kind === "approved-master" && creation.mode === "derived") issues.push(`${location}: approved master cannot hide its originating generation or authorship`);
}

async function validateExactAncillaryFile(repositoryRoot, record, location, issues) {
  if (record === null) return;
  if (!exactKeys(record, ["path", "sha256"], [], location, issues)) return;
  if (!safePath(record.path, `${location}.path`, issues) || !sha256(record.sha256, `${location}.sha256`, issues)) return;
  const resolved = path.resolve(repositoryRoot, record.path);
  try {
    const bytes = await readFile(resolved);
    if (hashBytes(bytes) !== record.sha256) issues.push(`${location}: SHA-256 drifted`);
  } catch (error) {
    issues.push(`${location}.path: ${error.message}`);
  }
}

function repositoryRelativePath(repositoryRoot, filePath, location, issues) {
  const resolvedRoot = path.resolve(repositoryRoot);
  const resolved = path.resolve(filePath);
  if (!resolved.startsWith(`${resolvedRoot}${path.sep}`)) {
    issues.push(`${location}: must remain inside the repository`);
    return undefined;
  }
  const relative = path.relative(resolvedRoot, resolved).split(path.sep).join("/");
  if (!safePath(relative, location, issues)) return undefined;
  return relative;
}

async function readExactJSONFile(repositoryRoot, record, location, issues) {
  if (!isObject(record)) {
    issues.push(`${location}: exact path/hash object required`);
    return undefined;
  }
  if (!exactKeys(record, ["path", "sha256"], [], location, issues)) return undefined;
  if (!safePath(record.path, `${location}.path`, issues) || !sha256(record.sha256, `${location}.sha256`, issues)) return undefined;
  try {
    const bytes = await readFile(path.resolve(repositoryRoot, record.path));
    if (hashBytes(bytes) !== record.sha256) {
      issues.push(`${location}: SHA-256 drifted`);
      return undefined;
    }
    return { bytes, document: JSON.parse(bytes.toString("utf8")) };
  } catch (error) {
    issues.push(`${location}: ${error.message}`);
    return undefined;
  }
}

async function validateProvisionalCandidateMetadata({
  metadata,
  metadataBytes,
  metadataPath,
  candidatePath,
  candidateBytes,
  candidateProbe,
  inventory,
  repositoryRoot,
  issues,
  location = "provisional visual master",
}) {
  if (!isObject(metadata)) {
    issues.push(`${location}.candidateMetadata: JSON object required`);
    return undefined;
  }
  if (metadata.schemaVersion !== 1) issues.push(`${location}.candidateMetadata.schemaVersion: expected 1`);
  stableID(metadata.candidateID, `${location}.candidateMetadata.candidateID`, issues);
  if (typeof metadata.status !== "string" || !metadata.status.includes("NON_SHIPPING")) {
    issues.push(`${location}.candidateMetadata.status: explicit NON_SHIPPING candidate status required`);
  }
  if (metadata.shippingAllowed !== false) {
    issues.push(`${location}.candidateMetadata.shippingAllowed: must remain false`);
  }
  if (!isObject(metadata.output)) {
    issues.push(`${location}.candidateMetadata.output: exact candidate output record required`);
  } else {
    exactKeys(metadata.output, ["path", "sha256", "bytes", "width", "height"], [], `${location}.candidateMetadata.output`, issues);
    safePath(metadata.output.path, `${location}.candidateMetadata.output.path`, issues);
    sha256(metadata.output.sha256, `${location}.candidateMetadata.output.sha256`, issues);
    integer(metadata.output.bytes, `${location}.candidateMetadata.output.bytes`, issues, 1);
    integer(metadata.output.width, `${location}.candidateMetadata.output.width`, issues, 1);
    integer(metadata.output.height, `${location}.candidateMetadata.output.height`, issues, 1);
    if (metadata.output.path !== candidatePath
        || metadata.output.bytes !== candidateBytes.byteLength
        || metadata.output.sha256 !== hashBytes(candidateBytes)) {
      issues.push(`${location}.candidateMetadata.output: candidate path or exact bytes drifted`);
    }
    if (metadata.output.width !== candidateProbe.width || metadata.output.height !== candidateProbe.height
        || metadata.output.width !== inventory.canvas.width || metadata.output.height !== inventory.canvas.height) {
      issues.push(`${location}.candidateMetadata.output: candidate must equal the SceneSpec canvas without resampling`);
    }
  }
  if (!isObject(metadata.codexPreflight)) {
    issues.push(`${location}.candidateMetadata.codexPreflight: exact Codex preflight required`);
  } else {
    exactKeys(metadata.codexPreflight, ["path", "sha256", "bytes", "status"], [], `${location}.candidateMetadata.codexPreflight`, issues);
    safePath(metadata.codexPreflight.path, `${location}.candidateMetadata.codexPreflight.path`, issues);
    sha256(metadata.codexPreflight.sha256, `${location}.candidateMetadata.codexPreflight.sha256`, issues);
    integer(metadata.codexPreflight.bytes, `${location}.candidateMetadata.codexPreflight.bytes`, issues, 1);
    if (metadata.codexPreflight.status !== provisionalPreflightStatus) {
      issues.push(`${location}.candidateMetadata.codexPreflight.status: ${provisionalPreflightStatus} required`);
    }
    try {
      const preflightBytes = await readFile(path.resolve(repositoryRoot, metadata.codexPreflight.path));
      if (preflightBytes.byteLength !== metadata.codexPreflight.bytes
          || hashBytes(preflightBytes) !== metadata.codexPreflight.sha256) {
        issues.push(`${location}.candidateMetadata.codexPreflight: exact bytes drifted`);
      }
      if (!preflightBytes.toString("utf8").includes(`Status: \`${provisionalPreflightStatus}\``)) {
        issues.push(`${location}.candidateMetadata.codexPreflight: document does not declare its provisional trust domain`);
      }
    } catch (error) {
      issues.push(`${location}.candidateMetadata.codexPreflight.path: ${error.message}`);
    }
  }
  if (!isObject(metadata.audit)
      || metadata.audit.productionMasterResult !== "PENDING_ARTISTIC_GATE"
      || metadata.audit.layerDAGAuthority !== "NOT_GRANTED") {
    issues.push(`${location}.candidateMetadata.audit: candidate must remain pending the artistic gate with no pre-existing layer-DAG authority`);
  }
  return {
    metadataRecord: {
      path: metadataPath,
      sha256: hashBytes(metadataBytes),
    },
    candidate: {
      id: metadata.candidateID,
      path: candidatePath,
      bytes: candidateBytes.byteLength,
      sha256: hashBytes(candidateBytes),
      width: candidateProbe.width,
      height: candidateProbe.height,
    },
    preflight: metadata.codexPreflight,
  };
}

export async function createProvisionalVisualMasterAuthority({
  candidatePath,
  candidateMetadataPath,
  contract,
  fixture,
  fixtureBytes,
  costRegistry,
  repositoryRoot,
  contractRepositoryPath,
}) {
  const contractContext = await validateVisualProductionContract({
    contract,
    fixture,
    fixtureBytes,
    costRegistry,
    repositoryRoot,
    contractRepositoryPath,
  });
  const issues = [];
  const candidateRepositoryPath = repositoryRelativePath(repositoryRoot, candidatePath, "provisional visual master.candidate.path", issues);
  const metadataRepositoryPath = repositoryRelativePath(repositoryRoot, candidateMetadataPath, "provisional visual master.candidateMetadata.path", issues);
  let candidateBytes;
  let metadataBytes;
  let metadata;
  let candidateProbe;
  try {
    candidateBytes = await readFile(path.resolve(candidatePath));
    candidateProbe = probeRaster(path.resolve(candidatePath));
  } catch (error) {
    issues.push(`provisional visual master.candidate.path: ${error.message}`);
  }
  try {
    metadataBytes = await readFile(path.resolve(candidateMetadataPath));
    metadata = JSON.parse(metadataBytes.toString("utf8"));
  } catch (error) {
    issues.push(`provisional visual master.candidateMetadata.path: ${error.message}`);
  }
  let candidateContext;
  if (candidateRepositoryPath && metadataRepositoryPath && candidateBytes && metadataBytes && metadata && candidateProbe) {
    candidateContext = await validateProvisionalCandidateMetadata({
      metadata,
      metadataBytes,
      metadataPath: metadataRepositoryPath,
      candidatePath: candidateRepositoryPath,
      candidateBytes,
      candidateProbe,
      inventory: contractContext.inventory,
      repositoryRoot,
      issues,
    });
  }
  if (issues.length || !candidateContext) throw new VisualProductionError(issues);
  return {
    schemaVersion: 1,
    status: provisionalVisualMasterStatus,
    authority: "codex",
    trustDomain: "LOCAL_DEVELOPMENT_ONLY",
    shippingState: "PROHIBITED",
    editorApprovalState: "NOT_CLAIMED",
    developmentDAGAuthorityState: "GRANTED",
    allowedUse: "BUILD_AND_VERIFY_NON_SHIPPING_VISUAL_ASSET_DAG",
    contract: {
      path: contractRepositoryPath,
      sha256: canonicalSHA256(contract),
    },
    sceneFixture: {
      path: contract.sceneFixturePath,
      sha256: hashBytes(fixtureBytes),
      sceneID: fixture.scene.id,
      canvas: clone(contractContext.inventory.canvas),
    },
    candidate: candidateContext.candidate,
    candidateMetadata: candidateContext.metadataRecord,
    codexPreflight: {
      path: candidateContext.preflight.path,
      sha256: candidateContext.preflight.sha256,
      status: provisionalPreflightStatus,
    },
  };
}

async function validateProvisionalVisualMasterAuthority({
  authority,
  source,
  contractContext,
  repositoryRoot,
  location,
  issues,
}) {
  exactKeys(authority, [
    "schemaVersion", "status", "authority", "trustDomain", "shippingState",
    "editorApprovalState", "developmentDAGAuthorityState", "allowedUse",
    "contract", "sceneFixture", "candidate", "candidateMetadata", "codexPreflight",
  ], [], location, issues);
  if (authority?.schemaVersion !== 1
      || authority?.status !== provisionalVisualMasterStatus
      || authority?.authority !== "codex"
      || authority?.trustDomain !== "LOCAL_DEVELOPMENT_ONLY"
      || authority?.shippingState !== "PROHIBITED"
      || authority?.editorApprovalState !== "NOT_CLAIMED"
      || authority?.developmentDAGAuthorityState !== "GRANTED"
      || authority?.allowedUse !== "BUILD_AND_VERIFY_NON_SHIPPING_VISUAL_ASSET_DAG") {
    issues.push(`${location}: exact local non-shipping Codex authority required`);
  }
  exactKeys(authority?.contract, ["path", "sha256"], [], `${location}.contract`, issues);
  if (authority?.contract?.path !== contractContext.contractRepositoryPath
      || authority?.contract?.sha256 !== canonicalSHA256(contractContext.contract)) {
    issues.push(`${location}.contract: exact validated visual contract required`);
  }
  exactKeys(authority?.sceneFixture, ["path", "sha256", "sceneID", "canvas"], [], `${location}.sceneFixture`, issues);
  if (authority?.sceneFixture?.path !== contractContext.contract.sceneFixturePath
      || authority?.sceneFixture?.sha256 !== contractContext.contract.sceneFixtureSHA256
      || authority?.sceneFixture?.sceneID !== contractContext.contract.expectedSceneID
      || canonicalJSON(authority?.sceneFixture?.canvas) !== canonicalJSON(contractContext.inventory.canvas)) {
    issues.push(`${location}.sceneFixture: exact contract-bound SceneSpec required`);
  }
  exactKeys(authority?.candidate, ["id", "path", "bytes", "sha256", "width", "height"], [], `${location}.candidate`, issues);
  if (authority?.candidate?.path !== source.path
      || authority?.candidate?.bytes !== source.bytes
      || authority?.candidate?.sha256 !== source.sha256
      || authority?.candidate?.width !== source.dimensions?.width
      || authority?.candidate?.height !== source.dimensions?.height) {
    issues.push(`${location}.candidate: authority must bind the exact provisional master source`);
  }
  const metadataFile = await readExactJSONFile(repositoryRoot, authority?.candidateMetadata, `${location}.candidateMetadata`, issues);
  const candidateFile = await exactFileRecord(repositoryRoot, source, `${location}.candidate`, issues);
  let candidateProbe;
  if (candidateFile) {
    try {
      candidateProbe = probeRaster(candidateFile.resolved);
    } catch (error) {
      issues.push(`${location}.candidate.path: ${error.message}`);
    }
  }
  if (metadataFile && candidateFile && candidateProbe) {
    const candidateContext = await validateProvisionalCandidateMetadata({
      metadata: metadataFile.document,
      metadataBytes: metadataFile.bytes,
      metadataPath: authority.candidateMetadata.path,
      candidatePath: source.path,
      candidateBytes: candidateFile.bytes,
      candidateProbe,
      inventory: contractContext.inventory,
      repositoryRoot,
      issues,
      location,
    });
    if (candidateContext && canonicalJSON(candidateContext.candidate) !== canonicalJSON(authority.candidate)) {
      issues.push(`${location}.candidate: authority candidate record drifted from the exact metadata output`);
    }
  }
  exactKeys(authority?.codexPreflight, ["path", "sha256", "status"], [], `${location}.codexPreflight`, issues);
  if (authority?.codexPreflight?.status !== provisionalPreflightStatus
      || authority?.codexPreflight?.path !== metadataFile?.document?.codexPreflight?.path
      || authority?.codexPreflight?.sha256 !== metadataFile?.document?.codexPreflight?.sha256) {
    issues.push(`${location}.codexPreflight: authority must bind the candidate's exact provisional preflight`);
  }
}

function validateEditorVisualMasterApproval({
  approval,
  source,
  contractContext,
  location,
  issues,
}) {
  exactKeys(approval, [
    "schemaVersion", "status", "authority", "approvedAt", "decisionReference",
    "contract", "sceneFixture", "master", "approvedScope", "shippingState",
  ], [], location, issues);
  if (approval?.schemaVersion !== 1
      || approval?.status !== "EDITOR_APPROVED_AS_PRODUCTION_MASTER"
      || approval?.authority !== "editor-in-chief") {
    issues.push(`${location}: explicit editor-in-chief production-master approval required`);
  }
  if (typeof approval?.approvedAt !== "string"
      || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/u.test(approval.approvedAt)
      || typeof approval?.decisionReference !== "string"
      || approval.decisionReference.length < 12) {
    issues.push(`${location}: UTC approval time and decision reference required`);
  }
  exactKeys(approval?.contract, ["path", "sha256"], [], `${location}.contract`, issues);
  if (approval?.contract?.path !== contractContext.contractRepositoryPath
      || approval?.contract?.sha256 !== canonicalSHA256(contractContext.contract)) {
    issues.push(`${location}.contract: exact validated visual contract required`);
  }
  exactKeys(approval?.sceneFixture, ["path", "sha256", "sceneID", "canvas"], [], `${location}.sceneFixture`, issues);
  if (approval?.sceneFixture?.path !== contractContext.contract.sceneFixturePath
      || approval?.sceneFixture?.sha256 !== contractContext.contract.sceneFixtureSHA256
      || approval?.sceneFixture?.sceneID !== contractContext.contract.expectedSceneID
      || canonicalJSON(approval?.sceneFixture?.canvas) !== canonicalJSON(contractContext.inventory.canvas)) {
    issues.push(`${location}.sceneFixture: exact contract-bound SceneSpec required`);
  }
  exactKeys(approval?.master, ["sourceID", "path", "bytes", "sha256", "width", "height"], [], `${location}.master`, issues);
  const expectedMaster = {
    sourceID: source.id,
    path: source.path,
    bytes: source.bytes,
    sha256: source.sha256,
    width: source.dimensions?.width,
    height: source.dimensions?.height,
  };
  if (canonicalJSON(approval?.master) !== canonicalJSON(expectedMaster)) {
    issues.push(`${location}.master: approval must bind the exact production-master source bytes`);
  }
  if (canonicalJSON(approval?.approvedScope) !== canonicalJSON([
    "PRODUCTION_MASTER_PIXELS",
    "LAYER_DAG_INPUT",
  ])) {
    issues.push(`${location}.approvedScope: exact master-pixel and layer-DAG scope required`);
  }
  if (approval?.shippingState !== "REQUIRES_SEPARATE_ASSET_AND_PACKAGE_APPROVAL") {
    issues.push(`${location}.shippingState: separated assets and package require separate editor approval`);
  }
  if (canonicalJSON(approval).includes("CODEX_PROVISIONAL_NON_SHIPPING")) {
    issues.push(`${location}: provisional authority cannot enter an editor approval record`);
  }
}

function validateRights(rights, location, issues) {
  exactKeys(rights, ["status", "incrementalCostNOK", "license"], [], location, issues);
  if (rights.status !== "COMMERCIAL_USE_CLEARED" || rights.incrementalCostNOK !== 0 || typeof rights.license !== "string" || !rights.license.trim()) {
    issues.push(`${location}: clear commercial rights and zero incremental cost required`);
  }
}

async function validateProductionDAG({ dag, contractContext, repositoryRoot }) {
  const issues = [];
  const {
    contract,
    inventory,
    toolIDs: contractToolIDs,
    costByID,
    contractRepositoryPath,
  } = contractContext;
  exactKeys(dag, [
    "schemaVersion", "id", "status", "buildMode", "contract", "masterSourceID", "sources",
    "operations", "recomposition", "rejectedCandidates", "backup",
  ], [], "visual DAG", issues);
  if (dag.schemaVersion !== 1) issues.push("visual DAG.schemaVersion: expected 1");
  stableID(dag.id, "visual DAG.id", issues);
  if (!Object.values(visualProductionBuildModes).includes(dag.buildMode)) {
    issues.push("visual DAG.buildMode: recognised visual production trust domain required");
  }
  const requiredDAGStatus = dag.buildMode === visualProductionBuildModes.codexProvisional
    ? provisionalDAGStatus
    : editorApprovedDAGStatus;
  if (dag.status !== requiredDAGStatus) {
    issues.push(`visual DAG.status: ${requiredDAGStatus} required for ${dag.buildMode ?? "the selected build mode"}`);
  }
  exactKeys(dag.contract, ["path", "sha256"], [], "visual DAG.contract", issues);
  safePath(dag.contract.path, "visual DAG.contract.path", issues);
  if (contractRepositoryPath !== undefined && dag.contract.path !== contractRepositoryPath) {
    issues.push("visual DAG.contract.path: must identify the exact validated contract file");
  }
  sha256(dag.contract.sha256, "visual DAG.contract.sha256", issues);
  if (dag.contract.sha256 !== canonicalSHA256(contract)) issues.push("visual DAG.contract.sha256: contract data drifted");

  const sourcesByID = new Map();
  const sourceFileRecords = new Map();
  if (!Array.isArray(dag.sources) || dag.sources.length === 0) issues.push("visual DAG.sources: non-empty array required");
  const dagSources = Array.isArray(dag.sources) ? dag.sources : [];
  for (const [index, source] of dagSources.entries()) {
    const location = `visual DAG.sources[${index}]`;
    exactKeys(source, ["id", "kind", "path", "bytes", "sha256", "dimensions", "creation", "rights"], ["editorApproval", "provisionalAuthority"], location, issues);
    stableID(source.id, `${location}.id`, issues);
    if (!SOURCE_KINDS.has(source.kind)) issues.push(`${location}.kind: unsupported source kind`);
    if (sourcesByID.has(source.id)) issues.push(`${location}.id: duplicate`);
    sourcesByID.set(source.id, source);
    const file = await exactFileRecord(repositoryRoot, source, location, issues);
    if (file) sourceFileRecords.set(source.id, file);
    exactKeys(source.dimensions, ["width", "height"], [], `${location}.dimensions`, issues);
    integer(source.dimensions?.width, `${location}.dimensions.width`, issues, 1);
    integer(source.dimensions?.height, `${location}.dimensions.height`, issues, 1);
    if (file) {
      try {
        const probe = probeRaster(file.resolved);
        if (probe.width !== source.dimensions.width || probe.height !== source.dimensions.height) issues.push(`${location}.dimensions: decoded raster dimensions drifted`);
      } catch (error) {
        issues.push(`${location}.path: ${error.message}`);
      }
    }
    validateCreation(source.creation, source, costByID, contractToolIDs, `${location}.creation`, issues);
    validateRights(source.rights, `${location}.rights`, issues);
    if (source.kind === "approved-master") {
      if (!isObject(source.editorApproval)) issues.push(`${location}.editorApproval: exact production-master approval required`);
      else {
        exactKeys(source.editorApproval, ["path", "sha256", "status"], [], `${location}.editorApproval`, issues);
        safePath(source.editorApproval.path, `${location}.editorApproval.path`, issues);
        sha256(source.editorApproval.sha256, `${location}.editorApproval.sha256`, issues);
        if (source.editorApproval.status !== "EDITOR_APPROVED_AS_PRODUCTION_MASTER") issues.push(`${location}.editorApproval.status: production-master approval required`);
        const approvalFile = await readExactJSONFile(
          repositoryRoot,
          { path: source.editorApproval.path, sha256: source.editorApproval.sha256 },
          `${location}.editorApproval`,
          issues,
        );
        if (approvalFile) {
          validateEditorVisualMasterApproval({
            approval: approvalFile.document,
            source,
            contractContext,
            location: `${location}.editorApproval`,
            issues,
          });
        }
      }
      if (Object.hasOwn(source, "provisionalAuthority")) {
        issues.push(`${location}.provisionalAuthority: editor-approved master cannot also carry provisional authority`);
      }
    } else if (source.kind === "provisional-master") {
      if (!isObject(source.provisionalAuthority)) {
        issues.push(`${location}.provisionalAuthority: exact Codex provisional production-master authority required`);
      } else {
        exactKeys(source.provisionalAuthority, ["path", "sha256", "status"], [], `${location}.provisionalAuthority`, issues);
        safePath(source.provisionalAuthority.path, `${location}.provisionalAuthority.path`, issues);
        sha256(source.provisionalAuthority.sha256, `${location}.provisionalAuthority.sha256`, issues);
        if (source.provisionalAuthority.status !== provisionalVisualMasterStatus) {
          issues.push(`${location}.provisionalAuthority.status: ${provisionalVisualMasterStatus} required`);
        }
        const authorityFile = await readExactJSONFile(
          repositoryRoot,
          { path: source.provisionalAuthority.path, sha256: source.provisionalAuthority.sha256 },
          `${location}.provisionalAuthority`,
          issues,
        );
        if (authorityFile) {
          await validateProvisionalVisualMasterAuthority({
            authority: authorityFile.document,
            source,
            contractContext,
            repositoryRoot,
            location: `${location}.provisionalAuthority`,
            issues,
          });
        }
      }
      if (Object.hasOwn(source, "editorApproval")) {
        issues.push(`${location}.editorApproval: provisional master cannot claim editor approval`);
      }
    } else {
      if (Object.hasOwn(source, "editorApproval")) issues.push(`${location}.editorApproval: only the master may carry scene-level approval`);
      if (Object.hasOwn(source, "provisionalAuthority")) issues.push(`${location}.provisionalAuthority: only the provisional master may carry local development authority`);
    }
  }
  const master = sourcesByID.get(dag.masterSourceID);
  const requiredMasterKind = dag.buildMode === visualProductionBuildModes.codexProvisional
    ? "provisional-master"
    : "approved-master";
  if (!master || master.kind !== requiredMasterKind) {
    issues.push(`visual DAG.masterSourceID: ${requiredMasterKind} source required for ${dag.buildMode ?? "the selected build mode"}`);
  }
  const masterSources = dagSources.filter(({ kind }) => ["approved-master", "provisional-master"].includes(kind));
  if (masterSources.length !== 1 || masterSources[0]?.id !== dag.masterSourceID) {
    issues.push("visual DAG.sources: exactly one trust-domain-matched production master required");
  }
  if (master && (master.dimensions.width !== inventory.canvas.width || master.dimensions.height !== inventory.canvas.height)) {
    issues.push("visual DAG.masterSourceID: master must equal the SceneSpec canvas; upscaling is forbidden");
  }

  for (const [index, source] of dagSources.entries()) {
    for (const [parentIndex, parent] of (source.creation?.parentHashes ?? []).entries()) {
      const actual = sourcesByID.get(parent.sourceID);
      if (!actual || actual.sha256 !== parent.sha256) issues.push(`visual DAG.sources[${index}].creation.parentHashes[${parentIndex}]: exact parent source/hash required`);
    }
    await validateExactAncillaryFile(repositoryRoot, source.creation?.prompt, `visual DAG.sources[${index}].creation.prompt`, issues);
    await validateExactAncillaryFile(repositoryRoot, source.creation?.symbolicSource, `visual DAG.sources[${index}].creation.symbolicSource`, issues);
  }
  const sourceVisiting = new Set();
  const sourceVisited = new Set();
  const visitSource = (source) => {
    if (sourceVisited.has(source.id)) return;
    if (sourceVisiting.has(source.id)) {
      issues.push(`visual DAG.sources: parent cycle contains '${source.id}'`);
      return;
    }
    sourceVisiting.add(source.id);
    for (const parent of source.creation?.parentHashes ?? []) {
      const parentSource = sourcesByID.get(parent.sourceID);
      if (parentSource) visitSource(parentSource);
    }
    sourceVisiting.delete(source.id);
    sourceVisited.add(source.id);
  };
  for (const source of sourcesByID.values()) visitSource(source);

  exactKeys(dag.backup, [
    "sourceID", "status", "storageClass", "locator", "verificationRecord",
    "bytes", "sha256",
  ], [], "visual DAG.backup", issues);
  if (dag.backup.sourceID !== dag.masterSourceID || dag.backup.status !== "HASH_VERIFIED") issues.push("visual DAG.backup: exact approved master backup must be HASH_VERIFIED");
  if (!["ENCRYPTED_EXISTING_PRIVATE_STORAGE", "TEST_REPOSITORY_COPY"].includes(dag.backup.storageClass)) {
    issues.push("visual DAG.backup.storageClass: encrypted existing private storage required outside tests");
  }
  if (typeof dag.backup.locator !== "string" || !dag.backup.locator.trim() || /(?:password|secret|token|key)=/iu.test(dag.backup.locator)) {
    issues.push("visual DAG.backup.locator: non-secret durable storage locator required");
  }
  await validateExactAncillaryFile(repositoryRoot, dag.backup.verificationRecord, "visual DAG.backup.verificationRecord", issues);
  if (isObject(dag.backup.verificationRecord) && safePath(dag.backup.verificationRecord.path, "visual DAG.backup.verificationRecord.path", [])) {
    try {
      const verification = JSON.parse(await readFile(path.resolve(repositoryRoot, dag.backup.verificationRecord.path), "utf8"));
      exactKeys(verification, [
        "schemaVersion", "status", "sourceID", "sourceBytes", "sourceSHA256",
        "backupBytes", "backupSHA256", "encryptedAtRest",
      ], [], "visual DAG backup verification", issues);
      const encryptionValid = dag.backup.storageClass === "ENCRYPTED_EXISTING_PRIVATE_STORAGE"
        ? verification.encryptedAtRest === true
        : typeof verification.encryptedAtRest === "boolean";
      if (verification.schemaVersion !== 1 || verification.status !== "HASH_VERIFIED"
          || verification.sourceID !== dag.masterSourceID || !encryptionValid
          || verification.sourceBytes !== dag.backup.bytes || verification.backupBytes !== dag.backup.bytes
          || verification.sourceSHA256 !== dag.backup.sha256 || verification.backupSHA256 !== dag.backup.sha256) {
        issues.push("visual DAG backup verification: must prove an encrypted byte-identical master backup");
      }
    } catch (error) {
      issues.push(`visual DAG.backup.verificationRecord: ${error.message}`);
    }
  }
  if (master && (dag.backup.bytes !== master.bytes || dag.backup.sha256 !== master.sha256)) issues.push("visual DAG.backup: backup bytes/hash must equal approved master");

  const rejectedIDs = new Set();
  if (!Array.isArray(dag.rejectedCandidates)) issues.push("visual DAG.rejectedCandidates: array required");
  for (const [index, rejected] of (Array.isArray(dag.rejectedCandidates) ? dag.rejectedCandidates : []).entries()) {
    const location = `visual DAG.rejectedCandidates[${index}]`;
    exactKeys(rejected, ["id", "path", "bytes", "sha256", "stage", "reasonCodes", "excludedFromShipping"], [], location, issues);
    stableID(rejected.id, `${location}.id`, issues);
    if (rejectedIDs.has(rejected.id)) issues.push(`${location}.id: duplicate`);
    rejectedIDs.add(rejected.id);
    await exactFileRecord(repositoryRoot, rejected, location, issues);
    if (!Array.isArray(rejected.reasonCodes) || rejected.reasonCodes.length === 0
        || rejected.reasonCodes.some((code) => typeof code !== "string" || !/^[A-Z][A-Z0-9_]+$/u.test(code))) {
      issues.push(`${location}.reasonCodes: non-empty machine-readable rejection codes required`);
    }
    if (rejected.excludedFromShipping !== true) issues.push(`${location}.excludedFromShipping: must be true`);
  }

  const operationByID = new Map();
  const outputPathToOperation = new Map();
  if (!Array.isArray(dag.operations) || dag.operations.length === 0) issues.push("visual DAG.operations: non-empty array required");
  const dagOperations = Array.isArray(dag.operations) ? dag.operations : [];
  for (const [index, operation] of dagOperations.entries()) {
    const location = `visual DAG.operations[${index}]`;
    exactKeys(operation, [
      "id", "kind", "outputRole", "outputPath", "sourceID", "inputOperationIDs",
      "alphaMaskOperationID", "frame", "maskType", "authorizationMaskOperationID",
      "toolIDs", "parameters",
    ], [], location, issues);
    stableID(operation.id, `${location}.id`, issues);
    if (!OPERATION_KINDS.has(operation.kind)) issues.push(`${location}.kind: unsupported operation`);
    if (![...FINAL_ASSET_KINDS, "control-mask", "clean-plate", "working-layer"].includes(operation.outputRole)) issues.push(`${location}.outputRole: unsupported role`);
    safePath(operation.outputPath, `${location}.outputPath`, issues);
    if (operationByID.has(operation.id)) issues.push(`${location}.id: duplicate`);
    if (outputPathToOperation.has(operation.outputPath)) issues.push(`${location}.outputPath: duplicate`);
    operationByID.set(operation.id, operation);
    outputPathToOperation.set(operation.outputPath, operation);
    if (operation.sourceID !== null && !sourcesByID.has(operation.sourceID)) issues.push(`${location}.sourceID: missing source`);
    if (!Array.isArray(operation.inputOperationIDs)) issues.push(`${location}.inputOperationIDs: array required`);
    validateFrame(operation.frame, `${location}.frame`, issues);
    if (operation.maskType !== null && !MASK_TYPES.has(operation.maskType)) issues.push(`${location}.maskType: unsupported mask type`);
    validateToolReferences(operation.toolIDs, contractToolIDs, costByID, `${location}.toolIDs`, issues);
    if (!isObject(operation.parameters)) issues.push(`${location}.parameters: object required`);
    if (operation.kind === "normalize-mask" && operation.maskType === null) issues.push(`${location}.maskType: normalize-mask requires a mask type`);
    if (operation.kind !== "normalize-mask" && operation.maskType !== null) issues.push(`${location}.maskType: only normalize-mask may declare a mask type`);
    if (operation.kind === "extract-layer" && operation.sourceID === null) issues.push(`${location}.sourceID: extract-layer requires a raster source`);
    if (operation.alphaMaskOperationID !== null && operation.kind !== "extract-layer") issues.push(`${location}.alphaMaskOperationID: only extract-layer may bind alpha`);
    if (operation.kind === "encode-heif") {
      if (operation.sourceID !== null || operation.inputOperationIDs?.length !== 1) issues.push(`${location}: encode-heif requires exactly one operation input and no source`);
      if (!/\.hei[cf]$/iu.test(operation.outputPath)) issues.push(`${location}.outputPath: encode-heif requires .heic or .heif`);
      if (!operation.toolIDs?.includes("apple-sips")) issues.push(`${location}.toolIDs: encode-heif requires the pinned Apple sips exporter`);
      exactKeys(operation.parameters, ["formatOptions"], [], `${location}.parameters`, issues);
      if (!["high", "best"].includes(operation.parameters?.formatOptions)) issues.push(`${location}.parameters.formatOptions: high or best required`);
    } else if (isObject(operation.parameters) && Object.keys(operation.parameters).length !== 0) {
      issues.push(`${location}.parameters: this operation requires an empty parameter object`);
    }
  }
  for (const [index, operation] of dagOperations.entries()) {
    const location = `visual DAG.operations[${index}]`;
    for (const [parentIndex, parentID] of (operation.inputOperationIDs ?? []).entries()) {
      if (!operationByID.has(parentID)) issues.push(`${location}.inputOperationIDs[${parentIndex}]: missing operation`);
    }
    if (operation.alphaMaskOperationID !== null) {
      const mask = operationByID.get(operation.alphaMaskOperationID);
      if (!mask || mask.maskType !== "alpha") issues.push(`${location}.alphaMaskOperationID: alpha mask operation required`);
    }
    if (operation.authorizationMaskOperationID !== null) {
      const mask = operationByID.get(operation.authorizationMaskOperationID);
      if (!mask || mask.maskType !== "authorization") issues.push(`${location}.authorizationMaskOperationID: authorization mask operation required`);
    }
  }
  const visiting = new Set();
  const visited = new Set();
  const visit = (operation) => {
    if (visited.has(operation.id)) return;
    if (visiting.has(operation.id)) {
      issues.push(`visual DAG.operations: cycle contains '${operation.id}'`);
      return;
    }
    visiting.add(operation.id);
    const dependencies = [...(operation.inputOperationIDs ?? [])];
    if (operation.alphaMaskOperationID) dependencies.push(operation.alphaMaskOperationID);
    if (operation.authorizationMaskOperationID) dependencies.push(operation.authorizationMaskOperationID);
    for (const dependency of dependencies) {
      const parent = operationByID.get(dependency);
      if (parent) visit(parent);
    }
    visiting.delete(operation.id);
    visited.add(operation.id);
  };
  for (const operation of operationByID.values()) visit(operation);

  const expectedFinalPaths = new Set(inventory.assets.map((asset) => asset.assetPath));
  for (const asset of inventory.assets) {
    const operation = outputPathToOperation.get(asset.assetPath);
    if (!operation) {
      issues.push(`visual DAG.operations: missing final asset '${asset.assetPath}'`);
      continue;
    }
    if (operation.outputRole !== asset.kind || !frameEqual(operation.frame, asset.frame)) issues.push(`visual DAG.operations '${operation.id}': role/frame drifted from SceneSpec`);
    if (asset.kind === "scene-mask" && operation.maskType !== asset.maskType) issues.push(`visual DAG.operations '${operation.id}': mask type drifted from SceneSpec`);
    if (/\.hei[cf]$/iu.test(asset.assetPath) && !["encode-heif", "copy-source"].includes(operation.kind)) {
      issues.push(`visual DAG.operations '${operation.id}': HEIF final assets require the pinned encoder or exact source preservation`);
    }
    if (/\.png$/iu.test(asset.assetPath) && operation.kind === "encode-heif") {
      issues.push(`visual DAG.operations '${operation.id}': HEIF bytes cannot be written behind a PNG path`);
    }
  }
  for (const operation of operationByID.values()) {
    if (FINAL_ASSET_KINDS.has(operation.outputRole) && !expectedFinalPaths.has(operation.outputPath)) issues.push(`visual DAG.operations '${operation.id}': unreferenced final asset`);
  }
  if (contract.schemaVersion === 1) {
    for (const plate of contract.cleanPlateCoverage) {
      const operation = outputPathToOperation.get(plate.workingPath);
      if (!operation || operation.outputRole !== "clean-plate" || !frameEqual(operation.frame, plate.frame)) issues.push(`visual DAG.operations: missing clean plate '${plate.workingPath}'`);
    }
  } else {
    for (const underlay of contract.disocclusionUnderlays) {
      if (underlay.recipe.status !== "MEASURED") {
        issues.push(`visual DAG: disocclusion underlay '${underlay.layerID}' remains PENDING_MEASUREMENT`);
      }
      const matchingSources = dagSources.filter(({ path: sourcePath }) => sourcePath === underlay.sourceLayerPlatePath);
      const source = matchingSources[0];
      if (matchingSources.length !== 1 || source?.kind !== "layer-plate") {
        issues.push(`visual DAG.sources: underlay '${underlay.layerID}' requires one layer-plate input at '${underlay.sourceLayerPlatePath}'`);
      }
      const operation = outputPathToOperation.get(underlay.workingPath);
      if (!operation || operation.outputRole !== "working-layer" || !frameEqual(operation.frame, underlay.frame)
          || operation.sourceID !== source?.id || !["normalize-raster", "copy-source"].includes(operation.kind)) {
        issues.push(`visual DAG.operations: underlay '${underlay.layerID}' requires a working-layer output at '${underlay.workingPath}' from its layer-plate input`);
      }
      if (underlay.recipe.status === "MEASURED") {
        if (underlay.recipe.sourceMaster.path !== master?.path || underlay.recipe.sourceMaster.sha256 !== master?.sha256) {
          issues.push(`visual DAG: underlay '${underlay.layerID}' recipe must bind the exact trust-domain production master`);
        }
        const matchingAuthorizationSources = dagSources.filter(({ path: sourcePath }) => sourcePath === underlay.recipe.authorizationMaskSourcePath);
        const authorizationSource = matchingAuthorizationSources[0];
        if (matchingAuthorizationSources.length !== 1 || authorizationSource?.kind !== "authored-mask") {
          issues.push(`visual DAG.sources: underlay '${underlay.layerID}' requires one authored-mask input at '${underlay.recipe.authorizationMaskSourcePath}'`);
        }
        const authorizationOperation = outputPathToOperation.get(underlay.recipe.authorizationMaskWorkingPath);
        if (!authorizationOperation || authorizationOperation.outputRole !== "control-mask"
            || authorizationOperation.kind !== "normalize-mask" || authorizationOperation.maskType !== "authorization"
            || !frameEqual(authorizationOperation.frame, underlay.frame)
            || authorizationOperation.sourceID !== authorizationSource?.id
            || operation?.authorizationMaskOperationID !== authorizationOperation.id) {
          issues.push(`visual DAG.operations: underlay '${underlay.layerID}' must bind its exact authorization-mask operation`);
        }
      }
    }
  }
  for (const mask of contract.auxiliaryMasks) {
    const operation = outputPathToOperation.get(mask.workingPath);
    if (!operation || operation.outputRole !== "control-mask" || operation.maskType !== mask.maskType || !frameEqual(operation.frame, mask.frame)) issues.push(`visual DAG.operations: missing auxiliary mask '${mask.workingPath}'`);
  }
  for (const policy of contract.stateVariantPolicies) {
    const asset = inventory.assets.find((candidate) => candidate.ownerID === policy.layerID && candidate.variantID === policy.variantID && candidate.kind === "scene-layer");
    const operation = outputPathToOperation.get(asset?.assetPath);
    const authorization = operationByID.get(operation?.authorizationMaskOperationID);
    const requiredMask = contract.auxiliaryMasks.find(({ id }) => id === policy.authorizationMaskID);
    if (!operation || authorization?.outputPath !== requiredMask?.workingPath) issues.push(`visual DAG.operations: ${policy.layerID}.${policy.variantID} must bind its declared authorization mask`);
  }

  exactKeys(dag.recomposition, ["outputPath", "diffPath", "baseLayerOperationIDs", "masterSourceID"], [], "visual DAG.recomposition", issues);
  safePath(dag.recomposition.outputPath, "visual DAG.recomposition.outputPath", issues);
  safePath(dag.recomposition.diffPath, "visual DAG.recomposition.diffPath", issues);
  if (dag.recomposition.masterSourceID !== dag.masterSourceID) issues.push("visual DAG.recomposition.masterSourceID: approved master required");
  if (!Array.isArray(dag.recomposition.baseLayerOperationIDs)) issues.push("visual DAG.recomposition.baseLayerOperationIDs: array required");
  const expectedBase = inventory.assets.filter((asset) => asset.kind === "scene-layer" && asset.variantID === null).sort((a, b) => a.order - b.order);
  const actualBase = (dag.recomposition.baseLayerOperationIDs ?? []).map((id) => operationByID.get(id)?.outputPath);
  if (JSON.stringify(actualBase) !== JSON.stringify(expectedBase.map((asset) => asset.assetPath))) issues.push("visual DAG.recomposition.baseLayerOperationIDs: must follow exact SceneSpec base-layer order");

  if (issues.length) throw new VisualProductionError(issues);
  return { dag, contract, inventory, sourcesByID, sourceFileRecords, operationByID, outputPathToOperation, master };
}

function operationDependencies(operation) {
  return [
    ...(operation.inputOperationIDs ?? []),
    ...(operation.alphaMaskOperationID ? [operation.alphaMaskOperationID] : []),
    ...(operation.authorizationMaskOperationID ? [operation.authorizationMaskOperationID] : []),
  ];
}

function topologicalOperations(operationByID) {
  const result = [];
  const visited = new Set();
  const visit = (operation) => {
    if (visited.has(operation.id)) return;
    for (const id of operationDependencies(operation)) visit(operationByID.get(id));
    visited.add(operation.id);
    result.push(operation);
  };
  for (const operation of operationByID.values()) visit(operation);
  return result;
}

async function writeOutput(outputRoot, relativePath, bytes) {
  const output = path.resolve(outputRoot, relativePath);
  if (!output.startsWith(`${path.resolve(outputRoot)}${path.sep}`)) throw new Error("output escaped build root");
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, bytes);
  return output;
}

function rasterForSource(source, sourceFileRecords, pixelFormat) {
  const file = sourceFileRecords.get(source.id);
  if (!file) throw new Error(`source '${source.id}' is unavailable`);
  return decodeRaster(file.resolved, pixelFormat, source.dimensions.width, source.dimensions.height);
}

function sourceCrop(source, sourceFileRecords, frame, canvas, pixelFormat) {
  const channels = pixelFormat === "gray" ? 1 : pixelFormat === "rgb24" ? 3 : 4;
  const pixels = rasterForSource(source, sourceFileRecords, pixelFormat);
  const rect = pixelRect(frame, canvas);
  if (source.dimensions.width === rect.width && source.dimensions.height === rect.height) return pixels;
  if (source.dimensions.width !== canvas.width || source.dimensions.height !== canvas.height) {
    throw new Error(`source '${source.id}' must match its operation frame or the complete master canvas`);
  }
  return cropPixels(pixels, source.dimensions.width, source.dimensions.height, channels, rect);
}

async function executeOperation(operation, context, outputRoot, products) {
  const { inventory, sourcesByID, sourceFileRecords } = context;
  const rect = pixelRect(operation.frame, inventory.canvas);
  let bytes;
  let stats;
  let workingPixels;
  let channels;
  if (operation.kind === "normalize-mask") {
    const source = sourcesByID.get(operation.sourceID);
    workingPixels = sourceCrop(source, sourceFileRecords, operation.frame, inventory.canvas, "gray");
    channels = 1;
    stats = maskStats(workingPixels, rect.width, rect.height);
    if (stats.nonzeroBounds === null) throw new Error(`${operation.id}: empty ${operation.maskType} mask`);
    if (["alpha", "light", "occlusion", "atmosphere", "authorization"].includes(operation.maskType)
        && stats.nonzeroFraction >= 0.999999) {
      throw new Error(`${operation.id}: ${operation.maskType} mask cannot authorize the complete frame`);
    }
    if (operation.maskType === "depth" && stats.minimum === stats.maximum) throw new Error(`${operation.id}: depth mask requires authored variation`);
    bytes = encodePNG(workingPixels, rect.width, rect.height, channels);
  } else if (["normalize-raster", "extract-layer"].includes(operation.kind)) {
    const source = sourcesByID.get(operation.sourceID);
    const rgb = sourceCrop(source, sourceFileRecords, operation.frame, inventory.canvas, "rgb24");
    if (operation.alphaMaskOperationID) {
      const mask = products.get(operation.alphaMaskOperationID);
      if (!mask || mask.channels !== 1 || mask.width !== rect.width || mask.height !== rect.height) throw new Error(`${operation.id}: registered alpha mask dimensions are invalid`);
      workingPixels = applyAlpha(rgb, mask.pixels);
      channels = 4;
    } else {
      workingPixels = rgb;
      channels = 3;
    }
    bytes = encodePNG(workingPixels, rect.width, rect.height, channels);
  } else if (operation.kind === "encode-heif") {
    const input = products.get(operation.inputOperationIDs[0]);
    if (!input || ![3, 4].includes(input.channels)) throw new Error(`${operation.id}: RGB or RGBA operation input required`);
    const output = path.resolve(outputRoot, operation.outputPath);
    if (!output.startsWith(`${path.resolve(outputRoot)}${path.sep}`)) throw new Error("output escaped build root");
    await mkdir(path.dirname(output), { recursive: true });
    run("/usr/bin/sips", [
      "-s", "format", "heic",
      "-s", "formatOptions", operation.parameters.formatOptions,
      input.absolutePath,
      "--out", output,
    ], { encoding: "utf8" });
    bytes = await readFile(output);
    const probe = probeRaster(output);
    if (probe.width !== rect.width || probe.height !== rect.height) throw new Error(`${operation.id}: HEIF dimensions drifted`);
    workingPixels = decodeRaster(output, "rgba", probe.width, probe.height);
    channels = 4;
    const expected = input.channels === 4
      ? input.pixels
      : applyAlpha(input.pixels, new Uint8Array(input.width * input.height).fill(255));
    const comparison = compareRGBA(workingPixels, expected);
    if (comparison.maxChannelError > context.contract.encodingGate.maxChannelError
        || comparison.meanAbsoluteError > context.contract.encodingGate.maxMeanAbsoluteError) {
      throw new VisualProductionError([
        `${operation.id}: HEIF encoding exceeded the visual fidelity gate (${comparison.maxChannelError} max, ${comparison.meanAbsoluteError} mean)`,
      ]);
    }
    stats = {
      encoding: "heic",
      maxChannelError: comparison.maxChannelError,
      meanAbsoluteError: comparison.meanAbsoluteError,
      exactPixelFraction: comparison.exactPixelFraction,
    };
  } else if (operation.kind === "copy-source") {
    const source = sourcesByID.get(operation.sourceID);
    const file = sourceFileRecords.get(source.id);
    bytes = Buffer.from(file.bytes);
    const probe = probeRaster(file.resolved);
    if (probe.width !== rect.width || probe.height !== rect.height) throw new Error(`${operation.id}: copied source does not match registered frame`);
    workingPixels = decodeRaster(file.resolved, "rgba", probe.width, probe.height);
    channels = 4;
  } else {
    throw new Error(`${operation.id}: unsupported operation ${operation.kind}`);
  }
  const output = operation.kind === "encode-heif"
    ? path.resolve(outputRoot, operation.outputPath)
    : await writeOutput(outputRoot, operation.outputPath, bytes);
  const product = {
    id: operation.id,
    outputPath: operation.outputPath,
    absolutePath: output,
    width: rect.width,
    height: rect.height,
    channels,
    pixels: workingPixels,
    bytes: bytes.byteLength,
    sha256: hashBytes(bytes),
    stats,
    operationHash: canonicalSHA256(operation),
  };
  products.set(operation.id, product);
  return product;
}

function blendChannel(back, front, blendMode) {
  if (blendMode === "screen") return 255 - Math.round((255 - back) * (255 - front) / 255);
  return front;
}

function compositeLayer(canvas, canvasWidth, product, asset, alphaProduct) {
  const rect = asset.pixelRect;
  const opacity = asset.opacity ?? 1;
  for (let y = 0; y < rect.height; y += 1) {
    for (let x = 0; x < rect.width; x += 1) {
      const sourceIndex = y * rect.width + x;
      const sourceOffset = sourceIndex * product.channels;
      const targetOffset = ((rect.y + y) * canvasWidth + rect.x + x) * 4;
      const embeddedAlpha = product.channels === 4 ? product.pixels[sourceOffset + 3] / 255 : 1;
      const maskAlpha = alphaProduct ? alphaProduct.pixels[sourceIndex] / 255 : 1;
      const alpha = embeddedAlpha * maskAlpha * opacity;
      const inverse = 1 - alpha;
      for (let channel = 0; channel < 3; channel += 1) {
        const foreground = product.pixels[sourceOffset + channel];
        const blended = blendChannel(canvas[targetOffset + channel], foreground, asset.blendMode);
        canvas[targetOffset + channel] = Math.round(blended * alpha + canvas[targetOffset + channel] * inverse);
      }
      canvas[targetOffset + 3] = 255;
    }
  }
}

function compareRGBA(actual, expected) {
  let maxChannelError = 0;
  let absoluteError = 0;
  let exactPixels = 0;
  const diff = new Uint8Array(actual.byteLength);
  for (let offset = 0; offset < actual.byteLength; offset += 4) {
    let exact = true;
    for (let channel = 0; channel < 3; channel += 1) {
      const delta = Math.abs(actual[offset + channel] - expected[offset + channel]);
      maxChannelError = Math.max(maxChannelError, delta);
      absoluteError += delta;
      exact = exact && delta === 0;
      diff[offset + channel] = delta;
    }
    if (exact) exactPixels += 1;
    diff[offset + 3] = 255;
  }
  const pixelCount = actual.byteLength / 4;
  return {
    maxChannelError,
    meanAbsoluteError: absoluteError / (pixelCount * 3),
    exactPixelFraction: exactPixels / pixelCount,
    diff,
  };
}

function enforceVariantAuthorization(context, products) {
  const issues = [];
  const { contract, inventory, outputPathToOperation, operationByID } = context;
  for (const policy of contract.stateVariantPolicies) {
    const variantAsset = inventory.assets.find((asset) => asset.kind === "scene-layer" && asset.ownerID === policy.layerID && asset.variantID === policy.variantID);
    const baseAsset = inventory.assets.find((asset) => asset.kind === "scene-layer" && asset.ownerID === policy.layerID && asset.variantID === null);
    const variantOperation = outputPathToOperation.get(variantAsset.assetPath);
    const baseOperation = outputPathToOperation.get(baseAsset.assetPath);
    const variant = variantOperation.kind === "encode-heif"
      ? products.get(variantOperation.inputOperationIDs[0])
      : products.get(variantOperation.id);
    const base = baseOperation.kind === "encode-heif"
      ? products.get(baseOperation.inputOperationIDs[0])
      : products.get(baseOperation.id);
    const authorizationOperation = operationByID.get(variantOperation.authorizationMaskOperationID);
    const authorization = products.get(authorizationOperation.id);
    if (variant.width !== base.width || variant.height !== base.height || authorization.width !== base.width || authorization.height !== base.height) {
      issues.push(`${policy.layerID}.${policy.variantID}: base, variant and authorization geometry drifted`);
      continue;
    }
    const rgba = (product) => product.channels === 4
      ? product.pixels
      : applyAlpha(product.pixels, new Uint8Array(product.width * product.height).fill(255));
    const baseRGBA = rgba(base);
    const variantRGBA = rgba(variant);
    let unauthorizedChanges = 0;
    for (let pixel = 0; pixel < authorization.pixels.byteLength; pixel += 1) {
      if (authorization.pixels[pixel] !== 0) continue;
      const offset = pixel * 4;
      for (let channel = 0; channel < 4; channel += 1) {
        if (baseRGBA[offset + channel] !== variantRGBA[offset + channel]) {
          unauthorizedChanges += 1;
          break;
        }
      }
    }
    if (unauthorizedChanges !== 0) issues.push(`${policy.layerID}.${policy.variantID}: ${unauthorizedChanges} pixels changed outside the authored authorization mask`);
    if (authorization.stats.nonzeroFraction > policy.maximumAuthorizedAreaFraction + 1e-12) issues.push(`${policy.layerID}.${policy.variantID}: authorization mask is broader than the contract permits`);
    const alphaOwner = variantOperation.kind === "encode-heif"
      ? operationByID.get(variantOperation.inputOperationIDs[0])
      : variantOperation;
    if (alphaOwner?.alphaMaskOperationID) {
      const alpha = products.get(alphaOwner.alphaMaskOperationID);
      if (alpha?.stats?.nonzeroBounds) {
        const relativeAllowed = {
          x: (policy.allowedAlphaBounds.x - variantAsset.frame.x) / variantAsset.frame.width,
          y: (policy.allowedAlphaBounds.y - variantAsset.frame.y) / variantAsset.frame.height,
          width: policy.allowedAlphaBounds.width / variantAsset.frame.width,
          height: policy.allowedAlphaBounds.height / variantAsset.frame.height,
        };
        if (!frameContains(relativeAllowed, alpha.stats.nonzeroBounds)) issues.push(`${policy.layerID}.${policy.variantID}: alpha bounds escaped the authored state bounds`);
      }
    }
  }
  if (issues.length) throw new VisualProductionError(issues);
}

function enforceUnderlayAuthorization(context, products) {
  if (context.contract.schemaVersion !== 2) return;
  const issues = [];
  for (const underlay of context.contract.disocclusionUnderlays) {
    if (underlay.recipe.status !== "MEASURED") continue;
    const operation = context.outputPathToOperation.get(underlay.workingPath);
    const authorizationOperation = context.operationByID.get(operation.authorizationMaskOperationID);
    const product = products.get(operation.id);
    const authorization = products.get(authorizationOperation.id);
    const baseline = sourceCrop(
      context.master,
      context.sourceFileRecords,
      underlay.frame,
      context.inventory.canvas,
      "rgb24",
    );
    if (!product || !authorization || product.width !== authorization.width || product.height !== authorization.height
        || product.width * product.height * 3 !== baseline.byteLength) {
      issues.push(`${underlay.layerID}: underlay, master crop and authorization geometry drifted`);
      continue;
    }
    let unauthorizedChanges = 0;
    for (let pixel = 0; pixel < authorization.pixels.byteLength; pixel += 1) {
      if (authorization.pixels[pixel] !== 0) continue;
      const sourceOffset = pixel * product.channels;
      const baselineOffset = pixel * 3;
      for (let channel = 0; channel < 3; channel += 1) {
        if (product.pixels[sourceOffset + channel] !== baseline[baselineOffset + channel]) {
          unauthorizedChanges += 1;
          break;
        }
      }
    }
    if (unauthorizedChanges !== 0) {
      issues.push(`${underlay.layerID}: ${unauthorizedChanges} pixels changed outside the authored underlay authorization mask`);
    }
  }
  if (issues.length) throw new VisualProductionError(issues);
}

async function recompose(context, products, outputRoot) {
  const { dag, inventory, sourcesByID, sourceFileRecords, outputPathToOperation, operationByID, contract } = context;
  const canvas = new Uint8Array(inventory.canvas.width * inventory.canvas.height * 4);
  canvas.fill(0);
  for (let index = 3; index < canvas.byteLength; index += 4) canvas[index] = 255;
  for (const operationID of dag.recomposition.baseLayerOperationIDs) {
    const operation = operationByID.get(operationID);
    const finalProduct = products.get(operationID);
    const product = operation.kind === "encode-heif"
      ? products.get(operation.inputOperationIDs[0])
      : finalProduct;
    const asset = inventory.byPath.get(operation.outputPath);
    const alphaAsset = inventory.assets.find((candidate) => candidate.kind === "scene-mask"
      && candidate.ownerID === asset.ownerID && candidate.variantID === null && candidate.maskType === "alpha");
    const alphaOperation = alphaAsset ? outputPathToOperation.get(alphaAsset.assetPath) : undefined;
    const alphaProduct = alphaOperation ? products.get(alphaOperation.id) : undefined;
    compositeLayer(canvas, inventory.canvas.width, product, asset, alphaProduct);
  }
  const master = sourcesByID.get(dag.masterSourceID);
  const expected = rasterForSource(master, sourceFileRecords, "rgba");
  const comparison = compareRGBA(canvas, expected);
  const outputBytes = encodePNG(canvas, inventory.canvas.width, inventory.canvas.height, 4);
  const diffBytes = encodePNG(comparison.diff, inventory.canvas.width, inventory.canvas.height, 4);
  const outputPath = await writeOutput(outputRoot, dag.recomposition.outputPath, outputBytes);
  const diffPath = await writeOutput(outputRoot, dag.recomposition.diffPath, diffBytes);
  const gate = contract.recompositionGate;
  if (comparison.maxChannelError > gate.maxChannelError
      || comparison.meanAbsoluteError > gate.maxMeanAbsoluteError
      || comparison.exactPixelFraction < gate.minimumExactPixelFraction) {
    throw new VisualProductionError([
      `recomposition: max error ${comparison.maxChannelError}, mean error ${comparison.meanAbsoluteError}, exact fraction ${comparison.exactPixelFraction}`,
    ]);
  }
  return {
    outputPath: dag.recomposition.outputPath,
    outputBytes: outputBytes.byteLength,
    outputSHA256: hashBytes(outputBytes),
    diffPath: dag.recomposition.diffPath,
    diffBytes: diffBytes.byteLength,
    diffSHA256: hashBytes(diffBytes),
    ...comparison,
    absoluteOutputPath: outputPath,
    absoluteDiffPath: diffPath,
  };
}

export async function buildVisualAssetDAG({
  dag,
  contract,
  fixture,
  fixtureBytes,
  costRegistry,
  repositoryRoot,
  outputRoot,
  contractRepositoryPath = undefined,
}) {
  const contractContext = await validateVisualProductionContract({
    contract,
    fixture,
    fixtureBytes,
    costRegistry,
    repositoryRoot,
    contractRepositoryPath,
  });
  const context = await validateProductionDAG({ dag, contractContext, repositoryRoot });
  validateInstalledToolchain(contract, contractContext.costByID);
  const products = new Map();
  for (const operation of topologicalOperations(context.operationByID)) {
    await executeOperation(operation, context, outputRoot, products);
  }
  enforceVariantAuthorization(context, products);
  enforceUnderlayAuthorization(context, products);
  const recomposition = await recompose(context, products, outputRoot);
  const sourceRecords = [...context.sourcesByID.values()].map((source) => sourceRecord(source, context.sourceFileRecords.get(source.id).bytes));
  const outputRecords = [...products.values()].map((product) => ({
    id: product.id,
    outputPath: product.outputPath,
    bytes: product.bytes,
    sha256: product.sha256,
    width: product.width,
    height: product.height,
    operationHash: product.operationHash,
    maskStats: product.stats ?? null,
  }));
  const receipt = {
    schemaVersion: 1,
    status: dag.buildMode === visualProductionBuildModes.codexProvisional
      ? provisionalReceiptStatus
      : editorApprovedReceiptStatus,
    buildMode: dag.buildMode,
    shippingState: "PROHIBITED_UNTIL_SEPARATE_EDITOR_ASSET_AND_PACKAGE_APPROVAL",
    dagID: dag.id,
    dagSHA256: canonicalSHA256(dag),
    contractID: contract.id,
    contractSHA256: canonicalSHA256(contract),
    masterAuthority: {
      sourceID: context.master.id,
      kind: context.master.kind,
      record: clone(
        context.master.kind === "provisional-master"
          ? context.master.provisionalAuthority
          : context.master.editorApproval,
      ),
    },
    tools: contract.toolchain.map((tool) => clone(tool)),
    sources: sourceRecords,
    outputs: outputRecords,
    recomposition: {
      outputPath: recomposition.outputPath,
      outputBytes: recomposition.outputBytes,
      outputSHA256: recomposition.outputSHA256,
      diffPath: recomposition.diffPath,
      diffBytes: recomposition.diffBytes,
      diffSHA256: recomposition.diffSHA256,
      maxChannelError: recomposition.maxChannelError,
      meanAbsoluteError: recomposition.meanAbsoluteError,
      exactPixelFraction: recomposition.exactPixelFraction,
    },
    rejectedCandidates: clone(dag.rejectedCandidates),
    backup: clone(dag.backup),
  };
  return { receipt, outputRoot };
}

export async function verifyVisualAssetReceipt(options) {
  const { expectedReceipt, ...buildOptions } = options;
  const result = await buildVisualAssetDAG(buildOptions);
  if (canonicalJSON(result.receipt) !== canonicalJSON(expectedReceipt)) {
    throw new VisualProductionError(["visual receipt: deterministic rebuild drifted"]);
  }
  return result;
}

export async function fileRecord(filePath) {
  const bytes = await readFile(filePath);
  return { bytes: bytes.byteLength, sha256: hashBytes(bytes) };
}

export async function preserveExactFile(sourcePath, backupPath) {
  await mkdir(path.dirname(backupPath), { recursive: true });
  await copyFile(sourcePath, backupPath);
  const [source, backup] = await Promise.all([fileRecord(sourcePath), fileRecord(backupPath)]);
  if (source.bytes !== backup.bytes || source.sha256 !== backup.sha256) throw new Error("backup verification failed");
  return backup;
}

export async function pathExists(filePath) {
  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}
