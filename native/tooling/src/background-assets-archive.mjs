import { execFile } from "node:child_process";
import {
  ECDH,
  createHash,
  createPublicKey,
} from "node:crypto";
import { createReadStream } from "node:fs";
import {
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { promisify } from "node:util";
import { verifyCompiledPackage } from "./compile.mjs";
import { validateLaunchAssembly } from "./launch-assembly.mjs";
import {
  validateLaunchSetReceipt,
} from "./launch-set-compile.mjs";
import {
  allowedPublicExtensions,
  allowedPublicTopLevel,
  forbiddenPathSegments,
  normalizePolicyName,
} from "./policy.mjs";
import {
  ValidationError,
  collectShippingAssetReferences,
  validateCollectionAgainstLaunchConfiguration,
  validatePublicDocument,
} from "./validate.mjs";

const execFileAsync = promisify(execFile);
const receiptKind = "long-west-background-assets-archive-set-v1";
const productionStatus = "PRODUCTION_APPROVED_LAUNCH_SET";
const fixtureStatus = "NON_SHIPPING_TEST_FIXTURE";
const essentialPackageID = "essential-free-v1";
const maximumControlFileBytes = 4 * 1_024 * 1_024;
const maximumOutputMetadataBytes = 1 * 1_024 * 1_024;
const digestPattern = /^[a-f0-9]{64}$/u;
const stableIDPattern = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/u;
const productionKeyForbiddenComponentPattern = /(?:^|-)(?:debug|development|fixture|local|test)(?:-|$)/u;

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

function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalValue(value[key])]),
    );
  }
  return value;
}

function canonicalJSONBytes(value) {
  return Buffer.from(JSON.stringify(canonicalValue(value)), "utf8");
}

function exactKeys(value, keys, location, issues) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    issues.push(`${location}: object required`);
    return false;
  }
  const expected = [...keys].sort();
  const actual = Object.keys(value).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    issues.push(`${location}: exact fields ${expected.join(", ")} required`);
    return false;
  }
  return true;
}

function isWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === ""
    || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

function portableRelative(root, file) {
  return path.relative(root, file).split(path.sep).join("/");
}

function requireSafeRelativePath(value, location) {
  if (typeof value !== "string" || !value || value.startsWith("/")
      || value.includes("\\") || value.includes("://")
      || /[\u0000-\u001f\u007f]/u.test(value)
      || value.split("/").some((segment) => !segment || segment === "." || segment === "..")) {
    throw new ValidationError([`${location}: safe POSIX relative path required`]);
  }
}

function requireVersion(value, location) {
  const keys = ["major", "minor", "patch"];
  const issues = [];
  if (!exactKeys(value, keys, location, issues)
      || keys.some((key) => !Number.isSafeInteger(value?.[key]) || value[key] < 0)) {
    issues.push(`${location}: non-negative integer semantic version required`);
  }
  if (issues.length) throw new ValidationError(issues);
  return { major: value.major, minor: value.minor, patch: value.patch };
}

function versionString(value) {
  const version = requireVersion(value, "package version");
  return `${version.major}.${version.minor}.${version.patch}`;
}

function parseCanonicalJSON(bytes, location) {
  let value;
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    throw new ValidationError([`${location}: invalid UTF-8 JSON (${error.message})`]);
  }
  if (!canonicalJSONBytes(value).equals(bytes)) {
    throw new ValidationError([`${location}: canonical sorted-key JSON bytes required`]);
  }
  return value;
}

async function readBoundedRegularFile(file, location, maximumBytes = maximumControlFileBytes) {
  const info = await lstat(file).catch(() => null);
  if (!info?.isFile() || info.isSymbolicLink()) {
    throw new ValidationError([`${location}: regular file required`]);
  }
  if (info.size > maximumBytes) {
    throw new ValidationError([`${location}: exceeds ${maximumBytes} bytes`]);
  }
  return readFile(file);
}

async function safeTreeFiles(root, location) {
  const rootInfo = await lstat(root).catch(() => null);
  if (!rootInfo?.isDirectory() || rootInfo.isSymbolicLink()) {
    throw new ValidationError([`${location}: real directory required`]);
  }
  const files = [];
  async function visit(directory) {
    const entries = await readdir(directory);
    entries.sort((left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right)));
    for (const name of entries) {
      if (!name || name === "." || name === ".." || /[\u0000-\u001f\u007f]/u.test(name)) {
        throw new ValidationError([`${location}: unsafe directory entry`]);
      }
      const candidate = path.join(directory, name);
      const info = await lstat(candidate);
      if (info.isSymbolicLink()) {
        throw new ValidationError([`${location}: symbolic links are forbidden (${portableRelative(root, candidate)})`]);
      }
      if (info.isDirectory()) {
        await visit(candidate);
      } else if (info.isFile()) {
        files.push(candidate);
      } else {
        throw new ValidationError([`${location}: special files are forbidden (${portableRelative(root, candidate)})`]);
      }
    }
  }
  await visit(root);
  return files;
}

async function snapshotTree(root, location) {
  const records = [];
  for (const file of await safeTreeFiles(root, location)) {
    records.push({ path: portableRelative(root, file), ...await hashFile(file) });
  }
  return records;
}

function requireSameSnapshot(before, after, location) {
  if (JSON.stringify(before) !== JSON.stringify(after)) {
    throw new ValidationError([`${location}: input changed while archives were being produced`]);
  }
}

function stableProductionKeyID(value) {
  return typeof value === "string"
    && Buffer.byteLength(value, "utf8") <= 64
    && stableIDPattern.test(value)
    && !productionKeyForbiddenComponentPattern.test(value);
}

function canonicalBase64(value, location) {
  if (typeof value !== "string" || !value) {
    throw new ValidationError([`${location}: canonical base64 required`]);
  }
  const bytes = Buffer.from(value, "base64");
  if (!bytes.length || bytes.toString("base64") !== value) {
    throw new ValidationError([`${location}: canonical base64 required`]);
  }
  return bytes;
}

export function validateApprovedTrust(trustBytes, approvalBytes, expectedKeyID) {
  const trust = parseCanonicalJSON(trustBytes, "launch package trust resource");
  const issues = [];
  exactKeys(trust, ["schemaVersion", "keys"], "launch package trust resource", issues);
  if (trust?.schemaVersion !== 1 || !Array.isArray(trust?.keys) || trust.keys.length !== 1) {
    issues.push("launch package trust resource: exactly one schema-v1 key required");
  }
  const key = trust?.keys?.[0];
  exactKeys(key, ["id", "x963PublicKeyBase64"], "launch package trust key", issues);
  if (!stableProductionKeyID(key?.id) || key?.id !== expectedKeyID) {
    issues.push("launch package trust key: approved production key ID must match launch-set receipt");
  }
  if (issues.length) throw new ValidationError(issues);

  const publicKeyBytes = canonicalBase64(
    key.x963PublicKeyBase64,
    "launch package trust key.x963PublicKeyBase64",
  );
  if (publicKeyBytes.length !== 65 || publicKeyBytes[0] !== 0x04) {
    throw new ValidationError(["launch package trust key: uncompressed P-256 point required"]);
  }
  try {
    const normalized = ECDH.convertKey(
      publicKeyBytes,
      "prime256v1",
      undefined,
      undefined,
      "uncompressed",
    );
    if (!normalized.equals(publicKeyBytes)) throw new Error("noncanonical point");
  } catch {
    throw new ValidationError(["launch package trust key: valid P-256 point required"]);
  }

  const approval = parseCanonicalJSON(approvalBytes, "approved trust receipt");
  exactKeys(
    approval,
    ["schemaVersion", "trustFileSHA256", "keys"],
    "approved trust receipt",
    issues,
  );
  if (approval?.schemaVersion !== 1
      || !Array.isArray(approval?.keys) || approval.keys.length !== 1) {
    issues.push("approved trust receipt: exactly one schema-v1 key required");
  }
  const approvedKey = approval?.keys?.[0];
  exactKeys(
    approvedKey,
    ["id", "x963PublicKeySHA256"],
    "approved trust receipt key",
    issues,
  );
  if (approval?.trustFileSHA256 !== sha256(trustBytes)
      || approvedKey?.id !== key.id
      || approvedKey?.x963PublicKeySHA256 !== sha256(publicKeyBytes)) {
    issues.push("approved trust receipt: trust resource bytes or key do not match approval");
  }
  if (issues.length) throw new ValidationError(issues);

  const publicKey = createPublicKey({
    format: "jwk",
    key: {
      kty: "EC",
      crv: "P-256",
      x: publicKeyBytes.subarray(1, 33).toString("base64url"),
      y: publicKeyBytes.subarray(33, 65).toString("base64url"),
    },
  });
  return {
    keyID: key.id,
    publicKey,
    trustFileSHA256: sha256(trustBytes),
    approvedTrustReceiptSHA256: sha256(approvalBytes),
  };
}

function requireLaunchRootShape(root, expectedPackageIDs) {
  return Promise.all([
    readdir(root).then((entries) => {
      const expected = ["launch-set-receipt.json", "packages"];
      if (JSON.stringify(entries.sort()) !== JSON.stringify(expected)) {
        throw new ValidationError([
          "compiled launch set: only launch-set-receipt.json and packages/ are permitted",
        ]);
      }
    }),
    readdir(path.join(root, "packages")).then((entries) => {
      if (JSON.stringify(entries.sort()) !== JSON.stringify([...expectedPackageIDs].sort())) {
        throw new ValidationError([
          "compiled launch set: package directories must exactly match the locked eight-package plan",
        ]);
      }
    }),
  ]);
}

function forbiddenPublicSegment(segment) {
  return forbiddenPathSegments.has(segment)
    || ["backstage", "research", "sources", "evidence", "findings", "claims"]
      .includes(normalizePolicyName(segment));
}

async function validateCompiledPublicPackage(packageRoot, manifest, expectedPayloadPath) {
  const declaredPaths = new Set(manifest.files.map((record) => record.path));
  if (!declaredPaths.has("collection.json") || !declaredPaths.has(expectedPayloadPath)) {
    throw new ValidationError([
      `${manifest.packageID}: signed package must contain collection.json and its receipted payload`,
    ]);
  }
  const documents = [];
  for (const record of manifest.files) {
    requireSafeRelativePath(record.path, `${manifest.packageID}.manifest.files.path`);
    const components = record.path.split("/");
    if (!allowedPublicTopLevel.has(components[0])
        || !allowedPublicExtensions.has(path.extname(record.path).toLowerCase())
        || components.some(forbiddenPublicSegment)) {
      throw new ValidationError([
        `${manifest.packageID}: foreign or backstage path '${record.path}' is forbidden`,
      ]);
    }
    if (path.extname(record.path).toLowerCase() !== ".json") continue;
    const file = path.join(packageRoot, ...record.path.split("/"));
    let document;
    try {
      document = JSON.parse(await readFile(file, "utf8"));
      validatePublicDocument(document, `${manifest.packageID}.${record.path}`);
    } catch (error) {
      if (error instanceof ValidationError) throw error;
      throw new ValidationError([`${manifest.packageID}.${record.path}: ${error.message}`]);
    }
    documents.push({ path: record.path, document });
  }
  const payloadDocuments = documents.filter(({ document }) =>
    Array.isArray(document?.chapters)
      && Array.isArray(document?.scenes)
      && Array.isArray(document?.audioTimelines));
  if (payloadDocuments.length !== 1 || payloadDocuments[0].path !== expectedPayloadPath) {
    throw new ValidationError([
      `${manifest.packageID}: exactly one ContentPackagePayload at the receipted path required`,
    ]);
  }
  const shippingReferences = collectShippingAssetReferences(payloadDocuments[0].document);
  for (const assetPath of shippingReferences.keys()) {
    if (!declaredPaths.has(assetPath)) {
      throw new ValidationError([`${manifest.packageID}: referenced offline asset '${assetPath}' is missing`]);
    }
  }
  for (const record of manifest.files) {
    if (path.extname(record.path).toLowerCase() === ".json") continue;
    if (!shippingReferences.has(record.path)) {
      throw new ValidationError([`${manifest.packageID}: unreferenced foreign asset '${record.path}'`]);
    }
  }
  return payloadDocuments[0].document;
}

function sameArray(left, right) {
  return Array.isArray(left) && Array.isArray(right)
    && left.length === right.length
    && left.every((value, index) => value === right[index]);
}

async function validateCompiledLaunchSet(
  launchRoot,
  trustResourcePath,
  approvedTrustReceiptPath,
  launchConfiguration,
) {
  const expectedPackageIDs = (launchConfiguration?.delivery?.packages ?? [])
    .map((record) => record.packageID);
  if (expectedPackageIDs.length !== 8
      || expectedPackageIDs[0] !== essentialPackageID
      || new Set(expectedPackageIDs).size !== 8) {
    throw new ValidationError(["background-assets bridge: locked eight-package delivery plan required"]);
  }
  await safeTreeFiles(launchRoot, "compiled launch set");
  await requireLaunchRootShape(launchRoot, expectedPackageIDs);

  const launchReceiptBytes = await readBoundedRegularFile(
    path.join(launchRoot, "launch-set-receipt.json"),
    "compiled launch-set receipt",
  );
  let launchReceipt;
  try {
    launchReceipt = JSON.parse(launchReceiptBytes.toString("utf8"));
  } catch (error) {
    throw new ValidationError([`compiled launch-set receipt: invalid JSON (${error.message})`]);
  }
  validateLaunchSetReceipt(launchReceipt, expectedPackageIDs);

  const [trustBytes, approvalBytes] = await Promise.all([
    readBoundedRegularFile(trustResourcePath, "launch package trust resource"),
    readBoundedRegularFile(approvedTrustReceiptPath, "approved trust receipt"),
  ]);
  const trust = validateApprovedTrust(trustBytes, approvalBytes, launchReceipt.keyID);

  const firstCollectionBytes = await readFile(path.join(
    launchRoot,
    "packages",
    essentialPackageID,
    "collection.json",
  ));
  if (sha256(firstCollectionBytes) !== launchReceipt.collectionSHA256) {
    throw new ValidationError(["compiled launch set: collection bytes do not match set receipt"]);
  }
  let collection;
  try {
    collection = JSON.parse(firstCollectionBytes.toString("utf8"));
  } catch (error) {
    throw new ValidationError([`compiled launch set collection: invalid JSON (${error.message})`]);
  }
  const collectionIssues = validateCollectionAgainstLaunchConfiguration(
    collection,
    launchConfiguration,
  );
  if (collectionIssues.length) throw new ValidationError(collectionIssues);

  const packageSpecByID = new Map(collection.packages.map((record) => [record.id, record]));
  const payloads = [];
  const packages = [];
  for (const receiptRecord of launchReceipt.packages) {
    const packageSpec = packageSpecByID.get(receiptRecord.packageID);
    if (!packageSpec || !sameArray(packageSpec.chapterIDs, receiptRecord.chapterIDs)) {
      throw new ValidationError([
        `${receiptRecord.packageID}: set receipt chapter ownership differs from collection specification`,
      ]);
    }
    const packageRoot = path.join(launchRoot, "packages", receiptRecord.packageID);
    const collectionBytes = await readFile(path.join(packageRoot, "collection.json"));
    if (sha256(collectionBytes) !== launchReceipt.collectionSHA256
        || !collectionBytes.equals(firstCollectionBytes)) {
      throw new ValidationError([
        `${receiptRecord.packageID}: collection.json differs from the receipted launch collection`,
      ]);
    }
    const manifestPath = path.join(packageRoot, "package-manifest.json");
    const manifestBytes = await readBoundedRegularFile(
      manifestPath,
      `${receiptRecord.packageID} signed package manifest`,
    );
    const manifest = await verifyCompiledPackage(
      packageRoot,
      trust.publicKey,
      trust.keyID,
      packageSpec,
    );
    if (manifest.manifestDigest !== receiptRecord.manifestDigest) {
      throw new ValidationError([
        `${receiptRecord.packageID}: signed manifest digest differs from launch-set receipt`,
      ]);
    }
    const payloadPath = path.join(packageRoot, ...receiptRecord.payloadPath.split("/"));
    const payloadBytes = await readFile(payloadPath);
    if (sha256(payloadBytes) !== receiptRecord.payloadSHA256) {
      throw new ValidationError([
        `${receiptRecord.packageID}: payload bytes differ from launch-set receipt`,
      ]);
    }
    const payload = await validateCompiledPublicPackage(
      packageRoot,
      manifest,
      receiptRecord.payloadPath,
    );
    if (payload.packageID !== receiptRecord.packageID
        || !sameArray(payload.chapters.map((chapter) => chapter.id), packageSpec.chapterIDs)) {
      throw new ValidationError([
        `${receiptRecord.packageID}: payload identity or ordered chapter ownership differs from specification`,
      ]);
    }
    payloads.push(payload);
    packages.push({
      packageID: receiptRecord.packageID,
      packageRoot,
      packageSpec,
      packageVersion: requireVersion(packageSpec.version, `${receiptRecord.packageID}.version`),
      manifest,
      manifestDigest: manifest.manifestDigest,
      packageManifestSHA256: sha256(manifestBytes),
    });
  }
  const replay = validateLaunchAssembly(collection, payloads);
  if (replay.finalWorldSHA256 !== launchReceipt.finalWorldSHA256) {
    throw new ValidationError([
      "compiled launch set: full causal replay differs from launch-set receipt",
    ]);
  }
  return {
    launchReceipt,
    launchSetReceiptFileSHA256: sha256(launchReceiptBytes),
    collection,
    packages,
    trust,
  };
}

export function canonicalBackgroundAssetManifest(packageID) {
  if (!stableIDPattern.test(packageID ?? "") || packageID === essentialPackageID) {
    throw new ValidationError(["background asset manifest: stable paid package ID required"]);
  }
  return {
    assetPackID: packageID,
    downloadPolicy: { onDemand: {} },
    fileSelectors: [{ directory: `packages/${packageID}` }],
    platforms: ["iOS"],
  };
}

function receiptWithoutDigest(receipt) {
  const { receiptSHA256: _ignored, ...material } = receipt;
  return material;
}

export function backgroundAssetsReceiptDigest(receipt) {
  return sha256(canonicalJSONBytes(receiptWithoutDigest(receipt)));
}

function validateArchiveReceipt(receipt, expectedPaidPackageIDs = undefined) {
  const issues = [];
  exactKeys(receipt, [
    "schemaVersion",
    "kind",
    "status",
    "launchSetReceiptSHA256",
    "launchSetReceiptFileSHA256",
    "collectionSHA256",
    "finalWorldSHA256",
    "trustFileSHA256",
    "approvedTrustReceiptSHA256",
    "keyID",
    "baPackageVersion",
    "sourceBindingSHA256",
    "packages",
    "receiptSHA256",
  ], "background-assets receipt", issues);
  if (receipt?.schemaVersion !== 1 || receipt?.kind !== receiptKind) {
    issues.push("background-assets receipt: schema version 1 and canonical kind required");
  }
  if (![productionStatus, fixtureStatus].includes(receipt?.status)) {
    issues.push("background-assets receipt.status: production or explicit non-shipping fixture status required");
  }
  for (const key of [
    "launchSetReceiptSHA256",
    "launchSetReceiptFileSHA256",
    "collectionSHA256",
    "finalWorldSHA256",
    "trustFileSHA256",
    "approvedTrustReceiptSHA256",
    "sourceBindingSHA256",
    "receiptSHA256",
  ]) {
    if (!digestPattern.test(receipt?.[key] ?? "")) {
      issues.push(`background-assets receipt.${key}: lowercase SHA-256 required`);
    }
  }
  if (!stableProductionKeyID(receipt?.keyID)
      || typeof receipt?.baPackageVersion !== "string"
      || !/^\d+(?:\.\d+)+$/u.test(receipt.baPackageVersion)) {
    issues.push("background-assets receipt: production key ID and ba-package version required");
  }
  if (!Array.isArray(receipt?.packages) || receipt.packages.length !== 7) {
    issues.push("background-assets receipt.packages: exactly seven paid archives required");
  }
  const records = Array.isArray(receipt?.packages) ? receipt.packages : [];
  for (const [index, record] of records.entries()) {
    const location = `background-assets receipt.packages[${index}]`;
    exactKeys(record, [
      "packageID",
      "assetPackID",
      "packageVersion",
      "selector",
      "packageManifestSHA256",
      "manifestDigest",
      "baManifestPath",
      "baManifestSHA256",
      "archivePath",
      "archiveBytes",
      "archiveSHA256",
      "archiveMaximumBytes",
    ], location, issues);
    if (!stableIDPattern.test(record?.packageID ?? "")
        || record?.assetPackID !== record?.packageID
        || record?.packageID === essentialPackageID) {
      issues.push(`${location}: identical stable paid package and asset-pack IDs required`);
    }
    try {
      requireVersion(record?.packageVersion, `${location}.packageVersion`);
      requireSafeRelativePath(record?.selector, `${location}.selector`);
      requireSafeRelativePath(record?.baManifestPath, `${location}.baManifestPath`);
      requireSafeRelativePath(record?.archivePath, `${location}.archivePath`);
    } catch (error) {
      if (error instanceof ValidationError) issues.push(...error.issues);
      else throw error;
    }
    if (record?.selector !== `packages/${record?.packageID}`) {
      issues.push(`${location}.selector: exact package directory selector required`);
    }
    try {
      const baseName = `${record?.packageID}-${versionString(record?.packageVersion)}`;
      if (record?.baManifestPath !== `manifests/${baseName}.ba-manifest.json`
          || record?.archivePath !== `archives/${baseName}.aar`) {
        issues.push(`${location}: manifest and archive paths must bind package ID and version`);
      }
    } catch (error) {
      if (error instanceof ValidationError) issues.push(...error.issues);
      else throw error;
    }
    for (const key of [
      "packageManifestSHA256",
      "manifestDigest",
      "baManifestSHA256",
      "archiveSHA256",
    ]) {
      if (!digestPattern.test(record?.[key] ?? "")) {
        issues.push(`${location}.${key}: lowercase SHA-256 required`);
      }
    }
    if (!Number.isSafeInteger(record?.archiveBytes) || record.archiveBytes <= 0
        || !Number.isSafeInteger(record?.archiveMaximumBytes) || record.archiveMaximumBytes <= 0
        || record.archiveBytes > record.archiveMaximumBytes) {
      issues.push(`${location}: positive archive bytes within explicit ceiling required`);
    }
  }
  if (expectedPaidPackageIDs !== undefined
      && !sameArray(records.map((record) => record.packageID), expectedPaidPackageIDs)) {
    issues.push("background-assets receipt.packages: locked paid delivery order required");
  }
  if (new Set(records.map((record) => record.packageID)).size !== records.length) {
    issues.push("background-assets receipt.packages: unique package IDs required");
  }
  if (receipt?.sourceBindingSHA256 !== sourceBindingDigestFromReceipt(receipt)) {
    issues.push("background-assets receipt.sourceBindingSHA256: source authority material changed");
  }
  if (receipt?.receiptSHA256 !== backgroundAssetsReceiptDigest(receipt)) {
    issues.push("background-assets receipt.receiptSHA256: receipt material changed");
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

function sourceBindingDigest(validated, baPackageVersion) {
  return sha256(canonicalJSONBytes({
    launchSetReceiptSHA256: validated.launchReceipt.receiptSHA256,
    launchSetReceiptFileSHA256: validated.launchSetReceiptFileSHA256,
    trustFileSHA256: validated.trust.trustFileSHA256,
    approvedTrustReceiptSHA256: validated.trust.approvedTrustReceiptSHA256,
    keyID: validated.trust.keyID,
    baPackageVersion,
    packages: validated.packages
      .filter((record) => record.packageID !== essentialPackageID)
      .map((record) => ({
        packageID: record.packageID,
        packageVersion: record.packageVersion,
        packageManifestSHA256: record.packageManifestSHA256,
        manifestDigest: record.manifestDigest,
        maximumInstalledBytes: record.packageSpec.maximumInstalledBytes,
      })),
  }));
}

function sourceBindingDigestFromReceipt(receipt) {
  return sha256(canonicalJSONBytes({
    launchSetReceiptSHA256: receipt?.launchSetReceiptSHA256,
    launchSetReceiptFileSHA256: receipt?.launchSetReceiptFileSHA256,
    trustFileSHA256: receipt?.trustFileSHA256,
    approvedTrustReceiptSHA256: receipt?.approvedTrustReceiptSHA256,
    keyID: receipt?.keyID,
    baPackageVersion: receipt?.baPackageVersion,
    packages: (receipt?.packages ?? []).map((record) => ({
      packageID: record?.packageID,
      packageVersion: record?.packageVersion,
      packageManifestSHA256: record?.packageManifestSHA256,
      manifestDigest: record?.manifestDigest,
      maximumInstalledBytes: record?.archiveMaximumBytes,
    })),
  }));
}

function receiptMatchesValidatedSource(receipt, validated, status, toolVersion) {
  if (receipt.status !== status
      || receipt.baPackageVersion !== toolVersion
      || receipt.launchSetReceiptSHA256 !== validated.launchReceipt.receiptSHA256
      || receipt.launchSetReceiptFileSHA256 !== validated.launchSetReceiptFileSHA256
      || receipt.collectionSHA256 !== validated.launchReceipt.collectionSHA256
      || receipt.finalWorldSHA256 !== validated.launchReceipt.finalWorldSHA256
      || receipt.trustFileSHA256 !== validated.trust.trustFileSHA256
      || receipt.approvedTrustReceiptSHA256 !== validated.trust.approvedTrustReceiptSHA256
      || receipt.keyID !== validated.trust.keyID
      || receipt.packages.length !== validated.packages.length - 1) {
    return false;
  }
  const paid = validated.packages.filter((record) => record.packageID !== essentialPackageID);
  return receipt.packages.every((record, index) => {
    const expected = paid[index];
    return record.packageID === expected.packageID
      && JSON.stringify(record.packageVersion) === JSON.stringify(expected.packageVersion)
      && record.packageManifestSHA256 === expected.packageManifestSHA256
      && record.manifestDigest === expected.manifestDigest
      && record.archiveMaximumBytes === expected.packageSpec.maximumInstalledBytes;
  });
}

async function baPackageVersion() {
  let stdout;
  try {
    ({ stdout } = await execFileAsync("xcrun", ["ba-package", "--version"], {
      encoding: "utf8",
      maxBuffer: 1 * 1_024 * 1_024,
    }));
  } catch (error) {
    throw new ValidationError([`xcrun ba-package: installed Apple tool required (${error.message})`]);
  }
  const version = stdout.trim();
  if (!/^\d+(?:\.\d+)+$/u.test(version)) {
    throw new ValidationError(["xcrun ba-package: numeric tool version required"]);
  }
  return version;
}

async function runBAPackage(manifestPath, archivePath, launchRoot) {
  try {
    await execFileAsync(
      "xcrun",
      ["ba-package", "package", manifestPath, "--output-path", archivePath, "--quiet"],
      {
        cwd: launchRoot,
        encoding: "utf8",
        maxBuffer: 4 * 1_024 * 1_024,
        env: {
          ...process.env,
          COPYFILE_DISABLE: "1",
          LC_ALL: "C",
          TZ: "UTC",
        },
      },
    );
  } catch (error) {
    const detail = String(error.stderr ?? error.message).trim();
    throw new ValidationError([`xcrun ba-package: archive creation failed (${detail})`]);
  }
}

function exactAppleArchiveEntries(packageID, manifest) {
  const contentRoot = `Contents/packages/${packageID}`;
  const entries = new Set(["Manifest.json", "Contents", "Contents/packages", contentRoot]);
  for (const relativePath of [
    "package-manifest.json",
    ...manifest.files.map((record) => record.path),
  ]) {
    const fullPath = `${contentRoot}/${relativePath}`;
    entries.add(fullPath);
    const components = fullPath.split("/");
    for (let count = 1; count < components.length; count += 1) {
      entries.add(components.slice(0, count).join("/"));
    }
  }
  return [...entries].sort();
}

async function verifyAppleArchiveInventory(archivePath, packageID, manifest = undefined) {
  let stdout;
  try {
    ({ stdout } = await execFileAsync("aa", ["list", "-i", archivePath], {
      encoding: "utf8",
      maxBuffer: 16 * 1_024 * 1_024,
    }));
  } catch (error) {
    throw new ValidationError([
      `${packageID}: Apple Archive inventory could not be read (${error.message})`,
    ]);
  }
  const entries = stdout.split("\n").map((entry) => entry.trim()).filter(Boolean);
  const contentRoot = `Contents/packages/${packageID}`;
  if (!entries.includes("Manifest.json")
      || !entries.includes(contentRoot)
      || !entries.includes(`${contentRoot}/package-manifest.json`)
      || entries.some((entry) => entry !== "Manifest.json"
        && entry !== "Contents"
        && entry !== "Contents/packages"
        && entry !== contentRoot
        && !entry.startsWith(`${contentRoot}/`))) {
    throw new ValidationError([
      `${packageID}: .aar inventory does not contain only the selected signed package tree`,
    ]);
  }
  if (manifest !== undefined
      && JSON.stringify([...entries].sort())
        !== JSON.stringify(exactAppleArchiveEntries(packageID, manifest))) {
    throw new ValidationError([
      `${packageID}: .aar inventory differs from the exact signed package inventory`,
    ]);
  }
}

async function verifyArchivesAgainstValidatedSource(outputRoot, receipt, validated) {
  const expectedByID = new Map(validated.packages.map((record) => [record.packageID, record]));
  for (const record of receipt.packages) {
    const expected = expectedByID.get(record.packageID);
    if (!expected) {
      throw new ValidationError([`${record.packageID}: no validated source package for archive`]);
    }
    await verifyAppleArchiveInventory(
      path.join(outputRoot, ...record.archivePath.split("/")),
      record.packageID,
      expected.manifest,
    );
  }
}

async function publishAtomically(stagingRoot, outputRoot) {
  const existing = await lstat(outputRoot).catch(() => null);
  if (existing?.isSymbolicLink() || (existing && !existing.isDirectory())) {
    throw new ValidationError(["background-assets output: existing target must be a real directory"]);
  }
  const backupRoot = `${outputRoot}.previous-${process.pid}-${Date.now()}`;
  let movedExisting = false;
  try {
    if (existing) {
      await rename(outputRoot, backupRoot);
      movedExisting = true;
    }
    await rename(stagingRoot, outputRoot);
  } catch (error) {
    if (movedExisting && !await lstat(outputRoot).catch(() => null)) {
      await rename(backupRoot, outputRoot).catch(() => {});
    }
    throw error;
  }
  if (movedExisting) await rm(backupRoot, { recursive: true, force: true }).catch(() => {});
}

export async function verifyBackgroundAssetsArchiveSet(
  outputRoot,
  expectedPaidPackageIDs = undefined,
) {
  const files = await safeTreeFiles(outputRoot, "background-assets output");
  const receiptPath = path.join(outputRoot, "background-assets-receipt.json");
  const receiptBytes = await readBoundedRegularFile(
    receiptPath,
    "background-assets output receipt",
  );
  const receipt = parseCanonicalJSON(receiptBytes, "background-assets output receipt");
  validateArchiveReceipt(receipt, expectedPaidPackageIDs);
  const expectedPaths = new Set(["background-assets-receipt.json"]);
  let metadataBytes = receiptBytes.byteLength;
  let aggregateArchiveBytes = 0;
  let aggregateArchiveCeiling = 0;
  for (const record of receipt.packages) {
    expectedPaths.add(record.baManifestPath);
    expectedPaths.add(record.archivePath);
    const baManifestFile = path.join(outputRoot, ...record.baManifestPath.split("/"));
    const baManifestBytes = await readBoundedRegularFile(
      baManifestFile,
      `${record.packageID} Background Assets manifest`,
    );
    metadataBytes += baManifestBytes.byteLength;
    if (!canonicalJSONBytes(canonicalBackgroundAssetManifest(record.packageID)).equals(baManifestBytes)
        || sha256(baManifestBytes) !== record.baManifestSHA256) {
      throw new ValidationError([
        `${record.packageID}: Background Assets manifest is not canonical or receipted`,
      ]);
    }
    const archiveFile = path.join(outputRoot, ...record.archivePath.split("/"));
    await verifyAppleArchiveInventory(archiveFile, record.packageID);
    const archive = await hashFile(archiveFile);
    if (archive.bytes !== record.archiveBytes || archive.sha256 !== record.archiveSHA256
        || archive.bytes > record.archiveMaximumBytes) {
      throw new ValidationError([`${record.packageID}: archive bytes differ from receipt or exceed ceiling`]);
    }
    aggregateArchiveBytes += archive.bytes;
    aggregateArchiveCeiling += record.archiveMaximumBytes;
  }
  if (metadataBytes > maximumOutputMetadataBytes) {
    throw new ValidationError([
      `background-assets output: metadata exceeds ${maximumOutputMetadataBytes} bytes`,
    ]);
  }
  if (aggregateArchiveBytes > aggregateArchiveCeiling) {
    throw new ValidationError(["background-assets output: aggregate archive ceiling exceeded"]);
  }
  const actualPaths = files.map((file) => portableRelative(outputRoot, file)).sort();
  if (JSON.stringify(actualPaths) !== JSON.stringify([...expectedPaths].sort())) {
    throw new ValidationError(["background-assets output: foreign or missing files detected"]);
  }
  return receipt;
}

function requireOutputStatus(value) {
  const status = value ?? productionStatus;
  if (![productionStatus, fixtureStatus].includes(status)) {
    throw new ValidationError(["background-assets output status: known production or fixture status required"]);
  }
  if (status === fixtureStatus && !process.env.NODE_TEST_CONTEXT) {
    throw new ValidationError([
      "background-assets output status: non-shipping fixture mode is available only under node --test",
    ]);
  }
  if (status === productionStatus && process.env.NODE_TEST_CONTEXT) {
    throw new ValidationError([
      "background-assets output status: node --test must use explicit NON_SHIPPING_TEST_FIXTURE status",
    ]);
  }
  return status;
}

export async function packagePaidLaunchBackgroundAssets(
  launchSetRoot,
  outputRoot,
  {
    launchConfiguration,
    trustResourcePath,
    approvedTrustReceiptPath,
    outputStatus,
  } = {},
) {
  const launchRoot = path.resolve(launchSetRoot);
  const resolvedOutput = path.resolve(outputRoot);
  const trustPath = path.resolve(trustResourcePath ?? "");
  const trustReceiptPath = path.resolve(approvedTrustReceiptPath ?? "");
  const status = requireOutputStatus(outputStatus);
  if (!trustResourcePath || !approvedTrustReceiptPath) {
    throw new ValidationError([
      "background-assets bridge: trust resource and approved trust receipt paths required",
    ]);
  }
  if (isWithin(launchRoot, resolvedOutput) || isWithin(resolvedOutput, launchRoot)) {
    throw new ValidationError([
      "background-assets bridge: compiled launch set and output must be disjoint",
    ]);
  }
  if (isWithin(launchRoot, trustPath) || isWithin(launchRoot, trustReceiptPath)) {
    throw new ValidationError([
      "background-assets bridge: trust controls must remain outside the compiled launch set",
    ]);
  }
  if (isWithin(resolvedOutput, trustPath) || isWithin(resolvedOutput, trustReceiptPath)) {
    throw new ValidationError([
      "background-assets bridge: trust controls cannot be inside output",
    ]);
  }

  const beforeSnapshot = await snapshotTree(launchRoot, "compiled launch set");
  const validated = await validateCompiledLaunchSet(
    launchRoot,
    trustPath,
    trustReceiptPath,
    launchConfiguration,
  );
  const toolVersion = await baPackageVersion();
  const paidPackages = validated.packages.filter((record) => record.packageID !== essentialPackageID);
  const expectedPaidPackageIDs = (launchConfiguration.delivery.packages ?? [])
    .filter((record) => !record.isEssentialInstall)
    .map((record) => record.packageID);
  if (!sameArray(paidPackages.map((record) => record.packageID), expectedPaidPackageIDs)
      || paidPackages.length !== 7) {
    throw new ValidationError([
      "background-assets bridge: exactly the seven locked paid packages must be archived",
    ]);
  }
  const binding = sourceBindingDigest(validated, toolVersion);

  const existing = await lstat(resolvedOutput).catch(() => null);
  if (existing?.isDirectory() && !existing.isSymbolicLink()) {
    try {
      const receipt = await verifyBackgroundAssetsArchiveSet(
        resolvedOutput,
        expectedPaidPackageIDs,
      );
      if (receipt.sourceBindingSHA256 === binding
          && receiptMatchesValidatedSource(receipt, validated, status, toolVersion)) {
        await verifyArchivesAgainstValidatedSource(resolvedOutput, receipt, validated);
        requireSameSnapshot(
          beforeSnapshot,
          await snapshotTree(launchRoot, "compiled launch set"),
          "background-assets bridge",
        );
        return receipt;
      }
    } catch {
      // A corrupt or stale prior output is replaced only after a complete new
      // set has been produced and verified in an isolated sibling directory.
    }
  } else if (existing) {
    throw new ValidationError(["background-assets output: existing target must be a real directory"]);
  }

  await mkdir(path.dirname(resolvedOutput), { recursive: true });
  const stagingRoot = await mkdtemp(path.join(
    path.dirname(resolvedOutput),
    `.${path.basename(resolvedOutput)}.background-assets-staging-`,
  ));
  try {
    const manifestsRoot = path.join(stagingRoot, "manifests");
    const archivesRoot = path.join(stagingRoot, "archives");
    await Promise.all([
      mkdir(manifestsRoot, { recursive: true }),
      mkdir(archivesRoot, { recursive: true }),
    ]);
    const receiptPackages = [];
    for (const record of paidPackages) {
      const version = versionString(record.packageVersion);
      const baseName = `${record.packageID}-${version}`;
      const baManifestRelativePath = `manifests/${baseName}.ba-manifest.json`;
      const archiveRelativePath = `archives/${baseName}.aar`;
      const baManifestPath = path.join(stagingRoot, ...baManifestRelativePath.split("/"));
      const archivePath = path.join(stagingRoot, ...archiveRelativePath.split("/"));
      const baManifest = canonicalBackgroundAssetManifest(record.packageID);
      const baManifestBytes = canonicalJSONBytes(baManifest);
      await writeFile(baManifestPath, baManifestBytes, { flag: "wx" });
      await runBAPackage(baManifestPath, archivePath, launchRoot);
      await verifyAppleArchiveInventory(archivePath, record.packageID, record.manifest);
      const archive = await hashFile(archivePath);
      if (archive.bytes <= 0 || archive.bytes > record.packageSpec.maximumInstalledBytes) {
        throw new ValidationError([
          `${record.packageID}: archive ${archive.bytes} exceeds explicit ${record.packageSpec.maximumInstalledBytes}-byte ceiling`,
        ]);
      }
      receiptPackages.push({
        packageID: record.packageID,
        assetPackID: record.packageID,
        packageVersion: record.packageVersion,
        selector: `packages/${record.packageID}`,
        packageManifestSHA256: record.packageManifestSHA256,
        manifestDigest: record.manifestDigest,
        baManifestPath: baManifestRelativePath,
        baManifestSHA256: sha256(baManifestBytes),
        archivePath: archiveRelativePath,
        archiveBytes: archive.bytes,
        archiveSHA256: archive.sha256,
        archiveMaximumBytes: record.packageSpec.maximumInstalledBytes,
      });
    }

    requireSameSnapshot(
      beforeSnapshot,
      await snapshotTree(launchRoot, "compiled launch set"),
      "background-assets bridge",
    );
    const receipt = {
      schemaVersion: 1,
      kind: receiptKind,
      status,
      launchSetReceiptSHA256: validated.launchReceipt.receiptSHA256,
      launchSetReceiptFileSHA256: validated.launchSetReceiptFileSHA256,
      collectionSHA256: validated.launchReceipt.collectionSHA256,
      finalWorldSHA256: validated.launchReceipt.finalWorldSHA256,
      trustFileSHA256: validated.trust.trustFileSHA256,
      approvedTrustReceiptSHA256: validated.trust.approvedTrustReceiptSHA256,
      keyID: validated.trust.keyID,
      baPackageVersion: toolVersion,
      sourceBindingSHA256: binding,
      packages: receiptPackages,
    };
    receipt.receiptSHA256 = backgroundAssetsReceiptDigest(receipt);
    validateArchiveReceipt(receipt, expectedPaidPackageIDs);
    await writeFile(
      path.join(stagingRoot, "background-assets-receipt.json"),
      canonicalJSONBytes(receipt),
      { flag: "wx" },
    );
    await verifyBackgroundAssetsArchiveSet(stagingRoot, expectedPaidPackageIDs);
    await verifyArchivesAgainstValidatedSource(stagingRoot, receipt, validated);
    await publishAtomically(stagingRoot, resolvedOutput);
    return receipt;
  } catch (error) {
    await rm(stagingRoot, { recursive: true, force: true }).catch(() => {});
    throw error;
  }
}

export const backgroundAssetsArchiveStatuses = Object.freeze({
  production: productionStatus,
  nonShippingFixture: fixtureStatus,
});
