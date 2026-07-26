#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  cp,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import {
  canonicalSHA256,
  pixelRect,
  probeRaster,
  sceneVisualInventory,
} from "../tooling/src/visual-asset-production.mjs";
import {
  forbiddenReleaseByteSequences,
  releaseValidationModes,
  validateReleaseAppBoundary,
} from "./validate-release-app-boundary.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const resolveRepositoryPath = (value) => path.resolve(repositoryRoot, value);
const hashBytes = (bytes) => createHash("sha256").update(bytes).digest("hex");
const paths = Object.freeze({
  backup: "native/content/backstage/harvest/backups/production-master-candidate-v26.filevault-copy.png",
  candidate: "native/design/phase1/harvest/production-master-candidate-v26-garments-local-composite.png",
  contract: "native/design/phase1/harvest/layer-production-contract.json",
  dag: "native/content/backstage/harvest/visual-asset-dag-v26.provisional.json",
  fixture: "native/phase1/fixtures/harvest-option-1.scene.json",
  output: "native/.build/visual-assets/harvest-v26-products",
  receipt: "native/content/backstage/harvest/visual-asset-receipt-v26.provisional.json",
  report: "native/content/backstage/harvest/visual-asset-qa-v26.provisional.json",
});
const candidateSHA256 = "e00eebcac9c20b7cd4c30193ea21bc7f032981817840cb85694298240d0618ca";

function fail(message) {
  throw new Error(message);
}

function requireCondition(condition, message) {
  if (!condition) fail(message);
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

function decode(filePath, pixelFormat, width, height) {
  const channels = pixelFormat === "gray" ? 1 : pixelFormat === "rgb24" ? 3 : 4;
  let decodePath = filePath;
  let temporaryRoot;
  if (/\.hei[cf]$/iu.test(filePath)) {
    temporaryRoot = run("mktemp", ["-d", path.join(os.tmpdir(), "long-west-harvest-qa.XXXXXX")], { encoding: "utf8" }).trim();
    decodePath = path.join(temporaryRoot, "primary.png");
    run("/usr/bin/sips", ["-s", "format", "png", filePath, "--out", decodePath], { encoding: "utf8" });
  }
  try {
    const bytes = run("ffmpeg", [
      "-v", "error", "-i", decodePath,
      "-frames:v", "1", "-vf", `format=${pixelFormat}`,
      "-f", "rawvideo", "pipe:1",
    ]);
    requireCondition(bytes.byteLength === width * height * channels, `${filePath}: decoded byte count drifted`);
    return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  } finally {
    if (temporaryRoot) run("rm", ["-rf", temporaryRoot]);
  }
}

function crop(pixels, sourceWidth, rect, channels) {
  const output = new Uint8Array(rect.width * rect.height * channels);
  for (let y = 0; y < rect.height; y += 1) {
    const sourceOffset = ((rect.y + y) * sourceWidth + rect.x) * channels;
    output.set(pixels.subarray(sourceOffset, sourceOffset + rect.width * channels), y * rect.width * channels);
  }
  return output;
}

function maskStatistics(pixels, width, height) {
  let minimum = 255;
  let maximum = 0;
  let nonzero = 0;
  let soft = 0;
  let sum = 0;
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
      if (value > 0 && value < 255) soft += 1;
    }
  }
  return {
    minimum,
    maximum,
    mean: sum / pixels.byteLength,
    nonzeroFraction: nonzero / pixels.byteLength,
    softEdgeFraction: soft / pixels.byteLength,
    nonzeroBounds: nonzero === 0 ? null : {
      x: minX / width,
      y: minY / height,
      width: (maxX + 1 - minX) / width,
      height: (maxY + 1 - minY) / height,
    },
  };
}

function meanLuminance(rgb, authorization) {
  let sum = 0;
  let count = 0;
  for (let index = 0; index < authorization.byteLength; index += 1) {
    if (authorization[index] < 128) continue;
    const offset = index * 3;
    sum += rgb[offset] * 0.30 + rgb[offset + 1] * 0.59 + rgb[offset + 2] * 0.11;
    count += 1;
  }
  requireCondition(count > 0, "state luminance gate received an empty authorization core");
  return sum / count;
}

async function main() {
  throw new Error(
    "REJECTED_GEOMETRIC_MASK_NEGATIVE_FIXTURE: deterministic bytes cannot pass visual QA when masks are geometric placeholders rather than subject silhouettes",
  );

  /* c8 ignore start -- retained only to preserve the rejected audit method */
  const [candidateBytes, backupBytes, contractBytes, dagBytes, fixtureBytes, receiptBytes] = await Promise.all([
    readFile(resolveRepositoryPath(paths.candidate)),
    readFile(resolveRepositoryPath(paths.backup)),
    readFile(resolveRepositoryPath(paths.contract)),
    readFile(resolveRepositoryPath(paths.dag)),
    readFile(resolveRepositoryPath(paths.fixture)),
    readFile(resolveRepositoryPath(paths.receipt)),
  ]);
  requireCondition(hashBytes(candidateBytes) === candidateSHA256, "v26 candidate drifted after asset production");
  requireCondition(backupBytes.equals(candidateBytes), "encrypted-at-rest local backup drifted from v26");
  const contract = JSON.parse(contractBytes);
  const dag = JSON.parse(dagBytes);
  const fixture = JSON.parse(fixtureBytes);
  const receipt = JSON.parse(receiptBytes);
  requireCondition(dag.buildMode === "CODEX_PROVISIONAL_NON_SHIPPING_DEVELOPMENT", "DAG escaped provisional development mode");
  requireCondition(receipt.status === "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_REPRODUCTION_PASS", "receipt trust domain drifted");
  requireCondition(receipt.shippingState === "PROHIBITED_UNTIL_SEPARATE_EDITOR_ASSET_AND_PACKAGE_APPROVAL", "receipt claims shipping authority");
  requireCondition(receipt.dagSHA256 === canonicalSHA256(dag), "receipt DAG hash drifted");
  requireCondition(receipt.contractSHA256 === canonicalSHA256(contract), "receipt contract hash drifted");

  const outputRoot = resolveRepositoryPath(paths.output);
  const inventory = sceneVisualInventory(fixture);
  requireCondition(JSON.stringify(inventory.counts) === JSON.stringify(contract.requiredFinalAssets), "SceneSpec inventory drifted from contract");
  requireCondition(inventory.counts.total === 86, "Harvest final inventory is not exactly 86 files");
  const receiptByPath = new Map(receipt.outputs.map((record) => [record.outputPath, record]));
  const operationByPath = new Map(dag.operations.map((record) => [record.outputPath, record]));
  const operationByID = new Map(dag.operations.map((record) => [record.id, record]));
  const sourceByID = new Map(dag.sources.map((record) => [record.id, record]));
  const finalAssets = [];
  const maskResults = [];

  for (const asset of inventory.assets) {
    requireCondition(asset.assetPath.startsWith("assets/phase1/harvest-option-1/"), `${asset.assetPath}: final asset escaped Harvest asset root`);
    requireCondition(!asset.assetPath.includes("backstage") && !asset.assetPath.includes(".build"), `${asset.assetPath}: backstage path leaked into final inventory`);
    const record = receiptByPath.get(asset.assetPath);
    const sourceOperation = operationByPath.get(asset.assetPath);
    requireCondition(record && sourceOperation, `${asset.assetPath}: missing exact receipt or DAG operation`);
    const filePath = path.resolve(outputRoot, asset.assetPath);
    const bytes = await readFile(filePath);
    requireCondition(bytes.byteLength === record.bytes && hashBytes(bytes) === record.sha256, `${asset.assetPath}: byte/hash drift`);
    const probe = probeRaster(filePath);
    requireCondition(probe.width === asset.pixelRect.width && probe.height === asset.pixelRect.height, `${asset.assetPath}: crop geometry drift`);
    for (const marker of forbiddenReleaseByteSequences) {
      requireCondition(bytes.indexOf(Buffer.from(marker, "utf8")) === -1, `${asset.assetPath}: provisional/debug marker leaked into final asset bytes`);
    }
    const finalRecord = {
      path: asset.assetPath,
      kind: asset.kind,
      ownerID: asset.ownerID,
      variantID: asset.variantID,
      maskType: asset.maskType,
      bytes: record.bytes,
      sha256: record.sha256,
      width: record.width,
      height: record.height,
    };
    finalAssets.push(finalRecord);
    if (asset.kind === "scene-mask") {
      const pixels = decode(filePath, "gray", probe.width, probe.height);
      const stats = maskStatistics(pixels, probe.width, probe.height);
      if (asset.maskType === "depth") {
        requireCondition(stats.minimum < stats.maximum, `${asset.assetPath}: depth map lacks variation`);
      } else {
        requireCondition(stats.nonzeroFraction > 0 && stats.nonzeroFraction < 0.999999, `${asset.assetPath}: ${asset.maskType} mask is empty or full-frame`);
      }
      if (asset.maskType === "alpha") {
        requireCondition(stats.softEdgeFraction > 0.0001, `${asset.assetPath}: alpha edge has no authored feather`);
      }
      maskResults.push({ path: asset.assetPath, maskType: asset.maskType, ...stats });
    }
    if (/\.hei[cf]$/iu.test(asset.assetPath)) {
      requireCondition(record.maskStats?.encoding === "heic", `${asset.assetPath}: missing HEIF fidelity record`);
      requireCondition(record.maskStats.maxChannelError <= contract.encodingGate.maxChannelError, `${asset.assetPath}: HEIF max error exceeded`);
      requireCondition(record.maskStats.meanAbsoluteError <= contract.encodingGate.maxMeanAbsoluteError, `${asset.assetPath}: HEIF mean error exceeded`);
    }
  }

  const expectedPaths = new Set(inventory.assets.map(({ assetPath }) => assetPath));
  requireCondition(finalAssets.length === expectedPaths.size && expectedPaths.size === 86, "final inventory is not one-to-one");

  let straightAlphaPixels = 0;
  let softEdgePixels = 0;
  for (const layerOperation of dag.operations.filter(({ kind }) => kind === "extract-layer")) {
    const outputRecord = receiptByPath.get(layerOperation.outputPath);
    const output = decode(
      path.resolve(outputRoot, layerOperation.outputPath),
      "rgba",
      outputRecord.width,
      outputRecord.height,
    );
    const source = sourceByID.get(layerOperation.sourceID);
    const sourcePixels = decode(
      resolveRepositoryPath(source.path),
      "rgb24",
      source.dimensions.width,
      source.dimensions.height,
    );
    const rect = pixelRect(layerOperation.frame, fixture.scene.sceneCanvas.canvas);
    const expectedRGB = source.dimensions.width === rect.width && source.dimensions.height === rect.height
      ? sourcePixels
      : crop(sourcePixels, source.dimensions.width, rect, 3);
    const alphaOperation = operationByID.get(layerOperation.alphaMaskOperationID);
    const alphaRecord = receiptByPath.get(alphaOperation.outputPath);
    const alpha = decode(
      path.resolve(outputRoot, alphaOperation.outputPath),
      "gray",
      alphaRecord.width,
      alphaRecord.height,
    );
    for (let pixel = 0; pixel < alpha.byteLength; pixel += 1) {
      const rgbaOffset = pixel * 4;
      const rgbOffset = pixel * 3;
      requireCondition(output[rgbaOffset] === expectedRGB[rgbOffset]
        && output[rgbaOffset + 1] === expectedRGB[rgbOffset + 1]
        && output[rgbaOffset + 2] === expectedRGB[rgbOffset + 2], `${layerOperation.id}: RGB edge was premultiplied or matted`);
      requireCondition(output[rgbaOffset + 3] === alpha[pixel], `${layerOperation.id}: embedded alpha drifted from authored mask`);
      straightAlphaPixels += 1;
      if (alpha[pixel] > 0 && alpha[pixel] < 255) softEdgePixels += 1;
    }
  }
  requireCondition(softEdgePixels > 0, "straight-alpha halo gate found no soft edge pixels");

  const cleanPlates = [];
  for (const plate of contract.cleanPlateCoverage) {
    const record = receiptByPath.get(plate.workingPath);
    requireCondition(record?.width === fixture.scene.sceneCanvas.canvas.width
      && record?.height === fixture.scene.sceneCanvas.canvas.height, `${plate.id}: clean plate geometry drifted`);
    requireCondition(record.sha256 !== candidateSHA256, `${plate.id}: clean plate is an unchanged master copy`);
    cleanPlates.push({ id: plate.id, path: plate.workingPath, bytes: record.bytes, sha256: record.sha256 });
  }

  const stateLuminance = {};
  for (const policy of contract.stateVariantPolicies) {
    const stateAsset = inventory.assets.find((asset) => asset.kind === "scene-layer"
      && asset.ownerID === policy.layerID && asset.variantID === policy.variantID);
    const stateOperation = operationByPath.get(stateAsset.assetPath);
    const workingOperation = operationByID.get(stateOperation.inputOperationIDs[0]);
    const source = sourceByID.get(workingOperation.sourceID);
    const rgb = decode(resolveRepositoryPath(source.path), "rgb24", source.dimensions.width, source.dimensions.height);
    const authorizationOperation = operationByID.get(stateOperation.authorizationMaskOperationID);
    const authorizationRecord = receiptByPath.get(authorizationOperation.outputPath);
    const authorization = decode(
      path.resolve(outputRoot, authorizationOperation.outputPath),
      "gray",
      authorizationRecord.width,
      authorizationRecord.height,
    );
    stateLuminance[`${policy.layerID}.${policy.variantID}`] = meanLuminance(rgb, authorization);
  }
  for (const ownerID of ["winter-store", "protected-reserve", "spring-seed"]) {
    const variants = Object.entries(stateLuminance).filter(([key]) => key.startsWith(`${ownerID}.`));
    const empty = variants.find(([key]) => key.endsWith(".empty"))?.[1];
    const other = variants.filter(([key]) => !key.endsWith(".empty")).map(([, value]) => value);
    requireCondition(other.every((value) => value > empty + 4), `${ownerID}: empty/receiving/completed state values are not causally distinct`);
  }
  const central = ["full", "reduced", "scarce", "exhausted"].map((variantID) => stateLuminance[`central-harvest.${variantID}`]);
  requireCondition(central.every((value, index) => index === 0 || central[index - 1] > value + 4), "central harvest depletion is not monotonically legible");

  const cropResults = [];
  const standardCrops = fixture.scene.sceneCanvas.viewportCrops;
  const reduceCrops = fixture.scene.reduceMotionComposition.viewportCrops;
  requireCondition(JSON.stringify(standardCrops) === JSON.stringify(reduceCrops), "Reduce Motion viewport crops drifted from standard composition");
  for (const cropRecord of standardCrops) {
    const source = cropRecord.sourceRect;
    requireCondition(source.x >= 0 && source.y >= 0
      && source.x + source.width <= 1 && source.y + source.height <= 1, `${cropRecord.id}: source crop escaped canvas`);
    const sourceAspect = source.width * fixture.scene.sceneCanvas.canvas.width
      / (source.height * fixture.scene.sceneCanvas.canvas.height);
    const viewportAspect = cropRecord.viewport.widthPoints / cropRecord.viewport.heightPoints;
    requireCondition(Math.abs(sourceAspect - viewportAspect) < 0.001, `${cropRecord.id}: crop aspect drifted from viewport`);
    for (const region of cropRecord.safeTextRegions) {
      requireCondition(region.rect.x >= 0 && region.rect.y >= 0
        && region.rect.x + region.rect.width <= 1
        && region.rect.y + region.rect.height <= 1, `${cropRecord.id}.${region.id}: safe text region escaped viewport`);
    }
    cropResults.push({
      id: cropRecord.id,
      sourceRect: cropRecord.sourceRect,
      viewport: cropRecord.viewport,
      sourceAspect,
      viewportAspect,
      safeTextRegionCount: cropRecord.safeTextRegions.length,
    });
  }

  requireCondition(receipt.recomposition.maxChannelError === 0
    && receipt.recomposition.meanAbsoluteError === 0
    && receipt.recomposition.exactPixelFraction === 1, "base-layer recomposition is not byte-exact at decoded pixels");

  const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "long-west-harvest-release-leak-"));
  const appPath = path.join(temporaryRoot, "HarvestAssets.app");
  try {
    await mkdir(appPath, { recursive: true });
    await cp(path.join(outputRoot, "assets"), path.join(appPath, "Assets"), { recursive: true });
    await validateReleaseAppBoundary(appPath, { mode: releaseValidationModes.boundaryOnly });
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }

  const report = {
    schemaVersion: 1,
    status: "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_QA_PASS",
    shippingState: "PROHIBITED",
    editorApprovalState: "NOT_CLAIMED",
    candidate: { path: paths.candidate, bytes: candidateBytes.byteLength, sha256: hashBytes(candidateBytes) },
    backup: { path: paths.backup, bytes: backupBytes.byteLength, sha256: hashBytes(backupBytes), scope: "SAME_FILEVAULT_VOLUME_ONLY" },
    dag: { path: paths.dag, bytes: dagBytes.byteLength, sha256: hashBytes(dagBytes), canonicalSHA256: canonicalSHA256(dag) },
    receipt: { path: paths.receipt, bytes: receiptBytes.byteLength, sha256: hashBytes(receiptBytes) },
    inventory: { counts: inventory.counts, files: finalAssets },
    gates: {
      exactRecomposition: {
        status: "PASS",
        maxChannelError: receipt.recomposition.maxChannelError,
        meanAbsoluteError: receipt.recomposition.meanAbsoluteError,
        exactPixelFraction: receipt.recomposition.exactPixelFraction,
        outputSHA256: receipt.recomposition.outputSHA256,
        diffSHA256: receipt.recomposition.diffSHA256,
      },
      geometryAndCrop: { status: "PASS", crops: cropResults },
      masks: { status: "PASS", files: maskResults },
      straightAlphaHalo: { status: "PASS", inspectedPixels: straightAlphaPixels, softEdgePixels },
      cleanPlates: { status: "PASS_TECHNICAL_NOT_ARTISTIC_APPROVAL", files: cleanPlates },
      causalStateLegibility: { status: "PASS_TECHNICAL", meanLuminance: stateLuminance },
      reduceMotion: {
        status: "PASS",
        files: finalAssets.filter(({ kind }) => kind === "reduce-motion-plate").map(({ path: filePath, bytes, sha256 }) => ({ path: filePath, bytes, sha256 })),
      },
      releaseLeakBoundary: { status: "PASS_BOUNDARY_ONLY", inspectedFinalAssetCount: finalAssets.length },
      deterministicReplay: { status: "PASS_SEPARATE_VERIFY_COMMAND", receiptStatus: receipt.status },
    },
    remainingLimits: [
      "Codex-authored geometric masks and deterministic local-sampling clean plates still require editor visual inspection before any asset approval.",
      "The mechanism-light layer is a black technical screen plate used to preserve exact master recomposition; runtime focus-light art remains open.",
      "This QA does not claim simulator motion quality, physical-device display quality, integrated sound, VoiceOver parity or shipping-package approval.",
      "The backup is byte-identical and encrypted at rest by existing FileVault, but it is on the same Mac and is not an independent failure domain.",
    ],
  };
  const reportBytes = Buffer.from(`${JSON.stringify(report, null, 2)}\n`);
  await writeFile(resolveRepositoryPath(paths.report), reportBytes);
  process.stdout.write(
    `Validated ${finalAssets.length} final Harvest assets, ${maskResults.length} masks and ${straightAlphaPixels} straight-alpha pixels.\n`
      + `QA report ${hashBytes(reportBytes)}; trust domain remains provisional and non-shipping.\n`,
  );
  /* c8 ignore stop */
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`);
  process.exitCode = 1;
});
