import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";

import { validateLaunchViewportCropContract } from
  "../tooling/src/compile.mjs";
import { validatePublicDocument } from "../tooling/src/validate.mjs";
import { validateChapter01ReviewMatrix } from
  "../phase2/validate-chapter-01-review-matrix.mjs";
import { validateChapter01ReviewTextFreeze } from
  "../phase2/validate-chapter-01-review-text-freeze.mjs";
import { validateFirstFarmersDraft } from
  "../phase2/validate-first-farmers-draft.mjs";
import { validateFirstFarmersClaimRegister } from
  "./validate-first-farmers-claim-register.mjs";

const gateRelativePath =
  "native/quality/chapter-01-review/review-ready-gate.json";
const stableIDPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
const sha256Pattern = /^[a-f0-9]{64}$/u;
const expectedEvidenceTypes = [
  "AUTOMATED_SUITES",
  "FIXTURE_DETERMINISM",
  "SIMULATOR_TRAVERSAL",
  "INTERACTION_RECORDINGS",
  "RESTORE_MATRIX",
  "AUDIO_RESTORE",
  "ACCESSIBILITY",
  "OFFLINE",
];
const expectedAutomatedSuiteIDs = [
  "editorial-regression-and-f1-f7",
  "tooling",
  "swiftpm",
  "fixture",
  "xcode-ui",
  "sanitizer",
  "release-boundary",
];
const commonReceiptKeys = [
  "schemaVersion",
  "receiptID",
  "type",
  "milestone",
  "status",
  "chapterID",
  "shippingState",
  "subjectSHA256",
];

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function safeRepositoryPath(repositoryRoot, relativePath, description) {
  assert.equal(typeof relativePath, "string", `${description} must be a path`);
  assert.ok(relativePath.length > 0, `${description} cannot be empty`);
  assert.ok(!path.isAbsolute(relativePath), `${description} cannot be absolute`);
  assert.ok(!relativePath.includes("\\"), `${description} must use package-style separators`);
  assert.equal(path.posix.normalize(relativePath), relativePath,
    `${description} cannot contain traversal or redundant components`);
  assert.ok(!relativePath.startsWith("../") && relativePath !== "..",
    `${description} cannot escape the repository`);
  const resolved = path.resolve(repositoryRoot, relativePath);
  const relation = path.relative(repositoryRoot, resolved);
  assert.ok(relation !== ".." && !relation.startsWith(`..${path.sep}`),
    `${description} escaped the repository`);
  return resolved;
}

async function readRegularBytes(repositoryRoot, relativePath, description) {
  const absolute = safeRepositoryPath(repositoryRoot, relativePath, description);
  const info = await lstat(absolute);
  assert.ok(info.isFile() && !info.isSymbolicLink(),
    `${description} must be a regular, non-symbolic-link file`);
  return readFile(absolute);
}

async function readRegularJSON(repositoryRoot, relativePath, description) {
  const bytes = await readRegularBytes(repositoryRoot, relativePath, description);
  let value;
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch {
    assert.fail(`${description} must contain valid JSON`);
  }
  assert.ok(isRecord(value), `${description} must be a JSON object`);
  return { bytes, value };
}

async function readOptionalRegularJSON(repositoryRoot, relativePath, description) {
  try {
    return await readRegularJSON(repositoryRoot, relativePath, description);
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    throw error;
  }
}

export async function chapter01ReviewFixtureTreeSHA256(repositoryRoot, relativeRoot) {
  const root = safeRepositoryPath(repositoryRoot, relativeRoot, "Chapter 01 fixture tree");
  const rootInfo = await lstat(root);
  assert.ok(rootInfo.isDirectory() && !rootInfo.isSymbolicLink(),
    "Chapter 01 fixture tree must be a regular directory");
  const records = [];
  async function visit(directory) {
    const entries = await readdir(directory, { withFileTypes: true });
    entries.sort((left, right) => left.name.localeCompare(right.name, "en"));
    for (const entry of entries) {
      const absolute = path.join(directory, entry.name);
      const info = await lstat(absolute);
      assert.ok(!info.isSymbolicLink(), "Chapter 01 fixture tree cannot contain symlinks");
      if (info.isDirectory()) {
        await visit(absolute);
      } else {
        assert.ok(info.isFile(), "Chapter 01 fixture tree can contain only files and directories");
        const bytes = await readFile(absolute);
        const relative = path.relative(root, absolute).split(path.sep).join("/");
        records.push(`${relative}\0${bytes.length}\0${sha256(bytes)}`);
      }
    }
  }
  await visit(root);
  assert.ok(records.length > 0, "Chapter 01 fixture tree cannot be empty");
  return sha256(Buffer.from(`${records.join("\n")}\n`, "utf8"));
}

export async function chapter01ReviewSubjectSHA256(repositoryRoot, gate) {
  const directoryRoots = [
    gate.sources.runtimeFixture,
    "native/ios/Sources",
    "native/ios/Tests",
    "native/ios/UITests",
    "native/ios/Config",
  ];
  const fileRoots = [
    "native/ios/Package.swift",
    "native/ios/project.yml",
    "native/scripts/verify-native.sh",
    gate.sources.trustReceipt,
  ];
  const records = [];
  for (const relativeRoot of directoryRoots) {
    records.push(
      `tree\0${relativeRoot}\0${await chapter01ReviewFixtureTreeSHA256(
        repositoryRoot,
        relativeRoot,
      )}`,
    );
  }
  for (const relativePath of fileRoots) {
    const bytes = await readRegularBytes(
      repositoryRoot,
      relativePath,
      `Chapter 01 review subject ${relativePath}`,
    );
    records.push(`file\0${relativePath}\0${bytes.length}\0${sha256(bytes)}`);
  }
  return sha256(Buffer.from(`${records.join("\n")}\n`, "utf8"));
}

function assertExactKeys(value, keys, description) {
  assert.ok(isRecord(value), `${description} must be an object`);
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort(),
    `${description} fields drifted`);
}

function assertStableUniqueIDs(ids, expectedCount, description) {
  assert.ok(Array.isArray(ids), `${description} must be an array`);
  assert.equal(ids.length, expectedCount, `${description} count drifted`);
  assert.equal(new Set(ids).size, expectedCount, `${description} must be unique`);
  ids.forEach((id) => assert.match(id, stableIDPattern, `${description} contains an unstable ID`));
}

function flattenDraftBeats(draft) {
  return draft.arcs.flatMap((arc) => arc.beats.map((beat) => ({
    arcID: arc.arcID,
    beatID: beat.beatID,
    sceneID: beat.sceneID,
    interactionID: beat.interaction?.id ?? null,
  })));
}

function flattenPayloadBeats(chapter) {
  return chapter.arcs.flatMap((arc) => arc.beats.map((beat) => ({
    arcID: arc.id,
    beatID: beat.id,
    sceneID: beat.sceneID,
    interactionID: beat.interaction?.id ?? null,
  })));
}

function assetPaths(value, output = []) {
  if (Array.isArray(value)) {
    value.forEach((item) => assetPaths(item, output));
  } else if (isRecord(value)) {
    for (const [key, child] of Object.entries(value)) {
      if (key === "assetPath") output.push(child);
      assetPaths(child, output);
    }
  }
  return output;
}

function assertOfflinePackageReferences(payload, description) {
  const paths = assetPaths(payload);
  assert.ok(paths.length > 0, `${description} contains no package assets`);
  for (const assetPath of paths) {
    assert.equal(typeof assetPath, "string", `${description} has a non-string asset path`);
    assert.ok(!assetPath.includes("://") && !assetPath.startsWith("/")
      && !assetPath.startsWith("../") && !assetPath.includes("/../"),
    `${description} contains a networked or escaping asset path: ${assetPath}`);
    assert.equal(path.posix.normalize(assetPath), assetPath,
      `${description} contains a non-canonical asset path: ${assetPath}`);
  }
  const serialized = JSON.stringify(payload);
  assert.ok(!/(?:https?|wss?|ftp):\/\//iu.test(serialized),
    `${description} contains a network URL`);
  return paths;
}

export function validateChapter01ReviewGateDocument(gate) {
  assert.equal(gate.schemaVersion, 1, "Chapter 01 review gate schema drifted");
  assert.equal(gate.gateID, "chapter-01-review-ready-v1", "Chapter 01 gate ID drifted");
  assert.equal(gate.milestone, "CHAPTER_01_REVIEW_READY", "Chapter 01 milestone drifted");
  assert.ok(["CANDIDATE", "PASS"].includes(gate.status), "Gate status is invalid");
  assert.equal(gate.chapterID, "first-farmers", "Chapter 01 gate changed chapter");
  assert.equal(gate.shippingState, "PROHIBITED", "Review gate escaped shipping boundary");
  assert.equal(gate.shippingAllowed, false, "Review gate cannot authorize shipping");
  assert.equal(gate.publicContentSchemaMutation, false,
    "Review gate cannot mutate the public content schema");
  assert.deepEqual(gate.expectedCounts, {
    arcs: 3,
    beats: 17,
    interactions: 6,
    reviewWorlds: 6,
    narrationCues: 37,
    firstFarmersAudioTimelines: 47,
    reviewTransitions: 3,
  }, "Chapter 01 review counts drifted");
  assert.deepEqual(gate.canonical.saveIdentityFields,
    ["chapterID", "arcID", "beatID", "interactionID"],
    "Chapter 01 canonical save identity drifted");
  assertStableUniqueIDs(gate.canonical.arcIDs, 3, "Chapter 01 arc IDs");
  assertStableUniqueIDs(gate.canonical.worldIDs, 6, "Chapter 01 review-world IDs");
  assertStableUniqueIDs(gate.canonical.transitionIDs, 3, "Chapter 01 transition IDs");
  assertStableUniqueIDs(
    gate.canonical.beatSaveAnchors.map(({ beatID }) => beatID),
    17,
    "Chapter 01 beat save anchors",
  );
  assertStableUniqueIDs(
    gate.canonical.beatSaveAnchors.map(({ sceneID }) => sceneID),
    17,
    "Chapter 01 scene restore anchors",
  );
  assertStableUniqueIDs(gate.canonical.narrationCueIDs, 37, "Chapter 01 narration cues");
  assertStableUniqueIDs(gate.canonical.audioTimelineIDs, 47, "Chapter 01 audio timelines");
  assert.equal(gate.requiredEvidence.length, expectedEvidenceTypes.length,
    "Chapter 01 required-evidence inventory drifted");
  assert.deepEqual(gate.requiredEvidence.map(({ type }) => type), expectedEvidenceTypes,
    "Chapter 01 required-evidence order or type drifted");
  assertStableUniqueIDs(gate.requiredEvidence.map(({ id }) => id),
    expectedEvidenceTypes.length, "Chapter 01 evidence IDs");
  for (const evidence of gate.requiredEvidence) {
    assert.ok(evidence.path.startsWith("native/quality/chapter-01-review/evidence/"),
      `${evidence.id}: evidence escaped the Chapter 01 review boundary`);
    assert.equal(path.posix.normalize(evidence.path), evidence.path,
      `${evidence.id}: evidence path is not canonical`);
    assert.ok(!evidence.path.includes("/../"),
      `${evidence.id}: evidence path escaped the review boundary`);
  }
}

function validateInteractionContracts(draft) {
  const interactions = draft.arcs.flatMap(({ beats }) => beats)
    .flatMap((beat) => beat.interaction ? [beat.interaction] : []);
  assert.equal(interactions.length, 6, "Chapter 01 requires exactly six interactions");
  const byID = new Map(interactions.map((interaction) => [interaction.id, interaction]));

  const trace = byID.get("interaction-first-farmers-a-household-crosses");
  assert.equal(trace?.grammar, "trace");
  assert.deepEqual(trace.anchors.map(({ id }) => id),
    ["western-anatolia", "aegean-islands", "thessaly", "danube-corridor"],
    "The Aegean trace route must retain its four ordered anchors");

  const allocate = byID.get("interaction-first-farmers-the-harvest-had-to-last");
  assert.equal(allocate?.grammar, "allocate");
  assert.equal(allocate.totalUnits, 12);
  assert.deepEqual(allocate.destinations.map(({ id, minimumUnits }) => [id, minimumUnits]), [
    ["food", 4],
    ["reserve", 2],
    ["seed", 3],
  ], "Harvest allocation obligations drifted");
  assert.equal(allocate.reversalPermittedUntilCommit, true,
    "Harvest allocation must remain reversible before commit");

  const records = byID.get("interaction-first-farmers-at-the-iron-gates");
  assert.equal(records?.grammar, "transform");
  assert.deepEqual(records.stages.map(({ id }) => id),
    ["river-communities", "contact-households", "later-settlements"],
    "Three Records chronology drifted");

  const assemble = byID.get("interaction-first-farmers-the-house-outlives");
  assert.equal(assemble?.grammar, "assemble");
  assert.deepEqual(assemble.components.map(({ id, prerequisites }) => ({ id, prerequisites })), [
    { id: "posts", prerequisites: [] },
    { id: "hearth", prerequisites: ["posts"] },
    { id: "storage", prerequisites: ["posts"] },
    { id: "roof", prerequisites: ["posts"] },
  ], "Longhouse assembly must require posts first and permit the rest in any order");

  const settlement = byID.get("interaction-first-farmers-more-mouths-more-land");
  assert.equal(settlement?.grammar, "transform");
  assert.deepEqual(settlement.stages.map(({ id }) => id),
    ["new-hearths", "field-edges", "herd-lanes-and-daughters"],
    "Settlement transform stages drifted");

  const continent = byID.get("interaction-first-farmers-a-continent-remade");
  assert.equal(continent?.grammar, "transform");
  assert.deepEqual(continent.stages.map(({ id }) => id),
    ["danube-fields", "loess-settlements", "european-farming-belt"],
    "Continent transform stages drifted");
  return interactions;
}

function validateSourcePayload({ gate, draft, freeze, matrix, payload }) {
  validatePublicDocument(payload, gate.sources.contentPackage);
  validateLaunchViewportCropContract(payload, "chapter01Review.sourcePayload");
  assert.equal(payload.packageID, "first-farmers-development-v1",
    "Chapter 01 development package ID drifted");
  assert.equal(payload.chapters.length, 1, "Chapter 01 source package must contain one chapter");
  const chapter = payload.chapters[0];
  assert.equal(chapter.id, gate.chapterID);
  assert.deepEqual(chapter.arcs.map(({ id }) => id), gate.canonical.arcIDs,
    "Chapter 01 payload arc IDs drifted");
  assert.deepEqual(flattenPayloadBeats(chapter), gate.canonical.beatSaveAnchors,
    "Chapter 01 payload save identities drifted");
  assert.deepEqual(flattenDraftBeats(draft), gate.canonical.beatSaveAnchors,
    "Chapter 01 draft save identities drifted");
  assert.deepEqual(matrix.worlds.map(({ id }) => id), gate.canonical.worldIDs,
    "Chapter 01 review-world IDs drifted");

  const interactions = validateInteractionContracts(draft);
  assert.deepEqual(interactions.map(({ id }) => id),
    gate.canonical.beatSaveAnchors.flatMap(({ interactionID }) =>
      interactionID ? [interactionID] : []),
  "Chapter 01 interaction save identities drifted");

  const cueIDs = chapter.arcs.flatMap(({ beats }) => beats)
    .flatMap(({ narrationCueIDs }) => narrationCueIDs);
  assert.deepEqual(cueIDs, gate.canonical.narrationCueIDs,
    "Chapter 01 narration cue IDs drifted");
  assert.deepEqual(payload.audioTimelines.map(({ id }) => id), gate.canonical.audioTimelineIDs,
    "Chapter 01 17 main and 30 responsive timeline IDs drifted");
  assert.equal(payload.responsiveAudioPrograms.length, 6,
    "Chapter 01 requires six responsive audio programs");

  const narrationEvents = payload.audioTimelines.flatMap(({ events }) => events)
    .filter(({ role }) => role === "narration");
  assert.deepEqual(narrationEvents.map(({ cueID }) => cueID), gate.canonical.narrationCueIDs,
    "Chapter 01 narration events drifted");
  const frozenBySegmentID = new Map(freeze.segments.map((segment) => [segment.segmentID, segment]));
  for (const event of narrationEvents) {
    const frozen = frozenBySegmentID.get(event.narrationBinding?.manuscriptSegmentID);
    assert.ok(frozen, `${event.cueID}: narration event is not bound to frozen prose`);
    assert.equal(event.narrationBinding.manuscriptSegmentSHA256, frozen.textSha256,
      `${event.cueID}: narration text hash drifted`);
    assert.equal(event.narrationBinding.scope.chapterID, gate.chapterID);
    assert.equal(event.narrationBinding.scope.arcID, frozen.arcID);
    assert.equal(event.narrationBinding.scope.beatID, frozen.beatID);
    assert.ok(Number.isSafeInteger(event.durationSamples) && event.durationSamples > 0,
      `${event.cueID}: narration duration must come from decoded audio`);
  }
  assert.ok(payload.audioTimelines.every(({ haptics }) =>
    Array.isArray(haptics) && haptics.length === 0),
  "Chapter 01 audio timelines cannot contain time-coded haptics");

  assert.equal(draft.accessibilityContract.sameReducerForTouchAndVoiceOver, true);
  assert.equal(draft.accessibilityContract.sameCompletionEffects, true);
  assert.equal(draft.accessibilityContract.sceneSummariesRequired, 17);
  assert.equal(draft.accessibilityContract.dynamicTypeOutsideMetalCanvas, true);
  assert.equal(draft.accessibilityContract.reduceMotionPreservesCausalStates, true);
  assert.equal(draft.accessibilityContract.narrationAndReadingTextShareExactSegments, true);
  assert.equal(matrix.portraitContract.minimumEffectiveTargetPoints, 44);
  assert.equal(payload.scenes.length, 17, "Chapter 01 requires 17 scenes");
  assert.equal(payload.accessibility.length, 17, "Chapter 01 requires 17 accessibility records");
  assert.ok(payload.scenes.every(({ reduceMotionComposition, accessibilityID }) =>
    reduceMotionComposition?.strata?.length > 0 && accessibilityID),
  "Every Chapter 01 scene requires Reduce Motion and VoiceOver bindings");
  assert.equal(new Set(payload.scenes.map(({ accessibilityID }) => accessibilityID)).size, 17,
    "Chapter 01 accessibility bindings must be unique");
  assertOfflinePackageReferences(payload, "Chapter 01 source package");
}

async function validateLaunchAndReleaseBoundary({ repositoryRoot, gate }) {
  const project = (await readRegularBytes(
    repositoryRoot, gate.sources.launchProject, "Chapter 01 launch project",
  )).toString("utf8");
  const schemeStart = project.indexOf("\n  LongWestJourneyLiveTest:\n");
  assert.ok(schemeStart >= 0, "LongWestJourneyLiveTest scheme is missing");
  const scheme = project.slice(schemeStart);
  assert.match(scheme, /run:\n\s+config: NON_SHIPPING_LIVE_TEST/u,
    "Live-test run configuration is not NON_SHIPPING_LIVE_TEST");
  assert.match(scheme, /"--ui-testing-signed-runtime-fixture": true/u,
    "Live-test scheme does not launch the signed fixture");
  assert.match(scheme, /"--ui-testing-signed-runtime-fixture-chapter=first-farmers": true/u,
    "Live-test scheme does not open Chapter 01 directly");
  assert.doesNotMatch(scheme, /--ui-testing-signed-runtime-fixture-beat=/u,
    "Live-test scheme must enter the canonical first beat without a debug beat override");
  assert.match(project,
    /Release:\n\s+EXCLUDED_SOURCE_FILE_NAMES:\n(?:\s+- .+\n)*\s+- first-farmers\.content-package\.json/u,
  "Release must exclude the Chapter 01 development payload");

  const loader = (await readRegularBytes(
    repositoryRoot, gate.sources.fixtureLoader, "Chapter 01 fixture loader",
  )).toString("utf8");
  assert.match(loader, /^#if DEBUG \|\| NON_SHIPPING_LIVE_TEST/u,
    "Fixture loader must be absent from ordinary Release");
  assert.match(loader, /return chapterIDs\[0\]/u,
    "Fixture loader no longer defaults to the first free chapter");
  assert.match(loader, /ChapterID\("first-farmers"\)/u,
    "Fixture loader first chapter drifted");
  assert.match(loader, /return nil\n\s+\}\n\s+return BeatID/u,
    "Fixture loader no longer defaults to the chapter's first beat");

  const releaseBoundary = (await readRegularBytes(
    repositoryRoot, gate.sources.releaseBoundary, "Release app boundary",
  )).toString("utf8");
  for (const sentinel of [
    "NON_SHIPPING",
    "vertical-slice-development-v1",
    "vertical-slice-development-trust-receipt.json",
    "--ui-testing-",
  ]) {
    assert.ok(releaseBoundary.includes(sentinel),
      `Release boundary no longer rejects review sentinel: ${sentinel}`);
  }
  const verifyNative = (await readRegularBytes(
    repositoryRoot, "native/scripts/verify-native.sh", "Native verification entrypoint",
  )).toString("utf8");
  assert.ok(verifyNative.includes("validate-release-app-boundary.mjs"),
    "Ordinary Release is no longer checked for review-resource leakage");
}

async function validateReceiptTemplates({ repositoryRoot, gate }) {
  const templates = (await readRegularJSON(
    repositoryRoot, gate.sources.receiptTemplates, "Chapter 01 evidence receipt templates",
  )).value;
  assert.equal(templates.schemaVersion, 1);
  assert.equal(templates.templateSetID, "chapter-01-review-evidence-templates-v1");
  assert.equal(templates.milestone, gate.milestone);
  assert.equal(templates.chapterID, gate.chapterID);
  assert.equal(templates.status, "PENDING_EVIDENCE");
  assert.equal(templates.shippingState, "PROHIBITED");
  assert.equal(templates.templates?.length, gate.requiredEvidence.length,
    "Chapter 01 must have one machine-readable template per evidence gate");
  const interactionIDs = receiptInteractionIDs(gate);
  const beatIDs = gate.canonical.beatSaveAnchors.map(({ beatID }) => beatID);
  for (const [index, template] of templates.templates.entries()) {
    const evidence = gate.requiredEvidence[index];
    assert.equal(template.evidenceID, evidence.id,
      "Chapter 01 receipt template order or ID drifted");
    assert.equal(template.destination, evidence.path,
      `${evidence.id}: receipt template destination drifted`);
    assert.equal(template.receipt?.schemaVersion, 1);
    assert.equal(template.receipt?.receiptID, `${evidence.id}-chapter-01-review-v1`);
    assert.equal(template.receipt?.type, evidence.type);
    assert.equal(template.receipt?.milestone, gate.milestone);
    assert.equal(template.receipt?.status, "PENDING_EVIDENCE");
    assert.equal(template.receipt?.chapterID, gate.chapterID);
    assert.equal(template.receipt?.shippingState, "PROHIBITED");
    assert.equal(template.receipt?.subjectSHA256, null,
      `${evidence.id}: pending template cannot pre-claim a review subject`);
    assert.ok(!JSON.stringify(template.receipt).includes('"status":"PASS"'),
      `${evidence.id}: pending template cannot claim PASS`);
  }
  const byType = new Map(templates.templates.map(({ receipt }) => [receipt.type, receipt]));
  assert.deepEqual(byType.get("AUTOMATED_SUITES")?.suites.map(({ id }) => id),
    expectedAutomatedSuiteIDs, "Automated-suite template drifted");
  assert.deepEqual(byType.get("RESTORE_MATRIX")?.beatEntry.map(({ beatID }) => beatID), beatIDs,
    "Entry-restore template drifted");
  assert.deepEqual(byType.get("RESTORE_MATRIX")?.beatExit.map(({ beatID }) => beatID), beatIDs,
    "Exit-restore template drifted");
  assert.deepEqual(byType.get("RESTORE_MATRIX")?.midInteraction
    .map(({ interactionID }) => interactionID), interactionIDs,
  "Mid-interaction restore template drifted");
  assert.deepEqual(byType.get("INTERACTION_RECORDINGS")?.recordings
    .map(({ interactionID }) => interactionID), interactionIDs,
  "Interaction-recording template drifted");
  assert.deepEqual(byType.get("ACCESSIBILITY")?.interactionIDs, interactionIDs,
    "Accessibility template drifted");
  assert.equal(byType.get("SIMULATOR_TRAVERSAL")?.operationMode, "CODEX_COMPUTER_USE",
    "Simulator traversal template must require a non-XCTest review round");
  const expectedArtifactRoles = new Map([
    ["AUTOMATED_SUITES", ["full-verification-log"]],
    ["SIMULATOR_TRAVERSAL", ["manual-traversal-log", "manual-traversal-recording"]],
    ["RESTORE_MATRIX", ["restore-matrix-log"]],
    ["AUDIO_RESTORE", ["audio-restore-log"]],
    ["ACCESSIBILITY", ["system-accessibility-log", "system-voiceover-recording"]],
    ["OFFLINE", ["network-denial-log", "offline-traversal-recording"]],
  ]);
  for (const [type, roles] of expectedArtifactRoles) {
    assert.deepEqual(byType.get(type)?.artifacts.map(({ role }) => role), roles,
      `${type} evidence-artifact template drifted`);
  }
}

async function validateArtifactBinding(repositoryRoot, binding, description, allowedPrefix) {
  assertExactKeys(binding, ["path", "bytes", "sha256"], description);
  assert.ok(binding.path.startsWith(allowedPrefix), `${description} escaped its evidence boundary`);
  assert.ok(Number.isSafeInteger(binding.bytes) && binding.bytes > 0,
    `${description} has no positive byte count`);
  assert.match(binding.sha256, sha256Pattern, `${description} has no SHA-256`);
  const bytes = await readRegularBytes(repositoryRoot, binding.path, description);
  assert.equal(bytes.length, binding.bytes, `${description} byte count drifted`);
  assert.equal(sha256(bytes), binding.sha256, `${description} hash drifted`);
  return bytes;
}

async function validateEvidenceArtifacts({
  repositoryRoot,
  artifacts,
  expectedRoles,
  description,
}) {
  assert.ok(Array.isArray(artifacts), `${description} artifacts must be an array`);
  assert.deepEqual(
    artifacts.map(({ role }) => role),
    expectedRoles,
    `${description} artifact roles drifted`,
  );
  const result = new Map();
  for (const artifact of artifacts) {
    assertExactKeys(
      artifact,
      ["role", "path", "bytes", "sha256"],
      `${description} ${artifact.role ?? "unknown"} artifact`,
    );
    const bytes = await validateArtifactBinding(
      repositoryRoot,
      {
        path: artifact.path,
        bytes: artifact.bytes,
        sha256: artifact.sha256,
      },
      `${description} ${artifact.role} artifact`,
      "native/quality/chapter-01-review/evidence/artifacts/",
    );
    result.set(artifact.role, bytes);
  }
  return result;
}

async function validateNarrationManifest({ repositoryRoot, gate, freeze }) {
  const loaded = await readOptionalRegularJSON(
    repositoryRoot, gate.sources.narrationManifest, "Chapter 01 review narration manifest",
  );
  if (!loaded) {
    return {
      blocker: "narration-manifest: missing 37-cue review narration manifest",
      manifest: null,
    };
  }
  const manifest = loaded.value;
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.manifestID, "chapter-01-review-narration-v1");
  assert.equal(manifest.status, "NON_SHIPPING_REVIEW");
  assert.equal(manifest.shippingState, "PROHIBITED");
  assert.equal(manifest.shippingUsePermitted, false);
  assert.equal(manifest.runtimeGenerationPermitted, false);
  assert.equal(manifest.milestone, gate.milestone);
  assert.equal(manifest.chapterID, gate.chapterID);
  assert.equal(manifest.sampleRate, 48_000);
  assert.equal(manifest.cueCount, 37);
  assert.equal(manifest.manuscriptDraftSHA256, freeze.sourceDraft.sha256);
  assert.equal(manifest.combinedBindingSHA256, freeze.combinedBindingSha256);
  assert.deepEqual(manifest.cues.map(({ cueID }) => cueID), gate.canonical.narrationCueIDs,
    "Review narration manifest cue IDs drifted");
  const frozenByID = new Map(freeze.segments.map((segment) => [segment.segmentID, segment]));
  for (const cue of manifest.cues) {
    assertExactKeys(cue, [
      "cueID", "manuscriptSegmentID", "manuscriptSegmentSHA256", "repositoryPath",
      "sampleRate", "durationSamples", "bytes", "sha256",
    ], `${cue.cueID} narration binding`);
    const frozen = frozenByID.get(cue.manuscriptSegmentID);
    assert.ok(frozen, `${cue.cueID}: unknown manuscript segment`);
    assert.equal(cue.manuscriptSegmentSHA256, frozen.textSha256,
      `${cue.cueID}: frozen text hash drifted`);
    assert.equal(cue.sampleRate, 48_000);
    await validateArtifactBinding(
      repositoryRoot,
      { path: cue.repositoryPath, bytes: cue.bytes, sha256: cue.sha256 },
      `${cue.cueID} review narration cue`,
      "native/audio/narration/review/chapter-01/cues/",
    );
  }
  return { blocker: null, manifest };
}

async function validateTransitionManifest({ repositoryRoot, gate }) {
  const loaded = await readOptionalRegularJSON(
    repositoryRoot, gate.sources.transitionManifest, "Chapter 01 review transition manifest",
  );
  if (!loaded) return "review-transitions: missing three-transition manifest";
  const manifest = loaded.value;
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.manifestID, "chapter-01-review-transitions-v1");
  assert.equal(manifest.status, "NON_SHIPPING_REVIEW");
  assert.equal(manifest.shippingState, "PROHIBITED");
  assert.equal(manifest.milestone, gate.milestone);
  assert.equal(manifest.chapterID, gate.chapterID);
  assert.equal(manifest.sampleRate, 48_000);
  assert.equal(manifest.channelCount, 2);
  assert.equal(manifest.transitionCount, 3);
  assert.equal(manifest.derivedWithoutNewComposition, true);
  assert.equal(manifest.runtimeGenerationPermitted, false);
  assert.equal(manifest.shippingUsePermitted, false);
  assert.deepEqual(manifest.transitions?.map(({ transitionID }) => transitionID),
    gate.canonical.transitionIDs, "Chapter 01 review transition IDs drifted");
  const expectedWorlds = [
    ["aegean-crossing", "thessaly-first-field"],
    ["harvest-store", "iron-gates-danube"],
    ["european-farming-belt", "steppe-transition"],
  ];
  for (const [index, transition] of manifest.transitions.entries()) {
    assert.equal(transition.fromWorld, expectedWorlds[index][0],
      `${transition.transitionID}: source world drifted`);
    assert.equal(transition.toWorld, expectedWorlds[index][1],
      `${transition.transitionID}: destination world drifted`);
    assert.equal(transition.derivation?.newCompositionAdded, false,
      `${transition.transitionID}: transition introduced a new composition`);
    assert.equal(transition.audio?.sampleRate, 48_000);
    assert.equal(transition.audio?.channelCount, 2);
    assert.ok(Number.isSafeInteger(transition.audio?.durationFrames)
      && transition.audio.durationFrames > 0,
    `${transition.transitionID}: transition has no decoded duration`);
    await validateArtifactBinding(
      repositoryRoot,
      {
        path: transition.audio?.path,
        bytes: transition.audio?.bytes,
        sha256: transition.audio?.sha256,
      },
      `${transition.transitionID} review transition`,
      "native/audio/score-soundscape/chapter-01-review-transitions-v1/audio/",
    );
  }
  return null;
}

async function validateRuntimeFixture({ repositoryRoot, gate, narrationManifest }) {
  const fixtureRoot = safeRepositoryPath(repositoryRoot, gate.sources.runtimeFixture,
    "Chapter 01 runtime fixture");
  let rootInfo;
  try {
    rootInfo = await lstat(fixtureRoot);
  } catch (error) {
    if (error?.code === "ENOENT") return "runtime-fixture: signed review fixture is missing";
    throw error;
  }
  assert.ok(rootInfo.isDirectory() && !rootInfo.isSymbolicLink(),
    "Chapter 01 runtime fixture must be a regular directory");
  const payloadRelative = `${gate.sources.runtimeFixture}/chapters/vertical-slice-development-v1.json`;
  const manifestRelative = `${gate.sources.runtimeFixture}/package-manifest.json`;
  const payload = (await readRegularJSON(
    repositoryRoot, payloadRelative, "Signed Chapter 01 runtime payload",
  )).value;
  validatePublicDocument(payload, payloadRelative);
  validateLaunchViewportCropContract(payload, "chapter01Review.runtimePayload");
  const chapter = payload.chapters.find(({ id }) => id === gate.chapterID);
  assert.ok(chapter, "Signed fixture does not contain Chapter 01");
  assert.deepEqual(flattenPayloadBeats(chapter), gate.canonical.beatSaveAnchors,
    "Signed fixture Chapter 01 save identities drifted");
  assert.deepEqual(chapter.arcs.flatMap(({ beats }) => beats)
    .flatMap(({ narrationCueIDs }) => narrationCueIDs), gate.canonical.narrationCueIDs,
  "Signed fixture Chapter 01 narration cues drifted");
  const timelinesByID = new Map(payload.audioTimelines.map((timeline) => [timeline.id, timeline]));
  assert.ok(gate.canonical.audioTimelineIDs.every((id) => timelinesByID.has(id)),
    "Signed fixture does not contain all 47 Chapter 01 timelines");
  assert.ok(gate.canonical.audioTimelineIDs.every((id) =>
    timelinesByID.get(id).haptics?.length === 0),
  "Signed fixture Chapter 01 timelines contain time-coded haptics");
  if (narrationManifest === null) {
    return "runtime-fixture: narration manifest is unavailable for decoded-length parity";
  }
  const narrationEvents = gate.canonical.audioTimelineIDs
    .filter((timelineID) => timelineID.startsWith("audio-beat-first-farmers-"))
    .flatMap((timelineID) => timelinesByID.get(timelineID).events)
    .filter(({ role }) => role === "narration");
  assert.deepEqual(narrationEvents.map(({ cueID }) => cueID), gate.canonical.narrationCueIDs,
    "Signed fixture narration cue projection drifted");
  const manifestCueByID = new Map(
    narrationManifest.cues.map((cue) => [cue.cueID, cue]),
  );
  for (const event of narrationEvents) {
    const cue = manifestCueByID.get(event.cueID);
    assert.equal(event.durationSamples, cue?.durationSamples,
      `${event.cueID}: signed fixture does not use decoded narration length`);
    assert.equal(event.assetPath,
      `audio/first-farmers/review-narration/${event.cueID}.m4a`,
    `${event.cueID}: signed fixture narration path drifted`);
  }
  const firstFarmerPrograms = payload.responsiveAudioPrograms
    .filter(({ scope }) => scope.chapterID === gate.chapterID);
  assert.equal(firstFarmerPrograms.length, 6,
    "Signed fixture does not contain six Chapter 01 responsive audio programs");
  const transitionTimelineIDs = new Map([
    ["transition-aegean-thessaly-v1", "audio-beat-first-farmers-living-system"],
    ["transition-store-iron-gates-v1", "audio-beat-first-farmers-gorge-contact"],
    ["transition-farming-belt-steppe-v1", "audio-beat-first-farmers-before-steppe"],
  ]);
  for (const [transitionID, timelineID] of transitionTimelineIDs) {
    const event = timelinesByID.get(timelineID)?.events
      .find(({ cueID }) => cueID === transitionID);
    assert.ok(event?.role === "soundscape" && event.startSample === 0
      && event.durationSamples > 0
      && event.assetPath === `audio/first-farmers/review-transitions/${transitionID}.m4a`,
    `${transitionID}: signed fixture transition projection drifted`);
  }
  const chapterSceneIDs = new Set(gate.canonical.beatSaveAnchors.map(({ sceneID }) => sceneID));
  const scenes = payload.scenes.filter(({ id }) => chapterSceneIDs.has(id));
  assert.equal(scenes.length, 17, "Signed fixture does not contain 17 Chapter 01 scenes");
  const projectedWorldIDs = new Set();
  for (const scene of scenes) {
    assert.ok(scene.reduceMotionComposition?.strata?.length > 0,
      `${scene.id}: signed fixture has no Reduce Motion composition`);
    for (const worldID of gate.canonical.worldIDs) {
      if (scene.layers.some(({ assetPath }) => assetPath.startsWith(`assets/${worldID}-`))) {
        projectedWorldIDs.add(worldID);
      }
    }
  }
  assert.deepEqual([...projectedWorldIDs].sort(), [...gate.canonical.worldIDs].sort(),
    "Signed fixture does not project exactly six Chapter 01 review worlds");
  const fixtureAssets = assertOfflinePackageReferences(payload, "Signed Chapter 01 runtime payload");
  const manifest = (await readRegularJSON(
    repositoryRoot, manifestRelative, "Signed Chapter 01 package manifest",
  )).value;
  const manifestPaths = new Set(manifest.files?.map(({ path: filePath }) => filePath));
  for (const assetPath of fixtureAssets) {
    assert.ok(manifestPaths.has(assetPath), `Signed fixture manifest omits ${assetPath}`);
    await readRegularBytes(repositoryRoot, `${gate.sources.runtimeFixture}/${assetPath}`,
      `Signed fixture asset ${assetPath}`);
  }
  await readRegularJSON(
    repositoryRoot, gate.sources.trustReceipt, "Signed Chapter 01 trust receipt",
  );
  return null;
}

function validateCommonReceipt(receipt, evidence) {
  assert.equal(receipt.schemaVersion, 1, `${evidence.id}: receipt schema drifted`);
  assert.equal(receipt.receiptID, `${evidence.id}-chapter-01-review-v1`,
    `${evidence.id}: receipt ID drifted`);
  assert.equal(receipt.type, evidence.type, `${evidence.id}: receipt type drifted`);
  assert.equal(receipt.milestone, "CHAPTER_01_REVIEW_READY");
  assert.equal(receipt.status, "PASS", `${evidence.id}: evidence did not pass`);
  assert.equal(receipt.chapterID, "first-farmers");
  assert.equal(receipt.shippingState, "PROHIBITED",
    `${evidence.id}: evidence cannot authorize shipping`);
  const serialized = JSON.stringify(receipt);
  assert.ok(!/(?:shippingAllowed|productionApproved|shippingApproved)/u.test(serialized),
    `${evidence.id}: evidence contains an unauthorized approval field`);
}

function receiptInteractionIDs(gate) {
  return gate.canonical.beatSaveAnchors.flatMap(({ interactionID }) =>
    interactionID ? [interactionID] : []);
}

function parseVersion(value, description) {
  assert.match(value, /^\d+(?:\.\d+){1,2}$/u, `${description} is not a version`);
  return value.split(".").map(Number);
}

function versionAtLeast(actual, minimum) {
  const left = parseVersion(actual, "Simulator OS version");
  const right = parseVersion(minimum, "Minimum simulator OS version");
  while (left.length < right.length) left.push(0);
  while (right.length < left.length) right.push(0);
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) return left[index] > right[index];
  }
  return true;
}

export async function validateChapter01ReviewEvidenceReceipt({
  repositoryRoot,
  gate,
  evidence,
  receipt,
}) {
  validateCommonReceipt(receipt, evidence);
  assert.match(receipt.subjectSHA256, sha256Pattern,
    `${evidence.id}: receipt has no review-subject SHA-256`);
  assert.equal(
    receipt.subjectSHA256,
    await chapter01ReviewSubjectSHA256(repositoryRoot, gate),
    `${evidence.id}: receipt does not bind the current fixture and native implementation`,
  );
  const interactionIDs = receiptInteractionIDs(gate);
  const beatIDs = gate.canonical.beatSaveAnchors.map(({ beatID }) => beatID);
  switch (evidence.type) {
    case "AUTOMATED_SUITES": {
      assertExactKeys(receipt, [...commonReceiptKeys, "suites", "artifacts"],
        "Automated suites receipt");
      assert.deepEqual(receipt.suites?.map(({ id }) => id), expectedAutomatedSuiteIDs,
        "Automated review-suite inventory drifted");
      receipt.suites.forEach((suite) => assertExactKeys(
        suite, ["id", "command", "exitCode", "errorCount"], `${suite.id} suite result`,
      ));
      assert.ok(receipt.suites.every(({ command, exitCode, errorCount }) =>
        typeof command === "string" && command.length > 0 && exitCode === 0 && errorCount === 0),
      "Every automated Chapter 01 suite must complete with zero errors");
      const artifacts = await validateEvidenceArtifacts({
        repositoryRoot,
        artifacts: receipt.artifacts,
        expectedRoles: ["full-verification-log"],
        description: "Automated suites",
      });
      const log = artifacts.get("full-verification-log").toString("utf8");
      assert.match(log, /^CHAPTER_01_NATIVE_VERIFY=PASS$/mu,
        "Automated suites log has no terminal full-verification PASS");
      assert.match(log, /Release app boundary-only: PASS_BOUNDARY_ONLY_NON_SHIPPING/u,
        "Automated suites log has no Release-boundary PASS");
      assert.match(log, /CHAPTER_01_LIVE_UI_TRAVERSAL beats=17 interactions=6/u,
        "Automated suites log has no NON_SHIPPING_LIVE_TEST traversal PASS");
      break;
    }
    case "FIXTURE_DETERMINISM": {
      assertExactKeys(receipt, [
        ...commonReceiptKeys,
        "firstBuildSHA256",
        "secondBuildSHA256",
        "trustReceiptSHA256",
        "byteIdentical",
        "signatureVerified",
        "trustBoundaryUnchanged",
        "ordinaryReleaseRejectsReviewResources",
      ], "Fixture determinism receipt");
      assert.match(receipt.firstBuildSHA256, sha256Pattern);
      assert.equal(receipt.secondBuildSHA256, receipt.firstBuildSHA256,
        "Repeated fixture builds are not byte-identical");
      assert.equal(
        await chapter01ReviewFixtureTreeSHA256(repositoryRoot, gate.sources.runtimeFixture),
        receipt.secondBuildSHA256,
        "Fixture determinism receipt does not bind the current signed fixture tree",
      );
      assert.match(receipt.trustReceiptSHA256, sha256Pattern);
      assert.equal(
        sha256(await readRegularBytes(
          repositoryRoot, gate.sources.trustReceipt, "Chapter 01 fixture trust receipt",
        )),
        receipt.trustReceiptSHA256,
        "Fixture determinism receipt does not bind the current trust receipt",
      );
      assert.equal(receipt.byteIdentical, true);
      assert.equal(receipt.signatureVerified, true);
      assert.equal(receipt.trustBoundaryUnchanged, true);
      assert.equal(receipt.ordinaryReleaseRejectsReviewResources, true);
      break;
    }
    case "SIMULATOR_TRAVERSAL": {
      assertExactKeys(receipt, [
        ...commonReceiptKeys,
        "operationMode",
        "device",
        "directLaunchBeatID",
        "finalBeatID",
        "completedCounts",
        "fullTraversalCompleted",
        "deliberateEntryAction",
        "authoredSoundStartedAfterEntry",
        "soundControlStayedVisible",
        "playingControlLabel",
        "mutePausedAuthoredSound",
        "mutedControlLabel",
        "unmuteResumedAuthoredSound",
        "interruptionControlLabel",
        "interruptionRestartedSoundSpontaneously",
        "coldRestoreControlLabel",
        "coldRestoreRestartedSoundSpontaneously",
        "accountSurfaceShown",
        "purchaseSurfaceShown",
        "debugControlsShown",
        "visibleReviewMarksShown",
        "artifacts",
      ], "Simulator traversal receipt");
      assertExactKeys(receipt.device, ["platform", "model", "osVersion"],
        "Simulator traversal device");
      assertExactKeys(receipt.completedCounts, [
        "arcs", "beats", "interactions", "worlds", "narrationCues", "audioTimelines",
      ], "Simulator traversal counts");
      assert.equal(receipt.device?.platform, "iOS Simulator");
      assert.equal(receipt.device?.model, "iPhone 17 Pro");
      assert.ok(versionAtLeast(receipt.device?.osVersion, "26.4"));
      assert.equal(receipt.operationMode, "CODEX_COMPUTER_USE",
        "The required simulator round must be operated outside XCTest");
      assert.equal(receipt.directLaunchBeatID, beatIDs[0]);
      assert.equal(receipt.finalBeatID, beatIDs.at(-1));
      assert.deepEqual(receipt.completedCounts, {
        arcs: 3, beats: 17, interactions: 6, worlds: 6, narrationCues: 37, audioTimelines: 47,
      });
      assert.equal(receipt.fullTraversalCompleted, true);
      assert.equal(receipt.deliberateEntryAction, "Begin",
        "Fresh Chapter 01 traversal must use the deliberate Begin entry");
      assert.equal(receipt.authoredSoundStartedAfterEntry, true,
        "Deliberate Chapter 01 entry did not start authored sound");
      assert.equal(receipt.soundControlStayedVisible, true,
        "The fixed chapter sound control was not continuously available");
      assert.equal(receipt.playingControlLabel, "Turn sound off");
      assert.equal(receipt.mutePausedAuthoredSound, true,
        "Mute did not pause the authored sound transport");
      assert.equal(receipt.mutedControlLabel, "Turn sound on");
      assert.equal(receipt.unmuteResumedAuthoredSound, true,
        "Unmute did not resume the authored sound transport");
      assert.equal(receipt.interruptionControlLabel, "Resume sound");
      assert.equal(receipt.interruptionRestartedSoundSpontaneously, false,
        "Sound restarted without an explicit action after interruption");
      assert.equal(receipt.coldRestoreControlLabel, "Resume sound");
      assert.equal(receipt.coldRestoreRestartedSoundSpontaneously, false,
        "Sound restarted without an explicit action after cold restore");
      assert.equal(receipt.accountSurfaceShown, false);
      assert.equal(receipt.purchaseSurfaceShown, false);
      assert.equal(receipt.debugControlsShown, false);
      assert.equal(receipt.visibleReviewMarksShown, false);
      const artifacts = await validateEvidenceArtifacts({
        repositoryRoot,
        artifacts: receipt.artifacts,
        expectedRoles: ["manual-traversal-log", "manual-traversal-recording"],
        description: "Simulator traversal",
      });
      const traversalLog = artifacts.get("manual-traversal-log").toString("utf8");
      const marker = traversalLog.match(/^CHAPTER_01_MANUAL_TRAVERSAL=(\{.*\})$/mu);
      assert.ok(marker, "Manual traversal log has no structured Chapter 01 marker");
      const measured = JSON.parse(marker[1]);
      assert.equal(measured.operationMode, receipt.operationMode);
      assert.deepEqual(measured.beatIDs, beatIDs,
        "Manual traversal log does not contain all 17 beats in order");
      assert.deepEqual(measured.interactionIDs, interactionIDs,
        "Manual traversal log does not contain all six interactions in order");
      assert.equal(measured.finalRoute, "world",
        "Manual traversal log did not exit Chapter 01 to the world");
      for (const key of [
        "deliberateEntryAction",
        "authoredSoundStartedAfterEntry",
        "soundControlStayedVisible",
        "playingControlLabel",
        "mutePausedAuthoredSound",
        "mutedControlLabel",
        "unmuteResumedAuthoredSound",
        "interruptionControlLabel",
        "interruptionRestartedSoundSpontaneously",
        "coldRestoreControlLabel",
        "coldRestoreRestartedSoundSpontaneously",
      ]) {
        assert.deepEqual(measured[key], receipt[key],
          `Manual traversal log does not bind ${key}`);
      }
      break;
    }
    case "INTERACTION_RECORDINGS": {
      assertExactKeys(receipt, [...commonReceiptKeys, "recordings"],
        "Interaction recordings receipt");
      assert.deepEqual(receipt.recordings?.map(({ interactionID }) => interactionID), interactionIDs,
        "Simulator recordings must cover the six canonical interactions in order");
      for (const recording of receipt.recordings) {
        assertExactKeys(recording, ["interactionID", "completed", "artifact"],
          `${recording.interactionID} simulator recording`);
        assert.equal(recording.completed, true, `${recording.interactionID}: recording is incomplete`);
        await validateArtifactBinding(
          repositoryRoot,
          recording.artifact,
          `${recording.interactionID} simulator recording`,
          "native/quality/chapter-01-review/evidence/recordings/",
        );
      }
      break;
    }
    case "RESTORE_MATRIX": {
      assertExactKeys(receipt, [
        ...commonReceiptKeys,
        "beatEntry",
        "beatExit",
        "midInteraction",
        "coldReturnStartsPaused",
        "loopCursorPreserved",
        "finalStateSHA256",
        "artifacts",
      ], "Restore matrix receipt");
      receipt.beatEntry?.forEach((item) => assertExactKeys(
        item, ["beatID", "passed"], `${item.beatID} entry restore`,
      ));
      receipt.beatExit?.forEach((item) => assertExactKeys(
        item, ["beatID", "passed"], `${item.beatID} exit restore`,
      ));
      receipt.midInteraction?.forEach((item) => assertExactKeys(
        item, ["interactionID", "passed"], `${item.interactionID} mid-state restore`,
      ));
      assert.deepEqual(receipt.beatEntry?.map(({ beatID }) => beatID), beatIDs,
        "Restore evidence must cover entry to all 17 beats");
      assert.deepEqual(receipt.beatExit?.map(({ beatID }) => beatID), beatIDs,
        "Restore evidence must cover exit from all 17 beats");
      assert.ok(receipt.beatEntry.every(({ passed }) => passed === true)
        && receipt.beatExit.every(({ passed }) => passed === true),
      "Every beat entry and exit restore must pass");
      assert.deepEqual(receipt.midInteraction?.map(({ interactionID }) => interactionID), interactionIDs,
        "Restore evidence must cover all six interactions mid-state");
      assert.ok(receipt.midInteraction.every(({ passed }) => passed === true),
        "Every mid-interaction restore must pass");
      assert.equal(receipt.coldReturnStartsPaused, true);
      assert.equal(receipt.loopCursorPreserved, true);
      assert.match(receipt.finalStateSHA256, sha256Pattern,
        "Restore evidence must bind the observed final state");
      const artifacts = await validateEvidenceArtifacts({
        repositoryRoot,
        artifacts: receipt.artifacts,
        expectedRoles: ["restore-matrix-log"],
        description: "Restore matrix",
      });
      const restoreLog = artifacts.get("restore-matrix-log").toString("utf8");
      const marker = restoreLog.match(/^CHAPTER_01_RESTORE_MATRIX=(\{.*\})$/mu);
      assert.ok(marker, "Restore matrix log has no structured Chapter 01 marker");
      const measured = JSON.parse(marker[1]);
      assert.equal(measured.finalStateSHA256, receipt.finalStateSHA256,
        "Restore receipt final hash differs from its bound log");
      assert.deepEqual(
        measured.checkpoints.filter(({ phase }) => phase === "entry").map(({ beatID }) => beatID),
        beatIDs,
        "Restore log does not contain all 17 beat entries",
      );
      assert.deepEqual(
        measured.checkpoints.filter(({ phase }) => phase === "exit").map(({ beatID }) => beatID),
        beatIDs,
        "Restore log does not contain all 17 beat exits",
      );
      assert.deepEqual(
        measured.checkpoints.filter(({ phase }) => phase === "mid-interaction")
          .map(({ interactionID }) => interactionID),
        interactionIDs,
        "Restore log does not contain all six interaction midpoints",
      );
      break;
    }
    case "AUDIO_RESTORE": {
      assertExactKeys(receipt, [
        ...commonReceiptKeys,
        "sampleRate",
        "controlledPauseSampleDelta",
        "rapidTraceMaximumCursorWriteMilliseconds",
        "hardKillMaximumCursorWriteMilliseconds",
        "sameProcessBackgroundPreservesActivePhase",
        "coldRestorePhaseNormalization",
        "coldReturnStartsPaused",
        "loopCursorPreserved",
        "silenceSurvivesChapterLifecycle",
        "silenceLeaksAcrossChapters",
        "artifacts",
      ], "Audio restore receipt");
      assert.equal(receipt.sampleRate, 48_000);
      assert.equal(receipt.controlledPauseSampleDelta, 0,
        "Controlled audio pause must be sample-exact");
      assert.ok(receipt.rapidTraceMaximumCursorWriteMilliseconds <= 250,
        "Rapid Trace cursor persistence exceeded 250 ms");
      assert.ok(receipt.hardKillMaximumCursorWriteMilliseconds <= 250,
        "Hard-kill cursor persistence exceeded 250 ms");
      assert.equal(receipt.sameProcessBackgroundPreservesActivePhase, true);
      assert.deepEqual(receipt.coldRestorePhaseNormalization, {
        engaged: "waiting",
        resistance: "waiting",
      });
      assert.equal(receipt.coldReturnStartsPaused, true);
      assert.equal(receipt.loopCursorPreserved, true);
      assert.equal(receipt.silenceSurvivesChapterLifecycle, true);
      assert.equal(receipt.silenceLeaksAcrossChapters, false);
      const artifacts = await validateEvidenceArtifacts({
        repositoryRoot,
        artifacts: receipt.artifacts,
        expectedRoles: ["audio-restore-log"],
        description: "Audio restore",
      });
      const audioLog = artifacts.get("audio-restore-log").toString("utf8");
      for (const testName of [
        "testPeriodicCursorWritesContinueWhileMainActorIsBusy",
        "testPauseQuiescesRenderThreadBeforeReadingFinalCursor",
        "testSilenceContinuesAcrossEverySameChapterBinding",
        "testColdRestoredActiveSessionRequiresExplicitResume",
        "testAllSixResponsiveProgramsColdRestoreTheirExactLoopPositionPaused",
      ]) {
        assert.match(audioLog, new RegExp(`${testName}.*passed`, "u"),
          `Audio restore log has no PASS for ${testName}`);
      }
      break;
    }
    case "ACCESSIBILITY": {
      assertExactKeys(receipt, [
        ...commonReceiptKeys,
        "minimumTouchTargetPoints",
        "touchFinalStateSHA256",
        "voiceOverFinalStateSHA256",
        "reduceMotionFinalStateSHA256",
        "interactionIDs",
        "systemVoiceOverRunCompleted",
        "systemReduceMotionRunCompleted",
        "systemDynamicTypeRunCompleted",
        "systemIncreasedContrastRunCompleted",
        "simulatorSettingsRestored",
        "dynamicTypeHidesRequiredInformation",
        "dynamicTypeHidesRequiredActions",
        "increasedContrastHidesRequiredInformation",
        "increasedContrastHidesRequiredActions",
        "artifacts",
      ], "Accessibility receipt");
      assert.ok(receipt.minimumTouchTargetPoints >= 44);
      assert.match(receipt.touchFinalStateSHA256, sha256Pattern);
      assert.equal(receipt.voiceOverFinalStateSHA256, receipt.touchFinalStateSHA256,
        "VoiceOver and touch do not reach the same historical result");
      assert.equal(receipt.reduceMotionFinalStateSHA256, receipt.touchFinalStateSHA256,
        "Reduce Motion does not reach the same historical result");
      assert.deepEqual(receipt.interactionIDs, interactionIDs,
        "Accessibility evidence does not cover all interactions");
      assert.equal(receipt.systemVoiceOverRunCompleted, true);
      assert.equal(receipt.systemReduceMotionRunCompleted, true);
      assert.equal(receipt.systemDynamicTypeRunCompleted, true);
      assert.equal(receipt.systemIncreasedContrastRunCompleted, true);
      assert.equal(receipt.simulatorSettingsRestored, true);
      assert.equal(receipt.dynamicTypeHidesRequiredInformation, false);
      assert.equal(receipt.dynamicTypeHidesRequiredActions, false);
      assert.equal(receipt.increasedContrastHidesRequiredInformation, false);
      assert.equal(receipt.increasedContrastHidesRequiredActions, false);
      const artifacts = await validateEvidenceArtifacts({
        repositoryRoot,
        artifacts: receipt.artifacts,
        expectedRoles: ["system-accessibility-log", "system-voiceover-recording"],
        description: "Accessibility",
      });
      const accessibilityLog = artifacts.get("system-accessibility-log").toString("utf8");
      const marker = accessibilityLog.match(
        /^CHAPTER_01_SYSTEM_ACCESSIBILITY=(\{.*\})$/mu,
      );
      assert.ok(marker, "Accessibility log has no structured system-settings marker");
      const measured = JSON.parse(marker[1]);
      assert.equal(measured.touchFinalStateSHA256, receipt.touchFinalStateSHA256);
      assert.equal(measured.voiceOverFinalStateSHA256, receipt.voiceOverFinalStateSHA256);
      assert.equal(measured.reduceMotionFinalStateSHA256, receipt.reduceMotionFinalStateSHA256);
      assert.equal(measured.systemVoiceOverRunCompleted, true);
      assert.equal(measured.systemReduceMotionRunCompleted, true);
      assert.equal(measured.systemDynamicTypeRunCompleted, true);
      assert.equal(measured.systemIncreasedContrastRunCompleted, true);
      assert.equal(measured.simulatorSettingsRestored, true);
      break;
    }
    case "OFFLINE": {
      assertExactKeys(receipt, [
        ...commonReceiptKeys,
        "networkDeniedAfterInstall",
        "fullTraversalCompleted",
        "restoreCompleted",
        "assetsLoadedFromInstalledPackageOnly",
        "networkRequestsObserved",
        "networkCondition",
        "networkObservationMethods",
        "simulatorNetworkSettingsRestored",
        "artifacts",
      ], "Offline receipt");
      assert.equal(receipt.networkDeniedAfterInstall, true);
      assert.equal(receipt.fullTraversalCompleted, true);
      assert.equal(receipt.restoreCompleted, true);
      assert.equal(receipt.assetsLoadedFromInstalledPackageOnly, true);
      assert.equal(receipt.networkRequestsObserved, 0);
      assert.equal(receipt.networkCondition, "100_PERCENT_PACKET_LOSS");
      assert.deepEqual(receipt.networkObservationMethods, [
        "NETTOP_EXTERNAL_SOCKET_SAMPLING",
        "CFNETWORK_DIAGNOSTICS_UNIFIED_LOG",
        "COMPILED_NON_SHIPPING_APPLE_SERVICE_BYPASS",
      ]);
      assert.equal(receipt.simulatorNetworkSettingsRestored, true);
      const artifacts = await validateEvidenceArtifacts({
        repositoryRoot,
        artifacts: receipt.artifacts,
        expectedRoles: ["network-denial-log", "offline-traversal-recording"],
        description: "Offline",
      });
      const offlineLog = artifacts.get("network-denial-log").toString("utf8");
      const marker = offlineLog.match(/^CHAPTER_01_OFFLINE=(\{.*\})$/mu);
      assert.ok(marker, "Offline log has no structured network-denial marker");
      const measured = JSON.parse(marker[1]);
      assert.equal(measured.networkCondition, receipt.networkCondition);
      assert.deepEqual(
        measured.networkObservationMethods,
        receipt.networkObservationMethods,
      );
      assert.equal(measured.networkRequestsObserved, 0);
      assert.equal(measured.fullTraversalCompleted, true);
      assert.equal(measured.restoreCompleted, true);
      assert.equal(measured.assetsLoadedFromInstalledPackageOnly, true);
      assert.equal(measured.simulatorNetworkSettingsRestored, true);
      break;
    }
    default:
      assert.fail(`${evidence.id}: unsupported Chapter 01 evidence type`);
  }
}

export function resolveChapter01ReviewGateStatus({ gateStatus, blockers, requirePass = false }) {
  assert.ok(["CANDIDATE", "PASS"].includes(gateStatus), "Gate status is invalid");
  assert.ok(Array.isArray(blockers) && blockers.every((blocker) =>
    typeof blocker === "string" && blocker.length > 0),
  "Chapter 01 gate blockers must be non-empty strings");
  const evidenceComplete = blockers.length === 0;
  const eligibleStatus = evidenceComplete ? "PASS" : "CANDIDATE";
  if (gateStatus === "PASS" && !evidenceComplete) {
    assert.fail(`CHAPTER_01_REVIEW_READY cannot declare PASS: ${blockers.join("; ")}`);
  }
  if (requirePass && (gateStatus !== "PASS" || !evidenceComplete)) {
    assert.fail(`CHAPTER_01_REVIEW_READY remains CANDIDATE: ${blockers.join("; ")}`);
  }
  return eligibleStatus;
}

export async function evaluateChapter01ReviewReady({
  repositoryRoot,
  gate: suppliedGate,
  requirePass = false,
} = {}) {
  assert.ok(repositoryRoot, "Chapter 01 review gate requires the repository root");
  const root = path.resolve(repositoryRoot);
  const gate = suppliedGate ?? (await readRegularJSON(
    root, gateRelativePath, "Chapter 01 review gate",
  )).value;
  validateChapter01ReviewGateDocument(gate);

  const draft = await validateFirstFarmersDraft({ repositoryRoot: root });
  await validateFirstFarmersClaimRegister({ repositoryRoot: root });
  const freeze = await validateChapter01ReviewTextFreeze({ repositoryRoot: root });
  const matrix = await validateChapter01ReviewMatrix({ repositoryRoot: root });
  const payload = (await readRegularJSON(
    root, gate.sources.contentPackage, "Chapter 01 generated content package",
  )).value;
  validateSourcePayload({ gate, draft, freeze, matrix, payload });
  await validateLaunchAndReleaseBoundary({ repositoryRoot: root, gate });
  await validateReceiptTemplates({ repositoryRoot: root, gate });

  const blockers = [];
  const narration = await validateNarrationManifest({
    repositoryRoot: root, gate, freeze,
  });
  if (narration.blocker) blockers.push(narration.blocker);
  const transitionBlocker = await validateTransitionManifest({ repositoryRoot: root, gate });
  if (transitionBlocker) blockers.push(transitionBlocker);
  const fixtureBlocker = await validateRuntimeFixture({
    repositoryRoot: root,
    gate,
    narrationManifest: narration.manifest,
  });
  if (fixtureBlocker) blockers.push(fixtureBlocker);

  for (const evidence of gate.requiredEvidence) {
    const loaded = await readOptionalRegularJSON(
      root, evidence.path, `${evidence.id} Chapter 01 evidence`,
    );
    if (!loaded) {
      blockers.push(`${evidence.id}: missing PASS receipt`);
      continue;
    }
    try {
      await validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: root,
        gate,
        evidence,
        receipt: loaded.value,
      });
    } catch (error) {
      blockers.push(`${evidence.id}: ${error.message}`);
    }
  }

  const eligibleStatus = resolveChapter01ReviewGateStatus({
    gateStatus: gate.status,
    blockers,
    requirePass,
  });
  return {
    schemaVersion: 1,
    gateID: gate.gateID,
    milestone: gate.milestone,
    status: gate.status,
    eligibleStatus,
    shippingState: gate.shippingState,
    subjectSHA256: await chapter01ReviewSubjectSHA256(root, gate),
    counts: gate.expectedCounts,
    automatedSourceChecks: [
      "approved chapter contract and F1-F7/editorial regression",
      "3 canonical arcs / 17 beats / 6 interactions",
      "6 backstage review worlds / 17 unique scene restore anchors",
      "baseline and largest portrait crops in both motion modes for all runtime scenes",
      "37 frozen narration cue IDs and text hashes",
      "17 main plus 30 responsive audio timelines",
      "3 review-only world transitions inside the 17 main timelines",
      "44-point touch geometry and VoiceOver/Reduce Motion contracts",
      "offline-only package references and event-driven haptics",
      "NON_SHIPPING_LIVE_TEST direct Chapter 01 launch",
      "ordinary Release exclusion and rejection boundary",
    ],
    deferredOutsideMilestone: [
      "owned-iPhone editorial traversal and six mid-interaction restores when Basta 16 is available",
      "formal battery, thermal and performance certification",
      "production image masters, production voice and shipping package approval",
    ],
    blockers,
  };
}

if (process.argv[1]
    && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  const requirePass = process.argv.slice(2).includes("--require-pass");
  const json = process.argv.slice(2).includes("--json");
  const repositoryRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
  const report = await evaluateChapter01ReviewReady({ repositoryRoot, requirePass });
  if (json) {
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  } else {
    process.stdout.write(
      `${report.milestone}: ${report.status}; ${report.blockers.length} open blocker(s).\n`,
    );
    for (const blocker of report.blockers) process.stdout.write(`- ${blocker}\n`);
  }
}
