#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  mkdir,
  readFile,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import {
  canonicalSHA256,
  pixelRect,
  provisionalVisualMasterStatus,
  sceneVisualInventory,
  visualProductionBuildModes,
} from "../tooling/src/visual-asset-production.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const repositoryPath = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const resolveRepositoryPath = (value) => path.resolve(repositoryRoot, value);
const hashBytes = (bytes) => createHash("sha256").update(bytes).digest("hex");
const clampByte = (value) => Math.max(0, Math.min(255, Math.round(value)));
const fullFrame = Object.freeze({ x: 0, y: 0, width: 1, height: 1 });

const paths = Object.freeze({
  authority: "native/content/backstage/harvest/production-master-authority-v26.provisional.json",
  backup: "native/content/backstage/harvest/backups/production-master-candidate-v26.filevault-copy.png",
  backupVerification: "native/content/backstage/harvest/backups/production-master-candidate-v26.backup-verification.json",
  candidate: "native/design/phase1/harvest/production-master-candidate-v26-garments-local-composite.png",
  contract: "native/design/phase1/harvest/layer-production-contract.json",
  dag: "native/content/backstage/harvest/visual-asset-dag-v26.provisional.json",
  fixture: "native/phase1/fixtures/harvest-option-1.scene.json",
  sourceInventory: "native/content/backstage/harvest/visual-source-inventory-v26.provisional.json",
  sourceRoot: "native/.build/visual-assets/harvest-v26-sources",
  symbolic: "native/content/backstage/harvest/visual-authoring-v26.symbolic.json",
});

const expected = Object.freeze({
  authoritySHA256: "82ffe59bfa5582b6fd2fb3d085fdd39e923e748352b735ae4f0e7f43fde44bbc",
  candidateBytes: 5_860_864,
  candidateSHA256: "e00eebcac9c20b7cd4c30193ea21bc7f032981817840cb85694298240d0618ca",
  height: 2_796,
  width: 1_290,
});

const masterSourceID = "harvest-production-master-candidate-v26-garments-local-composite";
const rights = Object.freeze({
  status: "COMMERCIAL_USE_CLEARED",
  incrementalCostNOK: 0,
  license: "Project-owned Codex-authored visual material; shipping remains prohibited until separate editor asset and package approval.",
});

function run(command, arguments_, options = {}) {
  const result = spawnSync(command, arguments_, {
    encoding: options.encoding,
    maxBuffer: options.maxBuffer ?? 128 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const error = Buffer.isBuffer(result.stderr) ? result.stderr.toString("utf8") : result.stderr;
    throw new Error(`${command} failed: ${error?.trim() || `exit ${result.status}`}`);
  }
  return result.stdout;
}

function decodeRGB(filePath, width, height) {
  const bytes = run("ffmpeg", [
    "-v", "error", "-i", filePath,
    "-frames:v", "1", "-vf", "format=rgb24",
    "-f", "rawvideo", "pipe:1",
  ]);
  if (bytes.byteLength !== width * height * 3) {
    throw new Error(`master decode returned ${bytes.byteLength} bytes; expected ${width * height * 3}`);
  }
  return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
}

function ppm(width, height, pixels) {
  if (pixels.byteLength !== width * height * 3) throw new Error("PPM pixel count drifted");
  return Buffer.concat([Buffer.from(`P6\n${width} ${height}\n255\n`), Buffer.from(pixels)]);
}

function pgm(width, height, pixels) {
  if (pixels.byteLength !== width * height) throw new Error("PGM pixel count drifted");
  return Buffer.concat([Buffer.from(`P5\n${width} ${height}\n255\n`), Buffer.from(pixels)]);
}

function cropRGB(pixels, canvas, rect) {
  const output = new Uint8Array(rect.width * rect.height * 3);
  for (let y = 0; y < rect.height; y += 1) {
    const sourceOffset = ((rect.y + y) * canvas.width + rect.x) * 3;
    output.set(
      pixels.subarray(sourceOffset, sourceOffset + rect.width * 3),
      y * rect.width * 3,
    );
  }
  return output;
}

function smoothstep(edge0, edge1, value) {
  if (edge0 === edge1) return value < edge0 ? 0 : 1;
  const amount = Math.max(0, Math.min(1, (value - edge0) / (edge1 - edge0)));
  return amount * amount * (3 - 2 * amount);
}

function ellipse(x, y, cx, cy, rx, ry, feather = 0.08) {
  const distance = Math.hypot((x - cx) / rx, (y - cy) / ry);
  return smoothstep(1, 1 - feather, distance);
}

function rectangle(x, y, left, top, right, bottom, feather = 0.04) {
  const signed = Math.min(x - left, right - x, y - top, bottom - y);
  return smoothstep(0, feather, signed);
}

function union(...values) {
  return Math.max(...values);
}

function baseAlpha(ownerID, x, y) {
  switch (ownerID) {
    case "settlement":
      return union(
        rectangle(x, y, 0.015, 0.02, 0.985, 0.48, 0.045),
        rectangle(x, y, 0.015, 0.34, 0.60, 0.985, 0.055),
      );
    case "people-and-work":
      return union(
        ellipse(x, y, 0.14, 0.67, 0.15, 0.29),
        ellipse(x, y, 0.34, 0.70, 0.16, 0.30),
        ellipse(x, y, 0.61, 0.46, 0.12, 0.23),
        ellipse(x, y, 0.88, 0.74, 0.15, 0.29),
      );
    case "allocation-ground":
      return ellipse(x, y, 0.50, 0.60, 0.49, 0.38, 0.07);
    case "winter-store":
    case "protected-reserve":
    case "spring-seed":
      return union(
        rectangle(x, y, 0.08, 0.14, 0.92, 0.88, 0.08),
        ellipse(x, y, 0.50, 0.20, 0.34, 0.17, 0.12),
      );
    case "central-harvest":
      return union(
        ellipse(x, y, 0.50, 0.58, 0.49, 0.34, 0.08),
        rectangle(x, y, 0.07, 0.48, 0.93, 0.90, 0.07),
      );
    case "hands-and-grain":
      return union(
        ellipse(x, y, 0.08, 0.74, 0.18, 0.34),
        ellipse(x, y, 0.92, 0.73, 0.22, 0.36),
        ellipse(x, y, 0.50, 0.38, 0.30, 0.18),
      );
    case "foreground-occluders":
      return union(
        rectangle(x, y, 0.00, 0.00, 1.00, 0.34, 0.035),
        rectangle(x, y, 0.00, 0.18, 0.12, 0.95, 0.035),
        ellipse(x, y, 0.10, 0.90, 0.20, 0.18),
        ellipse(x, y, 0.92, 0.91, 0.24, 0.20),
      );
    case "mechanism-light":
      return union(
        ellipse(x, y, 0.29, 0.58, 0.13, 0.10, 0.20),
        ellipse(x, y, 0.50, 0.58, 0.13, 0.10, 0.20),
        ellipse(x, y, 0.71, 0.58, 0.13, 0.10, 0.20),
        ellipse(x, y, 0.50, 0.78, 0.32, 0.14, 0.18),
      );
    default:
      return 1;
  }
}

function stateAlpha(ownerID, variantID, x, y) {
  if (ownerID !== "central-harvest") return baseAlpha(ownerID, x, y);
  const scale = {
    full: 1,
    reduced: 0.82,
    scarce: 0.59,
    exhausted: 0.27,
  }[variantID] ?? 1;
  const mound = ellipse(
    x,
    y,
    0.50,
    0.67 + (1 - scale) * 0.08,
    0.45 * scale + 0.04,
    0.28 * scale + 0.035,
    0.10,
  );
  const cloth = rectangle(x, y, 0.08, 0.52, 0.92, 0.90, 0.07);
  return Math.max(mound, cloth * (variantID === "exhausted" ? 0.30 : 0.68));
}

function lightField(ownerID, x, y) {
  if (ownerID === "storm-sky") return ellipse(x, y, 0.64, 0.42, 0.45, 0.27, 0.24);
  if (ownerID === "settlement") return union(
    ellipse(x, y, 0.18, 0.77, 0.20, 0.24, 0.22),
    ellipse(x, y, 0.68, 0.48, 0.17, 0.20, 0.22),
  );
  if (ownerID === "central-harvest") return ellipse(x, y, 0.50, 0.62, 0.46, 0.29, 0.20);
  if (ownerID === "mechanism-light") return baseAlpha(ownerID, x, y);
  return ellipse(x, y, 0.50, 0.52, 0.38, 0.34, 0.22);
}

function maskPixels({ ownerID, variantID, maskType, width, height }) {
  const pixels = new Uint8Array(width * height);
  for (let y = 0; y < height; y += 1) {
    const normalizedY = (y + 0.5) / height;
    for (let x = 0; x < width; x += 1) {
      const normalizedX = (x + 0.5) / width;
      const alpha = variantID === null
        ? baseAlpha(ownerID, normalizedX, normalizedY)
        : stateAlpha(ownerID, variantID, normalizedX, normalizedY);
      let value;
      if (maskType === "alpha") value = alpha;
      else if (maskType === "depth") {
        const gradient = 0.16 + 0.68 * normalizedY + 0.16 * normalizedX;
        value = (ownerID === "storm-sky" || ownerID === "farming-landscape")
          ? gradient
          : gradient * (0.22 + 0.78 * alpha);
      } else if (maskType === "light") value = lightField(ownerID, normalizedX, normalizedY) * Math.max(0.35, alpha);
      else if (maskType === "occlusion") value = smoothstep(0.12, 0.88, alpha);
      else throw new Error(`unsupported final mask type '${maskType}'`);
      pixels[y * width + x] = clampByte(value * 255);
    }
  }
  return pixels;
}

function auxiliaryMaskPixels(mask, policyByMaskID, width, height) {
  const pixels = new Uint8Array(width * height);
  const policy = policyByMaskID.get(mask.id);
  for (let y = 0; y < height; y += 1) {
    const normalizedY = (y + 0.5) / height;
    for (let x = 0; x < width; x += 1) {
      const normalizedX = (x + 0.5) / width;
      let value;
      if (mask.maskType === "authorization") {
        value = policy.layerID === "central-harvest"
          ? Math.max(
            baseAlpha(policy.layerID, normalizedX, normalizedY),
            ...["full", "reduced", "scarce", "exhausted"].map((variantID) =>
              stateAlpha(policy.layerID, variantID, normalizedX, normalizedY)),
          )
          : baseAlpha(policy.layerID, normalizedX, normalizedY);
      } else if (mask.id === "rain-density") {
        value = rectangle(normalizedX, normalizedY, 0.025, 0.015, 0.975, 0.78, 0.05)
          * (0.36 + 0.64 * (1 - normalizedY));
      } else if (mask.id === "rain-occlusion") {
        const shelter = baseAlpha("foreground-occluders", normalizedX, normalizedY);
        value = Math.max(0, rectangle(normalizedX, normalizedY, 0.03, 0.02, 0.97, 0.96, 0.05) - shelter * 0.96);
      } else if (mask.id === "smoke-emission") {
        value = union(
          ellipse(normalizedX, normalizedY, 0.18, 0.55, 0.075, 0.13, 0.22),
          ellipse(normalizedX, normalizedY, 0.62, 0.40, 0.065, 0.13, 0.22),
        );
      } else if (mask.id === "smoke-occlusion") {
        value = union(
          ellipse(normalizedX, normalizedY, 0.20, 0.43, 0.12, 0.28, 0.25),
          ellipse(normalizedX, normalizedY, 0.64, 0.31, 0.11, 0.25, 0.25),
        ) * (1 - 0.78 * baseAlpha("foreground-occluders", normalizedX, normalizedY));
      } else {
        throw new Error(`unsupported auxiliary mask '${mask.id}'`);
      }
      pixels[y * width + x] = clampByte(value * 255);
    }
  }
  return pixels;
}

function globalLayerAlpha(layer, canvas, canvasX, canvasY) {
  const rect = pixelRect(layer.frame, canvas);
  if (canvasX < rect.x || canvasY < rect.y
      || canvasX >= rect.x + rect.width || canvasY >= rect.y + rect.height) return 0;
  const x = (canvasX - rect.x + 0.5) / rect.width;
  const y = (canvasY - rect.y + 0.5) / rect.height;
  return baseAlpha(layer.id, x, y);
}

function cleanPlate(masterPixels, canvas, layers, layerIDs, offset) {
  const selected = layers.filter((layer) => layerIDs.includes(layer.id));
  const output = new Uint8Array(masterPixels);
  for (let y = 0; y < canvas.height; y += 1) {
    for (let x = 0; x < canvas.width; x += 1) {
      const alpha = selected.reduce(
        (maximum, layer) => Math.max(maximum, globalLayerAlpha(layer, canvas, x, y)),
        0,
      );
      if (alpha <= 0) continue;
      const sampleX = Math.max(0, Math.min(canvas.width - 1, x + offset.dx));
      const sampleY = Math.max(0, Math.min(canvas.height - 1, y + offset.dy));
      const sourceOffset = (sampleY * canvas.width + sampleX) * 3;
      const targetOffset = (y * canvas.width + x) * 3;
      const mix = Math.min(0.97, alpha * 0.94);
      for (let channel = 0; channel < 3; channel += 1) {
        const alternateX = Math.max(0, Math.min(canvas.width - 1, sampleX + (channel - 1) * 9));
        const alternateOffset = (sampleY * canvas.width + alternateX) * 3 + channel;
        const fill = (masterPixels[sourceOffset + channel] * 3 + masterPixels[alternateOffset]) / 4;
        output[targetOffset + channel] = clampByte(
          masterPixels[targetOffset + channel] * (1 - mix) + fill * mix,
        );
      }
    }
  }
  return output;
}

function transformState(basePixels, authorization, ownerID, variantID, width, height) {
  const output = new Uint8Array(basePixels);
  const completed = new Set(["provisioned", "sealed", "committed", "full"]);
  const receiving = variantID === "receiving";
  const empty = variantID === "empty" || variantID === "exhausted";
  const centralStrength = {
    full: 1.06,
    reduced: 0.91,
    scarce: 0.76,
    exhausted: 0.56,
  }[variantID];
  for (let index = 0; index < authorization.byteLength; index += 1) {
    const authorizationAmount = authorization[index] / 255;
    if (authorizationAmount === 0) continue;
    const x = index % width;
    const y = Math.floor(index / width);
    const offset = index * 3;
    const red = basePixels[offset];
    const green = basePixels[offset + 1];
    const blue = basePixels[offset + 2];
    const luminance = red * 0.30 + green * 0.59 + blue * 0.11;
    let adjusted;
    if (centralStrength !== undefined) {
      const factor = centralStrength;
      adjusted = [
        red * factor + (factor > 1 ? 7 : 0),
        green * factor + (factor > 1 ? 5 : 0),
        blue * factor * 0.94,
      ];
    } else if (receiving) {
      const grainFlash = ((x * 17 + y * 31) % 101) < 5 ? 24 : 0;
      adjusted = [red * 1.04 + 14 + grainFlash, green * 1.02 + 9 + grainFlash * 0.72, blue * 0.92];
    } else if (completed.has(variantID)) {
      adjusted = [red * 1.08 + 12, green * 1.06 + 9, blue * 0.91];
    } else if (empty) {
      adjusted = [luminance * 0.50 + red * 0.20, luminance * 0.48 + green * 0.18, luminance * 0.45 + blue * 0.16];
    } else {
      adjusted = [red, green, blue];
    }
    for (let channel = 0; channel < 3; channel += 1) {
      output[offset + channel] = clampByte(
        basePixels[offset + channel] * (1 - authorizationAmount)
          + adjusted[channel] * authorizationAmount,
      );
    }
  }
  return output;
}

function stableSlug(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/gu, "-").replace(/^-|-$/gu, "");
}

async function writeGenerated(relativePath, bytes) {
  const absolute = resolveRepositoryPath(relativePath);
  if (!absolute.startsWith(`${repositoryRoot}${path.sep}`)) throw new Error("generated path escaped repository");
  await mkdir(path.dirname(absolute), { recursive: true });
  await writeFile(absolute, bytes);
  return {
    path: relativePath,
    bytes: bytes.byteLength,
    sha256: hashBytes(bytes),
  };
}

async function exactRecord(relativePath) {
  const bytes = await readFile(resolveRepositoryPath(relativePath));
  return { path: relativePath, bytes: bytes.byteLength, sha256: hashBytes(bytes) };
}

function authoredCreation(symbolicRecord, parentHashes = []) {
  return {
    mode: "authored",
    toolIDs: ["nodejs-local", "ffmpeg-local"],
    parentHashes,
    prompt: null,
    symbolicSource: { path: symbolicRecord.path, sha256: symbolicRecord.sha256 },
    seed: null,
    model: null,
  };
}

function derivedCreation() {
  return {
    mode: "derived",
    toolIDs: ["nodejs-local", "ffmpeg-local"],
    parentHashes: [{ sourceID: masterSourceID, sha256: expected.candidateSHA256 }],
    prompt: null,
    symbolicSource: null,
    seed: null,
    model: null,
  };
}

function operation({
  id,
  kind,
  outputRole,
  outputPath,
  sourceID = null,
  inputOperationIDs = [],
  alphaMaskOperationID = null,
  frame = fullFrame,
  maskType = null,
  authorizationMaskOperationID = null,
  toolIDs = ["nodejs-local", "ffmpeg-local"],
  parameters = {},
}) {
  return {
    id,
    kind,
    outputRole,
    outputPath,
    sourceID,
    inputOperationIDs,
    alphaMaskOperationID,
    frame,
    maskType,
    authorizationMaskOperationID,
    toolIDs,
    parameters,
  };
}

async function main() {
  throw new Error(
    "REJECTED_GEOMETRIC_MASK_NEGATIVE_FIXTURE: this generator used synthetic geometric masks rather than subject silhouettes; it cannot author P1.05/P1.06 assets",
  );

  /* c8 ignore start -- retained only to preserve the rejected fixture recipe */
  const [
    authorityBytes,
    backupBytes,
    backupVerificationBytes,
    candidateBytes,
    contractBytes,
    fixtureBytes,
  ] = await Promise.all([
    readFile(resolveRepositoryPath(paths.authority)),
    readFile(resolveRepositoryPath(paths.backup)),
    readFile(resolveRepositoryPath(paths.backupVerification)),
    readFile(resolveRepositoryPath(paths.candidate)),
    readFile(resolveRepositoryPath(paths.contract)),
    readFile(resolveRepositoryPath(paths.fixture)),
  ]);
  if (hashBytes(authorityBytes) !== expected.authoritySHA256) throw new Error("frozen v26 authority drifted");
  if (candidateBytes.byteLength !== expected.candidateBytes
      || hashBytes(candidateBytes) !== expected.candidateSHA256) throw new Error("v26 candidate bytes drifted");
  if (!backupBytes.equals(candidateBytes)) throw new Error("FileVault backup is not byte-identical to v26");
  const authority = JSON.parse(authorityBytes);
  const backupVerification = JSON.parse(backupVerificationBytes);
  const contract = JSON.parse(contractBytes);
  const fixture = JSON.parse(fixtureBytes);
  if (authority.status !== provisionalVisualMasterStatus
      || authority.shippingState !== "PROHIBITED"
      || authority.editorApprovalState !== "NOT_CLAIMED") {
    throw new Error("v26 authority escaped its non-shipping trust domain");
  }
  if (backupVerification.encryptedAtRest !== true
      || backupVerification.sourceID !== masterSourceID
      || backupVerification.sourceSHA256 !== expected.candidateSHA256
      || backupVerification.backupSHA256 !== expected.candidateSHA256) {
    throw new Error("backup verification record drifted");
  }

  const inventory = sceneVisualInventory(fixture);
  if (inventory.counts.total !== 86) throw new Error("Harvest SceneSpec no longer declares 86 final assets");
  const canvas = fixture.scene.sceneCanvas.canvas;
  if (canvas.width !== expected.width || canvas.height !== expected.height) throw new Error("Harvest canvas drifted");
  const masterPixels = decodeRGB(resolveRepositoryPath(paths.candidate), canvas.width, canvas.height);
  const policyByMaskID = new Map(contract.stateVariantPolicies.map((policy) => [policy.authorizationMaskID, policy]));
  const layerByID = new Map(fixture.scene.layers.map((layer) => [layer.id, layer]));

  const symbolicDocument = {
    schemaVersion: 1,
    status: "CODEX_PROVISIONAL_NON_SHIPPING_AUTHORING_SPEC",
    shippingState: "PROHIBITED",
    editorApprovalState: "NOT_CLAIMED",
    authority: {
      path: paths.authority,
      sha256: expected.authoritySHA256,
    },
    master: {
      path: paths.candidate,
      bytes: expected.candidateBytes,
      sha256: expected.candidateSHA256,
      width: expected.width,
      height: expected.height,
    },
    coordinateSpace: "Each mask is authored in the exact normalized SceneSpec frame of its owner; rasterization samples pixel centres deterministically.",
    layerSeparation: fixture.scene.layers.map((layer) => ({
      id: layer.id,
      frame: layer.frame,
      depth: layer.depth,
      alphaRecipe: ["storm-sky", "farming-landscape"].includes(layer.id)
        ? "opaque exact-master plate"
        : layer.id === "mechanism-light"
          ? "four causal radial fields; black technical screen plate preserves exact recomposition"
          : `${layer.id} authored soft union mask`,
    })),
    stateTransforms: contract.stateVariantPolicies.map((policy) => ({
      layerID: policy.layerID,
      variantID: policy.variantID,
      authorizationMaskID: policy.authorizationMaskID,
      rule: policy.layerID === "central-harvest"
        ? "deterministic mound-scale and local material transform inside the authorization mask"
        : "deterministic empty, receiving or completed material response inside the authorization mask",
    })),
    cleanPlateRecipes: contract.cleanPlateCoverage.map((plate) => ({
      id: plate.id,
      coversLayerIDs: plate.coversLayerIDs,
      rule: "soft authored owner masks replace covered pixels with deterministic nearby samples; no generative redraw",
    })),
    maskRules: {
      alpha: "soft geometric unions with pixel-centre sampling",
      depth: "owner silhouette multiplied by an authored diagonal depth ramp",
      light: "bounded radial fields tied to hearth, destination and harvest mechanisms",
      occlusion: "thresholded owner silhouette",
      atmosphere: "bounded rain and smoke source/occlusion fields",
      authorization: "union of every permitted owner-state silhouette; no state pixel may change where its value is zero",
    },
    knownLimits: [
      "The clean plates use deterministic local sampling and require later editor inspection for parallax disocclusion quality.",
      "The black mechanism-light plate preserves byte-exact recomposition; integrated runtime focus light remains an artistic gate.",
      "Geometric masks are Codex-authored provisional masks and do not constitute editor asset approval.",
    ],
  };
  const symbolicRecord = await writeGenerated(
    paths.symbolic,
    Buffer.from(`${JSON.stringify(symbolicDocument, null, 2)}\n`),
  );

  const sources = [];
  const operations = [];
  const sourceByID = new Map();
  const operationByAssetPath = new Map();
  const addSource = (source) => {
    if (sourceByID.has(source.id)) throw new Error(`duplicate source '${source.id}'`);
    sourceByID.set(source.id, source);
    sources.push(source);
  };
  const addOperation = (value) => {
    operations.push(value);
    if (["scene-layer", "scene-mask", "reduce-motion-plate"].includes(value.outputRole)) {
      operationByAssetPath.set(value.outputPath, value);
    }
  };

  addSource({
    id: masterSourceID,
    kind: "provisional-master",
    path: paths.candidate,
    bytes: expected.candidateBytes,
    sha256: expected.candidateSHA256,
    dimensions: { width: canvas.width, height: canvas.height },
    creation: authoredCreation({ path: paths.authority, sha256: expected.authoritySHA256 }),
    rights,
    provisionalAuthority: {
      path: paths.authority,
      sha256: expected.authoritySHA256,
      status: provisionalVisualMasterStatus,
    },
  });

  const maskSourceRecordByAssetPath = new Map();
  for (const asset of inventory.assets.filter(({ kind }) => kind === "scene-mask")) {
    const slug = stableSlug(`${asset.ownerID}-${asset.variantID ?? "base"}-${asset.maskType}`);
    const relativePath = `${paths.sourceRoot}/masks/${slug}.pgm`;
    const mask = maskPixels({
      ownerID: asset.ownerID,
      variantID: asset.variantID,
      maskType: asset.maskType,
      width: asset.pixelRect.width,
      height: asset.pixelRect.height,
    });
    const record = await writeGenerated(relativePath, pgm(asset.pixelRect.width, asset.pixelRect.height, mask));
    const sourceID = `source-${slug}`;
    addSource({
      id: sourceID,
      kind: "authored-mask",
      ...record,
      dimensions: { width: asset.pixelRect.width, height: asset.pixelRect.height },
      creation: authoredCreation(symbolicRecord, [{ sourceID: masterSourceID, sha256: expected.candidateSHA256 }]),
      rights,
    });
    const maskOperation = operation({
      id: `mask-${slug}`,
      kind: "normalize-mask",
      outputRole: asset.kind,
      outputPath: asset.assetPath,
      sourceID,
      frame: asset.frame,
      maskType: asset.maskType,
    });
    addOperation(maskOperation);
    maskSourceRecordByAssetPath.set(asset.assetPath, { sourceID, operationID: maskOperation.id, mask });
  }

  const auxiliaryOperationByID = new Map();
  for (const mask of contract.auxiliaryMasks) {
    const rect = pixelRect(mask.frame, canvas);
    const pixels = auxiliaryMaskPixels(mask, policyByMaskID, rect.width, rect.height);
    const relativePath = `${paths.sourceRoot}/control-masks/${mask.id}.pgm`;
    const record = await writeGenerated(relativePath, pgm(rect.width, rect.height, pixels));
    const sourceID = `source-control-${mask.id}`;
    addSource({
      id: sourceID,
      kind: "authored-mask",
      ...record,
      dimensions: { width: rect.width, height: rect.height },
      creation: authoredCreation(symbolicRecord, [{ sourceID: masterSourceID, sha256: expected.candidateSHA256 }]),
      rights,
    });
    const controlOperation = operation({
      id: `control-${mask.id}`,
      kind: "normalize-mask",
      outputRole: "control-mask",
      outputPath: mask.workingPath,
      sourceID,
      frame: mask.frame,
      maskType: mask.maskType,
    });
    addOperation(controlOperation);
    auxiliaryOperationByID.set(mask.id, { operationID: controlOperation.id, pixels });
  }

  const cleanOffsets = new Map([
    ["clean-world-background", { dx: 238, dy: -310 }],
    ["clean-settlement-plane", { dx: -187, dy: -145 }],
    ["clean-allocation-foreground", { dx: 163, dy: -198 }],
  ]);
  const cleanSourceByID = new Map();
  for (const plate of contract.cleanPlateCoverage) {
    const pixels = cleanPlate(
      masterPixels,
      canvas,
      fixture.scene.layers,
      plate.coversLayerIDs,
      cleanOffsets.get(plate.id),
    );
    const relativePath = `${paths.sourceRoot}/clean-plates/${plate.id}.ppm`;
    const record = await writeGenerated(relativePath, ppm(canvas.width, canvas.height, pixels));
    const sourceID = `source-${plate.id}`;
    addSource({
      id: sourceID,
      kind: "clean-plate",
      ...record,
      dimensions: { width: canvas.width, height: canvas.height },
      creation: derivedCreation(),
      rights,
    });
    addOperation(operation({
      id: plate.id,
      kind: "normalize-raster",
      outputRole: "clean-plate",
      outputPath: plate.workingPath,
      sourceID,
      frame: plate.frame,
    }));
    cleanSourceByID.set(plate.id, { sourceID, pixels });
  }

  const blackPixels = new Uint8Array(canvas.width * canvas.height * 3);
  const blackRecord = await writeGenerated(
    `${paths.sourceRoot}/layer-plates/mechanism-light-black.ppm`,
    ppm(canvas.width, canvas.height, blackPixels),
  );
  const blackSourceID = "source-mechanism-light-black";
  addSource({
    id: blackSourceID,
    kind: "layer-plate",
    ...blackRecord,
    dimensions: { width: canvas.width, height: canvas.height },
    creation: derivedCreation(),
    rights,
  });

  const stateSourceByKey = new Map();
  for (const policy of contract.stateVariantPolicies) {
    const layer = layerByID.get(policy.layerID);
    const rect = pixelRect(layer.frame, canvas);
    const basePixels = cropRGB(masterPixels, canvas, rect);
    const authorization = auxiliaryOperationByID.get(policy.authorizationMaskID).pixels;
    const transformed = transformState(
      basePixels,
      authorization,
      policy.layerID,
      policy.variantID,
      rect.width,
      rect.height,
    );
    const key = `${policy.layerID}.${policy.variantID}`;
    const slug = stableSlug(`${policy.layerID}-${policy.variantID}`);
    const relativePath = `${paths.sourceRoot}/state-plates/${slug}.ppm`;
    const record = await writeGenerated(relativePath, ppm(rect.width, rect.height, transformed));
    const sourceID = `source-state-${slug}`;
    addSource({
      id: sourceID,
      kind: "state-plate",
      ...record,
      dimensions: { width: rect.width, height: rect.height },
      creation: derivedCreation(),
      rights,
    });
    stateSourceByKey.set(key, sourceID);
  }

  for (const asset of inventory.assets.filter(({ kind }) => kind === "scene-layer")) {
    const key = `${asset.ownerID}.${asset.variantID ?? "base"}`;
    const slug = stableSlug(key);
    const alphaAsset = inventory.assets.find((candidate) => candidate.kind === "scene-mask"
      && candidate.ownerID === asset.ownerID
      && candidate.variantID === asset.variantID
      && candidate.maskType === "alpha");
    const alphaMaskOperationID = alphaAsset
      ? maskSourceRecordByAssetPath.get(alphaAsset.assetPath).operationID
      : null;
    const sourceID = asset.variantID !== null
      ? stateSourceByKey.get(`${asset.ownerID}.${asset.variantID}`)
      : asset.ownerID === "mechanism-light"
        ? blackSourceID
        : masterSourceID;
    const workingID = `working-${slug}`;
    addOperation(operation({
      id: workingID,
      kind: alphaMaskOperationID ? "extract-layer" : "normalize-raster",
      outputRole: "working-layer",
      outputPath: `work/encoded-inputs/${slug}.png`,
      sourceID,
      alphaMaskOperationID,
      frame: asset.frame,
    }));
    const policy = asset.variantID === null
      ? null
      : contract.stateVariantPolicies.find((candidate) => candidate.layerID === asset.ownerID
        && candidate.variantID === asset.variantID);
    const authorizationMaskOperationID = policy
      ? auxiliaryOperationByID.get(policy.authorizationMaskID).operationID
      : null;
    addOperation(operation({
      id: `asset-${slug}`,
      kind: "encode-heif",
      outputRole: asset.kind,
      outputPath: asset.assetPath,
      inputOperationIDs: [workingID],
      frame: asset.frame,
      authorizationMaskOperationID,
      toolIDs: ["apple-sips"],
      parameters: { formatOptions: "best" },
    }));
  }

  for (const asset of inventory.assets.filter(({ kind }) => kind === "reduce-motion-plate")) {
    const foreground = asset.ownerID === "foreground-occlusion";
    const workingID = `working-reduce-${stableSlug(asset.ownerID)}`;
    const foregroundAlpha = inventory.assets.find((candidate) => candidate.kind === "scene-mask"
      && candidate.ownerID === "foreground-occluders"
      && candidate.variantID === null
      && candidate.maskType === "alpha");
    addOperation(operation({
      id: workingID,
      kind: foreground ? "extract-layer" : "normalize-raster",
      outputRole: "working-layer",
      outputPath: `work/encoded-inputs/reduce-${stableSlug(asset.ownerID)}.png`,
      sourceID: foreground
        ? masterSourceID
        : cleanSourceByID.get("clean-allocation-foreground").sourceID,
      alphaMaskOperationID: foreground
        ? maskSourceRecordByAssetPath.get(foregroundAlpha.assetPath).operationID
        : null,
      frame: asset.frame,
    }));
    addOperation(operation({
      id: `asset-reduce-${stableSlug(asset.ownerID)}`,
      kind: "encode-heif",
      outputRole: asset.kind,
      outputPath: asset.assetPath,
      inputOperationIDs: [workingID],
      frame: asset.frame,
      toolIDs: ["apple-sips"],
      parameters: { formatOptions: "best" },
    }));
  }

  const baseLayers = inventory.assets
    .filter((asset) => asset.kind === "scene-layer" && asset.variantID === null)
    .sort((left, right) => left.order - right.order);
  const dag = {
    schemaVersion: 1,
    id: "harvest-v26-provisional-visual-asset-dag",
    status: "CODEX_PROVISIONAL_NON_SHIPPING_INPUTS_LOCKED",
    buildMode: visualProductionBuildModes.codexProvisional,
    contract: {
      path: paths.contract,
      sha256: canonicalSHA256(contract),
    },
    masterSourceID,
    sources,
    operations,
    recomposition: {
      outputPath: "review/recomposition-v26.png",
      diffPath: "review/recomposition-v26-diff.png",
      baseLayerOperationIDs: baseLayers.map((asset) => operationByAssetPath.get(asset.assetPath).id),
      masterSourceID,
    },
    rejectedCandidates: [],
    backup: {
      sourceID: masterSourceID,
      status: "HASH_VERIFIED",
      storageClass: "ENCRYPTED_EXISTING_PRIVATE_STORAGE",
      locator: `filevault-local:${paths.backup}`,
      verificationRecord: {
        path: paths.backupVerification,
        sha256: hashBytes(backupVerificationBytes),
      },
      bytes: expected.candidateBytes,
      sha256: expected.candidateSHA256,
    },
  };
  const dagRecord = await writeGenerated(paths.dag, Buffer.from(`${JSON.stringify(dag, null, 2)}\n`));
  const sourceInventory = {
    schemaVersion: 1,
    status: "CODEX_PROVISIONAL_NON_SHIPPING_SOURCE_INVENTORY",
    shippingState: "PROHIBITED",
    editorApprovalState: "NOT_CLAIMED",
    authority: { path: paths.authority, sha256: expected.authoritySHA256 },
    dag: { path: paths.dag, bytes: dagRecord.bytes, sha256: dagRecord.sha256 },
    master: await exactRecord(paths.candidate),
    backup: await exactRecord(paths.backup),
    counts: {
      finalAssets: inventory.counts,
      sources: sources.length,
      operations: operations.length,
    },
    sources: sources.map(({ id, kind, path: sourcePath, bytes, sha256, dimensions }) => ({
      id,
      kind,
      path: sourcePath,
      bytes,
      sha256,
      dimensions,
    })),
  };
  const inventoryRecord = await writeGenerated(
    paths.sourceInventory,
    Buffer.from(`${JSON.stringify(sourceInventory, null, 2)}\n`),
  );

  process.stdout.write(
    `Authored ${sources.length} exact v26-bound sources and ${operations.length} DAG operations for ${inventory.counts.total} final Harvest files.\n`
      + `DAG ${dagRecord.sha256}; source inventory ${inventoryRecord.sha256}. Editor and shipping approval remain absent.\n`,
  );
  /* c8 ignore stop */
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`);
  process.exitCode = 1;
});
