import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  buildVisualAssetDAG,
  canonicalJSON,
  canonicalSHA256,
  createProvisionalVisualMasterAuthority,
  probeRaster,
  provisionalVisualMasterStatus,
  sceneVisualInventory,
  validateVisualProductionContract,
  verifyVisualAssetReceipt,
  visualProductionBuildModes,
} from "../src/visual-asset-production.mjs";

const repositoryRoot = fileURLToPath(new URL("../../..", import.meta.url));
const fixturePath = path.join(repositoryRoot, "native/phase1/fixtures/harvest-option-1.scene.json");
const contractPath = path.join(repositoryRoot, "native/design/phase1/harvest/layer-production-contract.json");
const costRegistryPath = path.join(repositoryRoot, "native/tooling/registries/cost-license.json");
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const fullFrame = { x: 0, y: 0, width: 1, height: 1 };

test("tiled HEIF probing reports the primary image canvas rather than a 512-pixel grid tile", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-heif-grid-"));
  try {
    const width = 520;
    const height = 777;
    const pixels = new Uint8Array(width * height * 3);
    for (let index = 0; index < pixels.byteLength; index += 3) {
      pixels[index] = 31;
      pixels[index + 1] = 67;
      pixels[index + 2] = 103;
    }
    const source = path.join(root, "source.ppm");
    const output = path.join(root, "output.heif");
    await writeFile(source, ppm(width, height, pixels));
    execFileSync("/usr/bin/sips", [
      "-s", "format", "heic",
      "-s", "formatOptions", "best",
      source,
      "--out", output,
    ]);
    assert.deepEqual(probeRaster(output), {
      width,
      height,
      pixelFormat: "rgba",
      formatName: "heic",
    });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("Harvest production contract binds the exact 86-file SceneSpec inventory", async () => {
  const [fixtureBytes, contract, costRegistry] = await Promise.all([
    readFile(fixturePath),
    readFile(contractPath, "utf8").then(JSON.parse),
    readFile(costRegistryPath, "utf8").then(JSON.parse),
  ]);
  const fixture = JSON.parse(fixtureBytes);
  const result = await validateVisualProductionContract({
    contract,
    fixture,
    fixtureBytes,
    costRegistry,
    repositoryRoot,
    contractRepositoryPath: "native/design/phase1/harvest/layer-production-contract.json",
  });

  assert.deepEqual(result.inventory.counts, {
    total: 86,
    baseLayers: 12,
    baseMasks: 27,
    stateFiles: 45,
    reduceMotionPlates: 2,
  });
  assert.equal(result.contract.schemaVersion, 2);
  assert.deepEqual(
    result.contract.disocclusionUnderlays.map(({ layerID, coverageMode }) => [layerID, coverageMode]),
    [
      ["settlement", "RAIL_BOUNDED"],
      ["people-and-work", "RAIL_BOUNDED"],
      ["allocation-ground", "RAIL_BOUNDED"],
      ["winter-store", "RAIL_BOUNDED"],
      ["protected-reserve", "RAIL_BOUNDED"],
      ["spring-seed", "RAIL_BOUNDED"],
      ["central-harvest", "FULL_STATE_AND_RAIL"],
      ["foreground-occluders", "RAIL_BOUNDED"],
    ],
  );
  assert.deepEqual(result.contract.disocclusionExemptions, [{
    layerID: "hands-and-grain",
    reasonCode: "ZERO_RELATIVE_MOTION_NO_REVEAL",
    relativeMotion: "ZERO",
    revealsBackground: false,
  }]);
  assert.ok(!result.contract.disocclusionUnderlays.some(({ layerID }) => layerID === "mechanism-light"));
  const centralRecipe = result.contract.disocclusionUnderlays.find(({ layerID }) => layerID === "central-harvest").recipe;
  assert.deepEqual(centralRecipe.cropPixels, { x: 192, y: 1752, width: 896, height: 896 });
  assert.deepEqual(centralRecipe.subjectMask.cropLocalBoundsPixels, { minX: 124, minY: 437, maxX: 783, maxY: 834 });
  assert.equal(centralRecipe.usableDonorPixelCount, 148493);
  assert.equal(result.contract.productionRules.autoMasksRequireArtReview, true);
  assert.equal(result.contract.productionRules.pipelineCannotApproveShipping, true);
  assert.equal(result.contract.productionRules.codexProvisionalMasterMayBuildDevelopmentDAG, true);
  assert.equal(result.contract.productionRules.provisionalOutputsForbiddenFromShipping, true);
  assert.equal(result.contract.recompositionGate.statePixelsOutsideAuthorizationMustMatch, true);
});

test("v2 disocclusion coverage rejects a missing alpha-normal layer and a reveal-capable exemption", async () => {
  const [fixtureBytes, originalContract, costRegistry] = await Promise.all([
    readFile(fixturePath),
    readFile(contractPath, "utf8").then(JSON.parse),
    readFile(costRegistryPath, "utf8").then(JSON.parse),
  ]);
  const fixture = JSON.parse(fixtureBytes);
  const contract = structuredClone(originalContract);
  contract.disocclusionUnderlays = contract.disocclusionUnderlays.filter(({ layerID }) => layerID !== "settlement");
  contract.disocclusionExemptions[0].revealsBackground = true;
  await assert.rejects(
    validateVisualProductionContract({ contract, fixture, fixtureBytes, costRegistry, repositoryRoot }),
    /exemption requires zero relative motion and no background reveal[\s\S]*incomplete alpha-normal disocclusion coverage/u,
  );
});

test("contract rejects fixture drift and a pipeline that claims artistic approval", async () => {
  const [fixtureBytes, originalContract, costRegistry] = await Promise.all([
    readFile(fixturePath),
    readFile(contractPath, "utf8").then(JSON.parse),
    readFile(costRegistryPath, "utf8").then(JSON.parse),
  ]);
  const fixture = JSON.parse(fixtureBytes);
  const contract = structuredClone(originalContract);
  contract.productionRules.pipelineCannotApproveShipping = false;
  contract.sceneFixtureSHA256 = "0".repeat(64);

  await assert.rejects(
    validateVisualProductionContract({ contract, fixture, fixtureBytes, costRegistry, repositoryRoot }),
    /fixture bytes drifted[\s\S]*pipelineCannotApproveShipping/u,
  );
});

function ppm(width, height, pixels) {
  return Buffer.concat([Buffer.from(`P6\n${width} ${height}\n255\n`), Buffer.from(pixels)]);
}

function pgm(width, height, pixels) {
  return Buffer.concat([Buffer.from(`P5\n${width} ${height}\n255\n`), Buffer.from(pixels)]);
}

function exactRecord(bytes) {
  return { bytes: bytes.byteLength, sha256: sha256(bytes) };
}

function authoredCreation(symbolicPath, symbolicHash) {
  return {
    mode: "authored",
    toolIDs: ["nodejs-local", "ffmpeg-local"],
    parentHashes: [],
    prompt: null,
    symbolicSource: { path: symbolicPath, sha256: symbolicHash },
    seed: null,
    model: null,
  };
}

function derivedCreation(parentID, parentHash) {
  return {
    mode: "derived",
    toolIDs: ["nodejs-local", "ffmpeg-local"],
    parentHashes: [{ sourceID: parentID, sha256: parentHash }],
    prompt: null,
    symbolicSource: null,
    seed: null,
    model: null,
  };
}

const rights = {
  status: "COMMERCIAL_USE_CLEARED",
  incrementalCostNOK: 0,
  license: "Project-owned deterministic test fixture",
};

function operation({
  id,
  kind,
  outputRole,
  outputPath,
  sourceID,
  maskType = null,
  alphaMaskOperationID = null,
  authorizationMaskOperationID = null,
}) {
  return {
    id,
    kind,
    outputRole,
    outputPath,
    sourceID,
    inputOperationIDs: [],
    alphaMaskOperationID,
    frame: fullFrame,
    maskType,
    authorizationMaskOperationID,
    toolIDs: ["nodejs-local", "ffmpeg-local"],
    parameters: {},
  };
}

async function makeBuildFixture(root) {
  const fixture = {
    scene: {
      id: "test-scene",
      sceneCanvas: { canvas: { width: 4, height: 4 } },
      layers: [
        {
          id: "background",
          order: 0,
          assetPath: "assets/background.png",
          frame: fullFrame,
          blendMode: "normal",
          opacity: 1,
          masks: {},
          stateVariants: [],
        },
        {
          id: "object",
          order: 1,
          assetPath: "assets/object.png",
          frame: fullFrame,
          blendMode: "normal",
          opacity: 1,
          masks: {
            alphaMaskAssetPath: "assets/object-alpha.png",
            depthMaskAssetPath: "assets/object-depth.png",
            lightMaskAssetPath: "assets/object-light.png",
            occlusionMaskAssetPath: "assets/object-occlusion.png",
          },
          stateVariants: [{
            id: "changed",
            assetPath: "assets/object-changed.png",
            masks: { alphaMaskAssetPath: "assets/object-changed-alpha.png" },
          }],
        },
      ],
      reduceMotionComposition: {
        strata: [
          { id: "underlay", kind: "staticPlate", assetPath: "assets/static-underlay.png" },
          { id: "foreground", kind: "staticPlate", assetPath: "assets/static-foreground.png" },
        ],
      },
    },
  };
  const fixtureBytes = Buffer.from(JSON.stringify(fixture));
  const inventory = sceneVisualInventory(fixture);
  const contract = {
    schemaVersion: 1,
    id: "test-layer-production",
    status: "NON_SHIPPING_PRODUCTION_CONTRACT",
    sceneFixturePath: "fixture.json",
    sceneFixtureSHA256: sha256(fixtureBytes),
    expectedSceneID: "test-scene",
    canvas: { width: 4, height: 4 },
    requiredFinalAssets: inventory.counts,
    toolchain: [
      { toolID: "nodejs-local", version: process.versions.node, license: "MIT" },
      { toolID: "ffmpeg-local", version: "8.1.2", license: "GPL-3.0-or-later local command-line tool; outputs are not linked to or derived from FFmpeg code" },
      { toolID: "apple-sips", version: "316", license: "Apple macOS Software License Agreement" },
    ],
    cleanPlateCoverage: [{
      id: "clean-object",
      workingPath: "work/clean-object.png",
      frame: fullFrame,
      coversLayerIDs: ["object"],
    }],
    auxiliaryMasks: [
      { id: "rain-density", maskType: "atmosphere", atmosphereKind: "rain", workingPath: "work/rain-density.png", frame: fullFrame, purpose: "Rain density." },
      { id: "rain-occlusion", maskType: "atmosphere", atmosphereKind: "rain", workingPath: "work/rain-occlusion.png", frame: fullFrame, purpose: "Rain occlusion." },
      { id: "smoke-emission", maskType: "atmosphere", atmosphereKind: "smoke", workingPath: "work/smoke-emission.png", frame: fullFrame, purpose: "Smoke emission." },
      { id: "smoke-occlusion", maskType: "atmosphere", atmosphereKind: "smoke", workingPath: "work/smoke-occlusion.png", frame: fullFrame, purpose: "Smoke occlusion." },
      { id: "object-change", maskType: "authorization", workingPath: "work/object-change.png", frame: fullFrame, purpose: "One local state change." },
    ],
    stateVariantPolicies: [{
      layerID: "object",
      variantID: "changed",
      authorizationMaskID: "object-change",
      allowedAlphaBounds: fullFrame,
      maximumAuthorizedAreaFraction: 0.25,
    }],
    recompositionGate: {
      maxChannelError: 0,
      maxMeanAbsoluteError: 0,
      minimumExactPixelFraction: 1,
      statePixelsOutsideAuthorizationMustMatch: true,
    },
    encodingGate: {
      maxChannelError: 96,
      maxMeanAbsoluteError: 6,
      deterministicByteReplayRequired: true,
    },
    productionRules: {
      editorApprovedMasterRequiredForShipping: true,
      independentlyGeneratedLayersForbidden: true,
      autoMasksRequireArtReview: true,
      losslessWorkingIntermediates: true,
      pipelineCannotApproveShipping: true,
      upscalingForbidden: true,
      codexProvisionalMasterMayBuildDevelopmentDAG: true,
      provisionalOutputsForbiddenFromShipping: true,
    },
  };
  const costRegistry = {
    entries: [
      {
        id: "nodejs-local",
        category: "tool",
        version: process.versions.node,
        incrementalCostNOK: 0,
        billingCredentialRequired: false,
        commercialUse: "allowed",
        license: "MIT",
      },
      {
        id: "ffmpeg-local",
        category: "tool",
        version: "8.1.2",
        incrementalCostNOK: 0,
        billingCredentialRequired: false,
        commercialUse: "allowed",
        license: "GPL-3.0-or-later local command-line tool; outputs are not linked to or derived from FFmpeg code",
      },
      {
        id: "apple-sips",
        category: "tool",
        version: "316",
        incrementalCostNOK: 0,
        billingCredentialRequired: false,
        commercialUse: "allowed",
        license: "Apple macOS Software License Agreement",
      },
    ],
  };

  const masterPixels = [];
  for (let y = 0; y < 4; y += 1) {
    for (let x = 0; x < 4; x += 1) masterPixels.push(30 + x * 20, 40 + y * 25, 90 + x * 4 + y * 3);
  }
  const masterBytes = ppm(4, 4, masterPixels);
  const changedPixels = [...masterPixels];
  changedPixels[(1 * 4 + 1) * 3] = 240;
  const changedBytes = ppm(4, 4, changedPixels);
  const alpha = Uint8Array.from({ length: 16 }, (_, index) => [5, 6, 9, 10].includes(index) ? 255 : 0);
  const depth = Uint8Array.from({ length: 16 }, (_, index) => index * 16);
  const onePixel = Uint8Array.from({ length: 16 }, (_, index) => index === 5 ? 255 : 0);
  const masterRecord = exactRecord(masterBytes);
  const editorApprovalDocument = {
    schemaVersion: 1,
    status: "EDITOR_APPROVED_AS_PRODUCTION_MASTER",
    authority: "editor-in-chief",
    approvedAt: "2026-07-25T08:00:00Z",
    decisionReference: "test-only-editor-master-decision",
    contract: {
      path: "contract.json",
      sha256: canonicalSHA256(contract),
    },
    sceneFixture: {
      path: contract.sceneFixturePath,
      sha256: contract.sceneFixtureSHA256,
      sceneID: fixture.scene.id,
      canvas: contract.canvas,
    },
    master: {
      sourceID: "master",
      path: "master.ppm",
      ...masterRecord,
      width: 4,
      height: 4,
    },
    approvedScope: ["PRODUCTION_MASTER_PIXELS", "LAYER_DAG_INPUT"],
    shippingState: "REQUIRES_SEPARATE_ASSET_AND_PACKAGE_APPROVAL",
  };
  const editorApprovalBytes = Buffer.from(`${JSON.stringify(editorApprovalDocument, null, 2)}\n`);
  const backupVerification = Buffer.from(`${JSON.stringify({
    schemaVersion: 1,
    status: "HASH_VERIFIED",
    sourceID: "master",
    sourceBytes: masterRecord.bytes,
    sourceSHA256: masterRecord.sha256,
    backupBytes: masterRecord.bytes,
    backupSHA256: masterRecord.sha256,
    encryptedAtRest: false,
  })}\n`);
  const files = {
    "master.ppm": masterBytes,
    "master-backup.ppm": masterBytes,
    "changed.ppm": changedBytes,
    "alpha.pgm": pgm(4, 4, alpha),
    "depth.pgm": pgm(4, 4, depth),
    "one-pixel.pgm": pgm(4, 4, onePixel),
    "source-record.json": Buffer.from("{\"authoring\":\"deterministic fixture\"}\n"),
    "approval.json": editorApprovalBytes,
    "backup-verification.json": backupVerification,
  };
  for (const [relative, bytes] of Object.entries(files)) await writeFile(path.join(root, relative), bytes);
  const sourceRecordHash = sha256(files["source-record.json"]);
  const approvalHash = sha256(files["approval.json"]);
  const source = (id, kind, fileName, creation, editorApproval = undefined) => ({
    id,
    kind,
    path: fileName,
    ...exactRecord(files[fileName]),
    dimensions: { width: 4, height: 4 },
    creation,
    rights,
    ...(editorApproval ? { editorApproval } : {}),
  });
  const sources = [
    source("master", "approved-master", "master.ppm", authoredCreation("source-record.json", sourceRecordHash), {
      path: "approval.json",
      sha256: approvalHash,
      status: "EDITOR_APPROVED_AS_PRODUCTION_MASTER",
    }),
    source("changed", "state-plate", "changed.ppm", derivedCreation("master", masterRecord.sha256)),
    source("alpha", "authored-mask", "alpha.pgm", authoredCreation("source-record.json", sourceRecordHash)),
    source("depth", "authored-mask", "depth.pgm", authoredCreation("source-record.json", sourceRecordHash)),
    source("one-pixel", "authored-mask", "one-pixel.pgm", authoredCreation("source-record.json", sourceRecordHash)),
  ];
  const operations = [
    operation({ id: "background", kind: "normalize-raster", outputRole: "scene-layer", outputPath: "assets/background.png", sourceID: "master" }),
    operation({ id: "object-alpha", kind: "normalize-mask", outputRole: "scene-mask", outputPath: "assets/object-alpha.png", sourceID: "alpha", maskType: "alpha" }),
    operation({ id: "object-depth", kind: "normalize-mask", outputRole: "scene-mask", outputPath: "assets/object-depth.png", sourceID: "depth", maskType: "depth" }),
    operation({ id: "object-light", kind: "normalize-mask", outputRole: "scene-mask", outputPath: "assets/object-light.png", sourceID: "one-pixel", maskType: "light" }),
    operation({ id: "object-occlusion", kind: "normalize-mask", outputRole: "scene-mask", outputPath: "assets/object-occlusion.png", sourceID: "one-pixel", maskType: "occlusion" }),
    operation({ id: "object", kind: "extract-layer", outputRole: "scene-layer", outputPath: "assets/object.png", sourceID: "master", alphaMaskOperationID: "object-alpha" }),
    operation({ id: "changed-alpha", kind: "normalize-mask", outputRole: "scene-mask", outputPath: "assets/object-changed-alpha.png", sourceID: "alpha", maskType: "alpha" }),
    operation({ id: "change-authorization", kind: "normalize-mask", outputRole: "control-mask", outputPath: "work/object-change.png", sourceID: "one-pixel", maskType: "authorization" }),
    operation({ id: "changed", kind: "extract-layer", outputRole: "scene-layer", outputPath: "assets/object-changed.png", sourceID: "changed", alphaMaskOperationID: "changed-alpha", authorizationMaskOperationID: "change-authorization" }),
    operation({ id: "underlay", kind: "normalize-raster", outputRole: "reduce-motion-plate", outputPath: "assets/static-underlay.png", sourceID: "master" }),
    operation({ id: "foreground", kind: "normalize-raster", outputRole: "reduce-motion-plate", outputPath: "assets/static-foreground.png", sourceID: "master" }),
    operation({ id: "clean-object", kind: "normalize-raster", outputRole: "clean-plate", outputPath: "work/clean-object.png", sourceID: "master" }),
    operation({ id: "rain-density", kind: "normalize-mask", outputRole: "control-mask", outputPath: "work/rain-density.png", sourceID: "one-pixel", maskType: "atmosphere" }),
    operation({ id: "rain-occlusion", kind: "normalize-mask", outputRole: "control-mask", outputPath: "work/rain-occlusion.png", sourceID: "one-pixel", maskType: "atmosphere" }),
    operation({ id: "smoke-emission", kind: "normalize-mask", outputRole: "control-mask", outputPath: "work/smoke-emission.png", sourceID: "one-pixel", maskType: "atmosphere" }),
    operation({ id: "smoke-occlusion", kind: "normalize-mask", outputRole: "control-mask", outputPath: "work/smoke-occlusion.png", sourceID: "one-pixel", maskType: "atmosphere" }),
    {
      id: "background-heif",
      kind: "encode-heif",
      outputRole: "working-layer",
      outputPath: "work/background.heif",
      sourceID: null,
      inputOperationIDs: ["background"],
      alphaMaskOperationID: null,
      frame: fullFrame,
      maskType: null,
      authorizationMaskOperationID: null,
      toolIDs: ["apple-sips"],
      parameters: { formatOptions: "best" },
    },
  ];
  const dag = {
    schemaVersion: 1,
    id: "test-visual-dag",
    status: "PRODUCTION_INPUTS_LOCKED",
    buildMode: visualProductionBuildModes.editorApproved,
    contract: { path: "contract.json", sha256: canonicalSHA256(contract) },
    masterSourceID: "master",
    sources,
    operations,
    recomposition: {
      outputPath: "review/recomposition.png",
      diffPath: "review/recomposition-diff.png",
      baseLayerOperationIDs: ["background", "object"],
      masterSourceID: "master",
    },
    rejectedCandidates: [],
    backup: {
      sourceID: "master",
      status: "HASH_VERIFIED",
      storageClass: "TEST_REPOSITORY_COPY",
      locator: "repository-test:master-backup.ppm",
      verificationRecord: {
        path: "backup-verification.json",
        sha256: sha256(backupVerification),
      },
      ...masterRecord,
    },
  };
  return { fixture, fixtureBytes, contract, costRegistry, dag };
}

async function convertBuildFixtureToV2Underlay(data, root, { pending = false } = {}) {
  const master = data.dag.sources.find(({ id }) => id === "master");
  const masterBytes = await readFile(path.join(root, master.path));
  const underlayPath = "underlay.png";
  const sourceAuthorityPath = "underlay-source-authority.json";
  const sourceAuthorityBytes = Buffer.from("{\"status\":\"NON_SHIPPING_TEST_SOURCE_INPUT\"}\n");
  await writeFile(path.join(root, underlayPath), masterBytes);
  await writeFile(path.join(root, sourceAuthorityPath), sourceAuthorityBytes);
  data.contract.schemaVersion = 2;
  delete data.contract.cleanPlateCoverage;
  data.contract.disocclusionCoverageRule = {
    eligibleLayerRule: "ALPHA_MASKED_NORMAL_BLEND",
    excludedBlendModes: ["screen"],
  };
  const recipe = pending ? { status: "PENDING_MEASUREMENT" } : {
    status: "MEASURED",
    toolIDs: ["nodejs-local", "ffmpeg-local"],
    sourceMaster: { path: "master.ppm", sha256: master.sha256 },
    cropPixels: { x: 0, y: 0, width: 4, height: 4 },
    targetFileName: underlayPath,
    sourceAuthority: { path: sourceAuthorityPath, sha256: sha256(sourceAuthorityBytes) },
    authorizationMaskSourcePath: "one-pixel.pgm",
    authorizationMaskWorkingPath: "work/object-change.png",
    subjectMask: {
      id: "object",
      path: "alpha.pgm",
      sha256: sha256(await readFile(path.join(root, "alpha.pgm"))),
      sourceBoundsPixels: { minX: 1, minY: 1, maxX: 2, maxY: 2 },
      cropLocalBoundsPixels: { minX: 1, minY: 1, maxX: 2, maxY: 2 },
    },
    donorMask: {
      id: "donor-mask",
      path: "one-pixel.pgm",
      sha256: sha256(await readFile(path.join(root, "one-pixel.pgm"))),
    },
    excludedOccluderMask: {
      id: "foreground-mask",
      path: "one-pixel.pgm",
      sha256: sha256(await readFile(path.join(root, "one-pixel.pgm"))),
    },
    usableDonorPixelCount: 1,
    maskPreparation: {
      closeRadiusPixels: 1,
      dilatePixels: 1,
      subtractForegroundOccluders: true,
    },
    fill: {
      method: "SOURCE_ONLY_MULTI_RESOLUTION_PATCHMATCH",
      mirrorAllowed: false,
      rotationDegrees: { minimum: -3, maximum: 3 },
      scale: { minimum: 0.92, maximum: 1.08 },
      sourceBuiltSeamRingPixels: 1,
    },
  };
  data.contract.disocclusionUnderlays = [{
    id: "object-underlay",
    layerID: "object",
    sourceLayerPlatePath: underlayPath,
    workingPath: "work/object-underlay.png",
    frame: fullFrame,
    coverageMode: "RAIL_BOUNDED",
    recipe,
  }];
  data.contract.disocclusionExemptions = [];
  data.dag.sources.push({
    id: "object-underlay-source",
    kind: "layer-plate",
    path: underlayPath,
    ...exactRecord(masterBytes),
    dimensions: { width: 4, height: 4 },
    creation: derivedCreation("master", master.sha256),
    rights,
  });
  data.dag.operations.push(operation({
    id: "object-underlay",
    kind: "normalize-raster",
    outputRole: "working-layer",
    outputPath: "work/object-underlay.png",
    sourceID: "object-underlay-source",
    authorizationMaskOperationID: "change-authorization",
  }));
  data.dag.contract.sha256 = canonicalSHA256(data.contract);
  const approvalPath = path.join(root, "approval.json");
  const approval = JSON.parse(await readFile(approvalPath, "utf8"));
  approval.contract.sha256 = data.dag.contract.sha256;
  const approvalBytes = Buffer.from(`${JSON.stringify(approval, null, 2)}\n`);
  await writeFile(approvalPath, approvalBytes);
  master.editorApproval.sha256 = sha256(approvalBytes);
  return data;
}

async function makeProvisionalBuildFixture(root) {
  const data = await makeBuildFixture(root);
  const master = data.dag.sources.find(({ id }) => id === data.dag.masterSourceID);
  const preflightBytes = Buffer.from(`# Test candidate preflight\n\nStatus: \`CODEX_PROVISIONAL_NON_SHIPPING_REVIEW\`\n`);
  await writeFile(path.join(root, "provisional-preflight.md"), preflightBytes);
  const metadata = {
    schemaVersion: 1,
    candidateID: "test-provisional-master",
    status: "NON_SHIPPING_EXACT_CANVAS_TEST_CANDIDATE",
    shippingAllowed: false,
    output: {
      path: master.path,
      sha256: master.sha256,
      bytes: master.bytes,
      width: master.dimensions.width,
      height: master.dimensions.height,
    },
    codexPreflight: {
      path: "provisional-preflight.md",
      sha256: sha256(preflightBytes),
      bytes: preflightBytes.byteLength,
      status: "CODEX_PROVISIONAL_NON_SHIPPING_REVIEW",
    },
    audit: {
      productionMasterResult: "PENDING_ARTISTIC_GATE",
      layerDAGAuthority: "NOT_GRANTED",
    },
  };
  const metadataBytes = Buffer.from(`${JSON.stringify(metadata, null, 2)}\n`);
  await writeFile(path.join(root, "provisional-metadata.json"), metadataBytes);
  const authority = await createProvisionalVisualMasterAuthority({
    ...data,
    repositoryRoot: root,
    candidatePath: path.join(root, master.path),
    candidateMetadataPath: path.join(root, "provisional-metadata.json"),
    contractRepositoryPath: "contract.json",
  });
  const authorityBytes = Buffer.from(`${JSON.stringify(authority, null, 2)}\n`);
  await writeFile(path.join(root, "provisional-authority.json"), authorityBytes);
  master.kind = "provisional-master";
  delete master.editorApproval;
  master.provisionalAuthority = {
    path: "provisional-authority.json",
    sha256: sha256(authorityBytes),
    status: provisionalVisualMasterStatus,
  };
  data.dag.status = "CODEX_PROVISIONAL_NON_SHIPPING_INPUTS_LOCKED";
  data.dag.buildMode = visualProductionBuildModes.codexProvisional;
  return { ...data, authority, authorityBytes, metadata, metadataBytes };
}

test("lossless layers, five mask kinds, bounds, local edits and recomposition are reproducible", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-pipeline-"));
  try {
    const data = await makeBuildFixture(root);
    const first = await buildVisualAssetDAG({
      ...data,
      repositoryRoot: root,
      outputRoot: path.join(root, "build-a"),
      contractRepositoryPath: "contract.json",
    });
    assert.equal(first.receipt.status, "TECHNICAL_REPRODUCTION_PASS_NOT_SHIPPING_APPROVAL");
    assert.equal(first.receipt.recomposition.maxChannelError, 0);
    assert.equal(first.receipt.recomposition.meanAbsoluteError, 0);
    assert.equal(first.receipt.recomposition.exactPixelFraction, 1);
    assert.ok(first.receipt.outputs.some(({ maskStats }) => maskStats?.nonzeroBounds));
    assert.ok(first.receipt.outputs.some(({ maskStats }) => maskStats?.encoding === "heic"));

    const second = await verifyVisualAssetReceipt({
      ...data,
      repositoryRoot: root,
      outputRoot: path.join(root, "build-b"),
      contractRepositoryPath: "contract.json",
      expectedReceipt: first.receipt,
    });
    assert.equal(canonicalJSON(second.receipt), canonicalJSON(first.receipt));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("v2 DAG admits a measured layer-plate underlay only through a working-layer output", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-underlay-v2-"));
  try {
    const data = await convertBuildFixtureToV2Underlay(await makeBuildFixture(root), root);
    const result = await buildVisualAssetDAG({
      ...data,
      repositoryRoot: root,
      outputRoot: path.join(root, "build"),
      contractRepositoryPath: "contract.json",
    });
    assert.ok(result.receipt.outputs.some(({ outputPath }) => outputPath === "work/object-underlay.png"));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("v2 measured underlay rejects source-authority byte drift", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-underlay-authority-v2-"));
  try {
    const data = await convertBuildFixtureToV2Underlay(await makeBuildFixture(root), root);
    data.contract.disocclusionUnderlays[0].recipe.sourceAuthority.sha256 = "0".repeat(64);
    await assert.rejects(
      validateVisualProductionContract({
        contract: data.contract,
        fixture: data.fixture,
        fixtureBytes: data.fixtureBytes,
        costRegistry: data.costRegistry,
        repositoryRoot: root,
        contractRepositoryPath: "contract.json",
      }),
      /sourceAuthority: SHA-256 drifted/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("v2 underlay rejects every source pixel changed outside its bound authorization mask", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-underlay-v2-"));
  try {
    const data = await convertBuildFixtureToV2Underlay(await makeBuildFixture(root), root);
    const source = data.dag.sources.find(({ id }) => id === "object-underlay-source");
    const bytes = Buffer.from(await readFile(path.join(root, source.path)));
    const headerEnd = bytes.indexOf(Buffer.from("255\n")) + 4;
    bytes[headerEnd] = 241;
    await writeFile(path.join(root, source.path), bytes);
    source.bytes = bytes.byteLength;
    source.sha256 = sha256(bytes);
    await assert.rejects(
      buildVisualAssetDAG({
        ...data,
        repositoryRoot: root,
        outputRoot: path.join(root, "build"),
        contractRepositoryPath: "contract.json",
      }),
      /pixels changed outside the authored underlay authorization mask/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("v2 DAG fails while any disocclusion recipe remains PENDING_MEASUREMENT", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-underlay-v2-"));
  try {
    const data = await convertBuildFixtureToV2Underlay(await makeBuildFixture(root), root, { pending: true });
    await assert.rejects(
      buildVisualAssetDAG({
        ...data,
        repositoryRoot: root,
        outputRoot: path.join(root, "build"),
        contractRepositoryPath: "contract.json",
      }),
      /disocclusion underlay 'object' remains PENDING_MEASUREMENT/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("an exact Codex provisional master can build and replay only the non-shipping development DAG", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-provisional-"));
  try {
    const data = await makeProvisionalBuildFixture(root);
    assert.equal(data.authority.status, provisionalVisualMasterStatus);
    assert.equal(data.authority.shippingState, "PROHIBITED");
    assert.equal(data.authority.editorApprovalState, "NOT_CLAIMED");
    const first = await buildVisualAssetDAG({
      ...data,
      repositoryRoot: root,
      outputRoot: path.join(root, "build-a"),
      contractRepositoryPath: "contract.json",
    });
    assert.equal(first.receipt.status, "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_REPRODUCTION_PASS");
    assert.equal(first.receipt.buildMode, visualProductionBuildModes.codexProvisional);
    assert.equal(first.receipt.shippingState, "PROHIBITED_UNTIL_SEPARATE_EDITOR_ASSET_AND_PACKAGE_APPROVAL");
    assert.equal(first.receipt.masterAuthority.kind, "provisional-master");
    assert.equal(first.receipt.masterAuthority.record.status, provisionalVisualMasterStatus);
    const second = await verifyVisualAssetReceipt({
      ...data,
      repositoryRoot: root,
      outputRoot: path.join(root, "build-b"),
      contractRepositoryPath: "contract.json",
      expectedReceipt: first.receipt,
    });
    assert.equal(canonicalJSON(second.receipt), canonicalJSON(first.receipt));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("renaming a provisional authority reference cannot fabricate editor master approval", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-provisional-"));
  try {
    const data = await makeProvisionalBuildFixture(root);
    data.dag.status = "PRODUCTION_INPUTS_LOCKED";
    data.dag.buildMode = visualProductionBuildModes.editorApproved;
    const master = data.dag.sources.find(({ id }) => id === data.dag.masterSourceID);
    const provisionalAuthority = master.provisionalAuthority;
    master.kind = "approved-master";
    delete master.provisionalAuthority;
    master.editorApproval = {
      path: provisionalAuthority.path,
      sha256: provisionalAuthority.sha256,
      status: "EDITOR_APPROVED_AS_PRODUCTION_MASTER",
    };
    await assert.rejects(
      buildVisualAssetDAG({
        ...data,
        repositoryRoot: root,
        outputRoot: path.join(root, "build"),
        contractRepositoryPath: "contract.json",
      }),
      /editorApproval[\s\S]*explicit editor-in-chief production-master approval required/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("development and editor build modes reject a master from the other trust domain", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-provisional-"));
  try {
    const provisional = await makeProvisionalBuildFixture(root);
    provisional.dag.status = "PRODUCTION_INPUTS_LOCKED";
    provisional.dag.buildMode = visualProductionBuildModes.editorApproved;
    await assert.rejects(
      buildVisualAssetDAG({
        ...provisional,
        repositoryRoot: root,
        outputRoot: path.join(root, "provisional-in-editor-build"),
        contractRepositoryPath: "contract.json",
      }),
      /approved-master source required/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }

  const editorRoot = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-editor-"));
  try {
    const editor = await makeBuildFixture(editorRoot);
    editor.dag.status = "CODEX_PROVISIONAL_NON_SHIPPING_INPUTS_LOCKED";
    editor.dag.buildMode = visualProductionBuildModes.codexProvisional;
    await assert.rejects(
      buildVisualAssetDAG({
        ...editor,
        repositoryRoot: editorRoot,
        outputRoot: path.join(editorRoot, "editor-in-provisional-build"),
        contractRepositoryPath: "contract.json",
      }),
      /provisional-master source required/u,
    );
  } finally {
    await rm(editorRoot, { recursive: true, force: true });
  }
});

test("provisional authority fails closed when candidate metadata drifts after the freeze", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-provisional-"));
  try {
    const data = await makeProvisionalBuildFixture(root);
    const changed = structuredClone(data.metadata);
    changed.audit.productionMasterResult = "APPROVED";
    await writeFile(path.join(root, "provisional-metadata.json"), `${JSON.stringify(changed, null, 2)}\n`);
    await assert.rejects(
      buildVisualAssetDAG({
        ...data,
        repositoryRoot: root,
        outputRoot: path.join(root, "build"),
        contractRepositoryPath: "contract.json",
      }),
      /candidateMetadata: SHA-256 drifted/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("a state edit outside its local authorization mask fails closed", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-pipeline-"));
  try {
    const data = await makeBuildFixture(root);
    const changed = data.dag.sources.find(({ id }) => id === "changed");
    const changedBytes = await readFile(path.join(root, changed.path));
    const pixels = Buffer.from(changedBytes);
    const headerEnd = pixels.indexOf(Buffer.from("255\n")) + 4;
    pixels[headerEnd] = 250;
    await writeFile(path.join(root, changed.path), pixels);
    changed.bytes = pixels.byteLength;
    changed.sha256 = sha256(pixels);

    await assert.rejects(
      buildVisualAssetDAG({
        ...data,
        repositoryRoot: root,
        outputRoot: path.join(root, "build"),
        contractRepositoryPath: "contract.json",
      }),
      /changed outside the authored authorization mask/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("generated master provenance requires the exact registered model snapshot and every weight hash", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-pipeline-"));
  try {
    const data = await makeBuildFixture(root);
    data.contract.toolchain.push({
      toolID: "test-image-model",
      version: "snapshot-1",
      license: "Apache License 2.0",
    });
    data.costRegistry.entries.push({
      id: "test-image-model",
      category: "model",
      version: "snapshot-1",
      incrementalCostNOK: 0,
      billingCredentialRequired: false,
      commercialUse: "allowed",
      license: "Apache License 2.0",
    });
    data.dag.contract.sha256 = canonicalSHA256(data.contract);
    const master = data.dag.sources.find(({ id }) => id === "master");
    master.creation = {
      mode: "generated",
      toolIDs: ["nodejs-local", "ffmpeg-local"],
      parentHashes: [],
      prompt: master.creation.symbolicSource,
      symbolicSource: null,
      seed: 18423001,
      model: {
        toolID: "test-image-model",
        version: "snapshot-1",
        weights: [],
      },
    };

    await assert.rejects(
      buildVisualAssetDAG({
        ...data,
        repositoryRoot: root,
        outputRoot: path.join(root, "build"),
        contractRepositoryPath: "contract.json",
      }),
      /every loaded model-weight file requires an exact hash/u,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
