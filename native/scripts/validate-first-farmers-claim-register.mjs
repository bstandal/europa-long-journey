#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const allowedResults = new Set([
  "PASS",
  "NARROW",
  "REPLACE",
  "REMOVE",
  "EDITOR_DECISION",
]);

const allowedDefects = new Set(["F1", "F2", "F3", "F4", "F5", "F6", "F7"]);
const resolvableResults = new Set(["NARROW", "REPLACE", "REMOVE"]);
const stableIDPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
const sha256Pattern = /^[a-f0-9]{64}$/u;

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

function requireNonEmptyString(value, location) {
  requireCondition(typeof value === "string" && value.trim().length > 0, `${location}: non-empty string required`);
}

function requireExactKeys(value, required, optional, location) {
  requireCondition(value && typeof value === "object" && !Array.isArray(value), `${location}: object required`);
  const allowed = new Set([...required, ...optional]);
  for (const key of required) requireCondition(Object.hasOwn(value, key), `${location}.${key}: required`);
  for (const key of Object.keys(value)) requireCondition(allowed.has(key), `${location}.${key}: unknown field`);
}

function resolveJSONPointer(value, pointer, location) {
  requireCondition(typeof pointer === "string" && pointer.startsWith("/"), `${location}: JSON pointer required`);
  let current = value;
  for (const encoded of pointer.slice(1).split("/")) {
    const key = encoded.replaceAll("~1", "/").replaceAll("~0", "~");
    requireCondition(current !== null && typeof current === "object" && Object.hasOwn(current, key), `${location}: missing '${key}'`);
    current = current[key];
  }
  return current;
}

function canonicalJSON(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJSON(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function assertNoProhibitedPublicMutationFields(value, location = "register") {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoProhibitedPublicMutationFields(item, `${location}[${index}]`));
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    requireCondition(!["replacementProse", "publicProse", "rewrittenText"].includes(key), `${location}.${key}: verifier cannot write public prose`);
    assertNoProhibitedPublicMutationFields(child, `${location}.${key}`);
  }
}

function findBeat(draft, beatID) {
  for (const arc of draft.arcs ?? []) {
    const beat = (arc.beats ?? []).find((candidate) => candidate.beatID === beatID);
    if (beat) return beat;
  }
  return undefined;
}

function draftSegmentIDs(draft) {
  return (draft.arcs ?? []).flatMap((arc) => arc.beats ?? [])
    .flatMap((beat) => beat.narrative?.segments ?? [])
    .map((segment) => segment.id);
}

function computedSummary(findings) {
  const output = {
    PASS: 0,
    NARROW: 0,
    REPLACE: 0,
    REMOVE: 0,
    EDITOR_DECISION: 0,
    openDefects: Object.fromEntries([...allowedDefects].map((code) => [code, 0])),
    closedDefects: Object.fromEntries([...allowedDefects].map((code) => [code, 0])),
  };
  for (const finding of findings) {
    output[finding.result] += 1;
    if (finding.defectCode !== null) {
      const bucket = finding.resolution?.status === "CLOSED"
        || finding.editorDecision?.status === "CLOSED"
        ? "closedDefects"
        : "openDefects";
      output[bucket][finding.defectCode] += 1;
    }
  }
  return output;
}

export async function validateFirstFarmersClaimRegister({
  repositoryRoot,
  register,
  draft,
} = {}) {
  const inferredRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
  const root = repositoryRoot ?? inferredRoot;
  const registryPath = path.join(root, "native/content/backstage/first-farmers/claim-register-v1.json");
  const loadedRegister = register ?? JSON.parse(await readFile(registryPath, "utf8"));
  const draftPath = path.resolve(root, loadedRegister.sourceDraft?.path ?? "");
  const draftBytes = draft === undefined ? await readFile(draftPath) : null;
  const loadedDraft = draft ?? JSON.parse(draftBytes.toString("utf8"));

  requireCondition(path.relative(root, registryPath).split(path.sep).includes("backstage"), "claim register must remain below backstage/");
  requireExactKeys(loadedRegister, [
    "schemaVersion",
    "registryID",
    "chapterID",
    "locale",
    "shippingBoundary",
    "sourceDraft",
    "verification",
    "sources",
    "findings",
    "summary",
  ], [], "register");
  assertNoProhibitedPublicMutationFields(loadedRegister);
  requireCondition(loadedRegister.schemaVersion === 1, "register.schemaVersion: expected 1");
  requireCondition(loadedRegister.registryID === "first-farmers-claim-register-v1", "register.registryID: locked ID drifted");
  requireCondition(loadedRegister.chapterID === "first-farmers", "register.chapterID: wrong chapter");
  requireCondition(loadedRegister.locale === "en", "register.locale: English launch register required");
  requireCondition(loadedRegister.shippingBoundary === "BACKSTAGE_ONLY_DO_NOT_PACKAGE", "register.shippingBoundary: shipping exclusion must remain explicit");
  requireExactKeys(loadedRegister.sourceDraft, ["path", "sha256"], [], "register.sourceDraft");
  requireCondition(loadedDraft.chapterID === loadedRegister.chapterID, "register.sourceDraft: chapter mismatch");
  requireCondition(loadedRegister.sourceDraft.path === "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json", "register.sourceDraft.path: locked draft path drifted");
  requireCondition(sha256Pattern.test(loadedRegister.sourceDraft.sha256), "register.sourceDraft.sha256: lowercase SHA-256 required");
  if (draftBytes !== null) {
    const actualSHA256 = createHash("sha256").update(draftBytes).digest("hex");
    requireCondition(actualSHA256 === loadedRegister.sourceDraft.sha256, `register.sourceDraft.sha256: expected ${actualSHA256}`);
  }

  requireExactKeys(loadedRegister.verification, [
    "verifiedAt",
    "publicMutationAuthorized",
    "verifierMayWritePublicProse",
    "editorialContractRemainsAuthoritative",
    "allowedResults",
    "allowedDefects",
  ], [], "register.verification");
  requireCondition(/^\d{4}-\d{2}-\d{2}$/u.test(loadedRegister.verification.verifiedAt), "register.verification.verifiedAt: YYYY-MM-DD required");
  requireCondition(loadedRegister.verification.publicMutationAuthorized === false, "register.verification.publicMutationAuthorized: must remain false");
  requireCondition(loadedRegister.verification.verifierMayWritePublicProse === false, "register.verification.verifierMayWritePublicProse: must remain false");
  requireCondition(loadedRegister.verification.editorialContractRemainsAuthoritative === true, "register.verification.editorialContractRemainsAuthoritative: must remain true");
  requireCondition(canonicalJSON(loadedRegister.verification.allowedResults) === canonicalJSON([...allowedResults]), "register.verification.allowedResults: closed result vocabulary drifted");
  requireCondition(canonicalJSON(loadedRegister.verification.allowedDefects) === canonicalJSON([...allowedDefects]), "register.verification.allowedDefects: closed F1–F7 vocabulary drifted");

  requireCondition(Array.isArray(loadedRegister.sources) && loadedRegister.sources.length > 0, "register.sources: non-empty array required");
  const sourceIDs = new Set();
  for (const [index, source] of loadedRegister.sources.entries()) {
    const location = `register.sources[${index}]`;
    requireExactKeys(source, ["id", "kind", "citation", "url", "usedFor"], ["doi"], location);
    requireCondition(stableIDPattern.test(source.id), `${location}.id: stable kebab-case ID required`);
    requireCondition(!sourceIDs.has(source.id), `${location}.id: duplicate '${source.id}'`);
    sourceIDs.add(source.id);
    requireNonEmptyString(source.kind, `${location}.kind`);
    requireNonEmptyString(source.citation, `${location}.citation`);
    requireCondition(/^https:\/\//u.test(source.url), `${location}.url: HTTPS source URL required`);
    requireNonEmptyString(source.usedFor, `${location}.usedFor`);
    if (source.doi !== undefined) requireNonEmptyString(source.doi, `${location}.doi`);
  }

  requireCondition(Array.isArray(loadedRegister.findings) && loadedRegister.findings.length > 0, "register.findings: non-empty array required");
  const findingIDs = new Set();
  const coveredSegments = new Set();
  for (const [index, finding] of loadedRegister.findings.entries()) {
    const location = `register.findings[${index}]`;
    requireExactKeys(finding, [
      "id",
      "result",
      "defectCode",
      "locations",
      "sourceIDs",
      "sourceBasis",
      "factualConflict",
      "smallestCorrection",
    ], ["resolution", "editorDecision"], location);
    requireCondition(stableIDPattern.test(finding.id), `${location}.id: stable kebab-case ID required`);
    requireCondition(!findingIDs.has(finding.id), `${location}.id: duplicate '${finding.id}'`);
    findingIDs.add(finding.id);
    requireCondition(allowedResults.has(finding.result), `${location}.result: closed verifier result required`);
    requireCondition(Array.isArray(finding.locations) && finding.locations.length > 0, `${location}.locations: at least one exact location required`);
    requireCondition(Array.isArray(finding.sourceIDs) && finding.sourceIDs.length > 0, `${location}.sourceIDs: at least one source required`);
    requireNonEmptyString(finding.sourceBasis, `${location}.sourceBasis`);
    for (const sourceID of finding.sourceIDs) requireCondition(sourceIDs.has(sourceID), `${location}.sourceIDs: unknown source '${sourceID}'`);

    if (finding.result === "PASS") {
      requireCondition(finding.defectCode === null, `${location}.defectCode: PASS cannot carry a defect`);
      requireCondition(finding.factualConflict === null, `${location}.factualConflict: PASS cannot carry a conflict`);
      requireCondition(finding.smallestCorrection === null, `${location}.smallestCorrection: PASS cannot prescribe a correction`);
      requireCondition(finding.resolution === undefined, `${location}.resolution: PASS cannot carry a repair resolution`);
      requireCondition(finding.editorDecision === undefined, `${location}.editorDecision: PASS cannot carry an editor decision`);
    } else {
      requireCondition(allowedDefects.has(finding.defectCode), `${location}.defectCode: F1–F7 required`);
      requireNonEmptyString(finding.factualConflict, `${location}.factualConflict`);
      requireNonEmptyString(finding.smallestCorrection, `${location}.smallestCorrection`);
    }

    if (finding.resolution !== undefined) {
      requireCondition(resolvableResults.has(finding.result), `${location}.resolution: only NARROW, REPLACE or REMOVE may be closed by the narrative writer`);
      requireExactKeys(finding.resolution, [
        "status",
        "appliedAt",
        "appliedBy",
        "repairKind",
        "originalClaim",
        "editorialFrameChanged",
      ], [], `${location}.resolution`);
      requireCondition(finding.resolution.status === "CLOSED", `${location}.resolution.status: CLOSED required`);
      requireCondition(/^\d{4}-\d{2}-\d{2}$/u.test(finding.resolution.appliedAt), `${location}.resolution.appliedAt: YYYY-MM-DD required`);
      requireCondition(finding.resolution.appliedBy === "NARRATIVE_WRITER", `${location}.resolution.appliedBy: NARRATIVE_WRITER required`);
      requireCondition(finding.resolution.repairKind === finding.result, `${location}.resolution.repairKind: must equal finding result`);
      requireNonEmptyString(finding.resolution.originalClaim, `${location}.resolution.originalClaim`);
      requireCondition(finding.resolution.editorialFrameChanged === false, `${location}.resolution.editorialFrameChanged: must remain false`);
    }

    if (finding.editorDecision !== undefined) {
      requireCondition(finding.result === "EDITOR_DECISION", `${location}.editorDecision: requires an EDITOR_DECISION finding`);
      requireCondition(finding.resolution === undefined, `${location}.editorDecision: cannot coexist with a verifier repair resolution`);
      requireExactKeys(finding.editorDecision, [
        "status",
        "decidedAt",
        "decidedBy",
        "decision",
        "narrativeRepair",
      ], [], `${location}.editorDecision`);
      requireCondition(finding.editorDecision.status === "CLOSED", `${location}.editorDecision.status: CLOSED required`);
      requireCondition(/^\d{4}-\d{2}-\d{2}$/u.test(finding.editorDecision.decidedAt), `${location}.editorDecision.decidedAt: YYYY-MM-DD required`);
      requireCondition(finding.editorDecision.decidedBy === "EDITOR_IN_CHIEF", `${location}.editorDecision.decidedBy: EDITOR_IN_CHIEF required`);
      requireCondition(finding.editorDecision.decision === "APPROVE_SMALLEST_CORRECTION", `${location}.editorDecision.decision: approved smallest correction required`);
      requireExactKeys(finding.editorDecision.narrativeRepair, [
        "status",
        "appliedAt",
        "appliedBy",
        "editorialFrameChanged",
      ], [], `${location}.editorDecision.narrativeRepair`);
      requireCondition(finding.editorDecision.narrativeRepair.status === "APPLIED", `${location}.editorDecision.narrativeRepair.status: APPLIED required`);
      requireCondition(/^\d{4}-\d{2}-\d{2}$/u.test(finding.editorDecision.narrativeRepair.appliedAt), `${location}.editorDecision.narrativeRepair.appliedAt: YYYY-MM-DD required`);
      requireCondition(finding.editorDecision.narrativeRepair.appliedBy === "NARRATIVE_WRITER", `${location}.editorDecision.narrativeRepair.appliedBy: NARRATIVE_WRITER required`);
      requireCondition(finding.editorDecision.narrativeRepair.editorialFrameChanged === false, `${location}.editorDecision.narrativeRepair.editorialFrameChanged: must remain false`);
    }

    for (const [locationIndex, claimLocation] of finding.locations.entries()) {
      const claimPath = `${location}.locations[${locationIndex}]`;
      requireExactKeys(claimLocation, ["beatID", "fieldPath", "exactClaim"], ["segmentID", "exactValue"], claimPath);
      requireNonEmptyString(claimLocation.beatID, `${claimPath}.beatID`);
      requireNonEmptyString(claimLocation.fieldPath, `${claimPath}.fieldPath`);
      requireNonEmptyString(claimLocation.exactClaim, `${claimPath}.exactClaim`);
      const beat = findBeat(loadedDraft, claimLocation.beatID);
      requireCondition(beat !== undefined, `${claimPath}.beatID: unknown beat '${claimLocation.beatID}'`);
      const actualValue = resolveJSONPointer(beat, claimLocation.fieldPath, `${claimPath}.fieldPath`);
      if (Object.hasOwn(claimLocation, "exactValue")) {
        requireCondition(canonicalJSON(actualValue) === canonicalJSON(claimLocation.exactValue), `${claimPath}.exactValue: draft value drifted`);
      } else {
        requireCondition(typeof actualValue === "string", `${claimPath}: exactClaim requires a string draft field`);
      }
      if (typeof actualValue === "string") {
        requireCondition(actualValue.includes(claimLocation.exactClaim), `${claimPath}.exactClaim: not found verbatim in draft field`);
      }
      if (claimLocation.segmentID !== undefined) {
        const segment = (beat.narrative?.segments ?? []).find((candidate) => candidate.id === claimLocation.segmentID);
        requireCondition(segment !== undefined, `${claimPath}.segmentID: unknown segment '${claimLocation.segmentID}'`);
        requireCondition(actualValue === segment.text, `${claimPath}.fieldPath: does not resolve to segment '${claimLocation.segmentID}'`);
        coveredSegments.add(claimLocation.segmentID);
      }
    }
  }

  const expectedSegments = draftSegmentIDs(loadedDraft);
  requireCondition(new Set(expectedSegments).size === expectedSegments.length, "source draft contains duplicate narrative segment IDs");
  const missingSegments = expectedSegments.filter((segmentID) => !coveredSegments.has(segmentID));
  requireCondition(missingSegments.length === 0, `register.findings: uncovered narrative segments: ${missingSegments.join(", ")}`);
  requireCondition(canonicalJSON(loadedRegister.summary) === canonicalJSON(computedSummary(loadedRegister.findings)), "register.summary: result or defect totals drifted");

  return {
    registryPath,
    sourceCount: loadedRegister.sources.length,
    findingCount: loadedRegister.findings.length,
    coveredSegmentCount: coveredSegments.size,
    summary: loadedRegister.summary,
  };
}

async function main() {
  const result = await validateFirstFarmersClaimRegister();
  process.stdout.write(`Validated ${result.findingCount} First Farmers findings against ${result.coveredSegmentCount} public narrative segments; register remains backstage-only.\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
  });
}
