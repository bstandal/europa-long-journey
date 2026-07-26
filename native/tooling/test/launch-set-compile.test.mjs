import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash, generateKeyPairSync } from "node:crypto";
import {
  cp,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import nodeTest from "node:test";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import {
  launchPackageApprovalDigest,
  launchPublicSourceInventoryDigest,
  phase0EditorialDigest,
  saveMigrationDescriptorInventoryDigest,
  saveMigrationGraphDigest,
  validateLaunchViewportCropContract,
} from "../src/compile.mjs";
import {
  compileLaunchSet,
  launchSetReceiptDigest,
  validateLaunchSetReceipt,
} from "../src/launch-set-compile.mjs";
import { listFiles } from "../src/validate.mjs";

const execFileAsync = promisify(execFile);
const nativeRoot = fileURLToPath(new URL("../../", import.meta.url));
const cliPath = fileURLToPath(new URL("../src/cli.mjs", import.meta.url));
const test = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])
  ? nodeTest
  : () => {};
const version = { major: 1, minor: 0, patch: 0 };
const phase0EditorialFileNames = [
  "arc-matrix.json",
  "authored-interaction-effects-01-12.json",
  "authored-interaction-effects-13-24.json",
  "chapter-catalog.json",
  "chapter-contracts.json",
  "interaction-mapping.json",
  "world-traces.json",
];

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function localized(id, launchEnglish) {
  return { id, launchEnglish };
}

function launchViewportCrops() {
  return [
    {
      id: "baseline-393x852",
      viewport: { widthPoints: 393, heightPoints: 852 },
      sourceRect: { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
      safeTextRegions: [{
        id: "opening-copy",
        rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.22 },
      }],
    },
    {
      id: "largest-430x932",
      viewport: { widthPoints: 430, heightPoints: 932 },
      sourceRect: { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
      safeTextRegions: [{
        id: "opening-copy",
        rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.22 },
      }],
    },
  ];
}

async function readJSON(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

async function writeJSON(file, value) {
  await writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

async function approveTemporaryBlueprint(temporaryRoot) {
  const blueprintRoot = path.join(temporaryRoot, "blueprint");
  await cp(path.join(nativeRoot, "blueprint"), blueprintRoot, { recursive: true });

  const catalog = await readJSON(path.join(blueprintRoot, "chapter-catalog.json"));
  catalog.status = "CANONICAL_PHASE_0_APPROVED";
  catalog.chapters.forEach((chapter) => {
    chapter.thesisStatus = "LOCKED_NATIVE_CONTRACT_APPROVED";
  });
  await writeJSON(path.join(blueprintRoot, "chapter-catalog.json"), catalog);

  const contracts = await readJSON(path.join(blueprintRoot, "chapter-contracts.json"));
  contracts.status = "APPROVED_BY_EDITOR_IN_CHIEF";
  contracts.contracts.forEach((contract) => {
    contract.editorApproval = "APPROVED";
  });
  await writeJSON(path.join(blueprintRoot, "chapter-contracts.json"), contracts);

  const arcs = await readJSON(path.join(blueprintRoot, "arc-matrix.json"));
  arcs.status = "APPROVED_BY_EDITOR_IN_CHIEF";
  arcs.chapters.forEach((chapter) => {
    chapter.editorApproval = "APPROVED";
  });
  await writeJSON(path.join(blueprintRoot, "arc-matrix.json"), arcs);

  for (const fileName of ["interaction-mapping.json", "world-traces.json"]) {
    const document = await readJSON(path.join(blueprintRoot, fileName));
    document.status = "APPROVED_BY_EDITOR_IN_CHIEF";
    await writeJSON(path.join(blueprintRoot, fileName), document);
  }
  for (const fileName of [
    "authored-interaction-effects-01-12.json",
    "authored-interaction-effects-13-24.json",
  ]) {
    const ledger = await readJSON(path.join(blueprintRoot, fileName));
    ledger.status = "AUTHORED_APPROVED_BY_EDITOR_IN_CHIEF";
    await writeJSON(path.join(blueprintRoot, fileName), ledger);
  }

  const editorialBytes = Object.fromEntries(await Promise.all(
    phase0EditorialFileNames.map(async (fileName) => [
      fileName,
      await readFile(path.join(blueprintRoot, fileName)),
    ]),
  ));
  const approvalPath = path.join(blueprintRoot, "editor-approval.json");
  const approval = await readJSON(approvalPath);
  Object.assign(approval, {
    status: "APPROVED_BY_EDITOR_IN_CHIEF",
    authority: "editor-in-chief",
    approvedAt: "2026-07-23T20:00:00Z",
    decisionReference: "launch-set-production-path-test-fixture",
    chapterContractsSHA256: sha256(editorialBytes["chapter-contracts.json"]),
    arcMatrixSHA256: sha256(editorialBytes["arc-matrix.json"]),
    phase0EditorialSHA256: phase0EditorialDigest(editorialBytes),
  });
  await writeJSON(approvalPath, approval);
  return { blueprintRoot, catalog };
}

function canonicalLaunchCollection(product, catalog, delivery) {
  const packageForChapter = new Map(delivery.packages.flatMap((packageSpec) =>
    packageSpec.chapterIDs.map((chapterID) => [chapterID, packageSpec.packageID])));
  const maximumContentBytes = delivery.budgets.completeInstalledWorkBytes
    - delivery.budgets.shellAndEngineBytes;
  const packageBudgets = delivery.packages.map((packageSpec) => packageSpec.maximumInstalledBytes);
  const declaredBytes = packageBudgets.reduce((sum, bytes) => sum + bytes, 0);
  packageBudgets[packageBudgets.length - 1] -= declaredBytes - maximumContentBytes;
  const freeIDs = new Set(catalog.freeContentIDs);

  return {
    schemaVersion: version,
    collectionID: catalog.collectionID,
    locale: { identifier: product.launchLanguage },
    product: {
      franchiseName: product.franchiseName,
      workTitle: product.workTitle,
    },
    chapters: [...catalog.chapters]
      .sort((left, right) => left.ordinal - right.ordinal)
      .map((chapter) => ({
        id: chapter.contentID,
        sequence: chapter.ordinal,
        title: localized(`${chapter.contentID}-title`, chapter.title),
        period: localized(`${chapter.contentID}-period`, chapter.period),
        packageID: packageForChapter.get(chapter.contentID),
        access: freeIDs.has(chapter.contentID)
          ? { kind: "included" }
          : { kind: "entitlement", entitlementID: delivery.entitlement.entitlementID },
      })),
    packages: delivery.packages.map((packageSpec, index) => ({
      id: packageSpec.packageID,
      version,
      chapterIDs: [...packageSpec.chapterIDs],
      maximumInstalledBytes: packageBudgets[index],
      minimumRuntime: version,
      isEssentialInstall: packageSpec.isEssentialInstall,
    })),
    entitlements: [{
      id: delivery.entitlement.entitlementID,
      storeProductID: delivery.entitlement.storeProductID,
      kind: "nonConsumable",
    }],
  };
}

function launchPayloads(collection) {
  const worldSeed = {
    nodes: [{
      id: "european-world-anchor",
      kind: "institution",
      form: "The hidden cumulative world",
      position: { x: 0.5, y: 0.5 },
      attributes: [],
    }],
    traces: [],
  };
  const chapterByID = new Map(collection.chapters.map((chapter) => [chapter.id, {
    schemaVersion: version,
    id: chapter.id,
    title: chapter.title,
    period: chapter.period,
    arcs: [{
      id: `${chapter.id}-arc`,
      title: localized(`${chapter.id}-arc-title`, `The ground of ${chapter.title.launchEnglish}`),
      targetDurationMinutes: 8,
      situation: localized(`${chapter.id}-arc-situation`, "A historical order stands in a defined place."),
      mechanism: localized(`${chapter.id}-arc-mechanism`, "Named institutions carry action into the world."),
      turn: localized(`${chapter.id}-arc-turn`, "The established arrangement changes under pressure."),
      consequence: localized(`${chapter.id}-arc-consequence`, "The changed order remains visible in the world."),
      handoff: localized(`${chapter.id}-arc-handoff`, "The next chapter inherits the altered ground."),
      beats: [{
        id: `${chapter.id}-beat`,
        sceneID: `scene-${chapter.packageID}`,
        narrative: {
          heading: localized(
            `${chapter.id}-beat-heading`,
            `${chapter.title.launchEnglish} changes the inherited world`,
          ),
          paragraphs: [localized(
            `${chapter.id}-beat-paragraph-1`,
            "People act through the material order around them.",
          )],
        },
        narrationCueIDs: [],
        completionEffects: [],
        checkpoint: "onExit",
      }],
    }],
    completionEffects: [{
      id: `effect-${chapter.id}`,
      mutation: "transform-node",
      nodeID: "european-world-anchor",
      form: `The world after ${chapter.title.launchEnglish}`,
      attributes: [{ key: `completed-${chapter.sequence}`, value: true }],
    }],
  }]));

  return collection.packages.map((packageSpec) => ({
    schemaVersion: version,
    packageID: packageSpec.id,
    worldSeed: structuredClone(worldSeed),
    chapters: packageSpec.chapterIDs.map((chapterID) => structuredClone(chapterByID.get(chapterID))),
    scenes: [{
      id: `scene-${packageSpec.id}`,
      sceneCanvas: {
        canvas: { width: 1200, height: 2600 },
        cameraTravelBounds: { x: 0.2, y: 0.2, width: 0.6, height: 0.6 },
        authoredOverscanFraction: 0.15,
        viewportCrops: launchViewportCrops(),
      },
      layers: [{
        id: "landscape",
        order: 0,
        assetPath: "assets/world.heif",
        frame: { x: 0, y: 0, width: 1, height: 1 },
        depth: 0.2,
        opacity: 1,
        blendMode: "normal",
        masks: {},
        motion: { parallaxFactor: 0.1, windResponse: 0.1, focusResponse: 0.1 },
        stateVariants: [],
      }],
      cameraRail: {
        keyframes: [
          { progress: 0, center: { x: 0.45, y: 0.5 }, scale: 1 },
          { progress: 1, center: { x: 0.55, y: 0.45 }, scale: 1.05 },
        ],
      },
      atmosphere: [],
      interactionTargets: [],
      reduceMotionComposition: {
        canvas: { width: 1200, height: 2600 },
        strata: [
          { id: "static-world", kind: "staticPlate", assetPath: "assets/world-reduce.heif" },
        ],
        viewportCrops: launchViewportCrops(),
      },
      mechanismFocus: localized("living-world-mechanism-focus", "The changed institution"),
      accessibilityID: `access-${packageSpec.id}`,
    }],
    audioTimelines: [{
      id: `audio-${packageSpec.id}`,
      sampleRate: 48_000,
      events: [{
        cueID: `silence-${packageSpec.id}`,
        role: "silence",
        startSample: 0,
        durationSamples: 48_000,
        gain: 0,
      }],
      haptics: [],
    }],
    responsiveAudioPrograms: [],
    accessibility: [{
      id: `access-${packageSpec.id}`,
      sceneSummary: localized(
        "living-world-scene-summary",
        "A historical institution changes in the landscape.",
      ),
      elements: [{
        id: `image-${packageSpec.id}`,
        role: "image",
        label: localized("living-world-image-label", "The changing historical world"),
        actions: [],
      }],
    }],
  }));
}

function zeroCostEntry(id, category) {
  return {
    id,
    category,
    version: "test-v1",
    costModel: "free-local",
    incrementalCostNOK: 0,
    billingCredentialRequired: false,
    commercialUse: "allowed",
    license: "Project-owned test fixture",
    source: "Local test fixture",
  };
}

async function writeCostRegistry(temporaryRoot) {
  const costRegistryPath = path.join(temporaryRoot, "backstage", "cost-license.json");
  await mkdir(path.dirname(costRegistryPath), { recursive: true });
  await writeJSON(costRegistryPath, {
    policyVersion: 1,
    entries: [
      zeroCostEntry("test-tool", "tool"),
      zeroCostEntry("native-image-layer-production", "image"),
    ],
    unresolvedCapabilities: [],
  });
  return costRegistryPath;
}

async function publicInventory(sourceRoot) {
  return Promise.all((await listFiles(sourceRoot)).map(async (file) => {
    const bytes = await readFile(file);
    return {
      path: path.relative(sourceRoot, file).split(path.sep).join("/"),
      bytes: bytes.byteLength,
      sha256: sha256(bytes),
    };
  }));
}

async function writePackageControls(
  temporaryRoot,
  sourceRoot,
  collection,
  payload,
  assetBytes,
  reducedAssetBytes,
) {
  const backstageRoot = path.join(temporaryRoot, "backstage", payload.packageID);
  await mkdir(backstageRoot, { recursive: true });
  const assetProvenancePath = path.join(backstageRoot, "native-asset-provenance.json");
  const assetDigest = sha256(assetBytes);
  const reducedAssetDigest = sha256(reducedAssetBytes);
  await writeJSON(assetProvenancePath, {
    schemaVersion: 3,
    status: "ACTIVE",
    assets: [
      {
        assetPath: "assets/world.heif",
        bytes: assetBytes.byteLength,
        sha256: assetDigest,
        sourceLineage: [{
          lineageType: "GENERATED_ORIGINAL",
          sourceID: `source-${payload.packageID}`,
          bytes: assetBytes.byteLength,
          sha256: assetDigest,
          rightsBasis: "PROJECT_OWNED",
          license: "Project-owned launch-set test fixture",
        }],
        toolLineage: [{ toolID: "test-tool" }],
        shippingRoles: ["scene-layer"],
        metadataPolicy: "STRIPPED_AND_INSPECTED",
        rightsStatus: "COMMERCIAL_USE_CLEARED",
        incrementalCostNOK: 0,
        approvedForShipping: true,
      },
      {
        assetPath: "assets/world-reduce.heif",
        bytes: reducedAssetBytes.byteLength,
        sha256: reducedAssetDigest,
        sourceLineage: [{
          lineageType: "GENERATED_ORIGINAL",
          sourceID: `source-reduced-${payload.packageID}`,
          bytes: reducedAssetBytes.byteLength,
          sha256: reducedAssetDigest,
          rightsBasis: "PROJECT_OWNED",
          license: "Project-owned launch-set test fixture",
        }],
        toolLineage: [{ toolID: "test-tool" }],
        shippingRoles: ["scene-layer"],
        metadataPolicy: "STRIPPED_AND_INSPECTED",
        rightsStatus: "COMMERCIAL_USE_CLEARED",
        incrementalCostNOK: 0,
        approvedForShipping: true,
      },
    ],
  });

  const collectionBytes = await readFile(path.join(sourceRoot, "collection.json"));
  const payloadBytes = await readFile(path.join(sourceRoot, "chapters", `${payload.packageID}.json`));
  const publicSourceInventorySHA256 = launchPublicSourceInventoryDigest(
    await publicInventory(sourceRoot),
  );
  const approvalPath = path.join(backstageRoot, "launch-package-approval.json");
  const saveMigrationGraphSHA256 = saveMigrationGraphDigest(
    collection.packages.find(({ id }) => id === payload.packageID).version,
  );
  const saveMigrationDescriptorInventorySHA256 = saveMigrationDescriptorInventoryDigest();
  await writeJSON(approvalPath, {
    schemaVersion: 2,
    status: "APPROVED_BY_EDITOR_IN_CHIEF",
    authority: "editor-in-chief",
    approvedAt: "2026-07-23T21:00:00Z",
    decisionReference: `launch-set-test-${payload.packageID}`,
    collectionID: collection.collectionID,
    packageID: payload.packageID,
    chapterIDs: payload.chapters.map((chapter) => chapter.id),
    collectionSHA256: sha256(collectionBytes),
    payloadSHA256: sha256(payloadBytes),
    publicSourceInventorySHA256,
    saveMigrationGraphSHA256,
    saveMigrationDescriptorInventorySHA256,
    launchPackageApprovalSHA256: launchPackageApprovalDigest(
      collectionBytes,
      payloadBytes,
      publicSourceInventorySHA256,
      saveMigrationGraphSHA256,
      saveMigrationDescriptorInventorySHA256,
    ),
  });
  return { approvalPath, assetProvenancePath };
}

export async function createLaunchSetFixture(context, mutatePayloads = undefined) {
  const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-launch-set-"));
  context.after(() => rm(temporary, { recursive: true, force: true }));
  const approved = await approveTemporaryBlueprint(temporary);
  const product = await readJSON(path.join(nativeRoot, "product.json"));
  const delivery = await readJSON(path.join(approved.blueprintRoot, "delivery-plan.json"));
  const collection = canonicalLaunchCollection(product, approved.catalog, delivery);
  const payloads = launchPayloads(collection);
  if (mutatePayloads) mutatePayloads(payloads);
  const collectionBytes = Buffer.from(`${JSON.stringify(collection, null, 2)}\n`, "utf8");
  const packageInputs = [];

  for (const payload of payloads) {
    const sourceRoot = path.join(temporary, "public", payload.packageID);
    await mkdir(path.join(sourceRoot, "chapters"), { recursive: true });
    await mkdir(path.join(sourceRoot, "assets"), { recursive: true });
    const assetBytes = Buffer.from(`world-layer-${payload.packageID}`, "utf8");
    const reducedAssetBytes = Buffer.from(`world-reduced-${payload.packageID}`, "utf8");
    await writeFile(path.join(sourceRoot, "collection.json"), collectionBytes);
    await writeJSON(path.join(sourceRoot, "chapters", `${payload.packageID}.json`), payload);
    await writeFile(path.join(sourceRoot, "assets", "world.heif"), assetBytes);
    await writeFile(path.join(sourceRoot, "assets", "world-reduce.heif"), reducedAssetBytes);
    const controls = await writePackageControls(
      temporary,
      sourceRoot,
      collection,
      payload,
      assetBytes,
      reducedAssetBytes,
    );
    packageInputs.push({
      packageID: payload.packageID,
      sourceRoot,
      ...controls,
    });
  }

  const costRegistryPath = await writeCostRegistry(temporary);
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const launchConfiguration = { product, catalog: approved.catalog, delivery };
  return {
    temporary,
    collection,
    descriptor: { schemaVersion: 1, packages: packageInputs.reverse() },
    expectedPackageIDs: delivery.packages.map((record) => record.packageID),
    publicKey,
    options: {
      blueprintRoot: approved.blueprintRoot,
      launchConfiguration,
      costRegistryPath,
      keyID: "launch-2026-a",
      signingPrivateKey: privateKey,
      testOnlyAllowUnprojectedPayload: true,
    },
  };
}

test("launch viewport crop contract requires the exact two portrait crops in both motion modes", () => {
  const payload = {
    scenes: [{
      sceneCanvas: { viewportCrops: launchViewportCrops() },
      reduceMotionComposition: { viewportCrops: launchViewportCrops() },
    }],
  };
  assert.equal(validateLaunchViewportCropContract(payload), true);

  const baselineOnly = structuredClone(payload);
  baselineOnly.scenes[0].sceneCanvas.viewportCrops.pop();
  baselineOnly.scenes[0].reduceMotionComposition.viewportCrops.pop();
  assert.throws(
    () => validateLaunchViewportCropContract(baselineOnly),
    /exactly baseline-393x852 and largest-430x932 are required/,
  );

  const wrongLargestDimensions = structuredClone(payload);
  wrongLargestDimensions.scenes[0]
    .reduceMotionComposition.viewportCrops[1].viewport.widthPoints = 431;
  assert.throws(
    () => validateLaunchViewportCropContract(wrongLargestDimensions),
    /largest-430x932\.viewport: 430 by 932 points required/,
  );

  const unexpectedThirdCrop = structuredClone(payload);
  unexpectedThirdCrop.scenes[0].sceneCanvas.viewportCrops.push({
    ...structuredClone(unexpectedThirdCrop.scenes[0].sceneCanvas.viewportCrops[0]),
    id: "compact-402x874",
    viewport: { widthPoints: 402, heightPoints: 874 },
  });
  unexpectedThirdCrop.scenes[0].reduceMotionComposition.viewportCrops.push({
    ...structuredClone(unexpectedThirdCrop.scenes[0].reduceMotionComposition.viewportCrops[0]),
    id: "compact-402x874",
    viewport: { widthPoints: 402, heightPoints: 874 },
  });
  assert.throws(
    () => validateLaunchViewportCropContract(unexpectedThirdCrop),
    /only baseline-393x852 and largest-430x932 may ship at launch/,
  );
});

test("official launch compilation signs, replays and atomically publishes one eight-package set", async (context) => {
  const fixture = await createLaunchSetFixture(context);
  const outputRoot = path.join(fixture.temporary, "submission", "launch-set");
  await mkdir(outputRoot, { recursive: true });
  await writeFile(path.join(outputRoot, "old-set-sentinel"), "previous verified set\n");

  assert.equal(Object.hasOwn(fixture.options, "testOnlyAllowUnapprovedBlueprint"), false);
  const receipt = await compileLaunchSet(fixture.descriptor, outputRoot, fixture.options);
  const diskReceipt = await readJSON(path.join(outputRoot, "launch-set-receipt.json"));
  assert.deepEqual(diskReceipt, receipt);
  assert.equal(validateLaunchSetReceipt(receipt, fixture.expectedPackageIDs), true);
  assert.deepEqual((await readdir(outputRoot)).sort(), ["launch-set-receipt.json", "packages"]);
  assert.deepEqual(
    (await readdir(path.join(outputRoot, "packages"))).sort(),
    [...fixture.expectedPackageIDs].sort(),
  );

  for (const record of receipt.packages) {
    const packageRoot = path.join(outputRoot, "packages", record.packageID);
    const packageSpec = fixture.collection.packages.find(({ id }) => id === record.packageID);
    assert.deepEqual(record.chapterIDs, packageSpec.chapterIDs);
    assert.equal(
      sha256(await readFile(path.join(packageRoot, ...record.payloadPath.split("/")))),
      record.payloadSHA256,
    );
    assert.equal(
      sha256(await readFile(path.join(packageRoot, "collection.json"))),
      receipt.collectionSHA256,
    );
    const manifest = await readJSON(path.join(packageRoot, "package-manifest.json"));
    assert.equal(manifest.manifestDigest, record.manifestDigest);
    assert.equal(manifest.signature.keyID, receipt.keyID);
    assert.equal(manifest.files.some(({ path: file }) => file.includes("launch-set-receipt")), false);
    assert.equal(await stat(path.join(packageRoot, "launch-set-receipt.json")).catch(() => null), null);
  }
});

test("official launch compilation rejects baseline-only scenes without touching a published set", async (context) => {
  const fixture = await createLaunchSetFixture(context, (payloads) => {
    payloads[3].scenes[0].sceneCanvas.viewportCrops.pop();
    payloads[3].scenes[0].reduceMotionComposition.viewportCrops.pop();
  });
  const outputRoot = path.join(fixture.temporary, "submission", "launch-set");
  await mkdir(outputRoot, { recursive: true });
  const sentinelPath = path.join(outputRoot, "previous-set-sentinel");
  await writeFile(sentinelPath, "previous verified set\n");

  await assert.rejects(
    () => compileLaunchSet(fixture.descriptor, outputRoot, fixture.options),
    /exactly baseline-393x852 and largest-430x932 are required/,
  );
  assert.deepEqual(await readdir(outputRoot), ["previous-set-sentinel"]);
  assert.equal(await readFile(sentinelPath, "utf8"), "previous verified set\n");
});

test("launch-set receipt deterministically binds key, chapter ownership and payload path", () => {
  const digest = "a".repeat(64);
  const packageIDs = Array.from({ length: 8 }, (_, index) => `package-${index + 1}`);
  const receipt = {
    schemaVersion: 1,
    kind: "long-west-launch-set-receipt-v1",
    collectionID: "collection-01",
    collectionSHA256: digest,
    finalWorldSHA256: "b".repeat(64),
    keyID: "production-key-01",
    packages: packageIDs.map((packageID, index) => ({
      packageID,
      chapterIDs: [`chapter-${index + 1}`],
      payloadPath: `chapters/${packageID}.json`,
      payloadSHA256: digest,
      manifestDigest: "c".repeat(64),
    })),
  };
  receipt.receiptSHA256 = launchSetReceiptDigest(receipt);
  assert.equal(launchSetReceiptDigest(receipt), receipt.receiptSHA256);
  assert.equal(validateLaunchSetReceipt(receipt, packageIDs), true);

  const changedKey = structuredClone(receipt);
  changedKey.keyID = "production-key-02";
  assert.notEqual(launchSetReceiptDigest(changedKey), receipt.receiptSHA256);
  const changedChapter = structuredClone(receipt);
  changedChapter.packages[0].chapterIDs = ["different-chapter"];
  assert.notEqual(launchSetReceiptDigest(changedChapter), receipt.receiptSHA256);
  const changedPath = structuredClone(receipt);
  changedPath.packages[0].payloadPath = "chapters/renamed.json";
  assert.notEqual(launchSetReceiptDigest(changedPath), receipt.receiptSHA256);
  const unsafePath = structuredClone(receipt);
  unsafePath.packages[0].payloadPath = "../backstage/approval.json";
  assert.throws(() => validateLaunchSetReceipt(unsafePath, packageIDs), /safe POSIX package-relative path/);
});

test("missing launch package input fails before a set can be published", async (context) => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-launch-set-missing-"));
  context.after(() => rm(temporary, { recursive: true, force: true }));
  const product = await readJSON(path.join(nativeRoot, "product.json"));
  const catalog = await readJSON(path.join(nativeRoot, "blueprint", "chapter-catalog.json"));
  const delivery = await readJSON(path.join(nativeRoot, "blueprint", "delivery-plan.json"));
  const descriptor = {
    schemaVersion: 1,
    packages: delivery.packages.slice(0, 7).map((record, index) => ({
      packageID: record.packageID,
      sourceRoot: path.join(temporary, `source-${index}`),
      approvalPath: path.join(temporary, "backstage", `approval-${index}.json`),
      assetProvenancePath: path.join(temporary, "backstage", `provenance-${index}.json`),
    })),
  };
  const outputRoot = path.join(temporary, "submission", "launch-set");
  await assert.rejects(
    () => compileLaunchSet(descriptor, outputRoot, {
      launchConfiguration: { product, catalog, delivery },
    }),
    /exactly eight package inputs required/,
  );
  assert.equal(await stat(outputRoot).catch(() => null), null);
});

test("cross-package world-seed drift preserves the previously published set", async (context) => {
  const fixture = await createLaunchSetFixture(context, (payloads) => {
    payloads[4].worldSeed.nodes[0].form = "A divergent but structurally valid seed";
  });
  const outputRoot = path.join(fixture.temporary, "submission", "launch-set");
  await mkdir(outputRoot, { recursive: true });
  const sentinelPath = path.join(outputRoot, "previous-set-sentinel");
  await writeFile(sentinelPath, "previous verified set\n");

  await assert.rejects(
    () => compileLaunchSet(fixture.descriptor, outputRoot, fixture.options),
    /worldSeed: must be identical across all launch packages/,
  );
  assert.deepEqual(await readdir(outputRoot), ["previous-set-sentinel"]);
  assert.equal(await readFile(sentinelPath, "utf8"), "previous verified set\n");
  const submissionEntries = await readdir(path.dirname(outputRoot));
  assert.equal(submissionEntries.some((entry) => entry.includes("launch-set-staging")), false);
});

test("the official CLI rejects standalone launch-package signing", async () => {
  await assert.rejects(
    execFileAsync(process.execPath, [cliPath, "compile", "/tmp/source", "/tmp/output"]),
    (error) => error.code === 1
      && /single-package launch signing is disabled; use compile-launch-set/.test(error.stderr),
  );
});
