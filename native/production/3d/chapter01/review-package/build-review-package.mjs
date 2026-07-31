#!/usr/bin/env node

import {
  createHash,
} from "node:crypto";
import { execFile } from "node:child_process";
import { createReadStream } from "node:fs";
import {
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rename,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import {
  manifestIntegrityMaterial,
  publicKeyX963Base64,
  requireInstalledByteBudget,
  validatePackageManifest,
  verifyCompiledPackage,
  verifyPackageManifest,
} from "../../../../tooling/src/compile.mjs";
import {
  deterministicDevelopmentPublicKey,
  signDeterministicDevelopmentMessage,
} from "../../../../tooling/src/deterministic-development-signing.mjs";
import { chapter01ImmersiveReviewIdentity } from "../../../../tooling/src/development-trust.mjs";

const execFileAsync = promisify(execFile);
const root = path.dirname(fileURLToPath(import.meta.url));
const nativeRoot = path.resolve(root, "../../../..");
const repositoryRoot = path.resolve(nativeRoot, "..");
const iosRoot = path.join(nativeRoot, "ios");
const outputRoot = path.join(
  root,
  "compiled/first-farmers-3d-review-v1.runtimefixture",
);
const backstageRoot = path.join(root, "backstage");
const payloadPath = "chapters/first-farmers-3d-review-v1.json";
const packageVersion = Object.freeze({ major: 1, minor: 0, patch: 0 });
const schemaVersion = Object.freeze({ major: 2, minor: 0, patch: 0 });
const minimumRuntime = Object.freeze({ major: 2, minor: 0, patch: 0 });
const maximumInstalledBytes = 200_000_000;
const expectedPublicAssetCount = 34;

const responsiveRoot = path.join(
  nativeRoot,
  "audio/score-soundscape/distribution-cache/first-farmers-aac-lc-384-alac-fallback-v1/audio/first-farmers",
);
const transitionRoot = path.join(
  nativeRoot,
  "audio/score-soundscape/chapter-01-review-transitions-v1/audio",
);

const cellSources = Object.freeze([
  "production/3d/chapter01/generated/aegean-crossing-v1/aegean-crossing-lod0.usdz",
  "production/3d/chapter01/thessaly/outputs/thessaly-household-store.usdz",
  "production/3d/chapter01/iron-gates/exports/iron-gates.usdz",
  "production/3d/chapter01/longhouse/exports/longhouse.usdz",
  "production/3d/chapter01/settlement/exports/settlement.usdz",
]);
const directedAnimationSource = path.join(
  nativeRoot,
  "production/3d/chapter01/animation-library/generated/chapter01-directed-animation-library.usdz",
);
const materialCarrierSource = path.join(
  nativeRoot,
  "production/3d/chapter01/material-library/generated/carrier/chapter01-material-carrier-v1.usdz",
);
const programNames = Object.freeze([
  "household-crosses-responsive-v1",
  "harvest-responsive-v1",
  "three-records-responsive-v1",
  "longhouse-responsive-v1",
  "more-mouths-responsive-v1",
  "continent-remade-responsive-v1",
]);

function twoDigits(value) {
  return String(value).padStart(2, "0");
}

function packageAssetPath(group, number, extension) {
  return `immersive/first-farmers/${group}/${group === "cells" ? "cell" : group === "materials" ? "material" : "action"}-${twoDigits(number)}.${extension}`;
}

const assetMappings = Object.freeze([
  ...cellSources.map((source, index) => Object.freeze({
    packagePath: packageAssetPath("cells", index + 1, "usdz"),
    sourcePath: path.join(nativeRoot, source),
    authority: "CONTINUITY_PROOF_USDZ",
  })),
  Object.freeze({
    packagePath:
      "immersive/first-farmers/materials/chapter01-material-carrier-v1.usdz",
    sourcePath: materialCarrierSource,
    authority: "MOBILE_PBR_MATERIAL_CANDIDATE",
  }),
  Object.freeze({
    packagePath:
      "immersive/first-farmers/animations/chapter01-directed-animation-library-v1.usdz",
    sourcePath: directedAnimationSource,
    authority: "DIRECTED_ANIMATION_CONTACT_CANDIDATE",
  }),
  ...programNames.slice(0, 5).map((program, index) => Object.freeze({
    packagePath: `immersive/first-farmers/audio/environment-${twoDigits(index + 1)}.m4a`,
    sourcePath: path.join(responsiveRoot, program, "approach/soundscape-master.m4a"),
    authority: "PROVISIONAL_EXISTING_REVIEW_SOUNDSCAPE",
  })),
  ...programNames.map((program, index) => Object.freeze({
    packagePath: `immersive/first-farmers/audio/mechanism-${twoDigits(index + 1)}.m4a`,
    sourcePath: path.join(
      responsiveRoot,
      program,
      index === 2
        ? "consequence/spatial-detail-master.m4a"
        : "engaged/spatial-detail-master.m4a",
    ),
    authority: "PROVISIONAL_EXISTING_REVIEW_MECHANISM",
  })),
  ...[
    path.join(transitionRoot, "transition-aegean-thessaly-v1.m4a"),
    path.join(responsiveRoot, programNames[1], "consequence/soundscape-master.m4a"),
    path.join(transitionRoot, "transition-store-iron-gates-v1.m4a"),
    path.join(responsiveRoot, programNames[2], "consequence/soundscape-master.m4a"),
    path.join(responsiveRoot, programNames[3], "consequence/soundscape-master.m4a"),
    path.join(transitionRoot, "transition-farming-belt-steppe-v1.m4a"),
  ].map((sourcePath, index) => Object.freeze({
    packagePath: `immersive/first-farmers/audio/transition-${twoDigits(index + 1)}.m4a`,
    sourcePath,
    authority: "PROVISIONAL_EXISTING_REVIEW_TRANSITION",
  })),
  ...(Array.from({ length: 10 }, (_, index) => Object.freeze({
    packagePath: `immersive/first-farmers/audio/narration-${twoDigits(index + 1)}.m4a`,
    sourcePath: path.join(root, `provisional-audio/narration-${twoDigits(index + 1)}.m4a`),
    authority: "NON_SHIPPING_SYSTEM_VOICE_TECHNICAL_BINDING",
  }))),
]);

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function hashFile(file) {
  const hasher = createHash("sha256");
  let bytes = 0;
  for await (const chunk of createReadStream(file)) {
    bytes += chunk.byteLength;
    hasher.update(chunk);
  }
  return { bytes, sha256: hasher.digest("hex") };
}

function sortedRecords(records) {
  return [...records].sort((left, right) =>
    Buffer.compare(Buffer.from(left.path), Buffer.from(right.path)));
}

function signManifest(records) {
  const unsigned = {
    packageID: chapter01ImmersiveReviewIdentity.packageID,
    packageVersion,
    schemaVersion,
    minimumRuntime,
    files: sortedRecords(records),
  };
  const material = manifestIntegrityMaterial(unsigned);
  const manifestDigest = sha256(Buffer.from(material, "utf8"));
  const manifest = {
    ...unsigned,
    manifestDigest,
    signature: {
      algorithm: "P-256-SHA256",
      keyID: chapter01ImmersiveReviewIdentity.keyID,
      value: signDeterministicDevelopmentMessage(
        Buffer.from(manifestDigest, "utf8"),
      ).toString("base64"),
    },
  };
  validatePackageManifest(manifest);
  verifyPackageManifest(
    manifest,
    deterministicDevelopmentPublicKey(),
    chapter01ImmersiveReviewIdentity.keyID,
  );
  return manifest;
}

async function publishAtomically(stagingRoot) {
  await mkdir(path.dirname(outputRoot), { recursive: true });
  const backup = `${outputRoot}.previous`;
  await rm(backup, { recursive: true, force: true });
  if (await stat(outputRoot).catch(() => null)) await rename(outputRoot, backup);
  try {
    await rename(stagingRoot, outputRoot);
    await rm(backup, { recursive: true, force: true });
  } catch (error) {
    if (!await stat(outputRoot).catch(() => null)
        && await stat(backup).catch(() => null)) {
      await rename(backup, outputRoot);
    }
    throw error;
  }
}

function requirePublicPayloadShape(payload, assetRecords, narrationTexts) {
  const expectedTopLevel = [
    "assets", "audioBindings", "captions", "chapterID", "narrationBindings",
    "packageID", "pacing", "schemaVersion", "sequences", "streamingPolicy",
    "transitions", "worldCells",
  ].sort();
  if (JSON.stringify(Object.keys(payload).sort()) !== JSON.stringify(expectedTopLevel)
      || payload.packageID !== chapter01ImmersiveReviewIdentity.packageID
      || payload.chapterID !== "first-farmers"
      || payload.schemaVersion?.major !== 2
      || payload.worldCells?.length !== 5
      || payload.sequences?.length !== 6
      || payload.sequences.flatMap(({ beats }) => beats).length !== 34
      || payload.assets?.length !== assetRecords.length
      || JSON.stringify(payload.narrationBindings?.map(({ text }) => text.launchEnglish))
        !== JSON.stringify(narrationTexts)) {
    throw new Error(`Swift compiler emitted an invalid Chapter 01 V2 authority shape: ${JSON.stringify({
      keys: Object.keys(payload).sort(),
      packageID: payload.packageID,
      chapterID: payload.chapterID,
      schemaVersion: payload.schemaVersion,
      worldCellCount: payload.worldCells?.length,
      sequenceCount: payload.sequences?.length,
      beatCount: payload.sequences?.flatMap(({ beats }) => beats).length,
      assetCount: payload.assets?.length,
      expectedAssetCount: assetRecords.length,
    })}`);
  }
  const expectedByPath = new Map(assetRecords.map((record) => [record.path, record]));
  for (const asset of payload.assets) {
    const record = expectedByPath.get(asset.path);
    if (!record || asset.byteCount !== record.bytes || asset.sha256 !== record.sha256) {
      throw new Error(`V2 inner integrity is not bound to ${asset.path}`);
    }
  }
  if (new Set(payload.assets.map(({ path: value }) => value)).size !== assetRecords.length) {
    throw new Error("V2 asset paths are not unique");
  }
}

async function requireProvisionalNarrationAuthority() {
  const scriptPath = path.join(backstageRoot, "provisional-narration-script.json");
  const receiptPath = path.join(backstageRoot, "provisional-narration-receipt.json");
  const [scriptBytes, receiptBytes] = await Promise.all([
    readFile(scriptPath),
    readFile(receiptPath),
  ]);
  const script = JSON.parse(scriptBytes);
  const receipt = JSON.parse(receiptBytes);
  if (script.status !== "NON_SHIPPING_TECHNICAL_REVIEW_AUDIO"
      || script.shippingState !== "PROHIBITED"
      || script.cues?.length !== 10
      || receipt.status !== script.status
      || receipt.shippingState !== "PROHIBITED"
      || receipt.finalNarrationGate !== "OPEN"
      || receipt.outputsAreFrozenPackageInputs !== true
      || receipt.generatorReproducibilityAuthority !== false
      || receipt.sourceScriptSHA256 !== sha256(scriptBytes)
      || receipt.outputs?.length !== 10) {
    throw new Error("provisional narration backstage authority is invalid");
  }
  const outputByID = new Map(receipt.outputs.map((output) => [output.id, output]));
  for (const cue of script.cues) {
    const output = outputByID.get(cue.id);
    const sourcePath = path.join(root, `provisional-audio/${cue.id}.m4a`);
    const actual = await hashFile(sourcePath);
    if (!output || output.bytes !== actual.bytes || output.sha256 !== actual.sha256
        || output.textSHA256 !== sha256(Buffer.from(cue.text, "utf8"))) {
      throw new Error(`${cue.id}: frozen provisional narration authority drifted`);
    }
  }
  return script.cues.map(({ text }) => text);
}

async function main() {
  if (assetMappings.length !== expectedPublicAssetCount
      || new Set(assetMappings.map(({ packagePath: value }) => value)).size
        !== expectedPublicAssetCount) {
    throw new Error(
      `Chapter 01 V2 requires exactly ${expectedPublicAssetCount} unique public assets`,
    );
  }
  const narrationTexts = await requireProvisionalNarrationAuthority();
  const sourceSnapshot = new Map();
  for (const mapping of assetMappings) {
    const source = await stat(mapping.sourcePath).catch(() => null);
    if (!source?.isFile() || source.size <= 0) {
      throw new Error(`required review asset is missing: ${mapping.sourcePath}`);
    }
    sourceSnapshot.set(mapping.sourcePath, await hashFile(mapping.sourcePath));
  }

  await mkdir(path.dirname(outputRoot), { recursive: true });
  const stagingRoot = await mkdtemp(path.join(
    path.dirname(outputRoot),
    ".first-farmers-3d-review-v1.staging-",
  ));
  const compilerRoot = await mkdtemp(path.join(
    path.dirname(outputRoot),
    ".first-farmers-3d-review-v1.compiler-",
  ));
  try {
    const assetRecords = [];
    for (const mapping of assetMappings) {
      const destination = path.join(stagingRoot, ...mapping.packagePath.split("/"));
      await mkdir(path.dirname(destination), { recursive: true });
      await copyFile(mapping.sourcePath, destination);
      const record = { path: mapping.packagePath, ...await hashFile(destination) };
      const expected = sourceSnapshot.get(mapping.sourcePath);
      if (record.bytes !== expected.bytes || record.sha256 !== expected.sha256) {
        throw new Error(`review source changed during copy: ${mapping.sourcePath}`);
      }
      assetRecords.push(record);
    }

    const integrityPath = path.join(compilerRoot, "asset-integrity.json");
    await writeFile(integrityPath, JSON.stringify({
      assets: sortedRecords(assetRecords).map((record) => ({
        path: record.path,
        sha256: record.sha256,
        byteCount: record.bytes,
      })),
    }));
    const payloadURL = path.join(stagingRoot, ...payloadPath.split("/"));
    await mkdir(path.dirname(payloadURL), { recursive: true });
    await execFileAsync("swift", [
      "run", "--quiet",
      "--package-path", iosRoot,
      "immersive-review-payload-compiler",
      integrityPath,
      payloadURL,
    ], { maxBuffer: 8 * 1024 * 1024 });
    const payloadBytes = await readFile(payloadURL);
    requirePublicPayloadShape(JSON.parse(payloadBytes), assetRecords, narrationTexts);

    const records = sortedRecords([
      ...assetRecords,
      { path: payloadPath, ...await hashFile(payloadURL) },
    ]);
    const manifest = signManifest(records);
    const manifestBytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8");
    requireInstalledByteBudget(records, manifestBytes.length, maximumInstalledBytes);
    await writeFile(path.join(stagingRoot, "package-manifest.json"), manifestBytes, {
      flag: "wx",
    });
    await verifyCompiledPackage(
      stagingRoot,
      deterministicDevelopmentPublicKey(),
      chapter01ImmersiveReviewIdentity.keyID,
      {
        id: chapter01ImmersiveReviewIdentity.packageID,
        version: packageVersion,
        minimumRuntime,
        maximumInstalledBytes,
      },
    );

    await publishAtomically(stagingRoot);
    const publicKey = deterministicDevelopmentPublicKey();
    await mkdir(backstageRoot, { recursive: true });
    const trustReceipt = {
      schemaVersion: 1,
      kind: chapter01ImmersiveReviewIdentity.receiptKind,
      trustDomain: chapter01ImmersiveReviewIdentity.trustDomain,
      packageID: chapter01ImmersiveReviewIdentity.packageID,
      chapterID: "first-farmers",
      packageVersion,
      schemaVersionBound: schemaVersion,
      minimumRuntime,
      keyID: chapter01ImmersiveReviewIdentity.keyID,
      manifestDigest: manifest.manifestDigest,
      shippingState: chapter01ImmersiveReviewIdentity.shippingState,
      trustedPublicKeyX963Base64: publicKeyX963Base64(publicKey),
      trustedPublicKeySPKIBase64: publicKey
        .export({ format: "der", type: "spki" }).toString("base64"),
    };
    await writeFile(
      path.join(backstageRoot, "review-trust-receipt.json"),
      `${JSON.stringify(trustReceipt, null, 2)}\n`,
    );
    const qualityAuthority = {
      schemaVersion: 1,
      packageID: chapter01ImmersiveReviewIdentity.packageID,
      chapterID: "first-farmers",
      status: "NON_SHIPPING_IMMERSIVE_CONTINUITY_PROOF",
      shippingState: "PROHIBITED",
      gates: {
        finalArt: "OPEN",
        finalCharacterAndAnimation: "OPEN",
        finalScoreAndSoundscape: "OPEN",
        finalNarration: "OPEN",
        physicalIPhone: "OPEN",
      },
      publicPackageContainsBackstageMetadata: false,
      assetSources: sortedRecords(assetMappings.map((mapping) => {
        const integrity = sourceSnapshot.get(mapping.sourcePath);
        return {
          path: mapping.packagePath,
          repositorySource: path.relative(repositoryRoot, mapping.sourcePath)
            .split(path.sep).join("/"),
          sourceStatus: mapping.authority,
          bytes: integrity.bytes,
          sha256: integrity.sha256,
        };
      })),
    };
    await writeFile(
      path.join(backstageRoot, "review-quality-authority.json"),
      `${JSON.stringify(qualityAuthority, null, 2)}\n`,
    );
  } catch (error) {
    await rm(stagingRoot, { recursive: true, force: true }).catch(() => {});
    throw error;
  } finally {
    await rm(compilerRoot, { recursive: true, force: true }).catch(() => {});
  }
}

await main();
