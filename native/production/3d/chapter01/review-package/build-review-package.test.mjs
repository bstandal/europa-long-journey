import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import {
  cp,
  mkdtemp,
  readFile,
  readdir,
  rm,
  unlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { verifyCompiledPackage } from "../../../../tooling/src/compile.mjs";
import { deterministicDevelopmentPublicKey } from "../../../../tooling/src/deterministic-development-signing.mjs";
import { chapter01ImmersiveReviewIdentity } from "../../../../tooling/src/development-trust.mjs";

const execFileAsync = promisify(execFile);
const root = path.dirname(fileURLToPath(import.meta.url));
const buildScript = path.join(root, "build-review-package.mjs");
const packageRoot = path.join(
  root,
  "compiled/first-farmers-3d-review-v1.runtimefixture",
);
const expectedPackage = Object.freeze({
  id: chapter01ImmersiveReviewIdentity.packageID,
  version: { major: 1, minor: 0, patch: 0 },
  minimumRuntime: { major: 2, minor: 0, patch: 0 },
  maximumInstalledBytes: 200_000_000,
});

async function filesUnder(directory) {
  const output = [];
  const entries = await readdir(directory, { withFileTypes: true });
  for (const entry of entries.sort((left, right) =>
    Buffer.compare(Buffer.from(left.name), Buffer.from(right.name)))) {
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) output.push(...await filesUnder(candidate));
    else if (entry.isFile()) output.push(candidate);
  }
  return output;
}

async function snapshot(directory) {
  return Object.fromEntries(await Promise.all((await filesUnder(directory)).map(async (file) => [
    path.relative(directory, file).split(path.sep).join("/"),
    createHash("sha256").update(await readFile(file)).digest("hex"),
  ])));
}

async function verify(directory) {
  return verifyCompiledPackage(
    directory,
    deterministicDevelopmentPublicKey(),
    chapter01ImmersiveReviewIdentity.keyID,
    expectedPackage,
  );
}

function allKeys(value, output = []) {
  if (Array.isArray(value)) {
    value.forEach((item) => allKeys(item, output));
  } else if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      output.push(key);
      allKeys(child, output);
    }
  }
  return output;
}

async function withPackageCopy(operation) {
  const temporary = await mkdtemp(path.join(os.tmpdir(), "chapter01-v2-package-test-"));
  const candidate = path.join(temporary, "package");
  try {
    await cp(packageRoot, candidate, { recursive: true });
    await operation(candidate);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

test("Chapter 01 V2 review package rebuilds byte-identically", async () => {
  await execFileAsync(process.execPath, [buildScript]);
  const first = await snapshot(packageRoot);
  await execFileAsync(process.execPath, [buildScript]);
  const second = await snapshot(packageRoot);
  assert.deepEqual(second, first);

  const manifest = await verify(packageRoot);
  assert.equal(manifest.packageID, chapter01ImmersiveReviewIdentity.packageID);
  assert.deepEqual(manifest.schemaVersion, { major: 2, minor: 0, patch: 0 });
  const payload = JSON.parse(await readFile(path.join(
    packageRoot,
    "chapters/first-farmers-3d-review-v1.json",
  )));
  assert.equal(payload.assets.length, 34);
  assert.equal(manifest.files.length, payload.assets.length + 1);
  assert.equal(payload.assets.filter(({ kind }) => kind === "scene-graph").length, 5);
  assert.equal(payload.assets.filter(({ kind }) => kind === "material").length, 1);
  assert.equal(payload.assets.filter(({ kind }) => kind === "animation").length, 1);
  const keys = new Set(allKeys(payload));
  for (const backstageKey of [
    "status", "shippingState", "gates", "finalArtGate", "sourceStatus",
    "repositorySource", "provenance", "confidence", "researchNotes",
  ]) {
    assert.equal(keys.has(backstageKey), false, backstageKey);
  }
});

test("signed V2 package rejects missing, corrupt and tampered bytes", async () => {
  const asset = "immersive/first-farmers/cells/cell-01.usdz";
  const payload = "chapters/first-farmers-3d-review-v1.json";

  await withPackageCopy(async (candidate) => {
    await unlink(path.join(candidate, asset));
    await assert.rejects(() => verify(candidate), /installed tree does not match/u);
  });

  await withPackageCopy(async (candidate) => {
    const file = path.join(candidate, asset);
    const bytes = await readFile(file);
    const corrupt = Buffer.from(bytes);
    corrupt[Math.floor(corrupt.length / 2)] ^= 0xff;
    await writeFile(file, corrupt);
    await assert.rejects(() => verify(candidate), /size or SHA-256 mismatch/u);
  });

  await withPackageCopy(async (candidate) => {
    const file = path.join(candidate, payload);
    const bytes = await readFile(file);
    const tampered = Buffer.from(bytes);
    const offset = tampered.indexOf(Buffer.from("first-farmers", "utf8"));
    assert.ok(offset >= 0);
    tampered[offset] = "x".charCodeAt(0);
    await writeFile(file, tampered);
    await assert.rejects(() => verify(candidate), /size or SHA-256 mismatch/u);
  });
});
