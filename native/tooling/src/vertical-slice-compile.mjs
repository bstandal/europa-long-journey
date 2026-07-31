import {
  createHash,
  createPublicKey,
} from "node:crypto";
import { createReadStream } from "node:fs";
import {
  cp,
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
  developmentBlueprintProjectionAuthorityRecord,
  readBlueprintProjectionDocuments,
  validateBlueprintProjection,
  validateDevelopmentBlueprintProjectionAuthority,
} from "./blueprint-projection.mjs";
import {
  manifestIntegrityMaterial,
  publicKeyX963Base64,
  requireApprovedBlueprint,
  requireInstalledByteBudget,
  validateLaunchViewportCropContract,
  validatePackageManifest,
  verifyCompiledPackage,
  verifyPackageManifest,
} from "./compile.mjs";
import { verticalSliceDevelopmentIdentity } from "./development-trust.mjs";
import {
  signVerticalSliceDevelopmentMessage,
  verticalSliceDevelopmentPublicKey,
} from "./deterministic-development-signing.mjs";
import { listFiles, ValidationError, validatePublicTree } from "./validate.mjs";

const signatureAlgorithm = "P-256-SHA256";
const digestPattern = /^[a-f0-9]{64}$/;
const optionKeys = new Set([
  "blueprintRoot",
  "launchConfiguration",
  "projectionAuthorityPath",
  "packageVersion",
  "minimumRuntime",
  "maximumInstalledBytes",
]);

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
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
  return [...records].sort((left, right) => Buffer.compare(Buffer.from(left.path), Buffer.from(right.path)));
}

function isWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`)
    && relative !== ".." && !path.isAbsolute(relative));
}

function requireDisjoint(left, right, location, issues) {
  if (isWithin(left, right) || isWithin(right, left)) issues.push(`${location}: paths must be disjoint`);
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

function validateOptions(options) {
  const issues = [];
  for (const key of Object.keys(options ?? {})) {
    if (!optionKeys.has(key)) issues.push(`vertical-slice compiler options.${key}: forbidden or unknown option`);
  }
  for (const key of [
    "blueprintRoot", "launchConfiguration", "projectionAuthorityPath",
    "packageVersion", "minimumRuntime", "maximumInstalledBytes",
  ]) {
    if (!Object.hasOwn(options ?? {}, key)) issues.push(`vertical-slice compiler options.${key}: required`);
  }
  if (!Number.isSafeInteger(options?.maximumInstalledBytes) || options.maximumInstalledBytes <= 0) {
    issues.push("vertical-slice compiler options.maximumInstalledBytes: positive safe integer required");
  }
  if (issues.length) throw new ValidationError(issues);
}

function requireLaunchIsolation(launchConfiguration) {
  const packageIDs = (launchConfiguration?.delivery?.packages ?? []).map((item) => item.packageID);
  const issues = [];
  if (packageIDs.length !== 8 || new Set(packageIDs).size !== 8
      || packageIDs.some((id) => typeof id !== "string" || !/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.test(id))) {
    issues.push("vertical-slice compiler: locked eight-package launch delivery plan required");
  }
  if (packageIDs.includes(verticalSliceDevelopmentIdentity.packageID)) {
    issues.push("vertical-slice compiler: development package ID collides with a launch package ID");
  }
  if (issues.length) throw new ValidationError(issues);
  return new Set(packageIDs);
}

async function findPayloadRecord(sourceRoot, files) {
  const records = [];
  for (const file of files.filter((candidate) => path.extname(candidate).toLowerCase() === ".json")) {
    const bytes = await readFile(file);
    const document = JSON.parse(bytes.toString("utf8"));
    if (document && typeof document === "object" && Array.isArray(document.chapters)
        && Array.isArray(document.scenes) && Array.isArray(document.audioTimelines)
        && Array.isArray(document.responsiveAudioPrograms)) {
      records.push({ file, bytes, document });
    }
  }
  if (records.length !== 1) {
    throw new ValidationError([
      `${sourceRoot}: vertical-slice compilation requires exactly one ContentPackagePayload, found ${records.length}`,
    ]);
  }
  return records[0];
}

async function sourceSnapshot(sourceRoot, files) {
  return new Map(await Promise.all(files.map(async (file) => [
    path.relative(sourceRoot, file).split(path.sep).join("/"),
    await hashFile(file),
  ])));
}

function requireSnapshot(records, snapshot) {
  const issues = [];
  if (records.length !== snapshot.size) {
    issues.push("vertical-slice package: public source file set changed after validation");
  }
  for (const record of records) {
    const expected = snapshot.get(record.path);
    if (!expected || expected.bytes !== record.bytes || expected.sha256 !== record.sha256) {
      issues.push(`vertical-slice package: source '${record.path}' changed after validation`);
    }
  }
  if (issues.length) throw new ValidationError(issues);
}

function signManifest(metadata, records, publicKey) {
  const unsigned = { ...metadata, files: sortedRecords(records) };
  const material = manifestIntegrityMaterial(unsigned);
  const manifestDigest = sha256(Buffer.from(material, "utf8"));
  const value = signVerticalSliceDevelopmentMessage(
    Buffer.from(manifestDigest, "utf8"),
  ).toString("base64");
  const manifest = {
    ...unsigned,
    manifestDigest,
    signature: {
      algorithm: signatureAlgorithm,
      keyID: verticalSliceDevelopmentIdentity.keyID,
      value,
    },
  };
  validatePackageManifest(manifest);
  verifyPackageManifest(
    manifest,
    publicKey,
    verticalSliceDevelopmentIdentity.keyID,
  );
  return manifest;
}

async function publishAtomically(stagingRoot, outputRoot) {
  const existing = await stat(outputRoot).catch(() => null);
  const backup = `${outputRoot}.previous-${process.pid}-${Date.now()}`;
  let movedExisting = false;
  try {
    if (existing) {
      await rename(outputRoot, backup);
      movedExisting = true;
    }
    await rename(stagingRoot, outputRoot);
  } catch (error) {
    if (movedExisting && !await stat(outputRoot).catch(() => null)) {
      await rename(backup, outputRoot).catch(() => {});
    }
    throw error;
  }
  if (movedExisting) await rm(backup, { recursive: true, force: true }).catch(() => {});
}

async function readProjectionAuthority(file) {
  try {
    const bytes = await readFile(file);
    return { bytes, document: JSON.parse(bytes.toString("utf8")) };
  } catch (error) {
    throw new ValidationError([`projectionAuthorityPath: ${error.message}`]);
  }
}

function verificationSpec(options) {
  return {
    id: verticalSliceDevelopmentIdentity.packageID,
    version: options.packageVersion,
    minimumRuntime: options.minimumRuntime,
    maximumInstalledBytes: options.maximumInstalledBytes,
  };
}

export async function compileDevelopmentVerticalSlice(sourceRoot, outputRoot, options) {
  validateOptions(options);
  const launchPackageIDs = requireLaunchIsolation(options.launchConfiguration);
  const resolvedSource = path.resolve(sourceRoot);
  const resolvedOutput = path.resolve(outputRoot);
  const resolvedAuthority = path.resolve(options.projectionAuthorityPath);
  const issues = [];
  requireDisjoint(resolvedSource, resolvedOutput, "vertical-slice source/output", issues);
  requireDisjoint(
    resolvedSource,
    resolvedAuthority,
    "vertical-slice source/projection authority",
    issues,
  );
  if (isWithin(resolvedOutput, resolvedAuthority)) {
    issues.push(
      "projectionAuthorityPath: backstage authority cannot enter the compiled package",
    );
  }
  if (!resolvedAuthority.split(path.sep).includes("backstage")) {
    issues.push(
      "projectionAuthorityPath: provisional authority must remain under a backstage tree",
    );
  }
  if (issues.length) throw new ValidationError(issues);

  const files = await validatePublicTree(resolvedSource);
  if (files.includes(path.join(resolvedSource, "collection.json"))) {
    throw new ValidationError([
      "vertical-slice compiler: collection.json and launch ownership cannot enter a development slice",
    ]);
  }
  const payloadRecord = await findPayloadRecord(resolvedSource, files);
  const payload = payloadRecord.document;
  if (launchPackageIDs.has(payload.packageID)) {
    throw new ValidationError([
      `vertical-slice compiler: launch package ID '${payload.packageID}' is forbidden`,
    ]);
  }
  if (payload.packageID !== verticalSliceDevelopmentIdentity.packageID) {
    throw new ValidationError([
      `vertical-slice compiler: payload packageID must be '${verticalSliceDevelopmentIdentity.packageID}'`,
    ]);
  }
  validateLaunchViewportCropContract(payload, "verticalSlice.payload");

  await requireApprovedBlueprint(options.blueprintRoot);
  const blueprint = await readBlueprintProjectionDocuments(options.blueprintRoot);
  const projectionAuthority = await readProjectionAuthority(resolvedAuthority);
  const projection = validateBlueprintProjection(payload, blueprint, {
    scope: "VERTICAL_SLICE",
    payloadBytes: payloadRecord.bytes,
  });
  validateDevelopmentBlueprintProjectionAuthority(
    projectionAuthority.document,
    projection,
    verticalSliceDevelopmentIdentity,
  );
  const snapshot = await sourceSnapshot(resolvedSource, files);
  const postProjectionSnapshot = await sourceSnapshot(resolvedSource, files);
  requireSnapshot(
    [...postProjectionSnapshot].map(([recordPath, record]) => ({ path: recordPath, ...record })),
    snapshot,
  );

  const publicKey = verticalSliceDevelopmentPublicKey();
  await mkdir(path.dirname(resolvedOutput), { recursive: true });
  const stagingRoot = await mkdtemp(path.join(
    path.dirname(resolvedOutput),
    `.${path.basename(resolvedOutput)}.vertical-slice-staging-`,
  ));
  try {
    const records = [];
    for (const source of files) {
      const relative = path.relative(resolvedSource, source).split(path.sep).join("/");
      const destination = path.join(stagingRoot, ...relative.split("/"));
      await mkdir(path.dirname(destination), { recursive: true });
      await cp(source, destination, { force: true });
      records.push({ path: relative, ...await hashFile(destination) });
    }
    requireSnapshot(records, snapshot);
    const manifest = signManifest({
      packageID: verticalSliceDevelopmentIdentity.packageID,
      packageVersion: options.packageVersion,
      schemaVersion: payload.schemaVersion,
      minimumRuntime: options.minimumRuntime,
    }, records, publicKey);
    const manifestBytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8");
    requireInstalledByteBudget(records, manifestBytes.byteLength, options.maximumInstalledBytes);
    await writeFile(path.join(stagingRoot, "package-manifest.json"), manifestBytes, { flag: "wx" });
    await verifyCompiledPackage(
      stagingRoot,
      publicKey,
      verticalSliceDevelopmentIdentity.keyID,
      verificationSpec(options),
    );
    await publishAtomically(stagingRoot, resolvedOutput);
    const publicKeySPKIBase64 = publicKey.export({ format: "der", type: "spki" }).toString("base64");
    return {
      manifest,
      projection,
      trustReceipt: {
        schemaVersion: 1,
        kind: verticalSliceDevelopmentIdentity.receiptKind,
        trustDomain: verticalSliceDevelopmentIdentity.trustDomain,
        packageID: verticalSliceDevelopmentIdentity.packageID,
        keyID: verticalSliceDevelopmentIdentity.keyID,
        manifestDigest: manifest.manifestDigest,
        projectionSHA256: projection.projectionSHA256,
        projectionAuthorityKind:
          verticalSliceDevelopmentIdentity.projectionAuthorityKind,
        projectionAuthorityStatus:
          verticalSliceDevelopmentIdentity.projectionAuthorityStatus,
        shippingState: verticalSliceDevelopmentIdentity.shippingState,
        projectionAuthoritySHA256: sha256(projectionAuthority.bytes),
        trustedPublicKeyX963Base64: publicKeyX963Base64(publicKey),
        trustedPublicKeySPKIBase64: publicKeySPKIBase64,
      },
    };
  } catch (error) {
    await rm(stagingRoot, { recursive: true, force: true }).catch(() => {});
    throw error;
  }
}

export async function verifyDevelopmentVerticalSlice(packageRoot, trustReceipt, options) {
  const issues = [];
  exactKeys(trustReceipt, [
    "schemaVersion", "kind", "trustDomain", "packageID", "keyID",
    "manifestDigest", "projectionSHA256", "projectionAuthorityKind",
    "projectionAuthorityStatus", "shippingState", "projectionAuthoritySHA256",
    "trustedPublicKeyX963Base64", "trustedPublicKeySPKIBase64",
  ], "vertical-slice trust receipt", issues);
  if (trustReceipt?.schemaVersion !== 1
      || trustReceipt?.kind !== verticalSliceDevelopmentIdentity.receiptKind
      || trustReceipt?.trustDomain !== verticalSliceDevelopmentIdentity.trustDomain
      || trustReceipt?.packageID !== verticalSliceDevelopmentIdentity.packageID
      || trustReceipt?.keyID !== verticalSliceDevelopmentIdentity.keyID
      || trustReceipt?.projectionAuthorityKind
        !== verticalSliceDevelopmentIdentity.projectionAuthorityKind
      || trustReceipt?.projectionAuthorityStatus
        !== verticalSliceDevelopmentIdentity.projectionAuthorityStatus
      || trustReceipt?.shippingState !== verticalSliceDevelopmentIdentity.shippingState) {
    issues.push("vertical-slice trust receipt: exact non-release identity required");
  }
  if (!digestPattern.test(trustReceipt?.manifestDigest ?? "")
      || !digestPattern.test(trustReceipt?.projectionSHA256 ?? "")
      || !digestPattern.test(trustReceipt?.projectionAuthoritySHA256 ?? "")) {
    issues.push(
      "vertical-slice trust receipt: manifest, projection and authority SHA-256 required",
    );
  }
  let publicKey;
  try {
    publicKey = createPublicKey({
      key: Buffer.from(trustReceipt?.trustedPublicKeySPKIBase64 ?? "", "base64"),
      format: "der",
      type: "spki",
    });
  } catch {
    issues.push("vertical-slice trust receipt: valid P-256 SPKI public key required");
  }
  if (publicKey && publicKeyX963Base64(publicKey) !== trustReceipt.trustedPublicKeyX963Base64) {
    issues.push("vertical-slice trust receipt: SPKI and X9.63 public keys differ");
  }
  if (issues.length) throw new ValidationError(issues);
  const manifest = await verifyCompiledPackage(
    packageRoot,
    publicKey,
    verticalSliceDevelopmentIdentity.keyID,
    verificationSpec(options),
  );
  if (manifest.manifestDigest !== trustReceipt.manifestDigest) {
    throw new ValidationError(["vertical-slice trust receipt: manifest digest drifted"]);
  }
  return manifest;
}

export function createDevelopmentProjectionAuthority(evidence) {
  const authority = developmentBlueprintProjectionAuthorityRecord(
    evidence,
    verticalSliceDevelopmentIdentity,
  );
  validateDevelopmentBlueprintProjectionAuthority(
    authority,
    evidence,
    verticalSliceDevelopmentIdentity,
  );
  return authority;
}
