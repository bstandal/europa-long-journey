import {
  createHash,
  createPrivateKey,
  createPublicKey,
  createSign,
  createVerify,
} from "node:crypto";
import { constants as fsConstants, createReadStream } from "node:fs";
import {
  cp,
  lstat,
  mkdir,
  mkdtemp,
  open,
  readFile,
  realpath,
  rename,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { isDeepStrictEqual } from "node:util";
import { validateBlueprint } from "./blueprint.mjs";
import {
  readBlueprintProjectionDocuments,
  validateBlueprintProjection,
} from "./blueprint-projection.mjs";
import { isDevelopmentOnlySigningKeyID } from "./development-trust.mjs";
import {
  collectShippingAssetReferences,
  listFiles,
  ValidationError,
  validateCollectionAgainstLaunchConfiguration,
  validateCostRegistry,
  validateNativeAssetProvenanceLineage,
  validatePublicTree,
  validateWorldSeedDocument,
} from "./validate.mjs";
import {
  requiredCapabilityByShippingRole,
  shippingAssetRoles,
  shippingMetadataPolicies,
} from "./policy.mjs";

const signatureAlgorithm = "P-256-SHA256";
const integrityHeader = "long-west-package-v1";
const signingIDPattern = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const saveMigrationFields = new Set([
  "beatIdentity",
  "interactionState",
  "cameraAndTextAnchors",
  "narrationAndAudioPosition",
  "cumulativeWorldState",
]);
const saveMigrationWorldOwnershipKeys = [
  "oldEffectIDs",
  "newEffectIDs",
  "oldNodeIDs",
  "newNodeIDs",
  "oldTraceIDs",
  "newTraceIDs",
];
const maximumSaveMigrationEdges = 128;
const launchViewportCrops = Object.freeze([
  Object.freeze({ id: "baseline-393x852", widthPoints: 393, heightPoints: 852 }),
  Object.freeze({ id: "largest-430x932", widthPoints: 430, heightPoints: 932 }),
]);
const phase0EditorialFileNames = [
  "arc-matrix.json",
  "authored-interaction-effects-01-12.json",
  "authored-interaction-effects-13-24.json",
  "chapter-catalog.json",
  "chapter-contracts.json",
  "interaction-mapping.json",
  "world-traces.json",
];

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
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

function versionString(version) {
  return `${version.major}.${version.minor}.${version.patch}`;
}

function requireVersion(value, location) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || !Number.isSafeInteger(value.major) || value.major < 0
      || !Number.isSafeInteger(value.minor) || value.minor < 0
      || !Number.isSafeInteger(value.patch) || value.patch < 0
      || Object.keys(value).some((key) => !["major", "minor", "patch"].includes(key))
      || !["major", "minor", "patch"].every((key) => Object.hasOwn(value, key))) {
    throw new ValidationError([`${location}: { major, minor, patch } non-negative integer version required`]);
  }
  return { major: value.major, minor: value.minor, patch: value.patch };
}

function requireManifestPath(value, location) {
  if (typeof value !== "string" || !value || value.startsWith("/") || value.includes("\\")
      || value.includes("://") || value.split("/").some((segment) => !segment || segment === "." || segment === "..")
      || /[\u0000-\u001f\u007f]/u.test(value)) {
    throw new ValidationError([`${location}: safe POSIX package-relative path required`]);
  }
}

function exactKeys(value, required, location, issues, optional = []) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    issues.push(`${location}: object required`);
    return false;
  }
  for (const key of required) {
    if (!Object.hasOwn(value, key)) issues.push(`${location}.${key}: required`);
  }
  for (const key of Object.keys(value)) {
    if (!required.includes(key) && !optional.includes(key)) {
      issues.push(`${location}.${key}: unknown field`);
    }
  }
  return true;
}

export function manifestIntegrityMaterial(manifest) {
  const packageVersion = requireVersion(manifest.packageVersion, "manifest.packageVersion");
  const schemaVersion = requireVersion(manifest.schemaVersion, "manifest.schemaVersion");
  const minimumRuntime = requireVersion(manifest.minimumRuntime, "manifest.minimumRuntime");
  if (!signingIDPattern.test(manifest.packageID ?? "")) {
    throw new ValidationError(["manifest.packageID: stable kebab-case ID required"]);
  }
  if (!Array.isArray(manifest.files) || !manifest.files.length) {
    throw new ValidationError(["manifest.files: at least one file required"]);
  }
  const records = sortedRecords(manifest.files);
  const { migrationLines } = validateManifestSaveMigrationPlan(manifest, packageVersion);
  const seen = new Set();
  const fileLines = records.map((record, index) => {
    requireManifestPath(record.path, `manifest.files[${index}].path`);
    if (seen.has(record.path)) throw new ValidationError([`manifest.files: duplicate path '${record.path}'`]);
    seen.add(record.path);
    if (!Number.isSafeInteger(record.bytes) || record.bytes < 0) {
      throw new ValidationError([`manifest.files[${index}].bytes: non-negative integer required`]);
    }
    if (typeof record.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(record.sha256)) {
      throw new ValidationError([`manifest.files[${index}].sha256: lowercase SHA-256 required`]);
    }
    return `file=${record.path}\t${record.bytes}\t${record.sha256}`;
  });
  return [
    integrityHeader,
    `packageID=${manifest.packageID}`,
    `packageVersion=${versionString(packageVersion)}`,
    `schemaVersion=${versionString(schemaVersion)}`,
    `minimumRuntime=${versionString(minimumRuntime)}`,
    ...migrationLines,
    ...fileLines,
    "",
  ].join("\n");
}

function compareVersion(left, right) {
  return left.major - right.major || left.minor - right.minor || left.patch - right.patch;
}

function validateCanonicalStableIDArray(value, location, issues) {
  if (!Array.isArray(value)
      || value.some((identifier) => !signingIDPattern.test(identifier ?? ""))) {
    issues.push(`${location}: canonical stable-ID array required`);
    return [];
  }
  const canonical = [...value].sort((left, right) =>
    Buffer.compare(Buffer.from(left), Buffer.from(right)));
  if (new Set(value).size !== value.length
      || JSON.stringify(canonical) !== JSON.stringify(value)) {
    issues.push(`${location}: unique canonical byte order required`);
  }
  return value;
}

function validateWorldOwnershipDelta(value, fields, location, issues) {
  if (!exactKeys(
    value,
    saveMigrationWorldOwnershipKeys,
    `${location}.worldOwnershipDelta`,
    issues,
  )) return value;
  for (const key of saveMigrationWorldOwnershipKeys) {
    validateCanonicalStableIDArray(
      value[key],
      `${location}.worldOwnershipDelta.${key}`,
      issues,
    );
  }
  const ownsAnyWorldRecord = saveMigrationWorldOwnershipKeys.some(
    (key) => Array.isArray(value[key]) && value[key].length > 0,
  );
  const declaresWorldMutation = Array.isArray(fields)
    && fields.includes("cumulativeWorldState");
  if (declaresWorldMutation && !ownsAnyWorldRecord) {
    issues.push(
      `${location}.worldOwnershipDelta: cumulativeWorldState requires an explicit old/new world ownership delta`,
    );
  }
  if (!declaresWorldMutation && ownsAnyWorldRecord) {
    issues.push(
      `${location}.worldOwnershipDelta: world ownership must be empty without cumulativeWorldState`,
    );
  }
  return value;
}

function canonicalWorldOwnershipColumns(delta) {
  return saveMigrationWorldOwnershipKeys.map(
    (key) => `${key}=${delta[key].join(",")}`,
  );
}

function canonicalSaveMigrationEdgeLine(migration, prefix = "saveMigration") {
  return [
    `${prefix}=${migration.id}`,
    versionString(migration.fromContentVersion),
    versionString(migration.toContentVersion),
    `save=${migration.requiredSaveFormatVersion}`,
    `state=${migration.requiredStateSchemaVersion}`,
    `fields=${migration.fields.join(",")}`,
    ...canonicalWorldOwnershipColumns(migration.worldOwnershipDelta),
    `implementation=${migration.implementationSHA256}`,
  ].join("\t");
}

function validateSaveMigrationDeclarations(value, packageVersion, { allowEmpty = false } = {}) {
  if (value === undefined) return [];
  const issues = [];
  if (!Array.isArray(value) || (!allowEmpty && value.length === 0)
      || value.length > maximumSaveMigrationEdges) {
    throw new ValidationError([
      `manifest.saveMigrations: ${allowEmpty ? "array" : "non-empty array"} of at most ${maximumSaveMigrationEdges} edges required`,
    ]);
  }
  const declarations = value.map((migration, index) => {
    const location = `manifest.saveMigrations[${index}]`;
    if (!exactKeys(migration, [
      "id", "fromContentVersion", "toContentVersion",
      "requiredSaveFormatVersion", "requiredStateSchemaVersion", "fields",
      "worldOwnershipDelta", "implementationSHA256",
    ], location, issues)) return migration;
    if (!signingIDPattern.test(migration.id ?? "")) {
      issues.push(`${location}.id: stable kebab-case ID required`);
    }
    let from;
    let to;
    try {
      from = requireVersion(migration.fromContentVersion, `${location}.fromContentVersion`);
      to = requireVersion(migration.toContentVersion, `${location}.toContentVersion`);
    } catch (error) {
      if (error instanceof ValidationError) issues.push(...error.issues);
      else throw error;
    }
    if (from && to && compareVersion(from, to) >= 0) {
      issues.push(`${location}: content versions must advance`);
    }
    if (to && compareVersion(to, packageVersion) > 0) {
      issues.push(`${location}.toContentVersion: cannot exceed manifest packageVersion`);
    }
    if (!Number.isSafeInteger(migration.requiredSaveFormatVersion)
        || migration.requiredSaveFormatVersion < 1) {
      issues.push(`${location}.requiredSaveFormatVersion: positive integer required`);
    }
    if (!Number.isSafeInteger(migration.requiredStateSchemaVersion)
        || migration.requiredStateSchemaVersion < 1) {
      issues.push(`${location}.requiredStateSchemaVersion: positive integer required`);
    }
    if (!Array.isArray(migration.fields) || migration.fields.length === 0
        || migration.fields.some((field) => !saveMigrationFields.has(field))) {
      issues.push(`${location}.fields: non-empty supported field list required`);
    } else {
      const canonical = [...migration.fields].sort((left, right) =>
        Buffer.compare(Buffer.from(left), Buffer.from(right)));
      if (new Set(migration.fields).size !== migration.fields.length
          || JSON.stringify(canonical) !== JSON.stringify(migration.fields)) {
        issues.push(`${location}.fields: unique canonical byte order required`);
      }
    }
    if (typeof migration.implementationSHA256 !== "string"
        || !/^[a-f0-9]{64}$/.test(migration.implementationSHA256)) {
      issues.push(`${location}.implementationSHA256: lowercase SHA-256 required`);
    }
    validateWorldOwnershipDelta(
      migration.worldOwnershipDelta,
      migration.fields,
      location,
      issues,
    );
    return migration;
  });
  const ids = declarations.map((migration) => migration?.id);
  const canonicalIDs = [...ids].sort((left, right) =>
    Buffer.compare(Buffer.from(left ?? ""), Buffer.from(right ?? "")));
  if (new Set(ids).size !== ids.length || JSON.stringify(ids) !== JSON.stringify(canonicalIDs)) {
    issues.push("manifest.saveMigrations: unique migration IDs in canonical byte order required");
  }
  if (issues.length) throw new ValidationError(issues);
  return declarations;
}

function validateSaveMigrationGraph(packageVersion, supportedSources, declarations) {
  const issues = [];
  if (!Array.isArray(supportedSources)
      || supportedSources.length === 0
      || supportedSources.length > maximumSaveMigrationEdges) {
    throw new ValidationError([
      `save migration supported sources: non-empty array of at most ${maximumSaveMigrationEdges} versions required`,
    ]);
  }
  const sources = supportedSources.map((source, index) => {
    try {
      return requireVersion(source, `save migration supported sources[${index}]`);
    } catch (error) {
      if (error instanceof ValidationError) issues.push(...error.issues);
      else throw error;
      return source;
    }
  });
  const canonicalSources = [...sources].sort(compareVersion);
  if (new Set(sources.map(versionString)).size !== sources.length
      || JSON.stringify(canonicalSources) !== JSON.stringify(sources)) {
    issues.push("save migration supported sources: unique semantic-version order required");
  }
  for (const source of sources) {
    if (source && compareVersion(source, packageVersion) >= 0) {
      issues.push(
        `save migration supported source ${versionString(source)} must precede target ${versionString(packageVersion)}`,
      );
    }
  }
  const declaredSources = [...new Set(declarations.map((edge) =>
    versionString(edge.fromContentVersion)))].sort();
  const explicitSources = sources.map(versionString).sort();
  if (JSON.stringify(declaredSources) !== JSON.stringify(explicitSources)) {
    issues.push(
      "save migration supported sources must exactly equal the graph's fromContentVersion set",
    );
  }

  const outgoing = new Map();
  for (const edge of declarations) {
    const key = versionString(edge.fromContentVersion);
    const list = outgoing.get(key) ?? [];
    list.push(edge);
    outgoing.set(key, list);
  }
  const targetKey = versionString(packageVersion);
  const memo = new Map();
  function pathCount(version) {
    const key = versionString(version);
    if (key === targetKey) return 1;
    if (memo.has(key)) return memo.get(key);
    let count = 0;
    for (const edge of outgoing.get(key) ?? []) {
      count = Math.min(2, count + pathCount(edge.toContentVersion));
      if (count === 2) break;
    }
    memo.set(key, count);
    return count;
  }
  for (const source of sources) {
    const count = pathCount(source);
    if (count === 0) {
      issues.push(
        `save migration graph: no complete path from ${versionString(source)} to ${targetKey}`,
      );
    } else if (count > 1) {
      issues.push(
        `save migration graph: ambiguous paths from ${versionString(source)} to ${targetKey}`,
      );
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return sources;
}

export function saveMigrationGraphDigest(
  packageVersionValue,
  supportedSources = [],
  declarations = [],
) {
  const packageVersion = requireVersion(packageVersionValue, "save migration target version");
  if (!Array.isArray(declarations) || !Array.isArray(supportedSources)) {
    throw new ValidationError(["save migration graph: arrays required"]);
  }
  if (declarations.length === 0 && supportedSources.length === 0) {
    return sha256(Buffer.from([
      "long-west-save-migration-graph-v1",
      `target=${versionString(packageVersion)}`,
      "",
    ].join("\n"), "utf8"));
  }
  const validated = validateSaveMigrationDeclarations(declarations, packageVersion);
  const sources = validateSaveMigrationGraph(packageVersion, supportedSources, validated);
  return sha256(Buffer.from([
    "long-west-save-migration-graph-v1",
    `target=${versionString(packageVersion)}`,
    ...sources.map((source) => `source=${versionString(source)}`),
    ...validated.map((edge) => canonicalSaveMigrationEdgeLine(edge, "edge")),
    "",
  ].join("\n"), "utf8"));
}

function validateSaveMigrationDescriptorInventory(inventory, declarations = undefined) {
  const issues = [];
  if (!Array.isArray(inventory) || inventory.length > maximumSaveMigrationEdges) {
    throw new ValidationError([
      `save migration descriptor inventory: array of at most ${maximumSaveMigrationEdges} records required`,
    ]);
  }
  const records = inventory.map((record, index) => {
    const location = `save migration descriptor inventory[${index}]`;
    if (!exactKeys(record, ["id", "path", "sha256"], location, issues)) return record;
    if (!signingIDPattern.test(record.id ?? "")) {
      issues.push(`${location}.id: stable kebab-case ID required`);
    }
    try {
      requireManifestPath(record.path, `${location}.path`);
    } catch (error) {
      if (error instanceof ValidationError) issues.push(...error.issues);
      else throw error;
    }
    if (typeof record.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(record.sha256)) {
      issues.push(`${location}.sha256: lowercase SHA-256 required`);
    }
    return record;
  });
  const ids = records.map((record) => record?.id);
  const canonicalIDs = [...ids].sort((left, right) =>
    Buffer.compare(Buffer.from(left ?? ""), Buffer.from(right ?? "")));
  if (new Set(ids).size !== ids.length || JSON.stringify(ids) !== JSON.stringify(canonicalIDs)) {
    issues.push("save migration descriptor inventory: unique IDs in canonical byte order required");
  }
  const paths = records.map((record) => record?.path);
  if (new Set(paths).size !== paths.length) {
    issues.push("save migration descriptor inventory: unique descriptor paths required");
  }
  if (declarations !== undefined) {
    if (records.length !== declarations.length) {
      issues.push("save migration descriptor inventory: one record per graph edge required");
    }
    const declarationsByID = new Map(declarations.map((edge) => [edge.id, edge]));
    for (const record of records) {
      const declaration = declarationsByID.get(record?.id);
      if (!declaration || declaration.implementationSHA256 !== record?.sha256) {
        issues.push(
          `save migration descriptor inventory: '${record?.id ?? "<missing>"}' does not match its graph implementation digest`,
        );
      }
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return records;
}

export function saveMigrationDescriptorInventoryDigest(inventory = []) {
  const records = validateSaveMigrationDescriptorInventory(inventory);
  return sha256(Buffer.from([
    "long-west-save-migration-descriptor-inventory-v1",
    ...records.map((record) =>
      `descriptor=${record.id}\t${record.path}\t${record.sha256}`),
    "",
  ].join("\n"), "utf8"));
}

function sameFileIdentity(left, right) {
  return left.dev === right.dev && left.ino === right.ino;
}

async function requireBoundSaveMigrationDescriptors(
  descriptorRootValue,
  inventory,
  sourceRoot,
) {
  if (typeof descriptorRootValue !== "string"
      || !path.isAbsolute(descriptorRootValue)) {
    throw new ValidationError([
      "saveMigrationDescriptorRoot: explicit absolute backstage directory required",
    ]);
  }

  const configuredRoot = path.resolve(descriptorRootValue);
  let configuredRootStat;
  try {
    configuredRootStat = await lstat(configuredRoot);
  } catch {
    throw new ValidationError([
      "saveMigrationDescriptorRoot: readable backstage directory required",
    ]);
  }
  if (configuredRootStat.isSymbolicLink() || !configuredRootStat.isDirectory()) {
    throw new ValidationError([
      "saveMigrationDescriptorRoot: real directory required; symbolic links are forbidden",
    ]);
  }

  let descriptorRoot;
  try {
    descriptorRoot = await realpath(configuredRoot);
  } catch {
    throw new ValidationError([
      "saveMigrationDescriptorRoot: backstage directory could not be resolved",
    ]);
  }

  if (sourceRoot !== undefined) {
    let resolvedSource;
    try {
      resolvedSource = await realpath(path.resolve(sourceRoot));
    } catch {
      throw new ValidationError([
        "saveMigrationDescriptorRoot: public source root could not be resolved",
      ]);
    }
    if (isPathWithin(resolvedSource, descriptorRoot)
        || isPathWithin(descriptorRoot, resolvedSource)) {
      throw new ValidationError([
        "saveMigrationDescriptorRoot: backstage descriptors and the public source tree must be disjoint",
      ]);
    }
  }

  for (const record of inventory) {
    const segments = record.path.split("/");
    let descriptorPath = descriptorRoot;
    for (const [index, segment] of segments.entries()) {
      descriptorPath = path.join(descriptorPath, segment);
      let componentStat;
      try {
        componentStat = await lstat(descriptorPath);
      } catch {
        throw new ValidationError([
          `save migration descriptor '${record.id}': '${record.path}' does not exist under the backstage descriptor root`,
        ]);
      }
      if (componentStat.isSymbolicLink()) {
        throw new ValidationError([
          `save migration descriptor '${record.id}': symbolic links are forbidden in '${record.path}'`,
        ]);
      }
      const isDescriptor = index === segments.length - 1;
      if ((!isDescriptor && !componentStat.isDirectory())
          || (isDescriptor && !componentStat.isFile())) {
        throw new ValidationError([
          `save migration descriptor '${record.id}': '${record.path}' must resolve through real directories to one regular file`,
        ]);
      }
    }

    let resolvedDescriptor;
    try {
      resolvedDescriptor = await realpath(descriptorPath);
    } catch {
      throw new ValidationError([
        `save migration descriptor '${record.id}': '${record.path}' could not be resolved`,
      ]);
    }
    if (!isPathWithin(descriptorRoot, resolvedDescriptor)
        || resolvedDescriptor !== descriptorPath) {
      throw new ValidationError([
        `save migration descriptor '${record.id}': '${record.path}' escapes its backstage descriptor root`,
      ]);
    }

    let handle;
    let bytes;
    let openedStat;
    try {
      handle = await open(
        descriptorPath,
        fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
      );
      openedStat = await handle.stat();
      if (!openedStat.isFile()) {
        throw new Error("not a regular file");
      }
      bytes = await handle.readFile();
      const completedStat = await handle.stat();
      if (!sameFileIdentity(openedStat, completedStat)
          || openedStat.size !== completedStat.size
          || openedStat.mtimeMs !== completedStat.mtimeMs) {
        throw new Error("changed while being read");
      }
    } catch {
      throw new ValidationError([
        `save migration descriptor '${record.id}': '${record.path}' could not be read as one stable regular file`,
      ]);
    } finally {
      await handle?.close().catch(() => {});
    }

    let finalPathStat;
    let finalResolvedDescriptor;
    try {
      [finalPathStat, finalResolvedDescriptor] = await Promise.all([
        lstat(descriptorPath),
        realpath(descriptorPath),
      ]);
    } catch {
      throw new ValidationError([
        `save migration descriptor '${record.id}': '${record.path}' changed during verification`,
      ]);
    }
    if (finalPathStat.isSymbolicLink() || !finalPathStat.isFile()
        || !sameFileIdentity(openedStat, finalPathStat)
        || finalResolvedDescriptor !== descriptorPath) {
      throw new ValidationError([
        `save migration descriptor '${record.id}': '${record.path}' changed during verification`,
      ]);
    }

    const actualSHA256 = sha256(bytes);
    if (actualSHA256 !== record.sha256) {
      throw new ValidationError([
        `save migration descriptor '${record.id}': exact bytes do not match inventory and graph implementation digest`,
      ]);
    }
  }
}

async function prepareSaveMigrationPlan(options, packageVersion, sourceRoot) {
  const provided = [
    options.saveMigrations,
    options.saveMigrationSupportedSourceVersions,
    options.saveMigrationDescriptorInventory,
  ].some((value) => value !== undefined);
  if (!provided) {
    if (options.saveMigrationDescriptorRoot !== undefined) {
      throw new ValidationError([
        "saveMigrationDescriptorRoot: cannot be supplied without a save-migration plan",
      ]);
    }
    return {
      manifestMetadata: {},
      graphSHA256: saveMigrationGraphDigest(packageVersion),
      descriptorInventorySHA256: saveMigrationDescriptorInventoryDigest(),
    };
  }
  if (options.saveMigrations === undefined
      || options.saveMigrationSupportedSourceVersions === undefined
      || options.saveMigrationDescriptorInventory === undefined) {
    throw new ValidationError([
      "save migration plan: saveMigrations, saveMigrationSupportedSourceVersions and saveMigrationDescriptorInventory are all required together",
    ]);
  }
  const declarations = validateSaveMigrationDeclarations(options.saveMigrations, packageVersion);
  const supportedSources = validateSaveMigrationGraph(
    packageVersion,
    options.saveMigrationSupportedSourceVersions,
    declarations,
  );
  const inventory = validateSaveMigrationDescriptorInventory(
    options.saveMigrationDescriptorInventory,
    declarations,
  );
  await requireBoundSaveMigrationDescriptors(
    options.saveMigrationDescriptorRoot,
    inventory,
    sourceRoot,
  );
  const descriptorInventorySHA256 = saveMigrationDescriptorInventoryDigest(inventory);
  return {
    manifestMetadata: {
      saveMigrationSupportedSourceVersions: supportedSources,
      saveMigrationDescriptorInventorySHA256: descriptorInventorySHA256,
      saveMigrations: declarations,
    },
    graphSHA256: saveMigrationGraphDigest(packageVersion, supportedSources, declarations),
    descriptorInventorySHA256,
  };
}

function validateManifestSaveMigrationPlan(manifest, packageVersion) {
  const values = [
    manifest.saveMigrations,
    manifest.saveMigrationSupportedSourceVersions,
    manifest.saveMigrationDescriptorInventorySHA256,
  ];
  const presentCount = values.filter((value) => value !== undefined).length;
  if (presentCount === 0) return { migrationLines: [] };
  if (presentCount !== values.length) {
    throw new ValidationError([
      "manifest save migration plan: graph, supported sources and descriptor inventory digest are required together",
    ]);
  }
  const declarations = validateSaveMigrationDeclarations(manifest.saveMigrations, packageVersion);
  const sources = validateSaveMigrationGraph(
    packageVersion,
    manifest.saveMigrationSupportedSourceVersions,
    declarations,
  );
  if (typeof manifest.saveMigrationDescriptorInventorySHA256 !== "string"
      || !/^[a-f0-9]{64}$/.test(manifest.saveMigrationDescriptorInventorySHA256)) {
    throw new ValidationError([
      "manifest.saveMigrationDescriptorInventorySHA256: lowercase SHA-256 required",
    ]);
  }
  return {
    migrationLines: [
      `saveMigrationSupportedSources=${sources.map(versionString).join(",")}`,
      `saveMigrationDescriptorInventory=${manifest.saveMigrationDescriptorInventorySHA256}`,
      ...declarations.map((migration) => canonicalSaveMigrationEdgeLine(migration)),
    ],
  };
}

export function validatePackageManifest(manifest) {
  const issues = [];
  exactKeys(manifest,
    ["packageID", "packageVersion", "schemaVersion", "minimumRuntime", "files", "manifestDigest", "signature"],
    "manifest", issues, [
      "saveMigrationSupportedSourceVersions",
      "saveMigrationDescriptorInventorySHA256",
      "saveMigrations",
    ]);
  if (issues.length) throw new ValidationError(issues);
  const material = manifestIntegrityMaterial(manifest);
  validateManifestSaveMigrationPlan(
    manifest,
    requireVersion(manifest.packageVersion, "manifest.packageVersion"),
  );
  for (const [index, record] of manifest.files.entries()) {
    exactKeys(record, ["path", "bytes", "sha256"], `manifest.files[${index}]`, issues);
    if (record.path === "package-manifest.json") issues.push(`manifest.files[${index}].path: manifest cannot inventory itself`);
  }
  const authoredOrder = manifest.files.map((record) => record.path);
  const canonicalOrder = sortedRecords(manifest.files).map((record) => record.path);
  if (JSON.stringify(authoredOrder) !== JSON.stringify(canonicalOrder)) {
    issues.push("manifest.files: records must already be sorted by UTF-8 path bytes");
  }
  if (manifest.manifestDigest !== sha256(Buffer.from(material, "utf8"))) {
    issues.push("manifest.manifestDigest: does not bind package metadata and file records");
  }
  if (exactKeys(manifest.signature, ["algorithm", "keyID", "value"], "manifest.signature", issues)) {
    if (manifest.signature.algorithm !== signatureAlgorithm) {
      issues.push(`manifest.signature.algorithm: ${signatureAlgorithm} required`);
    }
    if (!signingIDPattern.test(manifest.signature.keyID ?? "")) {
      issues.push("manifest.signature.keyID: stable kebab-case ID required");
    }
    if (typeof manifest.signature.value !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(manifest.signature.value)) {
      issues.push("manifest.signature.value: base64 DER signature required");
    } else if (Buffer.from(manifest.signature.value, "base64").toString("base64") !== manifest.signature.value) {
      issues.push("manifest.signature.value: canonical padded base64 required");
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return manifest;
}

function requireP256PrivateKey(value) {
  if (!value) throw new ValidationError(["signingPrivateKey: P-256 private key required"]);
  let key;
  try {
    key = value?.type === "private" && value?.asymmetricKeyType ? value : createPrivateKey(value);
  } catch (error) {
    throw new ValidationError([`signingPrivateKey: ${error.message}`]);
  }
  if (key.asymmetricKeyType !== "ec" || key.asymmetricKeyDetails?.namedCurve !== "prime256v1") {
    throw new ValidationError(["signingPrivateKey: EC prime256v1/P-256 key required"]);
  }
  return key;
}

function requireP256PublicKey(value) {
  let key;
  try {
    if (value?.type === "public" && value?.asymmetricKeyType) key = value;
    else key = createPublicKey(value);
  } catch (error) {
    throw new ValidationError([`trustedPublicKey: ${error.message}`]);
  }
  if (key.asymmetricKeyType !== "ec" || key.asymmetricKeyDetails?.namedCurve !== "prime256v1") {
    throw new ValidationError(["trustedPublicKey: EC prime256v1/P-256 key required"]);
  }
  return key;
}

export function publicKeyX963Base64(publicKey) {
  const key = requireP256PublicKey(publicKey);
  const jwk = key.export({ format: "jwk" });
  const x = Buffer.from(jwk.x, "base64url");
  const y = Buffer.from(jwk.y, "base64url");
  if (x.length !== 32 || y.length !== 32) throw new ValidationError(["trustedPublicKey: invalid P-256 coordinates"]);
  return Buffer.concat([Buffer.from([0x04]), x, y]).toString("base64");
}

export function verifyPackageManifest(manifest, trustedPublicKey, expectedKeyID = undefined) {
  validatePackageManifest(manifest);
  if (expectedKeyID !== undefined && manifest.signature.keyID !== expectedKeyID) {
    throw new ValidationError([`manifest.signature.keyID: expected '${expectedKeyID}'`]);
  }
  const publicKey = requireP256PublicKey(trustedPublicKey);
  const verifier = createVerify("SHA256");
  verifier.update(Buffer.from(manifest.manifestDigest, "utf8"));
  verifier.end();
  let signature;
  try {
    signature = Buffer.from(manifest.signature.value, "base64");
  } catch {
    throw new ValidationError(["manifest.signature.value: invalid base64"]);
  }
  let verified = false;
  try {
    verified = verifier.verify({ key: publicKey, dsaEncoding: "der" }, signature);
  } catch {
    verified = false;
  }
  if (!verified) {
    throw new ValidationError(["manifest.signature: verification failed"]);
  }
  return true;
}

async function readJSON(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

export function phase0EditorialDigest(filesByName) {
  const names = Object.keys(filesByName ?? {}).sort();
  if (JSON.stringify(names) !== JSON.stringify(phase0EditorialFileNames)) {
    throw new ValidationError(["editor-approval: complete Phase 0 editorial file set required"]);
  }
  const material = names.map((name) =>
    `${name}\0${sha256(filesByName[name])}\n`).join("");
  return sha256(Buffer.from(material, "utf8"));
}

function testOnlyApprovalEscape(options) {
  if (options.testOnlyAllowUnapprovedBlueprint !== true) return false;
  if (!process.env.NODE_TEST_CONTEXT) {
    throw new ValidationError(["testOnlyAllowUnapprovedBlueprint: available only under node --test"]);
  }
  return true;
}

function testOnlyProjectionEscape(options) {
  if (options.testOnlyAllowUnprojectedPayload !== true) return false;
  if (!process.env.NODE_TEST_CONTEXT) {
    throw new ValidationError(["testOnlyAllowUnprojectedPayload: available only under node --test"]);
  }
  return true;
}

export async function requireApprovedBlueprint(blueprintRoot, options = {}) {
  if (testOnlyApprovalEscape(options)) return { testOnlyBypass: true };
  if (!blueprintRoot) throw new ValidationError(["blueprintRoot: production compilation requires the approved Phase 0 blueprint"]);
  await validateBlueprint(blueprintRoot);
  const contracts = await readJSON(path.join(blueprintRoot, "chapter-contracts.json"));
  const arcs = await readJSON(path.join(blueprintRoot, "arc-matrix.json"));
  validateBlueprintApprovals(contracts, arcs);
  const approval = await readJSON(path.join(blueprintRoot, "editor-approval.json"));
  const editorialBytes = Object.fromEntries(await Promise.all(
    phase0EditorialFileNames.map(async (name) => [name, await readFile(path.join(blueprintRoot, name))])
  ));
  const contractBytes = editorialBytes["chapter-contracts.json"];
  const arcBytes = editorialBytes["arc-matrix.json"];
  validateEditorApprovalRecord(
    approval,
    contractBytes,
    arcBytes,
    phase0EditorialDigest(editorialBytes),
  );
  return { contracts: contracts.contracts.length, arcChapters: arcs.chapters.length };
}

export function validateBlueprintApprovals(contracts, arcs) {
  const issues = [];
  for (const [index, contract] of (contracts.contracts ?? []).entries()) {
    if (contract.editorApproval !== "APPROVED") {
      issues.push(`chapter-contracts.contracts[${index}].editorApproval: APPROVED required for production`);
    }
  }
  for (const [index, chapter] of (arcs.chapters ?? []).entries()) {
    if (chapter.editorApproval !== "APPROVED") {
      issues.push(`arc-matrix.chapters[${index}].editorApproval: APPROVED required for production`);
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

export function validateEditorApprovalRecord(
  approval,
  contractBytes,
  arcBytes,
  editorialDigest,
) {
  const issues = [];
  if (approval?.schemaVersion !== 1
      || approval?.status !== "APPROVED_BY_EDITOR_IN_CHIEF"
      || approval?.authority !== "editor-in-chief") {
    issues.push("editor-approval: explicit editor-in-chief approval record required");
  }
  if (typeof approval?.approvedAt !== "string"
      || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(approval.approvedAt)
      || typeof approval?.decisionReference !== "string"
      || approval.decisionReference.length < 12) {
    issues.push("editor-approval: UTC time and decision reference required");
  }
  const digest = (value) => createHash("sha256").update(value).digest("hex");
  if (approval?.chapterContractsSHA256 !== digest(contractBytes)
      || approval?.arcMatrixSHA256 !== digest(arcBytes)
      || approval?.phase0EditorialSHA256 !== editorialDigest) {
    issues.push("editor-approval: approved Phase 0 editorial digest does not match");
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

async function findPackagePayload(sourceRoot, files) {
  const payloads = [];
  for (const file of files.filter((candidate) => path.extname(candidate).toLowerCase() === ".json")) {
    const document = await readJSON(file);
    if (document && typeof document === "object" && Array.isArray(document.chapters)
        && Array.isArray(document.scenes) && Array.isArray(document.audioTimelines)
        && Array.isArray(document.responsiveAudioPrograms)) {
      payloads.push(document);
    }
  }
  if (payloads.length !== 1) {
    throw new ValidationError([`${sourceRoot}: compilation requires exactly one ContentPackagePayload, found ${payloads.length}`]);
  }
  return payloads[0];
}

async function findLaunchCollectionRecord(sourceRoot, files) {
  const collectionPath = path.join(sourceRoot, "collection.json");
  if (!files.includes(collectionPath)) {
    throw new ValidationError([`${sourceRoot}: production compilation requires collection.json`]);
  }
  const bytes = await readFile(collectionPath);
  return {
    document: JSON.parse(bytes.toString("utf8")),
    file: collectionPath,
    bytes,
  };
}

function sameVersion(left, right) {
  return left.major === right.major && left.minor === right.minor && left.patch === right.patch;
}

export function requireMatchingCollectionPackageSpec(
  collection,
  packageID,
  packageVersion,
  minimumRuntime,
) {
  const packageSpec = collection?.packages?.find(({ id }) => id === packageID);
  if (!packageSpec) {
    throw new ValidationError([`collection.packages: no package specification for '${packageID}'`]);
  }
  const declaredVersion = requireVersion(packageSpec.version, `collection.packages.${packageID}.version`);
  const declaredRuntime = requireVersion(packageSpec.minimumRuntime, `collection.packages.${packageID}.minimumRuntime`);
  if (!sameVersion(packageVersion, declaredVersion)) {
    throw new ValidationError([`packageVersion: must exactly match collection package '${packageID}' version ${versionString(declaredVersion)}`]);
  }
  if (!sameVersion(minimumRuntime, declaredRuntime)) {
    throw new ValidationError([`minimumRuntime: must exactly match collection package '${packageID}' runtime ${versionString(declaredRuntime)}`]);
  }
  return packageSpec;
}

function sameStringSet(left, right) {
  return JSON.stringify([...(left ?? [])].sort()) === JSON.stringify([...(right ?? [])].sort());
}

function sameStringArray(left, right) {
  return Array.isArray(left)
    && Array.isArray(right)
    && left.length === right.length
    && left.every((value, index) => value === right[index]);
}

export function launchPublicSourceInventoryDigest(records) {
  const inventory = records instanceof Map
    ? [...records].map(([recordPath, record]) => ({ path: recordPath, ...record }))
    : records;
  if (!Array.isArray(inventory) || !inventory.length) {
    throw new ValidationError(["launch public inventory: at least one file record required"]);
  }
  const seen = new Set();
  const lines = sortedRecords(inventory).map((record, index) => {
    requireManifestPath(record.path, `launch public inventory[${index}].path`);
    if (seen.has(record.path)) {
      throw new ValidationError([`launch public inventory: duplicate path '${record.path}'`]);
    }
    seen.add(record.path);
    if (!Number.isSafeInteger(record.bytes) || record.bytes < 0
        || typeof record.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(record.sha256)) {
      throw new ValidationError([
        `launch public inventory '${record.path}': exact bytes and lowercase SHA-256 required`,
      ]);
    }
    return `file=${record.path}\t${record.bytes}\t${record.sha256}`;
  });
  return sha256(Buffer.from([
    "long-west-launch-public-inventory-v1",
    ...lines,
    "",
  ].join("\n"), "utf8"));
}

export function launchPackageApprovalDigest(
  collectionBytes,
  payloadBytes,
  publicSourceInventorySHA256,
  saveMigrationGraphSHA256,
  saveMigrationDescriptorInventorySHA256,
) {
  if (![publicSourceInventorySHA256, saveMigrationGraphSHA256,
    saveMigrationDescriptorInventorySHA256].every((value) =>
    typeof value === "string" && /^[a-f0-9]{64}$/.test(value))) {
    throw new ValidationError([
      "launch-package approval: lowercase public-source, migration-graph and descriptor-inventory SHA-256 values required",
    ]);
  }
  return sha256(Buffer.from([
    "long-west-launch-package-approval-v2",
    `collectionSHA256=${sha256(collectionBytes)}`,
    `payloadSHA256=${sha256(payloadBytes)}`,
    `publicSourceInventorySHA256=${publicSourceInventorySHA256}`,
    `saveMigrationGraphSHA256=${saveMigrationGraphSHA256}`,
    `saveMigrationDescriptorInventorySHA256=${saveMigrationDescriptorInventorySHA256}`,
    "",
  ].join("\n"), "utf8"));
}

export function validateLaunchPackageApprovalRecord(
  approval,
  collection,
  collectionBytes,
  payload,
  payloadBytes,
  publicSourceInventorySHA256,
  saveMigrationGraphSHA256,
  saveMigrationDescriptorInventorySHA256,
) {
  const requiredKeys = [
    "schemaVersion", "status", "authority", "approvedAt", "decisionReference",
    "collectionID", "packageID", "chapterIDs", "collectionSHA256", "payloadSHA256",
    "publicSourceInventorySHA256", "saveMigrationGraphSHA256",
    "saveMigrationDescriptorInventorySHA256", "launchPackageApprovalSHA256",
  ];
  const issues = [];
  exactKeys(approval, requiredKeys, "launch-package approval", issues);
  if (approval?.schemaVersion !== 2
      || approval?.status !== "APPROVED_BY_EDITOR_IN_CHIEF"
      || approval?.authority !== "editor-in-chief") {
    issues.push("launch-package approval: explicit editor-in-chief approval record required");
  }
  if (typeof approval?.approvedAt !== "string"
      || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(approval.approvedAt)
      || typeof approval?.decisionReference !== "string"
      || approval.decisionReference.length < 12) {
    issues.push("launch-package approval: UTC time and decision reference required");
  }

  const payloadChapterIDs = (payload?.chapters ?? []).map((chapter) => chapter?.id);
  const packageSpec = collection?.packages?.find(({ id }) => id === payload?.packageID);
  if (!signingIDPattern.test(approval?.collectionID ?? "")
      || !signingIDPattern.test(approval?.packageID ?? "")
      || !Array.isArray(approval?.chapterIDs)
      || !approval.chapterIDs.length
      || new Set(approval.chapterIDs).size !== approval.chapterIDs.length
      || !approval.chapterIDs.every((id) => signingIDPattern.test(id))) {
    issues.push("launch-package approval: stable collection, package and unique chapter IDs required");
  }
  if (approval?.collectionID !== collection?.collectionID
      || approval?.packageID !== payload?.packageID) {
    issues.push("launch-package approval: collection or package identity does not match");
  }
  if (!packageSpec
      || !sameStringArray(packageSpec.chapterIDs, payloadChapterIDs)
      || !sameStringArray(approval?.chapterIDs, payloadChapterIDs)) {
    issues.push("launch-package approval: chapter ownership and order do not match collection and payload");
  }

  const combinedDigest = launchPackageApprovalDigest(
    collectionBytes,
    payloadBytes,
    publicSourceInventorySHA256,
    saveMigrationGraphSHA256,
    saveMigrationDescriptorInventorySHA256,
  );
  if (approval?.collectionSHA256 !== sha256(collectionBytes)
      || approval?.payloadSHA256 !== sha256(payloadBytes)
      || approval?.publicSourceInventorySHA256 !== publicSourceInventorySHA256
      || approval?.saveMigrationGraphSHA256 !== saveMigrationGraphSHA256
      || approval?.saveMigrationDescriptorInventorySHA256
        !== saveMigrationDescriptorInventorySHA256
      || approval?.launchPackageApprovalSHA256 !== combinedDigest) {
    issues.push(
      "launch-package approval: approved collection, payload, public inventory or save-migration authority digest does not match",
    );
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

async function requireLaunchPackageApproval(
  approvalPath,
  sourceRoot,
  collectionRecord,
  payloadRecord,
  sourceSnapshot,
  saveMigrationPlan,
) {
  if (!approvalPath) {
    throw new ValidationError([
      "launchPackageApprovalPath: separate backstage approval record required",
    ]);
  }
  const resolvedApproval = path.resolve(approvalPath);
  if (isPathWithin(sourceRoot, resolvedApproval)
      || !resolvedApproval.split(path.sep).includes("backstage")) {
    throw new ValidationError([
      "launchPackageApprovalPath: approval must remain under a separate backstage tree",
    ]);
  }
  const approvalStat = await stat(resolvedApproval).catch(() => null);
  if (!approvalStat?.isFile()) {
    throw new ValidationError(["launchPackageApprovalPath: readable JSON file required"]);
  }
  let approval;
  try {
    approval = await readJSON(resolvedApproval);
  } catch (error) {
    throw new ValidationError([`launchPackageApprovalPath: ${error.message}`]);
  }
  validateLaunchPackageApprovalRecord(
    approval,
    collectionRecord.document,
    collectionRecord.bytes,
    payloadRecord.document,
    payloadRecord.bytes,
    launchPublicSourceInventoryDigest(sourceSnapshot),
    saveMigrationPlan.graphSHA256,
    saveMigrationPlan.descriptorInventorySHA256,
  );
  return approval;
}

async function findFutureReleaseRecord(sourceRoot, files) {
  const releases = [];
  for (const file of files.filter((candidate) => path.extname(candidate).toLowerCase() === ".json")) {
    const bytes = await readFile(file);
    const document = JSON.parse(bytes.toString("utf8"));
    if (document && typeof document === "object" && Object.hasOwn(document, "publishedAtUnixMillis")) {
      releases.push({ document, file, bytes });
    }
  }
  if (releases.length !== 1) {
    throw new ValidationError([
      `${sourceRoot}: future-release compilation requires exactly one public Release record, found ${releases.length}`,
    ]);
  }
  return releases[0];
}

async function findPackagePayloadRecord(
  sourceRoot,
  files,
  context = "future-release compilation",
) {
  const payloads = [];
  for (const file of files.filter((candidate) => path.extname(candidate).toLowerCase() === ".json")) {
    const bytes = await readFile(file);
    const document = JSON.parse(bytes.toString("utf8"));
    if (document && typeof document === "object" && Array.isArray(document.chapters)
        && Array.isArray(document.scenes) && Array.isArray(document.audioTimelines)
        && Array.isArray(document.responsiveAudioPrograms)) {
      payloads.push({ document, file, bytes });
    }
  }
  if (payloads.length !== 1) {
    throw new ValidationError([
      `${sourceRoot}: ${context} requires exactly one ContentPackagePayload, found ${payloads.length}`,
    ]);
  }
  return payloads[0];
}

export function requireMatchingFutureRelease(release, payload) {
  const issues = [];
  if (release?.packageID !== payload?.packageID) {
    issues.push("future release: Release packageID must match ContentPackagePayload packageID");
  }
  const payloadChapterIDs = (payload?.chapters ?? []).map((chapter) => chapter.id);
  if (!Array.isArray(release?.chapterIDs)
      || release.chapterIDs.length !== payloadChapterIDs.length
      || release.chapterIDs.some((id, index) => id !== payloadChapterIDs[index])) {
    issues.push("future release: Release chapter ownership must exactly match ContentPackagePayload chapters");
  }
  if (!(release?.chapterIDs ?? []).includes(release?.contentID)) {
    issues.push("future release: contentID must identify an owned chapter");
  }
  let version;
  let minimumRuntime;
  try {
    version = requireVersion(release?.version, "future release.version");
    minimumRuntime = requireVersion(release?.minimumRuntime, "future release.minimumRuntime");
  } catch (error) {
    if (error instanceof ValidationError) issues.push(...error.issues);
    else throw error;
  }
  if (!Number.isSafeInteger(release?.maximumInstalledBytes) || release.maximumInstalledBytes <= 0) {
    issues.push("future release.maximumInstalledBytes: positive safe integer required");
  }
  if (issues.length) throw new ValidationError(issues);
  return {
    id: release.packageID,
    version,
    chapterIDs: [...release.chapterIDs],
    maximumInstalledBytes: release.maximumInstalledBytes,
    minimumRuntime,
    isEssentialInstall: false,
  };
}

export function requireFutureReleaseIsolation(release, payload, launchConfiguration) {
  const catalog = launchConfiguration?.catalog;
  const delivery = launchConfiguration?.delivery;
  const launchChapterIDs = (catalog?.chapters ?? []).map((chapter) => chapter.contentID);
  const deliveryChapterIDs = (delivery?.packages ?? []).flatMap((item) => item.chapterIDs ?? []);
  const launchPackageIDs = (delivery?.packages ?? []).map((item) => item.packageID);
  const issues = [];
  if (catalog?.chapterCount !== 24 || launchChapterIDs.length !== 24
      || new Set(launchChapterIDs).size !== 24
      || !launchChapterIDs.every((id) => signingIDPattern.test(id))) {
    issues.push("launchConfiguration: the locked 24-chapter catalog is required to isolate future releases");
  }
  if (delivery?.packages?.length !== 8
      || !sameStringSet(launchChapterIDs, deliveryChapterIDs)
      || new Set(launchPackageIDs).size !== 8
      || !launchPackageIDs.every((id) => signingIDPattern.test(id))) {
    issues.push("launchConfiguration: the locked eight-package delivery plan is required to isolate future releases");
  }
  const futureChapterIDs = (payload?.chapters ?? []).map((chapter) => chapter.id);
  const overlappingChapterIDs = futureChapterIDs.filter((id) => launchChapterIDs.includes(id));
  if (overlappingChapterIDs.length || launchChapterIDs.includes(release?.contentID)) {
    issues.push(`future release: cannot own locked launch content${overlappingChapterIDs.length ? ` '${overlappingChapterIDs.join("', '")}'` : ""}`);
  }
  if (launchPackageIDs.includes(release?.packageID)) {
    issues.push("future release: packageID cannot reuse a locked launch package ID");
  }
  for (const chapter of payload?.chapters ?? []) {
    const effectPrefix = `effect-${chapter.id}-`;
    const beats = (chapter.arcs ?? []).flatMap((arc) => arc.beats ?? []);
    const effects = [
      ...(chapter.completionEffects ?? []),
      ...beats.flatMap((beat) => [
        ...(beat.completionEffects ?? []),
        ...(beat.interaction?.completionEffects ?? []),
      ]),
    ];
    for (const effect of effects) {
      if (typeof effect?.id !== "string"
          || !effect.id.startsWith(effectPrefix)
          || effect.id.length === effectPrefix.length) {
        issues.push(
          `future release: world effect '${effect?.id ?? "<missing>"}' must be namespaced to owning chapter '${chapter.id}'`,
        );
      }
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

export function futureReleaseApprovalDigest(
  releaseBytes,
  payloadBytes,
  publicationBytes,
  worldAuthorityBytes,
  saveMigrationGraphSHA256,
  saveMigrationDescriptorInventorySHA256,
) {
  if (![saveMigrationGraphSHA256, saveMigrationDescriptorInventorySHA256].every(
    (value) => typeof value === "string" && /^[a-f0-9]{64}$/.test(value),
  )) {
    throw new ValidationError([
      "future-release approval: lowercase migration-graph and descriptor-inventory SHA-256 values required",
    ]);
  }
  const releaseDigest = sha256(releaseBytes);
  const payloadDigest = sha256(payloadBytes);
  const publicationDigest = sha256(publicationBytes);
  const worldAuthorityDigest = sha256(worldAuthorityBytes);
  return sha256(Buffer.from([
    "long-west-future-release-approval-v3",
    `releaseSHA256=${releaseDigest}`,
    `payloadSHA256=${payloadDigest}`,
    `publicationSHA256=${publicationDigest}`,
    `worldAuthoritySHA256=${worldAuthorityDigest}`,
    `saveMigrationGraphSHA256=${saveMigrationGraphSHA256}`,
    `saveMigrationDescriptorInventorySHA256=${saveMigrationDescriptorInventorySHA256}`,
    "",
  ].join("\n"), "utf8"));
}

export function validateFutureReleasePublicationRecord(publication, release) {
  const issues = [];
  exactKeys(
    publication,
    ["schemaVersion", "releaseID", "contentID", "packageID", "worldPlacement"],
    "future-release publication",
    issues,
  );
  if (publication?.schemaVersion !== 1) {
    issues.push("future-release publication.schemaVersion: version 1 required");
  }
  if (publication?.releaseID !== release?.id
      || publication?.contentID !== release?.contentID
      || publication?.packageID !== release?.packageID) {
    issues.push("future-release publication: release identity does not match");
  }
  const placement = publication?.worldPlacement;
  exactKeys(
    placement,
    ["worldNodeID", "historicalYear", "chronologyOrdinal"],
    "future-release publication.worldPlacement",
    issues,
  );
  if (!signingIDPattern.test(placement?.worldNodeID ?? "")) {
    issues.push(
      "future-release publication.worldPlacement.worldNodeID: stable kebab-case ID required",
    );
  }
  if (!Number.isSafeInteger(placement?.historicalYear)) {
    issues.push(
      "future-release publication.worldPlacement.historicalYear: safe integer required",
    );
  }
  if (!Number.isSafeInteger(placement?.chronologyOrdinal)
      || placement.chronologyOrdinal < 0) {
    issues.push(
      "future-release publication.worldPlacement.chronologyOrdinal: non-negative safe integer required",
    );
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

export function validateFutureReleaseWorldAuthorityRecord(authority) {
  const issues = [];
  exactKeys(
    authority,
    [
      "schemaVersion", "kind", "status", "authority", "approvedAt",
      "decisionReference", "collectionID", "worldSeed", "placementNodeIDs",
    ],
    "future-release world authority",
    issues,
  );
  if (authority?.schemaVersion !== 1
      || authority?.kind !== "FUTURE_RELEASE_WORLD_AUTHORITY"
      || authority?.status !== "APPROVED_BY_EDITOR_IN_CHIEF"
      || authority?.authority !== "editor-in-chief") {
    issues.push(
      "future-release world authority: explicit editor-in-chief authority record required",
    );
  }
  if (typeof authority?.approvedAt !== "string"
      || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(authority.approvedAt)
      || typeof authority?.decisionReference !== "string"
      || authority.decisionReference.length < 12) {
    issues.push("future-release world authority: UTC time and decision reference required");
  }
  if (!signingIDPattern.test(authority?.collectionID ?? "")) {
    issues.push("future-release world authority.collectionID: stable collection ID required");
  }
  try {
    validateWorldSeedDocument(
      authority?.worldSeed,
      "future-release world authority.worldSeed",
    );
  } catch (error) {
    if (error instanceof ValidationError) issues.push(...error.issues);
    else throw error;
  }
  if (!Array.isArray(authority?.placementNodeIDs)
      || authority.placementNodeIDs.length === 0
      || authority.placementNodeIDs.some((id) => !signingIDPattern.test(id ?? ""))) {
    issues.push(
      "future-release world authority.placementNodeIDs: non-empty stable node-ID list required",
    );
  } else if (new Set(authority.placementNodeIDs).size !== authority.placementNodeIDs.length) {
    issues.push("future-release world authority.placementNodeIDs: duplicate node ID");
  }
  if (Array.isArray(authority?.placementNodeIDs)
      && Array.isArray(authority?.worldSeed?.nodes)) {
    const seededNodeIDs = new Set(authority.worldSeed.nodes.map((node) => node?.id));
    for (const worldNodeID of authority.placementNodeIDs) {
      if (!seededNodeIDs.has(worldNodeID)) {
        issues.push(
          `future-release world authority.placementNodeIDs: '${worldNodeID}' is not an exact canonical worldSeed node`,
        );
      }
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

export function requireFutureReleaseWorldContinuity(
  publication,
  worldAuthority,
  release,
  payload,
  launchConfiguration,
) {
  validateFutureReleasePublicationRecord(publication, release);
  validateFutureReleaseWorldAuthorityRecord(worldAuthority);
  const issues = [];
  if (worldAuthority.collectionID !== launchConfiguration?.catalog?.collectionID) {
    issues.push(
      "future-release world authority: collection does not match the locked launch catalog",
    );
  }
  if (!isDeepStrictEqual(payload?.worldSeed, worldAuthority.worldSeed)) {
    issues.push(
      "future release: ContentPackagePayload world seed drifted from the trusted launch world authority",
    );
  }
  const worldNodeID = publication.worldPlacement.worldNodeID;
  if (!worldAuthority.placementNodeIDs.includes(worldNodeID)) {
    issues.push(
      `future-release publication: world placement node '${worldNodeID}' does not exist in the trusted launch world authority`,
    );
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

export function validateFutureReleaseApprovalRecord(
  approval,
  release,
  releaseBytes,
  payloadBytes,
  publicationBytes,
  worldAuthorityBytes,
  saveMigrationGraphSHA256,
  saveMigrationDescriptorInventorySHA256,
) {
  const requiredKeys = [
    "schemaVersion", "status", "authority", "approvedAt", "decisionReference",
    "releaseID", "contentID", "packageID", "releaseSHA256", "payloadSHA256",
    "publicationSHA256", "worldAuthoritySHA256", "saveMigrationGraphSHA256",
    "saveMigrationDescriptorInventorySHA256",
    "releasePayloadPublicationAuthoritySHA256",
  ];
  const issues = [];
  exactKeys(approval, requiredKeys, "future-release approval", issues);
  if (approval?.schemaVersion !== 3
      || approval?.status !== "APPROVED_BY_EDITOR_IN_CHIEF"
      || approval?.authority !== "editor-in-chief") {
    issues.push("future-release approval: explicit editor-in-chief approval record required");
  }
  if (typeof approval?.approvedAt !== "string"
      || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(approval.approvedAt)
      || typeof approval?.decisionReference !== "string"
      || approval.decisionReference.length < 12) {
    issues.push("future-release approval: UTC time and decision reference required");
  }
  if (approval?.releaseID !== release?.id
      || approval?.contentID !== release?.contentID
      || approval?.packageID !== release?.packageID) {
    issues.push("future-release approval: release identity does not match");
  }
  if (approval?.releaseSHA256 !== sha256(releaseBytes)
      || approval?.payloadSHA256 !== sha256(payloadBytes)
      || approval?.publicationSHA256 !== sha256(publicationBytes)
      || approval?.worldAuthoritySHA256 !== sha256(worldAuthorityBytes)
      || approval?.saveMigrationGraphSHA256 !== saveMigrationGraphSHA256
      || approval?.saveMigrationDescriptorInventorySHA256
        !== saveMigrationDescriptorInventorySHA256
      || approval?.releasePayloadPublicationAuthoritySHA256
        !== futureReleaseApprovalDigest(
          releaseBytes,
          payloadBytes,
          publicationBytes,
          worldAuthorityBytes,
          saveMigrationGraphSHA256,
          saveMigrationDescriptorInventorySHA256,
        )) {
    issues.push(
      "future-release approval: approved Release, payload, publication, world authority or save-migration authority digest does not match",
    );
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

function isPathWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`)
    && relative !== ".." && !path.isAbsolute(relative));
}

async function requireFutureReleaseApproval(
  approvalPath,
  sourceRoot,
  releaseRecord,
  payloadRecord,
  publicationRecord,
  worldAuthorityRecord,
  saveMigrationPlan,
) {
  if (!approvalPath) {
    throw new ValidationError(["futureReleaseApprovalPath: separate backstage approval record required"]);
  }
  const resolvedApproval = path.resolve(approvalPath);
  if (isPathWithin(sourceRoot, resolvedApproval)
      || !resolvedApproval.split(path.sep).includes("backstage")) {
    throw new ValidationError([
      "futureReleaseApprovalPath: approval must remain under a separate backstage tree",
    ]);
  }
  const approvalStat = await stat(resolvedApproval).catch(() => null);
  if (!approvalStat?.isFile()) {
    throw new ValidationError(["futureReleaseApprovalPath: readable JSON file required"]);
  }
  let approval;
  try {
    approval = await readJSON(resolvedApproval);
  } catch (error) {
    throw new ValidationError([`futureReleaseApprovalPath: ${error.message}`]);
  }
  validateFutureReleaseApprovalRecord(
    approval,
    releaseRecord.document,
    releaseRecord.bytes,
    payloadRecord.bytes,
    publicationRecord.bytes,
    worldAuthorityRecord.bytes,
    saveMigrationPlan.graphSHA256,
    saveMigrationPlan.descriptorInventorySHA256,
  );
  return approval;
}

async function readSeparateBackstageControl(controlPath, optionName, sourceRoot) {
  if (!controlPath) {
    throw new ValidationError([`${optionName}: separate backstage JSON record required`]);
  }
  const resolved = path.resolve(controlPath);
  if (isPathWithin(sourceRoot, resolved)
      || !resolved.split(path.sep).includes("backstage")) {
    throw new ValidationError([
      `${optionName}: record must remain under a separate backstage tree`,
    ]);
  }
  const controlStat = await stat(resolved).catch(() => null);
  if (!controlStat?.isFile()) {
    throw new ValidationError([`${optionName}: readable JSON file required`]);
  }
  let document;
  let bytes;
  try {
    bytes = await readFile(resolved);
    document = JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    throw new ValidationError([`${optionName}: ${error.message}`]);
  }
  return { path: resolved, document, bytes };
}

async function requireFutureReleaseWorldControls(
  publicationPath,
  worldAuthorityPath,
  sourceRoot,
  release,
  payload,
  launchConfiguration,
) {
  const [publicationRecord, worldAuthorityRecord] = await Promise.all([
    readSeparateBackstageControl(
      publicationPath,
      "futureReleasePublicationPath",
      sourceRoot,
    ),
    readSeparateBackstageControl(
      worldAuthorityPath,
      "futureReleaseWorldAuthorityPath",
      sourceRoot,
    ),
  ]);
  if (publicationRecord.path === worldAuthorityRecord.path) {
    throw new ValidationError([
      "future-release controls: publication and world authority must be separate records",
    ]);
  }
  requireFutureReleaseWorldContinuity(
    publicationRecord.document,
    worldAuthorityRecord.document,
    release,
    payload,
    launchConfiguration,
  );
  return { publicationRecord, worldAuthorityRecord };
}

async function snapshotPublicFiles(sourceRoot, files) {
  const snapshot = new Map();
  for (const file of files) {
    const relative = path.relative(sourceRoot, file).split(path.sep).join("/");
    snapshot.set(relative, await hashFile(file));
  }
  return snapshot;
}

function requireMatchingFileSnapshot(actualRecords, expectedSnapshot, context = "future release") {
  const issues = [];
  if (actualRecords.length !== expectedSnapshot.size) {
    issues.push(`${context}: public source file set changed during validation or compilation`);
  }
  for (const record of actualRecords) {
    const expected = expectedSnapshot.get(record.path);
    if (!expected || expected.bytes !== record.bytes || expected.sha256 !== record.sha256) {
      issues.push(`${context}: public source '${record.path}' changed after approval validation`);
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

const forbiddenBinaryMetadataTokens = [
  "backstage",
  "researchnotes",
  "sourceids",
  "scholarnotes",
  "claimregister",
  "verifierfinding",
  "citationlist",
  "codexprovisionalnonshipping",
  "provisionalnonshippingproductionmaster",
];

async function findForbiddenBinaryMetadata(file) {
  let carry = Buffer.alloc(0);
  for await (const chunk of createReadStream(file)) {
    const combined = Buffer.concat([carry, chunk]);
    const searchable = combined.toString("latin1").toLowerCase().replace(/[^a-z0-9]/g, "");
    const found = forbiddenBinaryMetadataTokens.find((token) => searchable.includes(token));
    if (found) return found;
    carry = combined.subarray(Math.max(0, combined.length - 128));
  }
  return undefined;
}

async function projectAudioFileInventory(registry, projectSourceRoot) {
  const relativePaths = new Set();
  for (const asset of Array.isArray(registry?.assets) ? registry.assets : []) {
    for (const lineage of Array.isArray(asset?.sourceLineage) ? asset.sourceLineage : []) {
      if (lineage?.lineageType === "PROJECT_AUTHORED_AUDIO" && typeof lineage.sourcePath === "string") {
        relativePaths.add(lineage.sourcePath);
      }
      if (lineage?.lineageType === "OPEN_LICENSE_AUDIO_SOURCE"
          && lineage.licenseSPDX === "MIT"
          && typeof lineage.noticePath === "string") {
        relativePaths.add(lineage.noticePath);
      }
    }
  }
  if (relativePaths.size === 0) return new Map();
  if (!projectSourceRoot) {
    throw new ValidationError(["projectSourceRoot: authored audio and licence notices require exact local source bytes"]);
  }
  const root = path.resolve(projectSourceRoot);
  const records = new Map();
  for (const relativePath of [...relativePaths].sort()) {
    const file = path.resolve(root, relativePath);
    if (!file.startsWith(`${root}${path.sep}`)) {
      throw new ValidationError([`asset provenance: project source escaped root: ${relativePath}`]);
    }
    let record;
    try {
      record = await hashFile(file);
    } catch {
      throw new ValidationError([`asset provenance: project source is missing: ${relativePath}`]);
    }
    records.set(relativePath, record);
  }
  return records;
}

export async function validateShippingAssetProvenance(
  sourceRoot,
  files,
  registryPath,
  costRegistryPath,
  webSourceInventoryPath = undefined,
  projectSourceRoot = undefined,
) {
  if (!registryPath) throw new ValidationError(["assetProvenancePath: production registry is required"]);
  if (!costRegistryPath) throw new ValidationError(["costRegistryPath: production zero-cost registry is required"]);
  const registry = await readJSON(registryPath).catch((error) => {
    throw new ValidationError([`assetProvenancePath: ${error.message}`]);
  });
  const costRegistry = await readJSON(costRegistryPath).catch((error) => {
    throw new ValidationError([`costRegistryPath: ${error.message}`]);
  });
  const webSourceInventory = webSourceInventoryPath === undefined
    ? undefined
    : await readJSON(webSourceInventoryPath).catch((error) => {
      throw new ValidationError([`webSourceInventoryPath: ${error.message}`]);
    });
  const projectFiles = await projectAudioFileInventory(registry, projectSourceRoot);
  validateNativeAssetProvenanceLineage(registry, webSourceInventory, projectFiles);
  validateCostRegistry(costRegistry);
  const costEntries = new Map(costRegistry.entries.map((entry) => [entry.id, entry]));
  const unresolvedCapabilities = new Map(
    costRegistry.unresolvedCapabilities.map((capability) => [capability.id, capability]),
  );
  const payload = await findPackagePayload(sourceRoot, files);
  const expectedRoles = collectShippingAssetReferences(payload);
  const records = new Map();
  const issues = [];
  exactKeys(registry, ["schemaVersion", "status", "assets"], "asset provenance", issues);
  if (registry.schemaVersion !== 3 || !["NO_NATIVE_ASSETS_APPROVED", "ACTIVE"].includes(registry.status)) {
    issues.push("asset provenance: schema version 3 and a recognised status are required");
  }
  const assetRecords = Array.isArray(registry.assets) ? registry.assets : [];
  if (!Array.isArray(registry.assets)) issues.push("asset provenance.assets: array required");
  for (const [index, record] of assetRecords.entries()) {
    const location = `asset provenance[${index}]`;
    if (!exactKeys(record, [
      "assetPath", "bytes", "sha256", "sourceLineage", "toolLineage", "shippingRoles",
      "metadataPolicy", "rightsStatus", "incrementalCostNOK", "approvedForShipping",
    ], location, issues)) continue;
    try {
      requireManifestPath(record.assetPath, `${location}.assetPath`);
    } catch (error) {
      if (error instanceof ValidationError) issues.push(...error.issues);
      else throw error;
    }
    if (records.has(record.assetPath)) issues.push(`asset provenance: duplicate path '${record.assetPath}'`);
    records.set(record.assetPath, record);
    if (!Number.isSafeInteger(record.bytes) || record.bytes < 0
        || typeof record.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(record.sha256)) {
      issues.push(`asset provenance '${record.assetPath}': exact bytes and SHA-256 required`);
    }
    if (record.rightsStatus !== "COMMERCIAL_USE_CLEARED"
        || record.incrementalCostNOK !== 0 || record.approvedForShipping !== true
        || !Array.isArray(record.sourceLineage) || !record.sourceLineage.length
        || !Array.isArray(record.toolLineage) || !record.toolLineage.length
        || !Array.isArray(record.shippingRoles) || !record.shippingRoles.length
        || !shippingMetadataPolicies.has(record.metadataPolicy)) {
      issues.push(`asset provenance '${record.assetPath}': cleared rights, zero cost and full lineage required`);
    }
    const toolIDs = [];
    const toolLineage = Array.isArray(record.toolLineage) ? record.toolLineage : [];
    for (const [toolIndex, tool] of toolLineage.entries()) {
      const toolLocation = `${location}.toolLineage[${toolIndex}]`;
      if (!exactKeys(tool, ["toolID"], toolLocation, issues)) continue;
      toolIDs.push(tool.toolID);
      const entry = costEntries.get(tool.toolID);
      if (!entry) {
        issues.push(`${toolLocation}: unknown zero-cost tool '${tool.toolID}'`);
      } else if (!["tool", "model", "service", "sdk"].includes(entry.category)) {
        issues.push(`${toolLocation}: '${tool.toolID}' is not a production tool, model, service or SDK`);
      }
    }
    if (new Set(toolIDs).size !== toolIDs.length) issues.push(`${location}.toolLineage: duplicate tool ID`);
    const roles = Array.isArray(record.shippingRoles) ? record.shippingRoles : [];
    if (new Set(roles).size !== roles.length || roles.some((role) => !shippingAssetRoles.has(role))) {
      issues.push(`${location}.shippingRoles: unique typed shipping roles required`);
    }
    const requiredRoles = expectedRoles.get(record.assetPath);
    if (!requiredRoles || !sameStringSet(roles, requiredRoles)) {
      issues.push(`${location}.shippingRoles: must exactly match the public content references`);
    }
    for (const role of roles) {
      const capabilityID = requiredCapabilityByShippingRole.get(role);
      if (!capabilityID) continue;
      if (unresolvedCapabilities.has(capabilityID)) {
        issues.push(`${location}.shippingRoles: required capability '${capabilityID}' remains unresolved`);
      } else if (!costEntries.has(capabilityID)) {
        issues.push(`${location}.shippingRoles: required capability '${capabilityID}' has no cleared zero-cost entry`);
      }
    }
  }
  const assets = files.filter((file) => path.extname(file).toLowerCase() !== ".json");
  if (registry.status === "NO_NATIVE_ASSETS_APPROVED" && assetRecords.length) {
    issues.push("asset provenance: non-empty registry must use ACTIVE status");
  }
  for (const file of assets) {
    const relative = path.relative(sourceRoot, file).split(path.sep).join("/");
    const record = records.get(relative);
    if (!record) {
      issues.push(`asset provenance: '${relative}' is not approved`);
      continue;
    }
    const actual = await hashFile(file);
    if (record.bytes !== actual.bytes || record.sha256 !== actual.sha256) {
      issues.push(`asset provenance: '${relative}' hash or byte count drifted`);
    }
    const forbiddenMetadata = await findForbiddenBinaryMetadata(file);
    if (forbiddenMetadata) {
      issues.push(`asset provenance: '${relative}' contains forbidden backstage metadata '${forbiddenMetadata}'`);
    }
  }
  for (const assetPath of records.keys()) {
    if (!assets.some((file) => path.relative(sourceRoot, file).split(path.sep).join("/") === assetPath)) {
      issues.push(`asset provenance: '${assetPath}' does not correspond to a shipping file`);
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return { assets: assets.length };
}

export async function validateFutureReleaseSource(sourceRoot, options = {}) {
  const resolvedSource = path.resolve(sourceRoot);
  const files = await validatePublicTree(resolvedSource);
  const sourceSnapshot = await snapshotPublicFiles(resolvedSource, files);
  if (files.includes(path.join(resolvedSource, "collection.json"))) {
    throw new ValidationError([
      "future release: collection.json is launch-only and cannot enter the future-release compiler",
    ]);
  }
  const [releaseRecord, payloadRecord] = await Promise.all([
    findFutureReleaseRecord(resolvedSource, files),
    findPackagePayloadRecord(resolvedSource, files),
  ]);
  const packageSpec = requireMatchingFutureRelease(
    releaseRecord.document,
    payloadRecord.document,
  );
  const saveMigrationPlan = await prepareSaveMigrationPlan(
    options,
    packageSpec.version,
    resolvedSource,
  );
  requireFutureReleaseIsolation(
    releaseRecord.document,
    payloadRecord.document,
    options.launchConfiguration,
  );
  const { publicationRecord, worldAuthorityRecord }
    = await requireFutureReleaseWorldControls(
      options.futureReleasePublicationPath,
      options.futureReleaseWorldAuthorityPath,
      resolvedSource,
      releaseRecord.document,
      payloadRecord.document,
      options.launchConfiguration,
    );
  await requireFutureReleaseApproval(
    options.futureReleaseApprovalPath,
    resolvedSource,
    releaseRecord,
    payloadRecord,
    publicationRecord,
    worldAuthorityRecord,
    saveMigrationPlan,
  );
  await validateShippingAssetProvenance(
    resolvedSource,
    files,
    options.assetProvenancePath,
    options.costRegistryPath,
    options.webSourceInventoryPath,
    options.projectSourceRoot,
  );
  const postValidationSnapshot = await snapshotPublicFiles(resolvedSource, files);
  requireMatchingFileSnapshot(
    [...postValidationSnapshot].map(([file, record]) => ({ path: file, ...record })),
    sourceSnapshot,
  );
  return {
    files,
    release: releaseRecord.document,
    payload: payloadRecord.document,
    publication: publicationRecord.document,
    worldAuthority: worldAuthorityRecord.document,
    worldAuthoritySHA256: sha256(worldAuthorityRecord.bytes),
    packageSpec,
    sourceSnapshot,
    saveMigrationPlan,
  };
}

function signingManifest(metadata, records, privateKey, keyID) {
  const unsigned = { ...metadata, files: sortedRecords(records) };
  const material = manifestIntegrityMaterial(unsigned);
  const manifestDigest = sha256(Buffer.from(material, "utf8"));
  const signer = createSign("SHA256");
  signer.update(Buffer.from(manifestDigest, "utf8"));
  signer.end();
  const signature = signer.sign({ key: privateKey, dsaEncoding: "der" }).toString("base64");
  const manifest = {
    ...unsigned,
    manifestDigest,
    signature: { algorithm: signatureAlgorithm, keyID, value: signature },
  };
  validatePackageManifest(manifest);
  verifyPackageManifest(manifest, createPublicKey(privateKey), keyID);
  return manifest;
}

export function requireInstalledByteBudget(records, manifestBytes, maximumInstalledBytes) {
  if (!Number.isSafeInteger(manifestBytes) || manifestBytes <= 0
      || !Number.isSafeInteger(maximumInstalledBytes) || maximumInstalledBytes <= 0) {
    throw new ValidationError(["installed byte budget: positive safe integers required"]);
  }
  let installedBytes = manifestBytes;
  for (const [index, record] of records.entries()) {
    if (!Number.isSafeInteger(record.bytes) || record.bytes < 0
        || installedBytes > Number.MAX_SAFE_INTEGER - record.bytes) {
      throw new ValidationError([`installed byte budget: invalid file size at record ${index}`]);
    }
    installedBytes += record.bytes;
  }
  if (installedBytes > maximumInstalledBytes) {
    throw new ValidationError([
      `installed byte budget: ${installedBytes} exceeds declared package maximum ${maximumInstalledBytes}`,
    ]);
  }
  return installedBytes;
}

function validateLaunchViewportCropSet(crops, location, issues) {
  if (!Array.isArray(crops)) {
    issues.push(`${location}: exactly baseline-393x852 and largest-430x932 are required`);
    return [];
  }
  if (crops.length !== launchViewportCrops.length) {
    issues.push(`${location}: exactly baseline-393x852 and largest-430x932 are required`);
  }

  const allowedIDs = new Set(launchViewportCrops.map(({ id }) => id));
  for (const [index, crop] of crops.entries()) {
    if (!crop || typeof crop !== "object" || Array.isArray(crop)) {
      issues.push(`${location}[${index}]: viewport crop object required`);
    } else if (!allowedIDs.has(crop.id)) {
      issues.push(`${location}[${index}].id: only baseline-393x852 and largest-430x932 may ship at launch`);
    }
  }

  for (const requirement of launchViewportCrops) {
    const matches = crops.filter((crop) => crop?.id === requirement.id);
    if (matches.length !== 1) {
      issues.push(`${location}: '${requirement.id}' must occur exactly once`);
      continue;
    }
    const viewport = matches[0].viewport;
    if (viewport?.widthPoints !== requirement.widthPoints
        || viewport?.heightPoints !== requirement.heightPoints) {
      issues.push(
        `${location}.${requirement.id}.viewport: ${requirement.widthPoints} by ${requirement.heightPoints} points required`,
      );
    }
  }

  return crops
    .filter((crop) => crop && typeof crop === "object" && !Array.isArray(crop))
    .map((crop) => `${crop.id}:${crop.viewport?.widthPoints}x${crop.viewport?.heightPoints}`)
    .sort();
}

/**
 * Launch-only production gate. General public-document validation deliberately
 * continues to accept the provisional one-crop development vertical slice.
 */
export function validateLaunchViewportCropContract(payload, location = "launchPackage.payload") {
  const issues = [];
  const scenes = Array.isArray(payload?.scenes) ? payload.scenes : [];
  for (const [index, scene] of scenes.entries()) {
    const sceneLocation = `${location}.scenes[${index}]`;
    const normalSignature = validateLaunchViewportCropSet(
      scene?.sceneCanvas?.viewportCrops,
      `${sceneLocation}.sceneCanvas.viewportCrops`,
      issues,
    );
    const reducedSignature = validateLaunchViewportCropSet(
      scene?.reduceMotionComposition?.viewportCrops,
      `${sceneLocation}.reduceMotionComposition.viewportCrops`,
      issues,
    );
    if (JSON.stringify(normalSignature) !== JSON.stringify(reducedSignature)) {
      issues.push(
        `${sceneLocation}: normal and Reduce Motion crops must have the same launch ID/dimension set`,
      );
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

async function publishStagingAtomically(stagingRoot, outputRoot) {
  const outputStat = await stat(outputRoot).catch(() => null);
  const backupRoot = `${outputRoot}.previous-${process.pid}-${Date.now()}`;
  let movedExisting = false;
  try {
    if (outputStat) {
      await rename(outputRoot, backupRoot);
      movedExisting = true;
    }
    await rename(stagingRoot, outputRoot);
    if (movedExisting) await rm(backupRoot, { recursive: true, force: true });
  } catch (error) {
    if (movedExisting && !await stat(outputRoot).catch(() => null)) {
      await rename(backupRoot, outputRoot).catch(() => {});
    }
    throw error;
  }
}

export async function validateLaunchPackageSource(sourceRoot, options = {}) {
  const resolvedSource = path.resolve(sourceRoot);
  const files = await validatePublicTree(resolvedSource);
  const sourceSnapshot = await snapshotPublicFiles(resolvedSource, files);
  const payloadRecord = await findPackagePayloadRecord(
    resolvedSource,
    files,
    "launch-package compilation",
  );
  const payload = payloadRecord.document;
  const packageID = options.packageID ?? payload.packageID;
  if (packageID !== payload.packageID) {
    throw new ValidationError([`packageID: '${packageID}' does not match ContentPackagePayload '${payload.packageID}'`]);
  }
  if (!signingIDPattern.test(packageID)) throw new ValidationError(["packageID: stable kebab-case ID required"]);
  const packageVersion = requireVersion(options.packageVersion, "packageVersion");
  const saveMigrationPlan = await prepareSaveMigrationPlan(
    options,
    packageVersion,
    resolvedSource,
  );
  const minimumRuntime = requireVersion(options.minimumRuntime, "minimumRuntime");
  const schemaVersion = requireVersion(payload.schemaVersion, "contentPackage.schemaVersion");
  const approval = await requireApprovedBlueprint(options.blueprintRoot, options);
  const projectionBypass = testOnlyProjectionEscape(options);
  let packageSpec;
  let collectionRecord;
  if (!approval.testOnlyBypass) {
    validateLaunchViewportCropContract(payload);
    if (!options.launchConfiguration) {
      throw new ValidationError(["launchConfiguration: production compilation requires product, catalog and delivery data"]);
    }
    collectionRecord = await findLaunchCollectionRecord(resolvedSource, files);
    const collection = collectionRecord.document;
    const launchIssues = validateCollectionAgainstLaunchConfiguration(
      collection,
      options.launchConfiguration,
    );
    if (launchIssues.length) throw new ValidationError(launchIssues);
    packageSpec = requireMatchingCollectionPackageSpec(
      collection,
      packageID,
      packageVersion,
      minimumRuntime,
    );
    if (!Number.isSafeInteger(packageSpec.maximumInstalledBytes) || packageSpec.maximumInstalledBytes <= 0) {
      throw new ValidationError([`collection.packages: no installed byte budget for '${packageID}'`]);
    }
    await requireLaunchPackageApproval(
      options.launchPackageApprovalPath,
      resolvedSource,
      collectionRecord,
      payloadRecord,
      sourceSnapshot,
      saveMigrationPlan,
    );
    if (!projectionBypass) {
      const projectionDocuments = await readBlueprintProjectionDocuments(options.blueprintRoot);
      validateBlueprintProjection(payload, projectionDocuments, {
        scope: "COMPLETE_CHAPTERS",
        payloadBytes: payloadRecord.bytes,
      });
    }
    await validateShippingAssetProvenance(
      resolvedSource,
      files,
      options.assetProvenancePath,
      options.costRegistryPath,
      options.webSourceInventoryPath,
      options.projectSourceRoot,
    );
    const postValidationSnapshot = await snapshotPublicFiles(resolvedSource, files);
    requireMatchingFileSnapshot(
      [...postValidationSnapshot].map(([file, record]) => ({ path: file, ...record })),
      sourceSnapshot,
      "launch package",
    );
  }

  return {
    resolvedSource,
    files,
    sourceSnapshot,
    payloadRecord,
    payload,
    packageID,
    packageVersion,
    minimumRuntime,
    schemaVersion,
    packageSpec,
    collectionRecord,
    saveMigrationPlan,
  };
}

export async function compilePublicPackage(sourceRoot, outputRoot, options = {}) {
  if (options.projectionAuthorityPath !== undefined) {
    throw new ValidationError([
      "projectionAuthorityPath: provisional development authority is forbidden for release packages",
    ]);
  }
  const resolvedSource = path.resolve(sourceRoot);
  const resolvedOutput = path.resolve(outputRoot);
  if (resolvedSource === resolvedOutput
      || resolvedOutput.startsWith(`${resolvedSource}${path.sep}`)
      || resolvedSource.startsWith(`${resolvedOutput}${path.sep}`)) {
    throw new ValidationError(["sourceRoot/outputRoot: package source and output trees must be disjoint"]);
  }
  if (options.launchPackageApprovalPath
      && isPathWithin(resolvedOutput, path.resolve(options.launchPackageApprovalPath))) {
    throw new ValidationError([
      "launchPackageApprovalPath: backstage approval cannot be placed in the package output",
    ]);
  }
  if (isDevelopmentOnlySigningKeyID(options.keyID)) {
    throw new ValidationError(["keyID: vertical-slice development keys are forbidden for release packages"]);
  }
  if (!signingIDPattern.test(options.keyID ?? "")) {
    throw new ValidationError(["keyID: stable kebab-case ID required"]);
  }
  const privateKey = requireP256PrivateKey(options.signingPrivateKey);
  const validated = await validateLaunchPackageSource(resolvedSource, options);
  const {
    files,
    sourceSnapshot,
    packageID,
    packageVersion,
    minimumRuntime,
    schemaVersion,
    packageSpec,
    saveMigrationPlan,
  } = validated;

  await mkdir(path.dirname(resolvedOutput), { recursive: true });
  const stagingRoot = await mkdtemp(path.join(path.dirname(resolvedOutput), `.${path.basename(resolvedOutput)}.staging-`));
  try {
    const records = [];
    for (const source of files) {
      const relative = path.relative(resolvedSource, source).split(path.sep).join("/");
      requireManifestPath(relative, `source.${relative}`);
      const destination = path.join(stagingRoot, ...relative.split("/"));
      await mkdir(path.dirname(destination), { recursive: true });
      await cp(source, destination, { force: true });
      records.push({ path: relative, ...await hashFile(destination) });
    }
    requireMatchingFileSnapshot(records, sourceSnapshot, "launch package");
    const manifest = signingManifest(
      {
        packageID,
        packageVersion,
        schemaVersion,
        minimumRuntime,
        ...saveMigrationPlan.manifestMetadata,
      },
      records,
      privateKey,
      options.keyID,
    );
    const manifestBytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8");
    if (packageSpec !== undefined) {
      requireInstalledByteBudget(records, manifestBytes.byteLength, packageSpec.maximumInstalledBytes);
    }
    await writeFile(path.join(stagingRoot, "package-manifest.json"), manifestBytes, { flag: "wx" });
    await verifyCompiledPackage(stagingRoot, createPublicKey(privateKey), options.keyID, packageSpec);
    await publishStagingAtomically(stagingRoot, resolvedOutput);
    return manifest;
  } catch (error) {
    await rm(stagingRoot, { recursive: true, force: true }).catch(() => {});
    throw error;
  }
}

/// Compiles one post-launch public deep-dive package. This path is deliberately
/// separate from `compilePublicPackage`: it cannot own any of the locked launch
/// chapters or reuse a launch package ID, and it cannot consume Phase 0's
/// aggregate approval as authority for newly authored content.
export async function compileFutureReleasePackage(sourceRoot, outputRoot, options = {}) {
  if (options.projectionAuthorityPath !== undefined) {
    throw new ValidationError([
      "projectionAuthorityPath: provisional development authority is forbidden for release packages",
    ]);
  }
  const resolvedSource = path.resolve(sourceRoot);
  const resolvedOutput = path.resolve(outputRoot);
  if (resolvedSource === resolvedOutput
      || resolvedOutput.startsWith(`${resolvedSource}${path.sep}`)
      || resolvedSource.startsWith(`${resolvedOutput}${path.sep}`)) {
    throw new ValidationError(["sourceRoot/outputRoot: package source and output trees must be disjoint"]);
  }
  if (options.futureReleaseApprovalPath
      && isPathWithin(resolvedOutput, path.resolve(options.futureReleaseApprovalPath))) {
    throw new ValidationError([
      "futureReleaseApprovalPath: backstage approval cannot be placed in the package output",
    ]);
  }
  for (const [optionName, controlPath] of [
    ["futureReleasePublicationPath", options.futureReleasePublicationPath],
    ["futureReleaseWorldAuthorityPath", options.futureReleaseWorldAuthorityPath],
  ]) {
    if (controlPath && isPathWithin(resolvedOutput, path.resolve(controlPath))) {
      throw new ValidationError([
        `${optionName}: backstage control cannot be placed in the package output`,
      ]);
    }
  }
  const validated = await validateFutureReleaseSource(resolvedSource, options);
  const {
    files,
    payload,
    release,
    publication,
    worldAuthoritySHA256,
    packageSpec,
    sourceSnapshot,
    saveMigrationPlan,
  } = validated;
  const packageID = payload.packageID;
  if (isDevelopmentOnlySigningKeyID(options.keyID)) {
    throw new ValidationError(["keyID: vertical-slice development keys are forbidden for release packages"]);
  }
  if (!signingIDPattern.test(packageID) || !signingIDPattern.test(options.keyID ?? "")) {
    throw new ValidationError(["packageID/keyID: stable kebab-case IDs required"]);
  }
  const privateKey = requireP256PrivateKey(options.signingPrivateKey);
  const schemaVersion = requireVersion(payload.schemaVersion, "contentPackage.schemaVersion");

  await mkdir(path.dirname(resolvedOutput), { recursive: true });
  const stagingRoot = await mkdtemp(path.join(
    path.dirname(resolvedOutput),
    `.${path.basename(resolvedOutput)}.staging-`,
  ));
  try {
    const records = [];
    for (const source of files) {
      const relative = path.relative(resolvedSource, source).split(path.sep).join("/");
      requireManifestPath(relative, `source.${relative}`);
      const destination = path.join(stagingRoot, ...relative.split("/"));
      await mkdir(path.dirname(destination), { recursive: true });
      await cp(source, destination, { force: true });
      records.push({ path: relative, ...await hashFile(destination) });
    }
    requireMatchingFileSnapshot(records, sourceSnapshot);
    const manifest = signingManifest(
      {
        packageID,
        packageVersion: packageSpec.version,
        schemaVersion,
        minimumRuntime: packageSpec.minimumRuntime,
        ...saveMigrationPlan.manifestMetadata,
      },
      records,
      privateKey,
      options.keyID,
    );
    const manifestBytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8");
    requireInstalledByteBudget(
      records,
      manifestBytes.byteLength,
      packageSpec.maximumInstalledBytes,
    );
    await writeFile(path.join(stagingRoot, "package-manifest.json"), manifestBytes, { flag: "wx" });
    await verifyCompiledPackage(
      stagingRoot,
      createPublicKey(privateKey),
      options.keyID,
      packageSpec,
    );
    await publishStagingAtomically(stagingRoot, resolvedOutput);
    return {
      manifest,
      release,
      publication,
      worldAuthoritySHA256,
      packageSpec,
    };
  } catch (error) {
    await rm(stagingRoot, { recursive: true, force: true }).catch(() => {});
    throw error;
  }
}

export async function verifyCompiledPackage(
  packageRoot,
  trustedPublicKey,
  expectedKeyID = undefined,
  expectedPackageSpec = undefined,
) {
  const manifest = await readJSON(path.join(packageRoot, "package-manifest.json"));
  verifyPackageManifest(manifest, trustedPublicKey, expectedKeyID);
  if (expectedPackageSpec !== undefined) {
    if (manifest.packageID !== expectedPackageSpec.id
        || !sameVersion(manifest.packageVersion, expectedPackageSpec.version)
        || !sameVersion(manifest.minimumRuntime, expectedPackageSpec.minimumRuntime)) {
      throw new ValidationError(["package manifest: metadata does not match the trusted package specification"]);
    }
    const manifestStat = await stat(path.join(packageRoot, "package-manifest.json"));
    requireInstalledByteBudget(manifest.files, manifestStat.size, expectedPackageSpec.maximumInstalledBytes);
  }
  const actualFiles = (await listFiles(packageRoot))
    .map((file) => path.relative(packageRoot, file).split(path.sep).join("/"))
    .filter((relative) => relative !== "package-manifest.json")
    .sort((left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right)));
  const declaredFiles = sortedRecords(manifest.files).map((record) => record.path);
  if (JSON.stringify(actualFiles) !== JSON.stringify(declaredFiles)) {
    throw new ValidationError(["package files: installed tree does not match signed manifest"]);
  }
  for (const record of manifest.files) {
    const installed = await hashFile(path.join(packageRoot, ...record.path.split("/")));
    if (installed.bytes !== record.bytes || installed.sha256 !== record.sha256) {
      throw new ValidationError([`package file '${record.path}': size or SHA-256 mismatch`]);
    }
  }
  return manifest;
}
