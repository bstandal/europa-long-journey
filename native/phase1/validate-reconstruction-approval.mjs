import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

export const reconstructionApprovalContract = Object.freeze({
  schemaVersion: 1,
  status: "APPROVED_BY_EDITOR_IN_CHIEF",
  authority: "editor-in-chief",
  role: "APPROVED_COMPOSITION_AND_ANATOMY_TARGET",
  target: Object.freeze({
    path: "native/design/phase1/harvest/reconstruction-master-draft-v2.png",
    sha256: "602c730450d7abd99fa88e877c6b74e2e0e2ad8bfd79bc57b6c7a50fcdc059be",
    pixelWidth: 862,
    pixelHeight: 1824,
  }),
  approvedScope: Object.freeze([
    "composition",
    "depthHierarchy",
    "historicalAnatomy",
    "singleSourceCausalLayout",
    "lightingDirection",
  ]),
  excludedScope: Object.freeze([
    "shippingPixels",
    "masterResolution",
    "cleanPlates",
    "stateVariants",
    "masks",
    "audio",
    "provenance",
  ]),
  shippingGate: Object.freeze({
    state: "PROHIBITED",
    requiresFullResolutionLayersAndMasks: true,
    requiresSeparateAssetApproval: true,
  }),
});

const exactKeys = (record, expected, location) => {
  assert.ok(record && typeof record === "object" && !Array.isArray(record), `${location} must be an object`);
  assert.deepEqual(
    Object.keys(record).sort(),
    [...expected].sort(),
    `${location} fields drifted`,
  );
};

const validateLockedRecord = (record, repositoryRoot) => {
  exactKeys(record, [
    "schemaVersion",
    "status",
    "authority",
    "role",
    "target",
    "approvedScope",
    "excludedScope",
    "shippingGate",
  ], "reconstruction approval");
  assert.equal(record.schemaVersion, reconstructionApprovalContract.schemaVersion, "reconstruction approval schema drifted");
  assert.equal(record.status, reconstructionApprovalContract.status, "reconstruction approval status drifted");
  assert.equal(record.authority, reconstructionApprovalContract.authority, "reconstruction approval authority drifted");
  assert.equal(record.role, reconstructionApprovalContract.role, "reconstruction approval role drifted");

  exactKeys(record.target, ["path", "sha256", "pixelWidth", "pixelHeight"], "reconstruction approval target");
  assert.equal(record.target.path, reconstructionApprovalContract.target.path, "reconstruction target path drifted");
  assert.equal(record.target.sha256, reconstructionApprovalContract.target.sha256, "reconstruction target SHA-256 drifted");
  assert.equal(record.target.pixelWidth, reconstructionApprovalContract.target.pixelWidth, "reconstruction target width drifted");
  assert.equal(record.target.pixelHeight, reconstructionApprovalContract.target.pixelHeight, "reconstruction target height drifted");

  assert.deepEqual(record.approvedScope, reconstructionApprovalContract.approvedScope, "reconstruction approved scope drifted");
  assert.deepEqual(record.excludedScope, reconstructionApprovalContract.excludedScope, "reconstruction excluded scope drifted");
  assert.equal(new Set(record.approvedScope).size, record.approvedScope.length, "reconstruction approved scope contains duplicates");
  assert.equal(new Set(record.excludedScope).size, record.excludedScope.length, "reconstruction excluded scope contains duplicates");
  assert.ok(
    record.approvedScope.every((scope) => !record.excludedScope.includes(scope)),
    "reconstruction approved and excluded scopes overlap",
  );

  exactKeys(record.shippingGate, [
    "state",
    "requiresFullResolutionLayersAndMasks",
    "requiresSeparateAssetApproval",
  ], "reconstruction shipping gate");
  assert.equal(record.shippingGate.state, reconstructionApprovalContract.shippingGate.state, "reconstruction shipping state drifted");
  assert.equal(
    record.shippingGate.requiresFullResolutionLayersAndMasks,
    true,
    "reconstruction cannot ship without full-resolution layers and masks",
  );
  assert.equal(
    record.shippingGate.requiresSeparateAssetApproval,
    true,
    "reconstruction cannot ship without separate asset approval",
  );

  const resolvedTargetPath = path.resolve(repositoryRoot, record.target.path);
  const expectedTargetPath = path.resolve(repositoryRoot, reconstructionApprovalContract.target.path);
  assert.equal(resolvedTargetPath, expectedTargetPath, "reconstruction target resolved to an unapproved path");
  const allowedDesignRoot = `${path.resolve(repositoryRoot, "native/design/phase1/harvest")}${path.sep}`;
  assert.ok(resolvedTargetPath.startsWith(allowedDesignRoot), "reconstruction target escaped the Harvest design tree");
  return resolvedTargetPath;
};

const validateLockedImage = (visualBytes) => {
  assert.ok(Buffer.isBuffer(visualBytes), "reconstruction target bytes must be a Buffer");
  assert.ok(visualBytes.length >= 24, "reconstruction target is too short to be a PNG");
  assert.deepEqual(
    [...visualBytes.subarray(0, 8)],
    [137, 80, 78, 71, 13, 10, 26, 10],
    "reconstruction target is not a PNG",
  );
  assert.equal(
    visualBytes.readUInt32BE(16),
    reconstructionApprovalContract.target.pixelWidth,
    "reconstruction target image width drifted",
  );
  assert.equal(
    visualBytes.readUInt32BE(20),
    reconstructionApprovalContract.target.pixelHeight,
    "reconstruction target image height drifted",
  );
  assert.equal(
    createHash("sha256").update(visualBytes).digest("hex"),
    reconstructionApprovalContract.target.sha256,
    "reconstruction target bytes drifted",
  );
};

export function validateReconstructionApprovalRecord(record, visualBytes, repositoryRoot) {
  assert.ok(path.isAbsolute(repositoryRoot), "repositoryRoot must be absolute");
  validateLockedRecord(record, repositoryRoot);
  validateLockedImage(visualBytes);
  return record;
}

export async function validateReconstructionApproval({ repositoryRoot, approvalPath }) {
  assert.ok(path.isAbsolute(repositoryRoot), "repositoryRoot must be absolute");
  const resolvedApprovalPath = approvalPath
    ?? path.join(repositoryRoot, "native/design/phase1/harvest/reconstruction-approval.json");
  const record = JSON.parse(await readFile(resolvedApprovalPath, "utf8"));
  const resolvedTargetPath = validateLockedRecord(record, repositoryRoot);
  const visualBytes = await readFile(resolvedTargetPath);
  validateLockedImage(visualBytes);
  return record;
}
