#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const root = path.dirname(fileURLToPath(import.meta.url));
const editorialFileNames = [
  "arc-matrix.json",
  "authored-interaction-effects-01-12.json",
  "authored-interaction-effects-13-24.json",
  "chapter-catalog.json",
  "chapter-contracts.json",
  "interaction-mapping.json",
  "world-traces.json",
];

function argument(name) {
  const prefix = `--${name}=`;
  return process.argv.find((value) => value.startsWith(prefix))?.slice(prefix.length);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function serialise(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function contractByID(contracts, contentID) {
  const contract = contracts.contracts.find((candidate) => candidate.contentID === contentID);
  assert(contract, `Missing contract '${contentID}'`);
  return contract;
}

function catalogChapterByID(catalog, contentID) {
  const chapter = catalog.chapters.find((candidate) => candidate.contentID === contentID);
  assert(chapter, `Missing catalog chapter '${contentID}'`);
  return chapter;
}

function requirePendingState(documents) {
  const { catalog, contracts, matrix, ledgers, interactions, world, approval } = documents;
  assert(catalog.status === "CANONICAL_PHASE_0_DRAFT", "Catalog is not in its pending state");
  assert(contracts.status === "DRAFT_PENDING_EDITOR_IN_CHIEF", "Contracts are not pending");
  assert(matrix.status === "DRAFT_PENDING_EDITOR_IN_CHIEF", "Arc matrix is not pending");
  assert(interactions.status === "DRAFT", "Interaction map is not pending");
  assert(world.status === "DRAFT", "World model is not pending");
  assert(approval.status === "PENDING_EDITOR_IN_CHIEF", "Approval record is not pending");
  assert(contracts.contracts.every(({ editorApproval }) => editorApproval === "DRAFT_PENDING"), "A contract has already moved");
  assert(matrix.chapters.every(({ editorApproval }) => editorApproval === "DRAFT_PENDING"), "An arc chapter has already moved");
  assert(ledgers.every(({ status }) => status === "AUTHORED_PENDING_EDITOR_APPROVAL"), "An authored ledger has already moved");
}

function applyRecommendedResolutions(catalog, contracts) {
  const farmers = contractByID(contracts, "first-farmers");
  assert(
    farmers.ending.consequence === "No text preserves the languages of the people who made it so.",
    "The First Farmers ending changed after editor review",
  );
  farmers.ending.consequence = "Fields, stores and inherited settlements had fixed Europe’s growing households to ground that the steppe expansion would seize and reorder.";

  const bronze = contractByID(contracts, "bronze-europe");
  assert(
    bronze.thesis === "Metal, ships and sacred power joined Europe to the older worlds of Egypt and the East.",
    "Bronze Europe thesis changed after editor review",
  );
  bronze.thesis = "Drawing on older eastern networks, Europeans mastered metal and sea, forging distinct worlds of craft, sacred power, warrior courage and heroic memory.";
  catalogChapterByID(catalog, "bronze-europe").lockedThesis = bronze.thesis;

  const cross = contractByID(contracts, "empire-takes-cross");
  assert(cross.ending.title === "The Roman centre now faces east", "The Empire Takes the Cross ending changed after editor review");
  cross.ending.title = "The Roman inheritance no longer depended on one western emperor.";
  cross.ending.consequence = "Justinian’s empire preserved Roman law and Christian kingship from Constantinople. In the former western provinces, bishops, monasteries and kings now carried that inheritance through institutions able to survive without one imperial centre.";

  const liberties = contractByID(contracts, "empire-many-liberties");
  assert(liberties.ending.title === "Liberty Has Learned to Live Inside Order", "The Empire of Many Liberties ending changed after editor review");
  liberties.ending.title = "The Empire ended; its jurisdictions remained.";
  liberties.ending.consequence = "When Francis II laid down the imperial crown in 1806, the Empire vanished as a polity. Its cities, territories, courts and archives preserved the habits of negotiated rule through which unequal powers had acted together for centuries.";
  liberties.handoff = "To see what that capacity had defended, the Journey now follows Europe’s southern and eastern frontiers across the centuries before 1806.";
}

async function main() {
  assert(
    process.argv.includes("--apply-recommended-resolutions"),
    "Explicit --apply-recommended-resolutions authority is required",
  );
  const decisionReference = argument("decision-reference");
  const approvedAt = argument("approved-at");
  assert(typeof decisionReference === "string" && decisionReference.length >= 12, "A durable decision reference is required");
  assert(
    typeof approvedAt === "string"
      && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(approvedAt)
      && Number.isFinite(Date.parse(approvedAt)),
    "A UTC ISO-8601 approval time is required",
  );

  const readJSON = (name) => readFile(path.join(root, name), "utf8").then(JSON.parse);
  const [catalog, contracts, matrix, ledgerEarly, ledgerLate, interactions, world, approval] = await Promise.all([
    readJSON("chapter-catalog.json"),
    readJSON("chapter-contracts.json"),
    readJSON("arc-matrix.json"),
    readJSON("authored-interaction-effects-01-12.json"),
    readJSON("authored-interaction-effects-13-24.json"),
    readJSON("interaction-mapping.json"),
    readJSON("world-traces.json"),
    readJSON("editor-approval.json"),
  ]);
  const ledgers = [ledgerEarly, ledgerLate];
  requirePendingState({ catalog, contracts, matrix, ledgers, interactions, world, approval });
  applyRecommendedResolutions(catalog, contracts);

  catalog.status = "CANONICAL_PHASE_0_APPROVED";
  for (const chapter of catalog.chapters) {
    chapter.thesisStatus = "LOCKED_NATIVE_CONTRACT_APPROVED";
  }
  contracts.status = "APPROVED_BY_EDITOR_IN_CHIEF";
  for (const contract of contracts.contracts) contract.editorApproval = "APPROVED";
  matrix.status = "APPROVED_BY_EDITOR_IN_CHIEF";
  for (const chapter of matrix.chapters) chapter.editorApproval = "APPROVED";
  for (const ledger of ledgers) ledger.status = "AUTHORED_APPROVED_BY_EDITOR_IN_CHIEF";
  interactions.status = "APPROVED_BY_EDITOR_IN_CHIEF";
  world.status = "APPROVED_BY_EDITOR_IN_CHIEF";

  const editorialDocuments = {
    "arc-matrix.json": matrix,
    "authored-interaction-effects-01-12.json": ledgerEarly,
    "authored-interaction-effects-13-24.json": ledgerLate,
    "chapter-catalog.json": catalog,
    "chapter-contracts.json": contracts,
    "interaction-mapping.json": interactions,
    "world-traces.json": world,
  };
  const editorialBytes = Object.fromEntries(
    editorialFileNames.map((name) => [name, serialise(editorialDocuments[name])]),
  );
  const aggregateMaterial = editorialFileNames
    .map((name) => `${name}\0${sha256(editorialBytes[name])}\n`)
    .join("");

  for (const name of editorialFileNames) {
    await writeFile(path.join(root, name), editorialBytes[name]);
  }
  const approvedRecord = {
    ...approval,
    status: "APPROVED_BY_EDITOR_IN_CHIEF",
    approvedAt,
    decisionReference,
    chapterContractsSHA256: sha256(editorialBytes["chapter-contracts.json"]),
    arcMatrixSHA256: sha256(editorialBytes["arc-matrix.json"]),
    phase0EditorialSHA256: sha256(Buffer.from(aggregateMaterial, "utf8")),
  };
  await writeFile(path.join(root, "editor-approval.json"), serialise(approvedRecord));

  await execFileAsync(process.execPath, [path.join(root, "enrich.mjs"), "--check"], { cwd: root });
  await execFileAsync(process.execPath, [path.join(root, "generate-editor-approval-brief.mjs")], { cwd: root });
  await execFileAsync(process.execPath, [path.join(root, "validate.mjs")], { cwd: root });
  process.stdout.write("Phase 0 approved with the four editor-reviewed resolutions.\n");
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`);
  process.exitCode = 1;
});

