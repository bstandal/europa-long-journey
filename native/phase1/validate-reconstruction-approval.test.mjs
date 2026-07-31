import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  reconstructionApprovalContract,
  validateReconstructionApproval,
  validateReconstructionApprovalRecord,
} from "./validate-reconstruction-approval.mjs";

const phase1Root = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.dirname(path.dirname(phase1Root));
const approvalPath = path.join(
  repositoryRoot,
  "native/design/phase1/harvest/reconstruction-approval.json",
);
const targetPath = path.join(repositoryRoot, reconstructionApprovalContract.target.path);
const clone = (value) => structuredClone(value);

const fixtures = async () => ({
  record: JSON.parse(await readFile(approvalPath, "utf8")),
  visualBytes: await readFile(targetPath),
});

test("accepts only the editor-approved reconstruction target", async () => {
  const record = await validateReconstructionApproval({ repositoryRoot, approvalPath });
  assert.equal(record.status, "APPROVED_BY_EDITOR_IN_CHIEF");
  assert.equal(record.shippingGate.state, "PROHIBITED");
});

test("rejects approval status, role, path and scope drift", async () => {
  const { record, visualBytes } = await fixtures();
  for (const mutate of [
    (value) => { value.status = "DRAFT"; },
    (value) => { value.role = "SHIPPING_ASSET"; },
    (value) => { value.target.path = "native/design/phase1/harvest/reconstruction-master-draft-v1.png"; },
    (value) => { value.target.sha256 = "0".repeat(64); },
    (value) => { value.target.pixelWidth = 861; },
    (value) => { value.target.pixelHeight = 1823; },
    (value) => { value.approvedScope.pop(); },
    (value) => { value.excludedScope = value.excludedScope.filter((scope) => scope !== "provenance"); },
  ]) {
    const changed = clone(record);
    mutate(changed);
    assert.throws(
      () => validateReconstructionApprovalRecord(changed, visualBytes, repositoryRoot),
      /drifted/,
    );
  }
});

test("keeps shipping prohibited behind both production approvals", async () => {
  const { record, visualBytes } = await fixtures();
  const allowed = clone(record);
  allowed.shippingGate.state = "APPROVED";
  assert.throws(
    () => validateReconstructionApprovalRecord(allowed, visualBytes, repositoryRoot),
    /shipping state drifted/,
  );

  const missingLayers = clone(record);
  missingLayers.shippingGate.requiresFullResolutionLayersAndMasks = false;
  assert.throws(
    () => validateReconstructionApprovalRecord(missingLayers, visualBytes, repositoryRoot),
    /cannot ship without full-resolution layers and masks/,
  );

  const missingAssetApproval = clone(record);
  missingAssetApproval.shippingGate.requiresSeparateAssetApproval = false;
  assert.throws(
    () => validateReconstructionApprovalRecord(missingAssetApproval, visualBytes, repositoryRoot),
    /cannot ship without separate asset approval/,
  );
});

test("rejects changed image dimensions and bytes", async () => {
  const { record, visualBytes } = await fixtures();
  const wrongDimensions = Buffer.from(visualBytes);
  wrongDimensions.writeUInt32BE(861, 16);
  assert.throws(
    () => validateReconstructionApprovalRecord(record, wrongDimensions, repositoryRoot),
    /image width drifted/,
  );

  const changedBytes = Buffer.from(visualBytes);
  changedBytes[changedBytes.length - 1] ^= 1;
  assert.throws(
    () => validateReconstructionApprovalRecord(record, changedBytes, repositoryRoot),
    /target bytes drifted/,
  );
});
