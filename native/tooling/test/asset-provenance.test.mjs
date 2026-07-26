import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { authoritativeWebSourceID } from "../src/policy.mjs";
import { validateNativeAssetProvenanceLineage } from "../src/validate.mjs";

const nativeRoot = fileURLToPath(new URL("../../", import.meta.url));
const webInventoryPath = path.join(nativeRoot, "blueprint", "source-asset-provenance.json");
const emptyRegistryPath = path.join(nativeRoot, "content", "backstage", "native-asset-provenance.json");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

function shippingRegistry(sourceLineage) {
  return {
    schemaVersion: 3,
    status: "ACTIVE",
    assets: [{
      assetPath: "assets/native-scene.heif",
      bytes: 12,
      sha256: sha256("native-scene"),
      sourceLineage,
      toolLineage: [{ toolID: "test-tool" }],
      shippingRoles: ["scene-layer"],
      metadataPolicy: "STRIPPED_AND_INSPECTED",
      rightsStatus: "COMMERCIAL_USE_CLEARED",
      incrementalCostNOK: 0,
      approvedForShipping: true,
    }],
  };
}

function audioShippingRegistry(sourceLineage, role = "score") {
  const asset = Buffer.from("rendered audio fixture");
  return {
    schemaVersion: 3,
    status: "ACTIVE",
    assets: [{
      assetPath: `audio/${role}.m4a`,
      bytes: asset.byteLength,
      sha256: sha256(asset),
      sourceLineage,
      toolLineage: [{ toolID: "test-audio-tool" }],
      shippingRoles: [role],
      metadataPolicy: "STRIPPED_AND_INSPECTED",
      rightsStatus: "COMMERCIAL_USE_CLEARED",
      incrementalCostNOK: 0,
      approvedForShipping: true,
    }],
  };
}

function webLineage(source) {
  return {
    lineageType: "WEB_SOURCE_DERIVATIVE",
    sourceID: authoritativeWebSourceID(source.sha256),
    webSourcePath: source.localPath,
    bytes: source.bytes,
    sha256: source.sha256,
    acknowledgedObligations: [...source.obligations],
  };
}

function generatedOriginal() {
  const master = Buffer.from("generated original master");
  return {
    lineageType: "GENERATED_ORIGINAL",
    sourceID: "generated-native-scene",
    bytes: master.byteLength,
    sha256: sha256(master),
    rightsBasis: "PROJECT_OWNED",
    license: "Project-owned generated-original test fixture",
  };
}

async function authoritativeInventory() {
  return JSON.parse(await readFile(webInventoryPath, "utf8"));
}

test("the checked-in zero-approved native registry remains valid and empty", async () => {
  const [registry, inventory] = await Promise.all([
    readFile(emptyRegistryPath, "utf8").then(JSON.parse),
    authoritativeInventory(),
  ]);
  assert.equal(registry.status, "NO_NATIVE_ASSETS_APPROVED");
  assert.deepEqual(registry.assets, []);
  assert.equal(validateNativeAssetProvenanceLineage(registry, inventory), registry);
});

test("web derivative lineage binds to one exact eligible authoritative source", async () => {
  const inventory = await authoritativeInventory();
  const eligible = inventory.assets.find((asset) => asset.allowedAsNativeRawMaterial);
  const registry = shippingRegistry([webLineage(eligible)]);
  assert.equal(validateNativeAssetProvenanceLineage(registry, inventory), registry);
});

test("web derivative lineage rejects fabricated paths and source hashes", async () => {
  const inventory = await authoritativeInventory();
  const eligible = inventory.assets.find((asset) => asset.allowedAsNativeRawMaterial);

  const fabricated = webLineage(eligible);
  fabricated.webSourcePath = "/assets/fabricated-source.webp";
  assert.throws(
    () => validateNativeAssetProvenanceLineage(shippingRegistry([fabricated]), inventory),
    /absent from the authoritative inventory/,
  );

  const drifted = webLineage(eligible);
  drifted.sha256 = "0".repeat(64);
  drifted.sourceID = authoritativeWebSourceID(drifted.sha256);
  assert.throws(
    () => validateNativeAssetProvenanceLineage(shippingRegistry([drifted]), inventory),
    /path\/hash does not match the authoritative inventory/,
  );
});

test("an inventoried but ineligible web plate cannot enter native lineage", async () => {
  const inventory = await authoritativeInventory();
  const blocked = inventory.assets.find((asset) => !asset.allowedAsNativeRawMaterial);
  assert.throws(
    () => validateNativeAssetProvenanceLineage(shippingRegistry([webLineage(blocked)]), inventory),
    /ineligible for native reuse/,
  );
});

test("web lineage preserves every authoritative reuse obligation", async () => {
  const inventory = await authoritativeInventory();
  const attributed = inventory.assets.find((asset) => asset.obligations.length > 0);
  const lineage = webLineage(attributed);
  lineage.acknowledgedObligations = [];
  assert.throws(
    () => validateNativeAssetProvenanceLineage(shippingRegistry([lineage]), inventory),
    /must exactly preserve authoritative obligations/,
  );
});

test("generated originals use a distinct project-owned lineage branch", () => {
  const registry = shippingRegistry([generatedOriginal()]);
  assert.equal(validateNativeAssetProvenanceLineage(registry), registry);

  const falseRights = generatedOriginal();
  falseRights.rightsBasis = "PUBLIC_DOMAIN";
  assert.throws(
    () => validateNativeAssetProvenanceLineage(shippingRegistry([falseRights])),
    /generated originals must be PROJECT_OWNED/,
  );

  const ambiguousLegacyLineage = generatedOriginal();
  delete ambiguousLegacyLineage.lineageType;
  assert.throws(
    () => validateNativeAssetProvenanceLineage(shippingRegistry([ambiguousLegacyLineage])),
    /recognised explicit source lineage required/,
  );
});

test("authored score and procedural sound sources retain exact project-owned lineage", () => {
  const symbolic = Buffer.from("symbolic score source");
  const procedural = Buffer.from("procedural soundscape source");
  const projectSource = (sourceID, sourceKind, sourcePath, bytes) => ({
    lineageType: "PROJECT_AUTHORED_AUDIO",
    sourceID,
    sourceKind,
    sourcePath,
    bytes: bytes.byteLength,
    sha256: sha256(bytes),
    rightsBasis: "PROJECT_OWNED",
    license: "Project-owned authored audio source",
  });

  const scoreRegistry = audioShippingRegistry([
    projectSource("harvest-symbolic-score", "SYMBOLIC_SCORE", "native/audio/score-soundscape/harvest-score-technique.json", symbolic),
  ]);
  const projectFiles = new Map([
    ["native/audio/score-soundscape/harvest-score-technique.json", {
      bytes: symbolic.byteLength,
      sha256: sha256(symbolic),
    }],
    ["native/audio/score-soundscape/harvest-soundscape-technique.json", {
      bytes: procedural.byteLength,
      sha256: sha256(procedural),
    }],
  ]);
  assert.equal(validateNativeAssetProvenanceLineage(scoreRegistry, undefined, projectFiles), scoreRegistry);

  const soundscapeRegistry = audioShippingRegistry([
    projectSource("harvest-procedural-patch", "PROCEDURAL_PATCH", "native/audio/score-soundscape/harvest-soundscape-technique.json", procedural),
  ], "soundscape");
  assert.equal(validateNativeAssetProvenanceLineage(soundscapeRegistry, undefined, projectFiles), soundscapeRegistry);

  const fabricated = structuredClone(scoreRegistry);
  fabricated.assets[0].sourceLineage[0].sha256 = "0".repeat(64);
  assert.throws(
    () => validateNativeAssetProvenanceLineage(fabricated, undefined, projectFiles),
    /does not match actual project bytes/,
  );

  assert.throws(
    () => validateNativeAssetProvenanceLineage(shippingRegistry(scoreRegistry.assets[0].sourceLineage)),
    /restricted to audio shipping roles/,
  );
});

test("open-licensed audio sources distinguish CC0 from notice-bearing MIT inputs", () => {
  const source = Buffer.from("licensed audio source");
  const cc0 = {
    lineageType: "OPEN_LICENSE_AUDIO_SOURCE",
    sourceID: "cc0-material-source",
    sourceURL: "https://example.invalid/source.wav",
    title: "Material source",
    creator: "Recorded creator",
    bytes: source.byteLength,
    sha256: sha256(source),
    licenseSPDX: "CC0-1.0",
    licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/legalcode",
    requiredNotices: [],
  };
  const cc0Registry = audioShippingRegistry([cc0], "soundscape");
  assert.equal(validateNativeAssetProvenanceLineage(cc0Registry), cc0Registry);

  const mit = {
    ...cc0,
    sourceID: "mit-score-source",
    licenseSPDX: "MIT",
    licenseURL: "https://example.invalid/LICENSE",
    requiredNotices: ["Copyright and MIT permission notice retained"],
    noticePath: "native/audio/notices/source-license.md",
    noticeBytes: source.byteLength,
    noticeSHA256: sha256(source),
  };
  const mitRegistry = audioShippingRegistry([mit]);
  const projectFiles = new Map([[mit.noticePath, {
    bytes: mit.noticeBytes,
    sha256: mit.noticeSHA256,
  }]]);
  assert.equal(validateNativeAssetProvenanceLineage(mitRegistry, undefined, projectFiles), mitRegistry);

  const missingNotice = { ...mit, requiredNotices: [] };
  assert.throws(
    () => validateNativeAssetProvenanceLineage(audioShippingRegistry([missingNotice]), undefined, projectFiles),
    /MIT source notice required/,
  );
});

test("MS Basic score lineage binds the exact bank, full toolchain and physical notice", () => {
  const symbolic = Buffer.from("symbolic production score");
  const authored = {
    lineageType: "PROJECT_AUTHORED_AUDIO",
    sourceID: "harvest-symbolic-production-score",
    sourceKind: "SYMBOLIC_SCORE",
    sourcePath: "native/audio/score-soundscape/harvest-score-technique.json",
    bytes: symbolic.byteLength,
    sha256: sha256(symbolic),
    rightsBasis: "PROJECT_OWNED",
    license: "Project-owned authored audio source",
  };
  const bank = {
    lineageType: "OPEN_LICENSE_AUDIO_SOURCE",
    sourceID: "musescore-ms-basic-0-2-0",
    sourceURL: "https://raw.githubusercontent.com/musescore/MuseScore/03c4afd5c9ae72b2698f6716e9e244ce53550495/share/sound/MS%20Basic.sf3",
    title: "MS Basic 0.2.0",
    creator: "MuseScore contributors; FluidR3 and credited sample contributors",
    bytes: 51_278_610,
    sha256: "5ea2375e8bd7d8e71def1036978c1621e85b66934169b6a2744b27b9b3c2d99c",
    licenseSPDX: "MIT",
    licenseURL: "https://raw.githubusercontent.com/musescore/MuseScore/03c4afd5c9ae72b2698f6716e9e244ce53550495/share/sound/MS%20Basic_License.md",
    requiredNotices: ["Full pinned upstream acknowledgements and MIT permission notice retained"],
    noticePath: "native/audio/score-soundscape/licenses/MS-Basic-0.2.0-LICENSE.md",
    noticeBytes: 3_320,
    noticeSHA256: "bf7db123b5d6c0beb1a37f6e1b11c6f4dfd8fb6abd5d59ff282ea24a5cd932e5",
  };
  const registry = audioShippingRegistry([authored, bank]);
  registry.assets[0].toolLineage = [
    { toolID: "audio-production-local" },
    { toolID: "fluid-synth-local" },
    { toolID: "musescore-ms-basic-sf3" },
    { toolID: "authored-score-rendering" },
  ];
  const projectFiles = new Map([
    [authored.sourcePath, { bytes: authored.bytes, sha256: authored.sha256 }],
    [bank.noticePath, { bytes: bank.noticeBytes, sha256: bank.noticeSHA256 }],
  ]);
  assert.equal(validateNativeAssetProvenanceLineage(registry, undefined, projectFiles), registry);

  const missingBank = structuredClone(registry);
  missingBank.assets[0].sourceLineage = [authored];
  assert.throws(
    () => validateNativeAssetProvenanceLineage(missingBank, undefined, projectFiles),
    /exact MS Basic MIT source record required/,
  );

  const missingNoticeBytes = new Map(projectFiles);
  missingNoticeBytes.delete(bank.noticePath);
  assert.throws(
    () => validateNativeAssetProvenanceLineage(registry, undefined, missingNoticeBytes),
    /MIT notice path\/hash does not match actual project bytes/,
  );
});

test("unknown or undocumented Apple audio remains fail closed", () => {
  const source = Buffer.from("apple source");
  const apple = {
    lineageType: "APPLE_LICENSED_AUDIO_SOURCE",
    sourceID: "undocumented-apple-audio",
    bytes: source.byteLength,
    sha256: sha256(source),
  };
  assert.throws(
    () => validateNativeAssetProvenanceLineage(audioShippingRegistry([apple])),
    /recognised explicit source lineage required/,
  );
});

test("web lineage fails closed when the authoritative inventory is unavailable", async () => {
  const inventory = await authoritativeInventory();
  const eligible = inventory.assets.find((asset) => asset.allowedAsNativeRawMaterial);
  assert.throws(
    () => validateNativeAssetProvenanceLineage(shippingRegistry([webLineage(eligible)])),
    /authoritative web source inventory required/,
  );
});
