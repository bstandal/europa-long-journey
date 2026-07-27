#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import {
  copyFile,
  mkdir,
  readFile,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import {
  readBlueprintProjectionDocuments,
  validateBlueprintProjection,
} from "../../tooling/src/blueprint-projection.mjs";
import {
  compileDevelopmentVerticalSlice,
  createDevelopmentProjectionAuthority,
} from "../../tooling/src/vertical-slice-compile.mjs";
import {
  requireResponsiveAudioDecodedBufferBudget,
} from "../../tooling/src/compile.mjs";
import { verticalSliceDevelopmentIdentity } from "../../tooling/src/development-trust.mjs";

const execFileAsync = promisify(execFile);
const fixtureRoot = path.dirname(fileURLToPath(import.meta.url));
const nativeRoot = path.resolve(fixtureRoot, "../..");
const repositoryRoot = path.resolve(nativeRoot, "..");
const blueprintRoot = path.join(nativeRoot, "blueprint");
const sourceRoot = path.join(fixtureRoot, "source");
const packageRoot = path.join(
  fixtureRoot,
  "compiled",
  "vertical-slice-development-v1.runtimefixture",
);
const backstageRoot = path.join(fixtureRoot, "backstage");
const authorityPath = path.join(backstageRoot, "projection-authority.json");
const trustReceiptPath = path.join(
  fixtureRoot,
  "vertical-slice-development-trust-receipt.json",
);
const lineagePath = path.join(fixtureRoot, "fixture-lineage.json");
const version = Object.freeze({ major: 1, minor: 0, patch: 0 });
const firstFarmersResponsiveAudioCandidateRoot = path.join(
  nativeRoot,
  "audio/score-soundscape/distribution-cache/first-farmers-aac-lc-384-alac-fallback-v1",
);
const firstFarmersResponsiveAudioReceiptPath = path.join(
  nativeRoot,
  "audio/score-soundscape/distribution-coding-v1/render-receipt.json",
);
const firstFarmersResponsiveAudioReceiptSHA256Path =
  `${firstFarmersResponsiveAudioReceiptPath}.sha256`;
const firstFarmersResponsiveAudioAssetCount = 91;
const firstFarmersResponsiveAudioSteadyDecodedBytes = 97_920_000;
const firstFarmersResponsiveAudioTransitionDecodedBytes = 115_200_000;
const firstFarmersResponsiveAudioProgramIDs = Object.freeze([
  "household-crosses-responsive-audio-v1",
  "harvest-responsive-audio-v1",
  "three-records-responsive-audio-v1",
  "longhouse-responsive-audio-v1",
  "more-mouths-responsive-audio-v1",
  "continent-remade-responsive-audio-v1",
]);
const moreMouthsTechnicalLiveSlice = Object.freeze({
  beatID: "beat-first-farmers-more-mouths",
  sceneID: "scene-first-farmers-settlement-growth",
  accessibilityID: "accessibility-beat-first-farmers-more-mouths",
  interactionID: "interaction-first-farmers-more-mouths-more-land",
  assetStemID: "lab-first-farmers-land-transformation",
  transparentAssetPath:
    "assets/lab-first-farmers-land-transformation-technical-transparent.png",
  transparentReduceMotionAssetPath:
    "assets/lab-first-farmers-land-transformation-technical-reduce-motion-foreground.png",
  stageMasks: Object.freeze([
    Object.freeze({
      stageID: "new-hearths",
      assetPath:
        "assets/lab-first-farmers-land-transformation-stage-new-hearths-alpha.png",
      pixelBounds: Object.freeze({ x: 92, y: 350, width: 82, height: 170 }),
    }),
    Object.freeze({
      stageID: "field-edges",
      assetPath:
        "assets/lab-first-farmers-land-transformation-stage-field-edges-alpha.png",
      pixelBounds: Object.freeze({ x: 157, y: 318, width: 92, height: 240 }),
    }),
    Object.freeze({
      stageID: "herd-lanes-and-daughters",
      assetPath:
        "assets/lab-first-farmers-land-transformation-stage-herd-lanes-and-daughters-alpha.png",
      pixelBounds: Object.freeze({ x: 223, y: 285, width: 105, height: 310 }),
    }),
  ]),
});

const experienceLabPath = path.join(nativeRoot, "phase1/experience-lab.json");
const visualSources = Object.freeze({
  "scene-first-farmers-iron-gates-dawn": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/before-the-fields.png",
  ),
  "scene-first-farmers-aegean-crossing": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/crossing-the-sea.png",
  ),
  "scene-first-farmers-thessaly-landing": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/crossing-the-sea.png",
  ),
  "scene-first-farmers-thessaly-first-season": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/before-the-fields.png",
  ),
  "scene-first-farmers-danube-arrival": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/at-the-iron-gates.png",
  ),
  "lab-first-farmers-harvest-allocation": path.join(
    nativeRoot,
    "design/phase1/harvest/production-master-candidate-v26-garments-local-composite.png",
  ),
  "scene-first-farmers-store-committed": path.join(
    nativeRoot,
    "design/phase1/harvest/production-master-candidate-v26-garments-local-composite.png",
  ),
  "scene-first-farmers-iron-gates-contact": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/at-the-iron-gates.png",
  ),
  "scene-first-farmers-iron-gates-transformation": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/at-the-iron-gates.png",
  ),
  "scene-first-farmers-danube-to-loess": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/at-the-iron-gates.png",
  ),
  "lab-first-farmers-house-assembly": path.join(
    nativeRoot,
    "design/phase1/longhouse/concepts/option-a4-inherited-ground-readable.png",
  ),
  "scene-first-farmers-longhouse-rebuilt": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/house-outlives-builders.png",
  ),
  "scene-first-farmers-household-descent": path.join(
    repositoryRoot,
    "site/public/assets/chapters/first-farmers/one-house-one-clearing.webp",
  ),
  "lab-first-farmers-land-transformation": path.join(
    repositoryRoot,
    "site/public/assets/chapters/first-farmers/more-mouths-more-land-v2.webp",
  ),
  "scene-first-farmers-local-contraction": path.join(
    repositoryRoot,
    "site/public/assets/chapters/first-farmers/empty-houses-regrowth.webp",
  ),
  "scene-first-farmers-europe-transformation": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/more-mouths-more-land.png",
  ),
  "scene-first-farmers-steppe-handoff": path.join(
    repositoryRoot,
    "site/public/assets/chapters/first-farmers/one-house-one-clearing.webp",
  ),
  "lab-frontiers-northern-valleys-pressure": path.join(
    repositoryRoot,
    "site/public/assets/chapters/europe-holds-the-line/02-northern-valleys-keep-crown.avif",
  ),
  "lab-european-world-ocean-schedule": path.join(
    repositoryRoot,
    "site/public/assets/chapters/european-world/02-steam-keeps-the-appointment.avif",
  ),
});
const supportingResponsiveAudioDerivations = Object.freeze([
  {
    sceneID: "lab-frontiers-northern-valleys-pressure",
    filter: "highpass=f=50,lowpass=f=7200,volume=0.76",
  },
  {
    sceneID: "lab-european-world-ocean-schedule",
    filter: "highpass=f=45,lowpass=f=8400,volume=0.78",
  },
]);
const audioSource = path.join(
  nativeRoot,
  "audio/score-soundscape/cache/harvest-responsive-v1/approach/soundscape-master.wav",
);
const sourcePayloadPath = path.join(
  nativeRoot,
  "phase2/generated/first-farmers.content-package.json",
);
const harvestProofSceneID = "lab-first-farmers-harvest-v26-parallax-proof";
const harvestProofAccessibilityID =
  "accessibility-lab-first-farmers-harvest-v26-parallax-proof";
const harvestProofRoot = path.join(
  nativeRoot,
  "content/backstage/harvest/parallax-halo-qa-v26.provisional",
);
const harvestProofInputs = Object.freeze({
  source: path.join(
    nativeRoot,
    "design/phase1/harvest/production-master-candidate-v26-garments-local-composite.png",
  ),
  diagnosticUnderlay: path.join(harvestProofRoot, "diagnostic-clean-base.png"),
  peopleAlpha: path.join(harvestProofRoot, "alpha-people.png"),
  grainAlpha: path.join(harvestProofRoot, "alpha-grain.png"),
  foregroundAlpha: path.join(harvestProofRoot, "alpha-foreground.png"),
  reduceMotionStatic: path.join(harvestProofRoot, "reduce-motion-static-crop.png"),
  review: path.join(
    nativeRoot,
    "content/backstage/harvest/parallax-halo-qa-v26.review.json",
  ),
  segmentationReceipt: path.join(
    nativeRoot,
    "content/backstage/harvest/semantic-masks-v26.provisional/segmentation-receipt.json",
  ),
});
const harvestProofAssetPaths = Object.freeze({
  source: "assets/harvest-v26-parallax-development-source.png",
  diagnosticUnderlay:
    "assets/harvest-v26-parallax-diagnostic-underlay.png",
  peopleAlpha: "assets/harvest-v26-parallax-alpha-people.png",
  grainAlpha: "assets/harvest-v26-parallax-alpha-grain.png",
  foregroundAlpha: "assets/harvest-v26-parallax-alpha-foreground.png",
  reduceMotionStatic:
    "assets/harvest-v26-parallax-reduce-motion-static.png",
});

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function fileRecord(file) {
  const bytes = await readFile(file);
  return {
    path: path.relative(repositoryRoot, file).split(path.sep).join("/"),
    bytes: bytes.byteLength,
    sha256: sha256(bytes),
  };
}

async function writeJSON(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

function isLowercaseSHA256(value) {
  return typeof value === "string" && /^[a-f0-9]{64}$/u.test(value);
}

function isSafePackagePath(value) {
  if (typeof value !== "string" || value.length === 0
      || value.startsWith("/") || value.includes("\\") || value.includes("://")) {
    return false;
  }
  return value.split("/").every((component) =>
    component.length > 0 && component !== "." && component !== "..");
}

export function validateFirstFarmersResponsiveAudioCandidateReceipt(
  receipt,
  receiptBytes,
  receiptSHA256Sidecar,
) {
  requireCondition(
    Buffer.isBuffer(receiptBytes),
    "responsive audio candidate receipt bytes are required",
  );
  const receiptSHA256 = sha256(receiptBytes);
  requireCondition(
    receiptSHA256Sidecar.trim() === `${receiptSHA256}  render-receipt.json`,
    "responsive audio candidate receipt digest sidecar does not match",
  );
  let receiptFromBytes;
  try {
    receiptFromBytes = JSON.parse(receiptBytes);
  } catch {
    throw new Error("responsive audio candidate receipt is not valid JSON");
  }
  requireCondition(
    JSON.stringify(receiptFromBytes) === JSON.stringify(receipt),
    "responsive audio candidate receipt object is not bound to its bytes",
  );
  requireCondition(
    receipt?.schemaVersion === 1
      && receipt.id === "first-farmers-responsive-aac-lc-384-alac-fallback-render-v1"
      && receipt.status === "PROVISIONAL_NON_SHIPPING"
      && receipt.shippingState === "PROHIBITED"
      && receipt.trustDomain === "BACKSTAGE_AUDIO_DISTRIBUTION_PROBE"
      && receipt.scope?.chapterID === "first-farmers",
    "responsive audio candidate authority is not the locked non-shipping Chapter 1 receipt",
  );
  requireCondition(
    receipt.inventory?.candidateM4AAssets === firstFarmersResponsiveAudioAssetCount
      && receipt.inventory?.sourceResponsiveWAVAssets
        === firstFarmersResponsiveAudioAssetCount
      && receipt.inventory?.aacLCAssets === 90
      && receipt.inventory?.alacFallbackAssets === 1
      && receipt.inventory?.candidateEncodedBytes === 85_479_069,
    "responsive audio candidate inventory drifted",
  );
  requireCondition(
    receipt.decodedPCM?.distributionEncodingDoesNotReduceDecodedWorkingSet === true
      && receipt.decodedPCM?.runtimeConcurrentMemoryGateIsSeparate === true
      && receipt.decodedPCM?.physicalIPhoneMeasurement === "OPEN",
    "responsive audio candidate decoded-memory or physical-test boundary drifted",
  );
  requireCondition(
    receipt.gates?.audioApproval === "OPEN"
      && receipt.gates?.editorApproval === "OPEN"
      && receipt.gates?.physicalIPhonePlayback === "OPEN"
      && receipt.gates?.physicalIPhoneEnergy === "OPEN"
      && receipt.gates?.shippingApproval === "PROHIBITED",
    "responsive audio candidate approval boundary drifted",
  );
  requireCondition(
    Array.isArray(receipt.outputs)
      && receipt.outputs.length === firstFarmersResponsiveAudioAssetCount,
    "responsive audio candidate receipt must contain exactly 91 outputs",
  );

  const bySourcePath = new Map();
  const candidatePaths = new Set();
  let encodedBytes = 0;
  let aacCount = 0;
  let alacCount = 0;
  for (const output of receipt.outputs) {
    const sourcePath = output?.sourcePackageAssetPath;
    const candidatePath = output?.candidateRelativePath;
    requireCondition(
      isSafePackagePath(sourcePath)
        && sourcePath.startsWith("audio/first-farmers/")
        && sourcePath.endsWith(".wav")
        && isSafePackagePath(candidatePath)
        && candidatePath === sourcePath.replace(/\.wav$/u, ".m4a"),
      "responsive audio candidate contains an unsafe or mismatched package path",
    );
    requireCondition(
      output.status === "PROVISIONAL_NON_SHIPPING"
        && output.shippingState === "PROHIBITED"
        && Number.isSafeInteger(output.bytes) && output.bytes > 0
        && isLowercaseSHA256(output.sha256)
        && output.deterministicReplay?.byteIdentical === true
        && output.deterministicReplay?.bytes === output.bytes
        && output.deterministicReplay?.sha256 === output.sha256,
      `${candidatePath}: candidate identity or non-shipping state drifted`,
    );
    requireCondition(
      output.format?.sampleRate === 48_000
        && output.format?.channels === 2
        && output.format?.durationSamples === output.source?.frames
        && output.decoded?.scheduledFrames === output.source?.frames,
      `${candidatePath}: candidate format or scheduled duration drifted`,
    );
    requireCondition(
      !bySourcePath.has(sourcePath) && !candidatePaths.has(candidatePath),
      `${candidatePath}: duplicate responsive audio candidate mapping`,
    );
    bySourcePath.set(sourcePath, output);
    candidatePaths.add(candidatePath);
    encodedBytes += output.bytes;
    if (output.format?.codec === "aac") aacCount += 1;
    else if (output.format?.codec === "alac") alacCount += 1;
    else throw new Error(`${candidatePath}: unsupported live-test codec`);
  }
  requireCondition(
    encodedBytes === receipt.inventory.candidateEncodedBytes
      && aacCount === receipt.inventory.aacLCAssets
      && alacCount === receipt.inventory.alacFallbackAssets,
    "responsive audio candidate aggregate identity drifted",
  );
  return {
    receipt,
    receiptSHA256,
    bySourcePath,
    candidatePaths: [...candidatePaths].sort(),
    encodedBytes,
  };
}

async function loadFirstFarmersResponsiveAudioCandidates() {
  const [receiptBytes, sidecar] = await Promise.all([
    readFile(firstFarmersResponsiveAudioReceiptPath),
    readFile(firstFarmersResponsiveAudioReceiptSHA256Path, "utf8"),
  ]);
  let receipt;
  try {
    receipt = JSON.parse(receiptBytes);
  } catch {
    throw new Error("responsive audio candidate receipt is not valid JSON");
  }
  const candidates = validateFirstFarmersResponsiveAudioCandidateReceipt(
    receipt,
    receiptBytes,
    sidecar,
  );
  for (const output of candidates.bySourcePath.values()) {
    const candidateFile = path.join(
      firstFarmersResponsiveAudioCandidateRoot,
      ...output.candidateRelativePath.split("/"),
    );
    const bytes = await readFile(candidateFile).catch(() => null);
    requireCondition(
      bytes !== null
        && bytes.byteLength === output.bytes
        && sha256(bytes) === output.sha256,
      `${output.candidateRelativePath}: verified M4A candidate is absent or changed`,
    );
  }
  return candidates;
}

async function installFirstFarmersResponsiveAudioCandidates(candidates) {
  for (const output of candidates.bySourcePath.values()) {
    const source = path.join(
      firstFarmersResponsiveAudioCandidateRoot,
      ...output.candidateRelativePath.split("/"),
    );
    const destination = path.join(
      sourceRoot,
      ...output.candidateRelativePath.split("/"),
    );
    await mkdir(path.dirname(destination), { recursive: true });
    await copyFile(source, destination);
  }
}

async function renderRaster(source, destination, tailFilter) {
  const common = "scale=393:852:force_original_aspect_ratio=increase,crop=393:852";
  const filter = tailFilter ? `${common},${tailFilter}` : common;
  await execFileAsync("ffmpeg", [
    "-hide_banner",
    "-loglevel", "error",
    "-y",
    "-i", source,
    "-vf", filter,
    "-frames:v", "1",
    "-map_metadata", "-1",
    destination,
  ]);
}

async function renderTechnicalMask(destination, pixelBounds) {
  const { x, y, width, height } = pixelBounds;
  await execFileAsync("ffmpeg", [
    "-hide_banner",
    "-loglevel", "error",
    "-y",
    "-f", "lavfi",
    "-i", "color=c=black:s=393x852:r=1",
    "-vf",
    `drawbox=x=${x}:y=${y}:w=${width}:h=${height}:color=white:t=fill,gblur=sigma=12,format=gray`,
    "-frames:v", "1",
    "-map_metadata", "-1",
    destination,
  ]);
}

async function renderAssets() {
  const assetRoot = path.join(sourceRoot, "assets");
  const audioRoot = path.join(sourceRoot, "audio");
  const renderedPaths = [];
  await mkdir(assetRoot, { recursive: true });
  await mkdir(audioRoot, { recursive: true });

  const rasterSpecifications = [
    ["base", "eq=contrast=1.02:brightness=-0.025:saturation=0.92"],
    ["state-before", "eq=contrast=0.9:brightness=-0.14:saturation=0.52"],
    ["state-active", "eq=contrast=1.06:brightness=0.015:saturation=0.98"],
    ["state-completed", "eq=contrast=1.12:brightness=0.035:saturation=1.08"],
    ["reduce-motion-underlay", "eq=contrast=0.94:brightness=-0.06:saturation=0.76"],
    ["reduce-motion-foreground", "eq=contrast=1.18:brightness=-0.18:saturation=0.64"],
    ["alpha", "format=gray,eq=contrast=0.22:brightness=0.72"],
    ["occlusion", "format=gray,negate,eq=contrast=0.55:brightness=0.18"],
    ["depth", "format=gray,eq=contrast=0.72:brightness=0.08"],
    ["light", "format=gray,eq=contrast=1.65:brightness=-0.12"],
  ];
  for (const [sceneID, source] of Object.entries(visualSources)) {
    for (const [suffix, filter] of rasterSpecifications) {
      const relative = `assets/${sceneID}-${suffix}.png`;
      await renderRaster(
        source,
        path.join(sourceRoot, ...relative.split("/")),
        filter,
      );
      renderedPaths.push(relative);
    }
  }

  const moreMouthsSource = visualSources[moreMouthsTechnicalLiveSlice.assetStemID];
  const transparentRelative = moreMouthsTechnicalLiveSlice.transparentAssetPath;
  for (const relative of [
    transparentRelative,
    moreMouthsTechnicalLiveSlice.transparentReduceMotionAssetPath,
  ]) {
    await renderRaster(
      moreMouthsSource,
      path.join(sourceRoot, ...relative.split("/")),
      "format=rgba,colorchannelmixer=aa=0",
    );
    renderedPaths.push(relative);
  }
  for (const stageMask of moreMouthsTechnicalLiveSlice.stageMasks) {
    await renderTechnicalMask(
      path.join(sourceRoot, ...stageMask.assetPath.split("/")),
      stageMask.pixelBounds,
    );
    renderedPaths.push(stageMask.assetPath);
  }

  for (const { sceneID, filter } of supportingResponsiveAudioDerivations) {
    const relative = `audio/${sceneID}-soundscape.m4a`;
    await execFileAsync("ffmpeg", [
      "-hide_banner",
      "-loglevel", "error",
      "-y",
      "-i", audioSource,
      "-t", "60",
      "-af", filter,
      "-map_metadata", "-1",
      "-fflags", "+bitexact",
      "-flags:a", "+bitexact",
      "-c:a", "aac",
      "-b:a", "128k",
      "-ar", "48000",
      "-ac", "2",
      path.join(sourceRoot, ...relative.split("/")),
    ]);
    renderedPaths.push(relative);
  }

  for (const [role, packagePath] of Object.entries(harvestProofAssetPaths)) {
    await copyFile(
      harvestProofInputs[role],
      path.join(sourceRoot, ...packagePath.split("/")),
    );
    renderedPaths.push(packagePath);
  }
  return renderedPaths;
}

function collectReferencedAssetPaths(value, key = undefined, paths = new Set()) {
  if (Array.isArray(value)) {
    for (const item of value) collectReferencedAssetPaths(item, undefined, paths);
  } else if (value && typeof value === "object") {
    for (const [childKey, childValue] of Object.entries(value)) {
      collectReferencedAssetPaths(childValue, childKey, paths);
    }
  } else if (typeof value === "string" && (
    key === "assetPath" || key === "alphaMaskAssetPath"
      || key === "occlusionMaskAssetPath" || key === "depthMaskAssetPath"
      || key === "lightMaskAssetPath"
  )) {
    paths.add(value);
  }
  return paths;
}

async function removeUnreferencedRenderedAssets(payload, renderedPaths) {
  const referenced = collectReferencedAssetPaths(payload);
  await Promise.all(renderedPaths
    .filter((assetPath) => !referenced.has(assetPath))
    .map((assetPath) => rm(path.join(sourceRoot, ...assetPath.split("/")), { force: true })));
}

function localizedEnglish(value) {
  return value?.launchEnglish;
}

function local(id, launchEnglish) {
  return { id, launchEnglish };
}

function assetPath(sceneID, suffix) {
  return `assets/${sceneID}-${suffix}.png`;
}

function audioPath(sceneID) {
  return `audio/${sceneID}-soundscape.m4a`;
}

function technicalMasks(sceneID) {
  return {
    alphaMaskAssetPath: assetPath(sceneID, "alpha"),
    occlusionMaskAssetPath: assetPath(sceneID, "occlusion"),
    depthMaskAssetPath: assetPath(sceneID, "depth"),
    lightMaskAssetPath: assetPath(sceneID, "light"),
  };
}

function variantAssetPath(sceneID, variantID) {
  if ([
    "available", "before", "broken", "empty", "exhausted", "idle",
    "resting", "scarce",
  ].includes(variantID)) {
    return assetPath(sceneID, "state-before");
  }
  if ([
    "active", "receiving", "reduced", "resisted", "resisting", "tracing",
  ].includes(variantID)) {
    return assetPath(sceneID, "state-active");
  }
  return assetPath(sceneID, "state-completed");
}

function rewriteMasks(masks, sceneID) {
  const paths = technicalMasks(sceneID);
  for (const key of Object.keys(paths)) {
    if (masks[key]) masks[key] = paths[key];
  }
}

function rewriteAuthoredSceneAssets(scene, sceneID) {
  scene.id = sceneID;
  for (const layer of scene.layers) {
    layer.assetPath = assetPath(sceneID, "base");
    rewriteMasks(layer.masks, sceneID);
    for (const variant of layer.stateVariants) {
      variant.assetPath = variantAssetPath(sceneID, variant.id);
      rewriteMasks(variant.masks, sceneID);
    }
  }
  const staticStrata = scene.reduceMotionComposition.strata.filter(
    ({ kind }) => kind === "staticPlate",
  );
  for (const [index, stratum] of staticStrata.entries()) {
    stratum.assetPath = index === 0
      ? assetPath(sceneID, "reduce-motion-underlay")
      : assetPath(sceneID, "reduce-motion-foreground");
  }
  return scene;
}

function rewriteMoreMouthsTechnicalSceneAssets(scene) {
  requireCondition(
    scene.id === moreMouthsTechnicalLiveSlice.sceneID,
    "More Mouths technical scene must retain its canonical scene ID",
  );
  const basePath = assetPath(moreMouthsTechnicalLiveSlice.assetStemID, "base");
  const activePath = assetPath(
    moreMouthsTechnicalLiveSlice.assetStemID,
    "state-active",
  );
  const completedPath = assetPath(
    moreMouthsTechnicalLiveSlice.assetStemID,
    "state-completed",
  );
  const reduceMotionUnderlayPath = assetPath(
    moreMouthsTechnicalLiveSlice.assetStemID,
    "reduce-motion-underlay",
  );
  const masksByLayerID = new Map(
    moreMouthsTechnicalLiveSlice.stageMasks.map(({ stageID, assetPath }) => [
      `stage-${stageID}`,
      { alphaMaskAssetPath: assetPath },
    ]),
  );

  for (const layer of scene.layers) {
    const stageMasks = masksByLayerID.get(layer.id);
    if (stageMasks) {
      layer.assetPath = basePath;
      layer.masks = structuredClone(stageMasks);
      for (const variant of layer.stateVariants) {
        if (variant.id === "before") variant.assetPath = basePath;
        else if (variant.id === "active") variant.assetPath = activePath;
        else if (variant.id === "completed") variant.assetPath = completedPath;
        else throw new Error(`More Mouths has unsupported state '${variant.id}'`);
        variant.masks = structuredClone(stageMasks);
      }
      continue;
    }

    if (layer.id === "far-landscape") {
      layer.assetPath = basePath;
      layer.masks = {};
      continue;
    }

    // The technical fixture must not place a full-frame opaque plate above
    // the three causal overlays. These transparent placeholders prove the
    // runtime ordering without making any production-art claim.
    layer.assetPath = moreMouthsTechnicalLiveSlice.transparentAssetPath;
    layer.masks = {};
    for (const variant of layer.stateVariants) {
      variant.assetPath = moreMouthsTechnicalLiveSlice.transparentAssetPath;
      variant.masks = {};
    }
  }

  const staticStrata = scene.reduceMotionComposition.strata.filter(
    ({ kind }) => kind === "staticPlate",
  );
  for (const [index, stratum] of staticStrata.entries()) {
    stratum.assetPath = index === 0
      ? reduceMotionUnderlayPath
      : moreMouthsTechnicalLiveSlice.transparentReduceMotionAssetPath;
  }
  return scene;
}

function baselineCrop() {
  return {
    id: "baseline-393x852",
    viewport: { widthPoints: 393, heightPoints: 852 },
    sourceRect: { x: 0.15, y: 0.15, width: 0.7, height: 0.7 },
    safeTextRegions: [
      { id: "narrative-copy", rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.2 } },
      { id: "mechanism-caption", rect: { x: 0.12, y: 0.78, width: 0.76, height: 0.12 } },
    ],
  };
}

function targetRegion(x, y, width = 0.15, height = 0.12) {
  return {
    path: [
      { x, y },
      { x: x + width, y },
      { x: x + width, y: y + height },
      { x, y: y + height },
    ],
  };
}

function technicalLayer(sceneID, id, order, variants = [], options = {}) {
  return {
    id,
    order,
    assetPath: assetPath(sceneID, "base"),
    frame: { x: 0, y: 0, width: 1, height: 1 },
    depth: options.depth ?? Math.min(0.96, 0.08 + order * 0.12),
    opacity: options.opacity ?? 1,
    blendMode: options.blendMode ?? "normal",
    masks: technicalMasks(sceneID),
    motion: {
      parallaxFactor: options.parallaxFactor ?? 0,
      windResponse: 0,
      focusResponse: options.focusResponse ?? 0.2,
    },
    stateVariants: variants.map((id) => ({
      id,
      assetPath: variantAssetPath(sceneID, id),
      masks: technicalMasks(sceneID),
    })),
  };
}

function technicalScene({
  sceneID,
  accessibilityID,
  mechanism,
  layers,
  interactionTargets,
  interactionVisualBinding,
  atmosphere,
}) {
  const statefulLayers = layers.filter(({ stateVariants }) => stateVariants.length > 0);
  return {
    id: sceneID,
    sceneCanvas: {
      canvas: { width: 1179, height: 2556 },
      cameraTravelBounds: { x: 0.2, y: 0.2, width: 0.6, height: 0.6 },
      authoredOverscanFraction: 0.15,
      viewportCrops: [baselineCrop()],
    },
    layers,
    cameraRail: {
      keyframes: [
        { progress: 0, center: { x: 0.5, y: 0.5 }, scale: 1 },
        { progress: 1, center: { x: 0.5, y: 0.5 }, scale: 1 },
      ],
    },
    atmosphere: [atmosphere],
    interactionTargets,
    interactionVisualBinding,
    reduceMotionComposition: {
      canvas: { width: 1179, height: 2556 },
      viewportCrops: [baselineCrop()],
      strata: [
        {
          id: "static-underlay",
          kind: "staticPlate",
          assetPath: assetPath(sceneID, "reduce-motion-underlay"),
        },
        ...statefulLayers.map(({ id }) => ({
          id: `${id}-state`,
          kind: "stateOverlay",
          layerID: id,
        })),
        {
          id: "static-foreground",
          kind: "staticPlate",
          assetPath: assetPath(sceneID, "reduce-motion-foreground"),
        },
      ],
    },
    mechanismFocus: mechanism,
    accessibilityID,
  };
}

function harvestProofCrop() {
  return {
    id: "baseline-393x852",
    viewport: { widthPoints: 393, heightPoints: 852 },
    sourceRect: {
      x: 103 / 1290,
      y: 224 / 2796,
      width: 1084 / 1290,
      height: 2348 / 2796,
    },
    safeTextRegions: [
      { id: "narrative-copy", rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.2 } },
      { id: "mechanism-caption", rect: { x: 0.12, y: 0.78, width: 0.76, height: 0.12 } },
    ],
  };
}

function harvestProofStaticCrop() {
  return {
    id: "baseline-393x852",
    viewport: { widthPoints: 393, heightPoints: 852 },
    sourceRect: { x: 0, y: 0, width: 1, height: 1 },
    safeTextRegions: [
      { id: "narrative-copy", rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.2 } },
      { id: "mechanism-caption", rect: { x: 0.12, y: 0.78, width: 0.76, height: 0.12 } },
    ],
  };
}

function harvestProofLayer(id, order, depth, parallaxFactor, alphaMaskAssetPath = null) {
  return {
    id,
    order,
    assetPath: id === "diagnostic-underlay"
      ? harvestProofAssetPaths.diagnosticUnderlay
      : harvestProofAssetPaths.source,
    frame: { x: 0, y: 0, width: 1, height: 1 },
    depth,
    opacity: 1,
    blendMode: "normal",
    masks: alphaMaskAssetPath ? { alphaMaskAssetPath } : {},
    motion: { parallaxFactor, windResponse: 0, focusResponse: 0 },
    stateVariants: [],
  };
}

function makeHarvestParallaxProof() {
  const mechanism = local(
    `${harvestProofSceneID}-mechanism-focus`,
    "Hands, grain and foreground material separate by bounded depth while the settlement remains fixed beneath them.",
  );
  const scene = {
    id: harvestProofSceneID,
    sceneCanvas: {
      canvas: { width: 1290, height: 2796 },
      cameraTravelBounds: { x: 0.42, y: 0.44, width: 0.16, height: 0.12 },
      authoredOverscanFraction: 0.15,
      viewportCrops: [harvestProofCrop()],
    },
    layers: [
      harvestProofLayer("diagnostic-underlay", 0, 0.08, 0),
      harvestProofLayer(
        "people",
        1,
        0.42,
        3 / (0.01 * 1290),
        harvestProofAssetPaths.peopleAlpha,
      ),
      harvestProofLayer(
        "grain",
        2,
        0.64,
        8 / (0.01 * 1290),
        harvestProofAssetPaths.grainAlpha,
      ),
      harvestProofLayer(
        "foreground",
        3,
        0.9,
        10 / (0.01 * 1290),
        harvestProofAssetPaths.foregroundAlpha,
      ),
    ],
    // The rail begins at the frozen crop. Its two extrema keep every relative
    // layer displacement at or below the exact v26 PARTIAL_PASS stress bound.
    cameraRail: {
      keyframes: [
        { progress: 0, center: { x: 0.5, y: 0.5 }, scale: 1 },
        { progress: 0.5, center: { x: 0.49, y: 0.5015379113018598 }, scale: 1 },
        { progress: 1, center: { x: 0.51, y: 0.4984620886981402 }, scale: 1 },
      ],
    },
    atmosphere: [],
    interactionTargets: [],
    reduceMotionComposition: {
      canvas: { width: 786, height: 1704 },
      viewportCrops: [harvestProofStaticCrop()],
      strata: [{
        id: "frozen-static-crop",
        kind: "staticPlate",
        assetPath: harvestProofAssetPaths.reduceMotionStatic,
      }],
    },
    mechanismFocus: mechanism,
    accessibilityID: harvestProofAccessibilityID,
  };
  const accessibility = {
    id: harvestProofAccessibilityID,
    sceneSummary: local(
      `${harvestProofSceneID}-scene-summary`,
      "A harvest settlement held at the exact approved static crop.",
    ),
    elements: [
      {
        id: "scene-heading",
        role: "heading",
        label: local(
          `${harvestProofSceneID}-heading`,
          "The Harvest Had to Last",
        ),
        actions: [],
      },
      {
        id: "historical-mechanism",
        role: "mechanism",
        label: mechanism,
        actions: [],
      },
    ],
  };
  return { scene, accessibility };
}

function descriptiveAccessibilityElements(beat, mechanism) {
  return [
    {
      id: "scene-heading",
      role: "heading",
      label: beat.narrative.heading,
      actions: [],
    },
    ...beat.narrative.paragraphs.map((paragraph, index) => ({
      id: `narration-${index + 1}`,
      role: "narration",
      label: paragraph,
      actions: [],
    })),
    {
      id: "historical-mechanism",
      role: "mechanism",
      label: mechanism,
      actions: [],
    },
  ];
}

function action(kind, id, label, token) {
  return { kind, label: local(id, label), token };
}

function makeAccessibility(beat, mechanism, controls) {
  return {
    id: beat.interaction.accessibilityID,
    sceneSummary: local(
      `${beat.id}-scene-summary`,
      `${beat.narrative.heading.launchEnglish}. ${mechanism.launchEnglish}`,
    ),
    elements: descriptiveAccessibilityElements(beat, mechanism).concat(controls),
  };
}

function makeResponsiveAudio(chapterID, arcID, beat, sceneID) {
  const regions = [
    ["approach", 144000],
    ["waiting", 96000],
    ["engaged", 96000],
    ["resistance", 96000],
    ["consequence", 144000],
  ];
  const timelineID = (region) => `responsive-${beat.id}-${region}`;
  return {
    program: {
      id: `responsive-program-${beat.id}`,
      scope: {
        chapterID,
        arcID,
        beatID: beat.id,
        interactionID: beat.interaction.id,
      },
      approachTimelineID: timelineID("approach"),
      interactionBeds: ["waiting", "engaged", "resistance"].map((phase) => ({
        phase,
        timelineID: timelineID(phase),
        layerStates: {
          soundscapeStateID: `${sceneID}-${phase}-world`,
        },
      })),
      consequenceTimelineID: timelineID("consequence"),
      exitPolicy: {
        kind: "bounded-fade",
        durationSamples: 9_600,
      },
    },
    timelines: regions.map(([region, durationSamples]) => ({
      id: timelineID(region),
      sampleRate: 48000,
      events: [{
        cueID: `cue-${beat.id}-${region}-soundscape`,
        role: "soundscape",
        startSample: 0,
        durationSamples,
        assetPath: audioPath(sceneID),
        gain: 0.72,
      }],
      haptics: [],
    })),
  };
}

function programTimelineIDs(program) {
  return [
    program.approachTimelineID,
    ...program.interactionBeds.map(({ timelineID }) => timelineID),
    program.consequenceTimelineID,
  ];
}

export function projectFirstFarmersResponsiveAudio(
  source,
  projectedChapter,
  candidates,
) {
  const sourcePrograms = source.responsiveAudioPrograms.filter(
    ({ scope }) => scope.chapterID === "first-farmers",
  );
  requireCondition(
    sourcePrograms.length === firstFarmersResponsiveAudioProgramIDs.length
      && sourcePrograms.map(({ id }) => id).join("\n")
        === firstFarmersResponsiveAudioProgramIDs.join("\n"),
    "authored First Farmers responsive program inventory drifted",
  );
  requireCondition(
    candidates?.bySourcePath instanceof Map
      && candidates.bySourcePath.size === firstFarmersResponsiveAudioAssetCount,
    "exact responsive audio candidate mapping is required",
  );

  const projectedScopesByInteractionID = new Map();
  for (const arc of projectedChapter.arcs) {
    for (const beat of arc.beats) {
      if (!beat.interaction) continue;
      requireCondition(
        !projectedScopesByInteractionID.has(beat.interaction.id),
        `${beat.interaction.id}: duplicate projected interaction scope`,
      );
      projectedScopesByInteractionID.set(beat.interaction.id, {
        chapterID: projectedChapter.id,
        arcID: arc.id,
        beatID: beat.id,
        interactionID: beat.interaction.id,
      });
    }
  }

  const timelineIDs = new Set();
  const projectedPrograms = sourcePrograms.map((sourceProgram) => {
    const program = structuredClone(sourceProgram);
    const projectedScope = projectedScopesByInteractionID.get(
      sourceProgram.scope.interactionID,
    );
    requireCondition(
      projectedScope !== undefined,
      `${sourceProgram.id}: projected interaction scope is missing`,
    );
    program.scope = projectedScope;
    for (const timelineID of programTimelineIDs(program)) {
      requireCondition(
        typeof timelineID === "string" && !timelineIDs.has(timelineID),
        `${sourceProgram.id}: duplicate or invalid responsive timeline ID`,
      );
      timelineIDs.add(timelineID);
    }
    if (program.causalMix) {
      for (const layer of program.causalMix.layers) {
        const output = candidates.bySourcePath.get(layer.assetPath);
        requireCondition(
          output !== undefined,
          `${sourceProgram.id}: causal layer has no verified M4A candidate`,
        );
        layer.assetPath = output.candidateRelativePath;
      }
    }
    return program;
  });
  requireCondition(
    timelineIDs.size === firstFarmersResponsiveAudioProgramIDs.length * 5,
    "First Farmers must project exactly thirty responsive timelines",
  );

  const usedSourcePaths = new Set();
  const projectedTimelines = source.audioTimelines
    .filter(({ id }) => timelineIDs.has(id))
    .map((sourceTimeline) => {
      const timeline = structuredClone(sourceTimeline);
      timeline.events = timeline.events.map((event) => {
        if (event.role === "silence") return event;
        const output = candidates.bySourcePath.get(event.assetPath);
        requireCondition(
          output !== undefined,
          `${timeline.id}/${event.cueID}: no verified M4A candidate`,
        );
        usedSourcePaths.add(event.assetPath);
        return { ...event, assetPath: output.candidateRelativePath };
      });
      return timeline;
    });
  requireCondition(
    projectedTimelines.length === timelineIDs.size
      && projectedTimelines.every(({ id }) => timelineIDs.has(id)),
    "First Farmers responsive timeline source is incomplete",
  );
  const missingOrUnused = [...candidates.bySourcePath.keys()].filter(
    (sourcePath) => !usedSourcePaths.has(sourcePath),
  );
  requireCondition(
    usedSourcePaths.size === firstFarmersResponsiveAudioAssetCount
      && missingOrUnused.length === 0,
    "the six First Farmers programs do not consume exactly 91 verified M4A candidates",
  );
  return {
    programs: projectedPrograms,
    timelines: projectedTimelines,
    assetPaths: [...usedSourcePaths]
      .map((sourcePath) => candidates.bySourcePath.get(sourcePath).candidateRelativePath)
      .sort(),
  };
}

export function requireRepresentativeFirstFarmersResponsiveAudio(payload) {
  const programs = payload.responsiveAudioPrograms.filter(
    ({ scope }) => scope.chapterID === "first-farmers",
  );
  requireCondition(
    programs.length === firstFarmersResponsiveAudioProgramIDs.length
      && programs.map(({ id }) => id).join("\n")
        === firstFarmersResponsiveAudioProgramIDs.join("\n"),
    "live-test payload does not contain the six authored First Farmers programs",
  );
  const timelineIDs = new Set(programs.flatMap(programTimelineIDs));
  requireCondition(
    timelineIDs.size === 30,
    "live-test payload does not contain thirty authored First Farmers timelines",
  );
  const timelines = payload.audioTimelines.filter(({ id }) => timelineIDs.has(id));
  requireCondition(
    timelines.length === timelineIDs.size,
    "live-test payload is missing an authored First Farmers timeline",
  );
  const paths = new Set(timelines.flatMap(({ events }) => events)
    .filter(({ role }) => role !== "silence")
    .map(({ assetPath }) => assetPath));
  requireCondition(
    paths.size === firstFarmersResponsiveAudioAssetCount
      && [...paths].every((assetPath) =>
        isSafePackagePath(assetPath)
          && assetPath.startsWith("audio/first-farmers/")
          && assetPath.endsWith(".m4a")),
    "live-test payload does not bind exactly 91 First Farmers M4A assets",
  );
  const estimate = requireResponsiveAudioDecodedBufferBudget(
    payload,
    100_000_000,
    200_000_000,
  );
  requireCondition(
    estimate.steady.bytes === firstFarmersResponsiveAudioSteadyDecodedBytes
      && estimate.steady.programID === "three-records-responsive-audio-v1"
      && estimate.transition.bytes
        === firstFarmersResponsiveAudioTransitionDecodedBytes
      && estimate.transition.programID === "three-records-responsive-audio-v1",
    "live-test responsive audio decoded-buffer bounds drifted from 97.92/115.20 MB",
  );
  return {
    programIDs: programs.map(({ id }) => id),
    timelineIDs: [...timelineIDs].sort(),
    assetPaths: [...paths].sort(),
    decodedBufferEstimate: estimate,
  };
}

function approvedArc(documents, contentID, arcID) {
  const chapter = documents.arcs.chapters.find((item) => item.contentID === contentID);
  const arc = chapter?.arcs.find((item) => item.arcID === arcID);
  if (!arc) throw new Error(`Missing approved arc ${contentID}/${arcID}`);
  return arc;
}

function approvedContract(documents, contentID) {
  const contract = documents.contracts.contracts.find((item) => item.contentID === contentID);
  if (!contract) throw new Error(`Missing approved contract ${contentID}`);
  return contract;
}

function projectArc(arc, beats, prefix) {
  return {
    id: arc.arcID,
    title: local(`${prefix}-title`, arc.title),
    targetDurationMinutes: arc.targetDurationMinutes,
    situation: local(`${prefix}-situation`, arc.situation),
    mechanism: local(`${prefix}-mechanism`, arc.mechanism),
    turn: local(`${prefix}-turn`, arc.turn),
    consequence: local(`${prefix}-consequence`, arc.consequence),
    handoff: local(`${prefix}-handoff`, arc.handoff),
    beats,
  };
}

function revealNodeEffect(id, nodeID, kind, form, position, attributes = []) {
  return {
    id,
    mutation: "reveal-node",
    node: { id: nodeID, kind, form, position, attributes },
  };
}

function makeAssembleProjection(source) {
  const sceneID = "lab-first-farmers-house-assembly";
  const sourceBeat = source.chapters[0].arcs
    .flatMap(({ beats }) => beats)
    .find(({ interaction }) => interaction?.id === "interaction-first-farmers-the-house-outlives");
  if (!sourceBeat) throw new Error("Missing authored house assembly beat");
  const beat = structuredClone(sourceBeat);
  beat.id = "beat-first-farmers-house-assembly";
  beat.sceneID = sceneID;
  beat.narrationCueIDs = [];
  beat.interaction.accessibilityID = "accessibility-lab-first-farmers-house-assembly";
  const mechanism = local(
    `${sceneID}-mechanism-focus`,
    "Posts, hearth, storage and roof make one house; rebuilding fixes the household to remembered ground.",
  );
  const sourcePositions = [
    [0.2, 0.36], [0.36, 0.36], [0.52, 0.36], [0.68, 0.36],
  ];
  const slotPositions = [
    [0.2, 0.64], [0.36, 0.64], [0.52, 0.64], [0.68, 0.64],
  ];
  const components = beat.interaction.configuration.components;
  const componentLayers = components.map(({ id }, index) =>
    technicalLayer(sceneID, `component-${id}`, index + 1, ["available", "resisted", "placed"]));
  const targets = components.flatMap(({ id }, index) => [
    {
      interactionTargetID: `component-${id}-source`,
      layerID: `component-${id}`,
      hitRegion: targetRegion(...sourcePositions[index], 0.1, 0.1),
      accessibilityElementID: `assemble-${id}`,
    },
    {
      interactionTargetID: `component-${id}-slot`,
      layerID: `component-${id}`,
      hitRegion: targetRegion(...slotPositions[index], 0.1, 0.1),
      accessibilityElementID: `assemble-${id}`,
    },
  ]);
  const scene = technicalScene({
    sceneID,
    accessibilityID: beat.interaction.accessibilityID,
    mechanism,
    layers: [
      technicalLayer(sceneID, "background", 0, [], { depth: 0.08, parallaxFactor: 0.02 }),
      ...componentLayers,
      technicalLayer(sceneID, "foreground", components.length + 1, [], {
        depth: 0.92,
        parallaxFactor: 0.08,
      }),
    ],
    interactionTargets: targets,
    interactionVisualBinding: {
      grammar: "assemble",
      configuration: {
        interactionID: beat.interaction.id,
        components: components.map(({ id }) => ({
          componentID: id,
          sourceInteractionTargetID: `component-${id}-source`,
          slotInteractionTargetID: `component-${id}-slot`,
          layerID: `component-${id}`,
          availableVariantID: "available",
          resistedVariantID: "resisted",
          placedVariantID: "placed",
        })),
      },
    },
    atmosphere: {
      kind: "smoke",
      density: 0.13,
      velocity: { dx: 0.03, dy: -0.08 },
      deterministicSeed: 19910411,
    },
  });
  const controls = components.map(({ id }) => ({
    id: `assemble-${id}`,
    role: "action",
    label: local(`${beat.id}-${id}-label`, id.replaceAll("-", " ")),
    actions: [action(
      "activate",
      `${beat.id}-${id}-place-label`,
      `Place ${id.replaceAll("-", " ")}`,
      { command: "place-component", targetID: id },
    )],
  }));
  return { beat, scene, accessibility: makeAccessibility(beat, mechanism, controls) };
}

function makeTransformProjection(source) {
  const sourceBeat = source.chapters[0].arcs
    .flatMap(({ beats }) => beats)
    .find(({ interaction }) =>
      interaction?.id === moreMouthsTechnicalLiveSlice.interactionID);
  const sourceScene = source.scenes.find(({ id }) => id === sourceBeat?.sceneID);
  const sourceAccessibility = source.accessibility.find(
    ({ id }) => id === sourceBeat?.interaction?.accessibilityID,
  );
  if (!sourceBeat || !sourceScene || !sourceAccessibility) {
    throw new Error("Missing authored land transformation projection");
  }
  requireCondition(
    sourceBeat.id === moreMouthsTechnicalLiveSlice.beatID
      && sourceScene.id === moreMouthsTechnicalLiveSlice.sceneID
      && sourceAccessibility.id === moreMouthsTechnicalLiveSlice.accessibilityID,
    "More Mouths canonical identity drifted before technical projection",
  );
  const beat = structuredClone(sourceBeat);
  beat.narrationCueIDs = [];
  const scene = rewriteMoreMouthsTechnicalSceneAssets(
    structuredClone(sourceScene),
  );
  const accessibility = structuredClone(sourceAccessibility);
  return { beat, scene, accessibility };
}

function makePressureProjection(documents) {
  const sceneID = "lab-frontiers-northern-valleys-pressure";
  const accessibilityID = "accessibility-lab-frontiers-northern-valleys-pressure";
  const interaction = {
    id: "interaction-europe-holds-the-line-northern-valleys-keep-crown",
    prompt: local(`${sceneID}-prompt`, "Hold the northern valleys"),
    grammar: "pressure",
    configuration: {
      forces: [
        { id: "conquest-pressure", direction: 1, initialMagnitude: 0.85, userControllable: false },
        { id: "mountain-depth", direction: -1, initialMagnitude: 0.15, userControllable: false },
        { id: "inhabited-stores", direction: -1, initialMagnitude: 0.2, userControllable: true },
      ],
      stableRange: [-0.05, 0.05],
      requiredHoldMillis: 1000,
    },
    completionEffects: [revealNodeEffect(
      "effect-europe-holds-the-line-northern-valleys-keep-crown",
      "trace-christian-frontier",
      "frontier",
      "Held passes, Oviedo, monastic stores and defended fields reaching toward León",
      { x: 0.32, y: 0.44 },
      [
        { key: "inhabitedCorridor", value: true },
        { key: "heldPasses", value: 1 },
      ],
    )],
    accessibilityID,
  };
  const beat = {
    id: "beat-frontiers-northern-valleys-pressure",
    sceneID,
    narrative: {
      eyebrow: local(`${sceneID}-eyebrow`, "c. AD 718–910 · Asturias"),
      heading: local(`${sceneID}-heading`, "The Northern Valleys Keep a Crown"),
      paragraphs: [
        local(
          `${sceneID}-paragraph-1`,
          "Rain crossed the Cantabrian ridges, paths narrowed above wooded ravines and an army accustomed to open country lost the advantage of numbers. Pelagius and a small Christian following preserved an armed centre beyond Córdoba’s dependable control.",
        ),
        local(
          `${sceneID}-paragraph-2`,
          "Asturian kings turned endurance into government. A court at Oviedo, churches, monasteries, defended routes and stored grain carried the crown toward León and the Duero basin.",
        ),
      ],
      actionPrompt: local(`${sceneID}-action`, "Hold the inhabited line"),
    },
    narrationCueIDs: [],
    interaction,
    completionEffects: [],
    checkpoint: "continuous",
  };
  const mechanism = local(
    `${sceneID}-mechanism-focus`,
    "Terrain buys refuge; court, stores and defended fields turn refuge into a frontier that can advance.",
  );
  const layers = [
    technicalLayer(sceneID, "background", 0, [], { depth: 0.08, parallaxFactor: 0.02 }),
    technicalLayer(sceneID, "conquest-force", 1),
    technicalLayer(sceneID, "mountain-depth", 2),
    technicalLayer(sceneID, "inhabited-stores", 3),
    technicalLayer(sceneID, "frontier-system", 4, ["resting", "resisting", "stable", "broken"]),
    technicalLayer(sceneID, "foreground", 5, [], { depth: 0.92, parallaxFactor: 0.08 }),
  ];
  const scene = technicalScene({
    sceneID,
    accessibilityID,
    mechanism,
    layers,
    interactionTargets: [{
      interactionTargetID: "inhabited-stores-target",
      layerID: "inhabited-stores",
      hitRegion: targetRegion(0.42, 0.56, 0.16, 0.16),
      accessibilityElementID: "pressure-inhabited-stores",
    }],
    interactionVisualBinding: {
      grammar: "pressure",
      configuration: {
        interactionID: interaction.id,
        forces: [
          { forceID: "conquest-pressure", layerID: "conquest-force" },
          { forceID: "mountain-depth", layerID: "mountain-depth" },
          {
            forceID: "inhabited-stores",
            layerID: "inhabited-stores",
            interactionTargetID: "inhabited-stores-target",
          },
        ],
        systemLayerID: "frontier-system",
        restingVariantID: "resting",
        resistingVariantID: "resisting",
        stableVariantID: "stable",
        brokenVariantID: "broken",
      },
    },
    atmosphere: {
      kind: "rain",
      density: 0.18,
      velocity: { dx: -0.08, dy: 0.18 },
      deterministicSeed: 19910413,
    },
  });
  const controls = [{
    id: "pressure-inhabited-stores",
    role: "adjustable",
    label: local(`${sceneID}-stores-label`, "The inhabited corridor"),
    hint: local(`${sceneID}-stores-hint`, "Strengthen the stores, fields and defended routes."),
    actions: [
      action("increment", `${sceneID}-stores-increase`, "Strengthen the corridor", {
        command: "adjust-pressure", targetID: "inhabited-stores", step: 0.5,
      }),
      action("decrement", `${sceneID}-stores-decrease`, "Release the corridor", {
        command: "adjust-pressure", targetID: "inhabited-stores", step: 0.5,
      }),
    ],
  }, {
    id: "pressure-hold-line",
    role: "action",
    label: local(`${sceneID}-hold-label`, "Hold the line"),
    actions: [action("activate", `${sceneID}-hold-action`, "Hold the line", {
      command: "hold-pressure",
    })],
  }];
  const contract = approvedContract(documents, "europe-holds-the-line");
  const arc = approvedArc(documents, "europe-holds-the-line", "europe-holds-the-line-arc-01");
  const chapter = {
    schemaVersion: version,
    id: "europe-holds-the-line",
    title: local("lab-frontiers-title", contract.title),
    period: local("lab-frontiers-period", contract.period),
    arcs: [projectArc(arc, [beat], "lab-frontiers-arc-01")],
    completionEffects: [revealNodeEffect(
      "effect-europe-holds-the-line-europe-answers-clermont",
      "trace-coalition-defence",
      "institution",
      "A coalition route able to carry armed aid across Christian Europe",
      { x: 0.49, y: 0.47 },
    )],
  };
  return { chapter, beat, scene, accessibility: makeAccessibility(beat, mechanism, controls) };
}

function makeTraceProjection(documents) {
  const sceneID = "lab-european-world-ocean-schedule";
  const accessibilityID = "accessibility-lab-european-world-ocean-schedule";
  const interaction = {
    id: "interaction-european-world-steam-keeps-the-appointment",
    prompt: local(`${sceneID}-prompt`, "Put the ocean on schedule"),
    grammar: "trace",
    configuration: {
      anchors: [
        { x: 0.3, y: 0.54 },
        { x: 0.43, y: 0.52 },
        { x: 0.57, y: 0.5 },
        { x: 0.7, y: 0.48 },
      ],
      tolerance: 0.08,
    },
    completionEffects: [{
      id: "effect-european-world-steam-keeps-the-appointment",
      mutation: "establish-trace",
      trace: {
        id: "trace-global-schedule",
        kind: "seaRoute",
        origin: "bristol-packet-office",
        destination: "new-york-packet-office",
        strength: 1,
      },
    }],
    accessibilityID,
  };
  const beat = {
    id: "beat-european-world-ocean-schedule",
    sceneID,
    narrative: {
      eyebrow: local(`${sceneID}-eyebrow`, "AD 1838–1840 · North Atlantic"),
      heading: local(`${sceneID}-heading`, "Steam Keeps the Appointment"),
      paragraphs: [
        local(
          `${sceneID}-paragraph-1`,
          "In April 1838, Sirius and Great Western reached New York from Britain under steam. A purpose-built steamship could carry enough coal for the North Atlantic and retain motive power when the wind failed.",
        ),
        local(
          `${sceneID}-paragraph-2`,
          "From 1840, Cunard packets left Liverpool on announced dates. Coal bunkers, engineering watches, shore agents and mail offices made repeated appointments reliable enough for other institutions to attach their work to the ship.",
        ),
      ],
      actionPrompt: local(`${sceneID}-action`, "Carry the appointment across the ocean"),
    },
    narrationCueIDs: [],
    interaction,
    completionEffects: [],
    checkpoint: "continuous",
  };
  const mechanism = local(
    `${sceneID}-mechanism-focus`,
    "Steam power, coal capacity, machinery watches and mail offices turn a crossing into a repeatable appointment.",
  );
  const scene = technicalScene({
    sceneID,
    accessibilityID,
    mechanism,
    layers: [
      technicalLayer(sceneID, "background", 0, [], { depth: 0.08, parallaxFactor: 0.02 }),
      technicalLayer(sceneID, "route-system", 1, ["idle", "tracing", "completed"], {
        depth: 0.56,
        focusResponse: 0.8,
      }),
      technicalLayer(sceneID, "foreground", 2, [], { depth: 0.92, parallaxFactor: 0.08 }),
    ],
    interactionTargets: [{
      interactionTargetID: "trace-ocean-route-target",
      layerID: "route-system",
      hitRegion: targetRegion(0.25, 0.4, 0.5, 0.24),
      accessibilityElementID: "trace-ocean-route",
    }],
    interactionVisualBinding: {
      grammar: "trace",
      configuration: {
        interactionID: interaction.id,
        interactionTargetID: "trace-ocean-route-target",
        layerID: "route-system",
        idleVariantID: "idle",
        tracingVariantID: "tracing",
        completedVariantID: "completed",
      },
    },
    atmosphere: {
      kind: "mist",
      density: 0.14,
      velocity: { dx: 0.08, dy: -0.01 },
      deterministicSeed: 19910414,
    },
  });
  const controls = [{
    id: "trace-ocean-route",
    role: "adjustable",
    label: local(`${sceneID}-route-label`, "The North Atlantic appointment"),
    hint: local(`${sceneID}-route-hint`, "Advance through power, coal, watches and connected mail."),
    actions: [action("increment", `${sceneID}-route-next`, "Advance the packet", {
      command: "trace-next",
    })],
  }];
  const contract = approvedContract(documents, "european-world");
  const arc = approvedArc(documents, "european-world", "european-world-arc-01");
  const chapter = {
    schemaVersion: version,
    id: "european-world",
    title: local("lab-european-world-title", contract.title),
    period: local("lab-european-world-period", contract.period),
    arcs: [projectArc(arc, [beat], "lab-european-world-arc-01")],
    completionEffects: [revealNodeEffect(
      "effect-european-world-twenty-states-agree-on-the-signal",
      "trace-common-protocols",
      "institution",
      "A common technical protocol carried through permanent international offices",
      { x: 0.58, y: 0.43 },
    )],
  };
  return { chapter, beat, scene, accessibility: makeAccessibility(beat, mechanism, controls) };
}

function validateExperienceLabCoverage(payload, experienceLab) {
  const issues = [];
  if (experienceLab.status !== "LOCKED_IMPLEMENTATION_SET") {
    issues.push("experience lab is not locked");
  }
  const grammarSet = new Set();
  const authoredEffectIDs = new Set(payload.chapters.flatMap((chapter) => [
    ...chapter.completionEffects.map(({ id }) => id),
    ...chapter.arcs.flatMap(({ beats }) => beats).flatMap((beat) =>
      (beat.interaction?.completionEffects ?? beat.completionEffects).map(({ id }) => id)),
  ]));
  for (const expected of experienceLab.scenes) {
    const isCanonicalMoreMouths =
      expected.nativeInteractionID === moreMouthsTechnicalLiveSlice.interactionID;
    const expectedBeatID = isCanonicalMoreMouths
      ? moreMouthsTechnicalLiveSlice.beatID
      : expected.beatID;
    const expectedSceneID = isCanonicalMoreMouths
      ? moreMouthsTechnicalLiveSlice.sceneID
      : expected.labSceneID;
    const chapter = payload.chapters.find(({ id }) => id === expected.contentID);
    const arc = chapter?.arcs.find(({ id }) => id === expected.arcID);
    const beat = arc?.beats.find(({ id }) => id === expectedBeatID);
    const scene = payload.scenes.find(({ id }) => id === expectedSceneID);
    if (!chapter || !arc || !beat || !scene) {
      issues.push(`${expectedSceneID}: chapter, arc, beat and scene are required`);
      continue;
    }
    if (beat.sceneID !== expectedSceneID
        || beat.interaction?.id !== expected.nativeInteractionID
        || beat.interaction?.grammar !== expected.grammar
        || beat.interaction?.completionEffects?.map(({ id }) => id).join(",")
          !== expected.worldEffectID) {
      issues.push(`${expectedSceneID}: locked interaction projection drifted`);
    }
    if (scene.interactionVisualBinding?.grammar !== expected.grammar
        || scene.accessibilityID !== beat.interaction?.accessibilityID) {
      issues.push(`${expectedSceneID}: visual/accessibility grammar drifted`);
    }
    for (const seedEffectID of expected.seedEffectIDs ?? []) {
      if (!authoredEffectIDs.has(seedEffectID)) {
        issues.push(`${expectedSceneID}: seed effect ${seedEffectID} is unavailable`);
      }
    }
    grammarSet.add(expected.grammar);
  }
  if (payload.chapters.map(({ id }) => id).join(",")
      !== "first-farmers,europe-holds-the-line,european-world") {
    issues.push("experience lab requires the exact three free chapter slices");
  }
  if ([...grammarSet].sort().join(",") !== [...experienceLab.requiredGrammars].sort().join(",")) {
    issues.push("experience lab does not cover all five locked grammars");
  }
  const firstFarmers = payload.chapters.find(({ id }) => id === "first-farmers");
  const firstFarmersBeats = firstFarmers?.arcs.flatMap(({ beats }) => beats) ?? [];
  const firstFarmersInteractions = firstFarmersBeats
    .flatMap(({ interaction }) => interaction ? [interaction] : []);
  if (firstFarmers?.arcs.length !== 3 || firstFarmersBeats.length !== 17) {
    issues.push("the live First Farmers projection must contain all three arcs and 17 beats");
  }
  if (firstFarmersInteractions.length !== 6) {
    issues.push("the live First Farmers projection must contain all six principal interactions");
  }
  for (const beat of firstFarmersBeats) {
    if (!payload.scenes.some(({ id }) => id === beat.sceneID)) {
      issues.push(`${beat.id}: referenced scene ${beat.sceneID} is unavailable`);
    }
  }
  const interactions = payload.chapters.flatMap(({ arcs }) => arcs)
    .flatMap(({ beats }) => beats)
    .flatMap(({ interaction }) => interaction ? [interaction] : []);
  if (interactions.length !== 8) {
    issues.push("the full-chapter live fixture must contain six First Farmers interactions and two supporting lab interactions");
  }
  if (issues.length) throw new Error(issues.join("\n"));
}

function buildPayload(source, documents, experienceLab, responsiveAudioCandidates) {
  const sourceChapter = source.chapters.find(({ id }) => id === "first-farmers");
  const sourceBeats = sourceChapter?.arcs.flatMap(({ beats }) => beats) ?? [];
  const harvestSourceBeat = sourceBeats.find(({ id }) =>
    id === "beat-first-farmers-harvest-allocation");
  const harvestSourceScene = source.scenes.find(({ id }) => id === "harvest-allocation-option-1");
  if (!sourceChapter || sourceChapter.arcs.length !== 3 || sourceBeats.length !== 17
      || !harvestSourceBeat || !harvestSourceScene) {
    throw new Error("The authored First Farmers chapter source is incomplete");
  }

  const harvestBeat = structuredClone(harvestSourceBeat);
  const harvestSceneID = "lab-first-farmers-harvest-allocation";
  harvestBeat.sceneID = harvestSceneID;
  harvestBeat.narrationCueIDs = [];
  harvestBeat.interaction.accessibilityID = "accessibility-lab-first-farmers-harvest-allocation";
  const harvestScene = rewriteAuthoredSceneAssets(structuredClone(harvestSourceScene), harvestSceneID);
  harvestScene.accessibilityID = harvestBeat.interaction.accessibilityID;
  const harvestAccessibility = structuredClone(source.accessibility.find(
    ({ id }) => id === harvestSourceBeat.interaction.accessibilityID,
  ));
  if (!harvestAccessibility) throw new Error("Harvest accessibility source is missing");
  harvestAccessibility.id = harvestBeat.interaction.accessibilityID;

  const assemble = makeAssembleProjection(source);
  const transform = makeTransformProjection(source);
  const firstFarmers = structuredClone(sourceChapter);
  const beatSubstitutions = new Map([
    ["beat-first-farmers-harvest-allocation", harvestBeat],
    ["beat-first-farmers-raise-longhouse", assemble.beat],
    ["beat-first-farmers-more-mouths", transform.beat],
  ]);
  firstFarmers.arcs = firstFarmers.arcs.map((arc) => ({
    ...arc,
    beats: arc.beats.map((sourceBeat) => {
      const beat = structuredClone(beatSubstitutions.get(sourceBeat.id) ?? sourceBeat);
      // The live fixture deliberately excludes the still-unapproved narrator
      // attempts. Responsive authored-state audio remains active for every
      // principal interaction.
      beat.narrationCueIDs = [];
      return beat;
    }),
  }));
  // The authored draft carries a provisional convenience mutation that is
  // intentionally outside the approved WorldEffect ledger. The six approved
  // interaction effects already carry the complete chapter causal state.
  firstFarmers.completionEffects = [];

  const replacedSceneIDs = new Set([
    "harvest-allocation-option-1",
    "scene-first-farmers-longhouse-assembly",
    "scene-first-farmers-settlement-growth",
  ]);
  const chapterScenesByID = new Map(
    source.scenes
      .filter(({ id }) => !replacedSceneIDs.has(id))
      .map((scene) => {
        const projection = rewriteAuthoredSceneAssets(structuredClone(scene), scene.id);
        return [projection.id, projection];
      }),
  );
  for (const scene of [harvestScene, assemble.scene, transform.scene]) {
    chapterScenesByID.set(scene.id, scene);
  }
  const chapterScenes = firstFarmers.arcs
    .flatMap(({ beats }) => beats)
    .map((beat) => chapterScenesByID.get(beat.sceneID));
  if (chapterScenes.some((scene) => !scene) || new Set(chapterScenes.map(({ id }) => id)).size !== 17) {
    throw new Error("The live First Farmers chapter does not project exactly one scene per beat");
  }

  const replacedAccessibilityIDs = new Set([
    harvestSourceBeat.interaction.accessibilityID,
    sourceBeats.find(({ id }) => id === "beat-first-farmers-raise-longhouse")
      ?.interaction?.accessibilityID,
    sourceBeats.find(({ id }) => id === "beat-first-farmers-more-mouths")
      ?.interaction?.accessibilityID,
  ]);
  const chapterAccessibilityByID = new Map(
    source.accessibility
      .filter(({ id }) => !replacedAccessibilityIDs.has(id))
      .map((accessibility) => [accessibility.id, structuredClone(accessibility)]),
  );
  for (const accessibility of [harvestAccessibility, assemble.accessibility, transform.accessibility]) {
    chapterAccessibilityByID.set(accessibility.id, accessibility);
  }
  const chapterAccessibility = chapterScenes.map((scene) =>
    chapterAccessibilityByID.get(scene.accessibilityID));
  if (chapterAccessibility.some((accessibility) => !accessibility)) {
    throw new Error("The live First Farmers chapter is missing scene accessibility");
  }

  const pressure = makePressureProjection(documents);
  const trace = makeTraceProjection(documents);
  const harvestParallaxProof = makeHarvestParallaxProof();
  const firstFarmersAudio = projectFirstFarmersResponsiveAudio(
    source,
    firstFarmers,
    responsiveAudioCandidates,
  );
  const supportingInteractiveRecords = [
    { chapterID: "europe-holds-the-line", arcID: "europe-holds-the-line-arc-01", beat: pressure.beat, sceneID: pressure.scene.id },
    { chapterID: "european-world", arcID: "european-world-arc-01", beat: trace.beat, sceneID: trace.scene.id },
  ];
  const supportingAudio = supportingInteractiveRecords.map(
    ({ chapterID, arcID, beat, sceneID }) =>
    makeResponsiveAudio(chapterID, arcID, beat, sceneID));
  const worldSeed = structuredClone(source.worldSeed);
  worldSeed.nodes.push(
    {
      id: "bristol-packet-office",
      kind: "institution",
      form: "A hidden packet office on the British shore",
      position: { x: 0.38, y: 0.48 },
      attributes: [],
    },
    {
      id: "new-york-packet-office",
      kind: "institution",
      form: "A hidden receiving office beyond the Atlantic",
      position: { x: 0.69, y: 0.48 },
      attributes: [],
    },
  );

  const payload = {
    schemaVersion: version,
    packageID: verticalSliceDevelopmentIdentity.packageID,
    worldSeed,
    chapters: [firstFarmers, pressure.chapter, trace.chapter],
    scenes: [
      ...chapterScenes,
      pressure.scene,
      trace.scene,
      harvestParallaxProof.scene,
    ],
    audioTimelines: [
      ...firstFarmersAudio.timelines,
      ...supportingAudio.flatMap(({ timelines }) => timelines),
    ],
    responsiveAudioPrograms: [
      ...firstFarmersAudio.programs,
      ...supportingAudio.map(({ program }) => program),
    ],
    accessibility: [
      ...chapterAccessibility,
      pressure.accessibility,
      trace.accessibility,
      harvestParallaxProof.accessibility,
    ],
  };
  validateExperienceLabCoverage(payload, experienceLab);
  if (localizedEnglish(firstFarmers.title) !== "The First Farmers"
      || localizedEnglish(firstFarmers.arcs[0].title) !== "The River Before the Fields"
      || localizedEnglish(firstFarmers.arcs[1].title) !== "The Harvest Had to Last"
      || localizedEnglish(firstFarmers.arcs[2].title) !== "The House Outlives Its Builders"
      || localizedEnglish(pressure.chapter.title) !== "The Frontiers Hold"
      || localizedEnglish(trace.chapter.title) !== "The European World") {
    throw new Error("Experience-lab editorial contracts drifted before fixture projection");
  }
  return payload;
}

async function launchConfiguration() {
  const [product, catalog, delivery] = await Promise.all([
    readFile(path.join(nativeRoot, "product.json"), "utf8").then(JSON.parse),
    readFile(path.join(blueprintRoot, "chapter-catalog.json"), "utf8").then(JSON.parse),
    readFile(path.join(blueprintRoot, "delivery-plan.json"), "utf8").then(JSON.parse),
  ]);
  return { product, catalog, delivery };
}

async function main() {
  for (const target of [sourceRoot, path.dirname(packageRoot), backstageRoot]) {
    await rm(target, { recursive: true, force: true });
  }
  for (const target of [trustReceiptPath, lineagePath]) {
    await rm(target, { force: true });
  }
  await mkdir(path.join(sourceRoot, "chapters"), { recursive: true });
  const renderedPaths = await renderAssets();

  const [
    sourcePayload,
    blueprint,
    experienceLab,
    responsiveAudioCandidates,
  ] = await Promise.all([
    readFile(sourcePayloadPath, "utf8").then(JSON.parse),
    readBlueprintProjectionDocuments(blueprintRoot),
    readFile(experienceLabPath, "utf8").then(JSON.parse),
    loadFirstFarmersResponsiveAudioCandidates(),
  ]);
  const payload = buildPayload(
    sourcePayload,
    blueprint,
    experienceLab,
    responsiveAudioCandidates,
  );
  const responsiveAudioProjection =
    requireRepresentativeFirstFarmersResponsiveAudio(payload);
  await removeUnreferencedRenderedAssets(payload, renderedPaths);
  await installFirstFarmersResponsiveAudioCandidates(
    responsiveAudioCandidates,
  );
  const firstFarmersProjection = payload.chapters.find(({ id }) => id === "first-farmers");
  const firstFarmersProjectedBeats = firstFarmersProjection.arcs.flatMap(({ beats }) => beats);
  const payloadPath = path.join(
    sourceRoot,
    "chapters",
    "vertical-slice-development-v1.json",
  );
  const payloadBytes = Buffer.from(`${JSON.stringify(payload, null, 2)}\n`, "utf8");
  await writeFile(payloadPath, payloadBytes);

  const evidence = validateBlueprintProjection(payload, blueprint, {
    scope: "VERTICAL_SLICE",
    payloadBytes,
  });
  const authority = createDevelopmentProjectionAuthority(evidence);
  await writeJSON(authorityPath, authority);

  const result = await compileDevelopmentVerticalSlice(
    sourceRoot,
    packageRoot,
    {
      blueprintRoot,
      launchConfiguration: await launchConfiguration(),
      projectionAuthorityPath: authorityPath,
      packageVersion: version,
      minimumRuntime: version,
      maximumInstalledBytes: 750_000_000,
    },
  );
  await writeJSON(trustReceiptPath, result.trustReceipt);

  const compiledFiles = await Promise.all(result.manifest.files.map(async ({ path: file }) => {
    const fullPath = path.join(packageRoot, ...file.split("/"));
    const info = await stat(fullPath);
    return { path: file, bytes: info.size, sha256: sha256(await readFile(fullPath)) };
  }));
  await writeJSON(lineagePath, {
    schemaVersion: 1,
    status: "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_FIXTURE",
    authorityShape:
      "FULL_FIRST_FARMERS_LIVE_TEST_PLUS_FIVE_GRAMMAR_LAB_WITH_UNREFERENCED_V26_PARTIAL_PASS_PROOF",
    chapterIDs: payload.chapters.map(({ id }) => id),
    fullChapterProjection: {
      contentID: "first-farmers",
      arcCount: firstFarmersProjection.arcs.length,
      beatCount: firstFarmersProjectedBeats.length,
      interactionCount: firstFarmersProjectedBeats
        .filter(({ interaction }) => interaction).length,
      sceneCount: firstFarmersProjectedBeats.length,
      accessibilityCount: firstFarmersProjectedBeats.length,
      narrationState: "EXCLUDED_PENDING_EDITOR_APPROVAL",
    },
    labSceneIDs: experienceLab.scenes.map(({ labSceneID }) => labSceneID),
    interactionIDs: experienceLab.scenes.map(({ nativeInteractionID }) => nativeInteractionID),
    requiredGrammars: experienceLab.requiredGrammars,
    incrementalCostNOK: 0,
    trustDomain: verticalSliceDevelopmentIdentity.trustDomain,
    packageID: verticalSliceDevelopmentIdentity.packageID,
    keyID: verticalSliceDevelopmentIdentity.keyID,
    projectionAuthorityKind:
      verticalSliceDevelopmentIdentity.projectionAuthorityKind,
    projectionAuthorityStatus:
      verticalSliceDevelopmentIdentity.projectionAuthorityStatus,
    projectionAuthority: verticalSliceDevelopmentIdentity.projectionAuthority,
    shippingState: verticalSliceDevelopmentIdentity.shippingState,
    visualSources: await Promise.all(
      Object.entries(visualSources).map(async ([assetStemID, file]) => ({
        sceneID: assetStemID === moreMouthsTechnicalLiveSlice.assetStemID
          ? moreMouthsTechnicalLiveSlice.sceneID
          : assetStemID,
        assetStemID,
        ...await fileRecord(file),
      })),
    ),
    visualSourceStatus: "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_INPUT",
    moreMouthsTechnicalLiveSlice: {
      status: "CODEX_PROVISIONAL_NON_SHIPPING_CAUSAL_STATE_PROOF",
      shippingState: "PROHIBITED",
      beatID: moreMouthsTechnicalLiveSlice.beatID,
      sceneID: moreMouthsTechnicalLiveSlice.sceneID,
      accessibilityID: moreMouthsTechnicalLiveSlice.accessibilityID,
      interactionID: moreMouthsTechnicalLiveSlice.interactionID,
      technicalAssetStemID: moreMouthsTechnicalLiveSlice.assetStemID,
      transparentOcclusionPlate: {
        packageAssetPath: moreMouthsTechnicalLiveSlice.transparentAssetPath,
        ...await fileRecord(path.join(
          sourceRoot,
          ...moreMouthsTechnicalLiveSlice.transparentAssetPath.split("/"),
        )),
      },
      transparentReduceMotionForeground: {
        packageAssetPath:
          moreMouthsTechnicalLiveSlice.transparentReduceMotionAssetPath,
        ...await fileRecord(path.join(
          sourceRoot,
          ...moreMouthsTechnicalLiveSlice.transparentReduceMotionAssetPath
            .split("/"),
        )),
      },
      stageMasks: await Promise.all(
        moreMouthsTechnicalLiveSlice.stageMasks.map(async (stage) => ({
          stageID: stage.stageID,
          pixelBounds: stage.pixelBounds,
          packageAssetPath: stage.assetPath,
          ...await fileRecord(path.join(sourceRoot, ...stage.assetPath.split("/"))),
        })),
      ),
      statePurpose:
        "VERIFY_VISIBLE_ORDERED_TRANSFORM_RESPONSE_AND_PERSISTENCE_ON_DEVICE",
      productionArtAuthority: "NONE",
      claimsExcluded: [
        "production art",
        "historical visual finish",
        "artistic approval",
        "shipping asset approval",
      ],
    },
    runtimeVisualProof: {
      sceneID: harvestProofSceneID,
      status: "CODEX_PROVISIONAL_NON_SHIPPING_V26_PARTIAL_PASS_RUNTIME_PROOF",
      shippingState: "PROHIBITED",
      source: await fileRecord(harvestProofInputs.source),
      diagnosticUnderlay: await fileRecord(harvestProofInputs.diagnosticUnderlay),
      alphaMasksBackToFront: await Promise.all([
        ["people", harvestProofInputs.peopleAlpha],
        ["grain", harvestProofInputs.grainAlpha],
        ["foreground", harvestProofInputs.foregroundAlpha],
      ].map(async ([layerID, file]) => ({ layerID, ...await fileRecord(file) }))),
      reduceMotionStatic: await fileRecord(harvestProofInputs.reduceMotionStatic),
      frozenReview: await fileRecord(harvestProofInputs.review),
      segmentationReceipt: await fileRecord(harvestProofInputs.segmentationReceipt),
      packageAssetPaths: harvestProofAssetPaths,
      passedScope: ["people", "grain", "foreground"],
      excludedLayers: [
        "winter-food-vessel",
        "protected-reserve-bin",
        "spring-seed-store",
        "settlement-shelter",
        "allocation-cloth",
      ],
    },
    audioSource: await fileRecord(audioSource),
    audioRights: "PROJECT_OWNED_PROCEDURAL_AUDIO",
    audioDerivations: supportingResponsiveAudioDerivations.map(({ sceneID }) => ({
      sceneID,
      path: `source/audio/${sceneID}-soundscape.m4a`,
    })),
    responsiveAudioCandidate: {
      status: responsiveAudioCandidates.receipt.status,
      shippingState: responsiveAudioCandidates.receipt.shippingState,
      trustDomain: responsiveAudioCandidates.receipt.trustDomain,
      receipt: await fileRecord(firstFarmersResponsiveAudioReceiptPath),
      receiptSHA256: responsiveAudioCandidates.receiptSHA256,
      candidateAssetCount: responsiveAudioProjection.assetPaths.length,
      candidateEncodedBytes: responsiveAudioCandidates.encodedBytes,
      programIDs: responsiveAudioProjection.programIDs,
      timelineCount: responsiveAudioProjection.timelineIDs.length,
      decodedBufferEstimate:
        responsiveAudioProjection.decodedBufferEstimate,
      audioApproval: "OPEN",
      editorApproval: "OPEN",
      physicalIPhonePlayback: "OPEN",
      physicalIPhoneEnergy: "OPEN",
      shippingApproval: "PROHIBITED",
      fixtureUse: "NON_SHIPPING_LIVE_TEST_ONLY",
    },
    sourcePayload: await fileRecord(sourcePayloadPath),
    experienceLab: await fileRecord(experienceLabPath),
    payloadSHA256: sha256(payloadBytes),
    manifestDigest: result.manifest.manifestDigest,
    compiledFiles,
    claimsExcluded: [
      "editor approval",
      "shipping approval",
      "production visual approval",
      "production audio approval",
      "chapter completion",
      "physical-device approval",
      "clean-plate approval",
      "complete layer DAG",
      "state-variant approval",
      "production-master approval",
      "complete-scene approval",
      "artistic approval",
      "shipping asset approval",
    ],
  });

  process.stdout.write(
    `Built signed non-shipping runtime fixture ${result.manifest.manifestDigest}.\n`,
  );
}

if (process.argv[1]
    && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error?.stack ?? error);
    process.exitCode = 1;
  });
}
