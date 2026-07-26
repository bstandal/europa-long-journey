import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { promisify } from "node:util";
import {
  editorialLeakagePatterns,
  interactionGrammars,
  requiredFreeChapterIDs,
  stableIDPattern,
} from "./policy.mjs";
import { ValidationError } from "./validate.mjs";

const dispositions = new Set(["KEEP", "MERGE", "REWRITE", "REMOVE"]);
const approvalStates = new Set(["DRAFT_PENDING", "APPROVED"]);
const execFileAsync = promisify(execFile);

async function readJSON(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

function inspectEditorialStrings(value, location, issues) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => inspectEditorialStrings(item, `${location}[${index}]`, issues));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      inspectEditorialStrings(child, `${location}.${key}`, issues);
    }
    return;
  }
  if (typeof value !== "string") return;
  for (const pattern of editorialLeakagePatterns) {
    if (pattern.test(value)) issues.push(`${location}: editorial regression '${value.match(pattern)?.[0]}'`);
  }
}

function equalsAsSet(left, right) {
  return JSON.stringify([...left].sort()) === JSON.stringify([...right].sort());
}

function equalNumericRecords(left = {}, right = {}, allowedKeys = []) {
  return allowedKeys.every((key) => (left[key] ?? 0) === (right[key] ?? 0))
    && Object.keys(left).every((key) => allowedKeys.includes(key))
    && Object.keys(right).every((key) => allowedKeys.includes(key));
}

export async function validateBlueprint(root) {
  const catalog = await readJSON(path.join(root, "chapter-catalog.json"));
  const contracts = await readJSON(path.join(root, "chapter-contracts.json"));
  const arcs = await readJSON(path.join(root, "arc-matrix.json"));
  const interactions = await readJSON(path.join(root, "interaction-mapping.json"));
  const world = await readJSON(path.join(root, "world-traces.json"));
  const issues = [];

  const chapterIDs = (catalog.chapters ?? []).map((chapter) => chapter.contentID);
  if (catalog.chapterCount !== 24 || chapterIDs.length !== 24 || new Set(chapterIDs).size !== 24) {
    issues.push("chapter-catalog: exactly 24 unique chapters required");
  }
  if (!chapterIDs.every((id) => stableIDPattern.test(id))) {
    issues.push("chapter-catalog: every contentID must be stable kebab case");
  }
  if (!equalsAsSet(catalog.freeContentIDs ?? [], requiredFreeChapterIDs)) {
    issues.push(`chapter-catalog: free IDs must equal ${requiredFreeChapterIDs.join(", ")}`);
  }
  const ordinals = (catalog.chapters ?? []).map((chapter) => chapter.ordinal);
  if (!equalsAsSet(ordinals, Array.from({ length: 24 }, (_, index) => index + 1))) {
    issues.push("chapter-catalog: ordinals must cover 1–24 exactly");
  }

  const contractItems = contracts.contracts ?? [];
  const contractIDs = contractItems.map((contract) => contract.contentID);
  if (contracts.contractCount !== 24 || !equalsAsSet(contractIDs, chapterIDs)) {
    issues.push("chapter-contracts: contracts must cover the catalog exactly");
  }
  for (const [index, contract] of contractItems.entries()) {
    const location = `chapter-contracts.contracts[${index}]`;
    if (!approvalStates.has(contract.editorApproval)) issues.push(`${location}: invalid editor approval state`);
    for (const field of ["thesis", "causalSpine", "requiredEmphases", "governingJudgement", "ending", "handoff"]) {
      if (!(field in contract)) issues.push(`${location}: missing ${field}`);
    }
    inspectEditorialStrings(contract, location, issues);
  }

  const arcChapters = arcs.chapters ?? [];
  if (arcs.chapterCount !== 24 || !equalsAsSet(arcChapters.map((chapter) => chapter.contentID), chapterIDs)) {
    issues.push("arc-matrix: arcs must cover the catalog exactly");
  }
  const seenMovementIDs = new Set();
  let arcCount = 0;
  for (const [chapterIndex, chapter] of arcChapters.entries()) {
    const location = `arc-matrix.chapters[${chapterIndex}]`;
    if (!approvalStates.has(chapter.editorApproval)) issues.push(`${location}: invalid editor approval state`);
    if (!Array.isArray(chapter.arcs) || chapter.arcs.length < 1 || chapter.arcs.length > 3) {
      issues.push(`${location}: requires 1–3 arcs`);
      continue;
    }
    if (chapter.arcCount !== chapter.arcs.length) issues.push(`${location}.arcCount: does not match arcs`);
    arcCount += chapter.arcs.length;
    for (const [arcIndex, arc] of chapter.arcs.entries()) {
      const arcLocation = `${location}.arcs[${arcIndex}]`;
      if (!stableIDPattern.test(arc.arcID ?? "")) issues.push(`${arcLocation}: invalid arcID`);
      if (!Number.isInteger(arc.targetDurationMinutes) || arc.targetDurationMinutes < 8 || arc.targetDurationMinutes > 15) {
        issues.push(`${arcLocation}: target duration must be 8–15 minutes`);
      }
      if (!Array.isArray(arc.movementIDs) || !arc.movementIDs.length) issues.push(`${arcLocation}: movement coverage required`);
      for (const movementID of arc.movementIDs ?? []) {
        const identity = `${chapter.contentID}/${movementID}`;
        if (seenMovementIDs.has(identity)) issues.push(`${arcLocation}: duplicate movement ${identity}`);
        seenMovementIDs.add(identity);
      }
      for (const field of ["situation", "mechanism", "turn", "consequence", "handoff"]) {
        if (!arc[field]) issues.push(`${arcLocation}: missing ${field}`);
      }
      inspectEditorialStrings(arc, arcLocation, issues);
    }
  }
  if (arcCount !== arcs.arcCount) issues.push(`arc-matrix: declared ${arcs.arcCount}, found ${arcCount}`);
  if (seenMovementIDs.size !== arcs.coveredMovementCount || seenMovementIDs.size !== 290) {
    issues.push(`arc-matrix: expected 290 unique movements, found ${seenMovementIDs.size}`);
  }

  const interactionItems = interactions.items ?? [];
  if (interactions.counts?.interactions !== 122 || interactionItems.length !== 122) {
    issues.push(`interaction-mapping: expected 122 interactions, found ${interactionItems.length}`);
  }
  const seenInteractions = new Set();
  const grammarCounts = {};
  const dispositionCounts = {};
  for (const [index, item] of interactionItems.entries()) {
    const location = `interaction-mapping.items[${index}]`;
    if (seenInteractions.has(item.sourceInteractionID)) issues.push(`${location}: duplicate sourceInteractionID`);
    seenInteractions.add(item.sourceInteractionID);
    if (!chapterIDs.includes(item.chapterID)) issues.push(`${location}: unknown chapterID`);
    if (!interactionGrammars.has(item.nativeGrammar)) issues.push(`${location}: invalid native grammar`);
    if (!dispositions.has(item.disposition)) issues.push(`${location}: invalid disposition`);
    grammarCounts[item.nativeGrammar] = (grammarCounts[item.nativeGrammar] ?? 0) + 1;
    dispositionCounts[item.disposition] = (dispositionCounts[item.disposition] ?? 0) + 1;
  }
  if (!equalNumericRecords(
    grammarCounts,
    interactions.counts?.byGrammar,
    [...interactionGrammars],
  )) {
    issues.push("interaction-mapping: grammar counts do not match items");
  }
  if (!equalNumericRecords(
    dispositionCounts,
    interactions.counts?.byDisposition,
    [...dispositions],
  )) {
    issues.push("interaction-mapping: disposition counts do not match items");
  }

  const traces = world.traces ?? world.worldTraces ?? [];
  if (!Array.isArray(traces) || traces.length < 24) issues.push("world-traces: at least one trace per chapter is required");
  const tracedChapters = new Set();
  for (const [index, trace] of traces.entries()) {
    const location = `world-traces.traces[${index}]`;
    if (!stableIDPattern.test(trace.traceID ?? trace.effectID ?? "")) issues.push(`${location}: stable traceID required`);
    const chapterID = trace.originChapterID ?? trace.chapterID ?? trace.introducedBy?.contentID;
    if (!chapterIDs.includes(chapterID)) issues.push(`${location}: unknown origin chapter`);
    tracedChapters.add(chapterID);
    if (!(trace.consequence ?? trace.result ?? trace.state)) issues.push(`${location}: concrete consequence required`);
  }
  if (!equalsAsSet(tracedChapters, chapterIDs)) issues.push("world-traces: every chapter must originate a trace");

  if (!issues.length) {
    try {
      await execFileAsync(process.execPath, [path.join(root, "validate.mjs")], {
        cwd: root,
        maxBuffer: 4 * 1024 * 1024,
      });
    } catch (error) {
      const detail = String(error.stderr || error.stdout || error.message).trim();
      issues.push(`strict Phase 0 validation failed: ${detail}`);
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return {
    chapters: chapterIDs.length,
    contracts: contractItems.length,
    arcs: arcCount,
    movements: seenMovementIDs.size,
    interactions: interactionItems.length,
    traces: traces.length,
  };
}
