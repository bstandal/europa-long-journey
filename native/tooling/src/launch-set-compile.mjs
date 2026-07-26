import { createHash, createPublicKey } from "node:crypto";
import {
  mkdir,
  mkdtemp,
  readFile,
  rename,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import {
  compilePublicPackage,
  validateLaunchPackageSource,
  verifyCompiledPackage,
} from "./compile.mjs";
import { validateLaunchAssembly } from "./launch-assembly.mjs";
import { ValidationError, validatePublicDocument } from "./validate.mjs";

const receiptHeader = "long-west-launch-set-receipt-v1";
const digestPattern = /^[a-f0-9]{64}$/;
const signingIDPattern = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function exactKeys(value, keys, location, issues) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    issues.push(`${location}: object required`);
    return false;
  }
  const allowed = new Set(keys);
  for (const key of keys) {
    if (!Object.hasOwn(value, key)) issues.push(`${location}.${key}: required`);
  }
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) issues.push(`${location}.${key}: unknown field`);
  }
  return true;
}

function isWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === ""
    || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

function requireDisjoint(left, right, location, issues) {
  if (isWithin(left, right) || isWithin(right, left)) {
    issues.push(`${location}: paths must be disjoint`);
  }
}

function safePackagePath(value) {
  return typeof value === "string"
    && value.length > 0
    && !value.startsWith("/")
    && !value.includes("\\")
    && !value.includes("://")
    && !/[\u0000-\u001f\u007f]/u.test(value)
    && value.split("/").every((segment) => segment && segment !== "." && segment !== "..");
}

export function validateLaunchSetDescriptor(descriptor, launchConfiguration) {
  const issues = [];
  if (!exactKeys(descriptor, ["schemaVersion", "packages"], "launch-set input", issues)) {
    throw new ValidationError(issues);
  }
  if (descriptor.schemaVersion !== 1) issues.push("launch-set input.schemaVersion: version 1 required");
  const records = Array.isArray(descriptor.packages) ? descriptor.packages : [];
  if (!Array.isArray(descriptor.packages) || records.length !== 8) {
    issues.push("launch-set input.packages: exactly eight package inputs required");
  }
  const expectedIDs = (launchConfiguration?.delivery?.packages ?? []).map((record) => record.packageID);
  if (expectedIDs.length !== 8 || new Set(expectedIDs).size !== 8) {
    issues.push("launchConfiguration.delivery.packages: exact locked eight-package plan required");
  }

  const seenIDs = new Set();
  const seenSources = new Set();
  const seenApprovals = new Set();
  const seenProvenance = new Set();
  for (const [index, record] of records.entries()) {
    const location = `launch-set input.packages[${index}]`;
    if (!exactKeys(
      record,
      ["packageID", "sourceRoot", "approvalPath", "assetProvenancePath"],
      location,
      issues,
    )) continue;
    if (typeof record.packageID !== "string" || !expectedIDs.includes(record.packageID)) {
      issues.push(`${location}.packageID: locked launch package ID required`);
    }
    for (const key of ["sourceRoot", "approvalPath", "assetProvenancePath"]) {
      if (typeof record[key] !== "string" || !path.isAbsolute(record[key])) {
        issues.push(`${location}.${key}: absolute path required`);
      }
    }
    if (seenIDs.has(record.packageID)) issues.push(`${location}.packageID: duplicate '${record.packageID}'`);
    seenIDs.add(record.packageID);
    const resolvedSource = path.resolve(record.sourceRoot ?? "");
    const resolvedApproval = path.resolve(record.approvalPath ?? "");
    const resolvedProvenance = path.resolve(record.assetProvenancePath ?? "");
    if (seenSources.has(resolvedSource)) issues.push(`${location}.sourceRoot: duplicate source tree`);
    if (seenApprovals.has(resolvedApproval)) issues.push(`${location}.approvalPath: one approval file per package required`);
    if (seenProvenance.has(resolvedProvenance)) {
      issues.push(`${location}.assetProvenancePath: one provenance file per package required`);
    }
    seenSources.add(resolvedSource);
    seenApprovals.add(resolvedApproval);
    seenProvenance.add(resolvedProvenance);
  }
  if (JSON.stringify([...seenIDs].sort()) !== JSON.stringify([...expectedIDs].sort())) {
    issues.push("launch-set input.packages: package IDs must equal the locked delivery set");
  }
  if (issues.length) throw new ValidationError(issues);

  const byID = new Map(records.map((record) => [record.packageID, record]));
  return expectedIDs.map((packageID) => ({
    packageID,
    sourceRoot: path.resolve(byID.get(packageID).sourceRoot),
    approvalPath: path.resolve(byID.get(packageID).approvalPath),
    assetProvenancePath: path.resolve(byID.get(packageID).assetProvenancePath),
  }));
}

export function launchSetReceiptDigest(receipt) {
  if (!signingIDPattern.test(receipt?.collectionID ?? "")
      || !digestPattern.test(receipt?.collectionSHA256 ?? "")
      || !digestPattern.test(receipt?.finalWorldSHA256 ?? "")
      || !signingIDPattern.test(receipt?.keyID ?? "")
      || !Array.isArray(receipt?.packages) || receipt.packages.length !== 8) {
    throw new ValidationError([
      "launch-set receipt: stable collection/key IDs, collection/final-world digests and eight packages required",
    ]);
  }
  const lines = receipt.packages.map((record, index) => {
    if (!signingIDPattern.test(record?.packageID ?? "")
        || !Array.isArray(record?.chapterIDs)
        || record.chapterIDs.length === 0
        || new Set(record.chapterIDs).size !== record.chapterIDs.length
        || !record.chapterIDs.every((chapterID) => signingIDPattern.test(chapterID))
        || !safePackagePath(record?.payloadPath)
        || !digestPattern.test(record?.payloadSHA256 ?? "")
        || !digestPattern.test(record?.manifestDigest ?? "")) {
      throw new ValidationError([
        `launch-set receipt.packages[${index}]: stable IDs, safe payload path and digests required`,
      ]);
    }
    return [
      `package=${record.packageID}`,
      `chapters=${record.chapterIDs.join(",")}`,
      `payloadPath=${record.payloadPath}`,
      `payloadSHA256=${record.payloadSHA256}`,
      `manifestDigest=${record.manifestDigest}`,
    ].join("\t");
  });
  return sha256(Buffer.from([
    receiptHeader,
    `collectionID=${receipt.collectionID}`,
    `collectionSHA256=${receipt.collectionSHA256}`,
    `finalWorldSHA256=${receipt.finalWorldSHA256}`,
    `keyID=${receipt.keyID}`,
    ...lines,
    "",
  ].join("\n"), "utf8"));
}

export function validateLaunchSetReceipt(receipt, expectedPackageIDs = undefined) {
  const issues = [];
  exactKeys(receipt, [
    "schemaVersion", "kind", "collectionID", "collectionSHA256", "finalWorldSHA256",
    "keyID", "packages", "receiptSHA256",
  ], "launch-set receipt", issues);
  if (receipt?.schemaVersion !== 1 || receipt?.kind !== receiptHeader) {
    issues.push("launch-set receipt: schema version 1 and canonical kind required");
  }
  if (!signingIDPattern.test(receipt?.collectionID ?? "")
      || !signingIDPattern.test(receipt?.keyID ?? "")) {
    issues.push("launch-set receipt: stable collection and key IDs required");
  }
  for (const [key, label] of [
    ["collectionSHA256", "collection"],
    ["finalWorldSHA256", "final world"],
    ["receiptSHA256", "receipt"],
  ]) {
    if (!digestPattern.test(receipt?.[key] ?? "")) {
      issues.push(`launch-set receipt.${key}: lowercase ${label} SHA-256 required`);
    }
  }
  const records = Array.isArray(receipt?.packages) ? receipt.packages : [];
  if (!Array.isArray(receipt?.packages) || records.length !== 8) {
    issues.push("launch-set receipt.packages: exactly eight package records required");
  }
  records.forEach((record, index) => exactKeys(record, [
    "packageID", "chapterIDs", "payloadPath", "payloadSHA256", "manifestDigest",
  ], `launch-set receipt.packages[${index}]`, issues));
  records.forEach((record, index) => {
    const location = `launch-set receipt.packages[${index}]`;
    if (!signingIDPattern.test(record?.packageID ?? "")) {
      issues.push(`${location}.packageID: stable kebab-case ID required`);
    }
    if (!Array.isArray(record?.chapterIDs) || record.chapterIDs.length === 0
        || new Set(record.chapterIDs).size !== record.chapterIDs.length
        || !record.chapterIDs.every((chapterID) => signingIDPattern.test(chapterID))) {
      issues.push(`${location}.chapterIDs: non-empty unique stable IDs required`);
    }
    if (!safePackagePath(record?.payloadPath)) {
      issues.push(`${location}.payloadPath: safe POSIX package-relative path required`);
    }
    if (!digestPattern.test(record?.payloadSHA256 ?? "")
        || !digestPattern.test(record?.manifestDigest ?? "")) {
      issues.push(`${location}: lowercase payload and manifest SHA-256 required`);
    }
  });
  if (expectedPackageIDs !== undefined
      && JSON.stringify(records.map((record) => record.packageID)) !== JSON.stringify(expectedPackageIDs)) {
    issues.push("launch-set receipt.packages: locked delivery order required");
  }
  if (new Set(records.map((record) => record.packageID)).size !== records.length) {
    issues.push("launch-set receipt.packages: unique package IDs required");
  }
  let computed;
  try {
    computed = launchSetReceiptDigest(receipt);
  } catch (error) {
    if (error instanceof ValidationError) issues.push(...error.issues);
    else throw error;
  }
  if (computed !== undefined && receipt?.receiptSHA256 !== computed) {
    issues.push("launch-set receipt.receiptSHA256: receipt material changed");
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

async function publishAtomically(stagingRoot, outputRoot) {
  const existing = await stat(outputRoot).catch(() => null);
  const backupRoot = `${outputRoot}.previous-${process.pid}-${Date.now()}`;
  let movedExisting = false;
  try {
    if (existing) {
      await rename(outputRoot, backupRoot);
      movedExisting = true;
    }
    await rename(stagingRoot, outputRoot);
  } catch (error) {
    if (movedExisting && !await stat(outputRoot).catch(() => null)) {
      await rename(backupRoot, outputRoot).catch(() => {});
    }
    throw error;
  }
  if (movedExisting) {
    await rm(backupRoot, { recursive: true, force: true }).catch(() => {});
  }
}

async function readCollectionSource(entry) {
  const file = path.join(entry.sourceRoot, "collection.json");
  const bytes = await readFile(file).catch((error) => {
    throw new ValidationError([`launch set '${entry.packageID}': collection.json ${error.message}`]);
  });
  let document;
  try {
    document = JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    throw new ValidationError([`launch set '${entry.packageID}': invalid collection.json (${error.message})`]);
  }
  return { file, bytes, document };
}

export async function compileLaunchSet(descriptor, outputRoot, options = {}) {
  if (options.testOnlyAllowUnapprovedBlueprint !== undefined) {
    throw new ValidationError(["compile-launch-set: production approval cannot be bypassed"]);
  }
  const entries = validateLaunchSetDescriptor(descriptor, options.launchConfiguration);
  const resolvedOutput = path.resolve(outputRoot);
  const issues = [];
  for (const [index, entry] of entries.entries()) {
    requireDisjoint(entry.sourceRoot, resolvedOutput, `launch-set input.packages[${index}].sourceRoot`, issues);
    for (const [controlName, controlPath] of [
      ["approvalPath", entry.approvalPath],
      ["assetProvenancePath", entry.assetProvenancePath],
    ]) {
      if (isWithin(resolvedOutput, controlPath)) {
        issues.push(`launch-set input.packages[${index}].${controlName}: backstage control cannot enter output`);
      }
      for (const [sourceIndex, sourceEntry] of entries.entries()) {
        if (isWithin(sourceEntry.sourceRoot, controlPath)) {
          issues.push(
            `launch-set input.packages[${index}].${controlName}: backstage control cannot enter source ${sourceIndex}`,
          );
        }
      }
    }
    for (let rightIndex = index + 1; rightIndex < entries.length; rightIndex += 1) {
      requireDisjoint(
        entry.sourceRoot,
        entries[rightIndex].sourceRoot,
        `launch-set input.packages[${index}].sourceRoot/launch-set input.packages[${rightIndex}].sourceRoot`,
        issues,
      );
    }
  }
  if (issues.length) throw new ValidationError(issues);

  const collectionSources = await Promise.all(entries.map(readCollectionSource));
  const collectionSHA256 = sha256(collectionSources[0].bytes);
  if (collectionSources.some((record) => sha256(record.bytes) !== collectionSHA256)) {
    throw new ValidationError(["compile-launch-set: all eight sources require one byte-identical collection.json"]);
  }
  const collection = collectionSources[0].document;

  const validated = [];
  for (const [index, entry] of entries.entries()) {
    const packageSpec = collection.packages?.find((record) => record.id === entry.packageID);
    if (!packageSpec) {
      throw new ValidationError([`compile-launch-set: collection is missing package '${entry.packageID}'`]);
    }
    const result = await validateLaunchPackageSource(entry.sourceRoot, {
      packageID: entry.packageID,
      packageVersion: packageSpec.version,
      minimumRuntime: packageSpec.minimumRuntime,
      blueprintRoot: options.blueprintRoot,
      launchPackageApprovalPath: entry.approvalPath,
      launchConfiguration: options.launchConfiguration,
      assetProvenancePath: entry.assetProvenancePath,
      costRegistryPath: options.costRegistryPath,
      webSourceInventoryPath: options.webSourceInventoryPath,
      projectSourceRoot: options.projectSourceRoot,
      testOnlyAllowUnprojectedPayload: options.testOnlyAllowUnprojectedPayload,
    });
    if (result.collectionRecord === undefined
        || sha256(result.collectionRecord.bytes) !== collectionSHA256) {
      throw new ValidationError([`compile-launch-set: package '${entry.packageID}' changed collection during validation`]);
    }
    validated.push({ entry, packageSpec, ...result, index });
  }

  const preflightReplay = validateLaunchAssembly(
    collection,
    validated.map((record) => record.payload),
  );

  await mkdir(path.dirname(resolvedOutput), { recursive: true });
  const stagingRoot = await mkdtemp(path.join(
    path.dirname(resolvedOutput),
    `.${path.basename(resolvedOutput)}.launch-set-staging-`,
  ));
  try {
    const packageRoot = path.join(stagingRoot, "packages");
    await mkdir(packageRoot, { recursive: true });
    for (const record of validated) {
      await compilePublicPackage(
        record.entry.sourceRoot,
        path.join(packageRoot, record.packageID),
        {
          packageID: record.packageID,
          packageVersion: record.packageSpec.version,
          minimumRuntime: record.packageSpec.minimumRuntime,
          keyID: options.keyID,
          signingPrivateKey: options.signingPrivateKey,
          blueprintRoot: options.blueprintRoot,
          launchPackageApprovalPath: record.entry.approvalPath,
          launchConfiguration: options.launchConfiguration,
          assetProvenancePath: record.entry.assetProvenancePath,
          costRegistryPath: options.costRegistryPath,
          webSourceInventoryPath: options.webSourceInventoryPath,
          projectSourceRoot: options.projectSourceRoot,
          testOnlyAllowUnprojectedPayload: options.testOnlyAllowUnprojectedPayload,
        },
      );
    }

    const trustedPublicKey = createPublicKey(options.signingPrivateKey);
    const stagedPayloads = [];
    const receiptPackages = [];
    for (const record of validated) {
      const root = path.join(packageRoot, record.packageID);
      const manifest = await verifyCompiledPackage(
        root,
        trustedPublicKey,
        options.keyID,
        record.packageSpec,
      );
      const relativePayloadPath = path.relative(
        record.resolvedSource,
        record.payloadRecord.file,
      ).split(path.sep).join("/");
      const payloadBytes = await readFile(path.join(root, ...relativePayloadPath.split("/")));
      if (sha256(payloadBytes) !== sha256(record.payloadRecord.bytes)) {
        throw new ValidationError([`compile-launch-set: staged payload drifted for '${record.packageID}'`]);
      }
      const stagedCollectionBytes = await readFile(path.join(root, "collection.json"));
      if (sha256(stagedCollectionBytes) !== collectionSHA256) {
        throw new ValidationError([`compile-launch-set: staged collection drifted for '${record.packageID}'`]);
      }
      const payload = JSON.parse(payloadBytes.toString("utf8"));
      validatePublicDocument(payload, `staged.${record.packageID}.payload`);
      stagedPayloads.push(payload);
      receiptPackages.push({
        packageID: record.packageID,
        chapterIDs: record.packageSpec.chapterIDs,
        payloadPath: relativePayloadPath,
        payloadSHA256: sha256(payloadBytes),
        manifestDigest: manifest.manifestDigest,
      });
    }

    const stagedReplay = validateLaunchAssembly(collection, stagedPayloads);
    if (stagedReplay.finalWorldSHA256 !== preflightReplay.finalWorldSHA256) {
      throw new ValidationError(["compile-launch-set: staged world replay differs from preflight"]);
    }
    const receipt = {
      schemaVersion: 1,
      kind: receiptHeader,
      collectionID: collection.collectionID,
      collectionSHA256,
      finalWorldSHA256: stagedReplay.finalWorldSHA256,
      keyID: options.keyID,
      packages: receiptPackages,
    };
    receipt.receiptSHA256 = launchSetReceiptDigest(receipt);
    validateLaunchSetReceipt(receipt, entries.map((entry) => entry.packageID));
    await writeFile(
      path.join(stagingRoot, "launch-set-receipt.json"),
      `${JSON.stringify(receipt, null, 2)}\n`,
      { flag: "wx" },
    );
    await publishAtomically(stagingRoot, resolvedOutput);
    return receipt;
  } catch (error) {
    await rm(stagingRoot, { recursive: true, force: true }).catch(() => {});
    throw error;
  }
}
