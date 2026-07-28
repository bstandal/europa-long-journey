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
const chapter01ReviewMatrixPath = path.join(
  fixtureRoot,
  "chapter-01-review-matrix.json",
);
const chapter01ReviewNarrationManifestPath = path.join(
  nativeRoot,
  "audio/narration/review/chapter-01/manifest.json",
);
const chapter01ReviewTransitionManifestPath = path.join(
  nativeRoot,
  "audio/score-soundscape/chapter-01-review-transitions-v1/manifest.json",
);
const version = Object.freeze({ major: 1, minor: 0, patch: 0 });
const chapter01ReviewMasterCanvas = Object.freeze({
  width: 1179,
  height: 2556,
});
const chapter01ReviewOverscanFraction = 0.15;
const chapter01ReviewBaselineSourceRect = Object.freeze({
  x: chapter01ReviewOverscanFraction,
  y: chapter01ReviewOverscanFraction,
  width: 1 - chapter01ReviewOverscanFraction * 2,
  height: 1 - chapter01ReviewOverscanFraction * 2,
});
const chapter01ReviewLargestSourceRect = Object.freeze(
  centeredPortraitSourceRect(
    chapter01ReviewMasterCanvas,
    { widthPoints: 430, heightPoints: 932 },
    1 - chapter01ReviewOverscanFraction * 2,
  ),
);
const chapter01ReviewSemanticAssetSuffixes = Object.freeze([
  "background",
  "midground",
  "foreground",
  "mechanism-light",
]);
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
const supportingVisualSources = Object.freeze({
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

function centeredPortraitSourceRect(canvas, viewport, width) {
  const height = canvas.width * width * viewport.heightPoints
    / (canvas.height * viewport.widthPoints);
  requireCondition(
    width > 0 && width <= 1 && height > 0 && height <= 1,
    "Portrait crop exceeds its authored master canvas",
  );
  return {
    x: (1 - width) / 2,
    y: (1 - height) / 2,
    width,
    height,
  };
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

export function validateChapter01ReviewMatrix(matrix) {
  requireCondition(
    matrix?.schemaVersion === 1
      && matrix.matrixID === "chapter-01-review-matrix-v1"
      && matrix.milestone === "CHAPTER_01_REVIEW_READY"
      && matrix.status === "NON_SHIPPING_REVIEW"
      && matrix.shippingAllowed === false
      && matrix.chapterID === "first-farmers"
      && matrix.publicContentSchemaMutation === false
      && isSafePackagePath(matrix.sourceDraft?.path)
      && isLowercaseSHA256(matrix.sourceDraft?.sha256),
    "Chapter 01 review matrix authority drifted",
  );
  requireCondition(
    matrix.portraitContract?.orientation === "portrait"
      && matrix.portraitContract?.overscanRequired === true
      && matrix.portraitContract?.masterCanvasPixels?.width
        === chapter01ReviewMasterCanvas.width
      && matrix.portraitContract?.masterCanvasPixels?.height
        === chapter01ReviewMasterCanvas.height
      && matrix.portraitContract?.authoredOverscanFraction
        === chapter01ReviewOverscanFraction
      && JSON.stringify(matrix.portraitContract?.baselineSourceRect)
        === JSON.stringify(chapter01ReviewBaselineSourceRect)
      && matrix.portraitContract?.minimumEffectiveTargetPoints === 44
      && matrix.portraitContract?.reduceMotionUsesStaticConsequenceComposition
        === true
      && JSON.stringify(matrix.portraitContract?.layers) === JSON.stringify([
        "background",
        "inhabited-material-midground",
        "foreground",
        "mechanism-light",
      ])
      && matrix.portraitContract?.transparentOverlayLayers?.join(",")
        === "inhabited-material-midground,foreground,mechanism-light",
    "Chapter 01 review matrix portrait contract drifted",
  );
  requireCondition(
    Array.isArray(matrix.worlds) && matrix.worlds.length === 6
      && Array.isArray(matrix.beats) && matrix.beats.length === 17,
    "Chapter 01 review matrix must contain six worlds and seventeen beats",
  );

  const worldsByID = new Map();
  const sourcePaths = new Set();
  for (const world of matrix.worlds) {
    requireCondition(
      typeof world?.id === "string"
        && world.id.startsWith("review-world-")
        && !worldsByID.has(world.id)
        && isSafePackagePath(world.sourceAsset)
        && !world.sourceAsset.startsWith("content/public/")
        && typeof world.sourceStatus === "string"
        && Array.isArray(world.interactionStateIDs)
        && world.interactionStateIDs.length > 0
        && typeof world.reduceMotion?.compositionID === "string"
        && Array.isArray(world.reduceMotion?.consequenceStateIDs)
        && !sourcePaths.has(world.sourceAsset),
      `${world?.id ?? "review-world"}: invalid review world`,
    );
    const resolvedSource = path.resolve(repositoryRoot, world.sourceAsset);
    requireCondition(
      !path.relative(repositoryRoot, resolvedSource).startsWith(".."),
      `${world.id}: source asset escapes the repository`,
    );
    sourcePaths.add(world.sourceAsset);
    worldsByID.set(world.id, { ...world, resolvedSource });
  }

  const expectedWorldBeatCounts = new Map([
    ["review-world-iron-gates-danube", 5],
    ["review-world-aegean-crossing", 1],
    ["review-world-thessaly-first-field", 2],
    ["review-world-harvest-store", 2],
    ["review-world-longhouse-settlement", 5],
    ["review-world-european-farming-belt", 2],
  ]);
  requireCondition(
    [...worldsByID.keys()].every((worldID) =>
      expectedWorldBeatCounts.has(worldID))
      && worldsByID.size === expectedWorldBeatCounts.size,
    "Chapter 01 review world IDs drifted",
  );

  const beatsByID = new Map();
  const worldIDBySceneID = new Map();
  const worldBeatCounts = new Map();
  for (const beat of matrix.beats) {
    const world = worldsByID.get(beat?.worldID);
    requireCondition(
      typeof beat?.beatID === "string"
        && typeof beat?.sceneID === "string"
        && world !== undefined
        && typeof beat.cameraVariant === "string"
        && typeof beat.lightVariant === "string"
        && typeof beat.stateVariant === "string"
        && world.interactionStateIDs.includes(beat.stateVariant)
        && !beatsByID.has(beat.beatID)
        && !worldIDBySceneID.has(beat.sceneID),
      `${beat?.beatID ?? "review-beat"}: invalid review beat binding`,
    );
    beatsByID.set(beat.beatID, beat);
    worldIDBySceneID.set(beat.sceneID, beat.worldID);
    worldBeatCounts.set(
      beat.worldID,
      (worldBeatCounts.get(beat.worldID) ?? 0) + 1,
    );
  }
  requireCondition(
    [...expectedWorldBeatCounts].every(([worldID, count]) =>
      worldBeatCounts.get(worldID) === count),
    "Chapter 01 review world beat distribution drifted",
  );
  return {
    worldsByID,
    beatsByID,
    worldIDBySceneID,
    portraitContract: matrix.portraitContract,
    sourceDraftSHA256: matrix.sourceDraft?.sha256,
  };
}

export function validateChapter01ReviewNarrationManifest(manifest) {
  requireCondition(
    manifest?.schemaVersion === 1
      && manifest.manifestID === "chapter-01-review-narration-v1"
      && manifest.status === "NON_SHIPPING_REVIEW"
      && manifest.shippingState === "PROHIBITED"
      && manifest.milestone === "CHAPTER_01_REVIEW_READY"
      && manifest.chapterID === "first-farmers"
      && manifest.locale === "en"
      && manifest.sampleRate === 48_000
      && manifest.cueCount === 37
      && manifest.engine === "Qwen3-TTS Base"
      && manifest.candidateID === "voice-candidate-05"
      && manifest.runtimeGenerationPermitted === false
      && manifest.shippingUsePermitted === false
      && isLowercaseSHA256(manifest.manuscriptDraftSHA256)
      && isLowercaseSHA256(manifest.combinedBindingSHA256)
      && Array.isArray(manifest.cues)
      && manifest.cues.length === 37,
    "Chapter 01 review narration manifest authority drifted",
  );
  const byCueID = new Map();
  const segmentIDs = new Set();
  const repositoryPaths = new Set();
  for (const cue of manifest.cues) {
    requireCondition(
      typeof cue?.cueID === "string"
        && cue.cueID.startsWith("narration-")
        && typeof cue.manuscriptSegmentID === "string"
        && cue.cueID === `narration-${cue.manuscriptSegmentID}`
        && isLowercaseSHA256(cue.manuscriptSegmentSHA256)
        && isSafePackagePath(cue.repositoryPath)
        && cue.repositoryPath.startsWith(
          "native/audio/narration/review/chapter-01/cues/",
        )
        && cue.repositoryPath.endsWith(".m4a")
        && cue.sampleRate === 48_000
        && Number.isSafeInteger(cue.durationSamples)
        && cue.durationSamples > 0
        && Number.isSafeInteger(cue.bytes)
        && cue.bytes > 0
        && isLowercaseSHA256(cue.sha256)
        && !byCueID.has(cue.cueID)
        && !segmentIDs.has(cue.manuscriptSegmentID)
        && !repositoryPaths.has(cue.repositoryPath),
      `${cue?.cueID ?? "review-narration"}: invalid review narration cue`,
    );
    byCueID.set(cue.cueID, cue);
    segmentIDs.add(cue.manuscriptSegmentID);
    repositoryPaths.add(cue.repositoryPath);
  }
  return { byCueID };
}

async function loadChapter01ReviewNarration() {
  const manifestBytes = await readFile(chapter01ReviewNarrationManifestPath);
  let manifest;
  try {
    manifest = JSON.parse(manifestBytes);
  } catch {
    throw new Error("Chapter 01 review narration manifest is not valid JSON");
  }
  const validated = validateChapter01ReviewNarrationManifest(manifest);
  for (const cue of validated.byCueID.values()) {
    const file = path.resolve(repositoryRoot, cue.repositoryPath);
    requireCondition(
      !path.relative(repositoryRoot, file).startsWith(".."),
      `${cue.cueID}: narration path escapes the repository`,
    );
    const bytes = await readFile(file).catch(() => null);
    requireCondition(
      bytes !== null
        && bytes.byteLength === cue.bytes
        && sha256(bytes) === cue.sha256,
      `${cue.cueID}: review narration asset is absent or changed`,
    );
  }
  return {
    manifest,
    manifestBytes,
    manifestSHA256: sha256(manifestBytes),
    byCueID: validated.byCueID,
  };
}

export function validateChapter01ReviewTransitionManifest(manifest) {
  requireCondition(
    manifest?.schemaVersion === 1
      && manifest.manifestID === "chapter-01-review-transitions-v1"
      && manifest.status === "NON_SHIPPING_REVIEW"
      && manifest.shippingState === "PROHIBITED"
      && manifest.milestone === "CHAPTER_01_REVIEW_READY"
      && manifest.chapterID === "first-farmers"
      && manifest.sampleRate === 48_000
      && manifest.channelCount === 2
      && manifest.transitionCount === 3
      && manifest.derivedWithoutNewComposition === true
      && manifest.runtimeGenerationPermitted === false
      && manifest.shippingUsePermitted === false
      && Array.isArray(manifest.transitions)
      && manifest.transitions.length === 3,
    "Chapter 01 review transition manifest authority drifted",
  );
  const expected = [
    ["transition-aegean-thessaly-v1", "aegean-crossing", "thessaly-first-field"],
    ["transition-store-iron-gates-v1", "harvest-store", "iron-gates-danube"],
    ["transition-farming-belt-steppe-v1", "european-farming-belt", "steppe-transition"],
  ];
  const byTransitionID = new Map();
  for (const [index, transition] of manifest.transitions.entries()) {
    const [transitionID, fromWorld, toWorld] = expected[index];
    const audio = transition?.audio;
    requireCondition(
      transition?.transitionID === transitionID
        && transition.fromWorld === fromWorld
        && transition.toWorld === toWorld
        && transition.derivation?.newCompositionAdded === false
        && isSafePackagePath(audio?.path)
        && audio.path.startsWith(
          "native/audio/score-soundscape/chapter-01-review-transitions-v1/audio/",
        )
        && audio.path.endsWith(`/${transitionID}.m4a`)
        && audio.sampleRate === 48_000
        && audio.channelCount === 2
        && Number.isSafeInteger(audio.durationFrames)
        && audio.durationFrames > 0
        && Number.isSafeInteger(audio.bytes)
        && audio.bytes > 0
        && isLowercaseSHA256(audio.sha256)
        && !byTransitionID.has(transitionID),
      `${transitionID}: invalid Chapter 01 review transition`,
    );
    byTransitionID.set(transitionID, transition);
  }
  return { byTransitionID };
}

async function loadChapter01ReviewTransitions() {
  const manifestBytes = await readFile(chapter01ReviewTransitionManifestPath);
  let manifest;
  try {
    manifest = JSON.parse(manifestBytes);
  } catch {
    throw new Error("Chapter 01 review transition manifest is not valid JSON");
  }
  const validated = validateChapter01ReviewTransitionManifest(manifest);
  for (const transition of validated.byTransitionID.values()) {
    const file = path.resolve(repositoryRoot, transition.audio.path);
    requireCondition(
      !path.relative(repositoryRoot, file).startsWith(".."),
      `${transition.transitionID}: transition path escapes the repository`,
    );
    const bytes = await readFile(file).catch(() => null);
    requireCondition(
      bytes !== null
        && bytes.byteLength === transition.audio.bytes
        && sha256(bytes) === transition.audio.sha256,
      `${transition.transitionID}: review transition asset is absent or changed`,
    );
  }
  return {
    manifest,
    manifestBytes,
    manifestSHA256: sha256(manifestBytes),
    byTransitionID: validated.byTransitionID,
  };
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

function reviewNarrationPackagePath(cue) {
  return `audio/first-farmers/review-narration/${path.basename(cue.repositoryPath)}`;
}

async function installChapter01ReviewNarration(reviewNarration) {
  for (const cue of reviewNarration.byCueID.values()) {
    const source = path.resolve(repositoryRoot, cue.repositoryPath);
    const packagePath = reviewNarrationPackagePath(cue);
    const destination = path.join(sourceRoot, ...packagePath.split("/"));
    await mkdir(path.dirname(destination), { recursive: true });
    await copyFile(source, destination);
  }
}

function reviewTransitionPackagePath(transition) {
  return `audio/first-farmers/review-transitions/${path.basename(transition.audio.path)}`;
}

async function installChapter01ReviewTransitions(reviewTransitions) {
  for (const transition of reviewTransitions.byTransitionID.values()) {
    const source = path.resolve(repositoryRoot, transition.audio.path);
    const packagePath = reviewTransitionPackagePath(transition);
    const destination = path.join(sourceRoot, ...packagePath.split("/"));
    await mkdir(path.dirname(destination), { recursive: true });
    await copyFile(source, destination);
  }
}

async function renderRaster(source, destination, tailFilter) {
  const { width, height } = chapter01ReviewMasterCanvas;
  const common = `scale=${width}:${height}:force_original_aspect_ratio=increase,crop=${width}:${height}`;
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

function transparentRasterFilter(toneFilter, alphaExpression) {
  return `${toneFilter},format=rgba,geq=`
    + `r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='${alphaExpression}'`;
}

const midgroundAlphaExpression =
  "255*max(0,min(1,(Y-H*0.18)/(H*0.12)))"
  + "*max(0,min(1,(H*0.82-Y)/(H*0.12)))"
  + "*max(0,min(1,(X-W*0.06)/(W*0.12)))"
  + "*max(0,min(1,(W*0.94-X)/(W*0.12)))";
const foregroundAlphaExpression =
  "255*max(0,min(1,(Y-H*0.58)/(H*0.16)))";
const mechanismLightAlphaExpression =
  "256*max(0,min(1,1-(pow((X-W*0.52)/(W*0.24),2)"
  + "+pow((Y-H*0.58)/(H*0.18),2))))";
const interactionOverlayAlphaExpression =
  "255*max(0,min(1,1-(pow((X-W*0.5)/(W*0.34),2)"
  + "+pow((Y-H*0.62)/(H*0.28),2))))";

const chapter01ReviewRasterSpecifications = Object.freeze([
  [
    "background",
    "eq=contrast=0.9:brightness=-0.065:saturation=0.72,boxblur=2:1",
  ],
  [
    "midground",
    transparentRasterFilter(
      "eq=contrast=1.04:brightness=-0.005:saturation=0.94",
      midgroundAlphaExpression,
    ),
  ],
  [
    "foreground",
    transparentRasterFilter(
      "eq=contrast=1.1:brightness=-0.025:saturation=0.86",
      foregroundAlphaExpression,
    ),
  ],
  [
    "mechanism-light",
    transparentRasterFilter(
      "eq=contrast=1.13:brightness=0.045:saturation=1.02",
      mechanismLightAlphaExpression,
    ),
  ],
  [
    "interaction-overlay",
    transparentRasterFilter(
      "eq=contrast=1.08:brightness=0.01:saturation=0.98",
      interactionOverlayAlphaExpression,
    ),
  ],
  [
    "transparent",
    transparentRasterFilter(
      "eq=contrast=1:brightness=0:saturation=1",
      "0",
    ),
  ],
  [
    "state-before",
    transparentRasterFilter(
      "eq=contrast=0.9:brightness=-0.14:saturation=0.52",
      midgroundAlphaExpression,
    ),
  ],
  [
    "state-active",
    transparentRasterFilter(
      "eq=contrast=1.06:brightness=0.015:saturation=0.98",
      midgroundAlphaExpression,
    ),
  ],
  [
    "state-completed",
    transparentRasterFilter(
      "eq=contrast=1.12:brightness=0.035:saturation=1.08",
      midgroundAlphaExpression,
    ),
  ],
  [
    "reduce-motion-state-before",
    "eq=contrast=0.88:brightness=-0.1:saturation=0.58",
  ],
  [
    "reduce-motion-state-active",
    "eq=contrast=1.02:brightness=-0.025:saturation=0.86",
  ],
  [
    "reduce-motion-state-completed",
    "eq=contrast=1.08:brightness=0.01:saturation=0.96",
  ],
  [
    "reduce-motion-foreground",
    transparentRasterFilter(
      "eq=contrast=1.06:brightness=-0.035:saturation=0.8",
      foregroundAlphaExpression,
    ),
  ],
  [
    "reduce-motion-mechanism-light",
    transparentRasterFilter(
      "eq=contrast=1.09:brightness=0.025:saturation=0.9",
      mechanismLightAlphaExpression,
    ),
  ],
]);

const supportingRasterSpecifications = Object.freeze([
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
]);

async function renderAlphaMask(source, destination) {
  await execFileAsync("ffmpeg", [
    "-hide_banner",
    "-loglevel", "error",
    "-y",
    "-i", source,
    "-vf", "alphaextract,format=gray",
    "-frames:v", "1",
    "-map_metadata", "-1",
    destination,
  ]);
}

async function renderTechnicalMask(destination, pixelBounds) {
  const scaleX = chapter01ReviewMasterCanvas.width / 393;
  const scaleY = chapter01ReviewMasterCanvas.height / 852;
  const x = Math.round(pixelBounds.x * scaleX);
  const y = Math.round(pixelBounds.y * scaleY);
  const width = Math.round(pixelBounds.width * scaleX);
  const height = Math.round(pixelBounds.height * scaleY);
  await execFileAsync("ffmpeg", [
    "-hide_banner",
    "-loglevel", "error",
    "-y",
    "-f", "lavfi",
    "-i", `color=c=black:s=${chapter01ReviewMasterCanvas.width}x${chapter01ReviewMasterCanvas.height}:r=1`,
    "-vf",
    `drawbox=x=${x}:y=${y}:w=${width}:h=${height}:color=white:t=fill,gblur=sigma=12,format=gray`,
    "-frames:v", "1",
    "-map_metadata", "-1",
    destination,
  ]);
}

function fixtureVisualSources(reviewWorldIndex) {
  return Object.freeze({
    ...Object.fromEntries(
      [...reviewWorldIndex.worldsByID].map(([worldID, world]) => [
        worldID,
        world.resolvedSource,
      ]),
    ),
    ...supportingVisualSources,
  });
}

async function renderAssets(reviewWorldIndex, visualSources) {
  const assetRoot = path.join(sourceRoot, "assets");
  const audioRoot = path.join(sourceRoot, "audio");
  const renderedPaths = [];
  await mkdir(assetRoot, { recursive: true });
  await mkdir(audioRoot, { recursive: true });

  for (const [sceneID, source] of Object.entries(visualSources)) {
    const isReviewWorld = reviewWorldIndex.worldsByID.has(sceneID);
    const rasterSpecifications = isReviewWorld
      ? chapter01ReviewRasterSpecifications
      : supportingRasterSpecifications;
    for (const [suffix, filter] of rasterSpecifications) {
      const relative = `assets/${sceneID}-${suffix}.png`;
      await renderRaster(
        source,
        path.join(sourceRoot, ...relative.split("/")),
        filter,
      );
      renderedPaths.push(relative);
    }
    if (isReviewWorld) {
      for (const [sourceSuffix, maskSuffix] of [
        ["midground", "midground-alpha"],
        ["foreground", "foreground-alpha"],
        ["mechanism-light", "mechanism-light-alpha"],
        ["interaction-overlay", "interaction-overlay-alpha"],
        ["state-active", "state-alpha"],
      ]) {
        const relative = `assets/${sceneID}-${maskSuffix}.png`;
        await renderAlphaMask(
          path.join(assetRoot, `${sceneID}-${sourceSuffix}.png`),
          path.join(sourceRoot, ...relative.split("/")),
        );
        renderedPaths.push(relative);
      }
    }
  }

  const moreMouthsWorldID = reviewWorldIndex.worldIDBySceneID.get(
    moreMouthsTechnicalLiveSlice.sceneID,
  );
  const moreMouthsSource = visualSources[moreMouthsWorldID];
  requireCondition(
    moreMouthsSource !== undefined,
    "More Mouths review world source is unavailable",
  );
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

function pngHeader(bytes, label) {
  const signature = "89504e470d0a1a0a";
  requireCondition(
    bytes.length >= 26
      && bytes.subarray(0, 8).toString("hex") === signature
      && bytes.subarray(12, 16).toString("ascii") === "IHDR",
    `${label}: expected a PNG with an IHDR header`,
  );
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
    bitDepth: bytes[24],
    colorType: bytes[25],
  };
}

async function alphaRange(file) {
  const { stdout, stderr } = await execFileAsync("ffmpeg", [
    "-hide_banner",
    "-loglevel", "error",
    "-i", file,
    "-vf", "alphaextract,signalstats,metadata=print:file=-",
    "-frames:v", "1",
    "-f", "null",
    "-",
  ]);
  const metadata = `${stdout}\n${stderr}`;
  const minimum = Number(metadata.match(/lavfi\.signalstats\.YMIN=(\d+)/u)?.[1]);
  const maximum = Number(metadata.match(/lavfi\.signalstats\.YMAX=(\d+)/u)?.[1]);
  requireCondition(
    Number.isFinite(minimum) && Number.isFinite(maximum),
    `${path.basename(file)}: alpha range could not be measured`,
  );
  return { minimum, maximum };
}

export async function validateChapter01ReviewRasterAssets(
  reviewWorldIndex,
  { root = sourceRoot, requireFullDerivationSet = true } = {},
) {
  const durableSuffixes = [
    ...chapter01ReviewSemanticAssetSuffixes,
    "midground-alpha",
    "foreground-alpha",
    "mechanism-light-alpha",
  ];
  const requiredSuffixes = requireFullDerivationSet ? [
    ...chapter01ReviewRasterSpecifications.map(([suffix]) => suffix),
    ...durableSuffixes.slice(chapter01ReviewSemanticAssetSuffixes.length),
    "interaction-overlay-alpha",
    "state-alpha",
  ] : durableSuffixes;
  const worlds = [];
  for (const worldID of reviewWorldIndex.worldsByID.keys()) {
    const records = new Map();
    for (const suffix of requiredSuffixes) {
      const packageAssetPath = assetPath(worldID, suffix);
      const file = path.join(root, ...packageAssetPath.split("/"));
      const bytes = await readFile(file);
      const header = pngHeader(bytes, packageAssetPath);
      requireCondition(
        header.width === chapter01ReviewMasterCanvas.width
          && header.height === chapter01ReviewMasterCanvas.height,
        `${packageAssetPath}: ${header.width}x${header.height} does not match the declared ${chapter01ReviewMasterCanvas.width}x${chapter01ReviewMasterCanvas.height} review master`,
      );
      records.set(suffix, {
        suffix,
        packageAssetPath,
        bytes: bytes.byteLength,
        sha256: sha256(bytes),
        ...header,
      });
    }
    const semanticLayers = chapter01ReviewSemanticAssetSuffixes.map(
      (suffix) => records.get(suffix),
    );
    requireCondition(
      new Set(semanticLayers.map(({ sha256: digest }) => digest)).size
        === semanticLayers.length,
      `${worldID}: shared semantic layers collapsed to cloned raster bytes`,
    );
    requireCondition(
      new Set(["midground-alpha", "foreground-alpha", "mechanism-light-alpha"]
        .map((suffix) => records.get(suffix).sha256)).size === 3,
      `${worldID}: semantic layer masks collapsed to cloned raster bytes`,
    );
    const transparentSuffixes = requireFullDerivationSet
      ? [
        "midground",
        "foreground",
        "mechanism-light",
        "interaction-overlay",
        "state-before",
        "state-active",
        "state-completed",
        "transparent",
        "reduce-motion-foreground",
        "reduce-motion-mechanism-light",
      ]
      : ["midground", "foreground", "mechanism-light"];
    requireCondition(
      transparentSuffixes.every((suffix) => records.get(suffix).colorType === 6),
      `${worldID}: review overlays must be RGBA PNGs`,
    );
    for (const suffix of ["midground", "foreground", "mechanism-light"]) {
      const range = await alphaRange(path.join(
        root,
        ...records.get(suffix).packageAssetPath.split("/"),
      ));
      requireCondition(
        range.minimum === 0 && range.maximum === 255,
        `${worldID}/${suffix}: semantic overlay must contain transparent and opaque pixels`,
      );
      records.get(suffix).alphaRange = range;
    }
    if (requireFullDerivationSet) {
      requireCondition(
        new Set(["state-before", "state-active", "state-completed"]
          .map((suffix) => records.get(suffix).sha256)).size === 3,
        `${worldID}: review consequence states collapsed to cloned raster bytes`,
      );
      requireCondition(
        new Set(["reduce-motion-state-before", "reduce-motion-state-active",
          "reduce-motion-state-completed"]
          .map((suffix) => records.get(suffix).sha256)).size === 3,
        `${worldID}: Reduce Motion consequence plates collapsed to cloned raster bytes`,
      );
    }
    worlds.push({ worldID, semanticLayers });
  }
  return {
    masterCanvasPixels: { ...chapter01ReviewMasterCanvas },
    authoredOverscanFraction: chapter01ReviewOverscanFraction,
    baselineSourceRect: { ...chapter01ReviewBaselineSourceRect },
    worlds,
  };
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

function variantAssetSuffix(variantID) {
  if ([
    "available", "before", "broken", "empty", "exhausted", "idle",
    "resting", "scarce",
  ].includes(variantID)) {
    return "state-before";
  }
  if ([
    "active", "receiving", "reduced", "resisted", "resisting", "tracing",
  ].includes(variantID)) {
    return "state-active";
  }
  return "state-completed";
}

function variantAssetPath(sceneID, variantID) {
  return assetPath(sceneID, variantAssetSuffix(variantID));
}

function reviewLayerAssetSuffix(layer) {
  if (layer.stateVariants.length > 0) return "state-before";
  if (["far-landscape", "storm-sky"].includes(layer.id)) return "background";
  if (["inhabited-world", "settlement"].includes(layer.id)) return "midground";
  if (["foreground-occlusion", "foreground-occluders"].includes(layer.id)) {
    return "foreground";
  }
  if (layer.id === "mechanism-light") return "mechanism-light";
  if (layer.id === "hands-and-grain") return "interaction-overlay";
  return "transparent";
}

function reviewMasks(assetStemID, assetSuffix) {
  if (["state-before", "state-active", "state-completed"].includes(assetSuffix)) {
    return { alphaMaskAssetPath: assetPath(assetStemID, "state-alpha") };
  }
  if (["midground", "foreground", "mechanism-light", "interaction-overlay"]
    .includes(assetSuffix)) {
    const alphaMaskAssetPath = assetPath(assetStemID, `${assetSuffix}-alpha`);
    return assetSuffix === "mechanism-light"
      ? { alphaMaskAssetPath, lightMaskAssetPath: alphaMaskAssetPath }
      : { alphaMaskAssetPath };
  }
  return {};
}

function installReviewReduceMotionAssets(scene, assetStemID) {
  const staticStrata = scene.reduceMotionComposition.strata.filter(
    ({ kind }) => kind === "staticPlate",
  );
  requireCondition(
    staticStrata.length >= 1,
    `${scene.id}: Reduce Motion composition has no static underlay`,
  );
  staticStrata.forEach((stratum, index) => {
    if (index === 0) {
      stratum.assetPath = assetPath(assetStemID, "reduce-motion-state-before");
    } else {
      stratum.assetPath = assetPath(assetStemID, "transparent");
    }
  });
  const foregroundStratum = staticStrata.length > 1
    ? staticStrata.at(-1)
    : {
      id: "static-review-foreground",
      kind: "staticPlate",
      assetPath: assetPath(assetStemID, "reduce-motion-foreground"),
    };
  foregroundStratum.assetPath = assetPath(assetStemID, "reduce-motion-foreground");
  if (staticStrata.length === 1) {
    scene.reduceMotionComposition.strata.push(foregroundStratum);
  }
  scene.reduceMotionComposition.strata.push({
    id: "static-mechanism-light",
    kind: "staticPlate",
    assetPath: assetPath(assetStemID, "reduce-motion-mechanism-light"),
  });
}

function rewriteAuthoredSceneAssets(scene, sceneID, assetStemID) {
  scene.id = sceneID;
  scene.sceneCanvas.canvas = { ...chapter01ReviewMasterCanvas };
  scene.sceneCanvas.authoredOverscanFraction = chapter01ReviewOverscanFraction;
  for (const crop of scene.sceneCanvas.viewportCrops) {
    if (crop.id === "baseline-393x852") {
      crop.sourceRect = { ...chapter01ReviewBaselineSourceRect };
    } else if (crop.id === "largest-430x932") {
      crop.sourceRect = { ...chapter01ReviewLargestSourceRect };
    }
  }
  scene.reduceMotionComposition.canvas = { ...chapter01ReviewMasterCanvas };
  for (const crop of scene.reduceMotionComposition.viewportCrops) {
    if (crop.id === "baseline-393x852") {
      crop.sourceRect = { ...chapter01ReviewBaselineSourceRect };
    } else if (crop.id === "largest-430x932") {
      crop.sourceRect = { ...chapter01ReviewLargestSourceRect };
    }
  }
  for (const layer of scene.layers) {
    const assetSuffix = reviewLayerAssetSuffix(layer);
    layer.assetPath = assetPath(assetStemID, assetSuffix);
    layer.masks = reviewMasks(assetStemID, assetSuffix);
    for (const variant of layer.stateVariants) {
      variant.assetPath = variantAssetPath(assetStemID, variant.id);
      variant.masks = reviewMasks(assetStemID, variantAssetSuffix(variant.id));
    }
  }
  installReviewReduceMotionAssets(scene, assetStemID);
  return scene;
}

function rewriteMoreMouthsTechnicalSceneAssets(scene, assetStemID) {
  requireCondition(
    scene.id === moreMouthsTechnicalLiveSlice.sceneID,
    "More Mouths technical scene must retain its canonical scene ID",
  );
  rewriteAuthoredSceneAssets(scene, scene.id, assetStemID);
  const masksByLayerID = new Map(
    moreMouthsTechnicalLiveSlice.stageMasks.map(({ stageID, assetPath }) => [
      `stage-${stageID}`,
      { alphaMaskAssetPath: assetPath },
    ]),
  );

  for (const layer of scene.layers) {
    const stageMasks = masksByLayerID.get(layer.id);
    if (stageMasks) {
      layer.masks = structuredClone(stageMasks);
      for (const variant of layer.stateVariants) {
        requireCondition(
          ["before", "active", "completed"].includes(variant.id),
          `More Mouths has unsupported state '${variant.id}'`,
        );
        variant.masks = structuredClone(stageMasks);
      }
    }
  }
  return scene;
}

function enforcePortraitTouchTargets(scene, minimumPoints = 44) {
  const minimumWidth = minimumPoints / 393;
  const minimumHeight = minimumPoints / 852;
  for (const target of scene.interactionTargets ?? []) {
    const points = target.hitRegion?.path;
    if (!Array.isArray(points) || points.length < 3) continue;
    const xs = points.map(({ x }) => x);
    const ys = points.map(({ y }) => y);
    const left = Math.min(...xs);
    const right = Math.max(...xs);
    const top = Math.min(...ys);
    const bottom = Math.max(...ys);
    const width = Math.max(right - left, minimumWidth);
    const height = Math.max(bottom - top, minimumHeight);
    const centerX = (left + right) / 2;
    const centerY = (top + bottom) / 2;
    const expandedLeft = Math.min(Math.max(centerX - width / 2, 0), 1 - width);
    const expandedTop = Math.min(Math.max(centerY - height / 2, 0), 1 - height);
    const expandedRight = expandedLeft + width;
    const expandedBottom = expandedTop + height;
    target.hitRegion.path = [
      { x: expandedLeft, y: expandedTop },
      { x: expandedRight, y: expandedTop },
      { x: expandedRight, y: expandedBottom },
      { x: expandedLeft, y: expandedBottom },
    ];
  }
  return scene;
}

function reviewVariantUnit(value, byteOffset = 0) {
  const digest = createHash("sha256").update(value).digest();
  return digest[byteOffset % digest.length] / 255;
}

function reviewStateSuffix(reviewBeat, reviewWorld) {
  const stateIndex = reviewWorld.interactionStateIDs.indexOf(
    reviewBeat.stateVariant,
  );
  const stateProgress = reviewWorld.interactionStateIDs.length === 1
    ? 1
    : stateIndex / (reviewWorld.interactionStateIDs.length - 1);
  return stateProgress <= 0.25
    ? "state-before"
    : stateProgress >= 0.75
      ? "state-completed"
      : "state-active";
}

function applyReviewBeatVariants(scene, reviewBeat, reviewWorld) {
  const cameraX = (reviewVariantUnit(reviewBeat.cameraVariant, 0) - 0.5) * 0.06;
  const cameraY = (reviewVariantUnit(reviewBeat.cameraVariant, 1) - 0.5) * 0.04;
  const cameraScale = 1.02 + reviewVariantUnit(reviewBeat.cameraVariant, 2) * 0.035;
  const lastKeyframe = scene.cameraRail?.keyframes?.at(-1);
  if (lastKeyframe) {
    lastKeyframe.center = {
      x: Math.min(0.56, Math.max(0.44, 0.5 + cameraX)),
      y: Math.min(0.54, Math.max(0.46, 0.5 + cameraY)),
    };
    lastKeyframe.scale = cameraScale;
  }
  if (
    reviewBeat.beatID === "beat-first-farmers-household-crosses"
      || reviewBeat.beatID === "beat-first-farmers-harvest-allocation"
  ) {
    // The route's first anchor and the harvest resource both begin low in
    // their portrait masters. Show the complete shared plate for these two
    // interactions so the required touch points remain above the compact
    // narrative sheet. Reduce Motion uses the identical crop and consequence
    // geometry.
    for (const composition of [
      scene.sceneCanvas,
      scene.reduceMotionComposition,
    ]) {
      for (const crop of composition?.viewportCrops ?? []) {
        crop.sourceRect = centeredPortraitSourceRect(
          composition.canvas,
          crop.viewport,
          1,
        );
      }
    }
    for (const keyframe of scene.cameraRail?.keyframes ?? []) {
      keyframe.center = { x: 0.5, y: 0.5 };
      keyframe.scale = 1;
    }
  }
  const mechanismLight = scene.layers.find(({ id }) => id === "mechanism-light");
  if (mechanismLight) {
    mechanismLight.opacity = 0.82
      + reviewVariantUnit(reviewBeat.lightVariant, 0) * 0.18;
  }
  if (!scene.interactionVisualBinding) {
    const stateSuffix = reviewStateSuffix(reviewBeat, reviewWorld);
    const inhabitedLayer = scene.layers.find(({ id }) =>
      id === "inhabited-world");
    const foregroundIndex = scene.layers.findIndex(({ id }) =>
      ["foreground-occlusion", "foreground-occluders"].includes(id));
    requireCondition(
      inhabitedLayer !== undefined && foregroundIndex >= 0,
      `${scene.id}: shared review layers cannot host the state consequence`,
    );
    const stateLayer = structuredClone(inhabitedLayer);
    stateLayer.id = "review-state-consequence";
    stateLayer.assetPath = assetPath(reviewBeat.worldID, stateSuffix);
    stateLayer.masks = reviewMasks(reviewBeat.worldID, stateSuffix);
    stateLayer.depth = Math.min(0.88, Math.max(0.12, inhabitedLayer.depth + 0.08));
    stateLayer.opacity = 1;
    stateLayer.stateVariants = [];
    scene.layers.splice(foregroundIndex, 0, stateLayer);
    scene.layers.forEach((layer, index) => { layer.order = index; });
    const staticUnderlay = scene.reduceMotionComposition.strata.find(
      ({ kind }) => kind === "staticPlate",
    );
    requireCondition(
      staticUnderlay !== undefined,
      `${scene.id}: Reduce Motion consequence underlay is missing`,
    );
    staticUnderlay.assetPath = assetPath(
      reviewBeat.worldID,
      `reduce-motion-${stateSuffix}`,
    );
  }
  return scene;
}

function baselineCrop() {
  return {
    id: "baseline-393x852",
    viewport: { widthPoints: 393, heightPoints: 852 },
    sourceRect: { ...chapter01ReviewBaselineSourceRect },
    safeTextRegions: [
      { id: "narrative-copy", rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.2 } },
      { id: "mechanism-caption", rect: { x: 0.12, y: 0.78, width: 0.76, height: 0.12 } },
    ],
  };
}

function largestCrop() {
  return {
    id: "largest-430x932",
    viewport: { widthPoints: 430, heightPoints: 932 },
    sourceRect: { ...chapter01ReviewLargestSourceRect },
    safeTextRegions: [
      { id: "narrative-copy", rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.2 } },
      { id: "mechanism-caption", rect: { x: 0.12, y: 0.78, width: 0.76, height: 0.12 } },
    ],
  };
}

function launchCrops() {
  return [baselineCrop(), largestCrop()];
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
      canvas: { ...chapter01ReviewMasterCanvas },
      cameraTravelBounds: { x: 0.2, y: 0.2, width: 0.6, height: 0.6 },
      authoredOverscanFraction: chapter01ReviewOverscanFraction,
      viewportCrops: launchCrops(),
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
      canvas: { ...chapter01ReviewMasterCanvas },
      viewportCrops: launchCrops(),
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

function harvestProofLargestCrop() {
  const canvas = { width: 1290, height: 2796 };
  return {
    id: "largest-430x932",
    viewport: { widthPoints: 430, heightPoints: 932 },
    sourceRect: centeredPortraitSourceRect(
      canvas,
      { widthPoints: 430, heightPoints: 932 },
      1084 / 1290,
    ),
    safeTextRegions: [
      { id: "narrative-copy", rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.2 } },
      { id: "mechanism-caption", rect: { x: 0.12, y: 0.78, width: 0.76, height: 0.12 } },
    ],
  };
}

function harvestProofStaticLargestCrop() {
  const canvas = { width: 786, height: 1704 };
  return {
    id: "largest-430x932",
    viewport: { widthPoints: 430, heightPoints: 932 },
    sourceRect: centeredPortraitSourceRect(
      canvas,
      { widthPoints: 430, heightPoints: 932 },
      1,
    ),
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
      viewportCrops: [harvestProofCrop(), harvestProofLargestCrop()],
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
      viewportCrops: [harvestProofStaticCrop(), harvestProofStaticLargestCrop()],
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

function projectChapter01ReviewMainTimelines(
  source,
  projectedChapter,
  candidates,
  reviewNarration,
  reviewTransitions,
  reviewWorldIndex,
) {
  requireCondition(
    reviewNarration.manifest.manuscriptDraftSHA256
      === reviewWorldIndex.sourceDraftSHA256,
    "Chapter 01 review narration is not bound to the review matrix manuscript",
  );
  const sourceTimelinesByID = new Map(
    source.audioTimelines.map((timeline) => [timeline.id, timeline]),
  );
  const bedTimelineIDByWorldID = new Map([
    ["review-world-iron-gates-danube", "three-records-approach-v1"],
    ["review-world-aegean-crossing", "household-crosses-approach-v1"],
    ["review-world-thessaly-first-field", "household-crosses-consequence-v1"],
    ["review-world-harvest-store", "harvest-approach-v1"],
    ["review-world-longhouse-settlement", "longhouse-approach-v1"],
    ["review-world-european-farming-belt", "continent-remade-approach-v1"],
  ]);
  const transitionIDByDestinationBeatID = new Map([
    ["beat-first-farmers-living-system", "transition-aegean-thessaly-v1"],
    ["beat-first-farmers-gorge-contact", "transition-store-iron-gates-v1"],
    ["beat-first-farmers-before-steppe", "transition-farming-belt-steppe-v1"],
  ]);
  const narrationCueIDs = new Set();
  const timelines = [];
  for (const beat of projectedChapter.arcs.flatMap(({ beats }) => beats)) {
    const sourceTimeline = sourceTimelinesByID.get(`audio-${beat.id}`);
    const reviewBeat = reviewWorldIndex.beatsByID.get(beat.id);
    const bedTimeline = sourceTimelinesByID.get(
      bedTimelineIDByWorldID.get(reviewBeat?.worldID),
    );
    requireCondition(
      sourceTimeline !== undefined && bedTimeline !== undefined,
      `${beat.id}: main or world-bed timeline is unavailable`,
    );
    const bedByRole = new Map(
      bedTimeline.events
        .filter(({ role }) => role !== "silence")
        .map((event) => [event.role, event]),
    );
    const timeline = structuredClone(sourceTimeline);
    let previousSourceNarrationEnd = 0;
    let previousProjectedNarrationEnd = 0;
    let narrationIndex = 0;
    timeline.events = timeline.events.map((event) => {
      if (event.role === "narration") {
        const cue = reviewNarration.byCueID.get(event.cueID);
        requireCondition(
          cue !== undefined
            && beat.narrationCueIDs.includes(event.cueID)
            && event.narrationBinding?.manuscriptSegmentID
              === cue.manuscriptSegmentID
            && event.narrationBinding?.manuscriptSegmentSHA256
              === cue.manuscriptSegmentSHA256,
          `${event.cueID}: narration binding drifted before review projection`,
        );
        const sourceGap = narrationIndex === 0
          ? event.startSample
          : Math.max(0, event.startSample - previousSourceNarrationEnd);
        const startSample = narrationIndex === 0
          ? sourceGap
          : previousProjectedNarrationEnd + sourceGap;
        previousSourceNarrationEnd = event.startSample + event.durationSamples;
        previousProjectedNarrationEnd = startSample + cue.durationSamples;
        narrationIndex += 1;
        narrationCueIDs.add(event.cueID);
        return {
          ...event,
          startSample,
          durationSamples: cue.durationSamples,
          assetPath: reviewNarrationPackagePath(cue),
        };
      }
      if (event.role === "silence") return event;
      const bedEvent = bedByRole.get(event.role);
      const output = candidates.bySourcePath.get(bedEvent?.assetPath);
      requireCondition(
        bedEvent !== undefined && output !== undefined,
        `${timeline.id}/${event.cueID}: review world bed is unavailable`,
      );
      return {
        ...event,
        durationSamples: output.format.durationSamples,
        assetPath: output.candidateRelativePath,
      };
    });
    const transitionID = transitionIDByDestinationBeatID.get(beat.id);
    if (transitionID !== undefined) {
      const transition = reviewTransitions.byTransitionID.get(transitionID);
      requireCondition(
        transition !== undefined,
        `${beat.id}: review transition is unavailable`,
      );
      timeline.events.push({
        cueID: transitionID,
        role: "soundscape",
        startSample: 0,
        durationSamples: transition.audio.durationFrames,
        assetPath: reviewTransitionPackagePath(transition),
        gain: 1,
      });
    }
    timelines.push(timeline);
  }
  requireCondition(
    timelines.length === 17
      && narrationCueIDs.size === 37
      && reviewNarration.byCueID.size === 37
      && [...reviewNarration.byCueID.keys()].every((cueID) =>
        narrationCueIDs.has(cueID))
      && timelines.flatMap(({ events }) => events)
        .filter(({ cueID }) => reviewTransitions.byTransitionID.has(cueID))
        .length === 3,
    "Chapter 01 review main timeline projection must bind 17 timelines, 37 cues and three transitions",
  );
  return timelines;
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

export function requireChapter01ReviewComposition(payload, reviewMatrix) {
  const reviewWorldIndex = validateChapter01ReviewMatrix(reviewMatrix);
  const chapter = payload.chapters.find(({ id }) => id === "first-farmers");
  const beats = chapter?.arcs.flatMap(({ beats }) => beats) ?? [];
  const interactions = beats.flatMap(({ interaction }) =>
    interaction ? [interaction] : []);
  const narrationCueIDs = new Set(beats.flatMap(({ narrationCueIDs }) =>
    narrationCueIDs));
  const mainTimelineIDs = new Set(beats.map(({ id }) => `audio-${id}`));
  const responsiveTimelineIDs = new Set(
    payload.responsiveAudioPrograms
      .filter(({ scope }) => scope.chapterID === "first-farmers")
      .flatMap(programTimelineIDs),
  );
  requireCondition(
    chapter?.arcs.length === 3
      && beats.length === 17
      && interactions.length === 6
      && narrationCueIDs.size === 37
      && mainTimelineIDs.size === 17
      && responsiveTimelineIDs.size === 30,
    "Chapter 01 review structure must be 3/17/6/37/47",
  );
  const timelineByID = new Map(payload.audioTimelines.map((timeline) => [
    timeline.id,
    timeline,
  ]));
  requireCondition(
    [...mainTimelineIDs, ...responsiveTimelineIDs].every((timelineID) =>
      timelineByID.has(timelineID))
      && [...mainTimelineIDs].every((timelineID) =>
        timelineByID.get(timelineID).haptics.length === 0)
      && [...responsiveTimelineIDs].every((timelineID) =>
        timelineByID.get(timelineID).haptics.length === 0),
    "Chapter 01 review timelines are incomplete or contain timed haptics",
  );
  const narrationEvents = [...mainTimelineIDs].flatMap((timelineID) =>
    timelineByID.get(timelineID).events.filter(({ role }) => role === "narration"));
  requireCondition(
    narrationEvents.length === 37
      && new Set(narrationEvents.map(({ cueID }) => cueID)).size === 37
      && narrationEvents.every(({ cueID, narrationBinding, assetPath }) =>
        narrationCueIDs.has(cueID)
          && narrationBinding?.manuscriptSegmentSHA256
          && assetPath.startsWith("audio/first-farmers/review-narration/")
          && assetPath.endsWith(".m4a")),
    "Chapter 01 review narration cue projection drifted",
  );
  const expectedTransitionTimelineIDs = new Map([
    ["transition-aegean-thessaly-v1", "audio-beat-first-farmers-living-system"],
    ["transition-store-iron-gates-v1", "audio-beat-first-farmers-gorge-contact"],
    ["transition-farming-belt-steppe-v1", "audio-beat-first-farmers-before-steppe"],
  ]);
  const transitionEvents = [...mainTimelineIDs].flatMap((timelineID) =>
    timelineByID.get(timelineID).events
      .filter(({ cueID }) => expectedTransitionTimelineIDs.has(cueID))
      .map((event) => ({ timelineID, event })));
  requireCondition(
    transitionEvents.length === 3
      && transitionEvents.every(({ timelineID, event }) =>
        expectedTransitionTimelineIDs.get(event.cueID) === timelineID
          && event.role === "soundscape"
          && event.startSample === 0
          && event.durationSamples > 0
          && event.assetPath
            === `audio/first-farmers/review-transitions/${event.cueID}.m4a`),
    "Chapter 01 review transition projection drifted",
  );

  const scenesByID = new Map(payload.scenes.map((scene) => [scene.id, scene]));
  const worldIDs = new Set();
  for (const beat of beats) {
    const scene = scenesByID.get(beat.sceneID);
    const reviewBeat = reviewWorldIndex.beatsByID.get(beat.id);
    const reviewWorld = reviewWorldIndex.worldsByID.get(reviewBeat?.worldID);
    const expectedStateSuffix = beat.interaction
      ? "state-before"
      : reviewStateSuffix(reviewBeat, reviewWorld);
    requireCondition(
      scene !== undefined
        && reviewBeat?.sceneID === scene.id
        && scene.layers.some(({ assetPath }) =>
          assetPath.startsWith(`assets/${reviewBeat.worldID}-`))
        && scene.reduceMotionComposition?.strata?.length > 0,
      `${beat.id}: review scene/world/Reduce Motion projection drifted`,
    );
    requireCondition(
      scene.sceneCanvas?.canvas?.width === chapter01ReviewMasterCanvas.width
        && scene.sceneCanvas?.canvas?.height === chapter01ReviewMasterCanvas.height
        && scene.sceneCanvas?.authoredOverscanFraction
          === chapter01ReviewOverscanFraction
        && scene.reduceMotionComposition?.canvas?.width
          === chapter01ReviewMasterCanvas.width
        && scene.reduceMotionComposition?.canvas?.height
          === chapter01ReviewMasterCanvas.height,
      `${scene.id}: declared canvas does not match the rendered review master`,
    );
    const semanticLayers = [
      ["background", scene.layers.find(({ id }) =>
        ["far-landscape", "storm-sky"].includes(id))],
      ["midground", scene.layers.find(({ id }) =>
        ["inhabited-world", "settlement"].includes(id))],
      ["foreground", scene.layers.find(({ id }) =>
        ["foreground-occlusion", "foreground-occluders"].includes(id))],
      ["mechanism-light", scene.layers.find(({ id }) => id === "mechanism-light")],
    ];
    requireCondition(
      semanticLayers.every(([suffix, layer]) =>
        layer?.assetPath === assetPath(reviewBeat.worldID, suffix))
        && new Set(semanticLayers.map(([, layer]) => layer.assetPath)).size === 4,
      `${scene.id}: shared four-layer world is missing distinct semantic assets`,
    );
    for (const [suffix, layer] of semanticLayers.slice(1)) {
      const maskSuffix = suffix.startsWith("state-")
        ? "state-alpha"
        : `${suffix}-alpha`;
      requireCondition(
        layer.masks?.alphaMaskAssetPath
          === assetPath(reviewBeat.worldID, maskSuffix),
        `${scene.id}/${layer.id}: semantic overlay lost its alpha mask`,
      );
    }
    const statefulLayerIDs = scene.layers
      .filter(({ stateVariants }) => stateVariants.length > 0)
      .map(({ id }) => id);
    const reduceMotionStateLayerIDs = scene.reduceMotionComposition.strata
      .filter(({ kind }) => kind === "stateOverlay")
      .map(({ layerID }) => layerID);
    requireCondition(
      statefulLayerIDs.every((layerID) =>
        reduceMotionStateLayerIDs.includes(layerID)),
      `${scene.id}: Reduce Motion lost an interactive consequence layer`,
    );
    const staticUnderlay = scene.reduceMotionComposition.strata.find(
      ({ kind }) => kind === "staticPlate",
    );
    requireCondition(
      staticUnderlay?.assetPath === assetPath(
        reviewBeat.worldID,
        `reduce-motion-${expectedStateSuffix}`,
      ),
      `${scene.id}: Reduce Motion does not project the beat's ${expectedStateSuffix} consequence`,
    );
    requireCondition(
      scene.reduceMotionComposition.strata.some(({ kind, assetPath: pathValue }) =>
        kind === "staticPlate"
          && pathValue === assetPath(
            reviewBeat.worldID,
            "reduce-motion-foreground",
          )),
      `${scene.id}: Reduce Motion lost the foreground consequence`,
    );
    requireCondition(
      scene.reduceMotionComposition.strata.some(({ id, kind, assetPath: pathValue }) =>
        id === "static-mechanism-light"
          && kind === "staticPlate"
          && pathValue === assetPath(
            reviewBeat.worldID,
            "reduce-motion-mechanism-light",
          )),
      `${scene.id}: Reduce Motion lost the mechanism-light consequence`,
    );
    if (!beat.interaction) {
      const stateLayer = scene.layers.find(({ id }) =>
        id === "review-state-consequence");
      requireCondition(
        stateLayer?.assetPath === assetPath(reviewBeat.worldID, expectedStateSuffix),
        `${scene.id}: normal and Reduce Motion state projections diverged`,
      );
    }
    worldIDs.add(reviewBeat.worldID);
    for (const target of scene.interactionTargets ?? []) {
      const xs = target.hitRegion.path.map(({ x }) => x);
      const ys = target.hitRegion.path.map(({ y }) => y);
      requireCondition(
        (Math.max(...xs) - Math.min(...xs)) * 393 >= 44 - 1e-6
          && (Math.max(...ys) - Math.min(...ys)) * 852
            >= 44 - 1e-6,
        `${scene.id}/${target.interactionTargetID}: touch target is below 44 points`,
      );
      if (beat.interaction) {
        const crop = scene.sceneCanvas.viewportCrops.find(
          ({ id }) => id === "baseline-393x852",
        );
        requireCondition(
          crop !== undefined,
          `${scene.id}: interactive portrait crop is unavailable`,
        );
        const centerY = (Math.min(...ys) + Math.max(...ys)) / 2;
        const viewportCenterY = (centerY - crop.sourceRect.y)
          / crop.sourceRect.height;
        requireCondition(
          viewportCenterY >= 0 && viewportCenterY < 0.82,
          `${scene.id}/${target.interactionTargetID}: target center is hidden by the interactive narrative sheet`,
        );
      }
    }
    if (beat.interaction && scene.interactionVisualBinding?.grammar === "allocate") {
      const crop = scene.sceneCanvas.viewportCrops.find(
        ({ id }) => id === "baseline-393x852",
      );
      const resourcePath = scene.interactionVisualBinding.configuration
        ?.resource?.hitRegion?.path;
      requireCondition(
        crop !== undefined
          && Array.isArray(resourcePath)
          && resourcePath.length >= 3,
        `${scene.id}: allocation resource touch region is unavailable`,
      );
      const resourceCenterY = resourcePath.reduce(
        (sum, { y }) => sum + y,
        0,
      ) / resourcePath.length;
      const resourceViewportCenterY = (resourceCenterY - crop.sourceRect.y)
        / crop.sourceRect.height;
      requireCondition(
        resourceViewportCenterY >= 0 && resourceViewportCenterY < 0.82,
        `${scene.id}: allocation resource center is hidden by the interactive narrative sheet`,
      );
    }
  }
  requireCondition(
    worldIDs.size === 6,
    "Chapter 01 review scenes must share exactly six worlds",
  );

  const trace = interactions.find(({ grammar }) => grammar === "trace");
  const allocate = interactions.find(({ grammar }) => grammar === "allocate");
  const assemble = interactions.find(({ grammar }) => grammar === "assemble");
  const transforms = interactions.filter(({ grammar }) => grammar === "transform");
  const traceBeat = beats.find(({ interaction }) =>
    interaction?.grammar === "trace");
  const traceScene = scenesByID.get(traceBeat?.sceneID);
  const traceCrop = traceScene?.sceneCanvas.viewportCrops.find(
    ({ id }) => id === "baseline-393x852",
  );
  requireCondition(
    trace?.configuration?.anchors?.length === 4
      && traceCrop !== undefined
      && trace.configuration.anchors.every(({ y }) => {
        const viewportY = (y - traceCrop.sourceRect.y)
          / traceCrop.sourceRect.height;
        return viewportY >= 0 && viewportY < 0.82;
      })
      && allocate?.configuration?.totalUnits === 12
      && allocate?.configuration?.destinations?.map(({ minimumUnits }) =>
        minimumUnits)
        .join(",") === "4,2,3"
      && assemble?.configuration?.components?.map(({ id, prerequisites }) =>
        `${id}:${prerequisites.join("+")}`).join(",")
        === "posts:,hearth:posts,storage:posts,roof:posts"
      && transforms.length === 3
      && transforms.every(({ configuration }) =>
        configuration.stages.length === 3),
    "Chapter 01 review interaction contract drifted",
  );
  return {
    arcCount: chapter.arcs.length,
    beatCount: beats.length,
    interactionCount: interactions.length,
    worldCount: worldIDs.size,
    narrationCueCount: narrationCueIDs.size,
    timelineCount: mainTimelineIDs.size + responsiveTimelineIDs.size,
    transitionCount: transitionEvents.length,
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
    const chapter = payload.chapters.find(({ id }) => id === expected.contentID);
    const canonicalFirstFarmersBeat = expected.contentID === "first-farmers"
      ? chapter?.arcs.flatMap(({ beats }) => beats).find(({ interaction }) =>
        interaction?.id === expected.nativeInteractionID)
      : undefined;
    const arc = canonicalFirstFarmersBeat
      ? chapter?.arcs.find(({ beats }) => beats.some(({ id }) =>
        id === canonicalFirstFarmersBeat.id))
      : chapter?.arcs.find(({ id }) => id === expected.arcID);
    const beat = canonicalFirstFarmersBeat
      ?? arc?.beats.find(({ id }) => id === expected.beatID);
    const expectedSceneID = beat?.sceneID ?? expected.labSceneID;
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

function buildPayload(
  source,
  documents,
  experienceLab,
  responsiveAudioCandidates,
  reviewWorldIndex,
  reviewNarration,
  reviewTransitions,
) {
  const sourceChapter = source.chapters.find(({ id }) => id === "first-farmers");
  const sourceBeats = sourceChapter?.arcs.flatMap(({ beats }) => beats) ?? [];
  if (!sourceChapter || sourceChapter.arcs.length !== 3 || sourceBeats.length !== 17) {
    throw new Error("The authored First Farmers chapter source is incomplete");
  }

  const firstFarmers = structuredClone(sourceChapter);
  // The authored draft carries a provisional convenience mutation that is
  // intentionally outside the approved WorldEffect ledger. The six approved
  // interaction effects already carry the complete chapter causal state.
  firstFarmers.completionEffects = [];

  const sourceScenesByID = new Map(source.scenes.map((scene) => [scene.id, scene]));
  const chapterScenesByID = new Map();
  for (const beat of firstFarmers.arcs.flatMap(({ beats }) => beats)) {
    const reviewBeat = reviewWorldIndex.beatsByID.get(beat.id);
    const sourceScene = sourceScenesByID.get(beat.sceneID);
    requireCondition(
      reviewBeat?.sceneID === beat.sceneID && sourceScene !== undefined,
      `${beat.id}: review matrix or authored scene identity drifted`,
    );
    const scene = beat.id === moreMouthsTechnicalLiveSlice.beatID
      ? rewriteMoreMouthsTechnicalSceneAssets(
        structuredClone(sourceScene),
        reviewBeat.worldID,
      )
      : rewriteAuthoredSceneAssets(
        structuredClone(sourceScene),
        beat.sceneID,
        reviewBeat.worldID,
      );
    if (beat.id === "beat-first-farmers-harvest-allocation") {
      requireCondition(
        typeof localizedEnglish(scene.mechanismFocus) === "string",
        "Harvest review projection is missing its mechanism focus",
      );
      scene.mechanismFocus.launchEnglish =
        "One finite harvest, divided into twelve equal illustrative runtime shares, must become winter food, protected reserve and seed grain before the grain in the foreground is exhausted.";
    }
    applyReviewBeatVariants(
      scene,
      reviewBeat,
      reviewWorldIndex.worldsByID.get(reviewBeat.worldID),
    );
    enforcePortraitTouchTargets(
      scene,
      44,
    );
    chapterScenesByID.set(scene.id, scene);
  }
  const chapterScenes = firstFarmers.arcs
    .flatMap(({ beats }) => beats)
    .map((beat) => chapterScenesByID.get(beat.sceneID));
  if (chapterScenes.some((scene) => !scene) || new Set(chapterScenes.map(({ id }) => id)).size !== 17) {
    throw new Error("The live First Farmers chapter does not project exactly one scene per beat");
  }

  const chapterAccessibilityByID = new Map(
    source.accessibility
      .map((accessibility) => [accessibility.id, structuredClone(accessibility)]),
  );
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
  const firstFarmersMainTimelines = projectChapter01ReviewMainTimelines(
    source,
    firstFarmers,
    responsiveAudioCandidates,
    reviewNarration,
    reviewTransitions,
    reviewWorldIndex,
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
      ...firstFarmersMainTimelines,
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
  const [
    sourcePayload,
    blueprint,
    experienceLab,
    responsiveAudioCandidates,
    reviewMatrix,
    reviewNarration,
    reviewTransitions,
  ] = await Promise.all([
    readFile(sourcePayloadPath, "utf8").then(JSON.parse),
    readBlueprintProjectionDocuments(blueprintRoot),
    readFile(experienceLabPath, "utf8").then(JSON.parse),
    loadFirstFarmersResponsiveAudioCandidates(),
    readFile(chapter01ReviewMatrixPath, "utf8").then(JSON.parse),
    loadChapter01ReviewNarration(),
    loadChapter01ReviewTransitions(),
  ]);
  const reviewWorldIndex = validateChapter01ReviewMatrix(reviewMatrix);
  const reviewDraftPath = path.resolve(
    repositoryRoot,
    reviewMatrix.sourceDraft?.path ?? "",
  );
  requireCondition(
    !path.relative(repositoryRoot, reviewDraftPath).startsWith("..")
      && sha256(await readFile(reviewDraftPath)) === reviewMatrix.sourceDraft?.sha256,
    "Chapter 01 review matrix is not bound to the frozen manuscript bytes",
  );

  // Resolve and verify every immutable input before replacing the last usable
  // fixture. A missing review cue or stale receipt must fail without leaving
  // the development package half-deleted.
  for (const target of [sourceRoot, path.dirname(packageRoot), backstageRoot]) {
    await rm(target, { recursive: true, force: true });
  }
  for (const target of [trustReceiptPath, lineagePath]) {
    await rm(target, { force: true });
  }
  await mkdir(path.join(sourceRoot, "chapters"), { recursive: true });

  const visualSources = fixtureVisualSources(reviewWorldIndex);
  const renderedPaths = await renderAssets(reviewWorldIndex, visualSources);
  const chapter01ReviewRasterMasters =
    await validateChapter01ReviewRasterAssets(reviewWorldIndex);
  const payload = buildPayload(
    sourcePayload,
    blueprint,
    experienceLab,
    responsiveAudioCandidates,
    reviewWorldIndex,
    reviewNarration,
    reviewTransitions,
  );
  const responsiveAudioProjection =
    requireRepresentativeFirstFarmersResponsiveAudio(payload);
  const chapter01ReviewComposition = requireChapter01ReviewComposition(
    payload,
    reviewMatrix,
  );
  await removeUnreferencedRenderedAssets(payload, renderedPaths);
  await installFirstFarmersResponsiveAudioCandidates(
    responsiveAudioCandidates,
  );
  await installChapter01ReviewNarration(reviewNarration);
  await installChapter01ReviewTransitions(reviewTransitions);
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
    milestone: "CHAPTER_01_REVIEW_READY",
    milestoneStatus: "CANDIDATE_PENDING_REVIEW_GATES",
    authorityShape:
      "CHAPTER_01_REVIEW_CANDIDATE_PLUS_EXISTING_SUPPORT_LABS",
    chapterIDs: payload.chapters.map(({ id }) => id),
    fullChapterProjection: {
      contentID: "first-farmers",
      arcCount: firstFarmersProjection.arcs.length,
      beatCount: firstFarmersProjectedBeats.length,
      interactionCount: firstFarmersProjectedBeats
        .filter(({ interaction }) => interaction).length,
      sceneCount: firstFarmersProjectedBeats.length,
      accessibilityCount: firstFarmersProjectedBeats.length,
      worldCount: chapter01ReviewComposition.worldCount,
      narrationCueCount: chapter01ReviewComposition.narrationCueCount,
      audioTimelineCount: chapter01ReviewComposition.timelineCount,
      transitionCount: chapter01ReviewComposition.transitionCount,
      narrationState: "PROVISIONAL_NON_SHIPPING_REVIEW",
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
        ...(reviewWorldIndex.worldsByID.has(assetStemID)
          ? {
            worldID: assetStemID,
            sourceStatus: reviewWorldIndex.worldsByID.get(assetStemID)
              .sourceStatus,
          }
          : { sceneID: assetStemID }),
        assetStemID,
        ...await fileRecord(file),
      })),
    ),
    visualSourceStatus: "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_INPUT",
    chapter01Review: {
      status: "NON_SHIPPING_REVIEW",
      shippingState: "PROHIBITED",
      milestone: "CHAPTER_01_REVIEW_READY",
      milestoneStatus: "CANDIDATE_PENDING_REVIEW_GATES",
      matrix: await fileRecord(chapter01ReviewMatrixPath),
      frozenDraft: await fileRecord(reviewDraftPath),
      composition: chapter01ReviewComposition,
      rasterMasters: chapter01ReviewRasterMasters,
      worldIDs: [...reviewWorldIndex.worldsByID.keys()],
      beatBindings: reviewMatrix.beats,
      narration: {
        manifest: await fileRecord(chapter01ReviewNarrationManifestPath),
        manifestSHA256: reviewNarration.manifestSHA256,
        status: reviewNarration.manifest.status,
        shippingState: reviewNarration.manifest.shippingState,
        cueCount: reviewNarration.byCueID.size,
        combinedBindingSHA256:
          reviewNarration.manifest.combinedBindingSHA256,
        cues: await Promise.all(
          [...reviewNarration.byCueID.values()].map(async (cue) => ({
            cueID: cue.cueID,
            manuscriptSegmentID: cue.manuscriptSegmentID,
            manuscriptSegmentSHA256: cue.manuscriptSegmentSHA256,
            packageAssetPath: reviewNarrationPackagePath(cue),
            ...await fileRecord(path.resolve(repositoryRoot, cue.repositoryPath)),
          })),
        ),
      },
      transitions: {
        manifest: await fileRecord(chapter01ReviewTransitionManifestPath),
        manifestSHA256: reviewTransitions.manifestSHA256,
        status: reviewTransitions.manifest.status,
        shippingState: reviewTransitions.manifest.shippingState,
        transitionCount: reviewTransitions.byTransitionID.size,
        items: await Promise.all(
          [...reviewTransitions.byTransitionID.values()].map(
            async (transition) => ({
              transitionID: transition.transitionID,
              fromWorld: transition.fromWorld,
              toWorld: transition.toWorld,
              packageAssetPath: reviewTransitionPackagePath(transition),
              ...await fileRecord(
                path.resolve(repositoryRoot, transition.audio.path),
              ),
            }),
          ),
        ),
      },
    },
    moreMouthsTechnicalLiveSlice: {
      status: "CODEX_PROVISIONAL_NON_SHIPPING_CAUSAL_STATE_PROOF",
      shippingState: "PROHIBITED",
      beatID: moreMouthsTechnicalLiveSlice.beatID,
      sceneID: moreMouthsTechnicalLiveSlice.sceneID,
      accessibilityID: moreMouthsTechnicalLiveSlice.accessibilityID,
      interactionID: moreMouthsTechnicalLiveSlice.interactionID,
      technicalAssetStemID: moreMouthsTechnicalLiveSlice.assetStemID,
      stateAssetStemID: reviewWorldIndex.worldIDBySceneID.get(
        moreMouthsTechnicalLiveSlice.sceneID,
      ),
      semanticLayers: await Promise.all(
        chapter01ReviewSemanticAssetSuffixes.map(async (suffix) => {
          const worldID = reviewWorldIndex.worldIDBySceneID.get(
            moreMouthsTechnicalLiveSlice.sceneID,
          );
          const packageAssetPath = assetPath(worldID, suffix);
          return {
            suffix,
            packageAssetPath,
            ...await fileRecord(path.join(
              sourceRoot,
              ...packageAssetPath.split("/"),
            )),
          };
        }),
      ),
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
