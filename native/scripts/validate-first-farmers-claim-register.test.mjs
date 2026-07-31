import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { validateFirstFarmersClaimRegister } from "./validate-first-farmers-claim-register.mjs";
import { validatePublicDocument, ValidationError } from "../tooling/src/validate.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const registerPath = path.join(
  repositoryRoot,
  "native/content/backstage/first-farmers/claim-register-v1.json",
);
const draftPath = path.join(
  repositoryRoot,
  "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json",
);
const decisionQueuePath = path.join(
  repositoryRoot,
  "native/phase2/editor-review/first-farmers/first-farmers-editor-decision-queue-v1.md",
);

const [registerSource, draftSource, decisionQueueSource] = await Promise.all([
  readFile(registerPath, "utf8"),
  readFile(draftPath, "utf8"),
  readFile(decisionQueuePath, "utf8"),
]);
const sourceRegister = JSON.parse(registerSource);
const sourceDraft = JSON.parse(draftSource);

function clone(value) {
  return structuredClone(value);
}

test("validates the sealed First Farmers register and covers every narrative segment", async () => {
  const result = await validateFirstFarmersClaimRegister({ repositoryRoot });

  assert.equal(result.registryPath, registerPath);
  assert.equal(result.sourceCount, 24);
  assert.equal(result.findingCount, 15);
  assert.equal(result.coveredSegmentCount, 37);
  assert.deepEqual(result.summary, sourceRegister.summary);
  assert.equal(result.summary.closedDefects.F2, 2);
  assert.equal(result.summary.closedDefects.F3, 2);
  assert.equal(result.summary.closedDefects.F5, 2);
  assert.ok(Object.values(result.summary.openDefects).every((count) => count === 0));
});

test("records only the two narrative-writer repairs as closed", () => {
  const resolved = sourceRegister.findings.filter((finding) => finding.resolution?.status === "CLOSED");

  assert.deepEqual(resolved.map((finding) => finding.id), [
    "ff-finding-c7000-subfloor-burial",
    "ff-finding-aegean-sailcloth",
  ]);
  assert.ok(resolved.every((finding) => finding.resolution.appliedBy === "NARRATIVE_WRITER"));
  assert.ok(resolved.every((finding) => finding.resolution.editorialFrameChanged === false));
});

test("records all four editor decisions as closed and applied backstage", () => {
  const editorDecisions = sourceRegister.findings
    .filter((finding) => finding.result === "EDITOR_DECISION");

  assert.equal(editorDecisions.length, 4);
  assert.ok(editorDecisions.every((finding) => finding.editorDecision?.status === "CLOSED"));
  assert.ok(editorDecisions.every((finding) =>
    finding.editorDecision?.decidedBy === "EDITOR_IN_CHIEF"));
  assert.ok(editorDecisions.every((finding) =>
    finding.editorDecision?.narrativeRepair?.status === "APPLIED"));
  assert.match(
    decisionQueueSource,
    /BACKSTAGE_EDITOR_DECISIONS_APPLIED_FOR_CHAPTER_01_REVIEW/u,
  );
  for (const finding of editorDecisions) assert.ok(decisionQueueSource.includes(finding.id));
});

test("rejects a register when the sealed source draft hash drifts", async () => {
  const register = clone(sourceRegister);
  register.sourceDraft.sha256 = "0".repeat(64);

  await assert.rejects(
    validateFirstFarmersClaimRegister({ repositoryRoot, register }),
    /sourceDraft\.sha256: expected [a-f0-9]{64}/u,
  );
});

test("rejects verifier-written public prose anywhere in the register", async () => {
  const register = clone(sourceRegister);
  register.verification.replacementProse = "A verifier-authored replacement.";

  await assert.rejects(
    validateFirstFarmersClaimRegister({ repositoryRoot, register, draft: sourceDraft }),
    /verifier cannot write public prose/u,
  );
});

test("rejects an uncovered public narrative segment", async () => {
  const register = clone(sourceRegister);
  for (const finding of register.findings) {
    finding.locations = finding.locations.filter((location) => location.segmentID !== "ff-river-world-02");
  }

  await assert.rejects(
    validateFirstFarmersClaimRegister({ repositoryRoot, register, draft: sourceDraft }),
    /uncovered narrative segments: ff-river-world-02/u,
  );
});

test("rejects a claim locator when its verbatim draft text drifts", async () => {
  const register = clone(sourceRegister);
  const location = register.findings
    .flatMap((finding) => finding.locations)
    .find((candidate) => candidate.segmentID === "ff-river-world-01");
  location.exactClaim = "A sentence absent from the sealed draft.";

  await assert.rejects(
    validateFirstFarmersClaimRegister({ repositoryRoot, register, draft: sourceDraft }),
    /exactClaim: not found verbatim in draft field/u,
  );
});

test("rejects summary totals that no longer match the findings", async () => {
  const register = clone(sourceRegister);
  register.summary.PASS += 1;

  await assert.rejects(
    validateFirstFarmersClaimRegister({ repositoryRoot, register, draft: sourceDraft }),
    /register\.summary: result or defect totals drifted/u,
  );
});

test("rejects a narrative-writer closure of an editor decision", async () => {
  const register = clone(sourceRegister);
  const finding = register.findings.find((candidate) => candidate.result === "EDITOR_DECISION");
  finding.resolution = {
    status: "CLOSED",
    appliedAt: "2026-07-24",
    appliedBy: "NARRATIVE_WRITER",
    repairKind: "EDITOR_DECISION",
    originalClaim: finding.locations[0].exactClaim,
    editorialFrameChanged: false,
  };

  await assert.rejects(
    validateFirstFarmersClaimRegister({ repositoryRoot, register, draft: sourceDraft }),
    /only NARROW, REPLACE or REMOVE may be closed/u,
  );
});

test("rejects an editor decision attributed to anyone but the editor-in-chief", async () => {
  const register = clone(sourceRegister);
  const finding = register.findings.find((candidate) => candidate.editorDecision);
  finding.editorDecision.decidedBy = "VERIFIER";

  await assert.rejects(
    validateFirstFarmersClaimRegister({ repositoryRoot, register, draft: sourceDraft }),
    /decidedBy: EDITOR_IN_CHIEF required/u,
  );
});

test("rejects a repair record that claims to alter the editorial frame", async () => {
  const register = clone(sourceRegister);
  const finding = register.findings.find((candidate) => candidate.resolution?.status === "CLOSED");
  finding.resolution.editorialFrameChanged = true;

  await assert.rejects(
    validateFirstFarmersClaimRegister({ repositoryRoot, register, draft: sourceDraft }),
    /editorialFrameChanged: must remain false/u,
  );
});

test("the public-content firewall rejects the backstage claim register", () => {
  assert.throws(
    () => validatePublicDocument(sourceRegister, "chapters/claim-register-v1.json"),
    (error) => {
      assert.ok(error instanceof ValidationError);
      assert.match(error.message, /forbidden backstage\/research field/u);
      assert.match(
        error.message,
        /expected CollectionManifest, ContentPackagePayload, AppShellSpec or Release/u,
      );
      return true;
    },
  );
});
