import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import {
  lstat,
  mkdir,
  readFile,
  readdir,
  stat,
  symlink,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import {
  backgroundAssetsArchiveStatuses,
  canonicalBackgroundAssetManifest,
  packagePaidLaunchBackgroundAssets,
  verifyBackgroundAssetsArchiveSet,
} from "../src/background-assets-archive.mjs";
import { compileLaunchSet } from "../src/launch-set-compile.mjs";
import { createLaunchSetFixture } from "./launch-set-compile.test.mjs";

const execFileAsync = promisify(execFile);

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalValue(value[key])]),
    );
  }
  return value;
}

function canonicalJSON(value) {
  return Buffer.from(JSON.stringify(canonicalValue(value)), "utf8");
}

async function writeApprovedTrust(fixture) {
  const jwk = fixture.publicKey.export({ format: "jwk" });
  const x963 = Buffer.concat([
    Buffer.from([0x04]),
    Buffer.from(jwk.x, "base64url"),
    Buffer.from(jwk.y, "base64url"),
  ]);
  const trust = canonicalJSON({
    schemaVersion: 1,
    keys: [{
      id: fixture.options.keyID,
      x963PublicKeyBase64: x963.toString("base64"),
    }],
  });
  const approval = canonicalJSON({
    schemaVersion: 1,
    trustFileSHA256: sha256(trust),
    keys: [{
      id: fixture.options.keyID,
      x963PublicKeySHA256: sha256(x963),
    }],
  });
  const controls = path.join(fixture.temporary, "release-controls");
  await mkdir(controls, { recursive: true });
  const trustResourcePath = path.join(controls, "launch-package-trust.json");
  const approvedTrustReceiptPath = path.join(controls, "approved-trust-receipt.json");
  await writeFile(trustResourcePath, trust);
  await writeFile(approvedTrustReceiptPath, approval);
  return { trustResourcePath, approvedTrustReceiptPath };
}

async function createCompiledFixture(context) {
  const fixture = await createLaunchSetFixture(context);
  const launchSetRoot = path.join(fixture.temporary, "submission", "launch-set");
  await compileLaunchSet(fixture.descriptor, launchSetRoot, fixture.options);
  const trust = await writeApprovedTrust(fixture);
  return {
    ...fixture,
    ...trust,
    launchSetRoot,
    outputRoot: path.join(fixture.temporary, "submission", "background-assets"),
  };
}

function packagingOptions(fixture) {
  return {
    launchConfiguration: fixture.options.launchConfiguration,
    trustResourcePath: fixture.trustResourcePath,
    approvedTrustReceiptPath: fixture.approvedTrustReceiptPath,
    outputStatus: backgroundAssetsArchiveStatuses.nonShippingFixture,
  };
}

test("node test fixtures cannot accidentally emit a production-status receipt", async () => {
  await assert.rejects(
    packagePaidLaunchBackgroundAssets("/tmp/non-shipping-input", "/tmp/non-shipping-output", {
      launchConfiguration: {},
      trustResourcePath: "/tmp/non-shipping-trust.json",
      approvedTrustReceiptPath: "/tmp/non-shipping-trust-receipt.json",
    }),
    /must use explicit NON_SHIPPING_TEST_FIXTURE status/u,
  );
});

test("installed xcrun ba-package creates exactly seven receipted paid launch archives", async (context) => {
  const fixture = await createCompiledFixture(context);
  const receipt = await packagePaidLaunchBackgroundAssets(
    fixture.launchSetRoot,
    fixture.outputRoot,
    packagingOptions(fixture),
  );

  const expectedPaidIDs = fixture.expectedPackageIDs.slice(1);
  assert.equal(receipt.status, "NON_SHIPPING_TEST_FIXTURE");
  assert.deepEqual(receipt.packages.map((record) => record.packageID), expectedPaidIDs);
  assert.equal(receipt.packages.some((record) => record.packageID === "essential-free-v1"), false);
  assert.deepEqual(
    await verifyBackgroundAssetsArchiveSet(fixture.outputRoot, expectedPaidIDs),
    receipt,
  );
  assert.deepEqual(
    (await readdir(fixture.outputRoot)).sort(),
    ["archives", "background-assets-receipt.json", "manifests"],
  );

  for (const record of receipt.packages) {
    assert.equal(record.assetPackID, record.packageID);
    assert.equal(record.selector, `packages/${record.packageID}`);
    assert.ok(record.archiveBytes > 0);
    assert.ok(record.archiveBytes <= record.archiveMaximumBytes);
    const manifestBytes = await readFile(path.join(fixture.outputRoot, record.baManifestPath));
    assert.deepEqual(JSON.parse(manifestBytes), canonicalBackgroundAssetManifest(record.packageID));
    assert.equal(sha256(manifestBytes), record.baManifestSHA256);
    const signedManifestBytes = await readFile(path.join(
      fixture.launchSetRoot,
      "packages",
      record.packageID,
      "package-manifest.json",
    ));
    assert.equal(sha256(signedManifestBytes), record.packageManifestSHA256);
  }

  const firstArchive = path.join(fixture.outputRoot, receipt.packages[0].archivePath);
  const { stdout } = await execFileAsync("aa", ["list", "-i", firstArchive], {
    encoding: "utf8",
    maxBuffer: 4 * 1_024 * 1_024,
  });
  assert.match(stdout, /packages\/paid-pack-01\/package-manifest\.json/u);
  assert.match(stdout, /Manifest\.json/u);

});

test("an unchanged rerun verifies and reuses the same archive set", async (context) => {
  const fixture = await createCompiledFixture(context);
  const first = await packagePaidLaunchBackgroundAssets(
    fixture.launchSetRoot,
    fixture.outputRoot,
    packagingOptions(fixture),
  );
  const archive = path.join(fixture.outputRoot, first.packages[0].archivePath);
  const before = await stat(archive);

  const second = await packagePaidLaunchBackgroundAssets(
    fixture.launchSetRoot,
    fixture.outputRoot,
    packagingOptions(fixture),
  );
  const after = await stat(archive);
  assert.deepEqual(second, first);
  assert.equal(after.ino, before.ino);
  assert.equal(after.mtimeMs, before.mtimeMs);
});

test("tampered input fails closed and preserves the previously published archives", async (context) => {
  const fixture = await createCompiledFixture(context);
  const prior = await packagePaidLaunchBackgroundAssets(
    fixture.launchSetRoot,
    fixture.outputRoot,
    packagingOptions(fixture),
  );
  const receiptBefore = await readFile(
    path.join(fixture.outputRoot, "background-assets-receipt.json"),
  );
  const tamperedAsset = path.join(
    fixture.launchSetRoot,
    "packages",
    "paid-pack-04",
    "assets",
    "world.heif",
  );
  await writeFile(tamperedAsset, "tampered after signed compilation");

  await assert.rejects(
    packagePaidLaunchBackgroundAssets(
      fixture.launchSetRoot,
      fixture.outputRoot,
      packagingOptions(fixture),
    ),
    /size or SHA-256 mismatch/u,
  );
  assert.deepEqual(
    await readFile(path.join(fixture.outputRoot, "background-assets-receipt.json")),
    receiptBefore,
  );
  assert.equal(
    (await verifyBackgroundAssetsArchiveSet(fixture.outputRoot)).receiptSHA256,
    prior.receiptSHA256,
  );
});

test("symbolic links and foreign launch-root files are rejected before packaging", async (context) => {
  const symlinkFixture = await createCompiledFixture(context);
  await symlink(
    path.join(symlinkFixture.launchSetRoot, "launch-set-receipt.json"),
    path.join(symlinkFixture.launchSetRoot, "receipt-alias.json"),
  );
  await assert.rejects(
    packagePaidLaunchBackgroundAssets(
      symlinkFixture.launchSetRoot,
      symlinkFixture.outputRoot,
      packagingOptions(symlinkFixture),
    ),
    /symbolic links are forbidden/u,
  );
  assert.equal(await lstat(symlinkFixture.outputRoot).catch(() => null), null);

  const foreignFixture = await createCompiledFixture(context);
  await writeFile(path.join(foreignFixture.launchSetRoot, "backstage-notes.json"), "{}");
  await assert.rejects(
    packagePaidLaunchBackgroundAssets(
      foreignFixture.launchSetRoot,
      foreignFixture.outputRoot,
      packagingOptions(foreignFixture),
    ),
    /only launch-set-receipt\.json and packages/u,
  );
  assert.equal(await lstat(foreignFixture.outputRoot).catch(() => null), null);
});

test("unapproved trust bytes cannot verify or replace an existing archive set", async (context) => {
  const fixture = await createCompiledFixture(context);
  const prior = await packagePaidLaunchBackgroundAssets(
    fixture.launchSetRoot,
    fixture.outputRoot,
    packagingOptions(fixture),
  );
  const approval = JSON.parse(await readFile(fixture.approvedTrustReceiptPath));
  approval.trustFileSHA256 = "0".repeat(64);
  await writeFile(fixture.approvedTrustReceiptPath, canonicalJSON(approval));

  await assert.rejects(
    packagePaidLaunchBackgroundAssets(
      fixture.launchSetRoot,
      fixture.outputRoot,
      packagingOptions(fixture),
    ),
    /trust resource bytes or key do not match approval/u,
  );
  assert.equal(
    (await verifyBackgroundAssetsArchiveSet(fixture.outputRoot)).receiptSHA256,
    prior.receiptSHA256,
  );
});
